import { makeDualApex } from './_wireAdapter.js';
import { plannerApiFetch } from './restHelper.js';

async function markPaid(params = {}) {
    const orderId = params.orderId;
    if (!orderId) {
        throw Object.assign(new Error('Order is required.'), {
            body: { message: 'Order is required.' }
        });
    }
    await plannerApiFetch(`/services/data/v62.0/sobjects/Field_Order__c/${orderId}`, {
        method: 'PATCH',
        body: JSON.stringify({ Status__c: 'Collected', Current_Approver__c: null })
    });
    return { id: orderId, status: 'Collected', statusLabel: 'Collected' };
}

export default makeDualApex(markPaid);
