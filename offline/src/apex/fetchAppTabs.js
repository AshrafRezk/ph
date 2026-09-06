// Org apps + tabs via Salesforce UI API / REST /tabs.
// Browser traffic goes through plannerApiFetch (Netlify sf-api) so CORS cannot
// collapse the launcher to the local Pharma Field fallback.

import { plannerApiFetch } from './restHelper.js';

const APP_TABS_CACHE_KEY = 'zeta.pwa.appTabs.v5';
const APPS_CACHE_KEY = 'zeta.pwa.apps.v5';
const TABS_CACHE_KEY = 'zeta.pwa.allTabs.v5';
const DEFAULT_API_VERSION = 'v62.0';
const FORM_FACTOR = 'Large';
const HYDRATE_BATCH = 6;

// Offline-only seed when the org cannot be reached. Labels match LightningSales.
const FALLBACK_TABS = [
    { key: 'Field_Rep_Home_App', label: 'Home', type: 'TabFlexiPage', iconUrl: null },
    { key: 'Field_Rep_Planner', label: 'Planner', type: 'TabAura', iconUrl: null },
    { key: 'Accounts_Tab', label: 'Accounts', type: 'TabFlexiPage', iconUrl: null },
    { key: 'Visit__c', label: 'Visits', type: 'Entity', iconUrl: null, objectApiName: 'Visit__c' },
    { key: 'CLM_Presentations', label: 'CLM Presentations', type: 'TabFlexiPage', iconUrl: null },
    { key: 'My_Learning', label: 'My Learning', type: 'TabFlexiPage', iconUrl: null },
    { key: 'Coaching_Event__c', label: 'Coaching Events', type: 'Entity', iconUrl: null, objectApiName: 'Coaching_Event__c' },
    { key: 'Request_Time_Off', label: 'Request Time Off', type: 'TabFlexiPage', iconUrl: null }
];

export const PHARMA_APP = {
    id: null,
    developerName: 'LightningSales',
    label: 'Pharma Field',
    iconUrl: null,
    description: 'Home, planner, accounts, CLM & time off — full offline support.',
    fullOffline: true,
    tabs: FALLBACK_TABS
};

const OFFLINE_HOME_TAB = 'Field_Rep_Home_App';

function sfInstance() {
    return (
        (typeof globalThis !== 'undefined' && globalThis.PLANNER_SF_INSTANCE) ||
        (typeof localStorage !== 'undefined' && localStorage.getItem('zeta.pwa.sfInstanceUrl')) ||
        ''
    );
}

function apiToken() {
    return (
        (typeof globalThis !== 'undefined' && globalThis.PLANNER_ACCESS_TOKEN) ||
        (typeof localStorage !== 'undefined' && localStorage.getItem('zeta.pwa.sfAccessToken')) ||
        ''
    );
}

function resolveIconUrl(url) {
    if (!url || typeof url !== 'string') return null;
    const trimmed = url.trim();
    if (!trimmed) return null;
    if (/^https?:\/\//i.test(trimmed)) return trimmed;
    const base = String(sfInstance()).replace(/\/$/, '');
    if (!base) return trimmed;
    return trimmed.startsWith('/') ? `${base}${trimmed}` : `${base}/${trimmed}`;
}

function cacheWrite(key, data) {
    try {
        localStorage.setItem(key, JSON.stringify({ savedAt: Date.now(), payload: data }));
    } catch (_err) {
        /* storage full */
    }
}

function cacheRead(key) {
    try {
        const raw = localStorage.getItem(key);
        if (!raw) return null;
        const parsed = JSON.parse(raw);
        return parsed && Array.isArray(parsed.payload) && parsed.payload.length ? parsed.payload : null;
    } catch (_err) {
        return null;
    }
}

function normalizeTabs(app) {
        const navItems = (app && (
        (Array.isArray(app.navItems) && app.navItems) ||
        (Array.isArray(app.items) && app.items) ||
        (app.navigation && Array.isArray(app.navigation.navItems) && app.navigation.navItems) ||
        []
    )) || [];
    return navItems
        .filter((item) => item && item.label && (item.developerName || item.name || item.objectApiName))
        .map((item) => ({
            key: item.developerName || item.name || item.objectApiName,
            label: item.label,
            type: item.itemType || item.type || (item.objectApiName ? 'Entity' : 'TabFlexiPage'),
            iconUrl: resolveIconUrl(item.iconUrl || (item.icon && item.icon.iconUrl) || null),
            objectApiName: item.objectApiName || null
        }));
}

function mapOrgApp(app) {
    const iconUrl = resolveIconUrl(
        app.iconUrl || (app.icon && (app.icon.iconUrl || app.icon.url)) || null
    );
    return {
        id: app.id || app.durableId || app.appId || null,
        developerName: app.developerName || app.label,
        label: app.label || app.developerName,
        iconUrl,
        description: app.description || '',
        selected: app.selected === true,
        fullOffline: false,
        tabs: normalizeTabs(app)
    };
}

async function sfGet(path) {
    return plannerApiFetch(path, { method: 'GET' });
}

async function fetchAppListFromOrg() {
    const token = apiToken();
    if (!token) {
        throw new Error('Not signed in.');
    }
    const path = `/services/data/${DEFAULT_API_VERSION}/ui-api/apps?formFactor=${FORM_FACTOR}`;
    const data = await sfGet(path);
    const apps = Array.isArray(data && data.apps) ? data.apps : [];
    return apps.map(mapOrgApp);
}

async function hydrateAppNav(app) {
    const appId = app && (app.id || app.developerName);
    if (!appId) return app;
    const factors = [FORM_FACTOR, 'Small', 'Medium'];
    let detail = null;
    let tabs = [];
    for (const factor of factors) {
        try {
            const path = `/services/data/${DEFAULT_API_VERSION}/ui-api/apps/${encodeURIComponent(appId)}?formFactor=${factor}`;
            detail = await sfGet(path);
            tabs = normalizeTabs(detail);
            if (tabs.length) break;
        } catch (err) {
            console.warn('[AppTabs] hydrate', app.developerName, factor, err);
        }
    }
    if (!detail) return app;
    return {
        ...app,
        id: app.id || detail.id || detail.durableId || detail.appId || null,
        label: detail.label || app.label,
        description: app.description || detail.description || '',
        iconUrl: app.iconUrl || resolveIconUrl(detail.iconUrl || (detail.icon && detail.icon.iconUrl)),
        tabs: tabs.length ? tabs : app.tabs || []
    };
}

async function hydrateMissingNavItems(apps) {
    const list = (apps || []).slice();
    const pendingIdx = [];
    list.forEach((app, idx) => {
        if (!app.tabs || !app.tabs.length) {
            pendingIdx.push(idx);
        }
    });
    for (let i = 0; i < pendingIdx.length; i += HYDRATE_BATCH) {
        const chunk = pendingIdx.slice(i, i + HYDRATE_BATCH);
        const results = await Promise.all(
            chunk.map(async (idx) => {
                try {
                    return await hydrateAppNav(list[idx]);
                } catch (err) {
                    console.warn('[AppTabs] hydrate failed', list[idx] && list[idx].developerName, err);
                    return list[idx];
                }
            })
        );
        results.forEach((app, j) => {
            list[chunk[j]] = app;
        });
    }
    return list;
}

function fallbackByKey() {
    const map = new Map();
    FALLBACK_TABS.forEach((tab) => {
        if (tab && tab.key) map.set(tab.key, tab);
    });
    return map;
}

/**
 * Prefer the org Lightning app nav (order + membership). Only seed the full
 * FALLBACK_TABS set when the org returned no navItems (true offline).
 */
function mergeFallbackTabs(tabs) {
    const orgTabs = Array.isArray(tabs) ? tabs.filter((t) => t && t.key) : [];
    if (!orgTabs.length) {
        return FALLBACK_TABS.map((tab) => ({ ...tab }));
    }
    const local = fallbackByKey();
    return orgTabs.map((org) => {
        const seed = local.get(org.key);
        return {
            ...(seed || {}),
            ...org,
            key: org.key,
            label: org.label || (seed && seed.label) || org.key,
            type: org.type || (seed && seed.type) || 'TabFlexiPage',
            objectApiName: org.objectApiName || (seed && seed.objectApiName) || null,
            // Prefer local SVG icons over Salesforce sprite URLs in the offline shell.
            iconUrl: null
        };
    });
}

export function ensureAppTabs(app) {
    if (!app) {
        return { ...PHARMA_APP, tabs: FALLBACK_TABS.map((tab) => ({ ...tab })) };
    }
    if (!isFieldApp(app)) {
        return app;
    }
    return {
        ...app,
        fullOffline: true,
        description: app.description || PHARMA_APP.description,
        tabs: mergeFallbackTabs(app.tabs)
    };
}

function overlayTabIcons(apps, allTabs) {
    const byKey = new Map();
    (allTabs || []).forEach((tab) => {
        if (tab && tab.key) byKey.set(tab.key, tab);
    });
    return (apps || []).map((app) => ({
        ...app,
        iconUrl: app.iconUrl || null,
        tabs: (app.tabs || []).map((tab) => {
            const meta = byKey.get(tab.key);
            if (!meta) return tab;
            return {
                ...tab,
                iconUrl: tab.iconUrl || meta.iconUrl || null,
                objectApiName: tab.objectApiName || meta.objectApiName || null
            };
        })
    }));
}

function isFieldApp(app) {
    if (!app) return false;
    if (app.developerName === 'LightningSales' || app.developerName === 'PharmaField') return true;
    return (app.tabs || []).some((t) => t.key === OFFLINE_HOME_TAB);
}

function markOfflineFirst(apps) {
    const list = (apps || []).map((app) => (isFieldApp(app) ? ensureAppTabs(app) : app));
    list.sort((a, b) => (b.fullOffline === true) - (a.fullOffline === true));
    if (!list.some((a) => a.fullOffline)) {
        list.unshift(ensureAppTabs(PHARMA_APP));
    }
    return list;
}

async function fetchAppsFromOrg() {
    const apps = await fetchAppListFromOrg();
    return hydrateMissingNavItems(apps);
}

export async function fetchAppTabs({ forceRefresh = false } = {}) {
    const fromCache = cacheRead(APP_TABS_CACHE_KEY);

    if (fromCache && !forceRefresh) {
        refreshAppTabs().catch(() => {});
        return fromCache;
    }

    try {
        const tabs = await fetchAppTabsFromOrg();
        if (tabs.length) {
            cacheWrite(APP_TABS_CACHE_KEY, tabs);
            return tabs;
        }
    } catch (err) {
        console.warn('[AppTabs] fetchAppTabs failed', err);
    }

    if (fromCache) return fromCache;
    return FALLBACK_TABS;
}

async function refreshAppTabs() {
    const tabs = await fetchAppTabsFromOrg();
    if (tabs.length) {
        cacheWrite(APP_TABS_CACHE_KEY, tabs);
        return tabs;
    }
    return null;
}

async function fetchAppTabsFromOrg() {
    const apps = await fetchAppsFromOrg();
    const selected =
        apps.find((app) => app && app.selected === true) ||
        apps.find((app) => isFieldApp(app)) ||
        apps[0];
    return (selected && selected.tabs) || [];
}

/** Cached Lightning apps from the last successful org fetch (empty if never synced). */
export function readCachedApps() {
    const cached = cacheRead(APPS_CACHE_KEY);
    return cached && cached.length ? markOfflineFirst(cached) : [];
}

export async function fetchApps({ forceRefresh = false } = {}) {
    const cached = cacheRead(APPS_CACHE_KEY);
    if (cached && !forceRefresh) {
        refreshApps().catch((err) => console.warn('[AppChooser] background refresh failed', err));
        return markOfflineFirst(cached);
    }
    try {
        const apps = await fetchAppsFromOrg();
        if (apps.length) {
            let itemTabs = [];
            try {
                itemTabs = await fetchTabsFromOrg();
                if (itemTabs.length) cacheWrite(TABS_CACHE_KEY, itemTabs);
            } catch (_err) {
                /* All Items is optional for the app cards */
            }
            const merged = overlayTabIcons(apps, itemTabs);
            cacheWrite(APPS_CACHE_KEY, merged);
            console.log('[AppChooser] loaded', merged.length, 'apps from org');
            return markOfflineFirst(merged);
        }
    } catch (err) {
        console.warn('[AppChooser] fetchApps failed', err);
    }
    if (cached) return markOfflineFirst(cached);
    return [PHARMA_APP];
}

async function refreshApps() {
    const apps = await fetchAppsFromOrg();
    if (apps.length) {
        let itemTabs = cacheRead(TABS_CACHE_KEY) || [];
        try {
            const freshTabs = await fetchTabsFromOrg();
            if (freshTabs.length) {
                itemTabs = freshTabs;
                cacheWrite(TABS_CACHE_KEY, freshTabs);
            }
        } catch (_err) {
            /* keep cached items */
        }
        const merged = overlayTabIcons(apps, itemTabs);
        cacheWrite(APPS_CACHE_KEY, merged);
        const marked = markOfflineFirst(merged);
        window.dispatchEvent(new CustomEvent('zeta-apps-refreshed', { detail: { apps: marked } }));
        return marked;
    }
    return apps;
}

function isSalesforceId(v) {
    return typeof v === 'string' && v[0] === '0' && /^[0-9A-Za-z]{15}([0-9A-Za-z]{3})?$/.test(v);
}

async function fetchTabsFromOrg() {
    const token = apiToken();
    if (!token) {
        throw new Error('Not signed in.');
    }
    const data = await sfGet(`/services/data/${DEFAULT_API_VERSION}/tabs`);
    const rows = Array.isArray(data) ? data : [];
    return rows
        .filter((t) => t && t.name && t.label)
        .map((t) => {
            const isObject = t.sobjectName && !isSalesforceId(t.sobjectName);
            return {
                key: t.name,
                label: t.label,
                type: isObject ? 'Entity' : 'TabFlexiPage',
                iconUrl: resolveIconUrl(t.iconUrl || t.miniIconUrl || null),
                objectApiName: isObject ? t.sobjectName : null
            };
        })
        .sort((a, b) => (a.label || '').localeCompare(b.label || ''));
}

export async function fetchTabs({ forceRefresh = false } = {}) {
    const cached = cacheRead(TABS_CACHE_KEY);
    if (cached && !forceRefresh) {
        fetchTabsFromOrg()
            .then((tabs) => cacheWrite(TABS_CACHE_KEY, tabs))
            .catch(() => {});
        return cached;
    }
    try {
        const tabs = await fetchTabsFromOrg();
        if (tabs.length) {
            cacheWrite(TABS_CACHE_KEY, tabs);
            return tabs;
        }
    } catch (err) {
        console.warn('[AppChooser] fetchTabs failed', err);
    }
    return cached || [];
}

export { overlayTabIcons };
