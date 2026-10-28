import { plannerApiFetch } from './restHelper.js';

export default async function rejectSuggestion(params = {}) {
    const request = params.request || params;
    return plannerApiFetch('/services/apexrest/planner/v1/classification-suggestions/reject', {
        method: 'POST',
        body: JSON.stringify({
            suggestionId: request.suggestionId,
            rejectionReason: request.rejectionReason,
            overwrittenClass: request.overwrittenClass
        })
    });
}
