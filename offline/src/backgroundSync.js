import { drainQueue, isOfflineMode } from 'c/clmOfflineSync';
import fetchPlannerData from './apex/fetchPlannerData.js';
import { plannerApiFetch } from './apex/restHelper.js';
import { fetchApps, readCachedApps } from './apex/fetchAppTabs.js';
import { drainMeetingOutbox } from './meetingOutbox.js';
import {
    runOfflineBootstrap,
    warmStaleEntityPages,
    FIELD_WARM_PATHS,
    warmPathFor,
    isBootstrapComplete
} from './offlineBootstrap.js';

const INTERVAL_MS = 3 * 60 * 1000;

let timer = null;
let listenersBound = false;
let inFlight = false;

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

function canSync() {
    if (typeof document !== 'undefined' && document.visibilityState === 'hidden') {
        return false;
    }
    if (isOfflineMode()) {
        return false;
    }
    if (typeof navigator !== 'undefined' && navigator.onLine === false) {
        return false;
    }
    const token = typeof globalThis !== 'undefined' && globalThis.PLANNER_ACCESS_TOKEN;
    return Boolean(token);
}

async function warmPlannerWeeks() {
    const origin = startOfWeek(new Date());
    const offsets = [-7, 0, 7];
    await Promise.all(
        offsets.map((offset) => {
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

async function warmRestGets() {
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
        await plannerApiFetch(`/services/data/v62.0/query?q=${encodeURIComponent(q)}`, {
            fresh: true
        });
    } catch (_err) {
        /* quiet */
    }
}

async function warmAppsNav() {
    await fetchApps({ forceRefresh: false }).catch(() => null);
}

export async function runBackgroundSync() {
    if (inFlight || !canSync()) {
        return;
    }
    inFlight = true;
    try {
        await drainQueue().catch(() => null);
        await drainMeetingOutbox();
        if (!canSync()) {
            return;
        }
        if (!isBootstrapComplete()) {
            await runOfflineBootstrap({ force: false }).catch(() => null);
            return;
        }
        await Promise.all([
            warmPlannerWeeks(),
            warmRestGets(),
            warmLearningCatalog(),
            warmAppsNav()
        ]);
        await warmStaleEntityPages(readCachedApps()).catch(() => null);
    } catch (error) {
        console.warn('[BackgroundSync] Warm failed:', error);
    } finally {
        inFlight = false;
    }
}

function onVisible() {
    if (document.visibilityState === 'visible') {
        void runBackgroundSync();
    }
}

function onOnline() {
    void runBackgroundSync();
}

export function startBackgroundSync() {
    if (!listenersBound && typeof window !== 'undefined') {
        listenersBound = true;
        document.addEventListener('visibilitychange', onVisible);
        window.addEventListener('online', onOnline);
    }
    if (timer) {
        return;
    }
    void runBackgroundSync();
    timer = window.setInterval(() => {
        void runBackgroundSync();
    }, INTERVAL_MS);
}

export function stopBackgroundSync() {
    if (timer) {
        window.clearInterval(timer);
        timer = null;
    }
}
