const DB_NAME = 'pharmaClmOffline';
const DB_VERSION = 3;

const STORES = {
    manifest: { name: 'manifest', keyPath: 'presentationId' },
    assets: { name: 'assets', keyPath: 'assetKey' },
    presentationList: { name: 'presentationList', keyPath: 'userKey' },
    localSessions: { name: 'localSessions', keyPath: 'clientSessionKey' },
    actionQueue: { name: 'actionQueue', keyPath: 'id', autoIncrement: true },
    ratingContext: { name: 'ratingContext', keyPath: 'visitId' },
    visitPayloads: { name: 'visitPayloads', keyPath: 'visitId' },
    todayPlan: { name: 'todayPlan', keyPath: 'userKey' },
    meta: { name: 'meta', keyPath: 'key' },
    plannerCache: { name: 'plannerCache', keyPath: 'userKey' },
    homeMetrics: { name: 'homeMetrics', keyPath: 'userKey' },
    coachingContext: { name: 'coachingContext', keyPath: 'visitId' },
    clientKeyMap: { name: 'clientKeyMap', keyPath: 'clientKey' }
};

let dbPromise = null;

function openDatabase() {
    if (dbPromise) {
        return dbPromise;
    }
    dbPromise = new Promise((resolve, reject) => {
        if (!window.indexedDB) {
            reject(new Error('IndexedDB is not available.'));
            return;
        }
        const request = window.indexedDB.open(DB_NAME, DB_VERSION);
        request.onupgradeneeded = () => {
            const db = request.result;
            Object.values(STORES).forEach((store) => {
                if (!db.objectStoreNames.contains(store.name)) {
                    const options = store.autoIncrement
                        ? { keyPath: store.keyPath, autoIncrement: true }
                        : { keyPath: store.keyPath };
                    db.createObjectStore(store.name, options);
                }
            });
        };
        request.onsuccess = () => resolve(request.result);
        request.onerror = () => reject(request.error || new Error('Unable to open offline store.'));
    });
    return dbPromise;
}

function isIdbRequest(value) {
    return value != null && typeof value === 'object' && 'readyState' in value && 'result' in value;
}

function toArray(value) {
    return Array.isArray(value) ? value : [];
}

async function withStore(storeName, mode, callback) {
    const db = await openDatabase();
    return new Promise((resolve, reject) => {
        const transaction = db.transaction(storeName, mode);
        const store = transaction.objectStore(storeName);
        let result;
        try {
            result = callback(store);
        } catch (error) {
            reject(error);
            return;
        }
        if (isIdbRequest(result)) {
            result.onsuccess = () => resolve(result.result);
            result.onerror = () => reject(result.error || new Error('IndexedDB request failed.'));
            return;
        }
        transaction.oncomplete = () => resolve(result);
        transaction.onerror = () => reject(transaction.error);
        transaction.onabort = () => reject(transaction.error || new Error('Transaction aborted.'));
    });
}

export async function putManifestEntry(entry) {
    return withStore(STORES.manifest.name, 'readwrite', (store) =>
        store.put({ ...entry, presentationId: entry.presentationId || entry.id })
    );
}

export async function getManifestEntry(presentationId) {
    return withStore(STORES.manifest.name, 'readonly', (store) => store.get(presentationId));
}

export async function getAllManifestEntries() {
    return withStore(STORES.manifest.name, 'readonly', (store) => {
        const request = store.getAll();
        return request;
    });
}

export async function putPresentationList(userKey, presentations, syncedAt = new Date().toISOString()) {
    return withStore(STORES.presentationList.name, 'readwrite', (store) =>
        store.put({ userKey, presentations, syncedAt })
    );
}

export async function getPresentationList(userKey) {
    return withStore(STORES.presentationList.name, 'readonly', (store) => store.get(userKey));
}

export async function putAsset(assetKey, blob, metadata = {}) {
    return withStore(STORES.assets.name, 'readwrite', (store) =>
        store.put({
            assetKey,
            blob,
            cachedAt: new Date().toISOString(),
            size: blob?.size || blob?.byteLength || 0,
            ...metadata
        })
    );
}

export async function getAsset(assetKey) {
    const row = await withStore(STORES.assets.name, 'readonly', (store) => store.get(assetKey));
    return row || null;
}

export async function putLocalSession(session) {
    return withStore(STORES.localSessions.name, 'readwrite', (store) => store.put(session));
}

export async function getLocalSession(clientSessionKey) {
    return withStore(STORES.localSessions.name, 'readonly', (store) => store.get(clientSessionKey));
}

export async function updateLocalSession(clientSessionKey, patch) {
    const existing = await getLocalSession(clientSessionKey);
    if (!existing) {
        return null;
    }
    const updated = { ...existing, ...patch };
    await putLocalSession(updated);
    return updated;
}

export async function enqueueAction(action) {
    return withStore(STORES.actionQueue.name, 'readwrite', (store) =>
        store.add({
            ...action,
            status: action.status || 'pending',
            retries: action.retries || 0,
            createdAt: action.createdAt || new Date().toISOString()
        })
    );
}

export async function getPendingActions() {
    const rows = await withStore(STORES.actionQueue.name, 'readonly', (store) => store.getAll());
    return toArray(rows)
        .filter((row) => row.status === 'pending' || row.status === 'failed')
        .sort((a, b) => (a.id || 0) - (b.id || 0));
}

export async function countPendingActions() {
    const pending = await getPendingActions();
    return pending.length;
}

export async function updateAction(id, patch) {
    const row = await withStore(STORES.actionQueue.name, 'readonly', (store) => store.get(id));
    if (!row) {
        return null;
    }
    const updated = { ...row, ...patch };
    await withStore(STORES.actionQueue.name, 'readwrite', (store) => store.put(updated));
    return updated;
}

export async function removeAction(id) {
    return withStore(STORES.actionQueue.name, 'readwrite', (store) => store.delete(id));
}

export async function putRatingContext(visitId, context) {
    return withStore(STORES.ratingContext.name, 'readwrite', (store) =>
        store.put({ visitId, context, cachedAt: new Date().toISOString() })
    );
}

export async function getRatingContext(visitId) {
    const row = await withStore(STORES.ratingContext.name, 'readonly', (store) => store.get(visitId));
    return row?.context || null;
}

export async function putMeta(key, value) {
    return withStore(STORES.meta.name, 'readwrite', (store) => store.put({ key, value }));
}

export async function getMeta(key) {
    const row = await withStore(STORES.meta.name, 'readonly', (store) => store.get(key));
    return row?.value ?? null;
}

export function hashUrl(url) {
    let hash = 0;
    const value = String(url || '');
    for (let i = 0; i < value.length; i += 1) {
        hash = (hash << 5) - hash + value.charCodeAt(i);
        hash |= 0;
    }
    return `url_${Math.abs(hash)}`;
}

export function getUserPresentationListKey(userId) {
    return `presentations_${userId || 'anonymous'}`;
}

export function getUserTodayPlanKey(userId) {
    return `todayPlan_${userId || 'anonymous'}`;
}

export function getUserPlannerCacheKey(userId) {
    return `planner_${userId || 'anonymous'}`;
}

export function getUserHomeMetricsKey(userId) {
    return `homeMetrics_${userId || 'anonymous'}`;
}

export async function putVisitPayload(visitId, payload) {
    return withStore(STORES.visitPayloads.name, 'readwrite', (store) =>
        store.put({ visitId, payload, cachedAt: new Date().toISOString() })
    );
}

export async function getVisitPayload(visitId) {
    const row = await withStore(STORES.visitPayloads.name, 'readonly', (store) => store.get(visitId));
    return row?.payload || null;
}

export async function putTodayPlan(userKey, visits) {
    return withStore(STORES.todayPlan.name, 'readwrite', (store) =>
        store.put({ userKey, visits, cachedAt: new Date().toISOString() })
    );
}

export async function getTodayPlan(userKey) {
    const row = await withStore(STORES.todayPlan.name, 'readonly', (store) => store.get(userKey));
    return row?.visits || null;
}

export async function putPlannerCache(userKey, payload) {
    return withStore(STORES.plannerCache.name, 'readwrite', (store) =>
        store.put({ userKey, payload, cachedAt: new Date().toISOString() })
    );
}

export async function getPlannerCache(userKey) {
    const row = await withStore(STORES.plannerCache.name, 'readonly', (store) => store.get(userKey));
    return row?.payload || null;
}

export async function putHomeMetrics(userKey, metrics) {
    return withStore(STORES.homeMetrics.name, 'readwrite', (store) =>
        store.put({ userKey, metrics, cachedAt: new Date().toISOString() })
    );
}

export async function getHomeMetricsCache(userKey) {
    const row = await withStore(STORES.homeMetrics.name, 'readonly', (store) => store.get(userKey));
    return row?.metrics || null;
}

export async function putCoachingContext(visitId, context) {
    return withStore(STORES.coachingContext.name, 'readwrite', (store) =>
        store.put({ visitId, context, cachedAt: new Date().toISOString() })
    );
}

export async function getCoachingContext(visitId) {
    const row = await withStore(STORES.coachingContext.name, 'readonly', (store) => store.get(visitId));
    return row?.context || null;
}

export async function putClientKeyMapping(clientKey, mapping) {
    return withStore(STORES.clientKeyMap.name, 'readwrite', (store) =>
        store.put({
            clientKey,
            ...mapping,
            updatedAt: new Date().toISOString()
        })
    );
}

export async function getClientKeyMapping(clientKey) {
    return withStore(STORES.clientKeyMap.name, 'readonly', (store) => store.get(clientKey));
}

export function newClientKey(prefix) {
    const rand =
        typeof crypto !== 'undefined' && crypto.randomUUID
            ? crypto.randomUUID()
            : `${Date.now()}_${Math.random().toString(36).slice(2, 10)}`;
    return `${prefix || 'key'}_${rand}`;
}
