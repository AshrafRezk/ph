import { plannerApiFetch } from './restHelper.js';

const PATH = '/services/apexrest/class-engine/v1/approve';

export default async function approveCycle(params = {}) {
    return plannerApiFetch(PATH, {
        method: 'POST',
        body: JSON.stringify({
            cycleId: params.cycleId || null,
            managerOverrides: params.managerOverrides || []
        })
    });
}
