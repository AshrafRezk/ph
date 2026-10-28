import { makeDualApex } from './_wireAdapter.js';
import { plannerApiFetch } from './restHelper.js';

const PATH = '/services/apexrest/accounts-tab/v1/vezeeta-profile';

export default makeDualApex(async (params = {}) => {
    return plannerApiFetch(PATH, {
        method: 'POST',
        body: JSON.stringify({
            profileUrl: params.profileUrl || params.urlName || ''
        })
    });
});
