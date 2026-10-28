import { makeDualApex } from './_wireAdapter.js';
import { plannerApiFetch } from './restHelper.js';

const PATH = '/services/apexrest/accounts-tab/v1/createable-record-types';

export default makeDualApex(async () => {
    const options = await plannerApiFetch(PATH, { method: 'GET' });
    return Array.isArray(options) ? options : [];
});
