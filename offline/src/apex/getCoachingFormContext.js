import { makeDualApex } from './_wireAdapter.js';
import { plannerApiFetch } from './restHelper.js';

const API_VERSION = 'v62.0';

async function soql(query) {
    const path = `/services/data/${API_VERSION}/query?q=${encodeURIComponent(query)}`;
    const result = await plannerApiFetch(path);
    return result && Array.isArray(result.records) ? result.records : [];
}

async function loadCoachingFormContext(params) {
    const visitId = params && (params.visitId || params.Id);
    if (!visitId) {
        throw { body: { message: 'Visit Id is required.' } };
    }
    const visits = await soql(
        'SELECT Id, Name, Visit_Objective__c, Visit_Notes__c, Is_Double_Visit__c, Coaching_Event__c, ' +
            'Coaching_Event__r.Status__c, Account__r.Name, Assigned_To__c, Assigned_To__r.Name, ' +
            'Assigned_To__r.ManagerId, Assigned_To__r.Manager.Name ' +
            `FROM Visit__c WHERE Id = '${visitId}' LIMIT 1`
    );
    if (!visits.length) {
        throw { body: { message: 'Visit not found.' } };
    }
    const visit = visits[0];
    const assigned = visit.Assigned_To__r || {};
    const templates = await soql(
        'SELECT Id, Template_Title__c, Template_Type__c FROM Coaching_Template__c ' +
            'WHERE Is_Active__c = true ORDER BY Template_Title__c'
    );
    return {
        visitId: visit.Id,
        visitName: visit.Name,
        accountName: visit.Account__r ? visit.Account__r.Name : null,
        visitObjective: visit.Visit_Objective__c,
        visitNotes: visit.Visit_Notes__c,
        employeeId: visit.Assigned_To__c,
        employeeName: assigned.Name || null,
        managerId: assigned.ManagerId || null,
        managerName: assigned.Manager ? assigned.Manager.Name : null,
        isDoubleVisit: visit.Is_Double_Visit__c === true,
        coachingEventId: visit.Coaching_Event__c || null,
        coachingEventStatus: visit.Coaching_Event__r ? visit.Coaching_Event__r.Status__c : null,
        templates: templates.map((row) => ({
            id: row.Id,
            title: row.Template_Title__c,
            templateType: row.Template_Type__c
        }))
    };
}

export default makeDualApex(loadCoachingFormContext);
