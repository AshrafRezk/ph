import { makeDualApex } from './_wireAdapter.js';
import { plannerApiFetch } from './restHelper.js';
import { apexError } from './learningShared.js';

const PATH = '/services/apexrest/accounts-tab/v1/reject-account';

export default makeDualApex(async (params = {}) => {
    try {
        return await plannerApiFetch(PATH, {
            method: 'POST',
            body: JSON.stringify({
                accountId: params.accountId || null,
                rejectionReason: params.rejectionReason || null
            })
        });
    } catch (error) {
        throw apexError(error?.body?.message || error?.message || 'Reject failed');
    }
});
