import { plannerApiFetch } from './restHelper.js';

export default async function updateMeeting(params = {}) {
    return plannerApiFetch('/services/apexrest/planner/v1/meetings/update', {
        method: 'POST',
        body: JSON.stringify({
            meetingId: params.meetingId,
            startDateTime: params.startDateTime,
            endDateTime: params.endDateTime,
            title: params.title
        })
    });
}
