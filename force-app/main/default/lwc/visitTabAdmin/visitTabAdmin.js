import { LightningElement, track } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import getMatrix from '@salesforce/apex/VisitTabConfigController.getMatrix';
import saveMatrix from '@salesforce/apex/VisitTabConfigController.saveMatrix';

export default class VisitTabAdmin extends LightningElement {
    @track columns = [];
    @track rows = [];
    isLoading = true;
    isSaving = false;
    errorMessage;
    _savedSignature = '';

    connectedCallback() {
        this.loadMatrix();
    }

    get saveDisabled() {
        return this.isLoading || this.isSaving || !this.isDirty;
    }

    get isDirty() {
        return this.signature() !== this._savedSignature;
    }

    get saveLabel() {
        return this.isDirty ? 'Save changes' : 'Saved';
    }

    get hasRows() {
        return this.rows.length > 0;
    }

    get showEmptyState() {
        return !this.hasRows && !this.errorMessage;
    }

    async loadMatrix() {
        this.isLoading = true;
        this.errorMessage = undefined;
        try {
            const matrix = await getMatrix();
            this.applyMatrix(matrix);
        } catch (error) {
            this.columns = [];
            this.rows = [];
            this.errorMessage =
                error?.body?.message || error?.message || 'Unable to load visit tabs.';
        } finally {
            this.isLoading = false;
        }
    }

    applyMatrix(matrix) {
        this.columns = (matrix?.columns || []).map((column) => ({ ...column }));
        this.rows = (matrix?.rows || []).map((row) => this.decorateRow(row));
        this._savedSignature = this.signature();
    }

    decorateRow(row) {
        // Two record types can share a developer name, so rows key on the record type Id.
        const rowKey = row.recordTypeId || row.developerName;
        const cells = (row.cells || []).map((cell) => ({
            ...cell,
            inputId: `${rowKey}-${cell.key}`,
            keyToken: `${rowKey}-${cell.key}-${cell.enabled ? '1' : '0'}`,
            ariaLabel: `${row.label}, ${this.labelFor(cell.key)}`
        }));
        return { ...row, rowKey, cells };
    }

    labelFor(key) {
        return this.columns.find((column) => column.key === key)?.label || key;
    }

    signature() {
        return JSON.stringify(
            this.rows.map((row) => ({
                recordTypeId: row.recordTypeId,
                developerName: row.developerName,
                label: row.label,
                tabs: row.cells.filter((cell) => cell.enabled).map((cell) => cell.key)
            }))
        );
    }

    handleToggle(event) {
        const rowKey = event.currentTarget.dataset.record;
        const tabKey = event.currentTarget.dataset.tab;
        const enabled = event.currentTarget.checked === true;
        // Visit tabs are saved per developer name, so record types that share one move together.
        const target = this.rows.find((row) => row.rowKey === rowKey);
        const developerName = target?.developerName;
        this.rows = this.rows.map((row) => {
            if (row.rowKey !== rowKey && (!developerName || row.developerName !== developerName)) {
                return row;
            }
            return {
                ...row,
                cells: row.cells.map((cell) => {
                    if (cell.key !== tabKey || cell.locked) {
                        return cell;
                    }
                    const next = { ...cell, enabled };
                    next.keyToken = `${row.rowKey}-${cell.key}-${enabled ? '1' : '0'}`;
                    return next;
                })
            };
        });
    }

    async handleSave() {
        if (!this.isDirty) {
            return;
        }
        this.isSaving = true;
        try {
            const matrix = await saveMatrix({ rowsJson: this.signature() });
            this.applyMatrix(matrix);
            this.dispatchEvent(
                new ShowToastEvent({
                    title: 'Visit tabs saved',
                    message: 'Each account type will show the sections you left on.',
                    variant: 'success'
                })
            );
        } catch (error) {
            this.dispatchEvent(
                new ShowToastEvent({
                    title: 'Save failed',
                    message: error?.body?.message || error?.message || 'Unable to save visit tabs.',
                    variant: 'error'
                })
            );
        } finally {
            this.isSaving = false;
        }
    }
}
