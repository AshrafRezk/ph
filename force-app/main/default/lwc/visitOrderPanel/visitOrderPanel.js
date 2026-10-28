import { LightningElement, api, track } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import getFieldOrder from '@salesforce/apex/FieldVisitWorkflowController.getFieldOrder';
import saveFieldOrder from '@salesforce/apex/FieldVisitWorkflowController.saveFieldOrder';
import submitFieldOrder from '@salesforce/apex/FieldVisitWorkflowController.submitFieldOrder';

let lineSeq = 0;

export default class VisitOrderPanel extends LightningElement {
    @api visitId;
    @api disabled = false;

    isLoading = true;
    errorMessage;
    status = 'Draft';
    productOptions = [];
    @track lines = [];
    draftProductId = '';
    draftQuantity = 1;

    connectedCallback() {
        this.load();
    }

    get hasLines() {
        return (this.lines || []).length > 0;
    }

    get statusLabel() {
        return this.status || 'Draft';
    }

    get isSubmitted() {
        return this.status === 'Submitted';
    }

    get editDisabled() {
        return this.disabled || this.isSubmitted;
    }

    get addDisabled() {
        return this.editDisabled || !this.draftProductId;
    }

    async load() {
        if (!this.visitId) {
            return;
        }
        this.isLoading = true;
        this.errorMessage = undefined;
        try {
            const payload = await getFieldOrder({ visitId: this.visitId });
            this.applyPayload(payload);
        } catch (error) {
            this.errorMessage = error?.body?.message || error?.message || 'Unable to load order.';
        } finally {
            this.isLoading = false;
        }
    }

    applyPayload(payload) {
        this.status = payload?.status || 'Draft';
        this.productOptions = (payload?.productOptions || []).map((row) => ({
            label: row.label || row.productName,
            value: row.value || row.productId
        }));
        this.lines = (payload?.lines || []).map((line) => this.toLine(line));
    }

    toLine(line) {
        lineSeq += 1;
        return {
            key: line.id || `new-${lineSeq}`,
            productId: line.productId,
            productName:
                line.productName ||
                this.productOptions.find((option) => option.value === line.productId)?.label ||
                'Product',
            quantity: line.quantity || 1
        };
    }

    handleDraftProduct(event) {
        this.draftProductId = event.detail.value;
    }
    handleDraftQuantity(event) {
        this.draftQuantity = Number(event.detail.value || 1);
    }

    handleAddLine() {
        const option = this.productOptions.find((row) => row.value === this.draftProductId);
        this.lines = [
            ...this.lines,
            this.toLine({
                productId: this.draftProductId,
                productName: option?.label,
                quantity: this.draftQuantity
            })
        ];
        this.draftProductId = '';
        this.draftQuantity = 1;
    }

    handleRemove(event) {
        const key = event.currentTarget.dataset.key;
        this.lines = this.lines.filter((line) => line.key !== key);
    }

    linePayload() {
        return this.lines.map((line) => ({
            productId: line.productId,
            quantity: line.quantity
        }));
    }

    async handleSave() {
        try {
            const payload = await saveFieldOrder({ visitId: this.visitId, lines: this.linePayload() });
            this.applyPayload(payload);
            this.toast('Order saved', 'success');
        } catch (error) {
            this.toast('Unable to save order', 'error', error);
        }
    }

    async handleSubmit() {
        try {
            await saveFieldOrder({ visitId: this.visitId, lines: this.linePayload() });
            const payload = await submitFieldOrder({ visitId: this.visitId });
            this.applyPayload(payload);
            this.toast('Order submitted', 'success');
        } catch (error) {
            this.toast('Unable to submit order', 'error', error);
        }
    }

    toast(title, variant, error) {
        this.dispatchEvent(
            new ShowToastEvent({
                title,
                message: error ? error?.body?.message || error?.message : '',
                variant
            })
        );
    }
}
