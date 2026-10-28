import { makeDualApex } from './_wireAdapter.js';
import { apexError } from './learningShared.js';
import { requireUnlockedVisit, createSObject } from './fieldWorkflowShared.js';
import { ensureStoreCheckId } from './storeCheckPhotos.js';
import getStoreCheck from './getStoreCheck.js';

function safeFileName(fileName) {
    const name = String(fileName || 'store-check.jpg').trim() || 'store-check.jpg';
    const lower = name.toLowerCase();
    if (lower.endsWith('.jpg') || lower.endsWith('.jpeg') || lower.endsWith('.png')) {
        return name;
    }
    return `${name}.jpg`;
}

export default makeDualApex(async (params = {}) => {
    const visit = await requireUnlockedVisit(params.visitId);
    const base64Data = String(params.base64Data || '').trim();
    if (!base64Data) {
        throw apexError('Choose a photo to upload.');
    }
    const storeCheckId = await ensureStoreCheckId(visit);
    const fileName = safeFileName(params.fileName);
    const title = fileName.replace(/\.[^.]+$/, '') || 'Store check photo';
    await createSObject('ContentVersion', {
        Title: title,
        PathOnClient: fileName,
        VersionData: base64Data,
        FirstPublishLocationId: storeCheckId
    });
    return getStoreCheck({ visitId: visit.Id });
});
