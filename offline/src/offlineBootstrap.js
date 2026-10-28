/**
 * First-login (and periodic) offline bootstrap: persist apps, Field REST, and
 * first page of each Entity object so reopen paints from IndexedDB.
 */
import { plannerApiFetch } from './apex/restHelper.js';
import { territoryScopeKey } from './apex/_territoryScope.js';
import { loadTeamLearning } from './apex/getTeamLearning.js';
import { fetchApps, readCachedApps } from './apex/fetchAppTabs.js';
import fetchPlannerData from './apex/fetchPlannerData.js';
import {
    PAGE_SIZE,
    collectEntityObjects,
    putEntityDescribe,
    putEntityListPage,
    putEntityListViews,
    getEntityListPage
} from './views/entityCache.js';

export const BOOTSTRAP_FLAG_KEY = 'zeta.pwa.bootstrap.v1';
export const BOOTSTRAP_STATUS_EVENT = 'zeta-bootstrap-status';

const API_VERSION = 'v62.0';
const FIELD_WARM_PATHS = [
    '/services/apexrest/planner/v1/accounts/record-types',
    '/services/apexrest/planner/v1/accounts/filters',
    '/services/apexrest/planner/v1/accounts/map',
    '/services/apexrest/planner/v1/home/dashboard',
    '/services/apexrest/planner/v1/home/monthly-timecard',
    '/services/apexrest/planner/v1/home/next-best-customers?limitSize=20',
    '/services/apexrest/planner/v1/projects'
];

const ENTITY_BATCH = 3;
let bootstrapInFlight = null;

function emitStatus(detail) {
    try {
        window.dispatchEvent(new CustomEvent(BOOTSTRAP_STATUS_EVENT, { detail }));
    } catch (_err) {
        /* ignore */
    }
}

export function isBootstrapComplete() {
    try {
        return localStorage.getItem(BOOTSTRAP_FLAG_KEY) === '1';
    } catch (_err) {
        return false;
    }
}

export function markBootstrapComplete() {
    try {
        localStorage.setItem(BOOTSTRAP_FLAG_KEY, '1');
        localStorage.setItem(`${BOOTSTRAP_FLAG_KEY}.at`, new Date().toISOString());
    } catch (_err) {
        /* ignore */
    }
}

function canRun() {
    if (typeof navigator !== 'undefined' && navigator.onLine === false) {
        return false;
    }
    try {
        if (localStorage.getItem('zeta.pwa.autoOffline') === '1') {
            localStorage.removeItem('zeta.pwa.autoOffline');
        }
    } catch (_err) {
        /* ignore */
    }
    const token = typeof globalThis !== 'undefined' && globalThis.PLANNER_ACCESS_TOKEN;
    return Boolean(token);
}

function startOfWeek(date) {
    const d = new Date(date);
    const daysFromSaturday = (d.getDay() + 1) % 7;
    d.setDate(d.getDate() - daysFromSaturday);
    d.setHours(0, 0, 0, 0);
    return d;
}

function addDays(date, days) {
    const d = new Date(date);
    d.setDate(d.getDate() + days);
    return d;
}

function toApexDate(date) {
    const pad = (n) => String(n).padStart(2, '0');
    return `${date.getFullYear()}-${pad(date.getMonth() + 1)}-${pad(date.getDate())}`;
}

async function warmPlannerWeeks() {
    const origin = startOfWeek(new Date());
    await Promise.all(
        [-7, 0, 7].map((offset) => {
            const weekStart = addDays(origin, offset);
            const weekEnd = addDays(weekStart, 6);
            return fetchPlannerData({
                weekStart: toApexDate(weekStart),
                weekEnd: toApexDate(weekEnd),
                fresh: true
            }).catch(() => null);
        })
    );
}

// Home reads the dashboard with a per-territory key (apex/homeDashboard.js), so warm that same key.
function warmPathFor(path) {
    if (path === '/services/apexrest/planner/v1/home/dashboard') {
        return `${path}?territoryScope=${encodeURIComponent(territoryScopeKey())}`;
    }
    return path;
}

async function warmFieldRest() {
    await Promise.all(
        FIELD_WARM_PATHS.map((path) => plannerApiFetch(warmPathFor(path), { fresh: true }).catch(() => null))
    );
}

async function warmLearningCatalog() {
    try {
        const userId = (localStorage.getItem('zeta.pwa.sfUserId') || '').trim();
        if (!userId) return;
        const q =
            'SELECT Id, Status__c, Progress__c, Material__c, Material__r.Title__c, ' +
            'Material__r.Description__c, Material__r.Issue_Certificate__c ' +
            'FROM Learning_Material_Instance__c ' +
            `WHERE Learner__c = '${userId.replace(/'/g, "\\'")}' AND Material__r.Material_Type__c = 'Course' ` +
            'ORDER BY Material__r.Title__c';
        await plannerApiFetch(
            `/services/data/${API_VERSION}/query?q=${encodeURIComponent(q)}`,
            { fresh: true }
        );
        await loadTeamLearning();
    } catch (_err) {
        /* quiet */
    }
}

function pickTitleField(describe) {
    const named = (describe.fields || []).find((field) => field.nameField);
    if (named) return named.name;
    if ((describe.fields || []).some((f) => f.name === 'Name')) return 'Name';
    return 'Id';
}

function pickDisplayFields(describe) {
    const title = pickTitleField(describe);
    const extras = ['Type', 'Status', 'StageName', 'Rating', 'Industry', 'CreatedDate', 'LastModifiedDate'];
    const fields = [title];
    extras.forEach((name) => {
        if (name !== title && (describe.fields || []).some((f) => f.name === name) && !fields.includes(name)) {
            fields.push(name);
        }
    });
    return fields;
}

async function warmEntityObject(objectApiName) {
    if (!objectApiName) return;
    const existing = await getEntityListPage(objectApiName, null);
    if (existing && Array.isArray(existing.records) && existing.records.length) {
        return;
    }
    try {
        const describe = await plannerApiFetch(
            `/services/data/${API_VERSION}/sobjects/${encodeURIComponent(objectApiName)}/describe`,
            { fresh: true }
        );
        await putEntityDescribe(objectApiName, describe);

        let listViews = [];
        try {
            const lv = await plannerApiFetch(
                `/services/data/${API_VERSION}/sobjects/${encodeURIComponent(objectApiName)}/listviews`,
                { fresh: true }
            );
            listViews = Array.isArray(lv?.listviews) ? lv.listviews : Array.isArray(lv) ? lv : [];
            await putEntityListViews(objectApiName, listViews);
        } catch (_err) {
            /* optional */
        }

        const displayFields = pickDisplayFields(describe || { fields: [] });
        const selectFields = ['Id', ...displayFields.filter((f) => f && f !== 'Id')];
        const unique = [...new Set(selectFields)];
        const soql = `SELECT ${unique.join(', ')} FROM ${objectApiName} LIMIT ${PAGE_SIZE}`;
        const data = await plannerApiFetch(
            `/services/data/${API_VERSION}/query?q=${encodeURIComponent(soql)}`,
            { fresh: true }
        );
        const records = Array.isArray(data?.records) ? data.records : [];
        await putEntityListPage(objectApiName, null, {
            objectApiName,
            listViewId: null,
            fields: displayFields,
            records,
            nextRecordsUrl: data?.nextRecordsUrl || null,
            totalSize: data?.totalSize != null ? data.totalSize : records.length,
            savedAt: Date.now()
        });
    } catch (err) {
        console.warn('[Bootstrap] entity warm failed', objectApiName, err);
    }
}

async function warmEntityObjects(apps) {
    const objects = collectEntityObjects(apps);
    for (let i = 0; i < objects.length; i += ENTITY_BATCH) {
        const chunk = objects.slice(i, i + ENTITY_BATCH);
        await Promise.all(chunk.map((obj) => warmEntityObject(obj)));
        emitStatus({
            phase: 'entities',
            done: Math.min(i + chunk.length, objects.length),
            total: objects.length
        });
    }
    return objects.length;
}

/**
 * Full first-login bootstrap. Safe to call repeatedly; skips when already complete
 * unless `force` is true. Never throws to callers — failures stay quiet.
 */
export async function runOfflineBootstrap({ force = false } = {}) {
    if (!force && isBootstrapComplete()) {
        return { skipped: true };
    }
    if (!canRun()) {
        return { skipped: true, reason: 'offline' };
    }
    if (bootstrapInFlight) {
        return bootstrapInFlight;
    }

    bootstrapInFlight = (async () => {
        emitStatus({ phase: 'start' });
        try {
            emitStatus({ phase: 'apps' });
            const apps = await fetchApps({ forceRefresh: true }).catch(() => readCachedApps());

            emitStatus({ phase: 'field' });
            await Promise.all([warmPlannerWeeks(), warmFieldRest(), warmLearningCatalog()]);

            emitStatus({ phase: 'entities', done: 0, total: 0 });
            const entityCount = await warmEntityObjects(apps && apps.length ? apps : readCachedApps());

            markBootstrapComplete();
            emitStatus({ phase: 'done', entityCount });
            return { ok: true, entityCount };
        } catch (error) {
            console.warn('[Bootstrap] failed:', error);
            emitStatus({ phase: 'error' });
            return { ok: false, error };
        } finally {
            bootstrapInFlight = null;
        }
    })();

    return bootstrapInFlight;
}

/**
 * Quiet refresh of Field paths + any missing entity first pages (used by background sync).
 */
export async function warmStaleEntityPages(apps) {
    if (!canRun()) return;
    const list = apps && apps.length ? apps : readCachedApps();
    const objects = collectEntityObjects(list);
    for (let i = 0; i < objects.length; i += ENTITY_BATCH) {
        const chunk = objects.slice(i, i + ENTITY_BATCH);
        await Promise.all(
            chunk.map(async (obj) => {
                const page = await getEntityListPage(obj, null);
                if (!page || !Array.isArray(page.records) || !page.records.length) {
                    await warmEntityObject(obj);
                }
            })
        );
    }
}

export { FIELD_WARM_PATHS, warmPathFor };
