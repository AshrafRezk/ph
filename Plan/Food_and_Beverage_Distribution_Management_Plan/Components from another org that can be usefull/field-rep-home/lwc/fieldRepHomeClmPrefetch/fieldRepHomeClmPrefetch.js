import { LightningElement, track } from 'lwc';
import Id from '@salesforce/user/Id';
import getRepPresentationManifest from '@salesforce/apex/ClmMetricsController.getRepPresentationManifest';
import getDeployedRatingLayoutJson from '@salesforce/apex/ClmMetricsController.getDeployedRatingLayoutJson';
import { prefetchPresentationAssets } from 'c/clmContentCache';
import {
    getManifestEntry,
    getUserPresentationListKey,
    putManifestEntry,
    putMeta,
    putPresentationList
} from 'c/clmOfflineStore';
import { registerOfflineListener, startSyncService } from 'c/clmOfflineSync';

const CONCURRENCY = 2;

export default class FieldRepHomeClmPrefetch extends LightningElement {
  @track statusLabel = '';
  @track isPrefetching = false;

  unregisterListener;

  connectedCallback() {
    this.unregisterListener = registerOfflineListener((status) => {
      if (status?.phase === 'syncing') {
        this.statusLabel = 'Syncing offline CLM data…';
      } else if (status?.phase === 'idle' && status.synced) {
        this.statusLabel = `Synced ${status.synced} offline action(s)`;
      }
    });
    startSyncService();
    this.schedulePrefetch();
  }

  disconnectedCallback() {
    if (this.unregisterListener) {
      this.unregisterListener();
    }
  }

  schedulePrefetch() {
    const run = () => this.runPrefetch();
    if (typeof window.requestIdleCallback === 'function') {
      window.requestIdleCallback(run, { timeout: 5000 });
    } else {
      // eslint-disable-next-line @lwc/lwc/no-async-operation
      window.setTimeout(run, 1500);
    }
  }

  async runPrefetch() {
    if (!navigator.onLine || this.isPrefetching) {
      return;
    }
    this.isPrefetching = true;
    this.statusLabel = 'Preparing CLM library…';
    try {
      const [manifest, ratingLayout] = await Promise.all([
        getRepPresentationManifest(),
        getDeployedRatingLayoutJson()
      ]);
      if (ratingLayout) {
        await putMeta('ratingLayout', ratingLayout);
      }
      const summaries = (manifest || []).map((entry) => ({
        id: entry.id,
        name: entry.name,
        status: entry.status,
        formatType: entry.formatType,
        productName: entry.productName,
        imageUrl: entry.imageUrl,
        slideCount: entry.slideCount,
        tags: entry.tags
      }));
      await putPresentationList(getUserPresentationListKey(Id), summaries);

      const queue = [];
      for (const entry of manifest || []) {
        const existing = await getManifestEntry(entry.id);
        const existingStamp = existing?.lastModifiedDate
          ? new Date(existing.lastModifiedDate).getTime()
          : 0;
        const nextStamp = entry.lastModifiedDate ? new Date(entry.lastModifiedDate).getTime() : 0;
        if (!existing || existingStamp !== nextStamp) {
          queue.push(entry);
        }
        await putManifestEntry({
          presentationId: entry.id,
          ...entry
        });
      }

      let completed = 0;
      const workers = Array.from({ length: CONCURRENCY }, async () => {
        while (queue.length) {
          const entry = queue.shift();
          if (!entry) {
            break;
          }
          this.statusLabel = `Caching ${entry.name}…`;
          await prefetchPresentationAssets(entry);
          completed += 1;
          this.statusLabel = `Cached ${completed} presentation(s)`;
        }
      });
      await Promise.all(workers);
      this.statusLabel =
        manifest?.length > 0 ? `${manifest.length} CLM(s) ready on device` : 'No CLMs to cache';
    } catch (error) {
      this.statusLabel = 'CLM cache will retry when online';
      // eslint-disable-next-line no-console
      console.warn('CLM prefetch failed', error);
    } finally {
      this.isPrefetching = false;
    }
  }

  get showStatus() {
    return !!this.statusLabel;
  }
}
