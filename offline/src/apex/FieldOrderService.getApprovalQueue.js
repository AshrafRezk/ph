import { makeDualApex } from './_wireAdapter.js';
import { plannerApiFetch } from './restHelper.js';

async function getApprovalQueue(params = {}) {
    try {
        const identity = await plannerApiFetch('/services/oauth2/userinfo');
        const userId = identity?.user_id;
        if (!userId) {
            return [];
        }
        const lim = Math.min(Number(params.limitSize) || 100, 200);
        const soql =
            'SELECT Id, Name, Account__c, Account__r.Name, Visit__c, Order_Type__c, Status__c, ' +
            'Total_Quantity__c, Requested_By__r.Name, Submitted_Date__c FROM Field_Order__c ' +
            `WHERE Current_Approver__c = '${userId}' ` +
            "AND Status__c IN ('Pending DM','Pending NAM','Pending BU','Pending Yasser','Pending Finance') " +
            `ORDER BY Submitted_Date__c ASC NULLS LAST LIMIT ${lim}`;
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
            requestedByName: row.Requested_By__r?.Name,
            canApprove: true
        }));
    } catch (_err) {
        return [];
    }
}

export default makeDualApex(getApprovalQueue);
