import { makeDualApex } from './_wireAdapter.js';
import { plannerApiFetch } from './restHelper.js';

const PATH = '/services/apexrest/accounts-tab/v1/wizard-options';

export default makeDualApex(async () => {
    const options = await plannerApiFetch(PATH, { method: 'GET' });
    return options || {};
});
