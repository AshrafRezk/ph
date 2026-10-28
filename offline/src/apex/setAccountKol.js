import { makeDualApex } from './_wireAdapter.js';
import { plannerApiFetch } from './restHelper.js';

const PATH = '/services/apexrest/accounts-tab/v1/set-kol';

export default makeDualApex(async (params = {}) => {
    return plannerApiFetch(PATH, {
        method: 'POST',
        body: JSON.stringify({
            accountId: params.accountId || null,
            isKol: params.isKol === true
        })
    });
});
