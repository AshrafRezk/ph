import { makeDualApex } from './_wireAdapter.js';
import { plannerApiFetch } from './restHelper.js';

async function approve(params = {}) {
    const requestId = params.requestId;
    await plannerApiFetch(`/services/data/v62.0/sobjects/Field_Request__c/${requestId}`, {
        method: 'PATCH',
        body: JSON.stringify({
            Status__c: 'Done',
            Decision_Notes__c: params.notes || null,
            Decision_Date__c: new Date().toISOString()
        })
    });
    return { id: requestId, status: 'Done', statusLabel: 'Done' };
}

export default makeDualApex(approve);
