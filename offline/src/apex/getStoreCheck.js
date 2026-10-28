import { makeDualApex } from './_wireAdapter.js';
import { soql } from './learningShared.js';
import { requireVisit, visitLocked, productOptions, esc } from './fieldWorkflowShared.js';
import { loadStoreCheckPhotos } from './storeCheckPhotos.js';

export default makeDualApex(async (params = {}) => {
    const visit = await requireVisit(params.visitId);
    const options = await productOptions();
    const headers = await soql(
        `SELECT Id, Notes__c FROM Store_Check__c WHERE Visit__c = '${esc(visit.Id)}' ORDER BY CreatedDate DESC LIMIT 1`
    );
    if (!headers.length) {
        return {
            storeCheckId: null,
            notes: '',
            isLocked: visitLocked(visit),
            lines: [],
            photos: [],
            productOptions: options
        };
    }
    const header = headers[0];
    const lines = await soql(
        `SELECT Id, Product__c, Product__r.Name, Available__c, Facings__c FROM Store_Check_Line__c WHERE Store_Check__c = '${esc(header.Id)}' ORDER BY CreatedDate ASC`
    );
    return {
        storeCheckId: header.Id,
        notes: header.Notes__c || '',
        isLocked: visitLocked(visit),
        productOptions: options,
        photos: await loadStoreCheckPhotos(header.Id),
        lines: lines.map((line) => ({
            id: line.Id,
            productId: line.Product__c,
            productName: line.Product__r?.Name,
            available: line.Available__c === true,
            facings: line.Facings__c
        }))
    };
});
