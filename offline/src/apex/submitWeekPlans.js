import { plannerApiFetch } from './restHelper.js';

export default async function submitWeekPlans(params = {}) {
    return plannerApiFetch('/services/apexrest/planner/v1/visits/submit-week', {
        method: 'POST',
        body: JSON.stringify({
            weekStart: params.weekStart,
            weekEnd: params.weekEnd
        })
    });
}
