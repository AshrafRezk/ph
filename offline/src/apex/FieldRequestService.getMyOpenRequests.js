import { makeDualApex } from './_wireAdapter.js';
import { plannerApiFetch } from './restHelper.js';

async function getMyOpenRequests() {
    if (import.meta.env.DEV && globalThis.__ZETA_LOOKUP_PREVIEW__?.requests) {
        return globalThis.__ZETA_LOOKUP_PREVIEW__.requests;
    }
    try {
        const identity = await plannerApiFetch('/services/oauth2/userinfo');
        const userId = identity?.user_id;
        if (!userId) {
            return [];
        }
        const soql =
            'SELECT Id, Name, Account__c, Account__r.Name, Visit__c, Kind__c, Request_Type__c, ' +
            'Urgency__c, Summary__c, Status__c, Source__c, Submitted_Date__c, CreatedDate ' +
            `FROM Field_Request__c WHERE Requested_By__c = '${userId}' ` +
            "AND Status__c IN ('Sent','With Manager','With Medical','Needs You') " +
            'ORDER BY Submitted_Date__c DESC NULLS LAST LIMIT 50';
        const data = await plannerApiFetch(
            `/services/data/v62.0/query?q=${encodeURIComponent(soql)}`
        );
        return (data?.records || []).map((row) => ({
            id: row.Id,
            name: row.Name,
            accountId: row.Account__c,
            accountName: row.Account__r?.Name,
            visitId: row.Visit__c,
            kind: row.Kind__c,
            requestType: row.Request_Type__c,
            urgency: row.Urgency__c,
            summary: row.Summary__c,
            status: row.Status__c,
            statusLabel:
                row.Status__c === 'With Manager'
                    ? 'With your manager'
                    : row.Status__c === 'With Medical'
                      ? 'With medical'
                      : row.Status__c || 'Sent',
            source: row.Source__c,
            submittedDate: row.Submitted_Date__c || row.CreatedDate,
            isLate: false
        }));
    } catch (_err) {
        return [];
    }
}

export default makeDualApex(getMyOpenRequests);
