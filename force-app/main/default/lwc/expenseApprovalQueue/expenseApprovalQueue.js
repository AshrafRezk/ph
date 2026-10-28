import approveExpense from '@salesforce/apex/ExpenseSubmissionController.approveExpense';
import getPendingExpenseApprovals from '@salesforce/apex/ExpenseSubmissionController.getPendingExpenseApprovals';
import rejectExpense from '@salesforce/apex/ExpenseSubmissionController.rejectExpense';
import { LightningElement, wire } from 'lwc';
import { refreshApex } from '@salesforce/apex';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';

export default class ExpenseApprovalQueue extends LightningElement {
    wiredResult;
    rows = [];
    rejectionReasonByExpenseId = {};

    @wire(getPendingExpenseApprovals)
    wiredApprovals(result) {
        this.wiredResult = result;
        if (result.data) {
            this.rows = result.data.map((row) => ({
                ...row,
                expenseDateLabel: row.expenseDate
                    ? new Date(row.expenseDate).toLocaleDateString('en-GB', {
                          day: '2-digit',
                          month: 'short',
                          year: 'numeric'
                      })
                    : '—',
                amountLabel: row.amount != null ? Number(row.amount).toLocaleString('en-EG') : '—'
            }));
        } else if (result.error) {
            this.rows = [];
        }
    }

    get hasRows() {
        return this.rows.length > 0;
    }

    get hasActionable() {
        return this.rows.some((row) => row.canAct === true);
    }

    get hasOwnPending() {
        return this.rows.some((row) => row.canAct !== true);
    }

    get subtitle() {
        if (!this.hasRows) {
            return 'Approve or reject expenses from subordinate territories.';
        }
        if (this.hasActionable && this.hasOwnPending) {
            return 'Your expenses are pending approval. Approve or reject requests from subordinate territories.';
        }
        if (this.hasActionable) {
            return 'Approve or reject expenses from subordinate territories.';
        }
        return 'Pending approval. Your manager will review these.';
    }

    handleRejectionChange(event) {
        this.rejectionReasonByExpenseId = {
            ...this.rejectionReasonByExpenseId,
            [event.target.dataset.expenseId]: event.detail.value
        };
    }

    async handleApprove(event) {
        const expenseId = event.target.dataset.expenseId;
        try {
            await approveExpense({ expenseId });
            this.showToast('Approved', 'Expense request approved.', 'success');
            await refreshApex(this.wiredResult);
        } catch (error) {
            this.showToast('Approve failed', this.reduceError(error), 'error');
        }
    }

    async handleReject(event) {
        const expenseId = event.target.dataset.expenseId;
        const rejectionReason = (this.rejectionReasonByExpenseId[expenseId] || '').trim();
        if (!rejectionReason) {
            this.showToast('Rejection reason required', 'Enter a reason before rejecting.', 'error');
            return;
        }
        try {
            await rejectExpense({ expenseId, rejectionReason });
            this.showToast('Rejected', 'Expense request rejected.', 'success');
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