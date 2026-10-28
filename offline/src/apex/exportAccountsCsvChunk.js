import { makeDualApex } from './_wireAdapter.js';
import { plannerApiFetch } from './restHelper.js';
import { buildQuery } from './getAccountsTabPage.js';

const PATH = '/services/apexrest/accounts-tab/v1/export-chunk';

export default makeDualApex(async (params = {}) => {
    const chunk = await plannerApiFetch(`${PATH}${buildQuery(params)}`, {
        method: 'GET',
        fresh: true,
        timeoutMs: 120000
    });
    return chunk && typeof chunk === 'object' ? chunk : { csv: '', done: true };
});
