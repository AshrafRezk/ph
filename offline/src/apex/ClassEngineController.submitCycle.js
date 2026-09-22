import { plannerApiFetch } from './restHelper.js';

const PATH = '/services/apexrest/class-engine/v1/submit';

export default async function submitCycle(params = {}) {
    return plannerApiFetch(PATH, {
        method: 'POST',
        body: JSON.stringify({
            cycleId: params.cycleId || null,
            quarter: params.quarter || null
        })
    });
}
