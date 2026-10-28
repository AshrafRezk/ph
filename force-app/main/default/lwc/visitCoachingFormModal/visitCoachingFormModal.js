import { LightningElement, api } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import getCoachingFormContext from '@salesforce/apex/VisitCoachingController.getCoachingFormContext';
import createVisitCoachingEvent from '@salesforce/apex/VisitCoachingController.createVisitCoachingEvent';
import submitForManagerReview from '@salesforce/apex/VisitCoachingController.submitForManagerReview';
import { getCoachingContext, newClientKey, putCoachingContext } from 'c/clmOfflineStore';
import { isOfflineMode, queueOfflineAction } from 'c/clmOfflineSync';

function createdCoachingEventId(result) {
    if (result == null || typeof result !== 'object') {
        return null;
    }
    return result.coachingEventId || result.id || null;
}

function formatVisitTime(value) {
    if (!value) {
        return 'Time not set';
    }
    return new Date(value).toLocaleTimeString([], { hour: 'numeric', minute: '2-digit' });
}

export default class VisitCoachingFormModal extends NavigationMixin(LightningElement) {
    @api visitId;

    context;
    visits = [];
    isLoading = true;
    isSubmitting = false;
    errorMessage;
    selectedTemplateId;
    prefillFromVisit = true;
    coachingEventId;
    coachingEventStatus;
    clientCoachingKey;
    usingCachedContext = false;

    connectedCallback() {
        this.loadContext();
    }

    get templateOptions() {
        return (this.context?.templates || []).map((row) => ({
            label: row.title,
            value: row.id
        }));
    }

    get employeeName() {
        return this.context?.employeeName || '—';
    }

    get managerName() {
        return this.context?.managerName || '—';
    }

    get accountName() {
        return this.context?.accountName || '—';
    }

    get hasCoachingEvent() {
        return !!this.coachingEventId;
    }

    get selectedVisitCount() {
        return this.visits.filter((row) => row.selected).length;
    }

    get selectableVisitCount() {
        return this.visits.filter((row) => row.selectable !== false).length;
    }

    get allSelectableSelected() {
        const selectable = this.visits.filter((row) => row.selectable !== false);
        return selectable.length > 0 && selectable.every((row) => row.selected);
    }

    get createDisabled() {
        return this.isLoading || this.isSubmitting || !this.selectedTemplateId || this.selectedVisitCount === 0;
    }

    get showSubmitForReview() {
        return (
            this.hasCoachingEvent &&
            this.coachingEventStatus !== 'Review' &&
            this.coachingEventStatus !== 'Completed' &&
            this.coachingEventStatus !== 'Cancelled'
        );
    }

    get canOpenEvent() {
        return !!this.coachingEventId && !String(this.coachingEventId).startsWith('local_');
    }

    get offlineHint() {
        return this.usingCachedContext ? 'Showing cached coaching context from device' : '';
    }

    get hasSameDayVisits() {
        return this.visits.length > 0;
    }

    get associatedVisits() {
        return (this.context?.associatedVisits || []).map((row) => ({
            ...row,
            startLabel: formatVisitTime(row.startDate)
        }));
    }

    get hasAssociatedVisits() {
        return this.associatedVisits.length > 0;
    }

    get visitCountLabel() {
        const count = this.selectedVisitCount;
        return count === 1 ? '1 visit selected' : `${count} visits selected`;
    }

    applyContext(context, fromCache = false) {
        this.context = context;
        this.usingCachedContext = fromCache;
        this.coachingEventId = context.coachingEventId;
        this.coachingEventStatus = context.coachingEventStatus;
        this.clientCoachingKey = context.clientCoachingKey || this.clientCoachingKey;
        this.visits = (context.sameDayVisits || []).map((row) => ({
            ...row,
            selected: row.selected === true || row.isCurrent === true,
            startLabel: formatVisitTime(row.startDate),
            checkboxDisabled: row.isCurrent === true || row.selectable === false,
            alreadyOnOtherEvent: row.alreadyOnOtherEvent === true
        }));
        if (!this.selectedTemplateId && context.templates?.length) {
            this.selectedTemplateId = context.templates[0].id;
        }
        if (!context.managerId) {
            this.errorMessage =
                'No manager is assigned to this rep. Set a manager on the user record before starting a coaching form.';
        } else if (!context.templates?.length && !this.coachingEventId) {
            this.errorMessage = 'No active coaching templates are available.';
        }
    }

    async loadContext() {
        this.isLoading = true;
        this.errorMessage = undefined;
        try {
            if (isOfflineMode()) {
                const cached = await getCoachingContext(this.visitId);
                if (!cached) {
                    this.errorMessage =
                        'Coaching context is not cached for offline use. Open this visit while online first.';
                    return;
                }
                this.applyContext(cached, true);
                return;
            }
            this.context = await getCoachingFormContext({ visitId: this.visitId });
            this.applyContext(this.context, false);
            await putCoachingContext(this.visitId, this.context);
        } catch (error) {
            const cached = await getCoachingContext(this.visitId);
            if (cached) {
                this.applyContext(cached, true);
            } else {
                this.errorMessage = this.reduceError(error);
            }
        } finally {
            this.isLoading = false;
        }
    }

    handleTemplateChange(event) {
        this.selectedTemplateId = event.detail.value;
    }

    handlePrefillChange(event) {
        this.prefillFromVisit = event.target.checked;
    }

    handleSelectAll(event) {
        const checked = event.target.checked;
        this.visits = this.visits.map((row) => ({
            ...row,
            selected: row.isCurrent || row.selectable === false ? row.selected || row.isCurrent : checked
        }));
    }

    handleVisitToggle(event) {
        const visitId = event.target.dataset.visitId;
        const checked = event.target.checked;
        this.visits = this.visits.map((row) => {
            if (row.visitId !== visitId || row.isCurrent) {
                return row;
            }
            return { ...row, selected: checked };
        });
    }

    handleNotesChange(event) {
        const visitId = event.target.dataset.visitId;
        const value = event.target.value;
        this.visits = this.visits.map((row) =>
            row.visitId === visitId ? { ...row, managerNotes: value } : row
        );
    }

    handleOpenVisit(event) {
        const visitId = event.currentTarget.dataset.visitId;
        if (!visitId) {
            return;
        }
        this[NavigationMixin.Navigate]({
            type: 'standard__recordPage',
            attributes: {
                recordId: visitId,
                objectApiName: 'Visit__c',
                actionName: 'view'
            }
        });
    }

    selectedVisitPayload() {
        return this.visits
            .filter((row) => row.selected)
            .map((row) => ({
                visitId: row.visitId,
                managerNotes: row.managerNotes || ''
            }));
    }

    async handleCreate() {
        this.isSubmitting = true;
        try {
            const visitSelections = this.selectedVisitPayload();
            if (isOfflineMode()) {
                this.clientCoachingKey = newClientKey('coaching');
                const localId = `local_${this.clientCoachingKey}`;
                await queueOfflineAction({
                    actionType: 'CREATE_COACHING_EVENT',
                    clientCoachingKey: this.clientCoachingKey,
                    clientActionKey: this.clientCoachingKey,
                    visitId: this.visitId,
                    payloadJson: JSON.stringify({
                        visitId: this.visitId,
                        templateId: this.selectedTemplateId,
                        prefillFromVisit: this.prefillFromVisit,
                        visitSelections
                    })
                });
                this.coachingEventId = localId;
                this.coachingEventStatus = 'Draft';
                const cached = {
                    ...(this.context || {}),
                    coachingEventId: localId,
                    coachingEventStatus: 'Draft',
                    clientCoachingKey: this.clientCoachingKey,
                    associatedVisits: this.visits.filter((row) => row.selected)
                };
                this.context = cached;
                await putCoachingContext(this.visitId, cached);
                this.dispatchEvent(
                    new CustomEvent('coachingcreated', {
                        detail: { coachingEventId: localId, clientCoachingKey: this.clientCoachingKey }
                    })
                );
                this.showToast(
                    'Queued offline',
                    'Coaching form will be created when you sync.',
                    'success'
                );
                return;
            }

            const result = await createVisitCoachingEvent({
                visitId: this.visitId,
                templateId: this.selectedTemplateId,
                prefillFromVisit: this.prefillFromVisit === true,
                visitSelections
            });
            const coachingEventId = createdCoachingEventId(result);
            if (!coachingEventId) {
                throw new Error('Coaching event was not created.');
            }
            this.coachingEventId = coachingEventId;
            this.coachingEventStatus = result.status || 'Draft';
            const refreshed = {
                ...(this.context || {}),
                coachingEventId,
                coachingEventStatus: this.coachingEventStatus,
                associatedVisits: this.visits.filter((row) => row.selected)
            };
            this.context = refreshed;
            await putCoachingContext(this.visitId, refreshed);
            this.dispatchEvent(
                new CustomEvent('coachingcreated', {
                    detail: { coachingEventId }
                })
            );
            const visitLabel = result.visitCount === 1 ? 'visit' : 'visits';
            this.showToast(
                'Coaching form created',
                `${result.visitCount || visitSelections.length} ${visitLabel} flagged as double visits.`,
                'success'
            );
        } catch (error) {
            this.showToast('Create failed', this.reduceError(error), 'error');
        } finally {
            this.isSubmitting = false;
        }
    }

    async handleSubmitForReview() {
        this.isSubmitting = true;
        try {
            if (isOfflineMode()) {
                await queueOfflineAction({
                    actionType: 'SUBMIT_COACHING_REVIEW',
                    clientCoachingKey: this.clientCoachingKey,
                    clientActionKey: newClientKey('coaching_submit'),
                    payloadJson: JSON.stringify({
                        coachingEventId: this.coachingEventId
                    })
                });
                this.coachingEventStatus = 'Review';
                const cached = {
                    ...(this.context || {}),
                    coachingEventStatus: 'Review',
                    clientCoachingKey: this.clientCoachingKey
                };
                this.context = cached;
                await putCoachingContext(this.visitId, cached);
                this.dispatchEvent(new CustomEvent('coachingsubmitted'));
                this.showToast(
                    'Queued offline',
                    'Coaching form will be sent for review when you sync.',
                    'success'
                );
                return;
            }

            await submitForManagerReview({ coachingEventId: this.coachingEventId });
            this.coachingEventStatus = 'Review';
            this.dispatchEvent(new CustomEvent('coachingsubmitted'));
            this.showToast(
                'Sent for review',
                `${this.managerName} can now review this coaching form.`,
                'success'
            );
        } catch (error) {
            this.showToast('Submit failed', this.reduceError(error), 'error');
        } finally {
            this.isSubmitting = false;
        }
    }

    handleOpenCoachingEvent() {
        if (!this.canOpenEvent) {
            this.showToast('Still offline', 'Open the coaching event after sync completes.', 'info');
            return;
        }
        this[NavigationMixin.Navigate]({
            type: 'standard__recordPage',
            attributes: {
                recordId: this.coachingEventId,
                objectApiName: 'Coaching_Event__c',
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