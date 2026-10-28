// Offline stub for FieldRepHomeController.getMonthlyLeaveDetails.
import { makeDualApex } from './_wireAdapter.js';
import { plannerApiFetch } from './restHelper.js';

const LEAVES_PATH = '/services/apexrest/planner/v1/home/monthly-timecard/leaves';

function emptyLeaves() {
    return {
        approvedDays: 0,
        pendingDays: 0,
        approvedRows: [],
        pendingRows: [],
        monthLabel: 'This month'
    };
}

function currentUserId(params) {
    if (params?.contextUserId) {
        return String(params.contextUserId);
    }
    try {
        return (localStorage.getItem('zeta.pwa.sfUserId') || '').trim();
    } catch (_err) {
        return '';
    }
}

function esc(value) {
    return String(value || '').replace(/'/g, "\\'");
}

const LEAVE_TYPES = new Set(['Sick Leave', 'Annual Vacation', 'Holiday', 'Conference']);

async function leavesFromQueries(userId) {
    const result = emptyLeaves();
    if (!userId) {
        return result;
    }
    const user = esc(userId);
    const path = `/services/data/v62.0/query?q=${encodeURIComponent(
        `SELECT Id, Type__c, Stage__c, Start_Date_Time__c, End_Date_Time__c, Span_Duration__c FROM Time_Off_Request__c WHERE (OwnerId = '${user}' OR CreatedById = '${user}') AND Stage__c IN ('Approved','Submitted for Approval') AND Start_Date_Time__c = THIS_MONTH ORDER BY Start_Date_Time__c ASC LIMIT 200`
    )}`;
    const remote = await plannerApiFetch(path);
    const records = remote && Array.isArray(remote.records) ? remote.records : [];
    for (const row of records) {
        if (!LEAVE_TYPES.has(row.Type__c)) {
            continue;
        }
        const isPending = row.Stage__c === 'Submitted for Approval';
        const days = Number(row.Span_Duration__c || 1);
        const mapped = {
            requestId: row.Id,
            type: row.Type__c,
            stage: row.Stage__c,
            stageLabel: isPending ? 'Pending' : 'Approved',
            startDateTime: row.Start_Date_Time__c,
            endDateTime: row.End_Date_Time__c,
            days,
            isPending
        };
        if (isPending) {
            result.pendingRows.push(mapped);
            result.pendingDays += days;
        } else {
            result.approvedRows.push(mapped);
            result.approvedDays += days;
        }
    }
    result.monthLabel = new Date().toLocaleDateString(undefined, { month: 'long', year: 'numeric' });
    return result;
}

async function loadMonthlyLeaveDetails(params = {}) {
    try {
        const qs = params?.contextUserId
            ? `?contextUserId=${encodeURIComponent(params.contextUserId)}`
            : '';
        const remote = await plannerApiFetch(`${LEAVES_PATH}${qs}`);
        if (remote && typeof remote === 'object' && (remote.approvedRows || remote.pendingRows || remote.monthLabel)) {
            return {
                ...emptyLeaves(),
                ...remote,
                approvedRows: remote.approvedRows || [],
                pendingRows: remote.pendingRows || []
            };
        }
    } catch (_err) {
        /* custom route may not be deployed yet */
    }
    try {
        return await leavesFromQueries(currentUserId(params));
    } catch (_err) {
        return emptyLeaves();
    }
}

export default makeDualApex(loadMonthlyLeaveDetails);
