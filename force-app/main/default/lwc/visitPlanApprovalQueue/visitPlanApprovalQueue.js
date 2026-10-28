import { LightningElement } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import loadPendingPlanApprovals from '@salesforce/apex/VisitValidationController.loadPendingPlanApprovals';
import approvePlanVisit from '@salesforce/apex/FieldPlannerController.approvePlanVisit';
import rejectPlanVisit from '@salesforce/apex/VisitValidationController.rejectPlanVisit';

export default class VisitPlanApprovalQueue extends LightningElement {
    rows = [];
    rejectionReasonByVisitId = {};

    connectedCallback() {
        this.loadRows();
    }

    // Imperative, non-cacheable load so newly submitted plans show without a hard reload.
    async loadRows() {
        try {
            const data = await loadPendingPlanApprovals();
            this.rows = (data || []).map((row) => ({
                ...row,
                startLabel: row.startDateTime
                    ? new Date(row.startDateTime).toLocaleString([], {
                          month: 'short',
                          day: 'numeric',
                          hour: '2-digit',
                          minute: '2-digit'
                      })
                    : '—'
            }));
        } catch (error) {
            this.rows = [];
            this.showToast('Could not load the queue', this.reduceError(error), 'error');
        }
    }

    get hasRows() {
        return this.rows.length > 0;
    }

    handleRejectionChange(event) {
        this.rejectionReasonByVisitId = {
            ...this.rejectionReasonByVisitId,
            [event.target.dataset.visitId]: event.detail.value
        };
    }

    async handleApprove(event) {
        const visitId = event.target.dataset.visitId;
        try {
            await approvePlanVisit({ visitId });
            this.showToast('Approved', 'Visit plan is now scheduled.', 'success');
            await this.loadRows();
        } catch (error) {
            this.showToast('Approve failed', this.reduceError(error), 'error');
        }
    }

    async handleReject(event) {
        const visitId = event.target.dataset.visitId;
        const rejectionReason = (this.rejectionReasonByVisitId[visitId] || '').trim();
        if (!rejectionReason) {
            this.showToast('Rejection reason required', 'Enter a reason before rejecting.', 'error');
            return;
        }
        try {
            await rejectPlanVisit({ visitId, rejectionReason });
            this.showToast('Rejected', 'Visit returned to Draft for the rep.', 'success');
            await this.loadRows();
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