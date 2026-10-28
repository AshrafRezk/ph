// Salesforce REST fetch with GET cache and connectivity signals.
// Offline mode for compiled LWCs is driven by `c/clmOfflineSync` via window events
// (avoids a circular import with the outbox drain).

import { idbGet, idbSet } from '../views/tabCache.js';
import {
    isRefreshRejected,
    notifySessionInvalid,
    readAccessToken,
    readRefreshToken,
    refreshAccessToken
} from '../sfSession.js';
import { readLoginAs } from '../loginAs.js';

const GET_CACHE_PREFIX = 'sfrest:';
const NETWORK_EVENT = 'zeta-network-status';
export const SFREST_UPDATED_EVENT = 'zeta-sfrest-updated';
// Same key as `c/clmOfflineSync` — read from storage so this file never imports the sync module.
const AUTO_OFFLINE_KEY = 'zeta.pwa.autoOffline';
export const LAST_ONLINE_AT_KEY = 'zeta.pwa.lastOnlineAt';
const ONE_HOUR_MS = 60 * 60 * 1000;
const TWENTY_FOUR_HOURS_MS = 24 * ONE_HOUR_MS;

let lastOnline = typeof navigator === 'undefined' || navigator.onLine !== false;
const refreshInflight = new Map();

export function readLastOnlineAt() {
    try {
        const raw = typeof localStorage !== 'undefined' ? localStorage.getItem(LAST_ONLINE_AT_KEY) : null;
        if (!raw) {
            return null;
        }
        const ms = Date.parse(raw);
        return Number.isFinite(ms) ? ms : null;
    } catch (_err) {
        return null;
    }
}

export function writeLastOnlineAt(date = new Date()) {
    try {
        if (typeof localStorage === 'undefined') {
            return;
        }
        localStorage.setItem(LAST_ONLINE_AT_KEY, new Date(date).toISOString());
    } catch (_err) {
        /* ignore */
    }
}

export function hoursSinceLastOnline(now = Date.now()) {
    const last = readLastOnlineAt();
    if (last == null) {
        return null;
    }
    return Math.max(0, (now - last) / ONE_HOUR_MS);
}

export function isStaleOfflineBeyond24h(now = Date.now()) {
    const last = readLastOnlineAt();
    if (last == null) {
        return false;
    }
    return now - last >= TWENTY_FOUR_HOURS_MS;
}

export function isStaleOnlineBeyond1h(now = Date.now()) {
    const last = readLastOnlineAt();
    if (last == null) {
        return false;
    }
    return now - last >= ONE_HOUR_MS;
}

export function formatHoursAgo(hours) {
    if (hours == null || !Number.isFinite(hours)) {
        return 'some time';
    }
    const rounded = Math.max(1, Math.round(hours));
    return `${rounded} hour${rounded === 1 ? '' : 's'}`;
}

function browserReportsOffline() {
    return typeof navigator !== 'undefined' && navigator.onLine === false;
}

function clearStuckOfflineFlag() {
    if (browserReportsOffline()) {
        return;
    }
    try {
        if (typeof localStorage !== 'undefined' && localStorage.getItem(AUTO_OFFLINE_KEY) === '1') {
            localStorage.removeItem(AUTO_OFFLINE_KEY);
        }
    } catch (_err) {
        /* ignore */
    }
}

export function isOffline() {
    clearStuckOfflineFlag();
    return browserReportsOffline();
}

function isNavigatorOffline() {
    return typeof navigator !== 'undefined' && navigator.onLine === false;
}

function isAutoOffline() {
    try {
        return typeof localStorage !== 'undefined' && localStorage.getItem(AUTO_OFFLINE_KEY) === '1';
    } catch (_err) {
        return false;
    }
}

function shouldSkipGetNetwork() {
    clearStuckOfflineFlag();
    return isNavigatorOffline();
}

function emitNetworkStatus(online) {
    if (lastOnline === online) {
        return;
    }
    lastOnline = online;
    try {
        window.dispatchEvent(new CustomEvent(NETWORK_EVENT, { detail: { online } }));
    } catch (_err) {
        /* ignore */
    }
}

export function markNetworkAvailable() {
    writeLastOnlineAt();
    emitNetworkStatus(true);
}

export function markNetworkUnavailable() {
    emitNetworkStatus(false);
}

export function isNetworkError(error) {
    if (!error) {
        return false;
    }
    if (error.name === 'AbortError' || error.name === 'TimeoutError') {
        return true;
    }
    const message = String(error.message || error || '');
    return /failed to fetch|networkerror|load failed|network error|offline|aborterror|internet connection|the request timed out/i.test(
        message
    );
}

function isBrowserWebClient() {
    try {
        const Cap = globalThis.Capacitor;
        if (Cap?.isNativePlatform?.()) return false;
    } catch {
        /* ignore */
    }
    return typeof window !== 'undefined';
}

function cacheKeyFor(path, method) {
    if (String(method || 'GET').toUpperCase() !== 'GET') {
        return null;
    }
    return GET_CACHE_PREFIX + String(path || '');
}

async function readGetCache(key) {
    if (!key) {
        return null;
    }
    const wrap = await idbGet(key);
    if (!wrap) {
        return null;
    }
    return wrap.payload !== undefined ? wrap.payload : wrap;
}

async function writeGetCache(key, value) {
    if (!key || value == null) {
        return;
    }
    await idbSet(key, value);
}

function samePayload(left, right) {
    try {
        return JSON.stringify(left) === JSON.stringify(right);
    } catch (_err) {
        return false;
    }
}

function emitCacheUpdated(path, data) {
    try {
        window.dispatchEvent(new CustomEvent(SFREST_UPDATED_EVENT, { detail: { path, data } }));
    } catch (_err) {
        /* ignore */
    }
}

function leafStrings(value) {
    if (typeof value === 'string') return value ? [value] : [];
    if (!value || typeof value !== 'object') return [];
    return Object.values(value).flatMap(leafStrings);
}

function sanitizeRestMessage(raw) {
    let message = String(raw || '').trim();
    if (!message || /script-thrown exception/i.test(message)) {
        return 'Something went wrong. Please try again.';
    }
    message = message
        .replace(/FIELD_CUSTOM_VALIDATION_EXCEPTION[,:]\s*/gi, '')
        .replace(/REQUIRED_FIELD_MISSING[,:]\s*/gi, '')
        .replace(/^HTTP\s+\d+\s*-?\s*/i, '')
        .trim();
    return message || 'Something went wrong. Please try again.';
}

function isInvalidSession(status, detail) {
    if (status === 401) return true;
    return /invalid_session_id|session expired or invalid/i.test(String(detail || ''));
}

async function doNetworkFetch(path, options = {}) {
    const restBase = (typeof globalThis !== 'undefined' && globalThis.PLANNER_REST_BASE) || '';
    const token =
        (typeof globalThis !== 'undefined' && globalThis.PLANNER_ACCESS_TOKEN) || readAccessToken();
    const headers = { Accept: 'application/json', ...(options.headers || {}) };
    if (token) {
        headers.Authorization = `Bearer ${token}`;
    }
    if (options.body && !headers['Content-Type']) {
        headers['Content-Type'] = 'application/json';
    }
    const fullUrl = `${String(restBase).replace(/\/$/, '')}${path}`;
    const method = options.method || 'GET';
    const key = cacheKeyFor(path, method);
    const timeoutMs = Number(options.timeoutMs) > 0 ? Number(options.timeoutMs) : 30000;
    const controller = new AbortController();
    const timeoutId = setTimeout(() => controller.abort(), timeoutMs);
    let response;
    try {
        try {
            if (isBrowserWebClient() && token) {
                response = await fetch('/.netlify/functions/sf-api', {
                    method: 'POST',
                    headers: { 'Content-Type': 'application/json', Accept: 'application/json' },
                    body: JSON.stringify({
                        url: fullUrl,
                        method,
                        authorization: `Bearer ${token}`,
                        body: options.body ?? null,
                        headers: { Accept: 'application/json', ...(options.headers || {}) }
                    }),
                    signal: controller.signal
                });
            } else {
                response = await fetch(fullUrl, {
                    method,
                    credentials: token ? 'omit' : 'same-origin',
                    headers,
                    body: options.body,
                    signal: controller.signal
                });
            }
        } catch (fetchError) {
            markNetworkUnavailable();
            throw new Error('Could not reach Salesforce. Check your connection and try again.');
        }

        if (!response.ok) {
            if (response.status === 0 || response.status >= 500) {
                markNetworkUnavailable();
            }
            let detail = `HTTP ${response.status}`;
            try {
                const failed = await response.json();
                if (Array.isArray(failed) && failed[0] && failed[0].message) {
                    detail = failed[0].message;
                } else if (Array.isArray(failed) && failed[0] && failed[0].dashboardErrors) {
                    detail = [...new Set(leafStrings(failed[0].dashboardErrors))].join(' ') || detail;
                } else if (failed && typeof failed === 'object') {
                    detail = failed.message || failed.error || detail;
                }
            } catch (_parseError) {
                try {
                    const text = await response.text();
                    detail = text ? `${detail} - ${text.substring(0, 200)}` : detail;
                } catch (_textErr) {
                    /* keep detail */
                }
            }
            if (isInvalidSession(response.status, detail) && !options._authRetried && readRefreshToken()) {
                try {
                    await refreshAccessToken();
                } catch (refreshError) {
                    if (isRefreshRejected(refreshError)) {
                        notifySessionInvalid();
                        throw new Error('Your session expired. Sign in again to continue.');
                    }
                    throw new Error('Could not refresh your Salesforce session. Check your connection and try again.');
                }
                return await doNetworkFetch(path, { ...options, _authRetried: true });
            }
            if (isInvalidSession(response.status, detail) && !readRefreshToken() && readLoginAs()) {
                // SFE Login As has no refresh token: end it cleanly when the org session times out.
                notifySessionInvalid();
            }
            if (isInvalidSession(response.status, detail)) {
                throw new Error('Your session expired. Sign in again to continue.');
            }
            if (response.status === 0 || response.status >= 500) {
                throw new Error('Could not reach Salesforce. Check your connection and try again.');
            }
            throw new Error(sanitizeRestMessage(detail));
        }

        markNetworkAvailable();
        if (response.status === 204) {
            return null;
        }
        const contentType = response.headers.get('content-type');
        if (!contentType || !contentType.includes('application/json')) {
            const text = await response.text();
            throw new Error(
                `Expected JSON response but got ${contentType || 'unknown'}: ${text.substring(0, 200)}`
            );
        }
        const data = await response.json();
        if (key) {
            writeGetCache(key, data).catch(() => {
                /* a stuck cache must not keep the screen spinning */
            });
        }
        return data;
    } finally {
        clearTimeout(timeoutId);
    }
}

function refreshGetInBackground(path, options, key) {
    if (refreshInflight.has(path)) {
        return;
    }
    const pending = (async () => {
        const previous = await readGetCache(key);
        const data = await doNetworkFetch(path, options);
        if (!samePayload(previous, data)) {
            emitCacheUpdated(path, data);
        }
        return data;
    })()
        .catch(() => {
            /* keep showing the cached payload */
        })
        .finally(() => {
            refreshInflight.delete(path);
        });
    refreshInflight.set(path, pending);
}

/**
 * Salesforce REST fetch.
 * GET is cache-first: paint from IndexedDB immediately, then refresh Salesforce
 * in the background (`options.fresh` waits on the network). POST still goes
 * out so the outbox can drain.
 */
export async function plannerApiFetch(path, options = {}) {
    const method = options.method || 'GET';
    const key = cacheKeyFor(path, method);
    const fresh = options.fresh === true;

    if (key && !fresh) {
        const cached = await readGetCache(key);
        if (cached != null) {
            if (!shouldSkipGetNetwork()) {
                refreshGetInBackground(path, options, key);
            }
            return cached;
        }
    }

    if (shouldSkipGetNetwork() && key && options.bypassOfflineGate !== true) {
        const cached = await readGetCache(key);
        if (cached != null) {
            return cached;
        }
        throw new Error('Offline — no cached response for this request.');
    }
    if (isNavigatorOffline() && String(method).toUpperCase() !== 'GET') {
        throw new Error('Offline');
    }

    try {
        return await doNetworkFetch(path, options);
    } catch (error) {
        if (key) {
            const cached = await readGetCache(key);
            if (cached != null) {
                return cached;
            }
        }
        throw error;
    }
}
