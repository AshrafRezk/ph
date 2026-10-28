import { makeDualApex } from './_wireAdapter.js';
import { plannerApiFetch } from './restHelper.js';

const PATH = '/services/apexrest/accounts-tab/v1/approval-manager';

export default makeDualApex(async () => {
    try {
        return (await plannerApiFetch(PATH, { fresh: true })) === true;
    } catch (_error) {
        return false;
    }
});
