import { makeDualApex } from './_wireAdapter.js';
import {
    apexError,
    asNumber,
    esc,
    findCourseInstanceId,
    isAnswerCorrect,
    nowIso,
    parseQuizJson,
    patchLearningInstance,
    requireOwnInstance,
    rollupCourseProgress,
    soqlOne
} from './learningShared.js';

const QUIZ_FIELDS =
    'Material__r.Passing_Score__c, Material__r.Quiz_Time_Limit_Minutes__c, ' +
    'Material__r.Max_Attempts__c, Material__r.Show_Results__c, Material__r.Quiz_Questions__c';

function parseAnswers(answersJson) {
    if (!answersJson) {
        return {};
    }
    if (typeof answersJson === 'object') {
        return answersJson;
    }
    try {
        const parsed = JSON.parse(answersJson);
        return parsed && typeof parsed === 'object' ? parsed : {};
    } catch (_err) {
        return {};
    }
}

async function submitQuiz(params) {
    const instanceId = params && (params.instanceId || params.Id);
    const inst = await requireOwnInstance(instanceId, QUIZ_FIELDS, { fresh: true });
    const material = inst.Material__r || {};
    if (material.Material_Type__c !== 'Quiz') {
        throw apexError('Material is not a quiz.');
    }
    const attemptNumber = asNumber(inst.Attempt_Number__c);
    const maxAttempts = material.Max_Attempts__c == null ? null : asNumber(material.Max_Attempts__c, null);
    if (inst.Status__c === 'Completed') {
        throw apexError('This quiz is already completed.');
    }
    if (maxAttempts != null && attemptNumber >= maxAttempts) {
        throw apexError('Maximum attempts reached.');
    }

    const answers = parseAnswers(params && params.answersJson);
    const quiz = parseQuizJson(material.Quiz_Questions__c);
    const questions = Array.isArray(quiz.questions) ? quiz.questions : [];
    let earned = 0;
    let total = 0;
    const questionResults = {};
    questions.forEach((question) => {
        const qid = question.id;
        const points = asNumber(question.points, 1);
        total += points;
        const correct = isAnswerCorrect(question, answers[qid]);
        if (correct) {
            earned += points;
        }
        questionResults[qid] = {
            correct,
            correctAnswer: question.correctAnswer != null ? question.correctAnswer : question.correctAnswers,
            explanation: question.explanation,
            points,
            earned: correct ? points : 0
        };
    });

    const scorePct = total > 0 ? Math.round((earned / total) * 1000) / 10 : 0;
    const passing = material.Passing_Score__c == null ? 70 : asNumber(material.Passing_Score__c, 70);
    const passed = scorePct >= passing;
    const fields = {
        Attempt_Number__c: attemptNumber + 1,
        Score__c: scorePct,
        Time_Taken_Minutes__c: asNumber(params && params.timeTakenMinutes, 0.1)
    };
    if (!inst.Started_On__c) {
        fields.Started_On__c = nowIso();
    }
    if (passed) {
        fields.Status__c = 'Completed';
        fields.Progress__c = 100;
        fields.Completed_On__c = nowIso();
    } else {
        fields.Status__c = 'In Progress';
        fields.Progress__c = scorePct;
    }
    await patchLearningInstance(inst.Id, fields);

    const courseInstanceId = await findCourseInstanceId(inst);
    const courseProgress = await rollupCourseProgress(courseInstanceId);
    const courseInst = await soqlOne(
        'SELECT Status__c, Material__r.Issue_Certificate__c FROM Learning_Material_Instance__c ' +
            `WHERE Id = '${esc(courseInstanceId)}' LIMIT 1`,
        { fresh: true }
    );
    const courseStatus = (courseInst && courseInst.Status__c) || 'In Progress';
    const issueCertificate = !!(courseInst && courseInst.Material__r && courseInst.Material__r.Issue_Certificate__c);
    const showResults = material.Show_Results__c === true;
    return {
        score: scorePct,
        earnedPoints: earned,
        totalPoints: total,
        passed,
        showResults,
        status: passed ? 'Completed' : 'In Progress',
        courseProgress,
        courseCompleted: courseStatus === 'Completed',
        canShowCertificate: issueCertificate && courseStatus === 'Completed',
        questionResults: showResults ? questionResults : null
    };
}

export default makeDualApex(submitQuiz);
