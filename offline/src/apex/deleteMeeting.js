import { plannerApiFetch } from './restHelper.js';

export default async function deleteMeeting(params = {}) {
    return plannerApiFetch('/services/apexrest/planner/v1/meetings/delete', {
        method: 'POST',
        body: JSON.stringify({ meetingId: params.meetingId })
    });
}