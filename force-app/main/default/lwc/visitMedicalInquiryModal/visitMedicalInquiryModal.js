import { LightningElement, api } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import getMedicalInquiryContext from '@salesforce/apex/VisitMedicalInquiryController.getMedicalInquiryContext';
import createMedicalInquiry from '@salesforce/apex/VisitMedicalInquiryController.createMedicalInquiry';

function formatDate(value) {
    if (!value) {
        return '—';
    }
    return new Date(value).toLocaleDateString([], {
        month: 'short',
        day: 'numeric',
        year: 'numeric'
    });
}

function truncateText(value, maxLength = 140) {
    if (!value) {
        return '';
    }
    const trimmed = value.trim();
    if (trimmed.length <= maxLength) {
        return trimmed;
    }
    return `${trimmed.slice(0, maxLength - 1)}…`;
}

const REQUEST_TYPES = [
    { label: 'Medical Request', value: 'Medical' },
    { label: 'Other', value: 'Other' }
];

const MEDICAL_CATEGORIES = new Set([
    'Efficacy',
    'Safety',
    'Dosing',
    'Adverse Event',
    'Administration',
    'Contraindications',
    'Drug Interactions',
    'Pregnancy/Lactation',
    'Off-label'
]);

function formatDateTime(value) {
    if (!value) {
        return '—';
    }
    return new Date(value).toLocaleString([], {
        month: 'short',
        day: 'numeric',
        year: 'numeric',
        hour: '2-digit',
        minute: '2-digit'
    });
}

export default class VisitMedicalInquiryModal extends NavigationMixin(LightningElement) {
    @api visitId;
    @api embedded = false;

    context;
    isLoading = true;
    isSubmitting = false;
    errorMessage;

    selectedInquirerId;
    selectedProductId;
    selectedRequestType = 'Other';
    selectedCategory;
    selectedRoute = 'Service_Team';
    questionText = '';

    connectedCallback() {
        this.loadContext();
    }

    get visitName() {
        return this.context?.visitName || '—';
    }

    get accountName() {
        return this.context?.accountName || '—';
    }

    get assignedToName() {
        return this.context?.assignedToName || '—';
    }

    get isLocked() {
        return this.context?.isLocked === true;
    }

    get shellClass() {
        return this.embedded
            ? 'inquiry-embedded'
            : 'slds-modal slds-fade-in-open inquiry-modal';
    }

    get containerClass() {
        return this.embedded ? 'inquiry-embedded-body' : 'slds-modal__container inquiry-modal-container';
    }

    get sectionRole() {
        return this.embedded ? 'region' : 'dialog';
    }

    get inquirerOptions() {
        return (this.context?.inquirerOptions || []).map((row) => ({
            label: row.role ? `${row.accountName} (${row.role})` : row.accountName,
            value: row.accountId
        }));
    }

    get productOptions() {
        return (this.context?.products || []).map((row) => ({
            label: row.productName,
            value: row.productId
        }));
    }

    get requestTypeOptions() {
        return REQUEST_TYPES;
    }

    get categoryOptions() {
        return this.categoriesForType(this.selectedRequestType).map((value) => ({
            label: value,
            value
        }));
    }

    categoriesForType(requestType) {
        const categories = this.context?.questionCategories || [];
        const medical = categories.filter((value) => MEDICAL_CATEGORIES.has(value));
        const other = categories.filter((value) => !MEDICAL_CATEGORIES.has(value));
        if (requestType === 'Medical') {
            return medical.length ? medical : categories;
        }
        return other.length ? other : categories;
    }

    requestTypeForCategory(category) {
        return MEDICAL_CATEGORIES.has(category) ? 'Medical' : 'Other';
    }

    get routeOptions() {
        return (this.context?.routeOptions || []).map((row) => ({
            label: row.label,
            value: row.value
        }));
    }

    get selectedRouteLabel() {
        return this.routeOptions.find((option) => option.value === this.selectedRoute)?.label || 'Service Team';
    }

    get existingInquiries() {
        return (this.context?.existingInquiries || []).map((row) => ({
            ...row,
            createdLabel: formatDateTime(row.createdDate),
            responseDateLabel: formatDate(row.responseDate),
            responsePreview: truncateText(row.responseText),
            hasResponse: Boolean(row.responseText?.trim())
        }));
    }

    get hasExistingInquiries() {
        return this.existingInquiries.length > 0;
    }

    get submitDisabled() {
        return (
            this.isLoading ||
            this.isSubmitting ||
            this.isLocked ||
            !this.selectedInquirerId ||
            !this.selectedProductId ||
            !this.selectedRequestType ||
            !this.selectedCategory ||
            !this.selectedRoute ||
            !this.questionText?.trim()
        );
    }

    get showIntakeForm() {
        return !this.isLocked && !this.errorMessage;
    }

    async loadContext() {
        this.isLoading = true;
        this.errorMessage = undefined;
        try {
            this.context = await getMedicalInquiryContext({ visitId: this.visitId });
            this.selectedInquirerId = this.context.defaultInquirerAccountId;
            if (!this.selectedInquirerId && this.context.inquirerOptions?.length) {
                this.selectedInquirerId = this.context.inquirerOptions[0].accountId;
            }
            if (this.context.products?.length) {
                this.selectedProductId = this.context.products[0].productId;
            }
            if (this.context.questionCategories?.length) {
                this.selectedCategory = this.context.questionCategories[0];
                this.selectedRequestType = this.requestTypeForCategory(this.selectedCategory);
                this.selectedCategory =
                    this.categoriesForType(this.selectedRequestType)[0] || this.selectedCategory;
                this.selectedRoute = this.selectedRequestType === 'Medical' ? 'Medical_Team' : 'Service_Team';
            }
            const routes = this.context.routeOptions || [];
            if (!routes.some((option) => option.value === this.selectedRoute) && routes.length) {
                this.selectedRoute = routes[0].value;
            }
            if (!this.context.products?.length && !this.isLocked) {
                this.errorMessage = 'No territory products are available for this visit.';
            }
        } catch (error) {
            this.errorMessage = this.reduceError(error);
        } finally {
            this.isLoading = false;
        }
    }

    handleInquirerChange(event) {
        this.selectedInquirerId = event.detail.value;
    }

    handleProductChange(event) {
        this.selectedProductId = event.detail.value;
    }

    handleRequestTypeChange(event) {
        const requestType = event.detail.value;
        this.selectedRequestType = requestType;
        const categories = this.categoriesForType(requestType);
        this.selectedCategory = categories[0] || '';
        this.selectedRoute = requestType === 'Medical' ? 'Medical_Team' : 'Service_Team';
    }

    handleCategoryChange(event) {
        this.selectedCategory = event.detail.value;
    }

    handleRouteChange(event) {
        this.selectedRoute = event.detail.value;
    }

    handleQuestionChange(event) {
        this.questionText = event.detail.value;
    }

    async handleSubmit() {
        const visitId = this.visitId || this.context?.visitId;
        if (!visitId) {
            this.showToast('Submit failed', 'Visit Id is required.', 'error');
            return;
        }

        this.isSubmitting = true;
        try {
            const result = await createMedicalInquiry({
                visitId,
                inquirerAccountId: this.selectedInquirerId,
                productId: this.selectedProductId,
                questionCategory: this.selectedCategory,
                questionText: this.questionText,
                routeTo: this.selectedRoute
            });
            this.dispatchEvent(
                new CustomEvent('inquirycreated', {
                    detail: { caseId: result.caseId, caseNumber: result.caseNumber }
                })
            );
            this.showToast(
                'Request recorded',
                `Case ${result.caseNumber} was sent to ${this.selectedRouteLabel}.`,
                'success'
            );
            this.questionText = '';
            if (this.embedded) {
                await this.loadContext();
            } else {
                this.handleClose();
            }
        } catch (error) {
            this.showToast('Submit failed', this.reduceError(error), 'error');
        } finally {
            this.isSubmitting = false;
        }
    }

    handleOpenCase(event) {
        const caseId = event.currentTarget.dataset.caseId;
        if (!caseId) {
            return;
        }
        this[NavigationMixin.Navigate]({
            type: 'standard__recordPage',
            attributes: {
                recordId: caseId,
                objectApiName: 'Case',
                actionName: 'view'
            }
        });
    }

    handleClose() {
        this.dispatchEvent(new CustomEvent('close'));
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