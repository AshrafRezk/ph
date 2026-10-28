import { plannerApiFetch } from './restHelper.js';

export default async function rejectMeetingPlan(params = {}) {
    return plannerApiFetch('/services/apexrest/planner/v1/meetings/reject', {
        method: 'POST',
        body: JSON.stringify({
            meetingId: params.meetingId,
            rejectionReason: params.rejectionReason || ''
        })
    });
}
