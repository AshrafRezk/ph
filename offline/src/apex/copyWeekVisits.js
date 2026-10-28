import { plannerApiFetch } from './restHelper.js';

export default async function copyWeekVisits(params = {}) {
    return plannerApiFetch('/services/apexrest/planner/assist/v1/visits/copy-week', {
        method: 'POST',
        body: JSON.stringify({
            targetWeekStart: params.targetWeekStart,
            weekCount: params.weekCount,
            contextUserId: params.contextUserId
        })
    });
}
