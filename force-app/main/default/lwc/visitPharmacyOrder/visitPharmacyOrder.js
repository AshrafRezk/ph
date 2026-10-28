import { LightningElement, api } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import getOrderContext from '@salesforce/apex/VisitPharmacyController.getOrderContext';
import saveOrder from '@salesforce/apex/VisitPharmacyController.saveOrder';

let lineSeq = 0;

export default class VisitPharmacyOrder extends LightningElement {
    @api visitId;
    @api disabled = false;

    products = [];
    lines = [];
    notes = '';
    status = 'Draft';
    emptyReason = '';
    isLoading = false;
    isSaving = false;

    connectedCallback() {
        this.refreshContext();
    }

    get statusOptions() {
        return [
            { label: 'Draft', value: 'Draft' },
            { label: 'Submitted', value: 'Submitted' }
        ];
    }

    get productOptions() {
        return (this.products || []).map((row) => ({
            label: row.productName,
            value: row.productId
        }));
    }

    get hasProducts() {
        return (this.products || []).length > 0;
    }

    get saveDisabled() {
        return this.disabled || this.isSaving || !this.hasProducts || !this.hasValidLine;
    }

    get hasValidLine() {
        return (this.lines || []).some((row) => row.productId && Number(row.quantity) >= 1);
    }

    get displayLines() {
        return this.lines;
    }

    async refreshContext() {
        if (!this.visitId) {
            return;
        }
        this.isLoading = true;
        try {
            const context = await getOrderContext({ visitId: this.visitId });
            this.products = context.products || [];
            this.emptyReason = context.emptyReason || '';
            this.notes = context.order?.notes || '';
            this.status = context.order?.status || 'Draft';
            const existing = context.order?.lines || [];
            this.lines = existing.length
                ? existing.map((row) => this.toLine(row))
                : [this.blankLine()];
        } catch (error) {
            this.showToast('Order', this.reduceError(error), 'error');
        } finally {
            this.isLoading = false;
        }
    }

    toLine(row) {
        lineSeq += 1;
        return {
            key: row.id || `line-${lineSeq}`,
            productId: row.productId || '',
            quantity: row.quantity == null ? 1 : row.quantity,
            notes: row.notes || ''
        };
    }

    blankLine() {
        lineSeq += 1;
        return {
            key: `line-${lineSeq}`,
            productId: this.productOptions[0]?.value || '',
            quantity: 1,
            notes: ''
        };
    }

    handleStatusChange(event) {
        this.status = event.detail.value;
    }

    handleNotesChange(event) {
        this.notes = event.detail.value;
    }

    handleLineChange(event) {
        const key = event.currentTarget.dataset.key;
        const field = event.currentTarget.dataset.field;
        this.lines = this.lines.map((row) => {
            if (row.key !== key) {
                return row;
            }
            return { ...row, [field]: event.detail.value };
        });
    }

    handleAddLine() {
        this.lines = [...this.lines, this.blankLine()];
    }

    handleRemoveLine(event) {
        const key = event.currentTarget.dataset.key;
        const remaining = this.lines.filter((row) => row.key !== key);
        this.lines = remaining.length ? remaining : [this.blankLine()];
    }

    async handleSave() {
        this.isSaving = true;
        try {
            const saved = await saveOrder({
                visitId: this.visitId,
                status: this.status,
                notes: this.notes,
                lines: this.lines
                    .filter((row) => row.productId && Number(row.quantity) >= 1)
                    .map((row) => ({
                        productId: row.productId,
                        quantity: Number(row.quantity),
                        notes: row.notes
                    }))
            });
            this.notes = saved.notes || '';
            this.status = saved.status || 'Draft';
            this.lines = (saved.lines || []).map((row) => this.toLine(row));
            this.showToast('Order saved', 'Pharmacy order saved against this visit.', 'success');
        } catch (error) {
            this.showToast('Order', this.reduceError(error), 'error');
        } finally {
            this.isSaving = false;
        }
    }

    showToast(title, message, variant) {
        this.dispatchEvent(new ShowToastEvent({ title, message, variant }));
    }

    reduceError(error) {
        if (Array.isArray(error?.body)) {
            return error.body.map((item) => item.message).join(', ');
        }
        return error?.body?.message || error?.message || 'Unexpected error';
    }
}