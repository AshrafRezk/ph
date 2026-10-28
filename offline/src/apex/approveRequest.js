import { plannerApiFetch } from './restHelper.js';

export default async function approveRequest(params = {}) {
    return plannerApiFetch('/services/apexrest/planner/v1/time-off/approve', {
        method: 'POST',
        body: JSON.stringify({ requestId: params.requestId })
    });
}
