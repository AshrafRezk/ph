// Offline stub for FieldRepHomeController.getMonthlyTimecardDetails.
// Uses the planner REST route (cached by plannerApiFetch) and overlays visits
// that are still sitting in the local outbox.
import { makeDualApex } from './_wireAdapter.js';
import { plannerApiFetch } from './restHelper.js';
import { getPendingActions } from 'c/clmOfflineStore';

const DETAILS_PATH = '/services/apexrest/planner/v1/home/monthly-timecard/details';
const POTENTIAL_STATUSES = new Set(['Draft', 'Submitted', 'Scheduled', 'Rescheduled']);

const TITLES = {
    field: 'Field days',
    coached: 'Coached',
    coaching: 'Coaching',
    activities: 'Activities recorded',
    completed: 'Completed activities',
    potential: 'Potential activities'
};

function emptyDetail(tileId) {
    return {
        tileId,
        title: TITLES[tileId] || 'Details',
        monthLabel: 'This month',
        emptyMessage: 'Details are not available offline yet. Open this card once while online, then it stays on this device.',
        groups: []
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

function formatDay(iso) {
    const date = iso ? new Date(iso) : null;
    if (!date || Number.isNaN(date.getTime())) {
        return 'Queued offline';
    }
    return date.toLocaleDateString(undefined, { weekday: 'short', month: 'short', day: 'numeric' });
}

async function overlayPendingVisits(detail, tileId) {
    if (tileId !== 'completed' && tileId !== 'potential') {
        return detail;
    }
    let pending = [];
    try {
        pending = await getPendingActions();
    } catch (_err) {
        pending = [];
    }
    if (!Array.isArray(pending) || pending.length === 0) {
        return detail;
    }

    const next = {
        ...detail,
        groups: (detail.groups || []).map((group) => ({
            ...group,
            rows: [...(group.rows || [])]
        }))
    };
    const wantCompleted = tileId === 'completed';
    const groupKey = wantCompleted ? 'completed-visits' : 'potential-visits';
    let group = next.groups.find((item) => item.key === groupKey);
    if (!group) {
        group = {
            key: groupKey,
            label: wantCompleted ? 'Completed visits' : 'Planned visits',
            totalLabel: '',
            rows: []
        };
        next.groups = [...next.groups, group];
    }
    const seen = new Set(group.rows.map((row) => row.key));

    for (const action of pending) {
        if (action.actionType !== 'UPSERT_VISIT') {
            continue;
        }
        const payload = parsePayload(action);
        if (!payload || !isCurrentMonthIso(payload.startDateTime)) {
            continue;
        }
        const status = payload.status || 'Draft';
        const isCompleted = status === 'Completed';
        if (wantCompleted !== isCompleted) {
            continue;
        }
        if (!wantCompleted && !POTENTIAL_STATUSES.has(status)) {
            continue;
        }
        const key = action.clientVisitKey || action.clientActionKey || action.id;
        if (!key || seen.has(key)) {
            continue;
        }
        seen.add(key);
        group.rows.push({
            key,
            title: payload.accountName || 'Visit queued offline',
            subtitle: status,
            meta: formatDay(payload.startDateTime),
            recordId: payload.visitId || null,
            objectApiName: payload.visitId ? 'Visit__c' : null
        });
    }

    group.totalLabel = `${group.rows.length} planned visit${group.rows.length === 1 ? '' : 's'}`;
    if (wantCompleted) {
        group.totalLabel = `${group.rows.length} completed visit${group.rows.length === 1 ? '' : 's'}`;
    }
    next.groups = next.groups.filter((item) => (item.rows || []).length > 0);
    if (next.groups.length > 0) {
        next.emptyMessage = null;
    }
    return next;
}

function currentUserId(params) {
    if (params?.contextUserId) {
        return String(params.contextUserId);
    }
    try {
        return (
            localStorage.getItem('zeta.pwa.sfUserId') ||
            (typeof globalThis !== 'undefined' && globalThis.PLANNER_USER_ID) ||
            ''
        ).trim();
    } catch (_err) {
        return '';
    }
}

function esc(value) {
    return String(value || '').replace(/'/g, "\\'");
}

function sameId(left, right) {
    return String(left || '').slice(0, 15) === String(right || '').slice(0, 15);
}

async function soql(query) {
    const path = `/services/data/v62.0/query?q=${encodeURIComponent(query)}`;
    const result = await plannerApiFetch(path);
    return result && Array.isArray(result.records) ? result.records : [];
}

function formatSalesforceDate(value) {
    if (!value) {
        return '—';
    }
    const date = new Date(value);
    if (Number.isNaN(date.getTime())) {
        return String(value).slice(0, 10);
    }
    return date.toLocaleDateString(undefined, { weekday: 'short', month: 'short', day: 'numeric' });
}

function monthLabel() {
    return new Date().toLocaleDateString(undefined, { month: 'long', year: 'numeric' });
}

function group(key, label, rows, noun) {
    if (!rows.length) {
        return null;
    }
    const totalLabel = `${rows.length} ${noun}${rows.length === 1 ? '' : 's'}`;
    return { key, label, totalLabel, rows };
}

async function detailFromQueries(tileId, userId) {
    const detail = {
        ...emptyDetail(tileId),
        monthLabel: monthLabel(),
        emptyMessage: 'Nothing to show for this month.'
    };
    if (!userId) {
        detail.emptyMessage = 'Sign in to see the records behind this card.';
        return detail;
    }
    const user = esc(userId);
    if (tileId === 'completed' || tileId === 'potential') {
        const completed = tileId === 'completed';
        const visitStatuses = completed
            ? "Status__c = 'Completed'"
            : "Status__c IN ('Draft','Submitted','Scheduled','Rescheduled')";
        const meetingStatuses = completed
            ? "Status__c IN ('Closed','Concluded')"
            : "Status__c IN ('Draft','PendingApproval','Pending GPM Approval','Pending NLM Approval','Approved')";
        const [visits, meetings] = await Promise.all([
            soql(
                `SELECT Id, Name, Status__c, Visit_Date__c, Start_Date__c, Account__r.Name FROM Visit__c WHERE Assigned_To__c = '${user}' AND ${visitStatuses} AND Visit_Date__c = THIS_MONTH ORDER BY Visit_Date__c ASC LIMIT 200`
            ),
            soql(
                `SELECT Id, Name, Status__c, Start_Date_Time__c, RecordType.Name FROM Meeting__c WHERE OwnerId = '${user}' AND ${meetingStatuses} AND Start_Date_Time__c = THIS_MONTH ORDER BY Start_Date_Time__c ASC LIMIT 200`
            )
        ]);
        const visitRows = visits.map((visit) => ({
            key: visit.Id,
            title: visit.Account__r?.Name || visit.Name || 'Visit',
            subtitle: visit.Status__c,
            meta: formatSalesforceDate(visit.Visit_Date__c || visit.Start_Date__c),
            recordId: visit.Id,
            objectApiName: 'Visit__c'
        }));
        const meetingRows = meetings.map((meeting) => ({
            key: meeting.Id,
            title: meeting.Name || 'Meeting',
            subtitle: meeting.RecordType?.Name || meeting.Status__c,
            meta: formatSalesforceDate(meeting.Start_Date_Time__c),
            recordId: meeting.Id,
            objectApiName: 'Meeting__c'
        }));
        detail.groups = [
            group(
                completed ? 'completed-visits' : 'potential-visits',
                completed ? 'Completed visits' : 'Planned visits',
                visitRows,
                completed ? 'completed visit' : 'planned visit'
            ),
            group(
                completed ? 'completed-meetings' : 'potential-meetings',
                completed ? 'Completed meetings' : 'Open meetings',
                meetingRows,
                completed ? 'completed meeting' : 'open meeting'
            )
        ].filter(Boolean);
        return detail;
    }
    if (tileId === 'coached' || tileId === 'coaching') {
        const delivered = tileId === 'coaching';
        const events = await soql(
            `SELECT Id, Name, Status__c, Event_Start__c, Employee__c, Employee__r.Name, Manager__c, Manager__r.Name FROM Coaching_Event__c WHERE (Employee__c = '${user}' OR Manager__c = '${user}') AND Event_Start__c = THIS_MONTH AND Status__c NOT IN ('Draft','Planned','Cancelled') ORDER BY Event_Start__c ASC LIMIT 200`
        );
        const rows = events
            .filter((event) => (delivered ? sameId(event.Manager__c, userId) : sameId(event.Employee__c, userId)))
            .map((event) => ({
                key: event.Id,
                title: delivered
                    ? event.Employee__r?.Name || event.Name
                    : event.Manager__r?.Name || event.Name,
                subtitle: event.Status__c,
                meta: formatSalesforceDate(event.Event_Start__c),
                recordId: event.Id,
                objectApiName: 'Coaching_Event__c'
            }));
        const built = group(
            tileId,
            delivered ? 'Coaching delivered' : 'Coaching received',
            rows,
            'event'
        );
        detail.groups = built ? [built] : [];
        return detail;
    }
    if (tileId === 'activities' || tileId === 'field') {
        const entries = await soql(
            `SELECT Date__c, Submitted_Calls__c, Days_with_Activities__c, Calendar_Working_Days__c, TOT_Days__c FROM Employee_Time_Card_Day_Entry__c WHERE Employee_Time_Card__r.Employee__c = '${user}' AND Date__c = THIS_MONTH ORDER BY Date__c ASC LIMIT 200`
        );
        if (tileId === 'activities') {
            const active = entries.filter(
                (entry) => Number(entry.Days_with_Activities__c || 0) > 0 || Number(entry.Submitted_Calls__c || 0) > 0
            );
            const rows = active.map((entry) => {
                const visits = Number(entry.Submitted_Calls__c || 0);
                return {
                    key: `activity-${entry.Date__c}`,
                    title: formatSalesforceDate(entry.Date__c),
                    subtitle: visits === 1 ? '1 completed visit' : `${visits} completed visits`,
                    meta: null,
                    recordId: null,
                    objectApiName: null
                };
            });
            const built = group('activities', 'Days with activities', rows, 'day');
            detail.groups = built ? [built] : [];
            return detail;
        }
        const fieldRows = [];
        const excluded = [];
        for (const entry of entries) {
            const working = Number(entry.Calendar_Working_Days__c || 0) > 0;
            const leave = Number(entry.TOT_Days__c || 0) > 0;
            const row = {
                key: `field-${entry.Date__c}`,
                title: formatSalesforceDate(entry.Date__c),
                subtitle: leave ? 'Leave' : 'Field day',
                meta: null,
                recordId: null,
                objectApiName: null
            };
            if (working && !leave) {
                fieldRows.push(row);
            } else if (leave) {
                excluded.push(row);
            }
        }
        detail.groups = [
            group('field', 'Field days', fieldRows, 'day'),
            group('excluded', 'Not counted', excluded, 'day')
        ].filter(Boolean);
        return detail;
    }
    return detail;
}

async function loadMonthlyTimecardDetails(params = {}) {
    const tileId = String(params?.tileId || '').trim().toLowerCase();
    let detail = null;
    try {
        const qs = new URLSearchParams();
        if (tileId) {
            qs.set('tileId', tileId);
        }
        if (params?.contextUserId) {
            qs.set('contextUserId', params.contextUserId);
        }
        const remote = await plannerApiFetch(`${DETAILS_PATH}?${qs.toString()}`);
        if (remote && typeof remote === 'object' && remote.title) {
            detail = remote;
        }
    } catch (_err) {
        detail = null;
    }
    if (!detail) {
        try {
            detail = await detailFromQueries(tileId, currentUserId(params));
        } catch (_err) {
            detail = emptyDetail(tileId);
        }
    }
    return overlayPendingVisits(detail || emptyDetail(tileId), tileId);
}

export default makeDualApex(loadMonthlyTimecardDetails);
