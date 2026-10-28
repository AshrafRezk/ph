import { LightningElement, api } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import getChangeRequests from '@salesforce/apex/FieldVisitWorkflowController.getChangeRequests';
import submitChangeRequest from '@salesforce/apex/FieldVisitWorkflowController.submitChangeRequest';

export default class VisitDataChangeRequest extends LightningElement {
    @api visitId;
    @api disabled = false;

    isLoading = true;
    errorMessage;
    accountName = 'this account';
    changeType = 'Name';
    changeTypeOptions = [];
    proposedValue = '';
    reason = '';
    rows = [];

    connectedCallback() {
        this.load();
    }

    get hasRows() {
        return (this.rows || []).length > 0;
    }

    get submitDisabled() {
        return this.disabled || !this.changeType || !(this.proposedValue || '').trim();
    }

    async load() {
        if (!this.visitId) {
            return;
        }
        this.isLoading = true;
        this.errorMessage = undefined;
        try {
            const payload = await getChangeRequests({ visitId: this.visitId });
            this.accountName = payload?.accountName || 'this account';
            this.changeTypeOptions = payload?.changeTypeOptions || [];
            this.rows = payload?.requests || [];
            if (!this.changeType && this.changeTypeOptions.length) {
                this.changeType = this.changeTypeOptions[0].value;
            }
        } catch (error) {
            this.errorMessage = error?.body?.message || error?.message || 'Unable to load change requests.';
        } finally {
            this.isLoading = false;
        }
    }

    handleType(event) {
        this.changeType = event.detail.value;
    }
    handleProposed(event) {
        this.proposedValue = event.detail.value;
    }
    handleReason(event) {
        this.reason = event.detail.value;
    }

    async handleSubmit() {
        try {
            const payload = await submitChangeRequest({
                request: {
                    visitId: this.visitId,
                    changeType: this.changeType,
                    proposedValue: this.proposedValue,
                    reason: this.reason
                }
            });
            this.rows = payload?.requests || [];
            this.proposedValue = '';
            this.reason = '';
            this.dispatchEvent(new ShowToastEvent({ title: 'Change request submitted', variant: 'success' }));
        } catch (error) {
            this.dispatchEvent(
                new ShowToastEvent({
                    title: 'Unable to submit request',
                    message: error?.body?.message || error?.message,
                    variant: 'error'
                })
            );
        }
    }
}
