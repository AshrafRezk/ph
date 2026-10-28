import { LightningElement, track } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import listAllTypes from '@salesforce/apex/ServiceRequestTypeService.listAllTypes';
import saveType from '@salesforce/apex/ServiceRequestTypeService.saveType';
import seedDefaults from '@salesforce/apex/ServiceRequestTypeService.seedDefaults';

const CATEGORY_OPTIONS = [
    { label: 'Field', value: 'Field' },
    { label: 'Medical', value: 'Medical' },
    { label: 'Marketing', value: 'Marketing' },
    { label: 'Visit', value: 'Visit' },
    { label: 'Sales', value: 'Sales' }
];

export default class ServiceRequestTypesAdmin extends LightningElement {
    loading = true;
    saving = false;
    seeding = false;
    showMaintenance = false;
    confirmSeed = false;
    categoryOptions = CATEGORY_OPTIONS;
    @track rows = [];
    draft = {
        id: null,
        name: '',
        category: 'Field',
        subtype: '',
        creatorTitles: 'Medical Rep;District Manager',
        isActive: true
    };

    connectedCallback() {
        this.load();
    }

    get editorHeading() {
        return this.draft.id ? 'Edit type' : 'Add type';
    }

    get hasRows() {
        return (this.rows || []).length > 0;
    }

    async load() {
        this.loading = true;
        try {
            const data = await listAllTypes({ category: null });
            this.rows = (data || []).map((row) => ({
                ...row,
                key: row.id,
                titlesLabel: row.creatorTitles || 'All titles',
                activeLabel: row.isActive ? 'Active' : 'Inactive'
            }));
        } catch (error) {
            this.toast('Could not load types', this.errorMessage(error), 'error');
        } finally {
            this.loading = false;
        }
    }

    get maintenanceToggleLabel() {
        return this.showMaintenance ? 'Hide maintenance (one-off setup)' : 'Maintenance (one-off setup)';
    }

    get maintenanceToggleIcon() {
        return this.showMaintenance ? 'utility:chevrondown' : 'utility:chevronright';
    }

    get maintenanceExpandedText() {
        return String(this.showMaintenance);
    }

    handleToggleMaintenance() {
        this.showMaintenance = !this.showMaintenance;
        this.confirmSeed = false;
    }

    handleSeedRequest() {
        this.confirmSeed = true;
    }

    handleSeedCancel() {
        this.confirmSeed = false;
    }

    async handleSeed() {
        this.confirmSeed = false;
        this.seeding = true;
        try {
            const result = await seedDefaults();
            this.toast(
                'Defaults loaded',
                `${result.marketingInserted} marketing and ${result.medicalInserted} medical services added (${result.skipped} already present).`,
                'success'
            );
            await this.load();
        } catch (error) {
            this.toast('Seed failed', this.errorMessage(error), 'error');
        } finally {
            this.seeding = false;
        }
    }

    handleDraft(event) {
        const field = event.target.dataset.field;
        if (!field) return;
        let value;
        if (event.target.type === 'checkbox' || event.target.type === 'toggle') {
            value = event.target.checked;
        } else if (event.detail && event.detail.value !== undefined) {
            value = event.detail.value;
        } else {
            value = event.target.value;
        }
        this.draft = { ...this.draft, [field]: value };
    }

    handleEdit(event) {
        const id = event.currentTarget.dataset.id;
        const row = (this.rows || []).find((r) => r.id === id);
        if (!row) return;
        this.draft = {
            id: row.id,
            name: row.name,
            category: row.category || 'Field',
            subtype: row.subtype || '',
            creatorTitles: row.creatorTitles || '',
            isActive: row.isActive !== false
        };
    }

    handleNew() {
        this.draft = {
            id: null,
            name: '',
            category: 'Field',
            subtype: '',
            creatorTitles: 'Medical Rep;District Manager',
            isActive: true
        };
    }

    async handleSave() {
        if (!this.draft.name) {
            this.toast('Name required', 'Enter a request type name.', 'error');
            return;
        }
        this.saving = true;
        try {
            await saveType({ input: this.draft });
            this.toast('Saved', 'Service request type is available to matching titles.', 'success');
            this.handleNew();
            await this.load();
        } catch (error) {
            this.toast('Save failed', this.errorMessage(error), 'error');
        } finally {
            this.saving = false;
        }
    }

    toast(title, message, variant) {
        this.dispatchEvent(new ShowToastEvent({ title, message, variant }));
    }

    errorMessage(error) {
        return error?.body?.message || error?.message || 'Unknown error';
    }
}
