import { plannerApiFetch } from './restHelper.js';
import { normalizeAccountsTabRow } from './classCode.js';
import { createScopeTracker } from './_territoryScope.js';

const PATH = '/services/apexrest/planner/v1/accounts-tab/page';
const nextScope = createScopeTracker();

function buildQuery(params) {
    const qs = new URLSearchParams();
    const source = params || {};
    Object.keys(source).forEach((key) => {
        const value = source[key];
        if (value == null) {
            return;
        }
        if (Array.isArray(value)) {
            if (value.length) {
                qs.set(key, value.join(','));
            }
            return;
        }
        if (typeof value !== 'object') {
            qs.set(key, String(value));
        }
    });
    const encoded = qs.toString();
    return encoded ? `?${encoded}` : '';
}

export default async function getAccountsTabPage(params) {
    // `territoryScope` keys the saved copy per working territory (the server ignores it); after a switch, wait on the network.
    const { scope, fresh } = nextScope();
    const page = await plannerApiFetch(`${PATH}${buildQuery({ ...(params || {}), territoryScope: scope })}`, {
        method: 'GET',
        fresh
    });
    if (!page || typeof page !== 'object') {
        return page;
    }
    return {
        ...page,
        rows: Array.isArray(page.rows) ? page.rows.map(normalizeAccountsTabRow) : page.rows
    };
}

export { buildQuery };
