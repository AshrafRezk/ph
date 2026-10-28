import { makeDualApex } from './_wireAdapter.js';
import { plannerApiFetch } from './restHelper.js';
import { apexError } from './learningShared.js';

export default makeDualApex(async (params = {}) => {
    const accountId = params && params.accountId;
    if (!accountId) {
        return null;
    }
    try {
        return await plannerApiFetch(
            `/services/apexrest/accounts-tab/v1/duplicate-check?accountId=${encodeURIComponent(accountId)}`
        );
    } catch (error) {
        throw apexError(error?.body?.message || error?.message || 'Unable to check duplicates.');
    }
});
