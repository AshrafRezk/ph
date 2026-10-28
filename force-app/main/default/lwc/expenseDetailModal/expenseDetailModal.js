import { api } from 'lwc';
import LightningModal from 'lightning/modal';

export default class ExpenseDetailModal extends LightningModal {
    @api expenseName;
    @api typeLabel;
    @api expenseDateLabel;
    @api amountLabel;
    @api descriptionLabel;
    @api status;
    @api statusBadgeClass;
    @api managerName;
    @api rejectionReason;
    @api recordId;

    get statusHelpText() {
        if (this.status === 'Pending') {
            return 'Waiting for your manager to approve or reject this request.';
        }
        if (this.status === 'Approved') {
            return 'This expense was approved by your manager.';
        }
        if (this.status === 'Rejected') {
            return 'This expense was rejected by your manager.';
        }
        return 'Expense request status.';
    }

    get showRejectionReason() {
        return this.status === 'Rejected' && this.rejectionReason;
    }

    handleClose() {
        this.close();
    }

    handleOpenRecord() {
        this.close({ action: 'openRecord', recordId: this.recordId });
    }
}