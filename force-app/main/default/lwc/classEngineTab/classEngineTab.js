import { LightningElement, track } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import getPage from '@salesforce/apex/ClassEngineController.getPage';
import saveProductRatings from '@salesforce/apex/ClassEngineController.saveProductRatings';
import classify from '@salesforce/apex/ClassEngineController.classify';
import saveChosenClasses from '@salesforce/apex/ClassEngineController.saveChosenClasses';
import submitCycle from '@salesforce/apex/ClassEngineController.submitCycle';
import approveCycle from '@salesforce/apex/ClassEngineController.approveCycle';
import rejectCycle from '@salesforce/apex/ClassEngineController.rejectCycle';
import { resolveAccountListKind } from 'c/plannerMapPins';
import { accountTypeIconUrl } from 'c/accountTypeTheme';
import { isFieldFeatureEnabled, loadFieldFeatures } from 'c/fieldFeatureFlags';

const VIEW_CYCLE = 'cycle';
const MONTH_DRAFT_SEPARATOR = '|';
const VIEW_TARGET_LIST = 'targetList';

export default class ClassEngineTab extends LightningElement {
    @track page;
    @track accounts = [];
    @track months = [];
    @track isLoading = false;
    @track showPromoModal = false;
    @track showInfoModal = false;
    @track searchTerm = '';
    @track specialtyFilter = 'All';
    @track selectedEmployeeId;
    @track selectedTerritoryId;
    @track quarter;
    @track livePreviewActive = false;
    @track view = VIEW_CYCLE;
    @track brokenProductImages = {};
    @track brokenPromoImages = {};
    featureEnabled = true;
    featuresReady = false;

    expandedIds = new Set();
    chosenDraft = new Map();
    frequencyDraft = new Map();
    classifyTimer;
    saveTimers = {};

    connectedCallback() {
        this.quarter = this.defaultQuarter();
        void this.bootstrapWithFeatures();
    }

    get showDisabledState() {
        return this.featuresReady && this.featureEnabled !== true;
    }

    get showEngine() {
        return this.featuresReady && this.featureEnabled === true;
    }

    async bootstrapWithFeatures() {
        await loadFieldFeatures();
        this.featureEnabled = isFieldFeatureEnabled('classEngine');
        this.featuresReady = true;
        if (this.featureEnabled) {
            this.refresh();
        }
    }

    disconnectedCallback() {
        if (this.classifyTimer) {
            clearTimeout(this.classifyTimer);
        }
        Object.keys(this.saveTimers).forEach((key) => clearTimeout(this.saveTimers[key]));
    }

    defaultQuarter() {
        const now = new Date();
        const q = Math.floor(now.getMonth() / 3) + 1;
        return `Q${q}-${now.getFullYear()}`;
    }

    get quarterOptions() {
        const year = new Date().getFullYear();
        const options = [];
        for (let y = year - 1; y <= year + 1; y += 1) {
            for (let q = 1; q <= 4; q += 1) {
                const value = `Q${q}-${y}`;
                options.push({ label: value, value });
            }
        }
        if (this.quarter && !options.some((option) => option.value === this.quarter)) {
            options.push({ label: this.quarter, value: this.quarter });
        }
        return options;
    }

    get emptyAccountsMessage() {
        if (!this.page?.territoryId) {
            return 'You are not assigned to a territory. Use the Territory utility or ask an admin to assign one, then refresh.';
        }
        return 'No Account Territory Fields found for this territory.';
    }

    get isBusy() {
        return this.isLoading;
    }

    get canEdit() {
        return (
            !this.isReviewingOther &&
            (this.cycleStatus === 'Draft' || this.cycleStatus === 'Rejected')
        );
    }

    get ratingDisabled() {
        return this.isBusy || !this.canEdit;
    }

    get canOverrideClass() {
        return this.canApprove && this.page?.canOverrideClass === true;
    }

    /** Rep suggests exceptions while drafting; the DM approves, edits or sets them in review. */
    get frequencyEditable() {
        return this.canEdit || this.canApprove;
    }

    get classifyDisabled() {
        return this.isBusy || !this.canEdit || !this.page?.promoGrid;
    }

    get submitDisabled() {
        return this.isBusy || !this.canSubmit;
    }

    get promoModalDisabled() {
        return this.isBusy || !this.page;
    }

    get cycleStatus() {
        return this.page?.cycle?.status || 'Draft';
    }

    get statusChipClass() {
        const status = (this.cycleStatus || 'Draft').toLowerCase();
        return `ce-chip status status-${status}`;
    }

    get canSubmit() {
        return this.canEdit && (this.accounts || []).some((row) => row.rxClass);
    }

    get canApprove() {
        return this.isReviewingOther && this.cycleStatus === 'Submitted' && Boolean(this.page?.cycle?.id);
    }

    get isReviewingOther() {
        return this.page?.viewerMode === 'manager';
    }

    get isReviewingRep() {
        return this.isReviewingOther;
    }

    /** Managers see a "Class cycle | Team target list" switch (QA B3-01..B3-04). */
    get hasTeam() {
        return this.navigatorTerritories.some((row) => row.label !== 'My territory');
    }

    get isTargetListView() {
        return this.hasTeam && this.view === VIEW_TARGET_LIST;
    }

    get isCycleViewPressed() {
        return String(!this.isTargetListView);
    }

    get isTargetListViewPressed() {
        return String(this.isTargetListView);
    }

    get cycleViewClass() {
        return this.isTargetListView ? 'ce-view-btn' : 'ce-view-btn ce-view-btn--active';
    }

    get targetListViewClass() {
        return this.isTargetListView ? 'ce-view-btn ce-view-btn--active' : 'ce-view-btn';
    }

    /** Opens the target list on the rep being reviewed in the cycle, if any. */
    get teamRepId() {
        return this.isReviewingOther ? this.page?.employeeId : undefined;
    }

    handleShowCycle() {
        this.view = VIEW_CYCLE;
    }

    handleShowTargetList() {
        this.view = VIEW_TARGET_LIST;
    }

    get reviewTerritories() {
        return this.page?.reviewTerritories || [];
    }

    get navigatorTerritories() {
        const rows = this.reviewTerritories || [];
        const assigned = rows.filter((row) => row.assigned === true || row.employeeName === 'You');
        const ownIds = new Set(assigned.map((row) => row.territoryId));
        const subordinates = rows.filter((row) => row.territoryId && !ownIds.has(row.territoryId));
        const items = [];
        const currentAssigned = assigned.find((row) => row.territoryId === this.selectedTerritoryId);
        const mine = currentAssigned || assigned[0];
        if (mine?.territoryId) {
            items.push({
                territoryId: mine.territoryId,
                label: 'My territory',
                pendingCount: 0
            });
        }
        subordinates.forEach((row) => {
            const who = row.employeeName || 'Unassigned';
            const pending = row.pendingCount ? ` · ${row.pendingCount}` : '';
            items.push({
                territoryId: row.territoryId,
                label: `${row.name} — ${who}${pending}`,
                pendingCount: row.pendingCount || 0
            });
        });
        return items;
    }

    get showTerritoryNav() {
        return this.navigatorTerritories.length > 1;
    }

    get territoryIndex() {
        const current = this.territoryPickerValue;
        const index = this.navigatorTerritories.findIndex((row) => row.territoryId === current);
        return index < 0 ? 0 : index;
    }

    get territoryPositionLabel() {
        const total = this.navigatorTerritories.length;
        if (!total) {
            return '';
        }
        return `${this.territoryIndex + 1} / ${total}`;
    }

    get prevTerritoryDisabled() {
        return this.isBusy || this.territoryIndex <= 0;
    }

    get nextTerritoryDisabled() {
        return this.isBusy || this.territoryIndex >= this.navigatorTerritories.length - 1;
    }

    get territoryPickerValue() {
        const items = this.navigatorTerritories;
        if (items.some((row) => row.territoryId === this.selectedTerritoryId)) {
            return this.selectedTerritoryId;
        }
        return items[0]?.territoryId || this.selectedTerritoryId;
    }

    get territoryOptions() {
        const current = this.territoryPickerValue;
        return this.navigatorTerritories.map((row) => ({
            label: row.label,
            value: row.territoryId,
            selected: row.territoryId === current
        }));
    }

    get quarterMenuOptions() {
        return this.quarterOptions.map((option) => ({
            ...option,
            selected: option.value === this.quarter
        }));
    }

    get teamPendingTotal() {
        const seen = new Set();
        return this.reviewTerritories.reduce((sum, row) => {
            if (!row.employeeId || seen.has(row.employeeId)) {
                return sum;
            }
            seen.add(row.employeeId);
            return sum + (row.pendingCount || 0);
        }, 0);
    }

    get teamPendingLabel() {
        const total = this.teamPendingTotal;
        return `${total} plan${total === 1 ? '' : 's'} awaiting your approval`;
    }

    get reviewHint() {
        const territory = this.page?.territoryName || 'This territory';
        const name = this.page?.employeeName || 'the owner';
        if (!this.isReviewingOther) {
            return `${territory} is yours. Classify it and submit the ${this.quarter} plan for approval.`;
        }
        if (this.cycleStatus === 'Submitted') {
            const pending = (this.accounts || []).filter(
                (row) => row.suggestedFrequency != null && !row.frequencyReviewed
            ).length;
            const exceptions = pending
                ? ` ${pending} frequency exception${pending === 1 ? '' : 's'} suggested — clear any you decline.`
                : '';
            return `Reviewing ${name} · ${territory}. Approve the ${this.quarter} plan, or reject it.${exceptions}`;
        }
        if (this.cycleStatus === 'Approved') {
            return `${name}'s ${this.quarter} plan for ${territory} is approved.`;
        }
        return `${name} has not submitted a ${this.quarter} plan for ${territory} yet (${this.cycleStatus}).`;
    }

    get specialtyOptions() {
        const set = new Set();
        (this.page?.accounts || []).forEach((row) => {
            if (row.specialty) {
                set.add(row.specialty);
            }
        });
        return [
            { label: 'All specialties', value: 'All' },
            ...Array.from(set)
                .sort()
                .map((value) => ({ label: value, value }))
        ];
    }

    get specialtyMenuOptions() {
        return this.specialtyOptions.map((option) => ({
            ...option,
            selected: option.value === this.specialtyFilter
        }));
    }

    get filteredAccounts() {
        const term = (this.searchTerm || '').trim().toLowerCase();
        return (this.accounts || []).filter((row) => {
            if (this.specialtyFilter !== 'All' && row.specialty !== this.specialtyFilter) {
                return false;
            }
            if (!term) {
                return true;
            }
            return (
                (row.accountName || '').toLowerCase().includes(term) ||
                (row.specialty || '').toLowerCase().includes(term) ||
                (row.rxClass || '').toLowerCase().includes(term)
            );
        });
    }

    get hasAccounts() {
        return this.filteredAccounts.length > 0;
    }

    get accountCountLabel() {
        const shown = this.filteredAccounts.length;
        const total = (this.accounts || []).length;
        if (shown === total) {
            return `${total} account${total === 1 ? '' : 's'}`;
        }
        return `${shown} of ${total} accounts`;
    }

    get promoGrid() {
        return this.page?.promoGrid;
    }

    get promoProductRows() {
        return (this.promoGrid?.productWeights || [])
            .filter((row) => row.weightPercentage != null && Number(row.weightPercentage) > 0)
            .slice()
            .sort((a, b) => Number(b.weightPercentage) - Number(a.weightPercentage));
    }

    get promoProductIdSet() {
        const ids = new Set();
        this.promoProductRows.forEach((row) => {
            if (row.product2Id) {
                ids.add(row.product2Id);
            }
        });
        return ids;
    }

    get promoProductCards() {
        return this.promoProductRows.map((row) => {
            const weight = Number(row.weightPercentage) || 0;
            const broken = this.brokenPromoImages[row.id];
            return {
                ...row,
                weightLabel: String(weight),
                hasImage: Boolean(row.imageUrl) && !broken,
                initials: this.initialsFrom(row.productName),
                barStyle: `width:${Math.min(100, Math.max(0, weight))}%;`,
                ringStyle: `--pct:${Math.min(100, Math.max(0, weight))}%;`
            };
        });
    }

    get specialtyCards() {
        return (this.promoGrid?.specialtyFocus || []).map((row) => {
            const pct = Number(row.listPercentage) || 0;
            return { ...row, barStyle: `width:${Math.min(100, Math.max(0, pct))}%;` };
        });
    }

    get classCards() {
        return (this.promoGrid?.classTargeting || []).map((row) => {
            const pct = Number(row.listPercentage) || 0;
            return { ...row, barStyle: `width:${Math.min(100, Math.max(0, pct))}%;` };
        });
    }

    get specialtyTotalLabel() {
        return `${Number(this.promoGrid?.specialtyFocusTotal) || 0}% total`;
    }

    get classTotalLabel() {
        return `${Number(this.promoGrid?.classTargetingTotal) || 0}% total`;
    }

    get promoModalTitle() {
        return this.promoGrid?.lineName || this.page?.lineTerritoryName || 'Promo Grid';
    }

    get promoModalSubtitle() {
        const products = this.promoProductRows.length;
        const specialties = (this.promoGrid?.specialtyFocus || []).length;
        const classes = (this.promoGrid?.classTargeting || []).length;
        return `${products} brands · ${specialties} specialties · ${classes} class targets`;
    }

    get scopeNote() {
        return this.page?.scopeNote || null;
    }

    get pendingCycles() {
        return this.page?.pendingCycles || [];
    }

    get hasPending() {
        return this.pendingCycles.length > 0;
    }

    get hasCapacityMonths() {
        return (this.months || []).length > 0;
    }

    get capacityCards() {
        return (this.months || []).map((month, index) => {
            const planned = (Number(month.plannedVisits) || 0) + this.exceptionDelta(month);
            const capacity = Number(month.capacityVisits) || 0;
            const pct = capacity > 0 ? Math.min(100, Math.round((planned / capacity) * 100)) : 0;
            const label = month.monthStart
                ? new Date(month.monthStart).toLocaleDateString(undefined, {
                      month: 'short',
                      year: 'numeric'
                  })
                : `Month ${index + 1}`;
            return {
                key: `${month.monthStart || index}`,
                label,
                ratio: `${planned} / ${capacity}`,
                pctLabel: `${pct}%`,
                sub: `${month.workingDays || 0} working · ${month.holidayDays || 0} holiday · ${month.leaveDays || 0} leave`,
                ringStyle: `--pct:${pct};`
            };
        });
    }

    /** Extra (or fewer) monthly visits from frequency exceptions versus the class frequency. */
    exceptionDelta(month) {
        const applied = month?.appliedVisitsByClass || {};
        let delta = 0;
        (this.accounts || []).forEach((row) => {
            const exception = this.effectiveException(row, month?.monthStart);
            if (exception == null) {
                return;
            }
            const classCode = row.chosenClass || row.rxClass;
            const base = Number(applied[classCode] ?? row.gridFrequency) || 0;
            delta += exception - base;
        });
        return delta;
    }

    monthDraftKey(accountId, monthStart) {
        return `${accountId}${MONTH_DRAFT_SEPARATOR}${monthStart}`;
    }

    /** The row's per-month exceptions: {"yyyy-MM-dd": {s: suggested, a: approved, r: reviewed}}. */
    monthlyEntries(row) {
        if (!row?.monthlyFrequencies) {
            return {};
        }
        try {
            return JSON.parse(row.monthlyFrequencies) || {};
        } catch {
            return {};
        }
    }

    /**
     * The month's state: suggested (rep), approved (manager), reviewed. A month without its own entry
     * uses the cycle-wide exception from before per-month exceptions.
     */
    monthState(row, monthStart) {
        const entry = this.monthlyEntries(row)[monthStart];
        if (entry) {
            return { suggested: entry.s ?? null, approved: entry.a ?? null, reviewed: entry.r === true };
        }
        return {
            suggested: row.suggestedFrequency ?? null,
            approved: row.approvedFrequency ?? null,
            reviewed: row.frequencyReviewed === true
        };
    }

    /** The exception that would apply on approve for the month: draft, then manager decision, then rep suggestion. */
    effectiveException(row, monthStart) {
        const key = this.monthDraftKey(row.accountId, monthStart);
        if (this.frequencyDraft.has(key)) {
            return this.frequencyDraft.get(key);
        }
        const state = this.monthState(row, monthStart);
        return state.reviewed ? state.approved : state.suggested;
    }

    /** The cycle's months; before the first classify there are none yet, so use the quarter's three. */
    get cycleMonths() {
        if (this.months && this.months.length) {
            return this.months;
        }
        const match = /^Q([1-4])-(\d{4})$/.exec(this.quarter || '');
        if (!match) {
            return [];
        }
        const firstMonth = (Number(match[1]) - 1) * 3 + 1;
        return [0, 1, 2].map((offset) => ({
            monthStart: `${match[2]}-${String(firstMonth + offset).padStart(2, '0')}-01`,
            appliedVisitsByClass: {}
        }));
    }

    get monthHeaders() {
        return this.cycleMonths.map((month, index) => ({
            key: `${month.monthStart || index}`,
            label: month.monthStart
                ? new Date(`${month.monthStart}T00:00:00`).toLocaleDateString(undefined, { month: 'short' })
                : `M${index + 1}`
        }));
    }

    /** One exception cell per month of the cycle: rep suggests, the manager approves, changes or declines. */
    monthCells(row, classCode) {
        return this.cycleMonths.map((month, index) => {
            const monthStart = month.monthStart;
            const key = this.monthDraftKey(row.accountId, monthStart);
            const drafted = this.frequencyDraft.has(key);
            const state = this.monthState(row, monthStart);
            const value = this.effectiveException(row, monthStart);
            const pending = value != null && !state.reviewed && !drafted;
            const classFrequency = month.appliedVisitsByClass?.[classCode] ?? row.gridFrequency;
            let note = '';
            if (drafted && value == null && state.suggested != null) {
                note = `Declining (${state.suggested})`;
            } else if (state.reviewed && state.suggested != null && state.approved == null) {
                note = `Declined (${state.suggested})`;
            } else if (state.reviewed && state.suggested != null && state.approved != null && state.approved !== state.suggested) {
                note = `Rep: ${state.suggested}`;
            } else if (pending && this.isReviewingOther) {
                note = 'Rep suggests';
            } else if (pending) {
                note = 'Awaiting DM';
            }
            const label = this.monthHeaders[index]?.label || '';
            return {
                key: `${row.accountId}-${monthStart || index}`,
                monthStart,
                value: value == null ? '' : String(value),
                hasValue: value != null,
                placeholder: classFrequency == null ? '—' : String(classFrequency),
                note,
                title: `${label}: ${
                    pending ? 'suggested visits · needs DM approval' : 'visits exception (overrides the class frequency)'
                }${note ? ` · ${note}` : ''}`,
                ariaLabel: `${label} visits exception`,
                inputClass: pending ? 'exc-input pending' : 'exc-input',
                pillClass: pending ? 'exc-pill pending' : 'exc-pill'
            };
        });
    }

    get classOptions() {
        return [
            { label: 'Select', value: '' },
            ...(this.page?.classOptions || []).map((option) => ({
                label: option.label,
                value: option.value
            }))
        ];
    }

    async refresh() {
        this.isLoading = true;
        try {
            const data = await getPage({
                employeeId: this.selectedTerritoryId ? null : this.selectedEmployeeId || null,
                quarter: this.quarter,
                territoryId: this.selectedTerritoryId || null
            });
            this.applyPage(data);
            if (data?.cycle?.quarter) {
                this.quarter = data.cycle.quarter;
            }
        } catch (error) {
            this.toast('Error', this.reduceError(error), 'error');
        } finally {
            this.isLoading = false;
        }
    }

    scoreProducts(products, useRx = true) {
        let total = 0;
        (products || []).forEach((product) => {
            const weight = Number(product.weightPercentage);
            if (Number.isNaN(weight)) {
                return;
            }
            const potential = Number(
                useRx ? product.rxPotential : product.salesPotential
            );
            const penetration = Number(
                useRx ? product.rxPenetration : product.salesPenetration
            );
            const pot = Number.isNaN(potential) ? 0 : potential;
            const pen = Number.isNaN(penetration) ? 0 : penetration;
            const share = pot === 0 ? 0 : pen / pot;
            total += (weight / 100) * pot * share;
        });
        return total;
    }

    productContribution(product) {
        const weight = Number(product.weightPercentage) || 0;
        const pot = Number(product.rxPotential) || 0;
        const pen = Number(product.rxPenetration) || 0;
        const share = pot === 0 ? 0 : pen / pot;
        return (weight / 100) * pot * share;
    }

    recomputeLiveScores() {
        const scored = (this.accounts || []).map((row) => {
            const liveScore = this.scoreProducts(row.products, true);
            return { accountId: row.accountId, liveScore };
        });
        scored.sort((a, b) => b.liveScore - a.liveScore);
        const rankById = new Map();
        scored.forEach((item, index) => {
            rankById.set(item.accountId, index + 1);
        });
        this.accounts = (this.accounts || []).map((row) => {
            const liveScore = this.scoreProducts(row.products, true);
            const products = (row.products || []).map((product) => ({
                ...product,
                contribLabel: this.formatScore(this.productContribution(product))
            }));
            return {
                ...row,
                products,
                liveScore,
                liveScoreLabel: this.formatScore(liveScore),
                liveRank: rankById.get(row.accountId) || '—',
                liveRankLabel: String(rankById.get(row.accountId) || '—')
            };
        });
    }

    formatScore(value) {
        const num = Number(value) || 0;
        return num.toFixed(1);
    }

    decorateAccount(row) {
        const expanded = this.expandedIds.has(row.accountId);
        const chosen = this.chosenDraft.has(row.accountId)
            ? this.chosenDraft.get(row.accountId)
            : row.chosenClass || row.rxClass || '';
        const promoIds = this.promoProductIdSet;
        const products = (row.products || [])
            .filter((product) => {
                if (!product?.product2Id) {
                    return false;
                }
                if (promoIds.size === 0) {
                    return Number(product.weightPercentage) > 0;
                }
                return promoIds.has(product.product2Id);
            })
            .map((product) => {
                const key = `${row.accountId}-${product.product2Id}`;
                const broken = this.brokenProductImages[key];
                return {
                    ...product,
                    key,
                    hasImage: Boolean(product.imageUrl) && !broken,
                    initials: this.initialsFrom(product.productName),
                    weightLabel:
                        product.weightPercentage == null ? '—' : String(product.weightPercentage),
                    salesPotentialLabel:
                        product.salesPotential == null ? '—' : String(product.salesPotential),
                    salesPenetrationLabel:
                        product.salesPenetration == null ? '—' : String(product.salesPenetration),
                    contribLabel: this.formatScore(this.productContribution(product))
                };
            });
        const liveScore = this.scoreProducts(products, true);
        const listKind = resolveAccountListKind(
            row.recordTypeDeveloperName,
            row.recordTypeName
        );
        return {
            ...row,
            expanded,
            rowClass: expanded ? 'account-row expanded' : 'account-row',
            chosenClass: chosen,
            monthCells: this.monthCells(row, chosen || row.rxClass),
            typeIconName: listKind.iconName,
            typeIconUrl: accountTypeIconUrl(listKind.kind),
            typeIconClass: `account-type-icon account-type-icon-${listKind.kind}`,
            typeIconLabel: listKind.label || row.recordTypeName || 'Account',
            gridFrequencyLabel: row.gridFrequency == null ? '—' : String(row.gridFrequency),
            products,
            productCount: products.length,
            hasProducts: products.length > 0,
            liveScore,
            liveScoreLabel: this.formatScore(liveScore),
            liveRankLabel: '—'
        };
    }

    initialsFrom(name) {
        const parts = String(name || '')
            .trim()
            .split(/\s+/)
            .filter(Boolean);
        if (parts.length === 0) {
            return '?';
        }
        if (parts.length === 1) {
            return parts[0].slice(0, 2).toUpperCase();
        }
        return `${parts[0][0]}${parts[1][0]}`.toUpperCase();
    }

    handleSearch(event) {
        this.searchTerm = event.target.value;
    }

    handleSpecialtyFilter(event) {
        this.specialtyFilter = event.detail?.value || event.target?.value;
    }

    handleQuarterChange(event) {
        this.quarter = event.detail?.value || event.target?.value;
        this.refresh();
    }

    handleTerritoryChange(event) {
        this.openTerritory(event.detail?.value || event.target?.value);
    }

    handlePrevTerritory() {
        const row = this.navigatorTerritories[this.territoryIndex - 1];
        if (row) {
            this.openTerritory(row.territoryId);
        }
    }

    handleNextTerritory() {
        const row = this.navigatorTerritories[this.territoryIndex + 1];
        if (row) {
            this.openTerritory(row.territoryId);
        }
    }

    openTerritory(territoryId) {
        if (!territoryId || territoryId === this.selectedTerritoryId) {
            return;
        }
        const row = this.reviewTerritories.find((item) => item.territoryId === territoryId);
        const pendingQuarters = row?.pendingQuarters || [];
        if (pendingQuarters.length > 0 && !pendingQuarters.includes(this.quarter)) {
            this.quarter = pendingQuarters[0];
        }
        this.selectedTerritoryId = territoryId;
        this.selectedEmployeeId = null;
        this.chosenDraft = new Map();
        this.frequencyDraft = new Map();
        this.refresh();
    }

    handlePrevQuarter() {
        this.quarter = this.shiftQuarter(this.quarter, -1);
        this.refresh();
    }

    handleNextQuarter() {
        this.quarter = this.shiftQuarter(this.quarter, 1);
        this.refresh();
    }

    shiftQuarter(value, delta) {
        const match = /^Q([1-4])-(\d{4})$/.exec(value || '');
        if (!match) {
            return this.defaultQuarter();
        }
        const index = Number(match[2]) * 4 + (Number(match[1]) - 1) + delta;
        return `Q${(index % 4) + 1}-${Math.floor(index / 4)}`;
    }

    openInfoModal() {
        this.showInfoModal = true;
    }

    closeInfoModal() {
        this.showInfoModal = false;
    }

    openPromoModal() {
        this.showPromoModal = true;
    }

    closePromoModal() {
        this.showPromoModal = false;
    }

    stopModalBubble(event) {
        event.stopPropagation();
    }

    handleProductImgError(event) {
        const key = event.target.dataset.key;
        if (!key) {
            return;
        }
        this.brokenProductImages = { ...this.brokenProductImages, [key]: true };
        this.accounts = this.accounts.map((row) => this.decorateAccount(row));
        this.recomputeLiveScores();
    }

    handlePromoImgError(event) {
        const id = event.target.dataset.id;
        if (!id) {
            return;
        }
        this.brokenPromoImages = { ...this.brokenPromoImages, [id]: true };
    }

    toggleRow(event) {
        const accountId = event.currentTarget.dataset.id;
        if (this.expandedIds.has(accountId)) {
            this.expandedIds.delete(accountId);
        } else {
            this.expandedIds.add(accountId);
        }
        this.accounts = this.accounts.map((row) => this.decorateAccount(row));
        this.recomputeLiveScores();
    }

    handleChosenClass(event) {
        const accountId = event.target.dataset.id;
        const value = event.detail.value;
        this.chosenDraft.set(accountId, value);
        this.accounts = this.accounts.map((row) => this.decorateAccount(row));
        this.recomputeLiveScores();
    }

    handleExceptionFrequency(event) {
        const accountId = event.target.dataset.id;
        const monthStart = event.target.dataset.month;
        const raw = event.target.value;
        const value = raw === '' || raw == null ? null : Math.round(Number(raw));
        if (value != null && (Number.isNaN(value) || value < 0 || value > 99)) {
            this.toast('Invalid frequency', 'Enter 0–99 visits per month, or leave blank.', 'warning');
            return;
        }
        this.frequencyDraft.set(this.monthDraftKey(accountId, monthStart), value);
        this.accounts = this.accounts.map((row) => this.decorateAccount(row));
        this.recomputeLiveScores();
        if (this.canEdit) {
            // Rep suggestions save right away so a re-classify keeps them.
            void this.persistFrequencyDraft();
        }
    }

    async persistFrequencyDraft() {
        try {
            await this.persistChosenDraft();
        } catch (error) {
            this.toast('Error', this.reduceError(error), 'error');
        }
    }

    handleRatingInput(event) {
        const product2Id = event.target.dataset.product;
        const accountId = event.target.dataset.account;
        const field = event.target.dataset.field;
        const value = event.target.value === '' ? null : Number(event.target.value);
        const account = this.accounts.find((row) => row.accountId === accountId);
        if (!account) {
            return;
        }
        const product = (account.products || []).find((item) => item.product2Id === product2Id);
        if (!product) {
            return;
        }
        if (field === 'potential') {
            product.rxPotential = value;
        } else {
            product.rxPenetration = value;
        }
        this.livePreviewActive = true;
        this.recomputeLiveScores();
        this.scheduleLiveClassify();
    }

    async handleSaveRating(event) {
        const product2Id = event.target.dataset.product;
        const accountId = event.target.dataset.account;
        const field = event.target.dataset.field;
        const value = event.target.value === '' ? null : Number(event.target.value);
        const account = this.accounts.find((row) => row.accountId === accountId);
        if (!account) {
            return;
        }
        const product = (account.products || []).find((item) => item.product2Id === product2Id);
        if (!product) {
            return;
        }
        if (field === 'potential') {
            product.rxPotential = value;
        } else {
            product.rxPenetration = value;
        }
        this.recomputeLiveScores();
        const timerKey = `${accountId}:${product2Id}`;
        if (this.saveTimers[timerKey]) {
            clearTimeout(this.saveTimers[timerKey]);
        }
        this.saveTimers[timerKey] = setTimeout(async () => {
            try {
                await saveProductRatings({
                    accountId,
                    territoryId: this.page?.territoryId,
                    product2Id,
                    potential: product.rxPotential,
                    penetration: product.rxPenetration
                });
                this.scheduleLiveClassify();
            } catch (error) {
                this.toast('Error', this.reduceError(error), 'error');
            }
        }, 250);
    }

    scheduleLiveClassify() {
        if (!this.canEdit || !this.page?.promoGrid) {
            return;
        }
        if (this.classifyTimer) {
            clearTimeout(this.classifyTimer);
        }
        this.livePreviewActive = true;
        this.classifyTimer = setTimeout(() => {
            this.runLiveClassify();
        }, 550);
    }

    async runLiveClassify() {
        if (!this.canEdit || !this.page?.promoGrid || this.isLoading) {
            return;
        }
        try {
            await this.persistChosenDraft();
            const data = await classify({
                employeeId: this.selectedTerritoryId ? null : this.selectedEmployeeId || null,
                quarter: this.quarter,
                territoryId: this.selectedTerritoryId || this.page?.territoryId || null
            });
            const expanded = new Set(this.expandedIds);
            this.applyPage(data);
            this.expandedIds = expanded;
            this.accounts = this.accounts.map((row) => this.decorateAccount(row));
            this.recomputeLiveScores();
            this.livePreviewActive = true;
            setTimeout(() => {
                this.livePreviewActive = false;
            }, 1200);
        } catch (error) {
            // Keep local live scores if classify fails (e.g. already submitted).
            this.livePreviewActive = false;
        }
    }

    async handleClassify() {
        this.isLoading = true;
        try {
            await this.persistChosenDraft();
            const data = await classify({
                employeeId: this.selectedTerritoryId ? null : this.selectedEmployeeId || null,
                quarter: this.quarter,
                territoryId: this.selectedTerritoryId || this.page?.territoryId || null
            });
            this.applyPage(data);
            this.recomputeLiveScores();
            this.toast('Classified', 'Promo Grid classify complete for this quarter.', 'success');
        } catch (error) {
            this.toast('Error', this.reduceError(error), 'error');
        } finally {
            this.isLoading = false;
        }
    }

    async handleSubmit() {
        if (!this.page?.cycle?.id) {
            return;
        }
        this.isLoading = true;
        try {
            await this.persistChosenDraft();
            const data = await submitCycle({
                cycleId: this.page.cycle.id,
                quarter: this.quarter
            });
            this.applyPage(data);
            this.toast('Submitted', 'Cycle sent for manager approval.', 'success');
        } catch (error) {
            this.toast('Error', this.reduceError(error), 'error');
        } finally {
            this.isLoading = false;
        }
    }

    async handleApprove() {
        if (!this.page?.cycle?.id) {
            return;
        }
        this.isLoading = true;
        try {
            const overrides = this.buildChosenUpdates();
            const data = await approveCycle({
                cycleId: this.page.cycle.id,
                managerOverrides: overrides
            });
            this.applyPage(data);
            this.toast(
                'Approved',
                'Classification and plan-cycle targets applied to monthly time cards.',
                'success'
            );
        } catch (error) {
            this.toast('Error', this.reduceError(error), 'error');
        } finally {
            this.isLoading = false;
        }
    }

    async handleReject() {
        if (!this.page?.cycle?.id) {
            return;
        }
        this.isLoading = true;
        try {
            const data = await rejectCycle({
                cycleId: this.page.cycle.id,
                reason: 'Rejected'
            });
            this.applyPage(data);
            this.toast('Rejected', 'Cycle returned to the rep.', 'success');
        } catch (error) {
            this.toast('Error', this.reduceError(error), 'error');
        } finally {
            this.isLoading = false;
        }
    }

    async handleOpenPending(event) {
        const territoryId = event.currentTarget.dataset.territory || null;
        const employeeId = event.currentTarget.dataset.employee || null;
        this.selectedTerritoryId = territoryId;
        this.selectedEmployeeId = territoryId ? null : employeeId;
        this.quarter = event.currentTarget.dataset.quarter;
        this.chosenDraft = new Map();
        this.frequencyDraft = new Map();
        await this.refresh();
    }

    applyPage(data) {
        this.page = data;
        if (data?.territoryId) {
            this.selectedTerritoryId = data.territoryId;
        }
        this.months = data?.months || [];
        this.accounts = (data?.accounts || []).map((row) => this.decorateAccount(row));
        this.recomputeLiveScores();
    }

    async persistChosenDraft() {
        if (!this.page?.cycle?.id || (this.chosenDraft.size === 0 && this.frequencyDraft.size === 0)) {
            return;
        }
        const updates = this.buildChosenUpdates();
        if (updates.length === 0) {
            return;
        }
        const data = await saveChosenClasses({
            cycleId: this.page.cycle.id,
            updates
        });
        this.chosenDraft = new Map();
        this.frequencyDraft = new Map();
        if (data) {
            this.applyPage(data);
        }
    }

    buildChosenUpdates() {
        const byAccount = new Map();
        this.chosenDraft.forEach((chosenClass, accountId) => {
            byAccount.set(accountId, { accountId, chosenClass, overrideClass: null });
        });
        this.frequencyDraft.forEach((frequency, key) => {
            const [accountId, monthStart] = key.split(MONTH_DRAFT_SEPARATOR);
            const row = byAccount.get(accountId) || { accountId, chosenClass: null, overrideClass: null };
            row.monthFrequencies = [...(row.monthFrequencies || []), { monthStart, frequency }];
            byAccount.set(accountId, row);
        });
        return Array.from(byAccount.values());
    }

    toast(title, message, variant) {
        this.dispatchEvent(new ShowToastEvent({ title, message, variant }));
    }

    reduceError(error) {
        if (!error) {
            return 'Unknown error';
        }
        if (Array.isArray(error.body)) {
            return error.body.map((item) => item.message).join(', ');
        }
        if (error.body?.message) {
            return error.body.message;
        }
        return error.message || 'Unknown error';
    }
}