import { LightningElement, api, track } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import getCreateContext from '@salesforce/apex/FieldOrderService.getCreateContext';
import saveAndSubmit from '@salesforce/apex/FieldOrderService.saveAndSubmit';

let lineSeq = 0;

export default class FieldOrderSheet extends LightningElement {
    @api accountId;
    @api accountName;
    @api visitId;
    @api source = 'Home';
    @api open = false;

    @track lines = [];
    isLoading = true;
    isSaving = false;
    errorMessage;
    productOptions = [];
    distributorOptions = [];
    accountHints = [];
    chosenAccountId;
    chosenAccountName;
    chosenVisitId;
    chosenIconName;
    chosenRecordTypeLabel;
    accountInvalid = false;
    orderType = 'Direct';
    distributorName;
    branchName;
    notes = '';
    totalQuantity = 0;

    orderTypeOptions = [
        { label: 'Zeta Direct', value: 'Direct' },
        { label: 'Distributor', value: 'Distributor' }
    ];

    connectedCallback() {
        if (this.open) {
            this.lockPage(true);
            this.loadContext();
        }
    }

    disconnectedCallback() {
        this.lockPage(false);
    }

    renderedCallback() {
        if (!this._focusSheet || !this.open || this.isLoading) {
            return;
        }
        this._focusSheet = false;
        this.template.querySelector('.sheet')?.focus();
    }

    @api
    openSheet(options = {}) {
        if (options.accountId) this.accountId = options.accountId;
        if (options.visitId) this.visitId = options.visitId;
        if (options.source) this.source = options.source;
        this.open = true;
        this.lockPage(true);
        this.loadContext();
    }

    @api
    closeSheet() {
        this.open = false;
        this.lockPage(false);
        this.dispatchEvent(new CustomEvent('close'));
    }

    get isOpen() {
        return this.open === true;
    }

    get accountLocked() {
        return Boolean(this.accountId);
    }

    get isDistributor() {
        return this.orderType === 'Distributor';
    }

    get routingHint() {
        if (this.totalQuantity > 200) {
            return 'More than 200 units must go through a distributor.';
        }
        if (this.totalQuantity > 0 && this.totalQuantity <= 10) {
            return '10 units or fewer go to finance. Your manager and Yasser are still told.';
        }
        return '';
    }

    async loadContext() {
        this.isLoading = true;
        this.errorMessage = undefined;
        try {
            const ctx = await getCreateContext({
                accountId: this.accountId || null,
                visitId: this.visitId || null
            });
            if (ctx?.ordersEnabled === false) {
                this.errorMessage = 'Orders are turned off for the field app.';
            }
            this.productOptions = ctx?.productOptions || [];
            this.distributorOptions = ctx?.distributorOptions || [];
            this.accountHints = ctx?.accountHints || [];
            this.chosenAccountId = ctx?.defaultAccountId || this.accountId || null;
            this.chosenAccountName = ctx?.defaultAccountName || this.accountName || null;
            this.chosenVisitId = ctx?.defaultVisitId || this.visitId || null;
            this.chosenIconName = ctx?.defaultIconName || null;
            this.chosenRecordTypeLabel = ctx?.defaultRecordTypeLabel || null;
            this.accountInvalid = false;
            this._focusSheet = true;
            this.lines = [this.blankLine()];
            this.recalcTotal();
        } catch (error) {
            this.errorMessage = error?.body?.message || error?.message || 'Unable to open order form.';
        } finally {
            this.isLoading = false;
        }
    }

    blankLine() {
        lineSeq += 1;
        return {
            key: `line-${lineSeq}`,
            productId: this.productOptions[0]?.value || '',
            quantity: 1,
            discountPercent: '',
            foc: false
        };
    }

    recalcTotal() {
        this.totalQuantity = (this.lines || []).reduce(
            (sum, row) => sum + (Number(row.quantity) || 0),
            0
        );
        if (this.totalQuantity > 200) {
            this.orderType = 'Distributor';
        }
    }

    handleClose() {
        this.closeSheet();
    }

    handleSheetClick(event) {
        event.stopPropagation();
    }

    handleSheetKeydown(event) {
        if (event.key === 'Escape') {
            event.preventDefault();
            this.closeSheet();
        }
    }

    handleAccountChange(event) {
        this.applyAccount(event.detail);
    }

    handleOrderTypeChange(event) {
        this.orderType = event.detail.value;
    }

    handleDistributorChange(event) {
        this.distributorName = event.detail.value;
    }

    handleBranchChange(event) {
        this.branchName = event.detail.value;
    }

    handleNotesChange(event) {
        this.notes = event.detail.value;
    }

    handleLineChange(event) {
        const key = event.currentTarget.dataset.key;
        const field = event.currentTarget.dataset.field;
        const value = field === 'foc' ? event.detail.checked === true : event.detail.value;
        this.lines = this.lines.map((row) =>
            row.key === key ? { ...row, [field]: value } : row
        );
        this.recalcTotal();
    }

    handleAddLine() {
        this.lines = [...this.lines, this.blankLine()];
    }

    handleRemoveLine(event) {
        const key = event.currentTarget.dataset.key;
        this.lines = this.lines.filter((row) => row.key !== key);
        if (!this.lines.length) {
            this.lines = [this.blankLine()];
        }
        this.recalcTotal();
    }

    handleSaveDraft() {
        return this.persist(false);
    }

    handleSubmit() {
        return this.persist(true);
    }

    async persist(submitNow) {
        if (!this.chosenAccountId) {
            this.accountInvalid = true;
            this.errorMessage = 'Choose an account for this order.';
            this.template.querySelector('c-field-account-lookup')?.focus();
            return;
        }
        this.isSaving = true;
        this.errorMessage = undefined;
        try {
            const order = await saveAndSubmit({
                input: {
                    accountId: this.chosenAccountId,
                    visitId: this.chosenVisitId || null,
                    orderType: this.orderType,
                    distributorName: this.distributorName,
                    branchName: this.branchName,
                    notes: this.notes,
                    source: this.source || 'Home',
                    submitNow,
                    lines: this.lines.map((row) => ({
                        productId: row.productId,
                        quantity: Number(row.quantity),
                        discountPercent:
                            row.discountPercent === '' || row.discountPercent == null
                                ? null
                                : Number(row.discountPercent),
                        foc: row.foc === true,
                        notes: null
                    }))
                }
            });
            this.dispatchEvent(
                new ShowToastEvent({
                    title: submitNow ? 'Order submitted' : 'Draft saved',
                    message: submitNow
                        ? order.skipFullApproval
                            ? 'Sent to Finance (qty ≤ 10).'
                            : 'Sent to your DM for approval.'
                        : 'You can submit when ready.',
                    variant: 'success'
                })
            );
            this.dispatchEvent(new CustomEvent('created', { detail: { order } }));
            this.closeSheet();
        } catch (error) {
            this.errorMessage =
                error?.body?.message || error?.message || 'Unable to save this order.';
        } finally {
            this.isSaving = false;
        }
    }

    applyAccount(detail) {
        if (this.accountLocked) {
            return;
        }
        const next = detail || {};
        this.chosenAccountId = next.accountId || null;
        this.chosenAccountName = next.accountName || null;
        this.chosenIconName = next.iconName || null;
        this.chosenRecordTypeLabel = next.recordTypeLabel || null;
        if (!this.chosenAccountId) {
            this.chosenVisitId = null;
        } else if (next.visitId) {
            this.chosenVisitId = next.visitId;
        } else if (this.chosenAccountId === this.accountId) {
            this.chosenVisitId = this.visitId || null;
        } else {
            this.chosenVisitId = null;
        }
        if (this.chosenAccountId) {
            this.accountInvalid = false;
            this.errorMessage = undefined;
        }
    }

    lockPage(locked) {
        if (typeof document === 'undefined') {
            return;
        }
        if (locked) {
            if (this._scrollLock != null) {
                return;
            }
            this._scrollLock = document.documentElement.style.overflow;
            document.documentElement.style.overflow = 'hidden';
            return;
        }
        if (this._scrollLock == null) {
            return;
        }
        document.documentElement.style.overflow = this._scrollLock;
        this._scrollLock = null;
    }
}
