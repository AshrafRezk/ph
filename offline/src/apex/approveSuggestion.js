import { plannerApiFetch } from './restHelper.js';

export default async function approveSuggestion(params = {}) {
    return plannerApiFetch('/services/apexrest/planner/v1/classification-suggestions/approve', {
        method: 'POST',
        body: JSON.stringify({ suggestionId: params.suggestionId })
    });
}
