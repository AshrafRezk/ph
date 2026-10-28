import { LightningElement, api, track } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import getCreateContext from '@salesforce/apex/FieldRequestService.getCreateContext';
import createRequest from '@salesforce/apex/FieldRequestService.createRequest';

export default class FieldRequestSheet extends LightningElement {
    @api accountId;
    @api accountName;
    @api visitId;
    @api source = 'Home';
    @api open = false;

    @track context;
    @track accountHints = [];
    @track isLoading = true;
    @track isSaving = false;
    @track errorMessage;

    selectedKind = 'Field';
    selectedType;
    selectedUrgency = 'Normal';
    selectedProductId;
    sampleQuantity;
    summary = '';
    chosenAccountId;
    chosenAccountName;
    chosenVisitId;
    chosenIconName;
    chosenRecordTypeLabel;
    accountInvalid = false;

    urgencyOptions = [
        { label: 'Normal', value: 'Normal' },
        { label: 'Urgent', value: 'Urgent' }
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
        if (options.accountId) {
            this.accountId = options.accountId;
        }
        if (options.visitId) {
            this.visitId = options.visitId;
        }
        if (options.source) {
            this.source = options.source;
        }
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

    get medicalKindClass() {
        return `kind-btn${this.selectedKind === 'Medical' ? ' is-active' : ''}`;
    }

    get fieldKindClass() {
        return `kind-btn${this.selectedKind === 'Field' ? ' is-active' : ''}`;
    }

    get marketingKindClass() {
        return `kind-btn${this.selectedKind === 'Marketing' ? ' is-active' : ''}`;
    }

    get marketingPressed() {
        return this.selectedKind === 'Marketing' ? 'true' : 'false';
    }

    get showMarketingKind() {
        return (
            this.context?.marketingEnabled !== false &&
            (this.context?.marketingTypes || []).length > 0
        );
    }

    get medicalPressed() {
        return this.selectedKind === 'Medical' ? 'true' : 'false';
    }

    get fieldPressed() {
        return this.selectedKind === 'Field' ? 'true' : 'false';
    }

    get showMedicalKind() {
        return this.context?.medicalEnabled === true;
    }

    get typeOptions() {
        if (this.selectedKind === 'Medical') {
            return this.context?.medicalTypes || [];
        }
        if (this.selectedKind === 'Marketing') {
            return this.context?.marketingTypes || [];
        }
        return this.context?.fieldTypes || [];
    }

    get productOptions() {
        return this.context?.productOptions || [];
    }

    get isSample() {
        return this.selectedType === 'Sample';
    }

    get isMedical() {
        return this.selectedKind === 'Medical';
    }

    get isMarketing() {
        return this.selectedKind === 'Marketing';
    }

    get productLabel() {
        return this.isSample ? 'Product' : 'Product (optional)';
    }

    get summaryLabel() {
        return this.isSample ? 'Who is it for?' : 'What is needed?';
    }

    async loadContext() {
        this.isLoading = true;
        this.errorMessage = undefined;
        try {
            const ctx = await getCreateContext({
                accountId: this.accountId || null,
                visitId: this.visitId || null
            });
            this.context = ctx;
            if (ctx?.requestsEnabled === false) {
                this.errorMessage = 'Requests are turned off for the field app.';
            }
            this.chosenAccountId = ctx?.defaultAccountId || this.accountId || null;
            this.chosenAccountName = ctx?.defaultAccountName || this.accountName || null;
            this.chosenVisitId = ctx?.defaultVisitId || this.visitId || null;
            this.chosenIconName = ctx?.defaultIconName || null;
            this.chosenRecordTypeLabel = ctx?.defaultRecordTypeLabel || null;
            this.accountHints = ctx?.accountHints || [];
            this.accountInvalid = false;
            if (ctx?.medicalEnabled && (!ctx.fieldTypes || !ctx.fieldTypes.length)) {
                this.selectedKind = 'Medical';
            } else {
                this.selectedKind = 'Field';
            }
            const types = this.typeOptions;
            this.selectedType = types.length ? types[0].value : null;
            this._focusSheet = true;
        } catch (error) {
            this.errorMessage =
                error?.body?.message || error?.message || 'Unable to open the request form.';
        } finally {
            this.isLoading = false;
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

    handleKind(event) {
        const kind = event.currentTarget.dataset.kind;
        this.selectedKind = kind;
        const types = this.typeOptions;
        this.selectedType = types.length ? types[0].value : null;
    }

    handleTypeChange(event) {
        this.selectedType = event.detail.value;
    }

    handleUrgencyChange(event) {
        this.selectedUrgency = event.detail.value;
    }

    handleProductChange(event) {
        this.selectedProductId = event.detail.value;
    }

    handleQuantityChange(event) {
        this.sampleQuantity = event.detail.value;
    }

    handleSummaryChange(event) {
        this.summary = event.detail.value;
    }

    handleAccountChange(event) {
        this.applyAccount(event.detail);
    }

    async handleSubmit() {
        if (!this.chosenAccountId) {
            this.accountInvalid = true;
            this.errorMessage = 'Choose an account for this request.';
            this.template.querySelector('c-field-account-lookup')?.focus();
            return;
        }
        if (this.isSample && (!this.sampleQuantity || Number(this.sampleQuantity) < 1)) {
            this.errorMessage = 'Enter how many samples are needed.';
            return;
        }
        if (!this.summary || !this.summary.trim()) {
            this.errorMessage = 'Write a short summary of what is needed.';
            return;
        }
        this.isSaving = true;
        this.errorMessage = undefined;
        try {
            const row = await createRequest({
                input: {
                    accountId: this.chosenAccountId,
                    visitId: this.chosenVisitId || this.visitId || null,
                    productId: this.selectedProductId || null,
                    quantity: this.isSample ? Number(this.sampleQuantity) : null,
                    kind: this.selectedKind,
                    requestType: this.selectedType,
                    urgency: this.selectedUrgency,
                    summary: this.summary,
                    source: this.source || 'Home'
                }
            });
            this.dispatchEvent(
                new ShowToastEvent({
                    title: 'Request sent',
                    message:
                        this.selectedKind === 'Medical'
                            ? 'Medical Affairs has your question.'
                            : this.selectedKind === 'Marketing'
                              ? 'Your manager has this marketing service request.'
                              : 'Your manager has this request.',
                    variant: 'success'
                })
            );
            this.dispatchEvent(
                new CustomEvent('created', {
                    detail: { request: row }
                })
            );
            this.closeSheet();
        } catch (error) {
            this.errorMessage =
                error?.body?.message || error?.message || 'Unable to send this request.';
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
