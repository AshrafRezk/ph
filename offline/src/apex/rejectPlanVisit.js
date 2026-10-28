import { plannerApiFetch } from './restHelper.js';

export default async function rejectPlanVisit(params = {}) {
    return plannerApiFetch('/services/apexrest/planner/v1/visits/reject', {
        method: 'POST',
        body: JSON.stringify({
            visitId: params.visitId,
            rejectionReason: params.rejectionReason || ''
        })
    });
}
