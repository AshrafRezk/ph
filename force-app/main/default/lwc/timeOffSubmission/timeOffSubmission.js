import createTimeOff from '@salesforce/apex/TimeOffRequestController.createTimeOff';
import getMyRequests from '@salesforce/apex/TimeOffRequestController.getMyRequests';
import recallRequest from '@salesforce/apex/TimeOffRequestController.recallRequest';
import { LightningElement, wire } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';
import { refreshApex } from '@salesforce/apex';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';

const STAGE_DRAFT = 'Draft';
const STAGE_SUBMITTED = 'Submitted for Approval';
const SPAN_FULL_DAY = 'Full_Day';
const SPAN_HALF_DAY = 'Half_Day';
const SPAN_HOURS = 'Hours';
const SPAN_DAYS = 'Days';

const TYPE_OPTIONS = [
    { label: 'Annual Leave', value: 'Annual Leave' },
    { label: 'Business Trip', value: 'Business Trip' },
    { label: 'Sick', value: 'Sick' },
    { label: 'Training', value: 'Training' },
    { label: 'Casual/Emergency', value: 'Casual/Emergency' },
    { label: 'Health Day', value: 'Health Day' },
    { label: 'Maternity/Paternity', value: 'Maternity/Paternity' },
    { label: 'Office Work', value: 'Office Work' },
    { label: 'Marriage', value: 'Marriage' },
    { label: 'Cycle Meeting', value: 'Cycle Meeting' },
    { label: 'Unpaid', value: 'Unpaid' },
    { label: 'Sales Meeting', value: 'Sales Meeting' },
    { label: 'Military', value: 'Military' },
    { label: 'Prospection', value: 'Prospection' },
    { label: 'Handover', value: 'Handover' },
    { label: 'Sales Day', value: 'Sales Day' },
    { label: 'Delegation', value: 'Delegation' },
    { label: 'RTD', value: 'RTD' },
    { label: 'Speaker', value: 'Speaker' }
];

const SPAN_TYPE_OPTIONS = [
    { label: 'Full Day', value: SPAN_FULL_DAY },
    { label: 'Half Day (0.5)', value: SPAN_HALF_DAY },
    { label: 'Partial (Hours)', value: SPAN_HOURS },
    { label: 'Days', value: SPAN_DAYS }
];

const HOUR_DURATION_OPTIONS = Array.from({ length: 8 }, (_, index) => {
    const value = String(index + 1);
    return { label: `${value} hour${index === 0 ? '' : 's'}`, value };
});

const DAY_DURATION_OPTIONS = Array.from({ length: 90 }, (_, index) => {
    const value = String(index + 1);
    return { label: `${value} day${index === 0 ? '' : 's'}`, value };
});

const STAGE_VARIANT = {
    Draft: 'base',
    'Submitted for Approval': 'warning',
    Approved: 'success',
    Rejected: 'error'
};

const SPAN_LABELS = {
    Full_Day: 'Full Day',
    Half_Day: 'Half Day',
    Hours: 'Partial (Hours)',
    Days: 'Days'
};

export default class TimeOffSubmission extends NavigationMixin(LightningElement) {
    typeValue = '';
    spanTypeValue = '';
    durationValue = '';
    startDateValue = '';
    startDateTimeValue = '';
    commentsValue = '';
    isSaving = false;

    typeOptions = TYPE_OPTIONS;
    spanTypeOptions = SPAN_TYPE_OPTIONS;

    wiredRequestsResult;
    myRequests = [];
    requestsError;

    columns = [
        { label: 'Request', fieldName: 'recordUrl', type: 'url', typeAttributes: { label: { fieldName: 'name' }, target: '_self' } },
        { label: 'Type', fieldName: 'typeLabel' },
        { label: 'Span', fieldName: 'spanTypeLabel' },
        { label: 'Start', fieldName: 'startDateLabel', type: 'text' },
        { label: 'End', fieldName: 'endDateLabel', type: 'text' },
        { label: 'Days', fieldName: 'workingDays', type: 'number', cellAttributes: { alignment: 'left' } },
        { label: 'Stage', fieldName: 'stage', type: 'text', cellAttributes: { class: { fieldName: 'stageClass' } } },
        {
            type: 'action',
            typeAttributes: {
                rowActions: [{ label: 'Recall', name: 'recall' }]
            }
        }
    ];

    @wire(getMyRequests, { limitSize: 10 })
    wiredRequests(result) {
        this.wiredRequestsResult = result;
        const { data, error } = result;
        if (data) {
            this.myRequests = data.map((request) => this.mapRequestRow(request));
            this.requestsError = undefined;
        } else if (error) {
            this.myRequests = [];
            this.requestsError = this.reduceError(error);
        }
    }

    get isHoursSpan() {
        return this.spanTypeValue === SPAN_HOURS;
    }

    get isDaysSpan() {
        return this.spanTypeValue === SPAN_DAYS;
    }

    get isFullDaySpan() {
        return this.spanTypeValue === SPAN_FULL_DAY;
    }

    get isHalfDaySpan() {
        return this.spanTypeValue === SPAN_HALF_DAY;
    }

    get showDateOnly() {
        return this.isFullDaySpan || this.isHalfDaySpan || this.isDaysSpan;
    }

    get showScheduleFields() {
        return Boolean(this.spanTypeValue);
    }

    get durationOptions() {
        return this.isDaysSpan ? DAY_DURATION_OPTIONS : HOUR_DURATION_OPTIONS;
    }

    get durationLabel() {
        return this.isDaysSpan ? 'Duration (Days)' : 'Duration (Hours)';
    }

    get hasRequests() {
        return this.myRequests.length > 0;
    }

    handleTypeChange(event) {
        this.typeValue = event.detail.value;
    }

    handleSpanTypeChange(event) {
        this.spanTypeValue = event.detail.value;
        this.durationValue = '';
    }

    handleDurationChange(event) {
        this.durationValue = event.detail.value;
    }

    handleStartDateChange(event) {
        this.startDateValue = event.detail.value;
    }

    handleStartDateTimeChange(event) {
        this.startDateTimeValue = event.detail.value;
    }

    handleCommentsChange(event) {
        this.commentsValue = event.detail.value;
    }

    handleSaveDraft() {
        this.saveRequest(STAGE_DRAFT);
    }

    handleSubmit() {
        this.saveRequest(STAGE_SUBMITTED);
    }

    async handleRowAction(event) {
        const actionName = event.detail.action.name;
        const row = event.detail.row;
        if (actionName !== 'recall' || !row?.id) {
            return;
        }
        if (row.stage !== STAGE_SUBMITTED) {
            this.showToast('Recall unavailable', 'Only submitted requests can be recalled.', 'error');
            return;
        }
        try {
            await recallRequest({ requestId: row.id });
            await refreshApex(this.wiredRequestsResult);
            this.showToast('Recalled', 'Request returned to Draft.', 'success');
        } catch (error) {
            this.showToast('Recall failed', this.reduceError(error), 'error');
        }
    }

    async saveRequest(stage) {
        const validationMessage = this.validateForm();
        if (validationMessage) {
            this.showToast('Validation Error', validationMessage, 'error');
            return;
        }

        this.isSaving = true;
        try {
            const startDateTime = this.buildStartDateTime();
            await createTimeOff({
                typeValue: this.typeValue,
                spanType: this.spanTypeValue,
                durationValue: this.isHoursSpan || this.isDaysSpan ? this.durationValue : null,
                startDateTime,
                comments: this.commentsValue || null,
                stage
            });
            const successTitle = stage === STAGE_SUBMITTED ? 'Submitted for Approval' : 'Draft Saved';
            const successMessage =
                stage === STAGE_SUBMITTED
                    ? 'Your time off request was submitted for Mendix/manager approval.'
                    : 'Your time off request was saved as a draft.';

            this.resetForm();
            await refreshApex(this.wiredRequestsResult);
            this.showToast(successTitle, successMessage, 'success');
        } catch (error) {
            this.showToast('Save Failed', this.reduceError(error), 'error');
        } finally {
            this.isSaving = false;
        }
    }

    validateForm() {
        if (!this.typeValue) {
            return 'Select a time off type.';
        }
        if (!this.spanTypeValue) {
            return 'Select a span type.';
        }
        if (this.isHoursSpan) {
            if (!this.durationValue) {
                return 'Select how many hours (1–8) for partial time off.';
            }
            if (!this.startDateTimeValue) {
                return 'Select a start date and time.';
            }
        }
        if (this.isDaysSpan) {
            if (!this.durationValue) {
                return 'Select how many days (1–90).';
            }
            if (!this.startDateValue) {
                return 'Select the start date for multi-day time off.';
            }
        }
        if ((this.isFullDaySpan || this.isHalfDaySpan) && !this.startDateValue) {
            return 'Select the date for your time off.';
        }
        return null;
    }

    buildStartDateTime() {
        // Apex @AuraEnabled DateTime requires ISO-8601 (with timezone), not date-only.
        if (this.showDateOnly) {
            return new Date(`${this.startDateValue}T09:00:00`).toISOString();
        }
        const raw =
            this.startDateTimeValue.length === 16
                ? `${this.startDateTimeValue}:00`
                : this.startDateTimeValue;
        const parsed = new Date(raw);
        if (Number.isNaN(parsed.getTime())) {
            return raw;
        }
        return parsed.toISOString();
    }

    resetForm() {
        this.typeValue = '';
        this.spanTypeValue = '';
        this.durationValue = '';
        this.startDateValue = '';
        this.startDateTimeValue = '';
        this.commentsValue = '';
    }

    mapRequestRow(request) {
        const stageKey = request.stage || 'Draft';
        return {
            ...request,
            recordUrl: `/lightning/r/Time_Off_Request__c/${request.id}/view`,
            spanTypeLabel: SPAN_LABELS[request.spanType] || request.spanType,
            startDateLabel: this.formatDate(request.startDate),
            endDateLabel: this.formatDate(request.endDate),
            stageClass: `slds-text-color_${STAGE_VARIANT[stageKey] || 'default'}`
        };
    }

    formatDate(value) {
        if (!value) {
            return '—';
        }
        return new Date(value).toLocaleDateString();
    }

    showToast(title, message, variant) {
        this.dispatchEvent(
            new ShowToastEvent({
                title,
                message,
                variant
            })
        );
    }

    reduceError(error) {
        if (Array.isArray(error?.body)) {
            return error.body.map((item) => item.message).join(', ');
        }
        if (error?.body?.output?.errors?.length) {
            return error.body.output.errors.map((item) => item.message).join(', ');
        }
        if (error?.body?.output?.fieldErrors) {
            return Object.values(error.body.output.fieldErrors)
                .flat()
                .map((item) => item.message)
                .join(', ');
        }
        return error?.body?.message || error?.message || 'An unexpected error occurred.';
    }
}