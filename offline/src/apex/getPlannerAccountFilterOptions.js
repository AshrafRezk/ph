import { plannerApiFetch } from './restHelper.js';
import { filterLetterNumberOptions } from './classCode.js';

export default async function getPlannerAccountFilterOptions(params = {}) {
    const query = new URLSearchParams();
    if (params.contextUserId) query.set('contextUserId', params.contextUserId);
    const suffix = query.toString() ? `?${query.toString()}` : '';
    const result = await plannerApiFetch(`/services/apexrest/planner/v1/accounts/filters${suffix}`);
    if (!result || typeof result !== 'object') {
        return result;
    }
    return {
        ...result,
        classificationOptions: filterLetterNumberOptions(result.classificationOptions)
    };
}
