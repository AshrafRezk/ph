import { LightningElement, api, wire } from 'lwc';
import getSampleInventoryForUser from '@salesforce/apex/VisitCallReportController.getSampleInventoryForUser';

export default class VisitSampleGrid extends LightningElement {
    @api samples = [];
    @api attendees = [];
    @api disabled = false;

    inventoryOptions = [];

    @wire(getSampleInventoryForUser)
    wiredInventory({ data }) {
        if (data) {
            this.inventoryOptions = data.map((row) => ({
                label: `${row.productName} · Lot ${row.lotNumber} (${row.quantityOnHand})`,
                value: row.id,
                row
            }));
        }
    }

    get displaySamples() {
        return (this.samples || []).map((row, index) => ({
            ...row,
            key: row.id || `sample-${index}`,
            imageUrl: row.imageUrl || this.resolveImageUrl(row)
        }));
    }

    resolveImageUrl(row) {
        if (!row.sampleInventoryId) {
            return null;
        }
        const inv = (this.inventoryOptions || []).find((opt) => opt.value === row.sampleInventoryId);
        return inv?.row?.imageUrl || null;
    }

    get attendeeOptions() {
        return (this.attendees || []).map((row) => ({
            label: row.accountName,
            value: row.id || row.accountId
        }));
    }

    handleAddRow() {
        if (this.disabled) {
            return;
        }
        const next = [
            ...(this.samples || []),
            {
                productId: null,
                productName: '',
                visitAttendeeId: null,
                attendeeName: '',
                quantity: 1,
                lotNumber: '',
                sampleInventoryId: null
            }
        ];
        this.emitChange(next);
    }

    handleRemoveRow(event) {
        const index = Number(event.currentTarget.dataset.index);
        const next = (this.samples || []).filter((_, idx) => idx !== index);
        this.emitChange(next);
    }

    handleFieldChange(event) {
        const index = Number(event.target.dataset.index);
        const field = event.target.dataset.field;
        const value = event.detail.value;
        const next = (this.samples || []).map((row, idx) => {
            if (idx !== index) {
                return row;
            }
            if (field === 'sampleInventoryId') {
                const inv = (this.inventoryOptions || []).find((opt) => opt.value === value);
                return {
                    ...row,
                    sampleInventoryId: value,
                    productId: inv?.row?.productId,
                    productName: inv?.row?.productName,
                    imageUrl: inv?.row?.imageUrl,
                    lotNumber: inv?.row?.lotNumber,
                    inventoryOnHand: inv?.row?.quantityOnHand,
                    inventoryExpiry: inv?.row?.expiryDate
                };
            }
            if (field === 'visitAttendeeId') {
                const attendee = (this.attendees || []).find(
                    (a) => (a.id || a.accountId) === value
                );
                return {
                    ...row,
                    visitAttendeeId: value,
                    attendeeName: attendee?.accountName
                };
            }
            return { ...row, [field]: value };
        });
        this.emitChange(next);
    }

    emitChange(samples) {
        this.dispatchEvent(
            new CustomEvent('sampleschange', {
                detail: { samples },
                bubbles: true,
                composed: true
            })
        );
    }
}
