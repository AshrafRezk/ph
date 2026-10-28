/**
 * Shared IndexedDB + cache-first Salesforce GET for standalone pages
 * (list.html / record.html). Same DB and sfrest: keys as the PWA shell.
 */
const DB_NAME = 'zeta.pwa.analytics';
const DB_VERSION = 1;
const STORE = 'payloads';
const GET_CACHE_PREFIX = 'sfrest:';
const AUTO_OFFLINE_KEY = 'zeta.pwa.autoOffline';

const ENTITY_LIST_PREFIX = 'entity:listPage:v1:';
const ENTITY_DESCRIBE_PREFIX = 'entity:describe:v1:';
const ENTITY_LISTVIEWS_PREFIX = 'entity:listViews:v1:';

let dbPromise = null;

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
        request.onerror = () => reject(request.error || new Error('Unable to open cache.'));
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

export async function idbPayload(key) {
    const wrap = await idbGet(key);
    if (!wrap) return null;
    return wrap.payload !== undefined ? wrap.payload : wrap;
}

export function listPageKey(objectApiName, listViewId = null) {
    const obj = String(objectApiName || '').trim();
    const view = listViewId ? String(listViewId) : 'default';
    return `${ENTITY_LIST_PREFIX}${obj}:${view}`;
}

export function describeEntityKey(objectApiName) {
    return `${ENTITY_DESCRIBE_PREFIX}${String(objectApiName || '').trim()}`;
}

export function listViewsEntityKey(objectApiName) {
    return `${ENTITY_LISTVIEWS_PREFIX}${String(objectApiName || '').trim()}`;
}

function sfInstance() {
    return (
        (typeof globalThis !== 'undefined' && globalThis.PLANNER_SF_INSTANCE) ||
        (typeof localStorage !== 'undefined' && localStorage.getItem('zeta.pwa.sfInstanceUrl')) ||
        ''
    );
}

function apiToken() {
    try {
        const stored = localStorage.getItem('zeta.pwa.sfAccessToken') || '';
        if (stored) return stored;
    } catch (_err) {
        /* ignore */
    }
    return (typeof globalThis !== 'undefined' && globalThis.PLANNER_ACCESS_TOKEN) || '';
}

async function refreshShellToken() {
    const host = window.parent && window.parent !== window ? window.parent : window;
    const refresh = host.refreshPlannerAccessToken;
    if (typeof refresh !== 'function') {
        throw new Error('Session expired. Sign in again in the main app.');
    }
    await refresh();
    return apiToken();
}

function shouldSkipNetwork() {
    if (typeof navigator !== 'undefined' && navigator.onLine === false) return true;
    try {
        if (localStorage.getItem(AUTO_OFFLINE_KEY) === '1') {
            localStorage.removeItem(AUTO_OFFLINE_KEY);
        }
    } catch (_err) {
        /* ignore */
    }
    return false;
}

function absoluteUrl(path, apiVersion) {
    const base = String(sfInstance()).replace(/\/$/, '');
    if (!path) return base;
    if (/^https?:\/\//i.test(path)) return path;
    if (path.startsWith('/services/')) return `${base}${path}`;
    const suffix = path.startsWith('/') ? path : `/${path}`;
    return `${base}/services/data/${apiVersion}${suffix}`;
}

function cacheKeyForPath(fullPath) {
    if (!fullPath) return null;
    if (fullPath.startsWith('/services/')) return GET_CACHE_PREFIX + fullPath;
    if (/^https?:\/\//i.test(fullPath)) {
        try {
            const u = new URL(fullPath);
            return GET_CACHE_PREFIX + u.pathname + u.search;
        } catch (_err) {
            return GET_CACHE_PREFIX + fullPath;
        }
    }
    return GET_CACHE_PREFIX + `/services/data/${fullPath}`;
}

/**
 * Store-review demo (src/demo/demoMode.js): embedded pages borrow the shell's fetch, which
 * answers Salesforce calls from sample data. Same origin, so the parent is reachable.
 */
function shellFetch() {
    try {
        if (window.localStorage.getItem('zeta.pwa.demoMode') === '1' && window.parent !== window) {
            return window.parent.fetch.bind(window.parent);
        }
    } catch (_err) {
        /* cross-origin or storage blocked */
    }
    return fetch;
}

async function networkGet(url, token, retried = false) {
    const fetch = shellFetch();
    try {
        const proxied = await fetch('/.netlify/functions/sf-api', {
            method: 'POST',
            headers: { 'Content-Type': 'application/json', Accept: 'application/json' },
            body: JSON.stringify({
                url,
                method: 'GET',
                authorization: `Bearer ${token}`
            })
        });
        if (proxied.ok) return proxied.json();
        if (proxied.status === 401 && !retried) {
            const next = await refreshShellToken();
            return networkGet(url, next, true);
        }
        if (proxied.status === 401) {
            throw new Error('Session expired. Sign in again in the main app.');
        }
        if (proxied.status !== 404) {
            let detail = `HTTP ${proxied.status}`;
            try {
                const err = await proxied.json();
                const first = Array.isArray(err) ? err[0] : err;
                detail = first?.message || detail;
            } catch (_e) {
                /* keep */
            }
            throw new Error(detail);
        }
    } catch (err) {
        if (err && err.message && err.message.includes('Session expired')) throw err;
        if (err && err.message && !/failed to fetch|networkerror/i.test(err.message) && !err.message.startsWith('HTTP')) {
            /* fall through to direct */
        } else if (err && err.message && err.message.startsWith('HTTP')) {
            throw err;
        }
    }
    const resp = await fetch(url, {
        method: 'GET',
        headers: {
            Accept: 'application/json',
            Authorization: `Bearer ${token}`
        }
    });
    if (resp.status === 401 && !retried) {
        const next = await refreshShellToken();
        return networkGet(url, next, true);
    }
    if (resp.status === 401) {
        throw new Error('Session expired. Sign in again in the main app.');
    }
    if (!resp.ok) {
        let detail = `HTTP ${resp.status}`;
        try {
            const err = await resp.json();
            const first = Array.isArray(err) ? err[0] : err;
            detail = first?.message || detail;
        } catch (_err) {
            /* keep */
        }
        throw new Error(detail);
    }
    return resp.json();
}

/**
 * Cache-first GET. Relative paths are under /services/data/{apiVersion}.
 * Absolute /services/... or full URLs (nextRecordsUrl) also work.
 */
export async function sfCacheGet(path, { apiVersion = 'v62.0', fresh = false } = {}) {
    const token = apiToken();
    if (!token) {
        throw new Error('Not signed in. Open the app, sign in with Salesforce, then try again.');
    }
    const url = absoluteUrl(path, apiVersion);
    let cachePath;
    if (path.startsWith('/services/')) {
        cachePath = path;
    } else if (/^https?:\/\//i.test(path)) {
        try {
            const u = new URL(path);
            cachePath = u.pathname + u.search;
        } catch (_err) {
            cachePath = path;
        }
    } else {
        const rel = path.startsWith('/') ? path : `/${path}`;
        cachePath = `/services/data/${apiVersion}${rel}`;
    }
    const key = GET_CACHE_PREFIX + cachePath;

    if (!fresh) {
        const cached = await idbPayload(key);
        if (cached != null) {
            if (!shouldSkipNetwork()) {
                networkGet(url, token)
                    .then((data) => idbSet(key, data))
                    .catch(() => {});
            }
            return cached;
        }
    }

    if (shouldSkipNetwork()) {
        const cached = await idbPayload(key);
        if (cached != null) return cached;
        throw new Error('Offline — no cached response for this request.');
    }

    try {
        const data = await networkGet(url, token);
        await idbSet(key, data);
        return data;
    } catch (error) {
        const cached = await idbPayload(key);
        if (cached != null) return cached;
        throw error;
    }
}

export { GET_CACHE_PREFIX, ENTITY_LIST_PREFIX };
