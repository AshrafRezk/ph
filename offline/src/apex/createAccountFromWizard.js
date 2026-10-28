import { makeDualApex } from './_wireAdapter.js';
import { plannerApiFetch } from './restHelper.js';

const PATH = '/services/apexrest/accounts-tab/v1/create';

export default makeDualApex(async (params = {}) => {
    const input = params.input || params || {};
    return plannerApiFetch(PATH, {
        method: 'POST',
        body: JSON.stringify({ input })
    });
});
