import { plannerApiFetch } from './restHelper.js';
import { normalizeAccountClassFields } from './classCode.js';

export default async function getMapAccounts(params = {}) {
    const query = new URLSearchParams();
    if (params.contextUserId) query.set('contextUserId', params.contextUserId);
    const suffix = query.toString() ? `?${query.toString()}` : '';
    const result = await plannerApiFetch(`/services/apexrest/planner/v1/accounts/map${suffix}`);
    if (Array.isArray(result)) {
        return result.map(normalizeAccountClassFields);
    }
    if (result && Array.isArray(result.accounts)) {
        return {
            ...result,
            accounts: result.accounts.map(normalizeAccountClassFields)
        };
    }
    return result;
}
