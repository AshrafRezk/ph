/**
 * Salesforce OAuth session for the offline shell.
 * Access tokens follow the org session timeout. The refresh token is kept and
 * exchanged silently so a person stays signed in without another login.
 * Refresh-token rotation is saved when Salesforce returns a new refresh token.
 */

const TOKEN_KEY = 'zeta.pwa.sfAccessToken';
const REFRESH_TOKEN_KEY = 'zeta.pwa.sfRefreshToken';
const INSTANCE_URL_KEY = 'zeta.pwa.sfInstanceUrl';
const LOGIN_URL_KEY = 'zeta.pwa.sfLoginUrl';
const ISSUED_AT_KEY = 'zeta.pwa.sfTokenIssuedAt';
const REFRESH_LOCK_KEY = 'zeta.pwa.sfRefreshLock';
const TOKEN_PROXY_PATH = '/.netlify/functions/sf-token';
const DEFAULT_PUBLIC_WEB_ORIGIN = 'https://www.salesforceoffline.com';
const PRODUCTION_LOGIN = 'https://login.salesforce.com';
/** Renew before a typical 2-hour Salesforce session ends. */
const REFRESH_AFTER_MS = 45 * 60 * 1000;
/** One refresh at a time. Rotation makes a second in-flight refresh revoke the new token. */
const REFRESH_LOCK_MS = 20000;
const TAB_ID = `${Date.now().toString(36)}-${Math.random().toString(36).slice(2, 8)}`;

let refreshInflight = null;
let keepAliveStarted = false;

function envValue(name) {
    try {
        const env = import.meta.env;
        return String((env && env[name]) || '').trim();
    } catch (_err) {
        return '';
    }
}

export function readAccessToken() {
    try {
        return (window.localStorage.getItem(TOKEN_KEY) || '').trim();
    } catch (_err) {
        return '';
    }
}

export function readRefreshToken() {
    try {
        return window.localStorage.getItem(REFRESH_TOKEN_KEY) || '';
    } catch (_err) {
        return '';
    }
}

export function readInstanceUrl() {
    try {
        return String(window.localStorage.getItem(INSTANCE_URL_KEY) || '').replace(/\/$/, '');
    } catch (_err) {
        return '';
    }
}

function readLoginUrl() {
    try {
        return (
            window.localStorage.getItem(LOGIN_URL_KEY) ||
            envValue('VITE_SF_LOGIN_URL') ||
            PRODUCTION_LOGIN
        ).replace(/\/$/, '');
    } catch (_err) {
        return PRODUCTION_LOGIN;
    }
}

function readIssuedAt() {
    try {
        const ms = Number(window.localStorage.getItem(ISSUED_AT_KEY));
        return Number.isFinite(ms) && ms > 0 ? ms : 0;
    } catch (_err) {
        return 0;
    }
}

/** Salesforce sends milliseconds. A seconds value would look ancient and refresh forever. */
function normalizeIssuedAt(value) {
    const issued = Number(value);
    if (!Number.isFinite(issued) || issued <= 0) return Date.now();
    return issued < 1e12 ? issued * 1000 : issued;
}

function sleep(ms) {
    return new Promise((resolve) => {
        setTimeout(resolve, ms);
    });
}

function readRefreshLock() {
    try {
        const raw = window.localStorage.getItem(REFRESH_LOCK_KEY);
        if (!raw) return null;
        const lock = JSON.parse(raw);
        if (!lock || typeof lock !== 'object') return null;
        return lock;
    } catch (_err) {
        return null;
    }
}

function lockHeldByOther(now = Date.now()) {
    const lock = readRefreshLock();
    if (!lock || lock.owner === TAB_ID) return false;
    return now - Number(lock.at || 0) < REFRESH_LOCK_MS;
}

function writeRefreshLock() {
    try {
        window.localStorage.setItem(
            REFRESH_LOCK_KEY,
            JSON.stringify({ owner: TAB_ID, at: Date.now() })
        );
    } catch (_err) {
        /* private mode */
    }
}

function releaseRefreshLock() {
    try {
        const lock = readRefreshLock();
        if (!lock || lock.owner === TAB_ID) {
            window.localStorage.removeItem(REFRESH_LOCK_KEY);
        }
    } catch (_err) {
        /* ignore */
    }
}

function currentTokenPayload() {
    const accessToken = readAccessToken();
    if (!accessToken) return null;
    return {
        access_token: accessToken,
        refresh_token: readRefreshToken(),
        instance_url: readInstanceUrl()
    };
}

/**
 * Another tab may have rotated the refresh token while this one was waiting.
 * Reuse that result instead of sending the old token and getting signed out.
 */
function adoptNewerToken(startedRefresh, startedIssued) {
    const refreshToken = readRefreshToken();
    const issued = readIssuedAt();
    const rotated = refreshToken && refreshToken !== startedRefresh;
    const renewed = issued > startedIssued && !accessTokenIsStale();
    if (!rotated && !renewed) return null;
    const payload = currentTokenPayload();
    if (payload) applyRuntime(payload.access_token, payload.instance_url);
    return payload;
}

export function accessTokenIsStale(now = Date.now()) {
    if (!readRefreshToken()) return false;
    const issued = readIssuedAt();
    if (!issued) return true;
    return now - issued >= REFRESH_AFTER_MS;
}

function errorText(error) {
    return String(error && (error.message || error) ? error.message || error : '').toLowerCase();
}

/** Salesforce is still finishing a rotated refresh. Wait and reuse the saved token. */
function isRotationInProgress(error) {
    return /already being processed/.test(errorText(error));
}

export function isRefreshRejected(error) {
    if (isRotationInProgress(error)) return false;
    return /invalid_grant|expired access\/refresh token|inactive user|inactive organization|authentication failure|invalid refresh token/.test(
        errorText(error)
    );
}

function applyRuntime(accessToken, instanceUrl) {
    if (typeof globalThis === 'undefined') return;
    if (accessToken) globalThis.PLANNER_ACCESS_TOKEN = accessToken;
    if (instanceUrl) {
        globalThis.PLANNER_REST_BASE = instanceUrl;
        globalThis.PLANNER_SF_INSTANCE = instanceUrl;
    }
}

/** Persist a token response, including a rotated refresh token. */
export function applyTokenResponse(tokenData) {
    if (!tokenData || typeof tokenData !== 'object') return;
    const accessToken = String(tokenData.access_token || '').trim();
    const refreshToken = String(tokenData.refresh_token || '').trim();
    const instanceUrl = String(tokenData.instance_url || '').replace(/\/$/, '');
    try {
        if (accessToken) window.localStorage.setItem(TOKEN_KEY, accessToken);
        if (refreshToken) window.localStorage.setItem(REFRESH_TOKEN_KEY, refreshToken);
        if (instanceUrl) window.localStorage.setItem(INSTANCE_URL_KEY, instanceUrl);
        if (accessToken) {
            window.localStorage.setItem(ISSUED_AT_KEY, String(normalizeIssuedAt(tokenData.issued_at)));
        }
    } catch (_err) {
        /* private mode */
    }
    applyRuntime(accessToken, instanceUrl);
}

export function clearStoredTokens() {
    try {
        window.localStorage.removeItem(TOKEN_KEY);
        window.localStorage.removeItem(REFRESH_TOKEN_KEY);
        window.localStorage.removeItem(ISSUED_AT_KEY);
    } catch (_err) {
        /* ignore */
    }
    if (typeof globalThis !== 'undefined') {
        globalThis.PLANNER_ACCESS_TOKEN = '';
    }
}

function isNativeShell() {
    try {
        const cap = window.Capacitor;
        if (cap && typeof cap.isNativePlatform === 'function' && cap.isNativePlatform()) return true;
    } catch (_err) {
        /* ignore */
    }
    const host = window.location?.hostname || '';
    const port = window.location?.port || '';
    return (host === 'localhost' || host === '127.0.0.1') && !port;
}

function publicWebOrigin() {
    const explicit = envValue('VITE_PUBLIC_WEB_ORIGIN').replace(/\/$/, '');
    if (explicit) return explicit;
    const webRedirect = envValue('VITE_SF_WEB_REDIRECT_URI');
    if (webRedirect) {
        try {
            return new URL(webRedirect).origin;
        } catch (_err) {
            /* ignore */
        }
    }
    return DEFAULT_PUBLIC_WEB_ORIGIN;
}

function tokenProxyUrl() {
    const explicit = envValue('VITE_TOKEN_PROXY_URL');
    if (explicit) return explicit;
    if (isNativeShell()) return `${publicWebOrigin()}${TOKEN_PROXY_PATH}`;
    return TOKEN_PROXY_PATH;
}

function looksLikeHtml(text) {
    const trimmed = String(text || '')
        .trim()
        .slice(0, 32)
        .toLowerCase();
    return trimmed.startsWith('<!doctype') || trimmed.startsWith('<html') || trimmed.startsWith('<head');
}

function parseTokenProxyBody(raw, status) {
    let json = raw;
    if (typeof raw === 'string' || raw == null) {
        const text = String(raw || '');
        if (looksLikeHtml(text)) {
            throw new Error('Invalid response from token proxy');
        }
        try {
            json = JSON.parse(text);
        } catch (_err) {
            throw new Error('Invalid response from token proxy');
        }
    }
    if (!json || typeof json !== 'object') {
        throw new Error('Invalid response from token proxy');
    }
    if (status < 200 || status >= 300) {
        const detail = json.error_description || json.errorMessage || json.error || JSON.stringify(json);
        throw new Error(`Failed to refresh token (${status}): ${detail}`);
    }
    return json;
}

async function postRefresh(refreshToken) {
    const clientId = envValue('VITE_SF_CLIENT_ID');
    if (!clientId) {
        throw new Error('Connected App client id is not configured (VITE_SF_CLIENT_ID).');
    }
    const payload = {
        tokenUrl: `${readLoginUrl()}/services/oauth2/token`,
        grant_type: 'refresh_token',
        client_id: clientId,
        refresh_token: refreshToken
    };
    const url = tokenProxyUrl();

    if (isNativeShell()) {
        try {
            const { CapacitorHttp } = await import('@capacitor/core');
            const result = await CapacitorHttp.post({
                url,
                headers: { 'Content-Type': 'application/json', Accept: 'application/json' },
                data: payload,
                connectTimeout: 30000,
                readTimeout: 30000
            });
            return parseTokenProxyBody(result.data, result.status);
        } catch (error) {
            const message = error instanceof Error ? error.message : String(error);
            if (message === 'Invalid response from token proxy' || message.startsWith('Failed to refresh token (')) {
                throw error;
            }
        }
    }

    const response = await fetch(url, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json', Accept: 'application/json' },
        body: JSON.stringify(payload)
    });
    const text = await response.text();
    return parseTokenProxyBody(text, response.status);
}

async function refreshCoordinated(refreshToken) {
    const startedIssued = readIssuedAt();
    let ownsLock = false;
    try {
        for (let attempt = 0; attempt < 40; attempt += 1) {
            const adopted = adoptNewerToken(refreshToken, startedIssued);
            if (adopted) return adopted;
            if (!lockHeldByOther()) {
                writeRefreshLock();
                await sleep(50);
                if (!lockHeldByOther()) {
                    ownsLock = true;
                    break;
                }
            }
            await sleep(400);
        }

        if (!ownsLock) {
            const adopted = adoptNewerToken(refreshToken, startedIssued);
            if (adopted) return adopted;
            throw new Error('Could not refresh your Salesforce session. Check your connection and try again.');
        }

        const tokenInUse = readRefreshToken() || refreshToken;
        const tokenData = await postRefresh(tokenInUse);
        if (!tokenData?.access_token) {
            throw new Error('Token refresh returned no access_token');
        }
        applyTokenResponse(tokenData);
        return tokenData;
    } catch (error) {
        const adopted = adoptNewerToken(refreshToken, startedIssued);
        if (adopted) return adopted;
        if (isRotationInProgress(error)) {
            await sleep(800);
            const afterWait = adoptNewerToken(refreshToken, startedIssued);
            if (afterWait) return afterWait;
        }
        throw error;
    } finally {
        if (ownsLock) releaseRefreshLock();
    }
}

/** Single-flight refresh so rotation cannot invalidate a token still in use. */
export function refreshAccessToken() {
    const refreshToken = readRefreshToken();
    if (!refreshToken) {
        return Promise.reject(new Error('No refresh token available'));
    }
    if (!refreshInflight) {
        refreshInflight = refreshCoordinated(refreshToken).finally(() => {
            refreshInflight = null;
        });
    }
    return refreshInflight;
}

export function notifySessionInvalid() {
    try {
        window.dispatchEvent(new CustomEvent('zeta-session-invalid'));
    } catch (_err) {
        /* ignore */
    }
}

/** Renew when the access token is old. A dead refresh token is the only sign-out. */
export function touchSession() {
    if (typeof navigator !== 'undefined' && navigator.onLine === false) return;
    if (!accessTokenIsStale()) return;
    refreshAccessToken().catch((error) => {
        if (isRefreshRejected(error)) notifySessionInvalid();
    });
}

/** Refresh on a timer and whenever the app returns to the foreground. */
export function startSessionKeepAlive() {
    if (keepAliveStarted || typeof window === 'undefined') return;
    keepAliveStarted = true;
    const tick = () => {
        touchSession();
    };
    document.addEventListener('visibilitychange', () => {
        if (document.visibilityState === 'visible') tick();
    });
    window.addEventListener('online', tick);
    window.addEventListener('storage', (event) => {
        if (
            event.key === TOKEN_KEY ||
            event.key === REFRESH_TOKEN_KEY ||
            event.key === INSTANCE_URL_KEY
        ) {
            applyRuntime(readAccessToken(), readInstanceUrl());
        }
    });
    window.setInterval(tick, 5 * 60 * 1000);
}

if (typeof window !== 'undefined') {
    window.refreshPlannerAccessToken = refreshAccessToken;
}
