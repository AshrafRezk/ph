import { plannerApiFetch } from './restHelper.js';

export default async function approveMeetingPlan(params = {}) {
    return plannerApiFetch('/services/apexrest/planner/v1/meetings/approve', {
        method: 'POST',
        body: JSON.stringify({ meetingId: params.meetingId })
    });
}
