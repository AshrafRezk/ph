import { makeDualApex } from './_wireAdapter.js';
import { plannerApiFetch } from './restHelper.js';

function esc(value) {
    return String(value || '').replace(/\\/g, '\\\\').replace(/'/g, "\\'");
}

function statusLabel(status) {
    if (status === 'With Manager') {
        return 'With your manager';
    }
    if (status === 'With Medical') {
        return 'With medical';
    }
    return status || 'Sent';
}

async function getRequestsForAccount(params = {}) {
    const accountId = params.accountId;
    if (!accountId) {
        return [];
    }
    try {
        const soql =
            'SELECT Id, Name, Account__c, Account__r.Name, Visit__c, Kind__c, Request_Type__c, ' +
            'Urgency__c, Summary__c, Status__c, Source__c, Submitted_Date__c, CreatedDate ' +
            `FROM Field_Request__c WHERE Account__c = '${esc(accountId)}' ` +
            'ORDER BY CreatedDate DESC LIMIT 50';
        const data = await plannerApiFetch(
            `/services/data/v62.0/query?q=${encodeURIComponent(soql)}`,
            { fresh: true }
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
            statusLabel: statusLabel(row.Status__c),
            source: row.Source__c,
            submittedDate: row.Submitted_Date__c || row.CreatedDate,
            isLate: false
        }));
    } catch (_err) {
        return [];
    }
}

export default makeDualApex(getRequestsForAccount);
