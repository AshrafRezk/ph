import { makeDualApex } from './_wireAdapter.js';
import { plannerApiFetch } from './restHelper.js';

async function getManagerQueue() {
    try {
        const identity = await plannerApiFetch('/services/oauth2/userinfo');
        const userId = identity?.user_id;
        if (!userId) {
            return [];
        }
        const soql =
            'SELECT Id, Name, Account__c, Account__r.Name, Requested_By__r.Name, Kind__c, ' +
            'Request_Type__c, Summary__c, Status__c, Urgency__c, Submitted_Date__c, CreatedDate ' +
            `FROM Field_Request__c WHERE Manager__c = '${userId}' AND Status__c = 'With Manager' ` +
            'ORDER BY Urgency__c DESC, Submitted_Date__c ASC NULLS LAST LIMIT 100';
        const data = await plannerApiFetch(
            `/services/data/v62.0/query?q=${encodeURIComponent(soql)}`
        );
        const now = Date.now();
        return (data?.records || []).map((row) => {
            const submitted = row.Submitted_Date__c || row.CreatedDate;
            const submittedMs = submitted ? new Date(submitted).getTime() : now;
            return {
                id: row.Id,
                name: row.Name,
                accountId: row.Account__c,
                accountName: row.Account__r?.Name,
                requestedByName: row.Requested_By__r?.Name,
                kind: row.Kind__c,
                requestType: row.Request_Type__c,
                summary: row.Summary__c,
                status: row.Status__c,
                statusLabel: 'With your manager',
                urgency: row.Urgency__c,
                submittedDate: submitted,
                isLate: now - submittedMs > 24 * 60 * 60 * 1000,
                canApprove: true,
                canDecline: true,
                canSendToMedical: true
            };
        });
    } catch (_err) {
        return [];
    }
}

export default makeDualApex(getManagerQueue);
