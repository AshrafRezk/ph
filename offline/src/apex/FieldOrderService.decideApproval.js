import { makeDualApex } from './_wireAdapter.js';
import { plannerApiFetch } from './restHelper.js';

async function decideApproval(params = {}) {
    const orderId = params.orderId;
    if (!orderId) {
        throw Object.assign(new Error('Order is required.'), {
            body: { message: 'Order is required.' }
        });
    }
    if (params.approve === true) {
        // Prefer Apex when online — PATCH status locally as a light fallback.
        const body = { Status__c: 'Pending NAM' };
        await plannerApiFetch(`/services/data/v62.0/sobjects/Field_Order__c/${orderId}`, {
            method: 'PATCH',
            body: JSON.stringify(body)
        });
        return { id: orderId, status: body.Status__c, statusLabel: body.Status__c };
    }
    await plannerApiFetch(`/services/data/v62.0/sobjects/Field_Order__c/${orderId}`, {
        method: 'PATCH',
        body: JSON.stringify({
            Status__c: 'Rejected',
            Decision_Notes__c: params.notes || 'Rejected',
            Current_Approver__c: null
        })
    });
    return { id: orderId, status: 'Rejected', statusLabel: 'Rejected' };
}

export default makeDualApex(decideApproval);
