import { plannerApiFetch } from './restHelper.js';
import { API_VERSION, soql, soqlOne, esc, apexError } from './learningShared.js';

export { API_VERSION, soql, soqlOne, esc, apexError, plannerApiFetch };

export async function requireVisit(visitId, extraFields = '') {
    if (!visitId) {
        throw apexError('Visit Id is required.');
    }
    const fields = [
        'Id',
        'Name',
        'Status__c',
        'Account__c',
        'Account__r.Name',
        'Assigned_To__c',
        extraFields
    ]
        .filter(Boolean)
        .join(', ');
    const visit = await soqlOne(
        `SELECT ${fields} FROM Visit__c WHERE Id = '${esc(visitId)}' LIMIT 1`,
        { fresh: true }
    );
    if (!visit) {
        throw apexError('Visit not found.');
    }
    return visit;
}

export function visitLocked(visit) {
    return visit?.Status__c === 'Completed' || visit?.Status__c === 'Cancelled';
}

export async function requireUnlockedVisit(visitId, extraFields) {
    const visit = await requireVisit(visitId, extraFields);
    if (visitLocked(visit)) {
        throw apexError('Completed or cancelled visits cannot be edited.');
    }
    return visit;
}

export async function productOptions() {
    const rows = await soql(
        "SELECT Id, Name FROM Product2 WHERE IsActive = true ORDER BY Name LIMIT 200"
    );
    return rows.map((row) => ({
        productId: row.Id,
        productName: row.Name,
        label: row.Name,
        value: row.Id
    }));
}

export async function createSObject(apiName, payload) {
    const created = await plannerApiFetch(`/services/data/${API_VERSION}/sobjects/${apiName}`, {
        method: 'POST',
        body: JSON.stringify(payload)
    });
    if (!created?.id) {
        throw apexError('Unable to save.');
    }
    return created.id;
}

export async function updateSObject(apiName, id, payload) {
    await plannerApiFetch(`/services/data/${API_VERSION}/sobjects/${apiName}/${id}`, {
        method: 'PATCH',
        body: JSON.stringify(payload)
    });
}

export async function deleteSObject(apiName, id) {
    await plannerApiFetch(`/services/data/${API_VERSION}/sobjects/${apiName}/${id}`, {
        method: 'DELETE'
    });
}

export const SENTIMENT_OPTIONS = [
    { label: 'Positive', value: 'Positive' },
    { label: 'Neutral', value: 'Neutral' },
    { label: 'Negative', value: 'Negative' }
];

export const CHANGE_TYPE_OPTIONS = [
    { label: 'Name', value: 'Name' },
    { label: 'Address', value: 'Address' },
    { label: 'Phone', value: 'Phone' },
    { label: 'Email', value: 'Email' },
    { label: 'Specialty', value: 'Specialty' },
    { label: 'Other', value: 'Other' }
];
