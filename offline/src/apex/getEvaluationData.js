import { makeDualApex } from './_wireAdapter.js';
import { plannerApiFetch } from './restHelper.js';
import { currentUserId, esc, soql } from './learningShared.js';

function escId(value) {
    return esc(value);
}

async function getEvaluationData(config) {
    const eventId = config && (config.eventId || config.recordId || config.Id);
    if (!eventId) {
        throw Object.assign(new Error('Event Id is required.'), { body: { message: 'Event Id is required.' } });
    }
    if (String(eventId).startsWith('local_')) {
        throw Object.assign(new Error('This coaching event is still queued offline. Connect and sync to score it.'), {
            body: { message: 'This coaching event is still queued offline. Connect and sync to score it.' }
        });
    }
    const events = await soql(
        'SELECT Id, Employee__c, Manager__c, Status__c, Responses_JSON__c, ' +
            'Manager_Total_Score__c, Employee_Total_Score__c, Previous_Score__c, ' +
            'Section_Scores_JSON__c, Self_Evaluation_Requested__c, Self_Evaluation_Completed__c, ' +
            'Coaching_Template__r.Questions_JSON__c ' +
            `FROM Coaching_Event__c WHERE Id = '${escId(eventId)}' LIMIT 1`,
        { fresh: true }
    );
    const event = events[0];
    if (!event) {
        throw Object.assign(new Error('Coaching event not found.'), {
            body: { message: 'Coaching event not found.' }
        });
    }
    const template = event.Coaching_Template__r || {};
    const me = currentUserId();
    let userRole = 'admin';
    if (me && event.Manager__c === me) {
        userRole = 'manager';
    } else if (me && event.Employee__c === me) {
        userRole = 'employee';
    }
    let previousScore = event.Previous_Score__c;
    if (previousScore == null && event.Employee__c) {
        try {
            const prior = await soql(
                'SELECT Manager_Total_Score__c FROM Coaching_Event__c ' +
                    `WHERE Employee__c = '${escId(event.Employee__c)}' ` +
                    "AND Status__c IN ('Closed','Completed') " +
                    `AND Id != '${escId(event.Id)}' AND Manager_Total_Score__c != null ` +
                    'ORDER BY Event_End__c DESC NULLS LAST LIMIT 1'
            );
            previousScore = prior[0] ? prior[0].Manager_Total_Score__c : null;
        } catch (_error) {
            previousScore = null;
        }
    }
    return {
        templateJson: template.Questions_JSON__c || '{"questions":[]}',
        responsesJson: event.Responses_JSON__c || '{"version":"1.0","answers":[]}',
        sectionScoresJson: event.Section_Scores_JSON__c || null,
        managerTotalScore: event.Manager_Total_Score__c,
        employeeTotalScore: event.Employee_Total_Score__c,
        previousScore,
        status: event.Status__c,
        employeeId: event.Employee__c,
        managerId: event.Manager__c,
        selfEvaluationRequested: event.Self_Evaluation_Requested__c === true,
        selfEvaluationCompleted: event.Self_Evaluation_Completed__c === true,
        userRole,
        currentUserId: me || null
    };
}

export default makeDualApex(getEvaluationData);
