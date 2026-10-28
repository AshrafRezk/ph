import { makeDualApex } from './_wireAdapter.js';
import { apexError } from './learningShared.js';
import { requireUnlockedVisit, createSObject } from './fieldWorkflowShared.js';
import getVisitSurveys from './getVisitSurveys.js';

function sentiment(value) {
    return value || 'Neutral';
}

export default makeDualApex(async (params = {}) => {
    const request = params.request || params;
    if (!String(request.productName || '').trim()) {
        throw apexError('Select a product.');
    }
    const visit = await requireUnlockedVisit(request.visitId);
    await createSObject('Visit_Product_Survey_Feedback__c', {
        Visit__c: visit.Id,
        Account__c: visit.Account__c || null,
        Assigned_Rep__c: visit.Assigned_To__c || null,
        Product_Name__c: String(request.productName).trim(),
        Efficacy_Sentiment__c: sentiment(request.efficacy),
        Safety_Sentiment__c: sentiment(request.safety),
        Indication_Sentiment__c: sentiment(request.indication),
        Side_Effects_Sentiment__c: sentiment(request.sideEffects),
        Usage_Sentiment__c: sentiment(request.usage),
        Visit_Feedback__c: request.notes || null,
        Submitted_At__c: new Date().toISOString(),
        Source__c: 'In-call Survey'
    });
    return getVisitSurveys({ visitId: visit.Id });
});
