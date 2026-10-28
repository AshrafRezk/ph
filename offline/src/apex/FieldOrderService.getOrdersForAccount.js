import { makeDualApex } from './_wireAdapter.js';
import { plannerApiFetch } from './restHelper.js';

function esc(value) {
    return String(value || '').replace(/\\/g, '\\\\').replace(/'/g, "\\'");
}

function mapRow(row) {
    return {
        id: row.Id,
        name: row.Name,
        accountId: row.Account__c,
        accountName: row.Account__r?.Name,
        visitId: row.Visit__c,
        orderType: row.Order_Type__c,
        status: row.Status__c,
        statusLabel: row.Status__c,
        totalQuantity: row.Total_Quantity__c,
        routingHint: row.Skip_Full_Approval__c
            ? 'Qty ≤ 10: full cycle skipped; Finance reviews next.'
            : 'Approval: DM → NAM → BU → Yasser → Finance.',
        requestedByName: row.Requested_By__r?.Name,
        skipFullApproval: row.Skip_Full_Approval__c === true
    };
}

async function getOrdersForAccount(params = {}) {
    const accountId = params.accountId;
    if (!accountId) {
        return [];
    }
    try {
        const soql =
            'SELECT Id, Name, Account__c, Account__r.Name, Visit__c, Order_Type__c, Status__c, ' +
            'Total_Quantity__c, Skip_Full_Approval__c, Requested_By__r.Name, Submitted_Date__c, CreatedDate ' +
            `FROM Field_Order__c WHERE Account__c = '${esc(accountId)}' ` +
            'ORDER BY CreatedDate DESC LIMIT 40';
        const data = await plannerApiFetch(
            `/services/data/v62.0/query?q=${encodeURIComponent(soql)}`,
            { fresh: true }
        );
        return (data?.records || []).map(mapRow);
    } catch (_err) {
        return [];
    }
}

export default makeDualApex(getOrdersForAccount);
