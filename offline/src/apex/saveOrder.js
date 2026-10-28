import { makeDualApex } from './_wireAdapter.js';
import { soql, apexError } from './learningShared.js';
import {
    requireUnlockedVisit,
    createSObject,
    updateSObject,
    deleteSObject,
    esc
} from './fieldWorkflowShared.js';
import { loadOrderPayload } from './getOrderContext.js';

async function saveOrder(params = {}) {
    const visit = await requireUnlockedVisit(params.visitId);
    const status = String(params.status || 'Draft').trim() || 'Draft';
    if (status !== 'Draft' && status !== 'Submitted') {
        throw apexError('Order status must be Draft or Submitted.');
    }
    const seen = new Set();
    const lines = [];
    for (const line of params.lines || []) {
        if (!line?.productId || seen.has(line.productId)) {
            continue;
        }
        const quantity = Number(line.quantity);
        if (!Number.isFinite(quantity) || quantity < 1) {
            throw apexError('Each order line needs a quantity of at least 1.');
        }
        seen.add(line.productId);
        lines.push({
            productId: line.productId,
            quantity,
            notes: line.notes || null
        });
    }
    if (!lines.length) {
        throw apexError('Add at least one territory product with a quantity.');
    }

    const existing = await soql(
        `SELECT Id FROM Visit_Order__c WHERE Visit__c = '${esc(visit.Id)}' ORDER BY CreatedDate DESC LIMIT 1`
    );
    let orderId;
    if (existing.length) {
        orderId = existing[0].Id;
        await updateSObject('Visit_Order__c', orderId, {
            Status__c: status,
            Notes__c: params.notes || null
        });
        const oldLines = await soql(
            `SELECT Id FROM Visit_Order_Line__c WHERE Visit_Order__c = '${esc(orderId)}'`
        );
        for (const line of oldLines) {
            await deleteSObject('Visit_Order_Line__c', line.Id);
        }
    } else {
        orderId = await createSObject('Visit_Order__c', {
            Visit__c: visit.Id,
            Status__c: status,
            Notes__c: params.notes || null
        });
    }

    let displayOrder = 1;
    for (const line of lines) {
        await createSObject('Visit_Order_Line__c', {
            Visit_Order__c: orderId,
            Product2__c: line.productId,
            Quantity__c: line.quantity,
            Notes__c: line.notes,
            Display_Order__c: displayOrder
        });
        displayOrder += 1;
    }
    return loadOrderPayload(visit.Id);
}

export default makeDualApex(saveOrder);
