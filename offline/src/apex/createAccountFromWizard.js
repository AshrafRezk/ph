import { makeDualApex } from './_wireAdapter.js';
import { plannerApiFetch } from './restHelper.js';

export default makeDualApex(async (params = {}) => {
    const input = params.input || params || {};
    const name = String(input.accountName || input.name || '').trim();
    if (!name) {
        throw new Error('Account name is required.');
    }
    const body = {
        Name: name,
        Phone: input.phone || null,
        BillingCity: input.city || null,
        BillingState: input.governorate || null,
        RecordTypeId: input.recordTypeId || null
    };
    Object.keys(body).forEach((key) => {
        if (body[key] == null || body[key] === '') delete body[key];
    });
    const created = await plannerApiFetch('/services/data/v59.0/sobjects/Account', {
        method: 'POST',
        body: JSON.stringify(body)
    });
    return {
        accountId: created?.id,
        success: true,
        message: 'Account created'
    };
});
