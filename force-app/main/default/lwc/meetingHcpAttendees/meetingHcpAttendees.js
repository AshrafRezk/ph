import { LightningElement, api, wire } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { refreshApex } from '@salesforce/apex';
import getMeetingHcpContext from '@salesforce/apex/MeetingHcpAttendeeController.getMeetingHcpContext';
import searchTargetHcpCandidates from '@salesforce/apex/MeetingHcpAttendeeController.searchTargetHcpCandidates';
import addHcpAttendee from '@salesforce/apex/MeetingHcpAttendeeController.addHcpAttendee';
import removeHcpAttendee from '@salesforce/apex/MeetingHcpAttendeeController.removeHcpAttendee';

const DEBOUNCE_MS = 300;

export default class MeetingHcpAttendees extends NavigationMixin(LightningElement) {
    @api recordId;

    context;
    wiredContextResult;
    pickerOpen = false;
    searchTerm = '';
    candidates = [];
    isSearching = false;
    isSaving = false;
    debounceTimer;

    @wire(getMeetingHcpContext, { meetingId: '$recordId' })
    wiredContext(result) {
        this.wiredContextResult = result;
        const { data, error } = result;
        if (data) {
            this.context = data;
        } else if (error) {
            this.context = undefined;
            this.toast('HCP attendees', this.reduceError(error), 'error');
        }
    }

    get showPanel() {
        return this.context?.requiresHcpAttendees === true;
    }

    get attendees() {
        return (this.context?.attendees || []).map((row) => ({
            ...row,
            key: row.memberId,
            specialtyLabel: row.specialty || '—'
        }));
    }

    get hasAttendees() {
        return this.attendees.length > 0;
    }

    get validationMessage() {
        return this.context?.validationMessage;
    }

    get showValidationWarning() {
        return Boolean(this.validationMessage) && !this.hasAttendees;
    }

    handleOpenPicker() {
        this.pickerOpen = true;
        this.runSearch('');
    }

    handleClosePicker() {
        this.pickerOpen = false;
        this.searchTerm = '';
        this.candidates = [];
    }

    handleSearchChange(event) {
        this.searchTerm = event.target.value;
        clearTimeout(this.debounceTimer);
        this.debounceTimer = setTimeout(() => {
            this.runSearch(this.searchTerm);
        }, DEBOUNCE_MS);
    }

    async runSearch(term) {
        if (!this.recordId) {
            return;
        }
        this.isSearching = true;
        try {
            this.candidates = await searchTargetHcpCandidates({
                meetingId: this.recordId,
                searchTerm: term
            });
        } catch (error) {
            this.candidates = [];
            this.toast('Search', this.reduceError(error), 'error');
        } finally {
            this.isSearching = false;
        }
    }

    async handleSelectCandidate(event) {
        const accountId = event.currentTarget.dataset.id;
        if (!accountId || this.isSaving) {
            return;
        }
        this.isSaving = true;
        try {
            await addHcpAttendee({ meetingId: this.recordId, accountId });
            await refreshApex(this.wiredContextResult);
            this.handleClosePicker();
            this.toast('HCP added', 'Attendee added from your target list.', 'success');
        } catch (error) {
            this.toast('Add attendee', this.reduceError(error), 'error');
        } finally {
            this.isSaving = false;
        }
    }

    async handleRemove(event) {
        const memberId = event.currentTarget.dataset.id;
        if (!memberId || this.isSaving) {
            return;
        }
        this.isSaving = true;
        try {
            await removeHcpAttendee({ memberId });
            await refreshApex(this.wiredContextResult);
            this.toast('Removed', 'HCP attendee removed.', 'success');
        } catch (error) {
            this.toast('Remove attendee', this.reduceError(error), 'error');
        } finally {
            this.isSaving = false;
        }
    }

    handleOpenProfile(event) {
        const accountId = event.currentTarget.dataset.id;
        if (!accountId) {
            return;
        }
        this[NavigationMixin.Navigate]({
            type: 'standard__recordPage',
            attributes: {
                recordId: accountId,
                objectApiName: 'Account',
                actionName: 'view'
            }
        });
    }

    get dialogClass() {
        return `slds-modal slds-fade-in-open ${this.pickerOpen ? '' : 'slds-hide'}`;
    }

    get backdropClass() {
        return `slds-backdrop ${this.pickerOpen ? 'slds-backdrop_open' : ''}`;
    }

    toast(title, message, variant) {
        this.dispatchEvent(new ShowToastEvent({ title, message, variant }));
    }

    reduceError(error) {
        if (Array.isArray(error?.body)) {
            return error.body.map((e) => e.message).join(', ');
        }
        return error?.body?.message || error?.message || 'Unexpected error';
    }
}