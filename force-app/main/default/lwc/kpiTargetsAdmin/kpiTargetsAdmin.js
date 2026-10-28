import { LightningElement, track } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import getCatalog from '@salesforce/apex/KpiTargetService.getCatalog';
import saveTargets from '@salesforce/apex/KpiTargetService.saveTargets';
import resetToFrameworkDefaults from '@salesforce/apex/KpiTargetService.resetToFrameworkDefaults';
import seedFrameworkDefaults from '@salesforce/apex/KpiTargetService.seedFrameworkDefaults';
import addTarget from '@salesforce/apex/KpiTargetService.addTarget';
import deleteTarget from '@salesforce/apex/KpiTargetService.deleteTarget';

const ROLE_LABELS = {
    MSR: 'Medical Sales Rep',
    DSM: 'District Manager',
    ASM: 'Area Manager',
    NSM: 'National Sales Manager',
    BM: 'Brand Manager',
    CHC_MSR: 'CHC Sales Rep',
    CHC_SS: 'CHC Sales Supervisor'
};

export default class KpiTargetsAdmin extends LightningElement {
    @track rows = [];
    @track countSources = [];
    @track metricPresets = [];
    @track roleKeys = [];
    needsSeed = false;
    loading = true;
    busy = false;
    confirmReset = false;
    error;
    roleFilter = 'ALL';
    searchText = '';
    showAdd = false;

    draftRole = 'DSM';
    draftMetricKey = 'Coverage';
    draftMetricLabel = 'Coverage';
    draftPercent = 90;
    draftPeriod = 'Monthly';
    draftScopeLevel = 'Org';
    draftScopeKey = '';
    draftCountSource = 'Visit_Coverage';
    draftCountNumerator = '';
    draftCountDenominator = '';

    get roleNav() {
        const counts = {};
        for (const row of this.rows) {
            counts[row.roleKey] = (counts[row.roleKey] || 0) + 1;
        }
        const items = [
            {
                key: 'ALL',
                label: 'All roles',
                count: this.rows.length,
                buttonClass: this.roleFilter === 'ALL' ? 'role-btn is-active' : 'role-btn'
            }
        ];
        for (const role of this.roleKeys) {
            items.push({
                key: role,
                label: ROLE_LABELS[role] || role,
                count: counts[role] || 0,
                buttonClass: this.roleFilter === role ? 'role-btn is-active' : 'role-btn'
            });
        }
        return items;
    }

    get roleOptions() {
        return this.roleKeys.map((r) => ({ label: ROLE_LABELS[r] || r, value: r }));
    }

    get periodOptions() {
        return [
            { label: 'Monthly', value: 'Monthly' },
            { label: 'Quarterly', value: 'Quarterly' }
        ];
    }

    get scopeLevelOptions() {
        return [
            { label: 'Org', value: 'Org' },
            { label: 'Line', value: 'Line' },
            { label: 'Title', value: 'Title' },
            { label: 'Profile', value: 'Profile' },
            { label: 'User', value: 'User' },
            { label: 'BU', value: 'BU' }
        ];
    }

    get countSourceOptions() {
        return (this.countSources || []).map((s) => ({ label: s.label, value: s.value }));
    }

    get metricPresetOptions() {
        const presets = (this.metricPresets || []).map((p) => ({
            label: p.metricLabel,
            value: p.metricKey
        }));
        return [{ label: 'Custom metric…', value: '__CUSTOM__' }, ...presets];
    }

    get selectedPresetValue() {
        const known = (this.metricPresets || []).some((p) => p.metricKey === this.draftMetricKey);
        return known ? this.draftMetricKey : '__CUSTOM__';
    }

    get isCustomMetric() {
        return this.selectedPresetValue === '__CUSTOM__';
    }

    get showScopeKey() {
        return this.draftScopeLevel && this.draftScopeLevel !== 'Org';
    }

    get filteredCards() {
        const q = (this.searchText || '').trim().toLowerCase();
        return this.rows
            .filter((r) => this.roleFilter === 'ALL' || r.roleKey === this.roleFilter)
            .filter((r) => {
                if (!q) return true;
                const blob = [
                    r.roleKey,
                    r.metricKey,
                    r.metricLabel,
                    r.countSourceLabel,
                    r.countNumerator,
                    r.countDenominator,
                    r.scopeLevel,
                    r.scopeKey
                ]
                    .filter(Boolean)
                    .join(' ')
                    .toLowerCase();
                return blob.includes(q);
            })
            .map((r) => ({
                ...r,
                key: r.id,
                roleLabel: ROLE_LABELS[r.roleKey] || r.roleKey,
                displayPct: r.targetPercent == null ? '' : String(r.targetPercent),
                periodLabel: r.period || 'Monthly',
                scopeLabel: [r.scopeLevel || 'Org', r.scopeKey].filter(Boolean).join(' · '),
                sourceBadge: r.countSourceLabel || r.countSource || 'Manual',
                customBadge: r.isCustom ? 'Custom' : null
            }));
    }

    get hasCards() {
        return this.filteredCards.length > 0;
    }

    get addToggleLabel() {
        return this.showAdd ? 'Hide add form' : 'Add metric';
    }

    connectedCallback() {
        this.refresh();
    }

    async refresh() {
        this.loading = true;
        this.error = null;
        try {
            const catalog = await getCatalog();
            this.rows = catalog.rows || [];
            this.countSources = catalog.countSources || [];
            this.metricPresets = catalog.metricPresets || [];
            this.roleKeys = catalog.roleKeys || [];
            this.needsSeed = catalog.needsSeed === true;
            this.applySourceDefaults(this.draftCountSource);
        } catch (e) {
            this.error = (e && e.body && e.body.message) || e.message || 'Failed to load KPI targets';
        } finally {
            this.loading = false;
        }
    }

    handleRoleClick(event) {
        this.roleFilter = event.currentTarget.dataset.role;
    }

    handleSearch(event) {
        this.searchText = event.target.value;
    }

    toggleAdd() {
        this.showAdd = !this.showAdd;
    }

    handlePctChange(event) {
        const id = event.target.dataset.id;
        const value = event.target.value;
        this.rows = this.rows.map((r) =>
            r.id === id ? { ...r, targetPercent: value === '' ? null : Number(value) } : r
        );
    }

    handleCardField(event) {
        const id = event.target.dataset.id;
        const field = event.target.dataset.field;
        const value = event.detail?.value ?? event.target.value;
        this.rows = this.rows.map((r) => {
            if (r.id !== id) return r;
            const next = { ...r, [field]: value };
            if (field === 'countSource') {
                const source = (this.countSources || []).find((s) => s.value === value);
                if (source) {
                    next.countSourceLabel = source.label;
                    next.countNumerator = source.numerator;
                    next.countDenominator = source.denominator;
                }
            }
            return next;
        });
    }

    handleDraftChange(event) {
        const field = event.target.dataset.field;
        const value = event.detail?.value ?? event.target.value;
        if (field === 'role') this.draftRole = value;
        if (field === 'metricKey') this.draftMetricKey = value;
        if (field === 'metricLabel') this.draftMetricLabel = value;
        if (field === 'percent') this.draftPercent = value === '' ? null : Number(value);
        if (field === 'period') this.draftPeriod = value;
        if (field === 'scopeLevel') this.draftScopeLevel = value;
        if (field === 'scopeKey') this.draftScopeKey = value;
        if (field === 'countSource') {
            this.draftCountSource = value;
            this.applySourceDefaults(value);
        }
        if (field === 'countNumerator') this.draftCountNumerator = value;
        if (field === 'countDenominator') this.draftCountDenominator = value;
    }

    handlePresetChange(event) {
        const value = event.detail.value;
        if (value === '__CUSTOM__') {
            this.draftMetricKey = '';
            this.draftMetricLabel = '';
            this.draftCountSource = 'Custom_Report';
            this.applySourceDefaults('Custom_Report');
            return;
        }
        const preset = (this.metricPresets || []).find((p) => p.metricKey === value);
        if (!preset) return;
        this.draftMetricKey = preset.metricKey;
        this.draftMetricLabel = preset.metricLabel;
        this.draftCountSource = preset.countSource || 'Manual';
        this.applySourceDefaults(this.draftCountSource);
    }

    applySourceDefaults(sourceValue) {
        const source = (this.countSources || []).find((s) => s.value === sourceValue);
        if (!source) return;
        this.draftCountNumerator = source.numerator || '';
        this.draftCountDenominator = source.denominator || '';
    }

    async handleSave() {
        this.busy = true;
        try {
            const payload = this.rows.map((r) => ({
                id: r.id,
                targetPercent: r.targetPercent,
                metricLabel: r.metricLabel,
                period: r.period,
                scopeLevel: r.scopeLevel,
                scopeKey: r.scopeKey,
                countSource: r.countSource,
                countNumerator: r.countNumerator,
                countDenominator: r.countDenominator
            }));
            this.rows = await saveTargets({ payloadJson: JSON.stringify(payload) });
            this.toast('KPI targets saved', 'success');
        } catch (e) {
            this.toast('Save failed', 'error', e);
        } finally {
            this.busy = false;
        }
    }

    async handleSeed() {
        this.busy = true;
        try {
            await seedFrameworkDefaults();
            this.toast('Framework targets loaded', 'success');
            await this.refresh();
        } catch (e) {
            this.toast('Could not load framework targets', 'error', e);
        } finally {
            this.busy = false;
        }
    }

    handleResetRequest() {
        this.confirmReset = true;
    }

    handleResetCancel() {
        this.confirmReset = false;
    }

    async handleReset() {
        if (!this.confirmReset) {
            return;
        }
        this.confirmReset = false;
        this.busy = true;
        try {
            this.rows = await resetToFrameworkDefaults();
            this.toast('Reset to SFE framework defaults', 'success');
            await this.refresh();
        } catch (e) {
            this.toast('Reset failed', 'error', e);
        } finally {
            this.busy = false;
        }
    }

    async handleAddTarget() {
        this.busy = true;
        try {
            this.rows = await addTarget({
                roleKey: this.draftRole,
                metricKey: this.draftMetricKey,
                metricLabel: this.draftMetricLabel,
                targetPercent: this.draftPercent,
                period: this.draftPeriod,
                scopeLevel: this.draftScopeLevel,
                scopeKey: this.draftScopeKey,
                countSource: this.draftCountSource,
                countNumerator: this.draftCountNumerator,
                countDenominator: this.draftCountDenominator
            });
            this.toast('Metric added', 'success');
            this.showAdd = false;
            this.roleFilter = this.draftRole || this.roleFilter;
            await this.refresh();
        } catch (e) {
            this.toast('Add failed', 'error', e);
        } finally {
            this.busy = false;
        }
    }

    async handleDelete(event) {
        const id = event.currentTarget.dataset.id;
        // eslint-disable-next-line no-alert
        if (!window.confirm('Remove this KPI metric?')) {
            return;
        }
        this.busy = true;
        try {
            this.rows = await deleteTarget({ targetId: id });
            this.toast('Metric removed', 'success');
            await this.refresh();
        } catch (e) {
            this.toast('Delete failed', 'error', e);
        } finally {
            this.busy = false;
        }
    }

    toast(title, variant, error) {
        this.dispatchEvent(
            new ShowToastEvent({
                title,
                message: error ? (error.body && error.body.message) || error.message : undefined,
                variant
            })
        );
    }
}
