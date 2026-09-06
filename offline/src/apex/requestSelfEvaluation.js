import { makeDualApex } from './_wireAdapter.js';
import { plannerApiFetch } from './restHelper.js';

const API_VERSION = 'v62.0';

async function requestSelfEvaluation(params) {
    const eventId = params && (params.eventId || params.Id);
    if (!eventId) {
        throw new Error('eventId is required');
    }
    await plannerApiFetch(`/services/data/${API_VERSION}/sobjects/Coaching_Event__c/${eventId}`, {
        method: 'PATCH',
        body: JSON.stringify({ Status__c: 'Self Evaluation' })
    });
    return { success: true, eventId };
}

export default makeDualApex(requestSelfEvaluation);
