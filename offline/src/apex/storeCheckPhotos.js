import { soql, esc, plannerApiFetch, API_VERSION } from './fieldWorkflowShared.js';

const IMAGE_EXT = new Set(['jpg', 'jpeg', 'png', 'gif', 'webp', 'heic']);

function mimeForExtension(extension) {
    const ext = String(extension || '').toLowerCase();
    if (ext === 'png') return 'image/png';
    if (ext === 'gif') return 'image/gif';
    if (ext === 'webp') return 'image/webp';
    if (ext === 'heic') return 'image/heic';
    return 'image/jpeg';
}

function isBrowserWebClient() {
    try {
        if (globalThis.Capacitor?.isNativePlatform?.()) {
            return false;
        }
    } catch (_err) {
        /* ignore */
    }
    return typeof window !== 'undefined';
}

async function fetchVersionBlob(versionId) {
    const restBase = (typeof globalThis !== 'undefined' && globalThis.PLANNER_REST_BASE) || '';
    const token = (typeof globalThis !== 'undefined' && globalThis.PLANNER_ACCESS_TOKEN) || '';
    const url = `${String(restBase).replace(/\/$/, '')}/services/data/${API_VERSION}/sobjects/ContentVersion/${versionId}/VersionData`;
    let response;
    if (isBrowserWebClient() && token) {
        response = await fetch('/.netlify/functions/sf-api', {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify({
                url,
                method: 'GET',
                authorization: `Bearer ${token}`,
                headers: { Accept: 'application/octet-stream' }
            })
        });
    } else {
        response = await fetch(url, {
            headers: token
                ? { Authorization: `Bearer ${token}`, Accept: 'application/octet-stream' }
                : { Accept: 'application/octet-stream' }
        });
    }
    if (!response.ok) {
        throw new Error(`Unable to load photo (HTTP ${response.status}).`);
    }
    return response.blob();
}

function blobToDataUrl(blob) {
    return new Promise((resolve, reject) => {
        const reader = new FileReader();
        reader.onload = () => resolve(String(reader.result || ''));
        reader.onerror = () => reject(reader.error || new Error('Could not read photo.'));
        reader.readAsDataURL(blob);
    });
}

export async function loadStoreCheckPhotos(storeCheckId) {
    if (!storeCheckId) {
        return [];
    }
    const links = await soql(
        'SELECT ContentDocumentId, ContentDocument.Title, ContentDocument.FileExtension, ' +
            'ContentDocument.LatestPublishedVersionId FROM ContentDocumentLink ' +
            `WHERE LinkedEntityId = '${esc(storeCheckId)}' ORDER BY SystemModstamp DESC`
    );
    const photos = [];
    for (const link of links) {
        const extension = String(link.ContentDocument?.FileExtension || '').toLowerCase();
        if (extension && !IMAGE_EXT.has(extension)) {
            continue;
        }
        const versionId = link.ContentDocument?.LatestPublishedVersionId || null;
        let previewUrl = null;
        if (versionId) {
            try {
                const blob = await fetchVersionBlob(versionId);
                const typed = new Blob([await blob.arrayBuffer()], { type: mimeForExtension(extension) });
                previewUrl = await blobToDataUrl(typed);
            } catch (_err) {
                previewUrl = null;
            }
        }
        photos.push({
            contentDocumentId: link.ContentDocumentId,
            contentVersionId: versionId,
            title: link.ContentDocument?.Title || 'Store check photo',
            previewUrl
        });
    }
    return photos;
}

export async function ensureStoreCheckId(visit) {
    const existing = await soql(
        `SELECT Id FROM Store_Check__c WHERE Visit__c = '${esc(visit.Id)}' ORDER BY CreatedDate DESC LIMIT 1`
    );
    if (existing.length) {
        return existing[0].Id;
    }
    const created = await plannerApiFetch(`/services/data/${API_VERSION}/sobjects/Store_Check__c`, {
        method: 'POST',
        body: JSON.stringify({
            Visit__c: visit.Id,
            Account__c: visit.Account__c || null
        })
    });
    if (!created?.id) {
        throw new Error('Unable to start the store check.');
    }
    return created.id;
}
