import { makeDualApex } from './_wireAdapter.js';
import { plannerApiFetch } from './restHelper.js';

async function decline(params = {}) {
    const requestId = params.requestId;
    const reason = String(params.reason || '').trim();
    if (!reason) {
        throw Object.assign(new Error('Add a short reason so the rep knows what to do next.'), {
            body: { message: 'Add a short reason so the rep knows what to do next.' }
        });
    }
    await plannerApiFetch(`/services/data/v62.0/sobjects/Field_Request__c/${requestId}`, {
        method: 'PATCH',
        body: JSON.stringify({
            Status__c: 'Declined',
            Decision_Notes__c: reason,
            Decision_Date__c: new Date().toISOString()
        })
    });
    return { id: requestId, status: 'Declined', statusLabel: 'Declined' };
}

export default makeDualApex(decline);
