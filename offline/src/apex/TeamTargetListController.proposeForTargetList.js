import { makeDualApex } from './_wireAdapter.js';
import { plannerApiFetch } from './restHelper.js';

// DM team target list: online only, the server checks the team and the limits.
export default makeDualApex(async (params = {}) =>
    plannerApiFetch('/services/apexrest/team-targets/v1/propose', {
        method: 'POST',
        body: JSON.stringify({ repId: params.repId, accountId: params.accountId })
    })
);
