import { LightningElement, track } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import getOrgPolicy from '@salesforce/apex/SalesPolicyService.getOrgPolicy';
import saveOrgPolicy from '@salesforce/apex/SalesPolicyService.saveOrgPolicy';

export default class SalesPolicyAdmin extends LightningElement {
    loading = true;
    saving = false;
    @track policy = {
        name: 'Org Default',
        ceilingCap: 200,
        actualSharePct: 100,
        targetSharePct: 50,
        excludeTenderFromAchievements: true,
        usePublicPriceForNonTender: true,
        tenderPriceExceptionBrands: 'Zeta Colest'
    };

    connectedCallback() {
        this.load();
    }

    async load() {
        this.loading = true;
        try {
            const row = await getOrgPolicy();
            if (row) {
                this.policy = { ...row };
            }
        } catch (error) {
            this.toast('Could not load sales policy', this.errorMessage(error), 'error');
        } finally {
            this.loading = false;
        }
    }

    handleField(event) {
        const field = event.target.dataset.field;
        if (!field) return;
        let value = event.target.type === 'checkbox' || event.target.type === 'toggle'
            ? event.target.checked
            : event.target.value;
        if (['ceilingCap', 'actualSharePct', 'targetSharePct'].includes(field)) {
            value = value === '' || value == null ? null : Number(value);
        }
        this.policy = { ...this.policy, [field]: value };
    }

    async handleSave() {
        this.saving = true;
        try {
            this.policy = await saveOrgPolicy({ payload: this.policy });
            this.toast('Saved', 'Sales distribution policy is live for achievements.', 'success');
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
