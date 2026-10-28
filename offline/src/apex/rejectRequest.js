import { plannerApiFetch } from './restHelper.js';

export default async function rejectRequest(params = {}) {
    return plannerApiFetch('/services/apexrest/planner/v1/time-off/reject', {
        method: 'POST',
        body: JSON.stringify({
            requestId: params.requestId,
            rejectionReason: params.rejectionReason || ''
        })
    });
}
