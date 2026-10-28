import { makeDualApex } from './_wireAdapter.js';
import { plannerApiFetch } from './restHelper.js';

const PATH = '/services/apexrest/accounts-tab/v1/resolve-bricks';

export default makeDualApex(async (params = {}) => {
    const result = await plannerApiFetch(PATH, {
        method: 'POST',
        body: JSON.stringify({
            latitude: params.latitude,
            longitude: params.longitude
        })
    });
    return result || {};
});
