import { makeDualApex } from './_wireAdapter.js';
import { plannerApiFetch } from './restHelper.js';
import { apexError } from './learningShared.js';

const PATH = '/services/apexrest/accounts-tab/v1/report-duplicate';

export default makeDualApex(async (params = {}) => {
    try {
        return await plannerApiFetch(PATH, {
            method: 'POST',
            body: JSON.stringify({
                accountId: params.accountId || null,
                duplicateOfId: params.duplicateOfId || null
            })
        });
    } catch (error) {
        throw apexError(error?.body?.message || error?.message || 'Could not report this duplicate.');
    }
});
