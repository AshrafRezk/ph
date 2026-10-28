import { LightningElement, track } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import getFeatureCatalog from '@salesforce/apex/FieldAppFeatureController.getFeatureCatalog';
import setFeatureEnabled from '@salesforce/apex/FieldAppFeatureController.setFeatureEnabled';

export default class FieldAppFeatureAdmin extends LightningElement {
    @track groups = [];
    isLoading = true;
    errorMessage;

    connectedCallback() {
        this.loadCatalog();
    }

    async loadCatalog() {
        this.isLoading = true;
        this.errorMessage = undefined;
        try {
            const rows = await getFeatureCatalog();
            const byCategory = new Map();
            (rows || []).forEach((row) => {
                const category = row.category || 'Visit';
                if (!byCategory.has(category)) {
                    byCategory.set(category, []);
                }
                byCategory.get(category).push({
                    ...row,
                    toggleLabel: row.enabled ? 'Visible to field users' : 'Hidden from field users'
                });
            });
            this.groups = Array.from(byCategory.entries()).map(([category, features]) => ({
                category,
                features
            }));
        } catch (error) {
            this.errorMessage = error?.body?.message || error?.message || 'Unable to load field features.';
            this.groups = [];
        } finally {
            this.isLoading = false;
        }
    }

    async handleToggle(event) {
        const key = event.currentTarget.dataset.key;
        const enabled = event.detail.checked === true;
        try {
            await setFeatureEnabled({ featureKey: key, enabled });
            this.dispatchEvent(
                new ShowToastEvent({
                    title: 'Feature updated',
                    message: enabled ? 'Visible to field users.' : 'Hidden from field users.',
                    variant: 'success'
                })
            );
            await this.loadCatalog();
        } catch (error) {
            this.dispatchEvent(
                new ShowToastEvent({
                    title: 'Update failed',
                    message: error?.body?.message || error?.message || 'Unable to save this feature.',
                    variant: 'error'
                })
            );
            await this.loadCatalog();
        }
    }
}
