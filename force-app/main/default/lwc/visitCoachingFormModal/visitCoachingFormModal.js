import { LightningElement, api } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import getCoachingFormContext from '@salesforce/apex/VisitCoachingController.getCoachingFormContext';
import createVisitCoachingEvent from '@salesforce/apex/VisitCoachingController.createVisitCoachingEvent';
import submitForManagerReview from '@salesforce/apex/VisitCoachingController.submitForManagerReview';
import { getCoachingContext, newClientKey, putCoachingContext } from 'c/clmOfflineStore';
import { isOfflineMode, queueOfflineAction } from 'c/clmOfflineSync';

export default class VisitCoachingFormModal extends NavigationMixin(LightningElement) {
    @api visitId;

    context;
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

    get createDisabled() {
        return this.isLoading || !this.selectedTemplateId;
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

    applyContext(context, fromCache = false) {
        this.context = context;
        this.usingCachedContext = fromCache;
        this.coachingEventId = context.coachingEventId;
        this.coachingEventStatus = context.coachingEventStatus;
        this.clientCoachingKey = context.clientCoachingKey || this.clientCoachingKey;
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

    async handleCreate() {
        this.isSubmitting = true;
        try {
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
                        prefillFromVisit: this.prefillFromVisit
                    })
                });
                this.coachingEventId = localId;
                this.coachingEventStatus = 'Draft';
                const cached = {
                    ...(this.context || {}),
                    coachingEventId: localId,
                    coachingEventStatus: 'Draft',
                    clientCoachingKey: this.clientCoachingKey
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
                prefillFromVisit: this.prefillFromVisit
            });
            this.coachingEventId = result.coachingEventId;
            this.coachingEventStatus = result.status;
            const refreshed = {
                ...(this.context || {}),
                coachingEventId: result.coachingEventId,
                coachingEventStatus: result.status
            };
            this.context = refreshed;
            await putCoachingContext(this.visitId, refreshed);
            this.dispatchEvent(
                new CustomEvent('coachingcreated', {
                    detail: { coachingEventId: result.coachingEventId }
                })
            );
            this.showToast('Coaching form created', 'This visit is now flagged as a double visit.', 'success');
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
