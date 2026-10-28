import { makeDualApex } from './_wireAdapter.js';
import {
    apexError,
    asNumber,
    mapQuizQuestion,
    parseQuizJson,
    requireOwnInstance
} from './learningShared.js';

const QUIZ_FIELDS =
    'Material__r.Passing_Score__c, Material__r.Quiz_Time_Limit_Minutes__c, ' +
    'Material__r.Max_Attempts__c, Material__r.Show_Results__c, Material__r.Quiz_Questions__c';

async function getQuizForTake(params) {
    const instanceId = params && (params.instanceId || params.Id);
    const inst = await requireOwnInstance(instanceId, QUIZ_FIELDS, { fresh: true });
    const material = inst.Material__r || {};
    if (material.Material_Type__c !== 'Quiz') {
        throw apexError('Material is not a quiz.');
    }
    const attemptNumber = asNumber(inst.Attempt_Number__c);
    const maxAttempts = material.Max_Attempts__c == null ? null : asNumber(material.Max_Attempts__c, null);
    const quiz = parseQuizJson(material.Quiz_Questions__c);
    const questions = Array.isArray(quiz.questions) ? quiz.questions.map(mapQuizQuestion) : [];
    return {
        instanceId: inst.Id,
        materialId: inst.Material__c,
        title: material.Title__c,
        passingScore: material.Passing_Score__c == null ? 70 : asNumber(material.Passing_Score__c, 70),
        timeLimitMinutes: material.Quiz_Time_Limit_Minutes__c,
        maxAttempts,
        attemptNumber,
        showResults: material.Show_Results__c === true,
        canAttempt:
            inst.Status__c !== 'Completed' && (maxAttempts == null || attemptNumber < maxAttempts),
        status: inst.Status__c,
        lastScore: inst.Score__c,
        questions
    };
}

export default makeDualApex(getQuizForTake);
