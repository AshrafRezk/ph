import { LightningElement, track } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import getCopilotNavigation from '@salesforce/apex/FieldAppFeatureController.getCopilotNavigation';
import saveCopilotNavigation from '@salesforce/apex/FieldAppFeatureController.saveCopilotNavigation';

export default class CopilotAppNavAdmin extends LightningElement {
    @track apps = [];
    selectedAppKey;
    isLoading = true;
    isSaving = false;
    errorMessage;

    connectedCallback() {
        this.loadApps();
    }

    async loadApps() {
        this.isLoading = true;
        this.errorMessage = undefined;
        try {
            const rows = await getCopilotNavigation();
            this.apps = (rows || []).map((app) => ({
                ...app,
                tabs: (app.tabs || []).map((tab) => ({ ...tab }))
            }));
            if (!this.selectedAppKey && this.apps.length) {
                this.selectedAppKey = this.apps[0].key;
            }
        } catch (error) {
            this.errorMessage = error?.body?.message || error?.message || 'Unable to load Co-pilot apps.';
            this.apps = [];
        } finally {
            this.isLoading = false;
        }
    }

    get appOptions() {
        return this.apps.map((app) => ({
            label: app.label,
            value: app.key
        }));
    }

    get selectedApp() {
        return this.apps.find((app) => app.key === this.selectedAppKey) || null;
    }

    get selectedTabs() {
        return this.selectedApp?.tabs || [];
    }

    handleAppChange(event) {
        this.selectedAppKey = event.detail.value;
    }

    handleToggle(event) {
        const tabKey = event.currentTarget.dataset.key;
        const enabled = event.detail.checked === true;
        this.apps = this.apps.map((app) => {
            if (app.key !== this.selectedAppKey) {
                return app;
            }
            return {
                ...app,
                tabs: app.tabs.map((tab) => (tab.key === tabKey ? { ...tab, enabled } : tab))
            };
        });
    }

    async handleSave() {
        const app = this.selectedApp;
        if (!app) {
            return;
        }
        this.isSaving = true;
        try {
            await saveCopilotNavigation({
                appKey: app.key,
                tabsJson: JSON.stringify(app.tabs)
            });
            this.dispatchEvent(
                new ShowToastEvent({
                    title: 'App tabs saved',
                    message: `${app.label} will show the tabs you left on.`,
                    variant: 'success'
                })
            );
        } catch (error) {
            this.dispatchEvent(
                new ShowToastEvent({
                    title: 'Save failed',
                    message: error?.body?.message || error?.message || 'Unable to save these tabs.',
                    variant: 'error'
                })
            );
        } finally {
            this.isSaving = false;
        }
    }
}
