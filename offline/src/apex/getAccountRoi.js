import { makeDualApex } from './_wireAdapter.js';
import { plannerApiFetch } from './restHelper.js';

function escapeSoql(value) {
    return String(value || '').replace(/\\/g, '\\\\').replace(/'/g, "\\'");
}

export default makeDualApex(async (params = {}) => {
    const accountId = params.accountId;
    if (!accountId) {
        return { hasProducts: false, productRanks: [], kpis: [] };
    }
    try {
        const id = escapeSoql(accountId);
        const data = await plannerApiFetch(
            `/services/data/v62.0/query?q=${encodeURIComponent(
                `SELECT Id, Name FROM Account WHERE Id = '${id}' LIMIT 1`
            )}`
        );
        return {
            accountId,
            accountName: data?.records?.[0]?.Name || '',
            hasProducts: false,
            productRanks: [],
            kpis: [],
            selectedProductId: params.productId || null
        };
    } catch (_error) {
        return { hasProducts: false, productRanks: [], kpis: [] };
    }
});
