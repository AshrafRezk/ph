import { makeDualApex } from './_wireAdapter.js';
import { soql, apexError } from './learningShared.js';
import { requireUnlockedVisit, updateSObject, esc } from './fieldWorkflowShared.js';
import getFieldOrder from './getFieldOrder.js';

export default makeDualApex(async (params = {}) => {
    const visit = await requireUnlockedVisit(params.visitId);
    const headers = await soql(
        `SELECT Id FROM Visit_Order__c WHERE Visit__c = '${esc(visit.Id)}' ORDER BY CreatedDate DESC LIMIT 1`
    );
    if (!headers.length) {
        throw apexError('Add at least one product before submitting.');
    }
    const lineCount = await soql(
        `SELECT Id FROM Visit_Order_Line__c WHERE Visit_Order__c = '${esc(headers[0].Id)}'`
    );
    if (!lineCount.length) {
        throw apexError('Add at least one product before submitting.');
    }
    await updateSObject('Visit_Order__c', headers[0].Id, { Status__c: 'Submitted' });
    return getFieldOrder({ visitId: visit.Id });
});
