import { makeDualApex } from './_wireAdapter.js';
import { plannerApiFetch } from './restHelper.js';

const PATH = '/services/apexrest/accounts-tab/v1/nurture-summary';

const EMPTY = { needsYou: 0, withManager: 0, withSfe: 0, total: 0 };

export default makeDualApex(async () => {
    try {
        return (await plannerApiFetch(PATH, { fresh: true })) || EMPTY;
    } catch (_error) {
        return EMPTY;
    }
});
