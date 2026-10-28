import { makeDualApex } from './_wireAdapter.js';
import { plannerApiFetch } from './restHelper.js';

const PATH = '/services/apexrest/accounts-tab/v1/pending-approvals';

export default makeDualApex(async () => {
    try {
        const rows = await plannerApiFetch(PATH, { fresh: true });
        return Array.isArray(rows) ? rows : [];
    } catch (_error) {
        return [];
    }
});
