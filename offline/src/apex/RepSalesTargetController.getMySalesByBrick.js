import { makeDualApex } from './_wireAdapter.js';
import { plannerApiFetch } from './restHelper.js';
import { createScopeTracker } from './_territoryScope.js';

const nextScope = createScopeTracker();

// Rep Home "Sales vs Target" card: products and brick map for one month.
// `scope` only keys the cache per territory (the server ignores it); a territory change waits on the network.
export default makeDualApex(async (params = {}) => {
    const { scope, fresh } = nextScope();
    const query = new URLSearchParams();
    if (params.monthKey) {
        query.set('month', params.monthKey);
    }
    if (params.productId) {
        query.set('product', params.productId);
    }
    query.set('scope', scope);
    return plannerApiFetch(`/services/apexrest/rep-sales/v1/bricks?${query.toString()}`, { fresh });
});
