import { LightningElement, track } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import getSetup from '@salesforce/apex/SfeApproverAdminController.getSetup';
import newRow from '@salesforce/apex/SfeApproverAdminController.newRow';
import saveRows from '@salesforce/apex/SfeApproverAdminController.saveRows';

const ACTIVE_USERS = {
    criteria: [{ fieldPath: 'IsActive', operator: 'eq', value: true }]
};

function lineKey(value) {
    return String(value || '').trim().toLowerCase();
}

function reduceError(error, fallback) {
    return error?.body?.message || error?.message || fallback;
}

export default class SfeApproverAdmin extends LightningElement {
    @track rows = [];
    businessUnits = [];
    canEdit = false;
    isLoading = true;
    isSaving = false;
    errorMessage;
    pickedUserId = null;
    userFilter = ACTIVE_USERS;
    _savedSignature = '';

    connectedCallback() {
        this.load();
    }

    get readOnly() {
        return !this.canEdit || this.isSaving;
    }

    get isDirty() {
        return this.signature() !== this._savedSignature;
    }

    get saveLabel() {
        return this.isDirty ? 'Save changes' : 'Saved';
    }

    get saveDisabled() {
        return this.isLoading || this.isSaving || !this.isDirty;
    }

    get addDisabled() {
        return this.isSaving || !this.pickedUserId;
    }

    get hasRows() {
        return this.rows.length > 0;
    }

    get showEmptyState() {
        return !this.hasRows && !this.errorMessage;
    }

    get displayRows() {
        const unitKeys = new Set(this.businessUnits.map(lineKey));
        return this.rows.map((row) => {
            const chosen = new Set(row.lines.map(lineKey));
            const extra = row.lines.filter((line) => !unitKeys.has(lineKey(line)));
            const cells = this.businessUnits.map((unit) => {
                const checked = row.allLines || chosen.has(lineKey(unit));
                const disabled = this.readOnly || row.allLines;
                return {
                    key: `${row.rowKey}-${unit}-${checked ? 1 : 0}-${disabled ? 1 : 0}`,
                    line: unit,
                    checked,
                    disabled,
                    label: `${row.approverName}, ${unit}`
                };
            });
            return {
                ...row,
                cells,
                extraLabel: !row.allLines && extra.length ? `Also: ${extra.join(', ')}` : '',
                rowClass: row.isActive ? 'sfa-row' : 'sfa-row sfa-row--off',
                allLinesLabel: `${row.approverName}, all lines`,
                classificationLabel: `${row.approverName}, Class Engine`,
                newAccountsLabel: `${row.approverName}, new accounts`,
                activeLabel: `${row.approverName}, active`,
                removeLabel: `Remove ${row.approverName}`
            };
        });
    }

    async load() {
        this.isLoading = true;
        this.errorMessage = undefined;
        try {
            this.applySetup(await getSetup());
        } catch (error) {
            this.rows = [];
            this.errorMessage = reduceError(error, 'Unable to load SFE approvers.');
        } finally {
            this.isLoading = false;
        }
    }

    applySetup(setup) {
        this.canEdit = setup?.canEdit === true;
        this.businessUnits = [...(setup?.businessUnits || [])];
        this.rows = (setup?.rows || []).map((row) => this.decorate(row));
        this._savedSignature = this.signature();
    }

    decorate(row) {
        return {
            id: row.id || null,
            rowKey: row.id || `new-${row.approverId}`,
            approverId: row.approverId,
            approverName: row.approverName || 'Unknown user',
            approverTitle: row.approverTitle || '',
            allLines: row.allLines === true,
            lines: [...(row.lines || [])],
            classification: row.classification === true,
            newAccounts: row.newAccounts === true,
            isActive: row.isActive !== false
        };
    }

    payload() {
        return this.rows.map((row) => ({
            id: row.id,
            approverId: row.approverId,
            allLines: row.allLines,
            lines: row.allLines
                ? []
                : [...row.lines].sort((a, b) => lineKey(a).localeCompare(lineKey(b))),
            classification: row.classification,
            newAccounts: row.newAccounts,
            isActive: row.isActive
        }));
    }

    signature() {
        return JSON.stringify(this.payload());
    }

    updateRow(rowKey, change) {
        this.rows = this.rows.map((row) => (row.rowKey === rowKey ? { ...row, ...change(row) } : row));
    }

    handleToggle(event) {
        const { key, field } = event.currentTarget.dataset;
        const checked = event.currentTarget.checked === true;
        this.updateRow(key, () => ({ [field]: checked }));
    }

    handleLineToggle(event) {
        const { key, line } = event.currentTarget.dataset;
        const checked = event.currentTarget.checked === true;
        this.updateRow(key, (row) => {
            const others = row.lines.filter((value) => lineKey(value) !== lineKey(line));
            return { lines: checked ? [...others, line] : others };
        });
    }

    handleRemove(event) {
        const { key } = event.currentTarget.dataset;
        this.rows = this.rows.filter((row) => row.rowKey !== key);
    }

    handlePickUser(event) {
        this.pickedUserId = event.detail?.recordId || null;
    }

    async handleAdd() {
        const userId = this.pickedUserId;
        if (!userId) {
            return;
        }
        if (this.rows.some((row) => row.approverId === userId)) {
            this.toast('Already listed', 'That user already has a row. Edit it instead.', 'warning');
            return;
        }
        try {
            const row = await newRow({ userId });
            this.rows = [...this.rows, this.decorate(row)];
            this.pickedUserId = null;
            this.template.querySelector('lightning-record-picker')?.clearSelection();
        } catch (error) {
            this.toast('Could not add approver', reduceError(error, 'Unable to add that user.'), 'error');
        }
    }

    async handleSave() {
        if (!this.isDirty) {
            return;
        }
        this.isSaving = true;
        try {
            this.applySetup(await saveRows({ rowsJson: this.signature() }));
            this.toast(
                'SFE approvers saved',
                'Class Engine and Pending SFE approvals follow these lines now.',
                'success'
            );
        } catch (error) {
            this.toast('Save failed', reduceError(error, 'Unable to save SFE approvers.'), 'error');
        } finally {
            this.isSaving = false;
        }
    }

    toast(title, message, variant) {
        this.dispatchEvent(new ShowToastEvent({ title, message, variant }));
    }
}
