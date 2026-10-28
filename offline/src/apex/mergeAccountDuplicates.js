import { makeDualApex } from './_wireAdapter.js';
import { plannerApiFetch } from './restHelper.js';
import { apexError } from './learningShared.js';

const PATH = '/services/apexrest/accounts-tab/v1/merge-accounts';

export default makeDualApex(async (params = {}) => {
    try {
        return await plannerApiFetch(PATH, {
            method: 'POST',
            body: JSON.stringify({
                survivorId: params.survivorId || null,
                duplicateId: params.duplicateId || null
            })
        });
    } catch (error) {
        throw apexError(error?.body?.message || error?.message || 'Could not merge these accounts.');
    }
});
