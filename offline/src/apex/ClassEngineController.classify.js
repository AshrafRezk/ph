import { plannerApiFetch } from './restHelper.js';

const PATH = '/services/apexrest/class-engine/v1/classify';

export default async function classify(params = {}) {
    return plannerApiFetch(PATH, {
        method: 'POST',
        body: JSON.stringify({
            employeeId: params.employeeId || null,
            quarter: params.quarter || null
        })
    });
}
