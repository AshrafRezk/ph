import { LightningElement } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import Id from '@salesforce/user/Id';
import getRepPresentations from '@salesforce/apex/ClmMetricsController.getRepPresentations';
import getRepPresentationManifest from '@salesforce/apex/ClmMetricsController.getRepPresentationManifest';
import {
    getPresentationList,
    getUserPresentationListKey,
    putManifestEntry,
    putPresentationList
} from 'c/clmOfflineStore';
import { prefetchPresentationAssets } from 'c/clmContentCache';
import { isOfflineMode } from 'c/clmOfflineSync';
import {
    isLightningUiHost,
    OFFLINE_CLM_URL,
    openOfflineClmApp
} from 'c/clmLightningGate';

export default class ClmPresentationsHub extends LightningElement {
    presentations = [];
    usingCachedPresentations = false;
    isLoading = false;

    showPlayer = false;
    activePresentationId;
    activePresentationName;

    isSaving = false;
    saveLabel = '';
    redirectToOffline = false;

    connectedCallback() {
        this.redirectToOffline = isLightningUiHost();
        this.loadPresentations();
    }

    async loadPresentations() {
        await this.loadCachedPresentations();
        if (isOfflineMode()) {
            return;
        }
        try {
            const rows = await getRepPresentations();
            if (Array.isArray(rows) && rows.length) {
                this.presentations = rows;
                this.usingCachedPresentations = false;
            }
        } catch (error) {
            if (!this.presentations.length) {
                this.showToast('Unable to load presentations', this.reduceError(error), 'error');
            }
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
        if (this.usingCachedPresentations) {
            return 'Showing cached CLMs from device';
        }
        return `${this.presentations.length} presentation${this.presentations.length === 1 ? '' : 's'} available`;
    }

    get presentationCards() {
        return this.presentations.map((pres) => ({
            key: pres.id,
            id: pres.id,
            name: pres.name,
            productName: pres.productName || '—',
            imageUrl: pres.imageUrl,
            slideCount: pres.slideCount || 0,
            slideCountLabel: `${pres.slideCount || 0} ${(pres.slideCount || 0) === 1 ? 'slide' : 'slides'}`,
            formatType: pres.formatType || '—',
            tags: pres.tags
        }));
    }

    async handleSaveAllOffline() {
        if (this.isSaving) {
            return;
        }
        this.isSaving = true;
        this.saveLabel = 'Preparing…';
        let saved = 0;
        let failed = 0;
        try {
            const entries = await getRepPresentationManifest();
            const list = Array.isArray(entries) ? entries : [];
            if (!list.length) {
                this.showToast('Nothing to save', 'No available presentations found.', 'warning');
                return;
            }

            // Persist the summary list so the offline hub can render it later.
            const summaries = list.map((e) => ({
                id: e.id,
                name: e.name,
                status: e.status,
                formatType: e.formatType,
                productName: e.productName,
                imageUrl: e.imageUrl,
                slideCount: e.slideCount,
                tags: e.tags
            }));
            try {
                await putPresentationList(getUserPresentationListKey(Id), summaries);
            } catch (listError) {
                // Non-fatal — individual manifests/assets are the critical part.
            }

            const total = list.length;
            // Save one by one so progress is visible and memory stays bounded.
            for (let i = 0; i < total; i++) {
                const entry = list[i];
                this.saveLabel = `Saving ${i + 1}/${total} — ${entry.name}`;
                try {
                    await putManifestEntry(entry);
                    await prefetchPresentationAssets(entry, ({ completed, total: assetTotal }) => {
                        this.saveLabel =
                            `Saving ${i + 1}/${total} — ${entry.name}` +
                            (assetTotal ? ` (${completed}/${assetTotal})` : '');
                    });
                    saved += 1;
                } catch (itemError) {
                    failed += 1;
                }
            }

            const summary = failed
                ? `Saved ${saved} of ${total} — ${failed} failed.`
                : `Saved ${saved} presentation${saved === 1 ? '' : 's'} for offline.`;
            this.showToast('Offline save complete', summary, failed ? 'warning' : 'success');
        } catch (error) {
            this.showToast('Offline save failed', this.reduceError(error), 'error');
        } finally {
            this.isSaving = false;
            this.saveLabel = '';
        }
    }

    get offlineAppUrl() {
        return OFFLINE_CLM_URL;
    }

    get presentButtonLabel() {
        return this.redirectToOffline ? 'Open in Offline App' : 'Present';
    }

    handleOpenOfflineApp() {
        openOfflineClmApp();
    }

    handlePresent(event) {
        if (this.redirectToOffline) {
            this.showToast(
                'Open CLM in the Offline App',
                'Presentations play on salesforceoffline.com — opening it now.',
                'info'
            );
            openOfflineClmApp();
            return;
        }
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
        this.loadPresentations();
    }

    handleSwitchPresentation(event) {
        this.activePresentationId = event.detail?.presentationId || this.activePresentationId;
        this.activePresentationName = event.detail?.presentationName || this.activePresentationName;
    }

    showToast(title, message, variant) {
        this.dispatchEvent(new ShowToastEvent({ title, message, variant }));
    }

    reduceError(error) {
        return error?.body?.message || error?.message || 'Unexpected error';
    }
}