// Offline stub for FieldRepHomeController.getMonthlyTimecardSummary.
// Prefers the home dashboard bundle (same round-trip as performance KPIs), then
// the dedicated REST route, then IndexedDB cache. Pending local visit actions
// overlay potential/completed counts while offline.
import { makeDualApex } from './_wireAdapter.js';
import { loadHomeDashboard } from './homeDashboard.js';
import { plannerApiFetch } from './restHelper.js';
import {
    getHomeMetricsCache,
    getPendingActions,
    getUserHomeMetricsKey,
    putHomeMetrics
} from 'c/clmOfflineStore';

const TIMECARD_PATH = '/services/apexrest/planner/v1/home/monthly-timecard';
const POTENTIAL_STATUSES = new Set(['Draft', 'Submitted', 'Scheduled', 'Rescheduled']);

function currentUserKey() {
    const userId =
        (typeof globalThis !== 'undefined' && globalThis.PLANNER_USER_ID) ||
        (typeof globalThis !== 'undefined' && globalThis.__ZETA_USER_ID__) ||
        null;
    return getUserHomeMetricsKey(userId);
}

function emptySummary() {
    return {
        fieldDays: 0,
        coachedDays: 0,
        coachingDays: 0,
        activityDays: 0,
        submittedCalls: 0,
        potentialVisits: 0,
        completedMeetings: 0,
        potentialMeetings: 0,
        completedActivities: 0,
        potentialActivities: 0,
        leaveDays: 0,
        isManager: false,
        monthLabel: 'This month'
    };
}

function normalizeSummary(raw) {
    if (!raw || typeof raw !== 'object') {
        return emptySummary();
    }
    const submittedCalls = Number(raw.submittedCalls || 0);
    const potentialVisits = Number(raw.potentialVisits || 0);
    const completedMeetings = Number(raw.completedMeetings || 0);
    const potentialMeetings = Number(raw.potentialMeetings || 0);
    return {
        ...emptySummary(),
        ...raw,
        fieldDays: Number(raw.fieldDays || 0),
        coachedDays: Number(raw.coachedDays || 0),
        coachingDays: Number(raw.coachingDays || 0),
        activityDays: Number(raw.activityDays || 0),
        submittedCalls,
        potentialVisits,
        completedMeetings,
        potentialMeetings,
        completedActivities: Number(
            raw.completedActivities != null ? raw.completedActivities : submittedCalls + completedMeetings
        ),
        potentialActivities: Number(
            raw.potentialActivities != null ? raw.potentialActivities : potentialVisits + potentialMeetings
        ),
        leaveDays: Number(raw.leaveDays || 0),
        isManager: raw.isManager === true
    };
}

function parsePayload(action) {
    if (!action?.payloadJson) {
        return null;
    }
    try {
        return JSON.parse(action.payloadJson);
    } catch (_err) {
        return null;
    }
}

function parseCallReport(action) {
    if (!action?.callReportJson) {
        return null;
    }
    try {
        return JSON.parse(action.callReportJson);
    } catch (_err) {
        return null;
    }
}

function isCurrentMonthIso(iso) {
    if (!iso) {
        return true;
    }
    const date = new Date(iso);
    if (Number.isNaN(date.getTime())) {
        return true;
    }
    const now = new Date();
    return date.getFullYear() === now.getFullYear() && date.getMonth() === now.getMonth();
}

async function overlayPendingLocalVisits(summary) {
    const next = { ...summary };
    let pending;
    try {
        pending = await getPendingActions();
    } catch (_err) {
        return next;
    }
    if (!Array.isArray(pending) || pending.length === 0) {
        return next;
    }

    let potentialDelta = 0;
    let completedDelta = 0;
    let activityDayBump = 0;
    const activityDaysSeen = new Set();

    for (const action of pending) {
        if (action.actionType === 'UPSERT_VISIT') {
            const payload = parsePayload(action);
            if (!payload || !isCurrentMonthIso(payload.startDateTime)) {
                continue;
            }
            const status = payload.status || 'Draft';
            if (status === 'Completed') {
                completedDelta += 1;
                const dayKey = String(payload.startDateTime || '').slice(0, 10);
                if (dayKey && !activityDaysSeen.has(dayKey)) {
                    activityDaysSeen.add(dayKey);
                    activityDayBump += 1;
                }
            } else if (POTENTIAL_STATUSES.has(status)) {
                potentialDelta += 1;
            }
        } else if (action.actionType === 'SAVE_CALL_REPORT') {
            const report = parseCallReport(action);
            const status = report?.status || report?.visit?.status;
            if (status === 'Completed') {
                completedDelta += 1;
                activityDayBump += 1;
            }
        }
    }

    next.potentialVisits = Math.max(0, Number(next.potentialVisits || 0) + potentialDelta);
    next.submittedCalls = Math.max(0, Number(next.submittedCalls || 0) + completedDelta);
    next.activityDays = Math.max(0, Number(next.activityDays || 0) + activityDayBump);
    next.completedActivities =
        Number(next.submittedCalls || 0) + Number(next.completedMeetings || 0);
    next.potentialActivities =
        Number(next.potentialVisits || 0) + Number(next.potentialMeetings || 0);
    return next;
}

async function cacheMonthlyTimecard(summary) {
    try {
        const key = currentUserKey();
        const existing = (await getHomeMetricsCache(key)) || {};
        await putHomeMetrics(key, {
            ...existing,
            monthlyTimecard: summary
        });
    } catch (_err) {
        /* ignore cache failures */
    }
}

async function loadFromCache() {
    try {
        const cached = await getHomeMetricsCache(currentUserKey());
        return cached?.monthlyTimecard ? normalizeSummary(cached.monthlyTimecard) : null;
    } catch (_err) {
        return null;
    }
}

async function loadMonthlyTimecardSummary(params = {}) {
    let summary = null;

    try {
        const dash = await loadHomeDashboard(params);
        if (dash?.monthlyTimecard) {
            summary = normalizeSummary(dash.monthlyTimecard);
        }
    } catch (_err) {
        /* fall through */
    }

    if (!summary) {
        try {
            const qs = params?.contextUserId
                ? `?contextUserId=${encodeURIComponent(params.contextUserId)}`
                : '';
            const remote = await plannerApiFetch(`${TIMECARD_PATH}${qs}`);
            if (remote && typeof remote === 'object') {
                summary = normalizeSummary(remote);
            }
        } catch (_err) {
            /* fall through */
        }
    }

    if (!summary) {
        summary = (await loadFromCache()) || emptySummary();
    } else {
        await cacheMonthlyTimecard(summary);
    }

    void warmTimecardDetails(params);
    return overlayPendingLocalVisits(summary);
}

const DETAIL_TILES = ['field', 'coached', 'coaching', 'activities', 'completed', 'potential'];

function warmTimecardDetails(params = {}) {
    const userQs = params?.contextUserId
        ? `&contextUserId=${encodeURIComponent(params.contextUserId)}`
        : '';
    for (const tileId of DETAIL_TILES) {
        plannerApiFetch(
            `/services/apexrest/planner/v1/home/monthly-timecard/details?tileId=${encodeURIComponent(tileId)}${userQs}`
        ).catch(() => {});
    }
    const leaveQs = params?.contextUserId
        ? `?contextUserId=${encodeURIComponent(params.contextUserId)}`
        : '';
    plannerApiFetch(`/services/apexrest/planner/v1/home/monthly-timecard/leaves${leaveQs}`).catch(() => {});
}

export default makeDualApex(loadMonthlyTimecardSummary);
