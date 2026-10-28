import { makeDualApex } from './_wireAdapter.js';
import { plannerApiFetch } from './restHelper.js';
import { prepareNameRomanizer } from '../nameRomanizer.js';

const PATH = '/services/apexrest/accounts-tab/v1/master-search';

export default makeDualApex(async (params = {}) => {
    if (params.cognitive === true) {
        prepareNameRomanizer();
    }
    const rows = await plannerApiFetch(PATH, {
        method: 'POST',
        body: JSON.stringify({
            searchTerm: params.searchTerm || params.q || '',
            recordTypeId: params.recordTypeId || null,
            cognitive: params.cognitive === true,
            brick148Id: params.brick148Id || null,
            brick702Id: params.brick702Id || null,
            specialtyFilter: params.specialtyFilter || null
        })
    });
    return Array.isArray(rows) ? rows : [];
});
