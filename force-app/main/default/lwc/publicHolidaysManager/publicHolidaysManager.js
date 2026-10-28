import { LightningElement, track } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import LightningConfirm from 'lightning/confirm';
import listHolidays from '@salesforce/apex/PublicHolidayService.listHolidays';
import saveHolidayFields from '@salesforce/apex/PublicHolidayService.saveHolidayFields';
import deleteHoliday from '@salesforce/apex/PublicHolidayService.deleteHoliday';
import loadEgypt2026Holidays from '@salesforce/apex/PublicHolidayService.loadEgypt2026Holidays';
import previewEgypt2026Holidays from '@salesforce/apex/PublicHolidayService.previewEgypt2026Holidays';

const LOAD_2026_HELP =
    'Adds the fixed 2026 dates that are not in the list yet, each as a one-off 2026 date: ' +
    'Coptic Christmas (7 Jan), Revolution Day (25 Jan), Sinai Liberation Day (25 Apr), Labour Day (1 May), ' +
    'June 30 Revolution, Armed Forces Day (6 Oct) and Christmas Eve (24 Dec). ' +
    'Eid and other moving dates must be added by hand. You will be asked to confirm first.';

function formatHolidayDate(value) {
    if (!value) {
        return '';
    }
    const parts = String(value).slice(0, 10).split('-').map(Number);
    if (parts.length !== 3 || parts.some((n) => Number.isNaN(n))) {
        return String(value);
    }
    const date = new Date(parts[0], parts[1] - 1, parts[2]);
    return date.toLocaleDateString(undefined, { day: 'numeric', month: 'short', year: 'numeric' });
}

export default class PublicHolidaysManager extends LightningElement {
    @track rows = [];
    @track isLoading = false;
    @track showForm = false;
    @track isSaving = false;
    @track draft = this.emptyDraft();
    formError = '';
    load2026Help = LOAD_2026_HELP;

    connectedCallback() {
        this.refresh();
    }

    emptyDraft() {
        return {
            id: null,
            name: '',
            holidayDate: null,
            recursYearly: false,
            isActive: true
        };
    }

    get hasRows() {
        return (this.rows || []).length > 0;
    }

    get formTitle() {
        return this.draft?.id ? 'Edit public holiday' : 'New public holiday';
    }

    async refresh() {
        this.isLoading = true;
        try {
            const data = await listHolidays();
            this.rows = (data || []).map((row) => ({
                ...row,
                dateLabel: formatHolidayDate(row.holidayDate),
                statusLabel: row.isActive === false ? 'Inactive' : 'Active',
                recursLabel: row.recursYearly ? 'Yearly' : 'One-off'
            }));
        } catch (error) {
            this.toast('Error', this.reduceError(error), 'error');
        } finally {
            this.isLoading = false;
        }
    }

    handleNew() {
        this.draft = this.emptyDraft();
        this.formError = '';
        this.showForm = true;
    }

    handleEdit(event) {
        const id = event.currentTarget.dataset.id;
        const row = (this.rows || []).find((item) => item.id === id);
        if (!row) {
            return;
        }
        this.draft = {
            id: row.id,
            name: row.name,
            holidayDate: row.holidayDate,
            recursYearly: row.recursYearly === true,
            isActive: row.isActive !== false
        };
        this.formError = '';
        this.showForm = true;
    }

    handleCancel() {
        this.showForm = false;
        this.formError = '';
        this.draft = this.emptyDraft();
    }

    handleFieldChange(event) {
        const field = event.target.dataset.field;
        let value = event.target.type === 'checkbox' ? event.target.checked : event.target.value;
        this.draft = { ...this.draft, [field]: value };
    }

    /** Reads what is on screen right now, so a value typed but not yet committed is not lost. */
    readForm() {
        const values = { ...this.draft };
        let dateTypedButInvalid = false;
        this.template.querySelectorAll('lightning-input[data-field]').forEach((input) => {
            const field = input.dataset.field;
            if (input.type === 'checkbox') {
                values[field] = input.checked;
            } else {
                values[field] = input.value;
                if (field === 'holidayDate' && !input.value && input.validity && input.validity.valid === false) {
                    dateTypedButInvalid = true;
                }
            }
        });
        return { values, dateTypedButInvalid };
    }

    async handleSave() {
        if (this.isSaving) {
            return;
        }
        this.isSaving = true;
        this.formError = '';
        try {
            const { values, dateTypedButInvalid } = this.readForm();
            const name = (values.name || '').trim();
            const holidayDate = values.holidayDate ? String(values.holidayDate).slice(0, 10) : '';
            if (!name || !holidayDate) {
                this.formError = !name && !holidayDate
                    ? 'Enter the holiday name and pick its date.'
                    : !name
                      ? 'Enter the holiday name.'
                      : dateTypedButInvalid
                        ? 'The date was not recognised. Click the calendar icon and pick the day.'
                        : 'Pick the holiday date from the calendar.';
                return;
            }
            await saveHolidayFields({
                holidayId: values.id || null,
                name,
                holidayDate,
                recursYearly: values.recursYearly === true,
                isActive: values.isActive !== false
            });
            this.toast('Saved', `${name} saved for ${formatHolidayDate(holidayDate)}.`, 'success');
            this.showForm = false;
            this.draft = this.emptyDraft();
            await this.refresh();
        } catch (error) {
            this.formError = this.reduceError(error);
            this.toast('Save failed', this.formError, 'error');
        } finally {
            this.isSaving = false;
        }
    }

    async handleLoad2026() {
        let preview;
        try {
            preview = (await previewEgypt2026Holidays()) || [];
        } catch (error) {
            this.toast('Load failed', this.reduceError(error), 'error');
            return;
        }
        if (!preview.length) {
            this.toast('2026 holidays', 'All fixed 2026 national dates are already in the list.', 'info');
            return;
        }
        const ok = await LightningConfirm.open({
            label: 'Add these 2026 holidays?',
            message:
                'This adds: ' +
                preview.map((row) => `${row.name} (${formatHolidayDate(row.holidayDate)})`).join(', ') +
                '. Each is a one-off 2026 date. Eid and other moving dates must be added by hand.',
            theme: 'warning'
        });
        if (!ok) {
            return;
        }
        this.isLoading = true;
        try {
            const inserted = await loadEgypt2026Holidays();
            await this.refresh();
            this.toast(
                '2026 holidays',
                inserted > 0
                    ? `Added ${inserted} fixed national holiday(s). Add movable religious dates manually.`
                    : 'All fixed 2026 national dates are already loaded.',
                'success'
            );
        } catch (error) {
            this.toast('Load failed', this.reduceError(error), 'error');
        } finally {
            this.isLoading = false;
        }
    }

    async handleDelete(event) {
        const id = event.currentTarget.dataset.id;
        const row = (this.rows || []).find((r) => r.id === id);
        const ok = await LightningConfirm.open({
            label: 'Delete this holiday?',
            message: `${row ? row.name + ' will be removed. ' : ''}Reps will be able to plan visits on that day again.`,
            theme: 'warning'
        });
        if (!ok) {
            return;
        }
        try {
            await deleteHoliday({ holidayId: id });
            this.toast('Deleted', 'Public holiday removed.', 'success');
            await this.refresh();
        } catch (error) {
            this.toast('Delete failed', this.reduceError(error), 'error');
        }
    }

    reduceError(error) {
        return error?.body?.message || error?.message || 'Unexpected error';
    }

    toast(title, message, variant) {
        this.dispatchEvent(new ShowToastEvent({ title, message, variant }));
    }
}