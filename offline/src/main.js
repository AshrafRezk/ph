import '@lwc/synthetic-shadow';
import { createElement } from 'lwc';
import FieldRepHomeMetrics from 'c/fieldRepHomeMetrics';
import FieldRepHomeMonthlyTimecard from 'c/fieldRepHomeMonthlyTimecard';
import FieldRepHomeTodayPlan from 'c/fieldRepHomeTodayPlan';
import FieldRepHomeNextBestCustomer from 'c/fieldRepHomeNextBestCustomer';
import HomeOfficeMessages from 'c/homeOfficeMessages';
import FieldRepHomeClmPrefetch from 'c/fieldRepHomeClmPrefetch';
import ReportsHub from 'c/reportsHub';
import FieldRepPlanner from 'c/fieldRepPlanner';
import AccountsTab from 'c/accountsTab';
import TimeOffSubmission from 'c/timeOffSubmission';
import ClmPresentationsHub from 'c/clmPresentationsHub';
import VisitCallShell from 'c/visitCallShell';
import MyLearning from 'c/myLearning';
import CoachingEventEvaluation from 'c/coachingEventEvaluation';
import AccountAffiliationNetwork from 'c/accountAffiliationNetwork';
import AccountStageAssistant from 'c/accountStageAssistant';
import AccountHcpProductRoi from 'c/accountHcpProductRoi';
import AccountRatingsPanel from 'c/accountRatingsPanel';
import AccountVisitInsightsPanel from 'c/accountVisitInsightsPanel';
import PendingPaymentAlert from 'c/pendingPaymentAlert';
import OfflineAppBanner from 'c/offlineAppBanner';
import { startSyncService, registerOfflineListener } from 'c/clmOfflineSync';
import { fetchApps, fetchTabs, PHARMA_APP, overlayTabIcons, ensureAppTabs, readCachedApps } from './apex/fetchAppTabs';
import { plannerApiFetch } from './apex/restHelper';
import { setupToastListener } from './toastManager';
import { mountChatterView as renderChatterView } from './views/chatterView';
import { mountReportsView as renderReportsView } from './views/reportsView';
import { mountDashboardsView as renderDashboardsView } from './views/dashboardsView';
import './slds-shim.css';
import './shell.css';

const TOKEN_KEY = 'zeta.pwa.sfAccessToken';
const REFRESH_TOKEN_KEY = 'zeta.pwa.sfRefreshToken';
const INSTANCE_URL_KEY = 'zeta.pwa.sfInstanceUrl';
const USER_NAME_KEY = 'zeta.pwa.sfUserName';
const USER_USERNAME_KEY = 'zeta.pwa.sfUserUsername';
const USER_ID_KEY = 'zeta.pwa.sfUserId';
const SESSION_CONFIRMED_KEY = 'zeta.pwa.sessionConfirmed';
const LAST_WORKSPACE_KEY = 'zeta.pwa.lastWorkspace';
const APP_VERSION_KEY = 'zeta.pwa.appVersion';
const HOME_TAB_KEY = 'Field_Rep_Home_App';
const VISIT_CALL_TAB_KEY = 'Visit_Call';
const ACTIVE_VISIT_KEY = 'zeta.pwa.activeVisitId';
let currentTab = HOME_TAB_KEY;
let appTabs = [];
let currentOpenApp = null;
/** Last Lightning app to reopen after a refresh while org apps are still loading. */
let pendingRestore = null;

// Capacitor plugin references (lazy loaded)
let capacitorApp = null;
let capacitorBrowser = null;

// Detect if running in Capacitor native app
function isCapacitor() {
    if (typeof window === 'undefined') return false;

    // Manual override via URL parameter or localStorage (for testing)
    const urlParams = new URLSearchParams(window.location.search);
    if (urlParams.get('capacitor') === 'true' || localStorage.getItem('forceCapacitor') === 'true') {
        console.log('[Capacitor] Forced via URL parameter or localStorage');
        return true;
    }

    // Check for Capacitor object
    if (window.Capacitor && window.Capacitor.isNativePlatform) {
        return window.Capacitor.isNativePlatform();
    }

    // Fallback: Check if running in Android WebView with Capacitor
    const ua = navigator.userAgent;
    console.log('[Capacitor] User Agent:', ua);
    if (/android/i.test(ua) && /Capacitor/i.test(ua)) {
        console.log('[Capacitor] Detected via User Agent');
        return true;
    }

    // Fallback: Check for Capacitor-specific flags
    if (window.CapacitorCookies || window.CapacitorHttp || window.CapacitorWebView) {
        console.log('[Capacitor] Detected via global flags');
        return true;
    }

    return false;
}

function looksLikeCapacitorHost() {
    if (typeof window === 'undefined') return false;
    if (window.Capacitor) return true;
    const ua = navigator.userAgent || '';
    return /Capacitor/i.test(ua);
}

// Wait for Capacitor to be ready (for remote URL loading in a native WebView).
// Regular browsers never become Capacitor — don't stall boot for seconds.
function waitForCapacitor(timeout = 5000) {
    return new Promise((resolve) => {
        if (isCapacitor()) {
            resolve(true);
            return;
        }
        if (!looksLikeCapacitorHost()) {
            resolve(false);
            return;
        }

        const startTime = Date.now();
        const checkInterval = setInterval(() => {
            if (isCapacitor()) {
                clearInterval(checkInterval);
                resolve(true);
                return;
            }

            if (Date.now() - startTime > timeout) {
                clearInterval(checkInterval);
                resolve(false);
            }
        }, 100);
    });
}

// Detect if Capacitor plugins are available
async function initCapacitorPlugins() {
    if (!isCapacitor()) return false;

    try {
        const { App } = await import('@capacitor/app');
        const { Browser } = await import('@capacitor/browser');
        capacitorApp = App;
        capacitorBrowser = Browser;
        console.log('[Capacitor] Plugins initialized');
        return true;
    } catch (error) {
        console.warn('[Capacitor] Failed to load plugins:', error);
        return false;
    }
}

// OAuth Configuration (env-based PKCE — never put client secrets in the bundle)
const PRODUCTION_LOGIN = 'https://login.salesforce.com';
const SANDBOX_LOGIN = 'https://test.salesforce.com';
const MY_DOMAIN_SUFFIX = '.my.salesforce.com';
const APP_SCHEME = 'com.zetapharma.fieldpwa';
const LOGIN_URL_KEY = 'zeta.pwa.sfLoginUrl';
const REDIRECT_URI_KEY = 'zeta.pwa.sfRedirectUri';
const PKCE_VERIFIER_KEY = 'zeta.pwa.oauthPkceVerifier';
const OAUTH_STATE_KEY = 'zeta.pwa.oauthState';
const TOKEN_PROXY_URL = '/.netlify/functions/sf-token';
/** @type {'login' | 'chooser' | 'app' | null} */
let currentScreen = null;

function defaultInstanceUrl() {
    const fromEnv = (import.meta.env.VITE_SF_INSTANCE_URL || '').trim();
    return fromEnv.replace(/\/$/, '');
}

function extractMyDomainLabel(raw) {
    if (!raw) return '';
    let s = String(raw).trim().replace(/^['"]|['"]$/g, '');
    if (!s) return '';
    s = s.replace(/^https?:\/\//i, '').replace(/\/.*$/, '');
    s = (s.split(':')[0] ?? s).trim();
    const lower = s.toLowerCase();
    if (lower.endsWith(MY_DOMAIN_SUFFIX)) {
        return s.slice(0, -MY_DOMAIN_SUFFIX.length).toLowerCase();
    }
    if (lower.endsWith('.sandbox.my.salesforce.com')) {
        return lower.replace(/\.my\.salesforce\.com$/, '');
    }
    if (s.includes('.')) {
        return (s.split('.')[0] ?? s).toLowerCase();
    }
    return lower;
}

function myDomainLoginUrlFromLabel(label) {
    const cleaned = extractMyDomainLabel(label);
    if (!cleaned) return null;
    if (!/^[a-z0-9]([a-z0-9-]*[a-z0-9])?(\.sandbox)?$/i.test(cleaned)) return null;
    if (cleaned.endsWith('.sandbox')) {
        return `https://${cleaned}.my.salesforce.com`;
    }
    return `https://${cleaned}${MY_DOMAIN_SUFFIX}`;
}

function getOAuthCallbackUrl() {
    if (isCapacitor()) {
        return import.meta.env.VITE_SF_REDIRECT_URI || `${APP_SCHEME}://oauth/callback`;
    }
    if (
        typeof window !== 'undefined' &&
        (window.location.hostname === 'localhost' || window.location.hostname === '127.0.0.1')
    ) {
        return `${window.location.origin}/oauth/callback`;
    }
    return (
        import.meta.env.VITE_SF_WEB_REDIRECT_URI ||
        `${window.location.origin}/oauth/callback`
    );
}

function getOAuthClientId() {
    return (import.meta.env.VITE_SF_CLIENT_ID || '').trim();
}

const OAUTH_CONFIG = {
    // Full API context for Allow Access + refresh for offline session restore.
    scopes: 'id api web full refresh_token',
    get clientId() {
        return getOAuthClientId();
    },
    get loginUrl() {
        return (
            window.localStorage.getItem(LOGIN_URL_KEY) ||
            import.meta.env.VITE_SF_LOGIN_URL ||
            PRODUCTION_LOGIN
        ).replace(/\/$/, '');
    },
    set loginUrl(url) {
        window.localStorage.setItem(LOGIN_URL_KEY, String(url || '').replace(/\/$/, ''));
    },
    get redirectUri() {
        return window.localStorage.getItem(REDIRECT_URI_KEY) || getOAuthCallbackUrl();
    },
    set redirectUri(uri) {
        window.localStorage.setItem(REDIRECT_URI_KEY, String(uri || ''));
    },
    get callbackUrl() {
        return getOAuthCallbackUrl();
    }
};

function readToken() {
    return (window.localStorage.getItem(TOKEN_KEY) || '').trim();
}

function readRefreshToken() {
    return window.localStorage.getItem(REFRESH_TOKEN_KEY) || '';
}

function readInstanceUrl() {
    return window.localStorage.getItem(INSTANCE_URL_KEY) || defaultInstanceUrl();
}

function hasStoredSession() {
    return !!(readToken() || readRefreshToken());
}

function readStoredIdentity() {
    return {
        name: (window.localStorage.getItem(USER_NAME_KEY) || '').trim(),
        username: (window.localStorage.getItem(USER_USERNAME_KEY) || '').trim(),
        userId: (window.localStorage.getItem(USER_ID_KEY) || '').trim()
    };
}

function saveIdentity({ name, username, userId }) {
    if (name) window.localStorage.setItem(USER_NAME_KEY, name);
    if (username) window.localStorage.setItem(USER_USERNAME_KEY, username);
    if (userId) window.localStorage.setItem(USER_ID_KEY, userId);
}

function clearIdentity() {
    window.localStorage.removeItem(USER_NAME_KEY);
    window.localStorage.removeItem(USER_USERNAME_KEY);
    window.localStorage.removeItem(USER_ID_KEY);
}

function isSessionConfirmed() {
    try {
        return sessionStorage.getItem(SESSION_CONFIRMED_KEY) === '1';
    } catch {
        return false;
    }
}

function confirmSession() {
    try {
        sessionStorage.setItem(SESSION_CONFIRMED_KEY, '1');
    } catch {
        /* ignore */
    }
}

function clearSessionConfirmed() {
    try {
        sessionStorage.removeItem(SESSION_CONFIRMED_KEY);
    } catch {
        /* ignore */
    }
}

function readLastWorkspace() {
    try {
        const raw = window.localStorage.getItem(LAST_WORKSPACE_KEY);
        if (!raw) return null;
        const parsed = JSON.parse(raw);
        return parsed && typeof parsed === 'object' ? parsed : null;
    } catch {
        return null;
    }
}

function writeLastWorkspace(patch) {
    try {
        const prev = readLastWorkspace() || {};
        window.localStorage.setItem(LAST_WORKSPACE_KEY, JSON.stringify({ ...prev, ...patch }));
    } catch {
        /* ignore */
    }
}

function clearLastWorkspace() {
    pendingRestore = null;
    try {
        window.localStorage.removeItem(LAST_WORKSPACE_KEY);
    } catch {
        /* ignore */
    }
}

function persistOpenWorkspace() {
    if (!currentOpenApp) return;
    writeLastWorkspace({
        screen: 'app',
        developerName: currentOpenApp.developerName || null,
        id: currentOpenApp.id || null,
        tabKey: currentTab || null
    });
}

function appIdentityKey(value) {
    return String(value || '')
        .replace(/^standard__/i, '')
        .toLowerCase();
}

function findAppBySaved(apps, saved) {
    if (!saved || !Array.isArray(apps) || !apps.length) return null;
    const name = appIdentityKey(saved.developerName);
    const id = saved.id || '';
    return (
        (name && apps.find((a) => appIdentityKey(a.developerName) === name)) ||
        (id && apps.find((a) => a.id === id)) ||
        null
    );
}

function isPharmaWorkspace(saved) {
    const name = appIdentityKey(saved && saved.developerName);
    return name === 'lightningsales' || name === 'pharmafield';
}

function applyResumeUserLabels() {
    const { name, username } = readStoredIdentity();
    const display = name || username || 'Someone';
    const nameEl = document.getElementById('resume-user-name');
    if (nameEl) nameEl.textContent = display;
    const unameEl = document.getElementById('resume-user-username');
    const wrap = document.getElementById('resume-user-username-wrap');
    if (unameEl) unameEl.textContent = username;
    if (wrap) wrap.hidden = !username || username === display;
}

function showResumeSession() {
    document.documentElement.classList.add('osr-has-session');
    document.documentElement.classList.remove('osr-session-confirmed');
    const resume = document.getElementById('login-resume');
    const fresh = document.getElementById('login-fresh');
    const downloads = document.getElementById('login-downloads');
    if (resume) {
        resume.hidden = false;
        resume.removeAttribute('hidden');
    }
    if (fresh) fresh.hidden = true;
    if (downloads) downloads.hidden = true;
    applyResumeUserLabels();
}

function showFreshLogin() {
    document.documentElement.classList.remove('osr-has-session');
    document.documentElement.classList.remove('osr-session-confirmed');
    const resume = document.getElementById('login-resume');
    const fresh = document.getElementById('login-fresh');
    const downloads = document.getElementById('login-downloads');
    if (resume) resume.hidden = true;
    if (fresh) {
        fresh.hidden = false;
        fresh.removeAttribute('hidden');
    }
    if (downloads) {
        downloads.hidden = false;
        downloads.removeAttribute('hidden');
    }
    syncLoginFormUi();
}

async function fetchAndStoreUserIdentity() {
    if (!readToken()) return readStoredIdentity();
    try {
        const info = await plannerApiFetch('/services/oauth2/userinfo');
        const name = String(info?.name || info?.display_name || '').trim();
        const username = String(
            info?.preferred_username || info?.username || info?.email || ''
        ).trim();
        const userId = String(info?.user_id || '').trim();
        saveIdentity({ name, username, userId });
        applyResumeUserLabels();
    } catch (error) {
        console.warn('[Auth] Could not load user identity:', error);
    }
    return readStoredIdentity();
}

function enterAuthenticatedApp() {
    const token = readToken();
    if (!token) {
        showFreshLogin();
        showScreen('login');
        setLoginStatus('Session expired. Please sign in again.', true);
        return;
    }
    confirmSession();
    document.documentElement.classList.add('osr-session-confirmed');
    configureRuntime(token);
    if (!restoreLastLightningApp()) {
        buildAppChooser();
    } else {
        seedChooserFromCache();
        loadOrgAppsIntoChooser();
    }
    registerOfflineListener((status) => {
        console.log('[OfflineSyncListener] Sync phase changed:', status);
    });
    startSyncService();
}

function configureRuntime(token, refreshToken = null, instanceUrl = null) {
    const sfInstance = (instanceUrl || readInstanceUrl()).replace(/\/$/, '');
    // Always point at the Salesforce instance; browser CORS is handled by sf-api proxy.
    globalThis.PLANNER_REST_BASE = sfInstance;
    globalThis.PLANNER_ACCESS_TOKEN = token;
    globalThis.PLANNER_SF_INSTANCE = sfInstance;

    console.log('[configureRuntime] isCapacitor:', isCapacitor());
    console.log('[configureRuntime] sfInstance:', sfInstance);
    console.log('[configureRuntime] PLANNER_REST_BASE:', globalThis.PLANNER_REST_BASE);

    if (refreshToken) {
        window.localStorage.setItem(REFRESH_TOKEN_KEY, refreshToken);
    }
    if (instanceUrl) {
        window.localStorage.setItem(INSTANCE_URL_KEY, instanceUrl.replace(/\/$/, ''));
    }
}

// OAuth Functions with PKCE
function generateCodeVerifier() {
    const array = new Uint8Array(32);
    crypto.getRandomValues(array);
    return base64UrlEncode(array);
}

function base64UrlEncode(buffer) {
    const bytes = new Uint8Array(buffer);
    let binary = '';
    for (let i = 0; i < bytes.length; i++) {
        binary += String.fromCharCode(bytes[i]);
    }
    return btoa(binary).replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, '');
}

async function generateCodeChallenge(verifier) {
    const encoder = new TextEncoder();
    const data = encoder.encode(verifier);
    const digest = await crypto.subtle.digest('SHA-256', data);
    return base64UrlEncode(digest);
}

async function generateAuthUrl(loginUrl) {
    const clientId = OAUTH_CONFIG.clientId;
    if (!clientId || clientId.includes('YOUR_')) {
        throw new Error('Connected App client id is not configured (VITE_SF_CLIENT_ID).');
    }
    const resolvedLogin = (loginUrl || OAUTH_CONFIG.loginUrl).replace(/\/$/, '');
    const redirectUri = getOAuthCallbackUrl();
    OAUTH_CONFIG.loginUrl = resolvedLogin;
    OAUTH_CONFIG.redirectUri = redirectUri;

    const codeVerifier = generateCodeVerifier();
    const codeChallenge = await generateCodeChallenge(codeVerifier);
    const state = generateState();
    // Persist outside navigation so PKCE/state survive the Salesforce round-trip (OSR pattern).
    window.localStorage.setItem(PKCE_VERIFIER_KEY, codeVerifier);
    window.localStorage.setItem(OAUTH_STATE_KEY, state);
    // Legacy keys — kept for in-flight logins started before this rename.
    window.localStorage.setItem('oauth_code_verifier', codeVerifier);
    window.localStorage.setItem('oauth_state', state);

    const params = new URLSearchParams({
        response_type: 'code',
        client_id: clientId,
        redirect_uri: redirectUri,
        scope: OAUTH_CONFIG.scopes,
        state,
        code_challenge: codeChallenge,
        code_challenge_method: 'S256',
        prompt: 'login'
    });
    return `${resolvedLogin}/services/oauth2/authorize?${params.toString()}`;
}

function generateState() {
    if (typeof crypto !== 'undefined' && crypto.randomUUID) {
        return crypto.randomUUID();
    }
    return Math.random().toString(36).substring(2, 15) + Math.random().toString(36).substring(2, 15);
}

function readPkceVerifier() {
    return (
        window.localStorage.getItem(PKCE_VERIFIER_KEY) ||
        window.localStorage.getItem('oauth_code_verifier') ||
        ''
    );
}

function readOAuthState() {
    return (
        window.localStorage.getItem(OAUTH_STATE_KEY) ||
        window.localStorage.getItem('oauth_state') ||
        ''
    );
}

function clearOAuthTransientState() {
    window.localStorage.removeItem(PKCE_VERIFIER_KEY);
    window.localStorage.removeItem(OAUTH_STATE_KEY);
    window.localStorage.removeItem('oauth_code_verifier');
    window.localStorage.removeItem('oauth_state');
}

async function exchangeCodeForToken(code) {
    const codeVerifier = readPkceVerifier();
    if (!codeVerifier) {
        throw new Error('Missing PKCE verifier — restart login');
    }

    const redirectUri = OAUTH_CONFIG.redirectUri || getOAuthCallbackUrl();
    const loginUrl = OAUTH_CONFIG.loginUrl;
    const tokenUrl = `${loginUrl}/services/oauth2/token`;
    const clientId = OAUTH_CONFIG.clientId;
    if (!clientId) {
        throw new Error('Connected App client id is not configured (VITE_SF_CLIENT_ID).');
    }

    const response = await fetch(TOKEN_PROXY_URL, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({
            tokenUrl,
            grant_type: 'authorization_code',
            client_id: clientId,
            redirect_uri: redirectUri,
            code,
            code_verifier: codeVerifier
        })
    });

    const text = await response.text();
    if (!response.ok) {
        console.error('Token exchange failed:', response.status, text);
        let detail = text;
        try {
            const parsed = JSON.parse(text);
            detail =
                parsed.error_description ||
                parsed.errorMessage ||
                parsed.error ||
                text;
        } catch {
            /* keep raw text */
        }
        throw new Error(`Token exchange failed (${response.status}): ${detail}`);
    }

    let json;
    try {
        json = JSON.parse(text);
    } catch {
        console.error('Non-JSON token response:', text.substring(0, 500));
        throw new Error('Invalid response from token proxy');
    }
    if (!json?.access_token) {
        throw new Error('Token exchange returned no access_token');
    }
    // Only clear PKCE after a successful exchange (OSR keeps prefs until clearSession).
    clearOAuthTransientState();
    return json;
}

async function refreshAccessToken() {
    const refreshToken = readRefreshToken();
    if (!refreshToken) {
        throw new Error('No refresh token available');
    }

    const loginUrl = OAUTH_CONFIG.loginUrl;
    const tokenUrl = `${loginUrl}/services/oauth2/token`;

    const response = await fetch(TOKEN_PROXY_URL, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({
            tokenUrl,
            grant_type: 'refresh_token',
            client_id: OAUTH_CONFIG.clientId,
            refresh_token: refreshToken
        })
    });

    if (!response.ok) {
        const text = await response.text();
        console.error('Token refresh failed:', response.status, text);
        throw new Error('Failed to refresh token: ' + response.status);
    }

    const contentType = response.headers.get('content-type');
    if (!contentType || !contentType.includes('application/json')) {
        const text = await response.text();
        console.error('Non-JSON response:', text.substring(0, 500));
        throw new Error('Invalid response from token proxy');
    }

    return response.json();
}

/** True when this navigation is an OAuth redirect (path and/or ?code=). */
function isOAuthCallbackLocation(href = window.location.href) {
    try {
        const u = new URL(href);
        // Only treat as callback when Salesforce actually sent code/error.
        return u.searchParams.has('code') || u.searchParams.has('error');
    } catch {
        return false;
    }
}

/**
 * Parse OAuth callback params (OSR-style). Throws on Salesforce error or state mismatch.
 * Returns null when this page load is not an OAuth callback.
 */
function parseOAuthCallback(href = window.location.href) {
    let u;
    try {
        u = new URL(href);
    } catch {
        return null;
    }
    if (!isOAuthCallbackLocation(href)) return null;

    const code = u.searchParams.get('code');
    const state = u.searchParams.get('state');
    const err = u.searchParams.get('error');
    if (err) {
        throw new Error(u.searchParams.get('error_description') || err);
    }
    if (!code) {
        throw new Error('OAuth callback missing authorization code');
    }

    const expectedState = readOAuthState();
    // OSR: only fail when both sides are present and disagree (survives missing storage edge cases).
    if (expectedState && state && expectedState !== state) {
        throw new Error('OAuth state mismatch — try signing in again');
    }
    return code;
}

/** Exchange code, persist tokens, clean URL. Mirrors OSR completeSalesforceLogin. */
async function completeWebOAuthLogin(href = window.location.href) {
    const code = parseOAuthCallback(href);
    if (!code) return null;

    setLoginStatus('Completing sign-in…');
    showScreen('login');

    const tokenData = await exchangeCodeForToken(code);
    const { access_token, refresh_token, instance_url } = tokenData;
    window.localStorage.setItem(TOKEN_KEY, access_token);
    configureRuntime(access_token, refresh_token, instance_url);
    // Always land on app root after success (not /oauth/callback).
    window.history.replaceState({}, document.title, '/');
    console.log('[OAuth] Token exchange successful');
    console.log('[OAuth] Instance URL:', instance_url);
    return tokenData;
}

function setLoginStatus(message, isError = false) {
    const el = document.getElementById('login-status');
    if (!el) return;
    if (!message) {
        el.hidden = true;
        el.textContent = '';
        return;
    }
    el.hidden = false;
    el.textContent = message;
    el.classList.toggle('login-status', true);
    el.style.color = isError ? '#ba0517' : '#706e6b';
}

function resolveLoginUrlFromForm() {
    const envSelect = document.getElementById('login-env');
    const env = envSelect?.value || 'custom';
    if (env === 'production') return PRODUCTION_LOGIN;
    if (env === 'sandbox') return SANDBOX_LOGIN;
    const input = document.getElementById('custom-domain-input');
    return myDomainLoginUrlFromLabel(input?.value || '') || null;
}

function syncLoginFormUi() {
    const envSelect = document.getElementById('login-env');
    const customField = document.getElementById('custom-domain-field');
    const ready = document.getElementById('login-ready');
    const loginBtn = document.getElementById('login-btn');
    const env = envSelect?.value || 'production';
    // Live + Sandbox must never show the company My Domain field.
    const showCustom = env === 'custom';
    if (customField) {
        customField.hidden = !showCustom;
        customField.style.display = showCustom ? '' : 'none';
        if (!showCustom) {
            customField.setAttribute('hidden', '');
        } else {
            customField.removeAttribute('hidden');
        }
    }
    const customReady =
        !showCustom ||
        !!myDomainLoginUrlFromLabel(document.getElementById('custom-domain-input')?.value);
    if (ready) {
        ready.hidden = !(showCustom && customReady);
    }
    if (loginBtn) loginBtn.disabled = showCustom && !customReady;
}

function prefillsCustomDomainFromEnv() {
    const input = document.getElementById('custom-domain-input');
    if (!input || input.value) return;
    const label = extractMyDomainLabel(defaultInstanceUrl());
    if (label) input.value = label;
}

async function login() {
    setLoginStatus('Opening sign-in…');
    const resolved = resolveLoginUrlFromForm();
    if (!resolved) {
        setLoginStatus('Enter your company login name.', true);
        return;
    }

    let authUrl;
    try {
        authUrl = await generateAuthUrl(resolved);
    } catch (error) {
        const msg = error instanceof Error ? error.message : String(error);
        setLoginStatus(
            msg.includes('client id')
                ? 'Sign-in isn’t set up yet. Please contact your admin.'
                : 'Couldn’t start sign-in. Check your connection and try again.',
            true
        );
        return;
    }

    // Initialize Capacitor plugins if needed
    if (isCapacitor() && !capacitorBrowser) {
        await initCapacitorPlugins();
    }

    if (isCapacitor() && capacitorBrowser) {
        try {
            console.log('[OAuth] Opening native browser for Capacitor');
            await capacitorBrowser.open({
                url: authUrl,
                presentationStyle: 'fullscreen',
                toolbarColor: '#0176d3'
            });
        } catch (error) {
            console.error('[OAuth] Failed to open browser:', error);
            window.location.href = authUrl;
        }
    } else {
        console.log('[OAuth] Using web flow');
        window.location.href = authUrl;
    }
}

// Handle OAuth callback from native browser
async function handleCapacitorCallback(url) {
    if (!url) return;

    let normalized = url;
    try {
        // eslint-disable-next-line no-new
        new URL(url);
    } catch {
        normalized = url
            .replace(`${APP_SCHEME}://`, 'https://oauth.local/')
            .replace(`${APP_SCHEME}:/`, 'https://oauth.local/');
    }

    try {
        await completeWebOAuthLogin(normalized);
        if (capacitorBrowser) {
            try {
                await capacitorBrowser.close();
            } catch {
                /* ignore */
            }
        }
        initializeApp({ enterImmediately: true });
    } catch (error) {
        console.error('[OAuth] Callback error:', error);
        showScreen('login');
        setLoginStatus(
            error instanceof Error ? error.message : 'Login failed. Please try again.',
            true
        );
    }
}

// Initialize Capacitor App listener for deep links
let deepLinkListenerAdded = false;
async function initCapacitorListener() {
    if (!isCapacitor()) return;

    // Initialize plugins if not already done
    if (!capacitorApp) {
        await initCapacitorPlugins();
    }

    if (capacitorApp && !deepLinkListenerAdded) {
        deepLinkListenerAdded = true;
        capacitorApp.addListener('appUrlOpen', (data) => {
            const url = data.url;
            console.log('[Capacitor] Deep link received:', url);
            if (url && url.includes(`${APP_SCHEME}://oauth/callback`)) {
                handleCapacitorCallback(url);
            }
        });
    }
}

function logout() {
    window.localStorage.removeItem(TOKEN_KEY);
    window.localStorage.removeItem(REFRESH_TOKEN_KEY);
    window.localStorage.removeItem(INSTANCE_URL_KEY);
    clearIdentity();
    clearSessionConfirmed();
    clearLastWorkspace();
    document.documentElement.classList.remove('osr-restore-app');
    configureRuntime('');
    unmountApp();
    showFreshLogin();
    showScreen('login');
}

function mountHomeView() {
    const homeRoot = document.getElementById('view-home');
    if (!homeRoot) {
        return;
    }
    if (!homeRoot.querySelector('c-offline-app-banner')) {
        homeRoot.appendChild(createElement('c-offline-app-banner', { is: OfflineAppBanner }));
    }
    if (!homeRoot.querySelector('c-pending-payment-alert')) {
        homeRoot.appendChild(createElement('c-pending-payment-alert', { is: PendingPaymentAlert }));
    }
    if (!homeRoot.querySelector('c-field-rep-home-clm-prefetch')) {
        homeRoot.appendChild(createElement('c-field-rep-home-clm-prefetch', { is: FieldRepHomeClmPrefetch }));
    }
    if (!homeRoot.querySelector('c-home-office-messages')) {
        homeRoot.appendChild(createElement('c-home-office-messages', { is: HomeOfficeMessages }));
    }
    if (!homeRoot.querySelector('c-field-rep-home-metrics')) {
        homeRoot.appendChild(createElement('c-field-rep-home-metrics', { is: FieldRepHomeMetrics }));
    }
    if (!homeRoot.querySelector('c-field-rep-home-monthly-timecard')) {
        homeRoot.appendChild(createElement('c-field-rep-home-monthly-timecard', { is: FieldRepHomeMonthlyTimecard }));
    }
    if (!homeRoot.querySelector('c-field-rep-home-today-plan')) {
        homeRoot.appendChild(createElement('c-field-rep-home-today-plan', { is: FieldRepHomeTodayPlan }));
    }
    if (!homeRoot.querySelector('c-field-rep-home-next-best-customer')) {
        homeRoot.appendChild(createElement('c-field-rep-home-next-best-customer', { is: FieldRepHomeNextBestCustomer }));
    }
    if (!homeRoot.querySelector('c-reports-hub')) {
        homeRoot.appendChild(createElement('c-reports-hub', { is: ReportsHub }));
    }
}

function mountPlannerView() {
    const plannerRoot = document.getElementById('view-planner');
    if (!plannerRoot) {
        return;
    }
    if (!plannerRoot.querySelector('c-field-rep-planner')) {
        plannerRoot.appendChild(createElement('c-field-rep-planner', { is: FieldRepPlanner }));
    }
}

function mountAccountsView() {
    const accountsRoot = document.getElementById('view-accounts');
    if (!accountsRoot) {
        return;
    }
    if (!accountsRoot.querySelector('c-accounts-tab')) {
        accountsRoot.appendChild(createElement('c-accounts-tab', { is: AccountsTab }));
    }
}

function mountTimeOffView() {
    const timeOffRoot = document.getElementById('view-timeoff');
    if (!timeOffRoot) {
        return;
    }
    if (!timeOffRoot.querySelector('c-time-off-submission')) {
        timeOffRoot.appendChild(createElement('c-time-off-submission', { is: TimeOffSubmission }));
    }
}

function mountClmPresentationsView() {
    const clmRoot = document.getElementById('view-clm');
    if (!clmRoot) {
        return;
    }
    if (!clmRoot.querySelector('c-clm-presentations-hub')) {
        clmRoot.appendChild(createElement('c-clm-presentations-hub', { is: ClmPresentationsHub }));
    }
}

function mountMyLearningView() {
    const root = document.getElementById('view-learning');
    if (!root) {
        return;
    }
    if (!root.querySelector('c-my-learning')) {
        root.appendChild(createElement('c-my-learning', { is: MyLearning }));
    }
}

function mountChatterPanel() {
    const root = document.getElementById('view-chatter');
    if (!root) return;
    renderChatterView(root);
}

function mountReportsPanel() {
    const root = document.getElementById('view-reports');
    if (!root) return;
    renderReportsView(root);
}

function mountDashboardsPanel() {
    const root = document.getElementById('view-dashboards');
    if (!root) return;
    renderDashboardsView(root);
}

// Map app tab keys (UI API developerName) to their PWA view panel + renderer.
// Entity tabs (object list views) use the generic list page via mountListView.
// Tabs not handled render the "not available" in-panel message.
// Mount the Visit Call Shell (ported LWC). It is a Visit-record component: the
// active Visit id comes from ?visit=, localStorage (set when opening a visit
// from the planner), or — as a fallback so the tab is never empty — the user's
// most recent visit.
async function resolveActiveVisitId() {
    const urlVisit = new URLSearchParams(window.location.search).get('visit');
    if (urlVisit) {
        return urlVisit;
    }
    const stored = window.localStorage.getItem(ACTIVE_VISIT_KEY);
    if (stored) {
        return stored;
    }
    try {
        const base = String(globalThis.PLANNER_SF_INSTANCE || '').replace(/\/$/, '');
        const token = globalThis.PLANNER_ACCESS_TOKEN || '';
        if (!base || !token) {
            return null;
        }
        const q = encodeURIComponent(
            'SELECT Id FROM Visit__c ORDER BY Start_Date__c DESC NULLS LAST LIMIT 1'
        );
        const resp = await fetch(`${base}/services/data/v62.0/query?q=${q}`, {
            headers: { Accept: 'application/json', Authorization: `Bearer ${token}` }
        });
        if (resp.ok) {
            const data = await resp.json();
            const id = data.records && data.records.length ? data.records[0].Id : null;
            if (id) {
                window.localStorage.setItem(ACTIVE_VISIT_KEY, id);
                return id;
            }
        }
    } catch (_err) {
        // Offline / no access — shell shows its empty state.
    }
    return null;
}

function mountVisitCallView() {
    const root = document.getElementById('view-visitcall');
    if (!root) {
        return;
    }
    let el = root.querySelector('c-visit-call-shell');
    if (!el) {
        el = createElement('c-visit-call-shell', { is: VisitCallShell });
        root.appendChild(el);
    }
    resolveActiveVisitId().then((visitId) => {
        if (visitId) {
            el.recordId = visitId;
        }
    });
}

// Open a specific Visit in the Visit Call Shell (replaces the generic record
// page for Visit__c). Called when a Visit row is opened from the entity list.
function openVisitCall(recordId) {
    if (recordId) {
        window.localStorage.setItem(ACTIVE_VISIT_KEY, recordId);
        try {
            const url = new URL(window.location.href);
            url.searchParams.set('visit', recordId);
            window.history.replaceState({}, '', url);
        } catch (_err) {
            /* ignore */
        }
    }
    closeRecordModal();
    const root = document.getElementById('view-visitcall');
    const el = root && root.querySelector('c-visit-call-shell');
    if (el && recordId) {
        el.recordId = recordId;
    }
    currentTab = VISIT_CALL_TAB_KEY;
    if (currentOpenApp) persistOpenWorkspace();
    document.querySelectorAll('.view-panel').forEach((panel) => panel.classList.remove('active'));
    if (root) root.classList.add('active');
    mountVisitCallView();
    document.querySelectorAll('#app-tabs .nav-tab').forEach((btn) => {
        const active = btn.dataset.tab === 'Visit__c' || btn.dataset.tab === VISIT_CALL_TAB_KEY;
        btn.classList.toggle('nav-tab-active', active);
        btn.setAttribute('aria-selected', active ? 'true' : 'false');
    });
}

function handleRecordNavigation(recordId, objectApiName) {
    if (!recordId) return;
    const obj = String(objectApiName || '');
    if (obj === 'Visit__c' || obj === 'Visit') {
        openVisitCall(recordId);
        return;
    }
    if (/^report$/i.test(obj) || /^dashboard$/i.test(obj)) {
        openAnalyticsRecord(recordId, obj);
        return;
    }
    openRecordModal(recordId, obj);
}

function openAnalyticsRecord(recordId, objectApiName) {
    const isReport = /^report$/i.test(String(objectApiName || ''));
    const keys = isReport ? ['standard-report', 'standard-Report'] : ['standard-Dashboard'];
    const matched = appTabs.find((tab) => keys.includes(tab.key));
    currentTab = (matched && matched.key) || keys[0];
    if (currentOpenApp) persistOpenWorkspace();
    document.querySelectorAll('#app-tabs .nav-tab').forEach((btn) => {
        const active = keys.includes(btn.dataset.tab);
        btn.classList.toggle('nav-tab-active', active);
        btn.setAttribute('aria-selected', active ? 'true' : 'false');
    });
    document.querySelectorAll('.view-panel').forEach((panel) => panel.classList.remove('active'));
    const panelId = isReport ? 'view-reports' : 'view-dashboards';
    const root = document.getElementById(panelId);
    if (root) root.classList.add('active');
    if (isReport) {
        renderReportsView(root, { recordId });
    } else {
        renderDashboardsView(root, { recordId });
    }
}

window.addEventListener('zeta-navigate-record', (event) => {
    const detail = (event && event.detail) || {};
    handleRecordNavigation(detail.recordId, detail.objectApiName);
});

window.addEventListener('zeta-navigate-tab', (event) => {
    const detail = (event && event.detail) || {};
    const apiName = detail.apiName || detail.tab || '';
    if (!apiName) return;
    if (detail.accountId) {
        try {
            sessionStorage.setItem('zeta.pwa.planAccountId', String(detail.accountId));
        } catch (_e) {
            // ignore
        }
    }
    if (detail.action === 'newAccount') {
        try {
            sessionStorage.setItem('zeta.pwa.openNewAccount', '1');
        } catch (_e) {
            // ignore
        }
    }
    switchTab(apiName);
});

// The entity list runs in an iframe; it posts here to open Visit records
// or a record modal on this same page.
window.addEventListener('message', (event) => {
    const data = event && event.data;
    if (!data || typeof data !== 'object') return;
    if (data.type === 'open-visit-call' && data.recordId) {
        openVisitCall(data.recordId);
        return;
    }
    if (data.type === 'zeta-navigate-record' && data.recordId) {
        handleRecordNavigation(data.recordId, data.objectApiName || data.object);
        return;
    }
    if (data.type === 'zeta-navigate-tab' && data.apiName) {
        window.dispatchEvent(new CustomEvent('zeta-navigate-tab', { detail: data }));
        return;
    }
    if (data.type === 'open-record-modal' && data.recordId) {
        openRecordModal(data.recordId, data.objectApiName || data.object);
        return;
    }
    if (data.type === 'close-record-modal') {
        closeRecordModal();
    }
});

const APP_TAB_VIEWS = {
    Field_Rep_Home_App: { panel: 'view-home', mount: mountHomeView },
    Field_Rep_Planner: { panel: 'view-planner', mount: mountPlannerView },
    Accounts_Tab: { panel: 'view-accounts', mount: mountAccountsView },
    Request_Time_Off: { panel: 'view-timeoff', mount: mountTimeOffView },
    CLM_Presentations: { panel: 'view-clm', mount: mountClmPresentationsView },
    Visit_Call: { panel: 'view-visitcall', mount: mountVisitCallView },
    My_Learning: { panel: 'view-learning', mount: mountMyLearningView },
    'standard-Chatter': { panel: 'view-chatter', mount: mountChatterPanel },
    Chatter: { panel: 'view-chatter', mount: mountChatterPanel },
    'standard-Dashboard': { panel: 'view-dashboards', mount: mountDashboardsPanel },
    Dashboard: { panel: 'view-dashboards', mount: mountDashboardsPanel },
    'standard-report': { panel: 'view-reports', mount: mountReportsPanel },
    'standard-Report': { panel: 'view-reports', mount: mountReportsPanel },
    Report: { panel: 'view-reports', mount: mountReportsPanel }
};

function isEntityTab(tab) {
    return appTabs.some((t) => t.key === tab && t.type === 'Entity');
}

// A tab is "supported" if it has an offline renderer or is an object list view.
function isSupportedTab(tab) {
    if (!tab) return false;
    if (APP_TAB_VIEWS[tab.key]) return true;
    return tab.type === 'Entity';
}

function switchTab(tab) {
    if (!tab) return;
    currentTab = tab;
    if (currentOpenApp) persistOpenWorkspace();

    // Update sidebar nav tab active state
    document.querySelectorAll('#app-tabs .nav-tab').forEach(btn => {
        const active = btn.dataset.tab === tab;
        btn.classList.toggle('nav-tab-active', active);
        btn.setAttribute('aria-selected', active ? 'true' : 'false');
    });

    // Hide all view panels
    document.querySelectorAll('.view-panel').forEach(panel => {
        panel.classList.remove('active');
    });

    const view = APP_TAB_VIEWS[tab];
    if (view) {
        const panel = document.getElementById(view.panel);
        panel?.classList.add('active');
        view.mount();
        return;
    }

    if (isEntityTab(tab)) {
        mountListView();
        return;
    }

    showUnsupportedTab(tab);
}

function showUnsupportedTab(key) {
    const panel = document.getElementById('view-unsupported');
    if (!panel) return;
    const tab = appTabs.find((t) => t.key === key);
    const label = tab ? tab.label : key;
    panel.innerHTML = `
        <div class="unsupported-message">
            <h2>${label}</h2>
            <p>This tab isn't available offline. Open it in Salesforce, or pick another tab from the sidebar.</p>
        </div>
    `;
    panel.classList.add('active');
}

function mountListView() {
    const tabDef = appTabs.find((t) => t.key === currentTab);
    const object = (tabDef && tabDef.objectApiName) || (tabDef && tabDef.key) || '';
    const entityRoot = document.getElementById('view-entity');
    if (!entityRoot) return;
    let iframe = entityRoot.querySelector('iframe');
    if (!iframe) {
        iframe = document.createElement('iframe');
        iframe.style.border = 'none';
        iframe.style.width = '100%';
        iframe.style.height = '100%';
        entityRoot.appendChild(iframe);
    }
    // BASE_URL respects the deploy base (e.g. "/Zeta/" on GitHub Pages, "/" on
    // localhost/Netlify) so the iframe resolves under a subpath, not the domain root.
    const src = `${import.meta.env.BASE_URL}list.html?object=${encodeURIComponent(object)}`;
    if (iframe.dataset.src !== src) {
        iframe.dataset.src = src;
        iframe.src = src;
    }
    entityRoot.classList.add('active');
}

function unmountApp() {
    const homeRoot = document.getElementById('view-home');
    const accountsRoot = document.getElementById('view-accounts');
    const plannerRoot = document.getElementById('view-planner');
    const entityRoot = document.getElementById('view-entity');
    const unsupportedRoot = document.getElementById('view-unsupported');
    const clmRoot = document.getElementById('view-clm');
    const learningRoot = document.getElementById('view-learning');
    const visitRoot = document.getElementById('view-visitcall');
    const chatterRoot = document.getElementById('view-chatter');
    const reportsRoot = document.getElementById('view-reports');
    const dashboardsRoot = document.getElementById('view-dashboards');
    if (homeRoot) homeRoot.innerHTML = '';
    if (accountsRoot) accountsRoot.innerHTML = '';
    if (plannerRoot) plannerRoot.innerHTML = '';
    if (entityRoot) entityRoot.innerHTML = '';
    if (unsupportedRoot) unsupportedRoot.innerHTML = '';
    if (clmRoot) clmRoot.innerHTML = '';
    if (learningRoot) learningRoot.innerHTML = '';
    if (visitRoot) visitRoot.innerHTML = '';
    if (chatterRoot) chatterRoot.innerHTML = '';
    if (reportsRoot) reportsRoot.innerHTML = '';
    if (dashboardsRoot) dashboardsRoot.innerHTML = '';
    currentTab = HOME_TAB_KEY;
    currentOpenApp = null;
}

function registerServiceWorker() {
    if (!('serviceWorker' in navigator)) {
        return;
    }
    window.addEventListener('load', () => {
        navigator.serviceWorker.register('/sw.js').catch((error) => {
            console.warn('Service worker registration failed', error);
        });
    });
}

// Show exactly one top-level screen: 'login' | 'chooser' | 'app'.
function showScreen(name) {
    currentScreen = name;
    if (name === 'app' || name === 'chooser') {
        document.documentElement.classList.toggle('osr-restore-app', name === 'app');
        if (name === 'chooser' && !pendingRestore) {
            writeLastWorkspace({ screen: 'chooser' });
        }
    }
    const login = document.getElementById('session-bar');
    const chooser = document.getElementById('app-chooser');
    const nav = document.getElementById('app-nav');
    const shell = document.getElementById('app');
    const toast = document.getElementById('toast-container');

    document.body.dataset.screen = name;
    document.body.classList.toggle('screen-login', name === 'login');
    document.body.classList.toggle('screen-chooser', name === 'chooser');
    document.body.classList.toggle('screen-app', name === 'app');

    const setVisible = (el, visible, displayWhenVisible) => {
        if (!el) return;
        el.hidden = !visible;
        if (visible) {
            el.removeAttribute('hidden');
            el.style.display = displayWhenVisible;
        } else {
            el.setAttribute('hidden', '');
            el.style.display = 'none';
        }
    };

    // Login must never leave #app-nav visible (CSS display:flex used to beat [hidden]).
    setVisible(login, name === 'login', 'flex');
    setVisible(chooser, name === 'chooser', 'block');
    setVisible(nav, name === 'app', 'flex');
    setVisible(shell, name === 'app', '');

    if (toast) {
        if (name === 'login') {
            toast.setAttribute('hidden', '');
            toast.style.display = 'none';
            toast.innerHTML = '';
        } else {
            toast.removeAttribute('hidden');
            toast.style.display = '';
        }
    }
}

// Salesforce-style App Launcher: search across apps + items, open an app or
// jump straight to a single object/tab. Renders Pharma immediately (local,
// always tappable), then augments with the org's apps once fetchApps resolves.
let chooserApps = [];
let chooserItems = [];
let chooserSearchWired = false;

function buildAppChooser() {
    showScreen('chooser');
    const grid = document.getElementById('app-chooser-grid');
    if (!grid) return;

    chooserApps = [ensureAppTabs(PHARMA_APP)];
    chooserItems = buildItemsFromApps(chooserApps);
    renderChooser();
    wireChooserSearch();
    loadOrgAppsIntoChooser();
}

function seedChooserFromCache() {
    const cached = readCachedApps();
    if (!cached.length) return;
    chooserApps = cached;
    chooserItems = buildItemsFromApps(chooserApps);
}

function loadOrgAppsIntoChooser() {
    fetchApps({ forceRefresh: true })
        .then((apps) => {
            if (apps && apps.length) {
                chooserApps = apps;
                applyChooserUpdate();
            }
        })
        .catch((error) => {
            console.warn('[AppChooser] Failed to load org apps:', error);
        });

    fetchTabs({ forceRefresh: true })
        .then((tabs) => {
            if (tabs && tabs.length) {
                chooserItems = tabs;
                applyChooserUpdate();
            }
        })
        .catch((error) => {
            console.warn('[AppChooser] Failed to load org tabs:', error);
        });
}

function restoreLastLightningApp() {
    const ws = readLastWorkspace();
    if (!ws || ws.screen !== 'app' || !ws.developerName) return false;
    pendingRestore = {
        developerName: ws.developerName,
        id: ws.id || null,
        tabKey: ws.tabKey || null
    };
    const cached = readCachedApps();
    let match = findAppBySaved(cached, pendingRestore);
    if (!match && isPharmaWorkspace(pendingRestore)) {
        match = PHARMA_APP;
    }
    if (!match) return false;
    openApp(match, { preferredTab: pendingRestore.tabKey });
    return true;
}

function restorePendingAppFromChooser() {
    if (!pendingRestore || currentScreen === 'app') return;
    const match = findAppBySaved(chooserApps, pendingRestore);
    if (!match) return;
    openApp(match, { preferredTab: pendingRestore.tabKey });
}

function applyChooserUpdate() {
    chooserApps = overlayTabIcons(chooserApps, chooserItems);
    if (!chooserItems.length) {
        chooserItems = buildItemsFromApps(chooserApps);
    }
    renderChooser();
    syncOpenAppFromOrg();
    restorePendingAppFromChooser();
}

window.addEventListener('zeta-apps-refreshed', (event) => {
    const apps = event.detail && event.detail.apps;
    if (apps && apps.length) {
        chooserApps = apps;
        applyChooserUpdate();
    }
});

// Flatten every app's tabs into a de-duped, sorted item list (the "All Items"
// section — objects, record pages and flexipage tabs the user can open).
function buildItemsFromApps(apps) {
    const seen = new Map();
    (apps || []).forEach((app) => {
        (app.tabs || []).forEach((tab) => {
            if (tab && tab.key && !seen.has(tab.key)) {
                seen.set(tab.key, tab);
            }
        });
    });
    return Array.from(seen.values()).sort((a, b) =>
        (a.label || '').localeCompare(b.label || '')
    );
}

function wireChooserSearch() {
    if (chooserSearchWired) return;
    const input = document.getElementById('chooser-search');
    if (!input) return;
    chooserSearchWired = true;
    input.addEventListener('input', renderChooser);
}

function renderChooser() {
    const term = (document.getElementById('chooser-search')?.value || '').trim().toLowerCase();
    const match = (label) => !term || (label || '').toLowerCase().includes(term);
    renderAppCards(chooserApps.filter((a) => match(a.label)));
    renderItemCards(chooserItems.filter((i) => match(i.label)));
}

// Build an icon element: real image when a URL loads, else a letter tile.
// A broken/blocked icon URL falls back to the letter instead of a blank gap.
function buildIconEl(url, label, baseCls) {
    const letter = (label || '?').charAt(0);
    const fallback = document.createElement('span');
    fallback.className = `${baseCls} ${baseCls}-fallback`;
    fallback.textContent = letter;
    if (!url) return fallback;

    const img = document.createElement('img');
    img.className = baseCls;
    img.src = url;
    img.alt = '';
    img.loading = 'lazy';
    img.addEventListener('error', () => {
        if (img.parentNode) img.parentNode.replaceChild(fallback, img);
    });
    return img;
}

function renderAppCards(apps) {
    const grid = document.getElementById('app-chooser-grid');
    if (!grid) return;
    grid.innerHTML = '';
    if (!apps.length) {
        grid.innerHTML = '<p class="chooser-empty">No matching apps.</p>';
        return;
    }
    apps.forEach((app) => {
        const card = document.createElement('button');
        card.className = 'chooser-card' + (app.fullOffline ? ' chooser-card-offline' : '');
        card.type = 'button';
        card.title = app.label;

        const tabCount = (app.tabs && app.tabs.length) || 0;
        const desc = app.description || `${tabCount} tab${tabCount === 1 ? '' : 's'}`;
        const body = document.createElement('span');
        body.className = 'chooser-card-body';
        body.innerHTML =
            `<span class="chooser-card-title">${app.label}</span>` +
            `<span class="chooser-card-desc">${desc}</span>`;

        card.appendChild(buildIconEl(app.iconUrl, app.label, 'chooser-card-icon'));
        card.appendChild(body);
        if (app.fullOffline) {
            const badge = document.createElement('span');
            badge.className = 'chooser-card-badge';
            badge.textContent = 'Offline ready';
            card.appendChild(badge);
        }
        card.addEventListener('click', () => openApp(app));
        grid.appendChild(card);
    });
}

function renderItemCards(items) {
    const grid = document.getElementById('item-chooser-grid');
    if (!grid) return;
    grid.innerHTML = '';
    if (!items.length) {
        grid.innerHTML = '<p class="chooser-empty">No matching items.</p>';
        return;
    }
    items.forEach((item) => {
        const chip = document.createElement('button');
        chip.className = 'chooser-item';
        chip.type = 'button';
        chip.title = item.label;

        const label = document.createElement('span');
        label.className = 'chooser-item-label';
        label.textContent = item.label;

        chip.appendChild(buildIconEl(item.iconUrl, item.label, 'chooser-item-icon'));
        chip.appendChild(label);
        chip.addEventListener('click', () => openItem(item));
        grid.appendChild(chip);
    });
}

const FIELD_ITEM_ALIASES = {
    Account: 'Accounts_Tab',
    'standard-Account': 'Accounts_Tab',
    standard_Account: 'Accounts_Tab'
};

// Open a single object/tab directly (the "All Items" behaviour), so the shell
// shows just that item. switchTab handles entity list views, known offline
// views and the "not available" fallback.
function openItem(item) {
    if (!item || !item.key) return;
    const fieldApp = ensureAppTabs(
        chooserApps.find((app) => app.fullOffline) || PHARMA_APP
    );
    const mappedKey = FIELD_ITEM_ALIASES[item.key] || FIELD_ITEM_ALIASES[item.objectApiName] || item.key;
    const match = (fieldApp.tabs || []).find(
        (tab) =>
            tab.key === mappedKey ||
            tab.key === item.key ||
            (item.objectApiName && tab.objectApiName === item.objectApiName) ||
            (item.label && tab.label === item.label)
    );
    if (match) {
        openApp(fieldApp);
        switchTab(match.key);
        return;
    }
    currentOpenApp = null;
    const tabs = [item];
    appTabs = tabs;
    const titleEl = document.getElementById('nav-title');
    if (titleEl) titleEl.textContent = item.label || 'Item';
    renderTabButtons(tabs);
    currentTab = item.key;
    showScreen('app');
    switchTab(item.key);
}

// Open the chosen app: load its tabs, render the sidebar, show the app screen.
function openApp(app, options = {}) {
    const resolved = ensureAppTabs(app);
    currentOpenApp = resolved;
    pendingRestore = null;
    const tabs = resolved && Array.isArray(resolved.tabs) ? resolved.tabs.slice() : [];
    appTabs = tabs;
    const titleEl = document.getElementById('nav-title');
    if (titleEl) titleEl.textContent = (resolved && resolved.label) || 'App';

    renderTabButtons(tabs);
    showScreen('app');

    // Land on the first tab that actually renders (Home preferred), so the app
    // never opens on a blank "not available" panel. All tabs stay in the nav.
    const preferredKey = options.preferredTab;
    const preferredTab = preferredKey && tabs.find((t) => t.key === preferredKey);
    const homeTab = tabs.find((t) => t.key === HOME_TAB_KEY && isSupportedTab(t));
    const firstSupported = tabs.find(isSupportedTab);
    currentTab = (preferredTab || homeTab || firstSupported || tabs[0] || {}).key || null;
    persistOpenWorkspace();

    if (currentTab) {
        switchTab(currentTab);
    } else {
        // App returned no tabs (only the org's *selected* app exposes navItems).
        // Clear any stale panel and show a clean empty state.
        showEmptyApp(app);
    }

    const visitFromUrl = new URLSearchParams(window.location.search).get('visit');
    if (visitFromUrl && resolved.fullOffline) {
        openVisitCall(visitFromUrl);
    }
}

function showEmptyApp(app) {
    document.querySelectorAll('.view-panel').forEach((p) => p.classList.remove('active'));
    const panel = document.getElementById('view-unsupported');
    if (!panel) return;
    const label = (app && app.label) || 'This app';
    panel.innerHTML = `
        <div class="unsupported-message">
            <h2>${label}</h2>
            <p>No offline-available tabs for this app. Use <strong>All Items</strong> in the launcher to open an object, or open the app in Salesforce.</p>
        </div>
    `;
    panel.classList.add('active');
}

function syncOpenAppFromOrg() {
    if (currentScreen !== 'app' || !currentOpenApp) return;
    const key = currentOpenApp.developerName;
    const fresh =
        chooserApps.find((a) => a.developerName === key) ||
        chooserApps.find((a) => a.fullOffline);
    if (!fresh || !Array.isArray(fresh.tabs) || !fresh.tabs.length) return;

    const sameTabs =
        fresh.tabs.length === appTabs.length &&
        fresh.tabs.every((tab, i) => tab.key === appTabs[i].key && tab.label === appTabs[i].label && tab.iconUrl === appTabs[i].iconUrl);
    if (sameTabs) return;

    currentOpenApp = fresh;
    appTabs = fresh.tabs.slice();
    const titleEl = document.getElementById('nav-title');
    if (titleEl) titleEl.textContent = fresh.label || 'App';
    const keep = currentTab;
    renderTabButtons(appTabs);
    if (keep && appTabs.some((t) => t.key === keep)) {
        switchTab(keep);
    } else if (appTabs[0]) {
        switchTab(appTabs[0].key);
    }
}

function renderTabButtons(tabs) {
    const tabsContainer = document.getElementById('app-tabs');
    if (!tabsContainer) return;
    tabsContainer.innerHTML = '';
    tabs.forEach((tab) => {
        const btn = document.createElement('button');
        btn.className = 'nav-tab';
        btn.type = 'button';
        btn.role = 'tab';
        btn.dataset.tab = tab.key;
        btn.setAttribute('aria-selected', 'false');
        btn.title = tab.label;

        const iconWrap = document.createElement('span');
        iconWrap.className = 'nav-icon-wrap';
        iconWrap.appendChild(svgIconEl(tab.key));

        const label = document.createElement('span');
        label.textContent = tab.label || tab.key;

        btn.appendChild(iconWrap);
        btn.appendChild(label);
        btn.addEventListener('click', () => switchTab(tab.key));
        tabsContainer.appendChild(btn);
    });
}

function svgIconEl(tabKey) {
    const span = document.createElement('span');
    span.className = 'nav-icon-wrap';
    span.innerHTML = defaultTabIcon(tabKey);
    return span.firstElementChild || span;
}

function defaultTabIcon(tabKey) {
    const exact = String(tabKey || '');
    const key = exact.toLowerCase();
    if (exact === 'Field_Rep_Home_App' || key === 'home') {
        return `<svg class="nav-icon" viewBox="0 0 24 24" fill="currentColor" aria-hidden="true"><path d="M12 3 2 10v11h7v-6h6v6h7V10L12 3z"/></svg>`;
    }
    if (exact === 'Field_Rep_Planner' || key.includes('planner')) {
        return `<svg class="nav-icon" viewBox="0 0 24 24" fill="currentColor" aria-hidden="true"><path d="M7 2h2v2h6V2h2v2h3a1 1 0 0 1 1 1v15a1 1 0 0 1-1 1H4a1 1 0 0 1-1-1V5a1 1 0 0 1 1-1h3V2zm12 8H5v10h14V10zM8 12h3v3H8v-3z"/></svg>`;
    }
    if (exact === 'Accounts_Tab' || key.includes('account')) {
        return `<svg class="nav-icon" viewBox="0 0 24 24" fill="currentColor" aria-hidden="true"><path d="M4 21V9l8-6 8 6v12h-6v-6H10v6H4zm2-2h2v-4h8v4h2v-9.2L12 5.5 6 9.8V19z"/></svg>`;
    }
    if (exact === 'My_Learning' || key.includes('learning')) {
        return `<svg class="nav-icon" viewBox="0 0 24 24" fill="currentColor" aria-hidden="true"><path d="M12 3 1 9l11 6 9-4.91V17h2V9L12 3zm-7.84 9.15L12 16.5l7.84-4.35L12 21 4.16 12.15z"/></svg>`;
    }
    if (exact === 'CLM_Presentations' || key.includes('clm') || key.includes('present')) {
        return `<svg class="nav-icon" viewBox="0 0 24 24" fill="currentColor" aria-hidden="true"><path d="M4 4h16v12H4V4zm2 2v8h12V6H6zm6 12 4 4H8l4-4z"/></svg>`;
    }
    if (exact === 'Visit__c' || key.includes('visit')) {
        return `<svg class="nav-icon" viewBox="0 0 24 24" fill="currentColor" aria-hidden="true"><path d="M12 2a7 7 0 0 1 7 7c0 5.25-7 13-7 13S5 14.25 5 9a7 7 0 0 1 7-7zm0 4.5A2.5 2.5 0 1 0 12 11a2.5 2.5 0 0 0 0-4.5z"/></svg>`;
    }
    if (exact === 'Coaching_Event__c' || key.includes('coach')) {
        return `<svg class="nav-icon" viewBox="0 0 24 24" fill="currentColor" aria-hidden="true"><path d="M3 17.25V21h3.75L17.81 9.94l-3.75-3.75L3 17.25zM20.71 7.04a1 1 0 0 0 0-1.41l-2.34-2.34a1 1 0 0 0-1.41 0l-1.83 1.83 3.75 3.75 1.83-1.83z"/></svg>`;
    }
    if (exact === 'standard-Chatter' || key.includes('chatter')) {
        return `<svg class="nav-icon" viewBox="0 0 24 24" fill="currentColor" aria-hidden="true"><path d="M4 4h16a2 2 0 0 1 2 2v9a2 2 0 0 1-2 2H8l-4 4V6a2 2 0 0 1 2-2zm2 4v2h12V8H6zm0 4v2h8v-2H6z"/></svg>`;
    }
    if (exact === 'standard-Dashboard' || key.includes('dashboard')) {
        return `<svg class="nav-icon" viewBox="0 0 24 24" fill="currentColor" aria-hidden="true"><path d="M3 13h8V3H3v10zm0 8h8v-6H3v6zm10 0h8V11h-8v10zm0-18v6h8V3h-8z"/></svg>`;
    }
    if (exact === 'standard-report' || exact === 'standard-Report' || key.includes('report')) {
        return `<svg class="nav-icon" viewBox="0 0 24 24" fill="currentColor" aria-hidden="true"><path d="M5 3h10l4 4v14a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2V5a2 2 0 0 1 2-2zm9 1.5V8h3.5L14 4.5zM7 12h10v2H7v-2zm0 4h10v2H7v-2zM7 8h5v2H7V8z"/></svg>`;
    }
    if (exact === 'Request_Time_Off' || key.includes('time') || key.includes('off')) {
        return `<svg class="nav-icon" viewBox="0 0 24 24" fill="currentColor" aria-hidden="true"><path d="M21 16v-2l-8-5V3.5A1.5 1.5 0 0 0 11.5 2 1.5 1.5 0 0 0 10 3.5V9l-8 5v2l8-2.5V19l-2 1.5V22l3.5-1 3.5 1v-1.5L13 19v-5.5L21 16z"/></svg>`;
    }
    return `<svg class="nav-icon" viewBox="0 0 520 520" fill="currentColor" aria-hidden="true">
        <path d="M490 270h-50v220c0 6-4 10-10 10H330c-6 0-10-4-10-10V320H200v170c0 6-4 10-10 10H90c-6 0-10-4-10-10V270H30c-4 0-8-2-9-6-2-4-1-8 2-11L253 23c4-4 11-4 14 0l230 230c3 3 3 7 2 11s-5 6-9 6z"/>
    </svg>`;
}

function setupNavigation() {
    setupRecordModal();
}

function setupRecordModal() {
    if (document.getElementById('record-modal')) return;
    const modal = document.createElement('div');
    modal.id = 'record-modal';
    modal.className = 'record-modal';
    modal.hidden = true;
    modal.innerHTML =
        '<div class="record-modal-backdrop" data-close="1"></div>' +
        '<div class="record-modal-panel" role="dialog" aria-modal="true" aria-label="Record">' +
        '<div class="record-modal-chrome">' +
        '<span class="record-modal-chrome-title">Record</span>' +
        '<button type="button" class="record-modal-expand" data-expand="1" aria-pressed="false">Full screen</button>' +
        '<button type="button" class="record-modal-close" data-close="1">Close</button>' +
        '</div>' +
        '<div id="record-modal-host" class="record-modal-host" hidden></div>' +
        '<iframe id="record-modal-frame" title="Record"></iframe>' +
        '</div>';
    modal.addEventListener('click', (event) => {
        const target = event.target;
        if (!target || !target.getAttribute) return;
        if (target.getAttribute('data-close')) {
            closeRecordModal();
            return;
        }
        if (target.getAttribute('data-expand')) {
            toggleRecordModalFullscreen();
        }
    });
    document.body.appendChild(modal);
    document.addEventListener('keydown', (event) => {
        if (event.key !== 'Escape') return;
        const openModal = document.getElementById('record-modal');
        if (!openModal || openModal.hidden) return;
        if (openModal.classList.contains('is-fullscreen')) {
            toggleRecordModalFullscreen();
            return;
        }
        closeRecordModal();
    });
}

function syncRecordModalExpandButton(modal) {
    const btn = modal && modal.querySelector('[data-expand]');
    if (!btn) return;
    const expanded = modal.classList.contains('is-fullscreen');
    btn.textContent = expanded ? 'Exit full screen' : 'Full screen';
    btn.setAttribute('aria-pressed', expanded ? 'true' : 'false');
}

function toggleRecordModalFullscreen() {
    const modal = document.getElementById('record-modal');
    if (!modal) return;
    modal.classList.toggle('is-fullscreen');
    syncRecordModalExpandButton(modal);
}

const COACHING_PATH_STEPS = [
    'Draft',
    'Planned',
    'In Progress',
    'Self Evaluation',
    'Available for Scoring',
    'Review',
    'Closed'
];

function clearRecordModalHost() {
    const host = document.getElementById('record-modal-host');
    if (host) {
        host.innerHTML = '';
        host.hidden = true;
        host.setAttribute('hidden', '');
    }
    const frame = document.getElementById('record-modal-frame');
    if (frame) {
        frame.hidden = false;
        frame.removeAttribute('hidden');
        frame.style.display = '';
    }
}

function mountCoachingRecord(recordId) {
    const host = document.getElementById('record-modal-host');
    const frame = document.getElementById('record-modal-frame');
    const title = document.querySelector('.record-modal-chrome-title');
    if (!host) return;
    if (frame) {
        frame.src = 'about:blank';
        frame.hidden = true;
        frame.setAttribute('hidden', '');
        frame.style.display = 'none';
    }
    host.hidden = false;
    host.removeAttribute('hidden');
    host.style.display = 'block';
    host.innerHTML = '';
    if (title) title.textContent = 'Coaching Event';

    const path = document.createElement('div');
    path.className = 'coaching-path';
    path.setAttribute('aria-label', 'Coaching status path');
    COACHING_PATH_STEPS.forEach((step, index) => {
        const chip = document.createElement('span');
        chip.className = 'coaching-path-step';
        chip.dataset.step = step;
        chip.textContent = step;
        if (index < COACHING_PATH_STEPS.length - 1) {
            path.appendChild(chip);
            const sep = document.createElement('span');
            sep.className = 'coaching-path-sep';
            sep.textContent = '›';
            path.appendChild(sep);
        } else {
            path.appendChild(chip);
        }
    });
    host.appendChild(path);

    const tabs = document.createElement('div');
    tabs.className = 'coaching-record-tabs';
    const evalBtn = document.createElement('button');
    evalBtn.type = 'button';
    evalBtn.className = 'coaching-record-tab is-active';
    evalBtn.textContent = 'Evaluation';
    const detailBtn = document.createElement('button');
    detailBtn.type = 'button';
    detailBtn.className = 'coaching-record-tab';
    detailBtn.textContent = 'Details';
    tabs.appendChild(evalBtn);
    tabs.appendChild(detailBtn);
    host.appendChild(tabs);

    const evalPane = document.createElement('div');
    evalPane.className = 'coaching-record-pane';
    const detailPane = document.createElement('div');
    detailPane.className = 'coaching-record-pane';
    detailPane.hidden = true;
    host.appendChild(evalPane);
    host.appendChild(detailPane);

    const evaluation = createElement('c-coaching-event-evaluation', { is: CoachingEventEvaluation });
    evaluation.recordId = recordId;
    evalPane.appendChild(evaluation);

    const detailFrame = document.createElement('iframe');
    detailFrame.className = 'coaching-detail-frame';
    detailFrame.title = 'Coaching details';
    detailFrame.src = `${import.meta.env.BASE_URL}record.html?embed=1&recordId=${encodeURIComponent(recordId)}&object=${encodeURIComponent('Coaching_Event__c')}`;
    detailPane.appendChild(detailFrame);

    evalBtn.addEventListener('click', () => {
        evalBtn.classList.add('is-active');
        detailBtn.classList.remove('is-active');
        evalPane.hidden = false;
        detailPane.hidden = true;
    });
    detailBtn.addEventListener('click', () => {
        detailBtn.classList.add('is-active');
        evalBtn.classList.remove('is-active');
        detailPane.hidden = false;
        evalPane.hidden = true;
    });

    // Highlight current status on the path when possible.
    void plannerApiFetch(
        `/services/data/v62.0/query?q=${encodeURIComponent(
            `SELECT Status__c FROM Coaching_Event__c WHERE Id = '${String(recordId).replace(/'/g, "\\'")}' LIMIT 1`
        )}`
    )
        .then((data) => {
            const status = data?.records?.[0]?.Status__c;
            if (!status) return;
            path.querySelectorAll('.coaching-path-step').forEach((chip) => {
                chip.classList.toggle('is-current', chip.dataset.step === status);
                const idx = COACHING_PATH_STEPS.indexOf(chip.dataset.step);
                const cur = COACHING_PATH_STEPS.indexOf(status);
                chip.classList.toggle('is-complete', idx >= 0 && cur >= 0 && idx < cur);
            });
        })
        .catch(() => {});
}

function mountAccountRecord(recordId) {
    const host = document.getElementById('record-modal-host');
    const frame = document.getElementById('record-modal-frame');
    const title = document.querySelector('.record-modal-chrome-title');
    if (!host) return;
    if (frame) {
        frame.src = 'about:blank';
        frame.hidden = true;
        frame.setAttribute('hidden', '');
        frame.style.display = 'none';
    }
    host.hidden = false;
    host.removeAttribute('hidden');
    host.style.display = 'flex';
    host.innerHTML = '';
    if (title) title.textContent = 'Account';

    const stageHost = document.createElement('div');
    stageHost.className = 'account-record-stage';
    host.appendChild(stageHost);
    try {
        const stage = createElement('c-account-stage-assistant', { is: AccountStageAssistant });
        stage.recordId = recordId;
        stageHost.appendChild(stage);
    } catch (err) {
        stageHost.hidden = true;
        console.warn('[Account] stage assistant mount failed', err);
    }

    const tabDefs = [
        { id: 'details', label: 'Details' },
        { id: 'affiliations', label: 'Affiliations' },
        { id: 'apm', label: 'APM' },
        { id: 'ratings', label: 'Ratings' },
        { id: 'insights', label: 'Visit Insights' }
    ];
    const tabs = document.createElement('div');
    tabs.className = 'coaching-record-tabs account-record-tabs';
    const panes = {};
    const buttons = {};
    tabDefs.forEach((def, index) => {
        const btn = document.createElement('button');
        btn.type = 'button';
        btn.className = `coaching-record-tab${index === 0 ? ' is-active' : ''}`;
        btn.textContent = def.label;
        tabs.appendChild(btn);
        buttons[def.id] = btn;

        const pane = document.createElement('div');
        pane.className = 'coaching-record-pane';
        pane.hidden = index !== 0;
        host.appendChild(pane);
        panes[def.id] = pane;
    });
    host.insertBefore(tabs, panes.details);

    const detailFrame = document.createElement('iframe');
    detailFrame.className = 'coaching-detail-frame';
    detailFrame.title = 'Account details';
    detailFrame.src = `${import.meta.env.BASE_URL}record.html?embed=1&recordId=${encodeURIComponent(recordId)}&object=${encodeURIComponent('Account')}`;
    panes.details.appendChild(detailFrame);

    const mountLwc = (pane, tag, Ctor, emptyTitle) => {
        try {
            const el = createElement(tag, { is: Ctor });
            el.recordId = recordId;
            pane.appendChild(el);
        } catch (err) {
            pane.innerHTML = `<div class="unsupported-message"><h2>${emptyTitle}</h2><p>Could not load this panel offline.</p></div>`;
            console.warn(`[Account] ${emptyTitle} mount failed`, err);
        }
    };
    mountLwc(panes.affiliations, 'c-account-affiliation-network', AccountAffiliationNetwork, 'Affiliations');
    mountLwc(panes.apm, 'c-account-hcp-product-roi', AccountHcpProductRoi, 'APM');
    mountLwc(panes.ratings, 'c-account-ratings-panel', AccountRatingsPanel, 'Ratings');
    mountLwc(panes.insights, 'c-account-visit-insights-panel', AccountVisitInsightsPanel, 'Visit Insights');

    const activate = (id) => {
        Object.keys(buttons).forEach((key) => {
            buttons[key].classList.toggle('is-active', key === id);
            panes[key].hidden = key !== id;
        });
    };
    Object.keys(buttons).forEach((id) => {
        buttons[id].addEventListener('click', () => activate(id));
    });
}

function openRecordModal(recordId, objectApiName) {
    if (!recordId) return;
    setupRecordModal();
    const modal = document.getElementById('record-modal');
    const frame = document.getElementById('record-modal-frame');
    const title = document.querySelector('.record-modal-chrome-title');
    const objectName = String(objectApiName || '');
    const isCoaching =
        objectName === 'Coaching_Event__c' || objectName.toLowerCase().includes('coaching_event');
    const isAccount = objectName === 'Account' || /^001/.test(String(recordId));

    if (isCoaching) {
        mountCoachingRecord(recordId);
    } else if (isAccount && (objectName === 'Account' || !objectName)) {
        mountAccountRecord(recordId);
    } else {
        clearRecordModalHost();
        if (title) title.textContent = 'Record';
        const src = `${import.meta.env.BASE_URL}record.html?embed=1&recordId=${encodeURIComponent(recordId)}&object=${encodeURIComponent(objectApiName || '')}`;
        if (frame) frame.src = src;
    }
    if (modal) {
        modal.classList.remove('is-fullscreen');
        syncRecordModalExpandButton(modal);
        modal.hidden = false;
        modal.removeAttribute('hidden');
    }
    document.body.classList.add('record-modal-open');
}

function closeRecordModal() {
    const modal = document.getElementById('record-modal');
    const frame = document.getElementById('record-modal-frame');
    clearRecordModalHost();
    if (frame) frame.src = 'about:blank';
    if (modal) {
        modal.classList.remove('is-fullscreen');
        syncRecordModalExpandButton(modal);
        modal.hidden = true;
        modal.setAttribute('hidden', '');
    }
    document.body.classList.remove('record-modal-open');
}

// Debug function to test the endpoint
window.testAccountsEndpoint = async function() {
    const restBase = globalThis.PLANNER_REST_BASE || '(not set)';
    const token = globalThis.PLANNER_ACCESS_TOKEN || '(not set)';
    const endpoint = '/services/apexrest/planner/v1/accounts-tab/page?pageSize=1';
    const fullUrl = `${restBase}${endpoint}`;

    console.log('=== DEBUG: Testing Accounts Endpoint ===');
    console.log('Base URL:', restBase);
    console.log('Token present:', !!token);
    console.log('Token (first 20 chars):', token ? token.substring(0, 20) + '...' : 'none');
    console.log('Endpoint:', endpoint);
    console.log('Full URL:', fullUrl);

    try {
        const response = await fetch(fullUrl, {
            method: 'GET',
            headers: {
                'Accept': 'application/json',
                'Authorization': `Bearer ${token}`
            }
        });
        console.log('Response status:', response.status);
        console.log('Response status text:', response.statusText);
        const text = await response.text();
        console.log('Response body (first 500 chars):', text.substring(0, 500));
        return { status: response.status, body: text };
    } catch (error) {
        console.error('Fetch error:', error.message);
        return { error: error.message };
    }
};

let sessionBarWired = false;

function setupSessionBar(token) {
    if (sessionBarWired) {
        void token;
        return;
    }
    sessionBarWired = true;

    const loginBtn = document.getElementById('login-btn');
    const logoutBtn = document.getElementById('logout-btn');
    const envSelect = document.getElementById('login-env');
    const domainInput = document.getElementById('custom-domain-input');
    const continueBtn = document.getElementById('continue-session-btn');
    const switchUserBtn = document.getElementById('switch-user-btn');

    if (logoutBtn) {
        logoutBtn.addEventListener('click', logout);
    }

    const chooserLogoutBtn = document.getElementById('chooser-logout-btn');
    if (chooserLogoutBtn) {
        chooserLogoutBtn.addEventListener('click', logout);
    }

    // "Switch app" returns to the launcher without dropping the session.
    const switchAppBtn = document.getElementById('switch-app-btn');
    if (switchAppBtn) {
        switchAppBtn.addEventListener('click', buildAppChooser);
    }

    prefillsCustomDomainFromEnv();
    if (envSelect) {
        envSelect.addEventListener('change', syncLoginFormUi);
    }
    if (domainInput) {
        domainInput.addEventListener('input', syncLoginFormUi);
    }
    syncLoginFormUi();

    if (loginBtn) {
        loginBtn.addEventListener('click', login);
    }
    if (continueBtn) {
        continueBtn.addEventListener('click', () => {
            enterAuthenticatedApp();
        });
    }
    if (switchUserBtn) {
        switchUserBtn.addEventListener('click', logout);
    }

    setupLoginDownloads();
    // Screen visibility is owned by showScreen(); this only wires buttons.
    void token;
}

let deferredPwaInstallPrompt = null;

function isIosDevice() {
    const ua = navigator.userAgent || '';
    return /iPad|iPhone|iPod/.test(ua) || (navigator.platform === 'MacIntel' && navigator.maxTouchPoints > 1);
}

function isStandalonePwa() {
    return (
        window.matchMedia('(display-mode: standalone)').matches ||
        window.navigator.standalone === true
    );
}

async function setupLoginDownloads() {
    const androidMeta = document.getElementById('android-download-meta');
    const iosBtn = document.getElementById('ios-install-btn');
    const iosHint = document.getElementById('ios-install-hint');

    if (androidMeta) {
        try {
            const res = await fetch('/downloads/apk-latest.json', { cache: 'no-store' });
            if (res.ok) {
                const meta = await res.json();
                if (meta?.version) {
                    androidMeta.textContent = `v${meta.version}`;
                }
            }
        } catch {
            // Keep default "APK install" label if metadata is unavailable.
        }
    }

    window.addEventListener('beforeinstallprompt', (event) => {
        event.preventDefault();
        deferredPwaInstallPrompt = event;
        if (iosHint) iosHint.hidden = true;
    });

    window.addEventListener('appinstalled', () => {
        deferredPwaInstallPrompt = null;
        if (iosHint) {
            iosHint.hidden = false;
            iosHint.textContent = 'Installed. Open Pharma Field from your home screen anytime.';
        }
    });

    if (!iosBtn) return;

    iosBtn.addEventListener('click', async () => {
        if (isStandalonePwa()) {
            if (iosHint) {
                iosHint.hidden = false;
                iosHint.textContent = 'You’re already running the installed app.';
            }
            return;
        }

        if (deferredPwaInstallPrompt) {
            try {
                await deferredPwaInstallPrompt.prompt();
                const choice = await deferredPwaInstallPrompt.userChoice;
                deferredPwaInstallPrompt = null;
                if (iosHint) {
                    iosHint.hidden = false;
                    iosHint.textContent =
                        choice?.outcome === 'accepted'
                            ? 'Installing… Look for Pharma Field on your home screen.'
                            : 'Install cancelled. You can try again anytime.';
                }
                return;
            } catch {
                // Fall through to manual guidance.
            }
        }

        if (iosHint) {
            iosHint.hidden = false;
            iosHint.textContent = isIosDevice()
                ? 'On iPhone/iPad: tap Share, then Add to Home Screen to install Pharma Field.'
                : 'In your browser menu, choose Install app or Add to Home Screen to install Pharma Field.';
        }
    });
}

async function stampOfflineRuntimeVersion() {
    document.documentElement.classList.add('osr-offline-shell');
    let version = '';
    try {
        const local = await fetch('/downloads/apk-latest.json', { cache: 'no-store' });
        if (local.ok) {
            const meta = await local.json();
            version = meta?.version ? String(meta.version) : '';
        }
    } catch (_e) {
        // ignore
    }
    if (!version) {
        try {
            version = localStorage.getItem(APP_VERSION_KEY) || '';
        } catch (_e) {
            version = '';
        }
    }
    if (version) {
        try {
            localStorage.setItem(APP_VERSION_KEY, version);
        } catch (_e) {
            // ignore
        }
    }
    window.__OSR_RUNTIME__ = {
        shell: 'offline',
        version,
        capacitor: isCapacitor()
    };
}

async function initializeApp(options = {}) {
    console.log('[App] Initializing...');
    console.log('[App] User Agent:', navigator.userAgent);
    console.log('[App] Initial window.Capacitor:', typeof window.Capacitor);

    await stampOfflineRuntimeVersion();

    const enterImmediately = !!options.enterImmediately;
    const oauthCallback = isOAuthCallbackLocation();
    const storedSession = hasStoredSession();

    if (oauthCallback) {
        showFreshLogin();
        showScreen('login');
        setLoginStatus('Completing sign-in…');
    } else if (storedSession && !isSessionConfirmed() && !enterImmediately) {
        showResumeSession();
        showScreen('login');
    } else if (!storedSession) {
        showFreshLogin();
        showScreen('login');
    }

    const capacitorReady = await waitForCapacitor(3000);
    console.log('[App] Capacitor ready:', capacitorReady);
    console.log('[App] isCapacitor():', isCapacitor());
    console.log('[App] callbackUrl:', OAUTH_CONFIG.callbackUrl);
    console.log('[App] stored redirectUri:', OAUTH_CONFIG.redirectUri);
    console.log('[App] stored loginUrl:', OAUTH_CONFIG.loginUrl);

    await initCapacitorListener();

    let oauthHandled = false;
    if (oauthCallback) {
        oauthHandled = true;
        try {
            await completeWebOAuthLogin(window.location.href);
        } catch (error) {
            console.error('OAuth callback error:', error);
            // Stay on login with a visible error — never silent Welcome bounce.
            window.history.replaceState({}, document.title, '/');
            setupSessionBar(null);
            showFreshLogin();
            showScreen('login');
            setLoginStatus(
                error instanceof Error
                    ? error.message
                    : 'Sign-in failed after Allow Access. Please try again.',
                true
            );
            registerServiceWorker();
            return;
        }
    } else if (!readToken()) {
        const refreshToken = readRefreshToken();
        if (refreshToken) {
            try {
                const tokenData = await refreshAccessToken();
                const { access_token, instance_url } = tokenData;
                console.log('[OAuth] Token refresh successful');
                window.localStorage.setItem(TOKEN_KEY, access_token);
                configureRuntime(access_token, null, instance_url);
            } catch (error) {
                console.error('Token refresh error:', error);
                window.localStorage.removeItem(TOKEN_KEY);
                window.localStorage.removeItem(REFRESH_TOKEN_KEY);
                window.localStorage.removeItem(INSTANCE_URL_KEY);
                clearIdentity();
                clearSessionConfirmed();
                configureRuntime('');
                showFreshLogin();
                showScreen('login');
                setLoginStatus('Session expired. Please sign in again.', true);
            }
        }
    }

    const token = readToken();
    configureRuntime(token);
    console.log('[App] PLANNER_ACCESS_TOKEN present:', !!globalThis.PLANNER_ACCESS_TOKEN);
    setupNavigation();
    setupSessionBar(token);
    setupToastListener();

    if (token) {
        void fetchAndStoreUserIdentity();
        if (enterImmediately || oauthHandled || isSessionConfirmed()) {
            enterAuthenticatedApp();
        } else {
            showResumeSession();
            showScreen('login');
        }
    } else {
        showFreshLogin();
        showScreen('login');
        if (!oauthHandled) {
            syncLoginFormUi();
        }
    }
    registerServiceWorker();
}

initializeApp();
