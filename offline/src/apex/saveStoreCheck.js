import { makeDualApex } from './_wireAdapter.js';
import { soql } from './learningShared.js';
import {
    requireUnlockedVisit,
    createSObject,
    updateSObject,
    deleteSObject,
    esc
} from './fieldWorkflowShared.js';
import getStoreCheck from './getStoreCheck.js';

export default makeDualApex(async (params = {}) => {
    const visit = await requireUnlockedVisit(params.visitId);
    const notes = params.notes || '';
    const lines = params.lines || [];
    const existing = await soql(
        `SELECT Id FROM Store_Check__c WHERE Visit__c = '${esc(visit.Id)}' ORDER BY CreatedDate DESC LIMIT 1`
    );
    let storeCheckId;
    if (!existing.length) {
        storeCheckId = await createSObject('Store_Check__c', {
            Visit__c: visit.Id,
            Account__c: visit.Account__c || null,
            Notes__c: notes
        });
    } else {
        storeCheckId = existing[0].Id;
        await updateSObject('Store_Check__c', storeCheckId, {
            Notes__c: notes,
            Account__c: visit.Account__c || null
        });
        const oldLines = await soql(
            `SELECT Id FROM Store_Check_Line__c WHERE Store_Check__c = '${esc(storeCheckId)}'`
        );
        for (const line of oldLines) {
            await deleteSObject('Store_Check_Line__c', line.Id);
        }
    }
    for (const line of lines) {
        if (!line?.productId) {
            continue;
        }
        await createSObject('Store_Check_Line__c', {
            Store_Check__c: storeCheckId,
            Product__c: line.productId,
            Available__c: line.available === true,
            Facings__c: line.facings || 0
        });
    }
    return getStoreCheck({ visitId: visit.Id });
});
