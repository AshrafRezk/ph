import { makeDualApex } from './_wireAdapter.js';
import { plannerApiFetch } from './restHelper.js';

async function getRequestsForVisit(params = {}) {
    const visitId = params.visitId;
    if (!visitId) {
        return [];
    }
    try {
        const soql =
            'SELECT Id, Name, Account__c, Account__r.Name, Visit__c, Kind__c, Request_Type__c, ' +
            'Summary__c, Status__c, Submitted_Date__c, CreatedDate ' +
            `FROM Field_Request__c WHERE Visit__c = '${visitId}' ORDER BY CreatedDate DESC LIMIT 100`;
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
            summary: row.Summary__c,
            status: row.Status__c,
            statusLabel:
                row.Status__c === 'With Manager'
                    ? 'With your manager'
                    : row.Status__c === 'With Medical'
                      ? 'With medical'
                      : row.Status__c || 'Sent'
        }));
    } catch (_err) {
        return [];
    }
}

export default makeDualApex(getRequestsForVisit);
