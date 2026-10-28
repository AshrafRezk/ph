import { makeDualApex } from './_wireAdapter.js';
import { plannerApiFetch } from './restHelper.js';

const API_VERSION = 'v62.0';

function asSalesforceId(value) {
    const id = String(value || '');
    return /^[a-zA-Z0-9]{15}$|^[a-zA-Z0-9]{18}$/.test(id) ? id : null;
}

async function soql(query) {
    const path = `/services/data/${API_VERSION}/query?q=${encodeURIComponent(query)}`;
    const result = await plannerApiFetch(path);
    return result && Array.isArray(result.records) ? result.records : [];
}

function mapSession(row) {
    const presentation = row.CLM_Presentation__r || {};
    return {
        id: row.Id || row.id,
        visitId: row.Visit__c || row.visitId,
        presentationId: row.CLM_Presentation__c || row.presentationId || presentation.Id,
        presentationName: presentation.Name || row.presentationName || row.Name || row.name || 'Presentation',
        status: row.Status__c || row.status || 'Active',
        totalDurationSeconds: row.Total_Duration_Seconds__c ?? row.totalDurationSeconds ?? 0,
        slidesPresentedCount: row.Slides_Presented_Count__c ?? row.slidesPresentedCount ?? 0,
        slideCount: presentation.Slide_Count__c ?? row.slideCount ?? 0
    };
}

async function loadVisitSessions(config = {}) {
    const visitId = asSalesforceId(config.visitId);
    if (!visitId) {
        return [];
    }
    try {
        const rest = await plannerApiFetch(`/services/apexrest/clm/v1/visits/${visitId}/sessions`);
        if (Array.isArray(rest)) {
            return rest.map(mapSession);
        }
    } catch (_error) {
        /* REST may not be deployed yet — fall through to SOQL */
    }
    const rows = await soql(
        'SELECT Id, Name, Status__c, Started_At__c, Ended_At__c, Total_Duration_Seconds__c, ' +
            'Slides_Presented_Count__c, Visit__c, CLM_Presentation__c, CLM_Presentation__r.Name, ' +
            'CLM_Presentation__r.Slide_Count__c FROM CLM_Presentation_Session__c ' +
            `WHERE Visit__c = '${visitId}' ORDER BY Started_At__c DESC NULLS LAST`
    );
    return rows.map(mapSession);
}

export default makeDualApex(loadVisitSessions);
