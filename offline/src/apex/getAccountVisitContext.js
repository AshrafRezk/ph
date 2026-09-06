import { makeDualApex } from './_wireAdapter.js';
import { plannerApiFetch } from './restHelper.js';

function escapeSoql(value) {
    return String(value || '').replace(/\\/g, '\\\\').replace(/'/g, "\\'");
}

export default makeDualApex(async (params = {}) => {
    const accountId = params.accountId;
    if (!accountId) {
        return {
            hasPlanTarget: false,
            hasGeo: false,
            futureVisits: [],
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

        const monthStart = new Date();
        monthStart.setDate(1);
        monthStart.setHours(0, 0, 0, 0);
        const monthEnd = new Date(monthStart);
        monthEnd.setMonth(monthEnd.getMonth() + 1);
        const startIso = monthStart.toISOString();
        const endIso = monthEnd.toISOString();

        const visits = await plannerApiFetch(
            `/services/data/v62.0/query?q=${encodeURIComponent(
                `SELECT Id, Name, Status__c, Start_Date__c, End_Date__c
                 FROM Visit__c
                 WHERE Account__c = '${id}'
                 AND Start_Date__c >= ${startIso.split('T')[0]}
                 AND Start_Date__c < ${endIso.split('T')[0]}
                 ORDER BY Start_Date__c ASC
                 LIMIT 50`
            )}`
        );
        const futureVisits = (visits?.records || []).map((v) => ({
            id: v.Id,
            name: v.Name,
            status: v.Status__c,
            startDateTime: v.Start_Date__c,
            endDateTime: v.End_Date__c
        }));
        const actualVisits = futureVisits.filter((v) => /completed/i.test(v.status || '')).length;

        return {
            accountName: row?.Name,
            hasPlanTarget: false,
            hasGeo,
            centerLatitude: row?.BillingLatitude,
            centerLongitude: row?.BillingLongitude,
            futureVisits,
            targetVisits: 0,
            actualVisits,
            visitGap: 0,
            committedVisits: futureVisits.length,
            projectedVisits: futureVisits.length,
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
            targetVisits: 0,
            actualVisits: 0,
            visitGap: 0,
            canMutateVisits: true,
            paceStatus: 'not_applicable'
        };
    }
});
