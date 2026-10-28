import { LightningElement, api } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import getFieldEmailContext from '@salesforce/apex/FieldVisitWorkflowController.getFieldEmailContext';
import sendFieldEmail from '@salesforce/apex/FieldVisitWorkflowController.sendFieldEmail';

export default class VisitFieldEmailModal extends LightningElement {
    @api visitId;

    isLoading = true;
    isSending = false;
    errorMessage;
    toAddress = '';
    subject = '';
    body = '';

    connectedCallback() {
        this.load();
    }

    get sendDisabled() {
        return (
            this.isLoading ||
            this.isSending ||
            !(this.toAddress || '').includes('@') ||
            !(this.subject || '').trim() ||
            !(this.body || '').trim()
        );
    }

    async load() {
        this.isLoading = true;
        try {
            const context = await getFieldEmailContext({ visitId: this.visitId });
            this.toAddress = context?.toAddress || '';
            this.subject = context?.defaultSubject || 'Visit follow-up';
            this.body = context?.accountName
                ? `Dear colleague,\n\nThank you for the time today at ${context.accountName}.\n\nBest regards`
                : 'Dear colleague,\n\nThank you for the time today.\n\nBest regards';
        } catch (error) {
            this.errorMessage = error?.body?.message || error?.message || 'Unable to load email.';
        } finally {
            this.isLoading = false;
        }
    }

    handleTo(event) {
        this.toAddress = event.detail.value;
    }
    handleSubject(event) {
        this.subject = event.detail.value;
    }
    handleBody(event) {
        this.body = event.detail.value;
    }

    handleClose() {
        this.dispatchEvent(new CustomEvent('close'));
    }

    async handleSend() {
        this.isSending = true;
        try {
            await sendFieldEmail({
                visitId: this.visitId,
                toAddress: this.toAddress,
                subject: this.subject,
                body: this.body
            });
            this.dispatchEvent(new ShowToastEvent({ title: 'Email sent', variant: 'success' }));
            this.dispatchEvent(new CustomEvent('sent'));
            this.handleClose();
        } catch (error) {
            this.dispatchEvent(
                new ShowToastEvent({
                    title: 'Unable to send email',
                    message: error?.body?.message || error?.message,
                    variant: 'error'
                })
            );
        } finally {
            this.isSending = false;
        }
    }
}
