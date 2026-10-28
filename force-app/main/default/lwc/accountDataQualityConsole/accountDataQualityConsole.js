import { LightningElement, track } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import startDuplicateScan from '@salesforce/apex/AccountQualityReviewService.startDuplicateScan';
import startNurtureScan from '@salesforce/apex/AccountQualityReviewService.startNurtureScan';
import getLatestRun from '@salesforce/apex/AccountQualityReviewService.getLatestRun';
import getRunStatus from '@salesforce/apex/AccountQualityReviewService.getRunStatus';
import listProposals from '@salesforce/apex/AccountQualityReviewService.listProposals';
import dismissProposals from '@salesforce/apex/AccountQualityReviewService.dismissProposals';
import applyProposals from '@salesforce/apex/AccountQualityReviewService.applyProposals';
import pickDoctor from '@salesforce/apex/AccountQualityReviewService.pickDoctor';

const TABS = [
    { id: 'duplicates', label: 'Duplicates' },
    { id: 'nurture', label: 'Nurture' },
    { id: 'specialty', label: 'Doctor specialty merger' }
];

const RECORD_TYPE_OPTIONS = [
    { label: 'HCP (person)', value: 'PersonAccount' },
    { label: 'HCP (clinic)', value: 'Medical_Professional_HCP' },
    { label: 'Pharmacy', value: 'Pharmacy' },
    { label: 'Institution (HCO)', value: 'Institution_HCO' }
];

export default class AccountDataQualityConsole extends LightningElement {
    @track activeTab = 'duplicates';
    @track selectedRecordTypes = ['PersonAccount', 'Medical_Professional_HCP', 'Pharmacy', 'Institution_HCO'];
    @track skipRecentlyReviewed = true;
    @track showPossible = false;
    @track isBusy = false;
    @track progressMessage = '';
    @track progressPercent = 0;
    @track runStatus = null;
    @track proposals = [];
    pollTimer;

    get tabs() {
        return TABS.map((tab) => ({
            ...tab,
            className: `tab-btn${this.activeTab === tab.id ? ' tab-btn--active' : ''}`
        }));
    }

    get isDuplicatesTab() {
        return this.activeTab === 'duplicates';
    }

    get isNurtureTab() {
        return this.activeTab === 'nurture';
    }

    get isSpecialtyTab() {
        return this.activeTab === 'specialty';
    }

    get isScanTab() {
        return !this.isSpecialtyTab;
    }

    get recordTypeOptions() {
        return RECORD_TYPE_OPTIONS.map((opt) => ({
            ...opt,
            checked: this.selectedRecordTypes.includes(opt.value)
        }));
    }

    get hasProposals() {
        return (this.proposals || []).length > 0;
    }

    get pendingProposals() {
        return (this.proposals || []).filter(
            (row) => row.status === 'Pending' || row.status === 'Needs Pick' || row.status === 'Failed'
        );
    }

    get selectedCount() {
        return this.pendingProposals.filter((row) => row.selected).length;
    }

    get allPendingSelected() {
        const pending = this.pendingProposals;
        return pending.length > 0 && pending.every((row) => row.selected);
    }

    get isRunActive() {
        const status = this.runStatus?.status;
        return status === 'Queued' || status === 'Running';
    }

    get runScanLabel() {
        return this.isDuplicatesTab ? 'Run duplicate scan' : 'Run nurture scan';
    }

    get runSummary() {
        if (!this.runStatus || this.runStatus.status === 'None') {
            return 'No scan yet for this tab.';
        }
        const parts = [
            `Status: ${this.runStatus.status}`,
            `Scanned: ${this.runStatus.accountsScanned || 0}`,
            `Proposals: ${this.runStatus.proposalCount || 0}`
        ];
        if (this.runStatus.errorMessage) {
            parts.push(this.runStatus.errorMessage);
        }
        return parts.join(' · ');
    }

    get proposalCards() {
        return (this.proposals || []).map((row) => {
            const badgeClass = this.badgeClass(row.possibilityLabel, row.score);
            const isDuplicate = row.provider === 'Duplicate';
            const isPending =
                row.status === 'Pending' || row.status === 'Needs Pick' || row.status === 'Failed';
            const fields = (row.fields || []).map((field) => ({
                ...field,
                key: `${row.id}-${field.field}`,
                kindClass: `kind kind--${field.kind || 'fill'}`,
                currentDisplay: field.currentValue || '—',
                proposedDisplay: field.proposedValue || '—'
            }));
            const factors = (row.factors || []).map((factor) => ({
                ...factor,
                key: `${row.id}-${factor.key}`
            }));
            const doctors = (row.doctors || []).map((doctor) => ({
                ...doctor,
                key: `${row.id}-${doctor.urlName}`
            }));
            return {
                ...row,
                cardClass: `card${row.selected ? ' card--selected' : ''}`,
                badgeClass,
                scoreLabel: row.score == null ? '' : `${row.score}%`,
                isDuplicate,
                isNurture: !isDuplicate,
                isPending,
                fieldsLocked: !isPending,
                showMerge: isDuplicate && row.canMerge,
                markChecked: row.decision === 'Mark',
                mergeChecked: row.decision === 'Merge',
                decisionGroupName: `${row.id}-decision`,
                survivorGroupName: `${row.id}-survivor`,
                survivorIsAccount: row.survivorAccountId === row.accountId,
                survivorIsMatch: row.survivorAccountId === row.matchAccountId,
                fields,
                factors,
                doctors,
                hasFields: fields.length > 0,
                hasFactors: factors.length > 0,
                hasDoctors: doctors.length > 0 && row.status === 'Needs Pick'
            };
        });
    }

    connectedCallback() {
        this.refreshLatest();
    }

    disconnectedCallback() {
        this.stopPolling();
    }

    handleTabClick(event) {
        const tabId = event.currentTarget.dataset.tabId;
        if (!tabId || tabId === this.activeTab) {
            return;
        }
        this.activeTab = tabId;
        this.proposals = [];
        this.runStatus = null;
        this.stopPolling();
        if (this.isSpecialtyTab) {
            // The merger tab loads its own runs.
            this.isBusy = false;
            return;
        }
        this.refreshLatest();
    }

    handleRecordTypeToggle(event) {
        const value = event.target.value;
        const checked = event.target.checked;
        const next = new Set(this.selectedRecordTypes);
        if (checked) {
            next.add(value);
        } else {
            next.delete(value);
        }
        this.selectedRecordTypes = Array.from(next);
    }

    handleSkipToggle(event) {
        this.skipRecentlyReviewed = event.target.checked;
    }

    handleShowPossibleToggle(event) {
        this.showPossible = event.target.checked;
        if (this.runStatus?.runId) {
            this.loadProposals(this.runStatus.runId);
        }
    }

    async handleRunScan() {
        if (this.isRunActive) {
            this.toast('Scan already running', 'A scan of this type is already in progress.', 'info');
            this.startPolling(this.runStatus.runId);
            return;
        }
        if (this.selectedRecordTypes.length === 0) {
            this.toast('Choose record types', 'Select at least one record type to scan.', 'warning');
            return;
        }
        this.isBusy = true;
        this.progressMessage = 'Starting scan…';
        this.progressPercent = 5;
        try {
            const filter = this.selectedRecordTypes.join(',');
            const status = this.isDuplicatesTab
                ? await startDuplicateScan({ recordTypeFilter: filter })
                : await startNurtureScan({
                      recordTypeFilter: filter,
                      skipRecentlyReviewed: this.skipRecentlyReviewed
                  });
            this.runStatus = status;
            this.startPolling(status.runId);
        } catch (error) {
            this.toast('Scan failed', this.errorMessage(error), 'error');
            this.isBusy = false;
            this.progressMessage = '';
        }
    }

    handleSelectAll(event) {
        const checked = event.target.checked;
        this.proposals = (this.proposals || []).map((row) => {
            if (row.status === 'Pending' || row.status === 'Needs Pick' || row.status === 'Failed') {
                return { ...row, selected: checked };
            }
            return row;
        });
    }

    handleRowSelect(event) {
        const id = event.target.dataset.id;
        const checked = event.target.checked;
        this.proposals = (this.proposals || []).map((row) =>
            row.id === id ? { ...row, selected: checked } : row
        );
    }

    handleDecisionChange(event) {
        const id = event.target.dataset.id;
        const decision = event.target.value;
        this.proposals = (this.proposals || []).map((row) =>
            row.id === id ? { ...row, decision } : row
        );
    }

    handleSurvivorChange(event) {
        const id = event.target.dataset.id;
        const survivorAccountId = event.target.value;
        this.proposals = (this.proposals || []).map((row) =>
            row.id === id ? { ...row, survivorAccountId } : row
        );
    }

    handleFieldToggle(event) {
        const id = event.target.dataset.id;
        const field = event.target.dataset.field;
        const checked = event.target.checked;
        this.proposals = (this.proposals || []).map((row) => {
            if (row.id !== id) {
                return row;
            }
            const fields = (row.fields || []).map((item) =>
                item.field === field ? { ...item, accepted: checked } : item
            );
            return { ...row, fields };
        });
    }

    async handlePickDoctor(event) {
        const id = event.currentTarget.dataset.id;
        const urlName = event.currentTarget.dataset.url;
        this.isBusy = true;
        try {
            const updated = await pickDoctor({ proposalId: id, urlName });
            this.proposals = (this.proposals || []).map((row) =>
                row.id === id ? { ...updated, selected: row.selected } : row
            );
            this.toast('Doctor selected', 'Field changes are ready to greenlight.', 'success');
        } catch (error) {
            this.toast('Pick failed', this.errorMessage(error), 'error');
        } finally {
            this.isBusy = false;
        }
    }

    async handleDismiss() {
        const ids = this.pendingProposals.filter((row) => row.selected).map((row) => row.id);
        if (ids.length === 0) {
            this.toast('Nothing selected', 'Select one or more pending rows.', 'warning');
            return;
        }
        this.isBusy = true;
        try {
            const result = await dismissProposals({ proposalIds: ids });
            this.toast('Dismissed', `${result.dismissed} row(s) dismissed.`, 'success');
            if (this.runStatus?.runId) {
                await this.loadProposals(this.runStatus.runId);
            }
        } catch (error) {
            this.toast('Dismiss failed', this.errorMessage(error), 'error');
        } finally {
            this.isBusy = false;
        }
    }

    async handleGreenlight() {
        const selected = this.pendingProposals.filter((row) => row.selected);
        if (selected.length === 0) {
            this.toast('Nothing selected', 'Select one or more pending rows.', 'warning');
            return;
        }
        for (const row of selected) {
            if (row.provider === 'Duplicate' && row.decision !== 'Mark' && row.decision !== 'Merge') {
                this.toast(
                    'Choose an action',
                    `Set Mark or Merge on ${row.accountName || 'the selected duplicate'}.`,
                    'warning'
                );
                return;
            }
            if (row.status === 'Needs Pick') {
                this.toast(
                    'Pick a doctor',
                    `Choose a Vezeeta doctor for ${row.accountName || 'the selected account'}.`,
                    'warning'
                );
                return;
            }
        }
        const confirmed = window.confirm(
            `Greenlight ${selected.length} selected row(s)? Account changes will be written.`
        );
        if (!confirmed) {
            return;
        }
        this.isBusy = true;
        try {
            const inputs = selected.map((row) => ({
                proposalId: row.id,
                decision: row.decision,
                survivorAccountId: row.survivorAccountId,
                acceptedFields: (row.fields || [])
                    .filter((field) => field.accepted !== false)
                    .map((field) => field.field)
            }));
            const result = await applyProposals({ inputs });
            const parts = [];
            if (result.applied) {
                parts.push(`${result.applied} applied`);
            }
            if (result.failed) {
                parts.push(`${result.failed} failed`);
            }
            this.toast(
                'Greenlight finished',
                parts.join(', ') || 'No rows changed.',
                result.failed ? 'warning' : 'success'
            );
            if (this.runStatus?.runId) {
                await this.loadProposals(this.runStatus.runId);
            }
        } catch (error) {
            this.toast('Greenlight failed', this.errorMessage(error), 'error');
        } finally {
            this.isBusy = false;
        }
    }

    async refreshLatest() {
        this.isBusy = true;
        try {
            const typeName = this.isDuplicatesTab ? 'Duplicate' : 'Nurture';
            const status = await getLatestRun({ typeName });
            this.runStatus = status;
            if (status?.runId && (status.status === 'Queued' || status.status === 'Running')) {
                this.startPolling(status.runId);
            } else if (status?.runId && status.status === 'Ready') {
                await this.loadProposals(status.runId);
            }
        } catch (error) {
            this.toast('Load failed', this.errorMessage(error), 'error');
        } finally {
            if (!this.isRunActive) {
                this.isBusy = false;
                this.progressMessage = '';
            }
        }
    }

    startPolling(runId) {
        this.stopPolling();
        if (!runId) {
            return;
        }
        this.isBusy = true;
        this.progressMessage = 'Scan running…';
        this.pollTimer = setInterval(() => {
            this.pollOnce(runId);
        }, 2500);
        this.pollOnce(runId);
    }

    stopPolling() {
        if (this.pollTimer) {
            clearInterval(this.pollTimer);
            this.pollTimer = null;
        }
    }

    async pollOnce(runId) {
        try {
            const status = await getRunStatus({ runId });
            this.runStatus = status;
            const processed = status.jobItemsProcessed || 0;
            const total = status.totalJobItems || 0;
            this.progressPercent =
                total > 0 ? Math.min(95, Math.round((processed / total) * 100)) : 15;
            this.progressMessage = `Scan ${status.status.toLowerCase()}… ${processed}/${total || '?'}`;
            if (status.status === 'Ready' || status.status === 'Failed') {
                this.stopPolling();
                this.progressPercent = 100;
                this.progressMessage =
                    status.status === 'Ready' ? 'Scan ready.' : status.errorMessage || 'Scan failed.';
                this.isBusy = false;
                if (status.status === 'Ready') {
                    await this.loadProposals(runId);
                }
            }
        } catch (error) {
            this.stopPolling();
            this.isBusy = false;
            this.toast('Status failed', this.errorMessage(error), 'error');
        }
    }

    async loadProposals(runId) {
        const minScore = this.isDuplicatesTab && !this.showPossible ? 70 : 50;
        const rows = await listProposals({ runId, minScore });
        this.proposals = (rows || []).map((row) => ({
            ...row,
            selected: false,
            decision: row.decision || (row.provider === 'Duplicate' ? null : 'Apply'),
            fields: (row.fields || []).map((field) => ({
                ...field,
                accepted: field.accepted !== false
            }))
        }));
    }

    badgeClass(label, score) {
        if (label === 'Very likely' || score >= 85) {
            return 'badge badge--very';
        }
        if (label === 'Likely' || score >= 70) {
            return 'badge badge--likely';
        }
        if (label === 'Possible' || score >= 50) {
            return 'badge badge--possible';
        }
        return 'badge badge--weak';
    }

    toast(title, message, variant) {
        this.dispatchEvent(new ShowToastEvent({ title, message, variant }));
    }

    errorMessage(error) {
        return error?.body?.message || error?.message || 'Unexpected error.';
    }
}
