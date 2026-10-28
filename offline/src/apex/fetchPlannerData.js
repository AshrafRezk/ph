import { plannerApiFetch } from './restHelper.js';
import { getPlannerCache, getUserPlannerCacheKey, putPlannerCache } from 'c/clmOfflineStore';
import { applyPendingOverlay } from 'c/plannerLocalQueue';

// Must match `src/stubs/userId.js` — the planner LWC keys IndexedDB with @salesforce/user/Id.
const STUB_USER_ID = '005000000000000AAA';

function weekCacheKey(weekStart) {
    const start = String(weekStart || '').slice(0, 10);
    return `${getUserPlannerCacheKey(STUB_USER_ID)}_${start}`;
}

function deviceIsOffline() {
    return typeof navigator !== 'undefined' && navigator.onLine === false;
}

/**
 * Keep queued visits, time off, and meetings visible after a server refresh,
 * including local removals that have not reached Salesforce yet.
 */
export async function mergePendingLocalVisits(payload = {}) {
    return applyPendingOverlay(payload);
}

export const PLANNER_WEEK_UPDATED_EVENT = 'zeta-planner-week-updated';

const weekRefreshInflight = new Map();

async function loadLocalWeek(params = {}) {
    const cached = params.weekStart ? await getPlannerCache(weekCacheKey(params.weekStart)) : null;
    const base = {
        visits: cached?.visits || [],
        timeOffBlocks: cached?.timeOffBlocks || [],
        meetings: cached?.meetings || [],
        publicHolidayDates: cached?.publicHolidayDates || []
    };
    const merged = await mergePendingLocalVisits(base);
    merged.publicHolidayDates = base.publicHolidayDates;
    return { cached, merged };
}

function weekPath(params = {}) {
    const query = new URLSearchParams();
    if (params.weekStart) query.set('weekStart', params.weekStart);
    if (params.weekEnd) query.set('weekEnd', params.weekEnd);
    if (params.contextUserId) query.set('contextUserId', params.contextUserId);
    const suffix = query.toString() ? `?${query.toString()}` : '';
    return `/services/apexrest/planner/v1/week${suffix}`;
}

function emitWeekUpdated(weekStart, payload) {
    const detailPayload = { ...(payload || {}) };
    if (detailPayload.meetingsFromServer !== true) {
        delete detailPayload.meetings;
    }
    delete detailPayload.meetingsFromServer;
    try {
        window.dispatchEvent(
            new CustomEvent(PLANNER_WEEK_UPDATED_EVENT, { detail: { weekStart, payload: detailPayload } })
        );
    } catch (_err) {
        /* ignore */
    }
}

async function fetchRemoteAndCache(params = {}) {
    const path = weekPath(params);
    const remote = await plannerApiFetch(path, { fresh: true });
    const previous = params.weekStart ? await getPlannerCache(weekCacheKey(params.weekStart)) : null;
    // Older week responses omitted meetings. Treating that as [] wiped the calendar
    // on every background refresh even though the meetings were still in Salesforce.
    const serverSentMeetings = Array.isArray(remote?.meetings);
    const meetings = serverSentMeetings ? remote.meetings : previous?.meetings || [];
    const merged = await mergePendingLocalVisits({
        visits: remote?.visits || [],
        timeOffBlocks: remote?.timeOffBlocks || remote?.timeOff || [],
        meetings
    });
    merged.publicHolidayDates = remote?.publicHolidayDates || [];
    merged.meetingsFromServer = serverSentMeetings;
    if (params.weekStart) {
        await putPlannerCache(weekCacheKey(params.weekStart), {
            visits: merged.visits,
            timeOffBlocks: merged.timeOffBlocks,
            meetings: merged.meetings,
            publicHolidayDates: merged.publicHolidayDates
        });
    }
    return merged;
}

function refreshWeekInBackground(params = {}) {
    const key = weekCacheKey(params.weekStart);
    if (weekRefreshInflight.has(key)) {
        return;
    }
    const pending = fetchRemoteAndCache(params)
        .then((merged) => {
            emitWeekUpdated(params.weekStart, merged);
            return merged;
        })
        .catch(() => {
            /* keep showing the local week */
        })
        .finally(() => {
            weekRefreshInflight.delete(key);
        });
    weekRefreshInflight.set(key, pending);
}

export default async function fetchPlannerData(params = {}) {
    const { cached, merged } = await loadLocalWeek(params);
    const hasLocal = Boolean(cached || merged.visits.length || merged.timeOffBlocks.length);

    if (deviceIsOffline()) {
        if (hasLocal) {
            return merged;
        }
        throw new Error('Planner data is not cached for offline use. Open planner while online first.');
    }

    if (params.fresh === true) {
        try {
            return await fetchRemoteAndCache(params);
        } catch (error) {
            if (hasLocal) {
                return merged;
            }
            throw error;
        }
    }

    if (hasLocal) {
        refreshWeekInBackground(params);
        return merged;
    }

    try {
        return await fetchRemoteAndCache(params);
    } catch (error) {
        if (hasLocal) {
            return merged;
        }
        throw error;
    }
}
