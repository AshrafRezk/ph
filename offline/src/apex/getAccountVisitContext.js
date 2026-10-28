import { makeDualApex } from './_wireAdapter.js';
import { plannerApiFetch } from './restHelper.js';

function escapeSoql(value) {
    return String(value || '').replace(/\\/g, '\\\\').replace(/'/g, "\\'");
}

function soqlDateLiteral(date) {
    const y = date.getFullYear();
    const m = String(date.getMonth() + 1).padStart(2, '0');
    const d = String(date.getDate()).padStart(2, '0');
    return `${y}-${m}-${d}`;
}

function mapVisit(v) {
    return {
        id: v.Id,
        name: v.Name,
        status: v.Status__c,
        startDateTime: v.Start_Date__c,
        endDateTime: v.End_Date__c
    };
}

const PLANNED_STATUSES = "('Draft','Submitted','Scheduled','Rescheduled')";

export default makeDualApex(async (params = {}) => {
    const accountId = params.accountId;
    if (!accountId) {
        return {
            hasPlanTarget: false,
            hasGeo: false,
            futureVisits: [],
            previousVisits: [],
            targetVisits: 0,
            actualVisits: 0,
            visitGap: 0,
            canMutateVisits: true,
            paceStatus: 'not_applicable'
        };
    }
    const id = escapeSoql(accountId);
    try {
        const acct = await plannerApiFetch(
            `/services/data/v62.0/query?q=${encodeURIComponent(
                `SELECT Id, Name, BillingLatitude, BillingLongitude FROM Account WHERE Id = '${id}' LIMIT 1`
            )}`
        );
        const row = acct?.records?.[0];
        const hasGeo = row?.BillingLatitude != null && row?.BillingLongitude != null;

        const today = new Date();
        today.setHours(0, 0, 0, 0);
        const monthStart = new Date(today.getFullYear(), today.getMonth(), 1);
        const monthEnd = new Date(today.getFullYear(), today.getMonth() + 1, 0);
        const todayLit = soqlDateLiteral(today);
        const monthEndLit = soqlDateLiteral(monthEnd);

        const futureResult = await plannerApiFetch(
            `/services/data/v62.0/query?q=${encodeURIComponent(
                `SELECT Id, Name, Status__c, Start_Date__c, End_Date__c
                 FROM Visit__c
                 WHERE Account__c = '${id}'
                 AND Start_Date__c >= ${todayLit}T00:00:00Z
                 AND Start_Date__c <= ${monthEndLit}T23:59:59Z
                 AND Status__c IN ${PLANNED_STATUSES}
                 ORDER BY Start_Date__c ASC
                 LIMIT 50`
            )}`
        );
        const futureVisits = (futureResult?.records || []).map(mapVisit);

        const previousResult = await plannerApiFetch(
            `/services/data/v62.0/query?q=${encodeURIComponent(
                `SELECT Id, Name, Status__c, Start_Date__c, End_Date__c
                 FROM Visit__c
                 WHERE Account__c = '${id}'
                 AND (Start_Date__c < ${todayLit}T00:00:00Z OR Status__c = 'Completed')
                 ORDER BY Start_Date__c DESC NULLS LAST
                 LIMIT 5`
            )}`
        );
        const previousVisits = (previousResult?.records || []).map(mapVisit);

        const actualVisits = previousVisits.filter((v) => /completed/i.test(v.status || '')).length;
        const hasPlanTarget = futureVisits.length > 0 || previousVisits.length > 0;

        return {
            accountName: row?.Name,
            hasPlanTarget,
            hasGeo,
            centerLatitude: row?.BillingLatitude,
            centerLongitude: row?.BillingLongitude,
            futureVisits,
            previousVisits,
            targetVisits: 0,
            actualVisits,
            visitGap: 0,
            committedVisits: futureVisits.length + actualVisits,
            projectedVisits: futureVisits.length + actualVisits,
            projectedPercent: 0,
            willMeetTarget: false,
            paceStatus: 'not_applicable',
            canMutateVisits: true,
            elapsedWorkingDays: 0,
            totalWorkingDays: 0
        };
    } catch (_error) {
        return {
            hasPlanTarget: false,
            hasGeo: false,
            futureVisits: [],
            previousVisits: [],
            targetVisits: 0,
            actualVisits: 0,
            visitGap: 0,
            canMutateVisits: true,
            paceStatus: 'not_applicable'
        };
    }
});
