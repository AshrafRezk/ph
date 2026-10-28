import { LightningElement, track } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import getCatalogByCategories from '@salesforce/apex/FieldAppFeatureController.getCatalogByCategories';
import saveFeatureMap from '@salesforce/apex/FieldAppFeatureController.saveFeatureMap';

const KEYS = ['hcp.products', 'hcp.news', 'hcp.home', 'hcp.events', 'hcp.requests'];

export default class HcpPortalManager extends LightningElement {
    @track features = [];
    isLoading = true;
    errorMessage;
    _byKey = new Map();
    _dirty = new Map();

    connectedCallback() {
        this.loadCatalog();
    }

    get saveDisabled() {
        return this._dirty.size === 0;
    }

    get saveLabel() {
        return this._dirty.size ? `Save (${this._dirty.size})` : 'Save';
    }

    async loadCatalog() {
        this.isLoading = true;
        this.errorMessage = undefined;
        try {
            const rows = await getCatalogByCategories({ categories: ['HCP'] });
            this._byKey = new Map((rows || []).map((row) => [row.key, { ...row }]));
            this._dirty = new Map();
            this.rebuild();
        } catch (error) {
            this.errorMessage =
                error?.body?.message || error?.message || 'Unable to load HCP Portal settings.';
            this.features = [];
        } finally {
            this.isLoading = false;
        }
    }

    rebuild() {
        this.features = KEYS.map((key) => this._byKey.get(key))
            .filter(Boolean)
            .map((row) => {
                const enabled = this._dirty.has(row.key)
                    ? this._dirty.get(row.key) === true
                    : row.enabled === true;
                return {
                    ...row,
                    enabled,
                    toggleLabel: enabled ? 'Visible' : 'Hidden'
                };
            });
    }

    handleToggle(event) {
        const key = event.currentTarget.dataset.key;
        this._dirty.set(key, event.detail.checked === true);
        this.rebuild();
    }

    async handleSave() {
        if (!this._dirty.size) {
            return;
        }
        const updates = {};
        this._dirty.forEach((value, key) => {
            updates[key] = value;
        });
        try {
            await saveFeatureMap({ updates });
            Object.keys(updates).forEach((key) => {
                const row = this._byKey.get(key);
                if (row) {
                    row.enabled = updates[key] === true;
                }
                this._dirty.delete(key);
            });
            this.rebuild();
            this.dispatchEvent(
                new ShowToastEvent({
                    title: 'Saved',
                    message: 'HCP portal tabs updated for meeting invites.',
                    variant: 'success'
                })
            );
        } catch (error) {
            this.dispatchEvent(
                new ShowToastEvent({
                    title: 'Could not save',
                    message: error?.body?.message || error?.message || 'Unable to save.',
                    variant: 'error'
                })
            );
            await this.loadCatalog();
        }
    }
}
