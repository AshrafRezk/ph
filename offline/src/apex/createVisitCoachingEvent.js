import { makeDualApex } from './_wireAdapter.js';
import { plannerApiFetch } from './restHelper.js';
import { API_VERSION, apexError, currentUserId, esc, soql } from './learningShared.js';
import { buildCoachingResponses, readCreatedCoachingEventId } from './coachingFormShared.js';

async function loadVisit(visitId) {
    const visits = await soql(
        'SELECT Id, Name, Visit_Objective__c, Visit_Notes__c, Is_Double_Visit__c, Coaching_Event__c, ' +
            'Account__r.Name, Assigned_To__c, Assigned_To__r.Name, Assigned_To__r.ManagerId, Assigned_To__r.Manager.Name ' +
            `FROM Visit__c WHERE Id = '${esc(visitId)}' LIMIT 1`,
        { fresh: true }
    );
    return visits[0] || null;
}

async function resolveManager(visit, employeeId) {
    const assigned = visit.Assigned_To__r || {};
    let managerId = assigned.ManagerId || null;
    let managerName = assigned.Manager ? assigned.Manager.Name : null;
    const viewerId = currentUserId();
    if (!managerId && viewerId && viewerId !== employeeId) {
        managerId = viewerId;
        const users = await soql(`SELECT Id, Name FROM User WHERE Id = '${esc(viewerId)}' LIMIT 1`);
        managerName = users[0]?.Name || managerName;
    }
    return { managerId, managerName };
}

async function linkVisit(visitId, coachingEventId) {
    const path = `/services/data/${API_VERSION}/sobjects/Visit__c/${visitId}`;
    try {
        await plannerApiFetch(path, {
            method: 'PATCH',
            body: JSON.stringify({
                Coaching_Event__c: coachingEventId,
                Is_Double_Visit__c: true
            })
        });
    } catch (_flagError) {
        await plannerApiFetch(path, {
            method: 'PATCH',
            body: JSON.stringify({
                Coaching_Event__c: coachingEventId
            })
        });
    }
}

async function createVisitCoachingEvent(params) {
    const visitId = params && (params.visitId || params.Id);
    const templateId = params && params.templateId;
    const prefillFromVisit = params?.prefillFromVisit === true;
    if (!visitId) {
        throw apexError('Visit Id is required.');
    }
    if (!templateId) {
        throw apexError('Select a coaching template.');
    }

    const visit = await loadVisit(visitId);
    if (!visit) {
        throw apexError('Visit not found.');
    }
    if (visit.Coaching_Event__c) {
        throw apexError('This visit already has a coaching event.');
    }

    const employeeId = visit.Assigned_To__c || currentUserId();
    const manager = await resolveManager(visit, employeeId);
    if (!manager.managerId) {
        throw apexError('No manager could be resolved for this visit.');
    }

    const templates = await soql(
        'SELECT Id, Questions_JSON__c FROM Coaching_Template__c ' +
            `WHERE Id = '${esc(templateId)}' AND Is_Active__c = true LIMIT 1`,
        { fresh: true }
    );
    if (!templates.length) {
        throw apexError('Coaching template not found or inactive.');
    }

    const context = {
        accountName: visit.Account__r ? visit.Account__r.Name : null,
        visitObjective: visit.Visit_Objective__c,
        visitNotes: visit.Visit_Notes__c
    };
    const responsesJson = buildCoachingResponses(
        templates[0].Questions_JSON__c,
        context,
        prefillFromVisit
    );
    const start = new Date();
    const end = new Date(start.getTime() + 24 * 60 * 60 * 1000);
    const created = await plannerApiFetch(`/services/data/${API_VERSION}/sobjects/Coaching_Event__c`, {
        method: 'POST',
        body: JSON.stringify({
            Coaching_Template__c: templateId,
            Employee__c: employeeId,
            Manager__c: manager.managerId,
            Visit__c: visitId,
            Status__c: 'Draft',
            Event_Start__c: start.toISOString(),
            Event_End__c: end.toISOString(),
            Responses_JSON__c: responsesJson
        })
    });
    const coachingEventId = readCreatedCoachingEventId(created);
    if (!coachingEventId) {
        throw apexError('Coaching event was not created.');
    }

    await linkVisit(visitId, coachingEventId);

    const selections = Array.isArray(params.visitSelections) ? params.visitSelections : [];
    const visitIds = new Set([visitId]);
    selections.forEach((row) => {
        if (row?.visitId) {
            visitIds.add(row.visitId);
        }
    });
    for (const selectedId of visitIds) {
        if (selectedId === visitId) {
            continue;
        }
        try {
            await plannerApiFetch(`/services/data/${API_VERSION}/sobjects/Visit__c/${selectedId}`, {
                method: 'PATCH',
                body: JSON.stringify({
                    Coaching_Event__c: coachingEventId,
                    Is_Double_Visit__c: true
                })
            });
        } catch (_error) {
            /* the origin visit is already linked; extra visits are best effort */
        }
    }

    return {
        coachingEventId,
        status: 'Draft',
        responsesJson,
        visitCount: visitIds.size
    };
}

export default makeDualApex(createVisitCoachingEvent);
