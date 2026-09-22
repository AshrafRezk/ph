import { plannerApiFetch } from './restHelper.js';
import {
    getPendingActions,
    getPlannerCache,
    getUserPlannerCacheKey,
    putPlannerCache
} from 'c/clmOfflineStore';

// Must match `src/stubs/userId.js` — the planner LWC keys IndexedDB with @salesforce/user/Id.
const STUB_USER_ID = '005000000000000AAA';
const AUTO_OFFLINE_KEY = 'zeta.pwa.autoOffline';

function weekCacheKey(weekStart) {
    const start = String(weekStart || '').slice(0, 10);
    return `${getUserPlannerCacheKey(STUB_USER_ID)}_${start}`;
}

function deviceIsOffline() {
    if (typeof navigator !== 'undefined' && navigator.onLine === false) {
        return true;
    }
    try {
        return typeof localStorage !== 'undefined' && localStorage.getItem(AUTO_OFFLINE_KEY) === '1';
    } catch (_err) {
        return false;
    }
}

function parseJson(raw) {
    if (!raw) {
        return null;
    }
    if (typeof raw === 'object') {
        return raw;
    }
    try {
        return JSON.parse(raw);
    } catch (_err) {
        return null;
    }
}

function visitIdFromAction(row, payload) {
    return String(payload?.visitId || row.visitId || row.clientVisitKey || '');
}

function asVisitDto(id, payload, existing = {}) {
    return {
        ...existing,
        id,
        name: existing.name || payload.visitObjective || 'Offline visit',
        accountId: payload.accountId || existing.accountId,
        accountName: existing.accountName || 'Offline visit',
        status: payload.status || existing.status || 'Draft',
        visitType: payload.visitType || existing.visitType,
        startDateTime: payload.startDateTime || existing.startDateTime,
        endDateTime: payload.endDateTime || existing.endDateTime,
        visitObjective: payload.visitObjective || existing.visitObjective,
        zetaProjectId: payload.zetaProjectId || existing.zetaProjectId,
        cancellationReason: payload.cancellationReason || existing.cancellationReason
    };
}

/**
 * Omar's planner-preservation: keep queued Visit__c / TOT rows visible after a
 * server cache refresh, and overlay them onto the IndexedDB week snapshot.
 */
export async function mergePendingLocalVisits(payload = {}) {
    const visits = [...(payload.visits || [])];
    const timeOffBlocks = [...(payload.timeOffBlocks || payload.timeOff || [])];
    let pending = [];
    try {
        pending = await getPendingActions();
    } catch (_err) {
        pending = [];
    }
    const byId = new Map(visits.map((visit) => [String(visit.id), { ...visit }]));

    for (const row of pending) {
        const type = String(row.actionType || '');
        const body = parseJson(row.payloadJson) || {};
        if (type === 'UPSERT_VISIT') {
            const id = visitIdFromAction(row, body);
            if (!id) {
                continue;
            }
            byId.set(id, asVisitDto(id, body, byId.get(id) || {}));
        } else if (type === 'SUBMIT_VISIT') {
            const id = visitIdFromAction(row, body);
            if (!id || !byId.has(id)) {
                continue;
            }
            byId.set(id, { ...byId.get(id), status: 'Submitted' });
        } else if (type === 'RESCHEDULE_VISITS') {
            const ids = body.visitIds || [];
            const starts = body.startDateTimes || [];
            const ends = body.endDateTimes || [];
            ids.forEach((id, idx) => {
                const key = String(id);
                const existing = byId.get(key);
                if (!existing) {
                    return;
                }
                byId.set(key, {
                    ...existing,
                    startDateTime: starts[idx] || existing.startDateTime,
                    endDateTime: ends[idx] || existing.endDateTime
                });
            });
        } else if (type === 'CREATE_TIME_OFF') {
            const id = String(row.clientActionKey || row.id || '');
            if (!id || timeOffBlocks.some((block) => String(block.id) === id)) {
                continue;
            }
            const start = body.startDateTime;
            let end = start;
            if (body.spanType === 'Full_Day' && start) {
                const dayEnd = new Date(start);
                dayEnd.setHours(17, 0, 0, 0);
                end = dayEnd.toISOString();
            } else if (start) {
                const hours = Number(body.durationHours || 2);
                end = new Date(new Date(start).getTime() + hours * 3600 * 1000).toISOString();
            }
            timeOffBlocks.push({
                id,
                name: body.typeValue,
                typeLabel: body.typeValue,
                typeValue: body.typeValue,
                startDateTime: start,
                endDateTime: end,
                spanType: body.spanType,
                stage: body.stage
            });
        }
    }

    return {
        ...payload,
        visits: Array.from(byId.values()),
        timeOffBlocks,
        timeOff: timeOffBlocks
    };
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
    try {
        window.dispatchEvent(
            new CustomEvent(PLANNER_WEEK_UPDATED_EVENT, { detail: { weekStart, payload } })
        );
    } catch (_err) {
        /* ignore */
    }
}

async function fetchRemoteAndCache(params = {}) {
    const path = weekPath(params);
    const remote = await plannerApiFetch(path, { fresh: true });
    const merged = await mergePendingLocalVisits({
        visits: remote?.visits || [],
        timeOffBlocks: remote?.timeOffBlocks || remote?.timeOff || [],
        meetings: remote?.meetings || []
    });
    merged.publicHolidayDates = remote?.publicHolidayDates || [];
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
