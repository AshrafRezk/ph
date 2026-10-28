import { makeDualApex } from './_wireAdapter.js';
import { plannerApiFetch } from './restHelper.js';

async function getOrdersForVisit(params = {}) {
    const visitId = params.visitId;
    if (!visitId) {
        return [];
    }
    try {
        const soql =
            'SELECT Id, Name, Account__c, Account__r.Name, Visit__c, Order_Type__c, Status__c, ' +
            'Total_Quantity__c, Skip_Full_Approval__c FROM Field_Order__c ' +
            `WHERE Visit__c = '${visitId}' ORDER BY CreatedDate DESC LIMIT 40`;
        const data = await plannerApiFetch(
            `/services/data/v62.0/query?q=${encodeURIComponent(soql)}`
        );
        return (data?.records || []).map((row) => ({
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
                : 'Approval: DM → NAM → BU → Yasser → Finance.'
        }));
    } catch (_err) {
        return [];
    }
}

export default makeDualApex(getOrdersForVisit);
