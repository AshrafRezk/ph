import { makeDualApex } from './_wireAdapter.js';
import { plannerApiFetch } from './restHelper.js';

const PATH = '/services/apexrest/accounts-tab/v1/map-places';

export default makeDualApex(async (params = {}) => {
    return plannerApiFetch(PATH, {
        method: 'POST',
        body: JSON.stringify({
            searchTerm: params.searchTerm || params.q || '',
            recordTypeDeveloperName: params.recordTypeDeveloperName || null,
            geoFilter: params.geoFilter || null
        })
    });
});
