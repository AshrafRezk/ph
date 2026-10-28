import { makeDualApex } from './_wireAdapter.js';
import { plannerApiFetch } from './restHelper.js';

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

async function getMyOrders(params = {}) {
    if (import.meta.env.DEV && globalThis.__ZETA_LOOKUP_PREVIEW__?.orders) {
        return globalThis.__ZETA_LOOKUP_PREVIEW__.orders;
    }
    try {
        const identity = await plannerApiFetch('/services/oauth2/userinfo');
        const userId = identity?.user_id;
        if (!userId) {
            return [];
        }
        const lim = Math.min(Number(params.limitSize) || 40, 200);
        const soql =
            'SELECT Id, Name, Account__c, Account__r.Name, Visit__c, Order_Type__c, Status__c, ' +
            'Total_Quantity__c, Skip_Full_Approval__c, Requested_By__r.Name, Submitted_Date__c, CreatedDate ' +
            `FROM Field_Order__c WHERE Requested_By__c = '${userId}' ` +
            "AND Status__c NOT IN ('Settled','Rejected') " +
            `ORDER BY Submitted_Date__c DESC NULLS LAST, CreatedDate DESC LIMIT ${lim}`;
        const data = await plannerApiFetch(
            `/services/data/v62.0/query?q=${encodeURIComponent(soql)}`
        );
        return (data?.records || []).map(mapRow);
    } catch (_err) {
        return [];
    }
}

export default makeDualApex(getMyOrders);
