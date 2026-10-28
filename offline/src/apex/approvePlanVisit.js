import { plannerApiFetch } from './restHelper.js';

export default async function approvePlanVisit(params = {}) {
    return plannerApiFetch('/services/apexrest/planner/v1/visits/approve', {
        method: 'POST',
        body: JSON.stringify({ visitId: params.visitId })
    });
}
