import { plannerApiFetch } from './restHelper.js';

const API_VERSION = 'v62.0';

/**
 * Load the current user's recent time-off requests.
 * Prefer Apex REST when available; fall back to SOQL so PWA works even if
 * GET /planner/v1/time-off is not yet deployed to the org.
 */
export default async function getMyRequests(params = {}) {
    const limitSize = Math.min(Math.max(Number(params.limitSize) || 10, 1), 50);
    try {
        const data = await plannerApiFetch(
            `/services/apexrest/planner/v1/time-off?limitSize=${encodeURIComponent(limitSize)}`,
            { method: 'GET' }
        );
        if (Array.isArray(data)) {
            return data;
        }
        if (data && Array.isArray(data.records)) {
            return data.records;
        }
    } catch (_apexError) {
        // Fall through to SOQL.
    }

    const soql = [
        'SELECT Id, Name, Type__c, Span_Type__c, Working_Day_Equivalent__c,',
        'Start_Date__c, End_Date__c, Stage__c, CreatedDate',
        'FROM Time_Off_Request__c',
        `WHERE CreatedById = '${await resolveCurrentUserId()}'`,
        'ORDER BY CreatedDate DESC',
        `LIMIT ${limitSize}`
    ].join(' ');

    const result = await plannerApiFetch(
        `/services/data/${API_VERSION}/query?q=${encodeURIComponent(soql)}`
    );
    const rows = result && Array.isArray(result.records) ? result.records : [];
    return rows.map((row) => ({
        id: row.Id,
        name: row.Name,
        typeLabel: row.Type__c,
        spanType: row.Span_Type__c,
        workingDays: row.Working_Day_Equivalent__c,
        startDate: row.Start_Date__c,
        endDate: row.End_Date__c,
        stage: row.Stage__c,
        createdDate: row.CreatedDate
    }));
}

async function resolveCurrentUserId() {
    try {
        const identity = await plannerApiFetch('/services/oauth2/userinfo');
        if (identity && identity.user_id) {
            return String(identity.user_id);
        }
    } catch (_error) {
        // ignore
    }
    try {
        const me = await plannerApiFetch(`/services/data/${API_VERSION}/chatter/users/me`);
        if (me && me.id) {
            return String(me.id);
        }
    } catch (_error) {
        // ignore
    }
    throw { body: { message: 'Unable to resolve current user for time-off list.' } };
}
