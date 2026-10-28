import { plannerApiFetch, isOffline } from './restHelper.js';

export default async function getPendingSuggestions(params = {}) {
    if (isOffline()) {
        return [];
    }
    const query = new URLSearchParams();
    if (params.contextUserId) query.set('contextUserId', params.contextUserId);
    const suffix = query.toString() ? `?${query.toString()}` : '';
    return plannerApiFetch(`/services/apexrest/planner/v1/classification-suggestions${suffix}`);
}
