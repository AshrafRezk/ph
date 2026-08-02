import getPdfBase64ForPlayer from '@salesforce/apex/ClmPdfViewerController.getPdfBase64ForPlayer';
import {
    getAsset,
    hashUrl,
    putAsset
} from 'c/clmOfflineStore';

function base64ToUint8Array(base64) {
    const raw = window.atob(base64);
    const bytes = new Uint8Array(raw.length);
    for (let i = 0; i < raw.length; i += 1) {
        bytes[i] = raw.charCodeAt(i);
    }
    return bytes;
}

async function fetchBytesFromUrl(url) {
    const response = await fetch(url, { credentials: 'same-origin' });
    if (!response.ok) {
        throw new Error(`Unable to load asset (HTTP ${response.status}).`);
    }
    return response.arrayBuffer();
}

export async function getPdfBytes(contentDocumentId, fetchNetwork = true) {
    if (!contentDocumentId) {
        return null;
    }
    const assetKey = `pdf_${contentDocumentId}`;
    const cached = await getAsset(assetKey);
    if (cached?.blob) {
        const buffer = cached.blob instanceof ArrayBuffer ? cached.blob : await cached.blob.arrayBuffer();
        return new Uint8Array(buffer);
    }
    if (!fetchNetwork || !navigator.onLine) {
        return null;
    }
    try {
        const downloadUrl = `/sfc/servlet.shepherd/document/download/${encodeURIComponent(contentDocumentId)}`;
        const buffer = await fetchBytesFromUrl(downloadUrl);
        await putAsset(assetKey, buffer, { contentDocumentId, type: 'pdf' });
        return new Uint8Array(buffer);
    } catch (fetchError) {
        const base64 = await getPdfBase64ForPlayer({ contentDocumentId });
        if (!base64) {
            throw fetchError;
        }
        const bytes = base64ToUint8Array(base64);
        await putAsset(assetKey, bytes.buffer, { contentDocumentId, type: 'pdf' });
        return bytes;
    }
}

export async function getSlideBlob(url, fetchNetwork = true) {
    if (!url) {
        return null;
    }
    const assetKey = hashUrl(url);
    const cached = await getAsset(assetKey);
    if (cached?.blob) {
        return cached.blob instanceof Blob ? cached.blob : new Blob([cached.blob]);
    }
    if (!fetchNetwork || !navigator.onLine) {
        return null;
    }
    const buffer = await fetchBytesFromUrl(url);
    const blob = new Blob([buffer]);
    await putAsset(assetKey, blob, { url, type: 'slide' });
    return blob;
}

export async function prefetchPresentationAssets(manifestEntry, onProgress) {
    if (!manifestEntry) {
        return;
    }
    const tasks = [];
    if (manifestEntry.formatType === 'PDF' && manifestEntry.contentDocumentId) {
        tasks.push({
            label: manifestEntry.name,
            run: () => getPdfBytes(manifestEntry.contentDocumentId, true)
        });
    }
    (manifestEntry.sequences || []).forEach((sequence) => {
        const url = sequence.slideImageUrl || sequence.thumbnailUrl;
        if (url) {
            tasks.push({
                label: sequence.sequenceName || url,
                run: () => getSlideBlob(url, true)
            });
        }
    });

    let completed = 0;
    for (const task of tasks) {
        try {
            await task.run();
        } catch (error) {
            // Continue prefetching remaining assets.
            // eslint-disable-next-line no-console
            console.warn('CLM prefetch failed', task.label, error);
        }
        completed += 1;
        if (onProgress) {
            onProgress({ completed, total: tasks.length, presentationName: manifestEntry.name });
        }
    }
}

export function createObjectUrl(blob) {
    if (!blob) {
        return null;
    }
    return URL.createObjectURL(blob instanceof Blob ? blob : new Blob([blob]));
}
