import { LightningElement, track } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import getRuleForLine from '@salesforce/apex/TargetGovernanceService.getRuleForLine';
import saveOrgRule from '@salesforce/apex/TargetGovernanceService.saveOrgRule';
import listProposals from '@salesforce/apex/OutOfTargetQueueService.listProposals';
import advanceStatus from '@salesforce/apex/OutOfTargetQueueService.advanceStatus';
import buildQueueForRep from '@salesforce/apex/OutOfTargetQueueService.buildQueueForRep';

const STATUS_OPTIONS = [
    { label: 'All', value: 'All' },
    { label: 'Pending DM', value: 'Pending DM' },
    { label: 'Pending FI', value: 'Pending FI' },
    { label: 'Pending BU', value: 'Pending BU' },
    { label: 'Approved', value: 'Approved' },
    { label: 'Rejected', value: 'Rejected' }
];

export default class TargetGovernanceAdmin extends LightningElement {
    loading = true;
    saving = false;
    statusOptions = STATUS_OPTIONS;
    statusFilter = 'Pending DM';
    @track rule = {
        frequencyDeviationPct: 10,
        listChurnDeviationPct: 10,
        scopeLevel: 'Org'
    };
    @track proposals = [];

    connectedCallback() {
        this.bootstrap();
    }

    get hasProposals() {
        return (this.proposals || []).length > 0;
    }

    async bootstrap() {
        this.loading = true;
        try {
            await Promise.all([this.loadRule(), this.loadProposals()]);
        } catch (error) {
            this.toast('Could not load target governance', this.errorMessage(error), 'error');
        } finally {
            this.loading = false;
        }
    }

    async loadRule() {
        this.rule = (await getRuleForLine({ lineName: null })) || this.rule;
    }

    async loadProposals() {
        const rows = await listProposals({
            repId: null,
            status: this.statusFilter === 'All' ? null : this.statusFilter
        });
        this.proposals = (rows || []).map((row) => ({
            ...row,
            key: row.id,
            // Only the next valid step is offered: DM -> FI -> BU -> Approved; Reject until final.
            canToFi: row.status === 'Pending DM',
            canToBu: row.status === 'Pending FI',
            canApprove: row.status === 'Pending BU',
            canReject: ['Pending DM', 'Pending FI', 'Pending BU'].includes(row.status),
            meta: `${row.repName || '—'} · ${row.visitCount || 0} validated visits · ${
                row.targetMonth || ''
            }`
        }));
    }

    handleRuleField(event) {
        const field = event.target.dataset.field;
        if (!field) return;
        const value = event.target.value === '' ? null : Number(event.target.value);
        this.rule = { ...this.rule, [field]: value };
    }

    async handleSaveRule() {
        this.saving = true;
        try {
            this.rule = await saveOrgRule({ payload: this.rule });
            this.toast('Saved', '±10% deviation alarms updated.', 'success');
        } catch (error) {
            this.toast('Save failed', this.errorMessage(error), 'error');
        } finally {
            this.saving = false;
        }
    }

    async handleStatusFilter(event) {
        this.statusFilter = event.detail.value;
        await this.loadProposals();
    }

    async handleBuildQueue() {
        this.saving = true;
        try {
            await buildQueueForRep({ repId: null, quarterStart: null, nextMonthStart: null });
            this.toast('Queue built', 'Out-of-target proposals for the current user were refreshed.', 'success');
            this.statusFilter = 'Pending DM';
            await this.loadProposals();
        } catch (error) {
            this.toast('Build failed', this.errorMessage(error), 'error');
        } finally {
            this.saving = false;
        }
    }

    async handleAdvance(event) {
        const id = event.currentTarget.dataset.id;
        const next = event.currentTarget.dataset.next;
        this.saving = true;
        try {
            await advanceStatus({ proposalId: id, nextStatus: next });
            this.toast('Updated', `Moved to ${next}.`, 'success');
            await this.loadProposals();
        } catch (error) {
            this.toast('Update failed', this.errorMessage(error), 'error');
        } finally {
            this.saving = false;
        }
    }

    toast(title, message, variant) {
        this.dispatchEvent(new ShowToastEvent({ title, message, variant }));
    }

    errorMessage(error) {
        return error?.body?.message || error?.message || 'Unknown error';
    }
}
