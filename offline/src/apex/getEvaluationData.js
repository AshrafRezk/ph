import { makeDualApex } from './_wireAdapter.js';
import { plannerApiFetch } from './restHelper.js';

const API_VERSION = 'v62.0';

async function soql(query) {
    const path = `/services/data/${API_VERSION}/query?q=${encodeURIComponent(query)}`;
    const result = await plannerApiFetch(path);
    return result && Array.isArray(result.records) ? result.records : [];
}

function esc(value) {
    return String(value || '').replace(/'/g, "\\'");
}

async function getEvaluationData(config) {
    const eventId = config && (config.eventId || config.recordId || config.Id);
    if (!eventId) {
        return {
            eventId: null,
            status: null,
            userRole: 'viewer',
            managerScore: null,
            employeeScore: null,
            previousScore: null,
            questions: [],
            managerResponsesJson: null,
            employeeResponsesJson: null,
            canRequestSelfEval: false,
            canEdit: false
        };
    }
    const events = await soql(
        'SELECT Id, Name, Status__c, Manager_Score__c, Employee_Score__c, Previous_Score__c,' +
            ' Manager_Responses__c, Employee_Responses__c, Coaching_Template__c,' +
            ' Coaching_Template__r.Name' +
            ` FROM Coaching_Event__c WHERE Id = '${esc(eventId)}' LIMIT 1`
    );
    const event = events[0] || {};
    let questions = [];
    const templateId = event.Coaching_Template__c;
    if (templateId) {
        try {
            questions = await soql(
                'SELECT Id, Name, Label__c, Section__c, Sort_Order__c, Question_Type__c,' +
                    ' Scale_Points_JSON__c' +
                    ' FROM Coaching_Template_Question__c' +
                    ` WHERE Coaching_Template__c = '${esc(templateId)}'` +
                    ' ORDER BY Sort_Order__c, Name'
            );
        } catch (_err) {
            questions = [];
        }
    }
    return {
        eventId: event.Id || eventId,
        status: event.Status__c || null,
        userRole: 'manager',
        managerScore: event.Manager_Score__c,
        employeeScore: event.Employee_Score__c,
        previousScore: event.Previous_Score__c,
        questions: questions.map((q) => {
            let scalePoints = [];
            try {
                scalePoints = q.Scale_Points_JSON__c ? JSON.parse(q.Scale_Points_JSON__c) : [];
            } catch (_err) {
                scalePoints = [];
            }
            return {
                id: q.Id,
                label: q.Label__c || q.Name,
                section: q.Section__c || 'General',
                sortOrder: q.Sort_Order__c || 0,
                type: (q.Question_Type__c || 'scale').toLowerCase(),
                scalePoints
            };
        }),
        managerResponsesJson: event.Manager_Responses__c || null,
        employeeResponsesJson: event.Employee_Responses__c || null,
        canRequestSelfEval: true,
        canEdit: true,
        templateName: event.Coaching_Template__r?.Name || null
    };
}

export default makeDualApex(getEvaluationData);
