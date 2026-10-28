import approveRequest from '@salesforce/apex/TimeOffRequestController.approveRequest';
import getPendingApprovals from '@salesforce/apex/TimeOffRequestController.getPendingApprovals';
import rejectRequest from '@salesforce/apex/TimeOffRequestController.rejectRequest';
import { LightningElement, wire } from 'lwc';
import { refreshApex } from '@salesforce/apex';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';

export default class TimeOffApprovalQueue extends LightningElement {
    wiredResult;
    rows = [];
    rejectionReasonByRequestId = {};

    @wire(getPendingApprovals)
    wiredApprovals(result) {
        this.wiredResult = result;
        if (result.data) {
            this.rows = result.data.map((row) => ({
                ...row,
                startLabel: row.startDateTime
                    ? new Date(row.startDateTime).toLocaleString([], {
                          month: 'short',
                          day: 'numeric',
                          hour: '2-digit',
                          minute: '2-digit'
                      })
                    : '—',
                mendixHint: 'Approve here or open Mendix via SSO for HR workflow.'
            }));
        } else if (result.error) {
            this.rows = [];
        }
    }

    get hasRows() {
        return this.rows.length > 0;
    }

    handleRejectionChange(event) {
        this.rejectionReasonByRequestId = {
            ...this.rejectionReasonByRequestId,
            [event.target.dataset.requestId]: event.detail.value
        };
    }

    async handleApprove(event) {
        const requestId = event.target.dataset.requestId;
        try {
            await approveRequest({ requestId });
            this.showToast('Approved', 'Time off request approved.', 'success');
            await refreshApex(this.wiredResult);
        } catch (error) {
            this.showToast('Approve failed', this.reduceError(error), 'error');
        }
    }

    async handleReject(event) {
        const requestId = event.target.dataset.requestId;
        const rejectionReason = (this.rejectionReasonByRequestId[requestId] || '').trim();
        if (!rejectionReason) {
            this.showToast('Rejection reason required', 'Enter a reason before rejecting.', 'error');
            return;
        }
        try {
            await rejectRequest({ requestId, rejectionReason });
            this.showToast('Rejected', 'Time off request rejected.', 'success');
            await refreshApex(this.wiredResult);
        } catch (error) {
            this.showToast('Reject failed', this.reduceError(error), 'error');
        }
    }

    showToast(title, message, variant) {
        this.dispatchEvent(new ShowToastEvent({ title, message, variant }));
    }

    reduceError(error) {
        return error?.body?.message || error?.message || 'Unexpected error';
    }
}