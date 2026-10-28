import { plannerApiFetch } from './restHelper.js';

export default async function submitVisit(params = {}) {
    return plannerApiFetch('/services/apexrest/planner/v1/visits/submit', {
        method: 'POST',
        body: JSON.stringify({ visitId: params.visitId })
    });
}
