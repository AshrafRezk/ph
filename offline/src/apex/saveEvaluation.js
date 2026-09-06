import { makeDualApex } from './_wireAdapter.js';
import { plannerApiFetch } from './restHelper.js';

const API_VERSION = 'v62.0';

async function saveEvaluation(params) {
    const eventId = params && (params.eventId || params.Id);
    if (!eventId) {
        throw new Error('eventId is required');
    }
    const fields = {};
    if (params.managerResponsesJson != null) fields.Manager_Responses__c = params.managerResponsesJson;
    if (params.employeeResponsesJson != null) fields.Employee_Responses__c = params.employeeResponsesJson;
    if (params.managerScore != null) fields.Manager_Score__c = params.managerScore;
    if (params.employeeScore != null) fields.Employee_Score__c = params.employeeScore;
    await plannerApiFetch(`/services/data/${API_VERSION}/sobjects/Coaching_Event__c/${eventId}`, {
        method: 'PATCH',
        body: JSON.stringify(fields)
    });
    return { success: true, eventId };
}

export default makeDualApex(saveEvaluation);
