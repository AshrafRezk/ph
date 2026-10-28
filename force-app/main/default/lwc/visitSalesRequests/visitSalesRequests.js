import { LightningElement, api, track, wire } from 'lwc';
import { refreshApex } from '@salesforce/apex';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import getRequestsForVisit from '@salesforce/apex/SalesRequestService.getRequestsForVisit';
import createRequest from '@salesforce/apex/SalesRequestService.createRequest';
import approveRequest from '@salesforce/apex/SalesRequestService.approve';
import rejectRequest from '@salesforce/apex/SalesRequestService.reject';

const TYPE_OPTIONS = [
    { label: 'Device', value: 'Device' },
    { label: 'Sample', value: 'Sample' },
    { label: 'Product', value: 'Product' },
    { label: 'Other', value: 'Other' }
];

export default class VisitSalesRequests extends LightningElement {
    @api recordId; // when placed directly on a Visit record page
    @api visitId; // when embedded in the visit workspace
    @api accountId;

    @track rows = [];
    @track showForm = false;
    @track saving = false;

    draft = { requestType: 'Device', itemName: '', quantity: null, details: '' };
    typeOptions = TYPE_OPTIONS;
    _wired;

    get effectiveVisitId() {
        return this.visitId || this.recordId;
    }

    @wire(getRequestsForVisit, { visitId: '$effectiveVisitId' })
    wiredRequests(result) {
        this._wired = result;
        if (result.data) {
            this.rows = result.data.map((r) => this.decorate(r));
        }
    }

    decorate(r) {
        return {
            ...r,
            isPending: r.status === 'Pending Approval',
            isApproved: r.status === 'Approved',
            isRejected: r.status === 'Rejected',
            badgeClass:
                'slds-badge ' +
                (r.status === 'Approved'
                    ? 'slds-theme_success'
                    : r.status === 'Rejected'
                    ? 'slds-theme_error'
                    : 'slds-theme_warning'),
            quantityLabel: r.quantity == null ? '' : String(r.quantity)
        };
    }

    get hasRows() {
        return this.rows && this.rows.length > 0;
    }

    handleNew() {
        this.draft = { requestType: 'Device', itemName: '', quantity: null, details: '' };
        this.showForm = true;
    }

    handleCancel() {
        this.showForm = false;
    }

    handleChange(event) {
        const field = event.target.dataset.field;
        this.draft = { ...this.draft, [field]: event.target.value };
    }

    async handleSave() {
        if (!this.draft.itemName) {
            this.toast('Missing info', 'Enter the item requested.', 'warning');
            return;
        }
        this.saving = true;
        try {
            await createRequest({
                input: {
                    visitId: this.effectiveVisitId,
                    accountId: this.accountId,
                    requestType: this.draft.requestType,
                    itemName: this.draft.itemName,
                    quantity: this.draft.quantity ? Number(this.draft.quantity) : null,
                    details: this.draft.details
                }
            });
            this.toast('Submitted', 'Request sent to your DM for approval.', 'success');
            this.showForm = false;
            await refreshApex(this._wired);
        } catch (e) {
            this.toast('Could not submit', this.errMsg(e), 'error');
        } finally {
            this.saving = false;
        }
    }

    async handleApprove(event) {
        const id = event.target.dataset.id;
        try {
            await approveRequest({ requestId: id });
            this.toast('Approved', 'Request approved.', 'success');
            await refreshApex(this._wired);
        } catch (e) {
            this.toast('Could not approve', this.errMsg(e), 'error');
        }
    }

    async handleReject(event) {
        const id = event.target.dataset.id;
        // eslint-disable-next-line no-alert
        const reason = window.prompt('Reason for rejection:');
        if (reason === null) {
            return;
        }
        if (!reason.trim()) {
            this.toast('Missing reason', 'A rejection reason is required.', 'warning');
            return;
        }
        try {
            await rejectRequest({ requestId: id, reason });
            this.toast('Rejected', 'Request rejected.', 'success');
            await refreshApex(this._wired);
        } catch (e) {
            this.toast('Could not reject', this.errMsg(e), 'error');
        }
    }

    errMsg(e) {
        return (e && e.body && e.body.message) || (e && e.message) || 'Unexpected error';
    }

    toast(title, message, variant) {
        this.dispatchEvent(new ShowToastEvent({ title, message, variant }));
    }
}