import { makeDualApex } from './_wireAdapter.js';
import { plannerApiFetch } from './restHelper.js';
import { API_VERSION, apexError, esc, soql } from './learningShared.js';
import { computeCoachingScores } from './coachingFormShared.js';

async function saveEvaluation(params) {
    const eventId = params && (params.eventId || params.Id);
    const responsesJson = params && params.responsesJson;
    if (!eventId) {
        throw apexError('Event Id is required.');
    }
    if (String(eventId).startsWith('local_')) {
        throw apexError('This coaching event is still queued offline. Sync before saving scores.');
    }
    const events = await soql(
        'SELECT Id, Status__c, Coaching_Template__r.Questions_JSON__c ' +
            `FROM Coaching_Event__c WHERE Id = '${esc(eventId)}' LIMIT 1`,
        { fresh: true }
    );
    if (!events.length) {
        throw apexError('Coaching event not found.');
    }
    const templateJson = events[0].Coaching_Template__r?.Questions_JSON__c || '{}';
    const scores = computeCoachingScores(templateJson, responsesJson);
    const status =
        params.status ||
        (events[0].Status__c === 'Draft' || events[0].Status__c === 'Planned'
            ? 'Available for Scoring'
            : events[0].Status__c);
    const fields = {
        Responses_JSON__c: responsesJson,
        Manager_Total_Score__c: scores.managerTotalScore,
        Employee_Total_Score__c: scores.employeeTotalScore,
        Section_Scores_JSON__c: scores.sectionScoresJson
    };
    if (status) {
        fields.Status__c = status;
    }
    if (scores.recommendedActionPlan) {
        fields.Recommended_Action_Plan__c = scores.recommendedActionPlan;
    }
    await plannerApiFetch(`/services/data/${API_VERSION}/sobjects/Coaching_Event__c/${eventId}`, {
        method: 'PATCH',
        body: JSON.stringify(fields)
    });
    return {
        managerTotalScore: scores.managerTotalScore,
        employeeTotalScore: scores.employeeTotalScore,
        sectionScoresJson: scores.sectionScoresJson,
        responsesJson
    };
}

export default makeDualApex(saveEvaluation);
