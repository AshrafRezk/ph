import { plannerApiFetch } from './restHelper.js';

export default async function rescheduleVisits(params = {}) {
    const starts = params.startDateTimes || params.starts || [];
    const ends = params.endDateTimes || params.ends || [];
    const moves = (params.visitIds || []).map((id, idx) => ({
        visitId: id,
        startDateTime: starts[idx] ?? null,
        endDateTime: ends[idx] ?? null
    }));
    return plannerApiFetch('/services/apexrest/planner/v1/mutate/visits/reschedule', {
        method: 'POST',
        body: JSON.stringify({ moves })
    });
}
