import { makeDualApex } from './_wireAdapter.js';
import { soql, apexError } from './learningShared.js';
import {
    requireUnlockedVisit,
    createSObject,
    deleteSObject,
    esc
} from './fieldWorkflowShared.js';
import getFieldOrder from './getFieldOrder.js';

async function upsertHeader(visit) {
    const existing = await soql(
        `SELECT Id, Status__c FROM Visit_Order__c WHERE Visit__c = '${esc(visit.Id)}' ORDER BY CreatedDate DESC LIMIT 1`
    );
    if (existing.length) {
        if (existing[0].Status__c === 'Submitted') {
            throw apexError('This order is already submitted.');
        }
        const oldLines = await soql(
            `SELECT Id FROM Visit_Order_Line__c WHERE Visit_Order__c = '${esc(existing[0].Id)}'`
        );
        for (const line of oldLines) {
            await deleteSObject('Visit_Order_Line__c', line.Id);
        }
        return existing[0].Id;
    }
    return createSObject('Visit_Order__c', {
        Visit__c: visit.Id,
        Status__c: 'Draft'
    });
}

export default makeDualApex(async (params = {}) => {
    const visit = await requireUnlockedVisit(params.visitId);
    const orderId = await upsertHeader(visit);
    let displayOrder = 1;
    for (const line of params.lines || []) {
        if (!line?.productId) {
            continue;
        }
        const quantity = Number(line.quantity || 0);
        if (quantity <= 0) {
            continue;
        }
        await createSObject('Visit_Order_Line__c', {
            Visit_Order__c: orderId,
            Product2__c: line.productId,
            Quantity__c: quantity,
            Display_Order__c: displayOrder
        });
        displayOrder += 1;
    }
    return getFieldOrder({ visitId: visit.Id });
});
