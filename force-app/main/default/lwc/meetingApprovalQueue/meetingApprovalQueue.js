import approveMeetingPlan from '@salesforce/apex/MeetingPlannerController.approveMeetingPlan';
import getPendingMeetingApprovals from '@salesforce/apex/MeetingPlannerController.getPendingMeetingApprovals';
import rejectMeetingPlan from '@salesforce/apex/MeetingPlannerController.rejectMeetingPlan';
import { LightningElement, wire } from 'lwc';
import { refreshApex } from '@salesforce/apex';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';

export default class MeetingApprovalQueue extends LightningElement {
    wiredResult;
    rows = [];
    rejectionReasonByMeetingId = {};

    @wire(getPendingMeetingApprovals)
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
                    : '—'
            }));
        } else if (result.error) {
            this.rows = [];
        }
    }

    get hasRows() {
        return this.rows.length > 0;
    }

    handleRejectionChange(event) {
        this.rejectionReasonByMeetingId = {
            ...this.rejectionReasonByMeetingId,
            [event.target.dataset.meetingId]: event.detail.value
        };
    }

    async handleApprove(event) {
        const meetingId = event.target.dataset.meetingId;
        try {
            await approveMeetingPlan({ meetingId });
            this.showToast('Approved', 'Meeting approved.', 'success');
            await refreshApex(this.wiredResult);
        } catch (error) {
            this.showToast('Approve failed', this.reduceError(error), 'error');
        }
    }

    async handleReject(event) {
        const meetingId = event.target.dataset.meetingId;
        const rejectionReason = (this.rejectionReasonByMeetingId[meetingId] || '').trim();
        if (!rejectionReason) {
            this.showToast('Rejection reason required', 'Enter a reason before rejecting.', 'error');
            return;
        }
        try {
            await rejectMeetingPlan({ meetingId, rejectionReason });
            this.showToast('Rejected', 'Meeting rejected.', 'success');
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