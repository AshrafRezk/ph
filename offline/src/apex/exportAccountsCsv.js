import { makeDualApex } from './_wireAdapter.js';
import { plannerApiFetch } from './restHelper.js';
import { buildQuery } from './getAccountsTabPage.js';

const PATH = '/services/apexrest/accounts-tab/v1/export';

export default makeDualApex(async (params = {}) => {
    const csv = await plannerApiFetch(`${PATH}${buildQuery(params)}`, {
        method: 'GET',
        fresh: true,
        timeoutMs: 120000
    });
    return typeof csv === 'string' ? csv : '';
});
