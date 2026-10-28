import Id from '@salesforce/user/Id';
import getRepPresentationManifest from '@salesforce/apex/ClmMetricsController.getRepPresentationManifest';
import getDeployedRatingLayoutJson from '@salesforce/apex/ClmMetricsController.getDeployedRatingLayoutJson';
import { exceedsApexDownloadLimit, getCachedPdfPageBlob, hasCachedPackage, prefetchPlayerLibraries, prefetchPresentationAssets, warmPlayerLibraries } from 'c/clmContentCache';
import {
    countPendingActions,
    getManifestEntry,
    getUserPresentationListKey,
    putManifestEntry,
    putMeta,
    putPresentationList
} from 'c/clmOfflineStore';

const CONCURRENCY = 2;
const listeners = new Set();

let inFlight = null;
let lastStatus = {
    phase: 'idle',
    label: '',
    presentationCount: 0,
    cachedCount: 0,
    pending: 0
};

function emit(patch) {
    lastStatus = { ...lastStatus, ...patch };
    listeners.forEach((listener) => {
        try {
            listener(lastStatus);
        } catch (error) {
            // eslint-disable-next-line no-console
            console.warn('CLM prefetch listener failed', error);
        }
    });
}

export function getClmPrefetchStatus() {
    return lastStatus;
}

export function subscribeClmPrefetch(listener) {
    if (typeof listener === 'function') {
        listeners.add(listener);
        listener(lastStatus);
    }
    return () => listeners.delete(listener);
}

function toPlain(value) {
    if (value == null) {
        return value;
    }
    try {
        return JSON.parse(JSON.stringify(value));
    } catch (error) {
        return value;
    }
}

function reduceError(error) {
    return (
        error?.body?.message ||
        error?.body?.pageErrors?.[0]?.message ||
        error?.message ||
        'Unexpected error'
    );
}

function prefetchErrorLabel(error) {
    if (typeof navigator !== 'undefined' && !navigator.onLine) {
        return 'CLM cache will retry when online';
    }
    const message = reduceError(error);
    if (/quota|limit exceeded/i.test(message)) {
        return 'CLM cache is full on this device';
    }
    if (/indexeddb|clone|offline store/i.test(message)) {
        return 'CLM cache could not save on this device';
    }
    return `CLM cache failed: ${message}`;
}

function stampOf(value) {
    return value ? new Date(value).getTime() : 0;
}

async function needsAssetPrefetch(entry, existing) {
    if (!existing || stampOf(existing.lastModifiedDate) !== stampOf(entry.lastModifiedDate)) {
        return true;
    }
    if (!entry.contentDocumentId) {
        return false;
    }
    const format = String(entry.formatType || '').toUpperCase();
    if (format === 'PDF') {
        const pageOne = await getCachedPdfPageBlob(entry.contentDocumentId, 1);
        if (!pageOne) {
            return true;
        }
        if (exceedsApexDownloadLimit(entry.contentSize)) {
            return false;
        }
        return !(await hasCachedPackage(entry.contentDocumentId));
    }
    if (format === 'HTML' || format === 'ZIP') {
        if (exceedsApexDownloadLimit(entry.contentSize)) {
            return false;
        }
        return !(await hasCachedPackage(entry.contentDocumentId));
    }
    return false;
}

async function runPrefetch(component) {
    emit({ phase: 'preparing', label: 'Preparing CLM library…' });
    try {
        try {
            await prefetchPlayerLibraries();
            if (component) {
                emit({ phase: 'preparing', label: 'Loading player…' });
                await warmPlayerLibraries(component);
            }
        } catch (error) {
            // eslint-disable-next-line no-console
            console.warn('CLM library prefetch failed', error);
        }
        const [manifest, ratingLayout] = await Promise.all([
            getRepPresentationManifest(),
            getDeployedRatingLayoutJson()
        ]);
        if (ratingLayout) {
            await putMeta('ratingLayout', ratingLayout);
        }
        const summaries = (manifest || []).map((entry) =>
            toPlain({
                id: entry.id,
                name: entry.name,
                status: entry.status,
                formatType: entry.formatType,
                productName: entry.productName,
                imageUrl: entry.imageUrl,
                slideCount: entry.slideCount,
                tags: entry.tags
            })
        );
        await putPresentationList(getUserPresentationListKey(Id), summaries);

        const queue = [];
        for (const entry of manifest || []) {
            const plain = toPlain({
                presentationId: entry.id,
                ...entry
            });
            const existing = await getManifestEntry(entry.id);
            try {
                if (await needsAssetPrefetch(plain, existing)) {
                    queue.push(plain);
                }
            } catch (error) {
                queue.push(plain);
            }
            try {
                await putManifestEntry(plain);
            } catch (error) {
                // eslint-disable-next-line no-console
                console.warn('CLM manifest save failed', entry.id, error);
            }
        }

        let completed = 0;
        const workers = Array.from({ length: CONCURRENCY }, async () => {
            while (queue.length) {
                const entry = queue.shift();
                if (!entry) {
                    break;
                }
                emit({
                    phase: 'caching',
                    label: `Caching ${entry.name}…`,
                    cachedCount: completed
                });
                await prefetchPresentationAssets(entry, null, component);
                completed += 1;
                emit({
                    phase: 'caching',
                    label: `Cached ${completed} presentation(s)`,
                    cachedCount: completed
                });
            }
        });
        await Promise.all(workers);

        const pending = await countPendingActions();
        const presentationCount = manifest?.length || 0;
        let readyCount = 0;
        for (const entry of manifest || []) {
            if (await isPresentationCached(entry.id)) {
                readyCount += 1;
            }
        }
        let label = 'No CLMs to cache';
        if (presentationCount > 0 && readyCount === presentationCount) {
            label = `${presentationCount} CLM(s) ready on device${pending ? ` · ${pending} pending sync` : ''}`;
        } else if (readyCount > 0) {
            label = `${readyCount} of ${presentationCount} CLM(s) ready on device`;
        } else if (presentationCount > 0) {
            label = 'CLM files are listed, but slides are not cached yet';
        } else if (pending) {
            label = `${pending} action(s) waiting to sync`;
        }
        emit({
            phase: readyCount > 0 ? 'ready' : presentationCount > 0 ? 'error' : 'ready',
            label,
            presentationCount,
            cachedCount: readyCount,
            pending
        });
        return lastStatus;
    } catch (error) {
        emit({ phase: 'error', label: prefetchErrorLabel(error) });
        // eslint-disable-next-line no-console
        console.warn('CLM prefetch failed', error);
        return lastStatus;
    }
}

export async function isPresentationCached(presentationId) {
    const entry = await getManifestEntry(presentationId);
    if (!entry?.contentDocumentId) {
        return false;
    }
    const format = String(entry.formatType || '').toUpperCase();
    if (format === 'PDF') {
        if (exceedsApexDownloadLimit(entry.contentSize)) {
            return !!(await getCachedPdfPageBlob(entry.contentDocumentId, 1));
        }
        const hasPackage = await hasCachedPackage(entry.contentDocumentId);
        const hasPage = await getCachedPdfPageBlob(entry.contentDocumentId, 1);
        return hasPackage || !!hasPage;
    }
    if (format === 'HTML' || format === 'ZIP') {
        return hasCachedPackage(entry.contentDocumentId);
    }
    return false;
}

export async function ensurePresentationCached(presentationId, component) {
    if (await isPresentationCached(presentationId)) {
        return true;
    }
    if (typeof navigator !== 'undefined' && !navigator.onLine) {
        throw new Error('Presentation is not cached. Open the app while online first.');
    }
    emit({ phase: 'caching', label: 'Caching presentation…' });
    try {
        await prefetchPlayerLibraries();
        if (component) {
            await warmPlayerLibraries(component);
        }
        let entry = await getManifestEntry(presentationId);
        if (!entry?.contentDocumentId) {
            const manifest = await getRepPresentationManifest();
            entry = (manifest || []).find((row) => row.id === presentationId);
            if (entry) {
                await putManifestEntry(
                    toPlain({
                        presentationId: entry.id,
                        ...entry
                    })
                );
                entry = await getManifestEntry(presentationId);
            }
        }
        if (!entry) {
            throw new Error('Presentation is not available to cache.');
        }
        await prefetchPresentationAssets(entry, null, component);
    } catch (error) {
        // eslint-disable-next-line no-console
        console.warn('CLM cache on present failed', error);
        if (!(await isPresentationCached(presentationId))) {
            emit({ phase: 'ready', label: 'Presenting without a full device cache' });
            return false;
        }
    }
    emit({
        phase: 'ready',
        label: (await isPresentationCached(presentationId))
            ? 'Presentation cached on device'
            : 'Presenting without a full device cache'
    });
    return !!(await isPresentationCached(presentationId));
}

export function startClmPrefetch(component) {
    if (typeof navigator !== 'undefined' && !navigator.onLine) {
        emit({ phase: 'offline', label: 'Offline mode — using device cache' });
        return Promise.resolve(lastStatus);
    }
    if (inFlight) {
        return inFlight;
    }
    inFlight = runPrefetch(component).finally(() => {
        inFlight = null;
    });
    return inFlight;
}

export function scheduleClmPrefetch(component) {
    const run = () => {
        startClmPrefetch(component);
    };
    if (typeof window === 'undefined') {
        return startClmPrefetch(component);
    }
    if (typeof window.requestIdleCallback === 'function') {
        window.requestIdleCallback(run, { timeout: 5000 });
    } else {
        // eslint-disable-next-line @lwc/lwc/no-async-operation
        window.setTimeout(run, 1500);
    }
    return inFlight;
}