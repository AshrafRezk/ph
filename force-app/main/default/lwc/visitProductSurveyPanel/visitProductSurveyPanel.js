import { LightningElement, api } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import getVisitSurveys from '@salesforce/apex/FieldVisitWorkflowController.getVisitSurveys';
import saveVisitSurvey from '@salesforce/apex/FieldVisitWorkflowController.saveVisitSurvey';

export default class VisitProductSurveyPanel extends LightningElement {
    @api visitId;
    @api disabled = false;

    isLoading = true;
    errorMessage;
    productName = '';
    productOptions = [];
    sentimentOptions = [];
    efficacy = 'Neutral';
    safety = 'Neutral';
    indication = 'Neutral';
    sideEffects = 'Neutral';
    usage = 'Neutral';
    notes = '';
    rows = [];

    connectedCallback() {
        this.load();
    }

    get hasRows() {
        return (this.rows || []).length > 0;
    }

    get saveDisabled() {
        return this.disabled || this.isLoading || !this.productName;
    }

    async load() {
        if (!this.visitId) {
            return;
        }
        this.isLoading = true;
        this.errorMessage = undefined;
        try {
            const payload = await getVisitSurveys({ visitId: this.visitId });
            this.productOptions = (payload?.productOptions || []).map((row) => ({
                label: row.label || row.productName,
                value: row.productName || row.label
            }));
            this.sentimentOptions = payload?.sentimentOptions || [
                { label: 'Positive', value: 'Positive' },
                { label: 'Neutral', value: 'Neutral' },
                { label: 'Negative', value: 'Negative' }
            ];
            this.rows = payload?.rows || [];
        } catch (error) {
            this.errorMessage = error?.body?.message || error?.message || 'Unable to load surveys.';
        } finally {
            this.isLoading = false;
        }
    }

    handleProductChange(event) {
        this.productName = event.detail.value;
    }
    handleEfficacy(event) {
        this.efficacy = event.detail.value;
    }
    handleSafety(event) {
        this.safety = event.detail.value;
    }
    handleIndication(event) {
        this.indication = event.detail.value;
    }
    handleSideEffects(event) {
        this.sideEffects = event.detail.value;
    }
    handleUsage(event) {
        this.usage = event.detail.value;
    }
    handleNotes(event) {
        this.notes = event.detail.value;
    }

    async handleSave() {
        try {
            const payload = await saveVisitSurvey({
                request: {
                    visitId: this.visitId,
                    productName: this.productName,
                    efficacy: this.efficacy,
                    safety: this.safety,
                    indication: this.indication,
                    sideEffects: this.sideEffects,
                    usage: this.usage,
                    notes: this.notes
                }
            });
            this.rows = payload?.rows || [];
            this.notes = '';
            this.dispatchEvent(
                new ShowToastEvent({ title: 'Survey saved', variant: 'success' })
            );
        } catch (error) {
            this.dispatchEvent(
                new ShowToastEvent({
                    title: 'Unable to save survey',
                    message: error?.body?.message || error?.message,
                    variant: 'error'
                })
            );
        }
    }
}
