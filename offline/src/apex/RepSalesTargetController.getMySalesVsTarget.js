import { makeDualApex } from './_wireAdapter.js';
import { plannerApiFetch } from './restHelper.js';
import { createScopeTracker } from './_territoryScope.js';

const nextScope = createScopeTracker();

// Rep Home "Sales vs Target" card: months view (RepSalesRestService → RepSalesTargetController).
// `scope` only keys the cache per territory (the server ignores it); a territory change waits on the network.
export default makeDualApex(async (params = {}) => {
    const { scope, fresh } = nextScope();
    const query = new URLSearchParams();
    if (params.monthsBack) {
        query.set('monthsBack', params.monthsBack);
    }
    query.set('scope', scope);
    return plannerApiFetch(`/services/apexrest/rep-sales/v1/summary?${query.toString()}`, { fresh });
});
