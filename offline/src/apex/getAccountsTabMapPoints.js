import { plannerApiFetch } from './restHelper';
import { buildQuery } from './getAccountsTabPage';
import { createScopeTracker } from './_territoryScope.js';

const PATH = '/services/apexrest/planner/v1/accounts-tab/map-points';
const nextScope = createScopeTracker();

export default async function getAccountsTabMapPoints(params) {
    // Same per-territory saved copy as the list (see getAccountsTabPage).
    const { scope, fresh } = nextScope();
    return plannerApiFetch(`${PATH}${buildQuery({ ...(params || {}), territoryScope: scope })}`, { method: 'GET', fresh });
}