import '@lwc/synthetic-shadow';
import { createElement } from 'lwc';
import FieldRepHomeMetrics from 'c/fieldRepHomeMetrics';
import FieldRepHomeTodayPlan from 'c/fieldRepHomeTodayPlan';
import FieldRepHomeActivityPlan from 'c/fieldRepHomeActivityPlan';
import FieldRepHomeNextBestCustomer from 'c/fieldRepHomeNextBestCustomer';
import HomeOfficeMessages from 'c/homeOfficeMessages';
import StayInTheKnow from 'c/stayInTheKnow';
import FieldRepHomeClmPrefetch from 'c/fieldRepHomeClmPrefetch';
import ReportsHub from 'c/reportsHub';
import FieldRepPlanner from 'c/fieldRepPlanner';
import AccountsTab from 'c/accountsTab';
import ClassEngineTab from 'c/classEngineTab';
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
import { plannerApiFetch, isNetworkError } from './apex/restHelper';
import {
    isStaleOfflineBeyond24h,
    isStaleOnlineBeyond1h,
    hoursSinceLastOnline,
    formatHoursAgo,
    writeLastOnlineAt,
    readLastOnlineAt
} from './apex/restHelper';
import { setupToastListener, showToast } from './toastManager';
import {
    startSyncService,
    registerOfflineListener,
    hydrateOfflineMode,
    isOfflineMode,
    drainQueue
} from 'c/clmOfflineSync';
import { countPendingActions } from 'c/clmOfflineStore';
import { startBackgroundSync } from './backgroundSync';
import { fetchApps, PHARMA_APP, ensureAppTabs, readCachedApps } from './apex/fetchAppTabs';
import {
    runOfflineBootstrap,
    BOOTSTRAP_STATUS_EVENT,
    isBootstrapComplete
} from './offlineBootstrap';
import {
    initApprovalInbox,
    teardownApprovalInbox,
    closeApprovalInbox
} from './approvalNotifications';
import {
    initPushNotifications,
    registerPushNotifications,
    teardownPushNotifications
} from './pushNotifications.js';
import { mountChatterView as renderChatterView } from './views/chatterView';
import { mountReportsView as renderReportsView } from './views/reportsView';
import { mountDashboardsView as renderDashboardsView } from './views/dashboardsView';
import { mountAgentforceChat, setAgentforceChatVisible } from './agentforceChat.js';
import {
    initUserMenu,
    refreshUserChrome,
    clearUserMenuCache,
    closeUserMenu,
    paintUserAvatars
} from './userMenu';
import './slds-shim.css';
import './shell.css';

const TOKEN_KEY = 'zeta.pwa.sfAccessToken';
const REFRESH_TOKEN_KEY = 'zeta.pwa.sfRefreshToken';
const INSTANCE_URL_KEY = 'zeta.pwa.sfInstanceUrl';
const USER_NAME_KEY = 'zeta.pwa.sfUserName';
const USER_USERNAME_KEY = 'zeta.pwa.sfUserUsername';
const USER_ID_KEY = 'zeta.pwa.sfUserId';
const USER_PICTURE_KEY = 'zeta.pwa.sfUserPicture';
const USER_FIRST_NAME_KEY = 'zeta.pwa.sfUserFirstName';
const USER_LAST_NAME_KEY = 'zeta.pwa.sfUserLastName';
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

    const cap = window.Capacitor;
    if (cap) {
        try {
            if (typeof cap.isNativePlatform === 'function' && cap.isNativePlatform()) {
                return true;
            }
        } catch (_e) {
            // ignore
        }
        if (cap.isNative === true) {
            return true;
        }
        try {
            const platform = typeof cap.getPlatform === 'function' ? cap.getPlatform() : '';
            if (platform === 'android' || platform === 'ios') {
                return true;
            }
        } catch (_e) {
            // ignore
        }
    }

    const ua = navigator.userAgent || '';
    if (/android/i.test(ua) && /Capacitor/i.test(ua)) {
        return true;
    }
    if (window.CapacitorCookies || window.CapacitorHttp || window.CapacitorWebView) {
        return true;
    }

    // Bundled Capacitor Android WebView is https://localhost with no Vite port.
    const host = window.location?.hostname || '';
    const port = window.location?.port || '';
    if (host === 'localhost' && !port && /android/i.test(ua) && /(wv|WebView)/i.test(ua)) {
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
const LOGIN_ENV_KEY = 'zeta.pwa.sfLoginEnv';
const CUSTOM_DOMAIN_KEY = 'zeta.pwa.sfCustomDomain';
const REDIRECT_URI_KEY = 'zeta.pwa.sfRedirectUri';
const PKCE_VERIFIER_KEY = 'zeta.pwa.oauthPkceVerifier';
const OAUTH_STATE_KEY = 'zeta.pwa.oauthState';
const TOKEN_PROXY_PATH = '/.netlify/functions/sf-token';
const DEFAULT_PUBLIC_WEB_ORIGIN = 'https://www.salesforceoffline.com';
/** @type {'login' | 'chooser' | 'app' | null} */
let currentScreen = null;

function getPublicWebOrigin() {
    const explicit = String(import.meta.env.VITE_PUBLIC_WEB_ORIGIN || '')
        .trim()
        .replace(/\/$/, '');
    if (explicit) return explicit;
    const webRedirect = String(import.meta.env.VITE_SF_WEB_REDIRECT_URI || '').trim();
    if (webRedirect) {
        try {
            return new URL(webRedirect).origin;
        } catch {
            /* ignore */
        }
    }
    return DEFAULT_PUBLIC_WEB_ORIGIN;
}

function isBundledNativeOrigin() {
    if (typeof window === 'undefined') return false;
    const host = window.location.hostname || '';
    const port = window.location.port || '';
    return (host === 'localhost' || host === '127.0.0.1') && !port;
}

function getTokenProxyUrl() {
    const explicit = String(import.meta.env.VITE_TOKEN_PROXY_URL || '').trim();
    if (explicit) return explicit;
    // Bundled APK origin is https://localhost — a relative Netlify path
    // hits the WebView SPA (HTML 200) and surfaces as "Invalid response from token proxy".
    if (isCapacitor() || isBundledNativeOrigin()) {
        return `${getPublicWebOrigin()}${TOKEN_PROXY_PATH}`;
    }
    return TOKEN_PROXY_PATH;
}

function defaultInstanceUrl() {
    // Never bake a tenant My Domain into the PWA/APK. After OAuth, instance_url
    // lives in localStorage. Local Vite may still proxy via VITE_SF_INSTANCE_URL.
    return '';
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
    return String(window.localStorage.getItem(INSTANCE_URL_KEY) || defaultInstanceUrl()).replace(
        /\/$/,
        ''
    );
}

function hasStoredSession() {
    return !!(readToken() || readRefreshToken());
}

function readStoredIdentity() {
    return {
        name: (window.localStorage.getItem(USER_NAME_KEY) || '').trim(),
        username: (window.localStorage.getItem(USER_USERNAME_KEY) || '').trim(),
        userId: (window.localStorage.getItem(USER_ID_KEY) || '').trim(),
        picture: (window.localStorage.getItem(USER_PICTURE_KEY) || '').trim(),
        firstName: (window.localStorage.getItem(USER_FIRST_NAME_KEY) || '').trim(),
        lastName: (window.localStorage.getItem(USER_LAST_NAME_KEY) || '').trim()
    };
}

function saveIdentity({ name, username, userId, picture, firstName, lastName }) {
    if (name) window.localStorage.setItem(USER_NAME_KEY, name);
    if (username) window.localStorage.setItem(USER_USERNAME_KEY, username);
    if (userId) window.localStorage.setItem(USER_ID_KEY, userId);
    if (picture) window.localStorage.setItem(USER_PICTURE_KEY, picture);
    if (firstName) window.localStorage.setItem(USER_FIRST_NAME_KEY, firstName);
    if (lastName) window.localStorage.setItem(USER_LAST_NAME_KEY, lastName);
    paintUserAvatars();
}

function clearIdentity() {
    window.localStorage.removeItem(USER_NAME_KEY);
    window.localStorage.removeItem(USER_USERNAME_KEY);
    window.localStorage.removeItem(USER_ID_KEY);
    window.localStorage.removeItem(USER_PICTURE_KEY);
    window.localStorage.removeItem(USER_FIRST_NAME_KEY);
    window.localStorage.removeItem(USER_LAST_NAME_KEY);
    clearUserMenuCache();
}

function isSessionConfirmed() {
    try {
        if (sessionStorage.getItem(SESSION_CONFIRMED_KEY) === '1') {
            return true;
        }
        // Native APK: persist across WebView refresh even if sessionStorage is cleared.
        return localStorage.getItem(SESSION_CONFIRMED_KEY) === '1';
    } catch {
        return false;
    }
}

function confirmSession() {
    try {
        sessionStorage.setItem(SESSION_CONFIRMED_KEY, '1');
        if (isCapacitor()) {
            localStorage.setItem(SESSION_CONFIRMED_KEY, '1');
        }
    } catch {
        /* ignore */
    }
}

function clearSessionConfirmed() {
    try {
        sessionStorage.removeItem(SESSION_CONFIRMED_KEY);
        localStorage.removeItem(SESSION_CONFIRMED_KEY);
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

function isNativeInstalledApp() {
    return isCapacitor() || isBundledNativeOrigin();
}

function syncLoginDownloadsVisibility() {
    const hide = isNativeInstalledApp();
    document.documentElement.classList.toggle('osr-native', hide);
    const downloads = document.getElementById('login-downloads');
    if (!downloads) return;
    downloads.hidden = hide;
    if (hide) {
        downloads.setAttribute('hidden', '');
    } else if (!document.documentElement.classList.contains('osr-has-session')) {
        downloads.removeAttribute('hidden');
    }
}

function applyResumeUserLabels() {
    const { name, username, firstName, lastName } = readStoredIdentity();
    const composed = `${firstName || ''} ${lastName || ''}`.trim();
    const display = composed || name || username || 'Someone';
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
    if (resume) resume.hidden = true;
    if (fresh) {
        fresh.hidden = false;
        fresh.removeAttribute('hidden');
    }
    const envSelect = document.getElementById('login-env');
    if (envSelect && !window.localStorage.getItem(LOGIN_ENV_KEY)) {
        envSelect.value = 'production';
    }
    syncLoginDownloadsVisibility();
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
        const picture = String(info?.picture || '').trim();
        const firstName = String(info?.given_name || info?.first_name || '').trim();
        const lastName = String(info?.family_name || info?.last_name || '').trim();
        saveIdentity({ name, username, userId, picture, firstName, lastName });
        applyResumeUserLabels();
    } catch (error) {
        console.warn('[Auth] Could not load user identity:', error);
    }
    return readStoredIdentity();
}

function enterAuthenticatedApp() {
    const token = readToken();
    if (!token && !(readRefreshToken() || readStoredIdentity().userId)) {
        showFreshLogin();
        showScreen('login');
        setLoginStatus('Session expired. Please sign in again.', true);
        return;
    }

    const navigatorOffline = typeof navigator !== 'undefined' && navigator.onLine === false;
    if (navigatorOffline && isStaleOfflineBeyond24h()) {
        const hours = formatHoursAgo(hoursSinceLastOnline());
        showOfflineLaunchLock(
            `Connect to the internet to open the app. Last online ${hours} ago (more than 24 hours).`
        );
        return;
    }

    confirmSession();
    document.documentElement.classList.add('osr-session-confirmed');
    hideOfflineLaunchLock();
    configureRuntime(token || '');
    void refreshUserChrome();
    initApprovalInbox();
    void initPushNotifications({ isCapacitor });
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
    startBackgroundSync();
    wireBootstrapStatusChip();
    void runOfflineBootstrap({ force: !isBootstrapComplete() }).catch(() => {});
    void maybeNotifyStaleSync();
    void maybeNotifyBrickGrowth();
    void maybeNotifyClassSuggestions();
}

async function maybeNotifyBrickGrowth() {
    if (typeof navigator !== 'undefined' && navigator.onLine === false) {
        return;
    }
    try {
        const { default: getBrickGrowthAlerts } = await import('./apex/getBrickGrowthAlerts.js');
        const alerts = await getBrickGrowthAlerts({});
        if (!Array.isArray(alerts) || !alerts.length) {
            return;
        }
        const top = alerts[0];
        const doctorCount = Array.isArray(top.doctors) ? top.doctors.length : 0;
        showToast({
            title: `Brick sales up: ${top.brickName || 'Brick'}`,
            message: `${top.growthPercent || 0}% MoM. Focus on ${doctorCount} doctor(s) in this brick.`,
            variant: 'info',
            duration: 10000
        });
    } catch (error) {
        console.warn('[BrickAlerts] Unable to load brick growth alerts:', error);
    }
}

async function maybeNotifyClassSuggestions() {
    if (typeof navigator !== 'undefined' && navigator.onLine === false) {
        return;
    }
    try {
        const { default: getPendingSuggestions } = await import('./apex/getPendingSuggestions.js');
        const rows = await getPendingSuggestions({});
        if (!Array.isArray(rows) || !rows.length) {
            return;
        }
        const first = rows[0];
        showToast({
            title: 'Classification suggestions',
            message: `${rows.length} pending. Open account ratings to approve or reject (e.g. ${first.accountName || 'account'} → ${first.suggestedClass || ''}).`,
            variant: 'info',
            duration: 10000
        });
    } catch (error) {
        console.warn('[ClassSuggestions] Unable to load pending suggestions:', error);
    }
}

function showOfflineLaunchLock(message) {
    let lock = document.getElementById('offline-launch-lock');
    if (!lock) {
        lock = document.createElement('div');
        lock.id = 'offline-launch-lock';
        lock.className = 'offline-launch-lock';
        lock.innerHTML = `
            <div class="offline-launch-lock-card" role="alertdialog" aria-modal="true" aria-labelledby="offline-lock-title">
                <h2 id="offline-lock-title">Internet required</h2>
                <p class="offline-launch-lock-message"></p>
                <button type="button" class="offline-launch-lock-btn" id="offline-lock-retry">Try again</button>
            </div>
        `;
        document.body.appendChild(lock);
        lock.querySelector('#offline-lock-retry')?.addEventListener('click', () => {
            if (typeof navigator !== 'undefined' && navigator.onLine) {
                hideOfflineLaunchLock();
                enterAuthenticatedApp();
            } else {
                const msg = lock.querySelector('.offline-launch-lock-message');
                if (msg) {
                    msg.textContent =
                        'Still offline. Connect to the internet, then tap Try again.';
                }
            }
        });
    }
    const msg = lock.querySelector('.offline-launch-lock-message');
    if (msg) {
        msg.textContent = message;
    }
    lock.hidden = false;
    lock.removeAttribute('hidden');
    lock.style.display = 'flex';
    showScreen('login');
    setLoginStatus(message, true);
}

function hideOfflineLaunchLock() {
    const lock = document.getElementById('offline-launch-lock');
    if (!lock) {
        return;
    }
    lock.hidden = true;
    lock.setAttribute('hidden', '');
    lock.style.display = 'none';
}

async function maybeNotifyStaleSync() {
    const navigatorOffline = typeof navigator !== 'undefined' && navigator.onLine === false;
    if (navigatorOffline || !isStaleOnlineBeyond1h()) {
        if (!navigatorOffline && readLastOnlineAt()) {
            writeLastOnlineAt();
        }
        return;
    }
    const hours = formatHoursAgo(hoursSinceLastOnline());
    let pending = 0;
    try {
        pending = await countPendingActions();
    } catch (_err) {
        pending = 0;
    }
    const pendingPart =
        pending > 0
            ? ` ${pending} queued visit action${pending === 1 ? '' : 's'} will sync.`
            : '';
    showToast({
        title: 'Syncing visits',
        message: `Last online ${hours} ago.${pendingPart}`,
        variant: 'info',
        duration: 8000
    });
    try {
        await drainQueue();
        writeLastOnlineAt();
    } catch (error) {
        console.warn('[OfflineGate] Sync after stale reopen failed:', error);
    }
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

function looksLikeHtml(text) {
    const trimmed = String(text || '')
        .trim()
        .slice(0, 32)
        .toLowerCase();
    return trimmed.startsWith('<!doctype') || trimmed.startsWith('<html') || trimmed.startsWith('<head');
}

function tokenProxyErrorDetail(raw) {
    if (raw && typeof raw === 'object') {
        return raw.error_description || raw.errorMessage || raw.error || JSON.stringify(raw);
    }
    return String(raw || '').slice(0, 300);
}

function parseTokenProxyBody(raw, status, failLabel) {
    let json = raw;
    if (typeof raw === 'string' || raw == null) {
        const text = String(raw || '');
        if (looksLikeHtml(text)) {
            console.error('[Auth] Token proxy returned HTML instead of JSON from', getTokenProxyUrl());
            throw new Error('Invalid response from token proxy');
        }
        try {
            json = JSON.parse(text);
        } catch {
            console.error('[Auth] Non-JSON token response:', text.substring(0, 500));
            throw new Error('Invalid response from token proxy');
        }
    }
    if (!json || typeof json !== 'object') {
        throw new Error('Invalid response from token proxy');
    }
    if (status < 200 || status >= 300) {
        throw new Error(`${failLabel} (${status}): ${tokenProxyErrorDetail(json)}`);
    }
    return json;
}

async function postTokenProxy(payload, failLabel = 'Token exchange failed') {
    const url = getTokenProxyUrl();
    console.log('[Auth] Token proxy POST', url);

    if (isCapacitor()) {
        try {
            const { CapacitorHttp } = await import('@capacitor/core');
            const result = await CapacitorHttp.post({
                url,
                headers: {
                    'Content-Type': 'application/json',
                    Accept: 'application/json'
                },
                data: payload,
                connectTimeout: 30000,
                readTimeout: 30000
            });
            return parseTokenProxyBody(result.data, result.status, failLabel);
        } catch (error) {
            const message = error instanceof Error ? error.message : String(error);
            if (
                message === 'Invalid response from token proxy' ||
                message.startsWith(`${failLabel} (`)
            ) {
                throw error;
            }
            console.warn('[Auth] CapacitorHttp token proxy failed, falling back to fetch:', error);
        }
    }

    const response = await fetch(url, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json', Accept: 'application/json' },
        body: JSON.stringify(payload)
    });
    const text = await response.text();
    return parseTokenProxyBody(text, response.status, failLabel);
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

    const json = await postTokenProxy({
        tokenUrl,
        grant_type: 'authorization_code',
        client_id: clientId,
        redirect_uri: redirectUri,
        code,
        code_verifier: codeVerifier
    });
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

    return postTokenProxy(
        {
            tokenUrl,
            grant_type: 'refresh_token',
            client_id: OAUTH_CONFIG.clientId,
            refresh_token: refreshToken
        },
        'Failed to refresh token'
    );
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

function describeOAuthError(error) {
    const raw = error instanceof Error ? error.message : String(error || '');
    const lower = raw.toLowerCase();
    if (lower.includes('cross-org') || lower.includes('external client app')) {
        return 'This app can’t sign in other Salesforce companies yet. Sign-in must use a Connected App, not an External Client App.';
    }
    if (lower.includes('redirect_uri') || lower.includes('redirect uri')) {
        return 'Sign-in couldn’t return to this app. Check the Connected App callback URL and try again.';
    }
    return raw || 'Sign-in failed. Please try again.';
}

function resolveLoginUrlFromForm() {
    const envSelect = document.getElementById('login-env');
    const env = envSelect?.value || 'production';
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

function persistLoginFormChoice() {
    const envSelect = document.getElementById('login-env');
    const env = envSelect?.value || 'production';
    if (env === 'production' || env === 'sandbox' || env === 'custom') {
        window.localStorage.setItem(LOGIN_ENV_KEY, env);
    }
    const input = document.getElementById('custom-domain-input');
    const label = extractMyDomainLabel(input?.value || '');
    if (label) {
        window.localStorage.setItem(CUSTOM_DOMAIN_KEY, label);
    }
}

function restoreLoginFormChoice() {
    const envSelect = document.getElementById('login-env');
    const savedEnv = (window.localStorage.getItem(LOGIN_ENV_KEY) || '').trim();
    if (envSelect && (savedEnv === 'production' || savedEnv === 'sandbox' || savedEnv === 'custom')) {
        envSelect.value = savedEnv;
    }
    const input = document.getElementById('custom-domain-input');
    if (!input || input.value) return;
    const savedLabel = (window.localStorage.getItem(CUSTOM_DOMAIN_KEY) || '').trim();
    if (savedLabel) input.value = savedLabel;
}

async function login() {
    setLoginStatus('Opening sign-in…');
    const resolved = resolveLoginUrlFromForm();
    if (!resolved) {
        setLoginStatus('Enter your company login name.', true);
        return;
    }
    persistLoginFormChoice();

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
            describeOAuthError(error),
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
        capacitorApp.addListener('appStateChange', (state) => {
            if (state?.isActive && !isOfflineMode()) {
                startSyncService();
                startBackgroundSync();
                void registerPushNotifications();
            }
        });
    }
}

async function logout() {
    try {
        await teardownPushNotifications();
    } catch {
        /* best-effort unregister */
    }
    window.localStorage.removeItem(TOKEN_KEY);
    window.localStorage.removeItem(REFRESH_TOKEN_KEY);
    window.localStorage.removeItem(INSTANCE_URL_KEY);
    window.localStorage.removeItem(LOGIN_URL_KEY);
    window.localStorage.removeItem(LOGIN_ENV_KEY);
    clearIdentity();
    clearSessionConfirmed();
    clearLastWorkspace();
    closeUserMenu();
    closeApprovalInbox();
    teardownApprovalInbox();
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
    if (!homeRoot.querySelector('c-stay-in-the-know')) {
        homeRoot.appendChild(createElement('c-stay-in-the-know', { is: StayInTheKnow }));
    }
    if (!homeRoot.querySelector('c-field-rep-home-metrics')) {
        homeRoot.appendChild(createElement('c-field-rep-home-metrics', { is: FieldRepHomeMetrics }));
    }
    if (!homeRoot.querySelector('c-field-rep-home-today-plan')) {
        homeRoot.appendChild(createElement('c-field-rep-home-today-plan', { is: FieldRepHomeTodayPlan }));
    }
    if (!homeRoot.querySelector('c-field-rep-home-activity-plan')) {
        homeRoot.appendChild(createElement('c-field-rep-home-activity-plan', { is: FieldRepHomeActivityPlan }));
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
    let planner = plannerRoot.querySelector('c-field-rep-planner');
    if (!planner) {
        planner = createElement('c-field-rep-planner', { is: FieldRepPlanner });
        planner.hideEmbeddedAgentforce = true;
        plannerRoot.appendChild(planner);
    } else {
        planner.hideEmbeddedAgentforce = true;
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

function mountClassEngineView() {
    const root = document.getElementById('view-class-engine');
    if (!root) {
        return;
    }
    if (!root.querySelector('c-class-engine-tab')) {
        root.appendChild(createElement('c-class-engine-tab', { is: ClassEngineTab }));
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
    const stored = window.localStorage.getItem(ACTIVE_VISIT_KEY);
    if (stored) {
        return stored;
    }
    const urlVisit = new URLSearchParams(window.location.search).get('visit');
    if (urlVisit) {
        window.localStorage.setItem(ACTIVE_VISIT_KEY, urlVisit);
        return urlVisit;
    }
    const hashVisit = String(window.location.hash || '').match(/^#visit\/(.+)$/);
    if (hashVisit && hashVisit[1]) {
        const id = decodeURIComponent(hashVisit[1]);
        window.localStorage.setItem(ACTIVE_VISIT_KEY, id);
        return id;
    }
    try {
        const base = String(globalThis.PLANNER_SF_INSTANCE || '').replace(/\/$/, '');
        const token = globalThis.PLANNER_ACCESS_TOKEN || '';
        if (!base || !token || (typeof navigator !== 'undefined' && navigator.onLine === false)) {
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

// Open a specific Visit in the Visit Call Shell without a full-page redirect.
// Same panel swap as switching tabs, so it stays in-app and works offline.
function openVisitCall(recordId) {
    if (recordId) {
        window.localStorage.setItem(ACTIVE_VISIT_KEY, recordId);
    }
    closeRecordModal();
    const shell = document.getElementById('app');
    if (shell && currentTab !== VISIT_CALL_TAB_KEY) {
        shell.classList.remove('tab-dir-back');
        shell.classList.add('tab-dir-forward');
    }
    switchTab(VISIT_CALL_TAB_KEY);
    const root = document.getElementById('view-visitcall');
    const el = root && root.querySelector('c-visit-call-shell');
    if (el && recordId) {
        el.recordId = recordId;
    }
    document.querySelectorAll('#app-tabs .nav-tab').forEach((btn) => {
        const active = btn.dataset.tab === 'Visit__c' || btn.dataset.tab === VISIT_CALL_TAB_KEY;
        btn.classList.toggle('nav-tab-active', active);
        btn.setAttribute('aria-selected', active ? 'true' : 'false');
    });
}

function visitIdFromHref(href) {
    if (!href) {
        return null;
    }
    try {
        const url = new URL(href, window.location.href);
        const fromQuery = url.searchParams.get('visit');
        if (fromQuery) {
            return fromQuery;
        }
        const hash = String(url.hash || '');
        const hashMatch = hash.match(/^#visit\/(.+)$/);
        if (hashMatch) {
            return decodeURIComponent(hashMatch[1]);
        }
    } catch (_err) {
        /* ignore */
    }
    return null;
}

function isVisitObjectName(objectApiName) {
    const obj = String(objectApiName || '');
    return obj === 'Visit__c' || obj === 'Visit';
}

function handleRecordNavigation(recordId, objectApiName) {
    if (!recordId) return;
    if (isVisitObjectName(objectApiName)) {
        openVisitCall(recordId);
        return;
    }
    if (/^report$/i.test(String(objectApiName || '')) || /^dashboard$/i.test(String(objectApiName || ''))) {
        openAnalyticsRecord(recordId, objectApiName);
        return;
    }
    openRecordModal(recordId, objectApiName);
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
    const panelId = isReport ? 'view-reports' : 'view-dashboards';
    const root = document.getElementById(panelId);
    activatePanel(panelId);
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
        return;
    }
    if (data.type === 'osr-record-title' && data.title) {
        const title = document.querySelector('.record-modal-chrome-title');
        if (title) title.textContent = data.title;
    }
});

const APP_TAB_VIEWS = {
    Field_Rep_Home_App: { panel: 'view-home', mount: mountHomeView },
    Field_Rep_Planner: { panel: 'view-planner', mount: mountPlannerView },
    Accounts_Tab: { panel: 'view-accounts', mount: mountAccountsView },
    Class_Engine: { panel: 'view-class-engine', mount: mountClassEngineView },
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

function tabOrderIndex(tabKey) {
    return appTabs.findIndex((item) => item.key === tabKey);
}

function activatePanel(panelId) {
    document.querySelectorAll('.view-panel').forEach((panel) => {
        const on = panel.id === panelId;
        panel.classList.toggle('active', on);
        panel.toggleAttribute('inert', !on);
        panel.setAttribute('aria-hidden', on ? 'false' : 'true');
    });
}

let primaryTabsWarmed = false;

function warmupPrimaryTabs() {
    if (primaryTabsWarmed) {
        return;
    }
    primaryTabsWarmed = true;
    const mountNow = () => {
        ['Field_Rep_Home_App', 'Field_Rep_Planner', 'Accounts_Tab'].forEach((key) => {
            const view = APP_TAB_VIEWS[key];
            if (view) {
                view.mount();
            }
        });
        const mountLater = () => {
            const learning = APP_TAB_VIEWS.My_Learning;
            if (learning) {
                learning.mount();
            }
        };
        if (typeof window.requestIdleCallback === 'function') {
            window.requestIdleCallback(mountLater, { timeout: 1200 });
        } else {
            window.setTimeout(mountLater, 200);
        }
    };
    window.requestAnimationFrame(mountNow);
}

function switchTab(tab) {
    if (!tab) return;
    const previousTab = currentTab;
    currentTab = tab;
    if (currentOpenApp) persistOpenWorkspace();

    const fromIdx = tabOrderIndex(previousTab);
    const toIdx = tabOrderIndex(tab);
    const shell = document.getElementById('app');
    if (shell && fromIdx >= 0 && toIdx >= 0 && fromIdx !== toIdx) {
        shell.classList.toggle('tab-dir-back', toIdx < fromIdx);
        shell.classList.toggle('tab-dir-forward', toIdx > fromIdx);
    }

    document.querySelectorAll('#app-tabs .nav-tab').forEach((btn) => {
        const active = btn.dataset.tab === tab;
        btn.classList.toggle('nav-tab-active', active);
        btn.setAttribute('aria-selected', active ? 'true' : 'false');
    });

    const view = APP_TAB_VIEWS[tab];
    if (view) {
        view.mount();
        activatePanel(view.panel);
        warmupPrimaryTabs();
        syncAgentforceFab(true);
        return;
    }

    if (isEntityTab(tab)) {
        mountListView();
        activatePanel('view-entity');
        syncAgentforceFab(true);
        return;
    }

    showUnsupportedTab(tab);
    syncAgentforceFab(true);
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
    activatePanel('view-unsupported');
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
    primaryTabsWarmed = false;
}

function registerServiceWorker() {
    if (!('serviceWorker' in navigator)) {
        return;
    }
    // Capacitor APK already ships the shell in the package. A service worker
    // cache-first layer is what blanked the WebView after a refresh.
    if (isCapacitor()) {
        navigator.serviceWorker
            .getRegistrations()
            .then((regs) => regs.forEach((reg) => reg.unregister()))
            .catch(() => {});
        return;
    }
    const register = () => {
        navigator.serviceWorker.register('/sw.js').catch((error) => {
            console.warn('Service worker registration failed', error);
        });
    };
    if (document.readyState === 'complete') {
        register();
    } else {
        window.addEventListener('load', register, { once: true });
    }
}

function syncAgentforceFab(appVisible) {
    setAgentforceChatVisible(Boolean(appVisible));
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
    syncAgentforceFab(name === 'app');
    if (name === 'app') {
        mountAgentforceChat({
            openPlanner: () => switchTab('Field_Rep_Planner')
        });
    }

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

// Salesforce-style App Launcher: apps only. Paint cached org apps immediately
// (no Salesforce OSR seed flash). Refresh quietly in the background.
let chooserApps = [];
let chooserSearchWired = false;
let bootstrapChipWired = false;

function wireBootstrapStatusChip() {
    if (bootstrapChipWired) return;
    bootstrapChipWired = true;
    let chip = document.getElementById('bootstrap-status-chip');
    if (!chip) {
        chip = document.createElement('div');
        chip.id = 'bootstrap-status-chip';
        chip.className = 'bootstrap-status-chip';
        chip.hidden = true;
        chip.setAttribute('role', 'status');
        document.body.appendChild(chip);
    }
    window.addEventListener(BOOTSTRAP_STATUS_EVENT, (event) => {
        const detail = (event && event.detail) || {};
        if (detail.phase === 'done' || detail.phase === 'error' || detail.phase === 'skipped') {
            chip.hidden = true;
            chip.textContent = '';
            return;
        }
        if (detail.phase === 'entities' && detail.total) {
            chip.hidden = false;
            chip.textContent = `Preparing offline data… ${detail.done || 0}/${detail.total}`;
            return;
        }
        if (detail.phase === 'start' || detail.phase === 'apps' || detail.phase === 'field' || detail.phase === 'entities') {
            chip.hidden = false;
            chip.textContent = 'Preparing offline data…';
        }
    });
}

function buildAppChooser() {
    showScreen('chooser');
    const grid = document.getElementById('app-chooser-grid');
    if (!grid) return;

    const cached = readCachedApps();
    if (cached.length) {
        chooserApps = cached;
        renderChooser();
    } else {
        chooserApps = [];
        grid.innerHTML = '<p class="chooser-loading">Loading apps…</p>';
    }
    wireChooserSearch();
    loadOrgAppsIntoChooser();
}

function seedChooserFromCache() {
    const cached = readCachedApps();
    if (!cached.length) return;
    chooserApps = cached;
}

function loadOrgAppsIntoChooser() {
    // Always cache-first; forceRefresh only when we have nothing to paint.
    const forceRefresh = !readCachedApps().length;
    fetchApps({ forceRefresh })
        .then((apps) => {
            if (apps && apps.length) {
                chooserApps = apps;
                applyChooserUpdate();
            } else if (!chooserApps.length) {
                chooserApps = [ensureAppTabs(PHARMA_APP)];
                applyChooserUpdate();
            }
        })
        .catch((error) => {
            console.warn('[AppChooser] Failed to load org apps:', error);
            if (!chooserApps.length) {
                chooserApps = [ensureAppTabs(PHARMA_APP)];
                applyChooserUpdate();
            }
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
        card.className = 'chooser-card';
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
        card.addEventListener('click', () => openApp(app));
        grid.appendChild(card);
    });
}

const FIELD_ITEM_ALIASES = {
    Account: 'Accounts_Tab',
    'standard-Account': 'Accounts_Tab',
    standard_Account: 'Accounts_Tab'
};

// Keep the Salesforce logo in the top-left; never replace it with app text.
function setNavBrand(label) {
    document.title = 'Salesforce OSR';
    const brandEl = document.getElementById('nav-title');
    if (!brandEl) return;
    const title = label ? `${label} · Salesforce OSR` : 'Salesforce OSR';
    brandEl.setAttribute('title', title);
    brandEl.setAttribute('alt', 'Salesforce');
}

// Open a single object/tab directly (used when navigating to an entity from
// elsewhere). Prefers the Field app when the tab lives there.
function openItem(item) {
    if (!item || !item.key) return;
    const fieldApp = ensureAppTabs(
        chooserApps.find((app) => isFieldAppChooser(app)) ||
            chooserApps.find((app) => app.fullOffline) ||
            PHARMA_APP
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
    setNavBrand();
    renderTabButtons(tabs);
    currentTab = item.key;
    showScreen('app');
    switchTab(item.key);
}

function isFieldAppChooser(app) {
    if (!app) return false;
    if (app.developerName === 'LightningSales' || app.developerName === 'PharmaField') return true;
    return (app.tabs || []).some((t) => t.key === HOME_TAB_KEY);
}

// Open the chosen app: load its tabs, render the sidebar, show the app screen.
function openApp(app, options = {}) {
    const resolved = ensureAppTabs(app);
    currentOpenApp = resolved;
    pendingRestore = null;
    const tabs = resolved && Array.isArray(resolved.tabs) ? resolved.tabs.slice() : [];
    appTabs = tabs;
    setNavBrand(resolved && resolved.label);
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
    const hashVisit = visitIdFromHref(window.location.href);
    const resumeVisitId =
        visitFromUrl ||
        hashVisit ||
        (options.preferredTab === VISIT_CALL_TAB_KEY ? window.localStorage.getItem(ACTIVE_VISIT_KEY) : null);
    if (resumeVisitId && (resolved.fullOffline || isFieldAppChooser(resolved))) {
        openVisitCall(resumeVisitId);
    }
}

function showEmptyApp(app) {
    const panel = document.getElementById('view-unsupported');
    if (!panel) return;
    activatePanel('view-unsupported');
    const label = (app && app.label) || 'This app';
    panel.innerHTML = `
        <div class="unsupported-message">
            <h2>${label}</h2>
            <p>No offline-available tabs for this app yet. Open another app from the launcher, or open this app in Salesforce.</p>
        </div>
    `;
}

function syncOpenAppFromOrg() {
    if (currentScreen !== 'app' || !currentOpenApp) return;
    const key = currentOpenApp.developerName;
    const fresh =
        chooserApps.find((a) => a.developerName === key) ||
        chooserApps.find((a) => isFieldAppChooser(a));
    if (!fresh || !Array.isArray(fresh.tabs) || !fresh.tabs.length) return;

    const sameTabs =
        fresh.tabs.length === appTabs.length &&
        fresh.tabs.every((tab, i) => tab.key === appTabs[i].key && tab.label === appTabs[i].label && tab.iconUrl === appTabs[i].iconUrl);
    if (sameTabs) return;

    currentOpenApp = fresh;
    appTabs = fresh.tabs.slice();
    setNavBrand(fresh.label);
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
    if (exact === 'Class_Engine' || key.includes('class_engine') || key.includes('class-engine')) {
        return `<svg class="nav-icon" viewBox="0 0 24 24" fill="currentColor" aria-hidden="true"><path d="M3 5h18v2H3V5zm2 4h14v2H5V9zm-2 4h18v2H3v-2zm2 4h14v2H5v-2z"/></svg>`;
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
    document.addEventListener(
        'click',
        (event) => {
            const anchor = event.target && event.target.closest && event.target.closest('a[href]');
            if (!anchor) {
                return;
            }
            const visitId = visitIdFromHref(anchor.getAttribute('href'));
            if (!visitId) {
                return;
            }
            event.preventDefault();
            event.stopPropagation();
            openVisitCall(visitId);
        },
        true
    );
    window.addEventListener('hashchange', () => {
        const visitId = visitIdFromHref(window.location.href);
        if (visitId) {
            openVisitCall(visitId);
        }
    });
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

    void (async () => {
        try {
            const { plannerApiFetch } = await import('./apex/restHelper.js');
            const soql = `SELECT Id, Name FROM Account WHERE Id = '${String(recordId).replace(/'/g, "\\'")}' LIMIT 1`;
            const data = await plannerApiFetch(
                `/services/data/v62.0/query?q=${encodeURIComponent(soql)}`
            );
            const name = data?.records?.[0]?.Name;
            if (name && title) {
                title.textContent = name;
            }
        } catch (_err) {
            // keep generic title
        }
    })();

    const stageHost = document.createElement('div');
    stageHost.className = 'account-record-stage';
    stageHost.hidden = true;
    host.appendChild(stageHost);
    try {
        const stage = createElement('c-account-stage-assistant', { is: AccountStageAssistant });
        stage.recordId = recordId;
        stageHost.appendChild(stage);
        // Reveal once the stage assistant paints a view (avoids empty white band).
        const reveal = () => {
            const hasContent = Boolean(stageHost.querySelector('.slds-path, .stage-view, [data-stage-ready]'));
            const text = (stageHost.textContent || '').trim();
            if (hasContent || text.length > 8) {
                stageHost.hidden = false;
            }
        };
        window.setTimeout(reveal, 400);
        window.setTimeout(reveal, 1200);
        window.setTimeout(() => {
            if (stageHost.hidden && !(stageHost.textContent || '').trim()) {
                stageHost.remove();
            } else {
                reveal();
            }
        }, 2500);
    } catch (err) {
        stageHost.remove();
        console.warn('[Account] stage assistant mount failed', err);
    }

    const tabDefs = [
        { id: 'details', label: 'Overview' },
        { id: 'affiliations', label: 'Affiliations' },
        { id: 'apm', label: 'APM' },
        { id: 'ratings', label: 'Ratings' },
        { id: 'insights', label: 'Visits' }
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
            pane.appendChild(el);
            el.recordId = recordId;
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
        if (id === 'affiliations') {
            window.requestAnimationFrame(() => {
                window.dispatchEvent(new Event('resize'));
                const network = panes.affiliations.querySelector('c-account-affiliation-network');
                if (network && typeof network.redrawNetwork === 'function') {
                    network.redrawNetwork();
                }
            });
        }
        if (id === 'apm') {
            const apm = panes.apm.querySelector('c-account-hcp-product-roi');
            if (apm && typeof apm.handleRefresh === 'function') {
                apm.handleRefresh();
            }
        }
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
    const envSelect = document.getElementById('login-env');
    const domainInput = document.getElementById('custom-domain-input');
    const continueBtn = document.getElementById('continue-session-btn');
    const switchUserBtn = document.getElementById('switch-user-btn');

    initUserMenu({
        onSwitchApp: buildAppChooser,
        onLogout: logout,
        getIdentity: readStoredIdentity,
        saveIdentity
    });

    restoreLoginFormChoice();
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

function publicApkFileName(fileName, version) {
    const cleaned = String(fileName || '')
        .replace(/-debug(?=\.apk$)/i, '')
        .replace(/-debug/gi, '')
        .trim();
    if (cleaned) {
        return cleaned;
    }
    const ver = String(version || '').replace(/^v/i, '').trim();
    return ver ? `OSR-${ver}.apk` : '';
}

async function setupLoginDownloads() {
    syncLoginDownloadsVisibility();
    if (isNativeInstalledApp()) {
        return;
    }

    const androidMeta = document.getElementById('android-download-meta');
    const androidLink = document.getElementById('android-download');
    const iosBtn = document.getElementById('ios-install-btn');
    const iosHint = document.getElementById('ios-install-hint');

    if (androidMeta) {
        try {
            const res = await fetch('/downloads/apk-latest.json', { cache: 'no-store' });
            if (res.ok) {
                const meta = await res.json();
                const version = String(meta?.version || '').replace(/^v/i, '');
                if (version) {
                    const file = publicApkFileName(meta?.fileName, version);
                    androidMeta.textContent = file ? `v${version} - ${file}` : `v${version}`;
                    if (androidLink && file) {
                        androidLink.setAttribute('download', file);
                    }
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
            iosHint.textContent = 'Installed. Open Salesforce OSR from your home screen anytime.';
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
                            ? 'Installing… Look for Salesforce OSR on your home screen.'
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
                ? 'On iPhone/iPad: tap Share, then Add to Home Screen to install Salesforce OSR.'
                : 'In your browser menu, choose Install app or Add to Home Screen to install Salesforce OSR.';
        }
    });
}

async function readNativeAppVersion() {
    if (!isCapacitor()) {
        return '';
    }
    try {
        if (!capacitorApp) {
            await initCapacitorPlugins();
        }
        if (capacitorApp?.getInfo) {
            const info = await capacitorApp.getInfo();
            if (info?.version) {
                return String(info.version);
            }
        }
    } catch (_e) {
        // Fall through to the last native stamp, if any.
    }
    try {
        return localStorage.getItem(APP_VERSION_KEY) || '';
    } catch (_e) {
        return '';
    }
}

async function stampOfflineRuntimeVersion() {
    document.documentElement.classList.add('osr-offline-shell');
    const capacitor = isCapacitor();
    // Only the APK's native versionName counts as "installed". Never stamp
    // hosted apk-latest.json here — that would hide updates and also make a
    // browser session look like the Android app is already installed.
    let version = '';
    if (capacitor) {
        version = await readNativeAppVersion();
        if (version) {
            try {
                localStorage.setItem(APP_VERSION_KEY, version);
            } catch (_e) {
                // ignore
            }
        }
    } else {
        try {
            localStorage.removeItem(APP_VERSION_KEY);
        } catch (_e) {
            // ignore
        }
    }
    window.__OSR_RUNTIME__ = {
        shell: 'offline',
        version,
        capacitor
    };
}

async function initializeApp(options = {}) {
    console.log('[App] Initializing...');
    console.log('[App] User Agent:', navigator.userAgent);
    console.log('[App] Initial window.Capacitor:', typeof window.Capacitor);

    document.documentElement.classList.add('osr-offline-shell');
    hydrateOfflineMode();

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
    syncLoginDownloadsVisibility();
    console.log('[App] tokenProxy:', getTokenProxyUrl());
    console.log('[App] callbackUrl:', OAUTH_CONFIG.callbackUrl);
    console.log('[App] stored redirectUri:', OAUTH_CONFIG.redirectUri);
    console.log('[App] stored loginUrl:', OAUTH_CONFIG.loginUrl);

    await initCapacitorListener();
    await stampOfflineRuntimeVersion();
    console.log('[App] runtime:', window.__OSR_RUNTIME__);

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
                describeOAuthError(error),
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
                const { access_token, refresh_token, instance_url } = tokenData;
                console.log('[OAuth] Token refresh successful');
                window.localStorage.setItem(TOKEN_KEY, access_token);
                configureRuntime(access_token, refresh_token || null, instance_url);
            } catch (error) {
                console.error('Token refresh error:', error);
                if (isNetworkError(error)) {
                    hydrateOfflineMode();
                    configureRuntime(readToken() || '');
                } else {
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
    } else if ((readRefreshToken() || readStoredIdentity().userId) && (isSessionConfirmed() || enterImmediately || isOfflineMode())) {
        if (enterImmediately || isSessionConfirmed() || isOfflineMode()) {
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
