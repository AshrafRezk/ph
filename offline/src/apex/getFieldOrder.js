import { makeDualApex } from './_wireAdapter.js';
import { soql } from './learningShared.js';
import { requireVisit, visitLocked, productOptions, esc } from './fieldWorkflowShared.js';

export default makeDualApex(async (params = {}) => {
    const visit = await requireVisit(params.visitId);
    const options = await productOptions();
    const headers = await soql(
        `SELECT Id, Status__c, Notes__c FROM Visit_Order__c WHERE Visit__c = '${esc(visit.Id)}' ORDER BY CreatedDate DESC LIMIT 1`
    );
    if (!headers.length) {
        return { orderId: null, status: 'Draft', isLocked: visitLocked(visit), lines: [], productOptions: options };
    }
    const header = headers[0];
    const lines = await soql(
        `SELECT Id, Product2__c, Product2__r.Name, Quantity__c FROM Visit_Order_Line__c WHERE Visit_Order__c = '${esc(header.Id)}' ORDER BY Display_Order__c ASC NULLS LAST, CreatedDate ASC`
    );
    return {
        orderId: header.Id,
        status: header.Status__c || 'Draft',
        isLocked: visitLocked(visit),
        productOptions: options,
        lines: lines.map((line) => ({
            id: line.Id,
            productId: line.Product2__c,
            productName: line.Product2__r?.Name,
            quantity: line.Quantity__c
        }))
    };
});
