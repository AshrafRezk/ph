import { makeDualApex } from './_wireAdapter.js';
import { plannerApiFetch } from './restHelper.js';

async function getFinanceQueue(params = {}) {
    try {
        const lim = Math.min(Number(params.limitSize) || 40, 200);
        const soql =
            'SELECT Id, Name, Account__c, Account__r.Name, Visit__c, Order_Type__c, Status__c, ' +
            'Total_Quantity__c, Requested_By__r.Name, Submitted_Date__c FROM Field_Order__c ' +
            "WHERE Status__c IN ('Pending Finance','Approved','Goods Issued','Collected') " +
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
            requestedByName: row.Requested_By__r?.Name
        }));
    } catch (_err) {
        return [];
    }
}

export default makeDualApex(getFinanceQueue);
