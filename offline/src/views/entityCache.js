/**
 * Structured entity list / describe cache in the shared analytics IndexedDB.
 * Keys are also warmed by offlineBootstrap and read by public/list.js via sfRestCache.
 */
import { idbGet, idbSet } from './tabCache.js';

export const ENTITY_LIST_PREFIX = 'entity:listPage:v1:';
export const ENTITY_DESCRIBE_PREFIX = 'entity:describe:v1:';
export const ENTITY_LISTVIEWS_PREFIX = 'entity:listViews:v1:';
export const PAGE_SIZE = 25;

export function listPageKey(objectApiName, listViewId = null) {
    const obj = String(objectApiName || '').trim();
    const view = listViewId ? String(listViewId) : 'default';
    return `${ENTITY_LIST_PREFIX}${obj}:${view}`;
}

export function describeKey(objectApiName) {
    return `${ENTITY_DESCRIBE_PREFIX}${String(objectApiName || '').trim()}`;
}

export function listViewsKey(objectApiName) {
    return `${ENTITY_LISTVIEWS_PREFIX}${String(objectApiName || '').trim()}`;
}

export async function getEntityListPage(objectApiName, listViewId = null) {
    const wrap = await idbGet(listPageKey(objectApiName, listViewId));
    if (!wrap) return null;
    return wrap.payload !== undefined ? wrap.payload : wrap;
}

export async function putEntityListPage(objectApiName, listViewId, payload) {
    if (!objectApiName || !payload) return;
    await idbSet(listPageKey(objectApiName, listViewId), payload);
}

export async function getEntityDescribe(objectApiName) {
    const wrap = await idbGet(describeKey(objectApiName));
    if (!wrap) return null;
    return wrap.payload !== undefined ? wrap.payload : wrap;
}

export async function putEntityDescribe(objectApiName, describe) {
    if (!objectApiName || !describe) return;
    await idbSet(describeKey(objectApiName), describe);
}

export async function getEntityListViews(objectApiName) {
    const wrap = await idbGet(listViewsKey(objectApiName));
    if (!wrap) return null;
    return wrap.payload !== undefined ? wrap.payload : wrap;
}

export async function putEntityListViews(objectApiName, views) {
    if (!objectApiName) return;
    await idbSet(listViewsKey(objectApiName), views || []);
}

/** Unique Entity object API names from org apps (tabs with type Entity / objectApiName). */
export function collectEntityObjects(apps) {
    const seen = new Set();
    const out = [];
    (apps || []).forEach((app) => {
        (app.tabs || []).forEach((tab) => {
            const obj =
                tab &&
                (tab.objectApiName ||
                    (tab.type === 'Entity' ? tab.key : null));
            if (!obj || typeof obj !== 'string') return;
            if (/^standard-/i.test(obj)) return;
            // Some tab keys are record ids (0M0…, 0Rb…), not objects; describing them only returns 404.
            if (!/^[A-Za-z][A-Za-z0-9_]*$/.test(obj)) return;
            if (seen.has(obj)) return;
            seen.add(obj);
            out.push(obj);
        });
    });
    return out;
}
