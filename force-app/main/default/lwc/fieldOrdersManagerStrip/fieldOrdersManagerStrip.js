import { LightningElement, track } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import getApprovalQueue from '@salesforce/apex/FieldOrderService.getApprovalQueue';
import getMyOrders from '@salesforce/apex/FieldOrderService.getMyOrders';
import getFinanceQueue from '@salesforce/apex/FieldOrderService.getFinanceQueue';
import decideApproval from '@salesforce/apex/FieldOrderService.decideApproval';
import markPaid from '@salesforce/apex/FieldOrderService.markPaid';
import markSettled from '@salesforce/apex/FieldOrderService.markSettled';
import { isFieldFeatureEnabled, loadFieldFeatures } from 'c/fieldFeatureFlags';

const APPROVAL_STATUSES = new Set([
    'Pending DM',
    'Pending NAM',
    'Pending BU',
    'Pending Yasser',
    'Pending Finance'
]);

const FINANCE_STATUSES = new Set([
    'Pending Finance',
    'Approved',
    'Goods Issued',
    'Collected'
]);

export default class FieldOrdersManagerStrip extends LightningElement {
    @track rows = [];
    activeTab = 'pending';
    isLoading = false;
    errorMessage;
    featureEnabled = true;

    connectedCallback() {
        void this.bootstrap();
    }

    async bootstrap() {
        await loadFieldFeatures();
        this.featureEnabled = isFieldFeatureEnabled('orders');
        if (this.featureEnabled) {
            this.refresh();
        }
    }

    get hasRows() {
        return Array.isArray(this.rows) && this.rows.length > 0;
    }

    get isPendingTab() {
        return this.activeTab === 'pending';
    }
    get isMineTab() {
        return this.activeTab === 'mine';
    }
    get isFinanceTab() {
        return this.activeTab === 'finance';
    }

    handleTab(event) {
        this.activeTab = event.currentTarget.dataset.tab;
        this.refresh();
    }

    async refresh() {
        this.isLoading = true;
        this.errorMessage = undefined;
        try {
            let data = [];
            if (this.activeTab === 'pending') {
                data = await getApprovalQueue({ limitSize: 40 });
            } else if (this.activeTab === 'finance') {
                data = await getFinanceQueue({ limitSize: 40 });
            } else {
                data = await getMyOrders({ limitSize: 40 });
            }
            this.rows = (data || []).map((row) => ({
                ...row,
                createdByName: row.requestedByName,
                approvalStage: row.statusLabel || row.status,
                canApprove:
                    this.activeTab === 'pending' &&
                    (row.canApprove === true || APPROVAL_STATUSES.has(row.status)),
                canFinance: this.activeTab === 'finance' && FINANCE_STATUSES.has(row.status)
            }));
        } catch (error) {
            this.errorMessage = error?.body?.message || error?.message || 'Unable to load queue.';
            this.rows = [];
        } finally {
            this.isLoading = false;
        }
    }

    async handleApprove(event) {
        await this.decide(event.currentTarget.dataset.id, true);
    }

    async handleReject(event) {
        const notes = window.prompt('Rejection reason (optional)') || '';
        await this.decide(event.currentTarget.dataset.id, false, notes);
    }

    async decide(orderId, approve, notes) {
        try {
            await decideApproval({ orderId, approve, notes: notes || null });
            this.toast('Done', approve ? 'Order approved.' : 'Order rejected.', 'success');
            this.refresh();
        } catch (error) {
            this.toast('Error', error?.body?.message || error?.message || 'Action failed.', 'error');
        }
    }

    async handlePaid(event) {
        try {
            await markPaid({ orderId: event.currentTarget.dataset.id });
            this.toast('Done', 'Marked paid / collection.', 'success');
            this.refresh();
        } catch (error) {
            this.toast('Error', error?.body?.message || error?.message || 'Action failed.', 'error');
        }
    }

    async handleSettle(event) {
        try {
            await markSettled({ orderId: event.currentTarget.dataset.id });
            this.toast('Done', 'Order settled.', 'success');
            this.refresh();
        } catch (error) {
            this.toast('Error', error?.body?.message || error?.message || 'Action failed.', 'error');
        }
    }

    toast(title, message, variant) {
        this.dispatchEvent(new ShowToastEvent({ title, message, variant }));
    }
}
