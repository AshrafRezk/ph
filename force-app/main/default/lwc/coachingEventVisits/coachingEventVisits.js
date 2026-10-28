import { LightningElement, api } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import getEventVisits from '@salesforce/apex/VisitCoachingController.getEventVisits';
import addVisitsToEvent from '@salesforce/apex/VisitCoachingController.addVisitsToEvent';
import removeVisitFromEvent from '@salesforce/apex/VisitCoachingController.removeVisitFromEvent';
import saveManagerNotes from '@salesforce/apex/VisitCoachingController.saveManagerNotes';

function formatVisitTime(value) {
    if (!value) {
        return 'Time not set';
    }
    return new Date(value).toLocaleString([], {
        month: 'short',
        day: 'numeric',
        hour: 'numeric',
        minute: '2-digit'
    });
}

function decorateRows(rows) {
    return (rows || []).map((row) => ({
        ...row,
        startLabel: formatVisitTime(row.startDate),
        selected: row.selected === true,
        notesDirty: false,
        savingNotes: false,
        removing: false,
        notesPlaceholder: 'Manager notes for this visit'
    }));
}

export default class CoachingEventVisits extends NavigationMixin(LightningElement) {
    @api recordId;

    isLoading = true;
    isSaving = false;
    errorMessage;
    context;
    associatedVisits = [];
    eligibleVisits = [];
    pickerVisitId;
    employeeId;

    connectedCallback() {
        this.load();
    }

    renderedCallback() {
        if (this.recordId && this.context && this.context.coachingEventId !== this.recordId) {
            this.load();
        }
    }

    get employeeName() {
        return this.context?.employeeName || '-';
    }

    get associatedCountLabel() {
        const count = this.associatedVisits.length;
        return count === 1 ? '1 associated visit' : `${count} associated visits`;
    }

    get hasAssociatedVisits() {
        return this.associatedVisits.length > 0;
    }

    get hasEligibleVisits() {
        return this.eligibleVisits.length > 0;
    }

    get selectedEligibleCount() {
        return this.eligibleVisits.filter((row) => row.selected).length;
    }

    get allEligibleSelected() {
        return this.hasEligibleVisits && this.eligibleVisits.every((row) => row.selected);
    }

    get addDisabled() {
        return this.isSaving || this.selectedEligibleCount === 0;
    }

    get pickerAddDisabled() {
        return this.isSaving || !this.pickerVisitId;
    }

    get recordPickerFilter() {
        if (!this.employeeId) {
            return undefined;
        }
        return {
            criteria: [
                {
                    fieldPath: 'Assigned_To__c',
                    operator: 'eq',
                    value: this.employeeId
                }
            ]
        };
    }

    async load() {
        if (!this.recordId) {
            return;
        }
        this.isLoading = true;
        this.errorMessage = undefined;
        try {
            const context = await getEventVisits({ coachingEventId: this.recordId });
            this.applyContext(context);
        } catch (error) {
            this.errorMessage = this.reduceError(error);
        } finally {
            this.isLoading = false;
        }
    }

    applyContext(context) {
        this.context = context;
        this.employeeId = context.employeeId;
        this.associatedVisits = decorateRows(context.associatedVisits);
        this.eligibleVisits = decorateRows(context.eligibleVisits).map((row) => ({
            ...row,
            selected: false
        }));
        this.pickerVisitId = undefined;
    }

    handleSelectAllEligible(event) {
        const checked = event.target.checked;
        this.eligibleVisits = this.eligibleVisits.map((row) => ({ ...row, selected: checked }));
    }

    handleEligibleToggle(event) {
        const visitId = event.target.dataset.visitId;
        const checked = event.target.checked;
        this.eligibleVisits = this.eligibleVisits.map((row) =>
            row.visitId === visitId ? { ...row, selected: checked } : row
        );
    }

    handleEligibleNotesChange(event) {
        const visitId = event.target.dataset.visitId;
        const value = event.target.value;
        this.eligibleVisits = this.eligibleVisits.map((row) =>
            row.visitId === visitId ? { ...row, managerNotes: value } : row
        );
    }

    handleAssociatedNotesChange(event) {
        const visitId = event.target.dataset.visitId;
        const value = event.target.value;
        this.associatedVisits = this.associatedVisits.map((row) =>
            row.visitId === visitId ? { ...row, managerNotes: value, notesDirty: true } : row
        );
    }

    handlePickerChange(event) {
        this.pickerVisitId = event.detail.recordId;
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

    async handleAddSelected() {
        const selections = this.eligibleVisits
            .filter((row) => row.selected)
            .map((row) => ({
                visitId: row.visitId,
                managerNotes: row.managerNotes || ''
            }));
        await this.addSelections(selections, `${selections.length} visit${selections.length === 1 ? '' : 's'} added.`);
    }

    async handleAddFromPicker() {
        if (!this.pickerVisitId) {
            return;
        }
        await this.addSelections(
            [{ visitId: this.pickerVisitId, managerNotes: '' }],
            'Visit added to this coaching event.'
        );
    }

    async addSelections(visitSelections, successMessage) {
        this.isSaving = true;
        try {
            const context = await addVisitsToEvent({
                coachingEventId: this.recordId,
                visitSelections
            });
            this.applyContext(context);
            this.showToast('Visits updated', successMessage, 'success');
        } catch (error) {
            this.showToast('Could not add visit', this.reduceError(error), 'error');
        } finally {
            this.isSaving = false;
        }
    }

    async handleRemove(event) {
        const visitId = event.currentTarget.dataset.visitId;
        const isOrigin = event.currentTarget.dataset.isOrigin === 'true';
        if (isOrigin) {
            this.showToast('Cannot remove', 'The originating visit stays on this coaching event.', 'info');
            return;
        }
        this.isSaving = true;
        this.associatedVisits = this.associatedVisits.map((row) =>
            row.visitId === visitId ? { ...row, removing: true } : row
        );
        try {
            const context = await removeVisitFromEvent({
                coachingEventId: this.recordId,
                visitId
            });
            this.applyContext(context);
            this.showToast('Visit removed', 'The visit is no longer associated with this coaching event.', 'success');
        } catch (error) {
            this.showToast('Could not remove visit', this.reduceError(error), 'error');
            this.associatedVisits = this.associatedVisits.map((row) => ({ ...row, removing: false }));
        } finally {
            this.isSaving = false;
        }
    }

    async handleSaveNotes(event) {
        const visitId = event.currentTarget.dataset.visitId;
        const row = this.associatedVisits.find((item) => item.visitId === visitId);
        if (!row?.junctionId) {
            return;
        }
        this.associatedVisits = this.associatedVisits.map((item) =>
            item.visitId === visitId ? { ...item, savingNotes: true } : item
        );
        try {
            await saveManagerNotes({
                junctionId: row.junctionId,
                managerNotes: row.managerNotes || ''
            });
            this.associatedVisits = this.associatedVisits.map((item) =>
                item.visitId === visitId ? { ...item, notesDirty: false, savingNotes: false } : item
            );
            this.showToast('Notes saved', `Manager notes updated for ${row.visitName}.`, 'success');
        } catch (error) {
            this.associatedVisits = this.associatedVisits.map((item) =>
                item.visitId === visitId ? { ...item, savingNotes: false } : item
            );
            this.showToast('Could not save notes', this.reduceError(error), 'error');
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