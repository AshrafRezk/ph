import { LightningElement, wire } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import Id from '@salesforce/user/Id';
import getRepPresentations from '@salesforce/apex/ClmMetricsController.getRepPresentations';
import { getPresentationList, getUserPresentationListKey } from 'c/clmOfflineStore';
import { isOfflineMode } from 'c/clmOfflineSync';

export default class ClmPresentationsHub extends LightningElement {
    presentations = [];
    wiredPresentationsResult;
    usingCachedPresentations = false;

    showPlayer = false;
    activePresentationId;
    activePresentationName;

    connectedCallback() {
        if (isOfflineMode()) {
            this.loadCachedPresentations();
        }
    }

    @wire(getRepPresentations)
    wiredPresentations(result) {
        this.wiredPresentationsResult = result;
        if (result.data) {
            this.presentations = result.data;
            this.usingCachedPresentations = false;
        } else if (result.error || isOfflineMode()) {
            this.loadCachedPresentations();
        }
    }

    async loadCachedPresentations() {
        try {
            const cached = await getPresentationList(getUserPresentationListKey(Id));
            this.presentations = cached?.presentations || [];
            this.usingCachedPresentations = this.presentations.length > 0;
        } catch (error) {
            this.presentations = [];
            this.usingCachedPresentations = false;
        }
    }

    get hasPresentations() {
        return this.presentations.length > 0;
    }

    get offlineHint() {
        return this.usingCachedPresentations ? 'Showing cached CLMs from device' : '';
    }

    get presentationCards() {
        return this.presentations.map((pres) => ({
            key: pres.id,
            id: pres.id,
            name: pres.name,
            productName: pres.productName || '—',
            imageUrl: pres.imageUrl,
            slideCount: pres.slideCount || 0,
            formatType: pres.formatType || '—',
            tags: pres.tags
        }));
    }

    handlePresent(event) {
        const presentationId = event.currentTarget.dataset.id;
        const presentationName = event.currentTarget.dataset.name;
        if (!presentationId) {
            return;
        }

        this.activePresentationId = presentationId;
        this.activePresentationName = presentationName;
        this.showPlayer = true;
    }

    handlePlayerClose() {
        this.showPlayer = false;
        this.activePresentationId = null;
        this.activePresentationName = null;
    }

    showToast(title, message, variant) {
        this.dispatchEvent(new ShowToastEvent({ title, message, variant }));
    }

    reduceError(error) {
        return error?.body?.message || error?.message || 'Unexpected error';
    }
}
