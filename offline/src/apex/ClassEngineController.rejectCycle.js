import { plannerApiFetch } from './restHelper.js';

const PATH = '/services/apexrest/class-engine/v1/reject';

export default async function rejectCycle(params = {}) {
    return plannerApiFetch(PATH, {
        method: 'POST',
        body: JSON.stringify({
            cycleId: params.cycleId || null,
            reason: params.reason || null
        })
    });
}
