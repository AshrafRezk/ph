import { plannerApiFetch } from './restHelper.js';

export default async function copyDayVisits(params = {}) {
    return plannerApiFetch('/services/apexrest/planner/assist/v1/visits/copy-day', {
        method: 'POST',
        body: JSON.stringify({
            sourceDate: params.sourceDate,
            targetDate: params.targetDate,
            contextUserId: params.contextUserId
        })
    });
}
