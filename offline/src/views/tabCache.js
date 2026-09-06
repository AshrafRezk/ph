const LS_PREFIX = 'zeta.pwa.tab.';
const DB_NAME = 'zeta.pwa.analytics';
const DB_VERSION = 1;
const STORE = 'payloads';

let dbPromise = null;

export function cacheRead(key) {
    try {
        const raw = localStorage.getItem(LS_PREFIX + key);
        if (!raw) return null;
        const parsed = JSON.parse(raw);
        if (!parsed || typeof parsed !== 'object') return null;
        return parsed;
    } catch (_err) {
        return null;
    }
}

export function cacheWrite(key, payload) {
    try {
        localStorage.setItem(
            LS_PREFIX + key,
            JSON.stringify({ savedAt: Date.now(), payload })
        );
    } catch (_err) {
        /* storage full */
    }
}

export function cachePayload(key) {
    const wrap = cacheRead(key);
    return wrap ? wrap.payload : null;
}

function openDb() {
    if (dbPromise) return dbPromise;
    dbPromise = new Promise((resolve, reject) => {
        if (typeof indexedDB === 'undefined') {
            reject(new Error('IndexedDB is not available.'));
            return;
        }
        const request = indexedDB.open(DB_NAME, DB_VERSION);
        request.onupgradeneeded = () => {
            const db = request.result;
            if (!db.objectStoreNames.contains(STORE)) {
                db.createObjectStore(STORE);
            }
        };
        request.onsuccess = () => resolve(request.result);
        request.onerror = () => reject(request.error || new Error('Unable to open analytics cache.'));
    });
    return dbPromise;
}

export async function idbGet(key) {
    try {
        const db = await openDb();
        return await new Promise((resolve, reject) => {
            const tx = db.transaction(STORE, 'readonly');
            const req = tx.objectStore(STORE).get(key);
            req.onsuccess = () => resolve(req.result || null);
            req.onerror = () => reject(req.error);
        });
    } catch (_err) {
        return null;
    }
}

export async function idbSet(key, value) {
    try {
        const db = await openDb();
        await new Promise((resolve, reject) => {
            const tx = db.transaction(STORE, 'readwrite');
            const req = tx.objectStore(STORE).put({ savedAt: Date.now(), payload: value }, key);
            req.onsuccess = () => resolve();
            req.onerror = () => reject(req.error);
        });
    } catch (_err) {
        /* ignore */
    }
}
