import { LightningElement, track } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import getPage from '@salesforce/apex/ClassEngineController.getPage';
import saveProductRatings from '@salesforce/apex/ClassEngineController.saveProductRatings';
import classify from '@salesforce/apex/ClassEngineController.classify';
import saveChosenClasses from '@salesforce/apex/ClassEngineController.saveChosenClasses';
import submitCycle from '@salesforce/apex/ClassEngineController.submitCycle';
import approveCycle from '@salesforce/apex/ClassEngineController.approveCycle';
import rejectCycle from '@salesforce/apex/ClassEngineController.rejectCycle';

export default class ClassEngineTab extends LightningElement {
    @track page;
    @track accounts = [];
    @track months = [];
    @track isLoading = false;
    @track showSettings = false;
    @track searchTerm = '';
    @track specialtyFilter = 'All';
    @track selectedEmployeeId;
    @track quarter;

    expandedIds = new Set();
    chosenDraft = new Map();

    connectedCallback() {
        const now = new Date();
        const q = Math.floor(now.getMonth() / 3) + 1;
        this.quarter = `Q${q}-${now.getFullYear()}`;
        this.refresh();
    }

    get isBusy() {
        return this.isLoading;
    }

    get cycleStatus() {
        return this.page?.cycle?.status || 'Draft';
    }

    get canEdit() {
        return this.cycleStatus === 'Draft' || this.cycleStatus === 'Rejected';
    }

    get canSubmit() {
        return this.canEdit && (this.accounts || []).some((row) => row.rxClass);
    }

    get canApprove() {
        return this.page?.canApprove === true && this.cycleStatus === 'Submitted';
    }

    get showRepSwitcher() {
        return this.page?.canApprove === true && (this.page?.teamReps || []).length > 0;
    }

    get teamRepOptions() {
        const options = [{ label: 'My territory', value: '' }];
        (this.page?.teamReps || []).forEach((rep) => {
            options.push({ label: rep.name, value: rep.userId });
        });
        return options;
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

    get promoGrid() {
        return this.page?.promoGrid;
    }

    get pendingCycles() {
        return this.page?.pendingCycles || [];
    }

    get hasPending() {
        return this.pendingCycles.length > 0;
    }

    get capacitySummary() {
        if (!this.months || this.months.length === 0) {
            return 'Classify to see monthly capacity.';
        }
        return this.months
            .map((month) => {
                const label = month.monthStart
                    ? new Date(month.monthStart).toLocaleDateString(undefined, {
                          month: 'short',
                          year: 'numeric'
                      })
                    : 'Month';
                return `${label}: ${month.plannedVisits || 0} / ${month.capacityVisits || 0}`;
            })
            .join(' · ');
    }

    get classOptions() {
        return (this.page?.classOptions || []).map((option) => ({
            label: option.label,
            value: option.value
        }));
    }

    async refresh() {
        this.isLoading = true;
        try {
            const data = await getPage({
                employeeId: this.selectedEmployeeId || null,
                quarter: this.quarter
            });
            this.page = data;
            this.accounts = (data?.accounts || []).map((row) => this.decorateAccount(row));
            this.months = data?.months || [];
            if (data?.cycle?.quarter) {
                this.quarter = data.cycle.quarter;
            }
        } catch (error) {
            this.toast('Error', this.reduceError(error), 'error');
        } finally {
            this.isLoading = false;
        }
    }

    decorateAccount(row) {
        const expanded = this.expandedIds.has(row.accountId);
        const chosen = this.chosenDraft.has(row.accountId)
            ? this.chosenDraft.get(row.accountId)
            : row.chosenClass || row.rxClass;
        return {
            ...row,
            expanded,
            expandIcon: expanded ? '▾' : '▸',
            rowClass: expanded ? 'account-row expanded' : 'account-row',
            chosenClass: chosen,
            gridFrequencyLabel: row.gridFrequency == null ? '—' : String(row.gridFrequency),
            monthFrequencyLabel: row.monthFrequency == null ? '—' : String(row.monthFrequency),
            products: (row.products || []).map((product) => ({
                ...product,
                key: `${row.accountId}-${product.product2Id}`
            }))
        };
    }

    handleSearch(event) {
        this.searchTerm = event.target.value;
    }

    handleSpecialtyFilter(event) {
        this.specialtyFilter = event.detail.value;
    }

    handleQuarterChange(event) {
        this.quarter = event.target.value;
        this.refresh();
    }

    handleRepChange(event) {
        this.selectedEmployeeId = event.detail.value || null;
        this.refresh();
    }

    toggleSettings() {
        this.showSettings = !this.showSettings;
    }

    toggleRow(event) {
        const accountId = event.currentTarget.dataset.id;
        if (this.expandedIds.has(accountId)) {
            this.expandedIds.delete(accountId);
        } else {
            this.expandedIds.add(accountId);
        }
        this.accounts = this.accounts.map((row) => this.decorateAccount(row));
    }

    handleChosenClass(event) {
        const accountId = event.target.dataset.id;
        const value = event.detail.value;
        this.chosenDraft.set(accountId, value);
        this.accounts = this.accounts.map((row) => this.decorateAccount(row));
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
        try {
            await saveProductRatings({
                accountId,
                territoryId: this.page?.territoryId,
                product2Id,
                potential: product.rxPotential,
                penetration: product.rxPenetration
            });
            this.toast('Saved', 'Rx rating updated.', 'success');
        } catch (error) {
            this.toast('Error', this.reduceError(error), 'error');
        }
    }

    async handleClassify() {
        this.isLoading = true;
        try {
            await this.persistChosenDraft();
            const data = await classify({
                employeeId: this.selectedEmployeeId || null,
                quarter: this.quarter
            });
            this.page = data;
            this.accounts = (data?.accounts || []).map((row) => this.decorateAccount(row));
            this.months = data?.months || [];
            this.toast('Classified', 'Promo Grid classify complete.', 'success');
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
            this.toast('Approved', 'Classification and plan-cycle targets applied.', 'success');
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
        const employeeId = event.currentTarget.dataset.employee;
        const quarter = event.currentTarget.dataset.quarter;
        this.selectedEmployeeId = employeeId;
        this.quarter = quarter;
        await this.refresh();
    }

    applyPage(data) {
        this.page = data;
        this.accounts = (data?.accounts || []).map((row) => this.decorateAccount(row));
        this.months = data?.months || [];
    }

    async persistChosenDraft() {
        if (!this.page?.cycle?.id || this.chosenDraft.size === 0) {
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
        if (data) {
            this.applyPage(data);
        }
    }

    buildChosenUpdates() {
        const updates = [];
        this.chosenDraft.forEach((chosenClass, accountId) => {
            updates.push({ accountId, chosenClass, overrideClass: null });
        });
        return updates;
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
