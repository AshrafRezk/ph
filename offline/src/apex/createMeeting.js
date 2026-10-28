import { plannerApiFetch } from './restHelper.js';

export default async function createMeeting(params = {}) {
    return plannerApiFetch('/services/apexrest/planner/v1/meetings', {
        method: 'POST',
        body: JSON.stringify({
            recordTypeDeveloperName: params.recordTypeDeveloperName,
            startDateTime: params.startDateTime,
            endDateTime: params.endDateTime,
            title: params.title,
            pharmaProjectId: params.pharmaProjectId
        })
    });
}
