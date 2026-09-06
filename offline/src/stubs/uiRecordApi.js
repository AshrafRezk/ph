import { plannerApiFetch } from '../apex/restHelper.js';
import { makeDualApex } from '../apex/_wireAdapter.js';

const API_VERSION = 'v62.0';

// @wire(getRecord, { recordId, fields }) adapter. Resolves the requested fields
// via a read-only SOQL query and shapes the result like uiRecordApi's getRecord
// so getFieldValue works (record.fields[api].value).
async function loadRecord(config) {
    if (!config || !config.recordId || !Array.isArray(config.fields) || !config.fields.length) {
        return undefined;
    }
    const refs = config.fields
        .map((f) => (typeof f === 'string' ? f : f && f.fieldApiName))
        .filter(Boolean);
    if (!refs.length) {
        return undefined;
    }
    const objectApiName = refs[0].split('.')[0];
    const fieldNames = refs.map((r) => r.split('.').slice(1).join('.')).filter(Boolean);
    const select = ['Id', ...fieldNames].join(', ');
    const path = `/services/data/${API_VERSION}/query?q=${encodeURIComponent(
        `SELECT ${select} FROM ${objectApiName} WHERE Id = '${config.recordId}' LIMIT 1`
    )}`;
    const result = await plannerApiFetch(path);
    const rows = result && Array.isArray(result.records) ? result.records : [];
    if (!rows.length) {
        throw { status: 404, body: { message: 'Record not found.' } };
    }
    const row = rows[0];
    const fields = {};
    fieldNames.forEach((fn) => {
        fields[fn] = { value: row[fn] !== undefined ? row[fn] : null };
    });
    return { id: row.Id, apiName: objectApiName, fields };
}

export const getRecord = makeDualApex(loadRecord);

// Extract a field value from a getRecord result, tolerant of our empty shape and
// of both string field names and @salesforce/schema field references.
export function getFieldValue(record, field) {
    if (!record || !record.fields) {
        return undefined;
    }
    const apiName = field && field.fieldApiName
        ? String(field.fieldApiName).split('.').pop()
        : field;
    const entry = record.fields[apiName];
    return entry ? entry.value : undefined;
}

function fieldValue(fields, apiName) {
    if (!fields || !apiName) {
        return undefined;
    }
    if (Object.prototype.hasOwnProperty.call(fields, apiName)) {
        return fields[apiName];
    }
    // Tolerate fully-qualified keys like Time_Off_Request__c.Type__c
    const short = String(apiName).includes('.') ? String(apiName).split('.').pop() : apiName;
    if (Object.prototype.hasOwnProperty.call(fields, short)) {
        return fields[short];
    }
    const qualified = Object.keys(fields).find((key) => key === apiName || key.endsWith(`.${short}`));
    return qualified ? fields[qualified] : undefined;
}

function mapTimeOffCreateBody(fields) {
    return {
        typeValue: fieldValue(fields, 'Type__c'),
        spanType: fieldValue(fields, 'Span_Type__c'),
        durationHours: fieldValue(fields, 'Span_Duration_Select__c'),
        startDateTime: fieldValue(fields, 'Start_Date_Time__c'),
        comments: fieldValue(fields, 'Comments__c'),
        stage: fieldValue(fields, 'Stage__c')
    };
}

export async function createRecord(recordInput) {
    const { apiName, fields } = recordInput || {};
    if (apiName && apiName !== 'Time_Off_Request__c') {
        throw {
            body: { message: `createRecord is only supported for Time_Off_Request__c (got ${apiName}).` }
        };
    }
    const result = await plannerApiFetch('/services/apexrest/planner/v1/time-off', {
        method: 'POST',
        body: JSON.stringify(mapTimeOffCreateBody(fields || {}))
    });
    const id = result?.id || result?.Id || `tmp_${Date.now()}`;
    return { id, success: true, ...result };
}

export async function updateRecord(recordInput) {
    const { apiName, fields, recordId } = recordInput;
    const result = await plannerApiFetch(`/services/apexrest/planner/v1/time-off/${recordId}`, {
        method: 'PATCH',
        body: JSON.stringify({ apiName, fields })
    });
    return result || { id: recordId, success: true };
}

export async function deleteRecord(recordId) {
    await plannerApiFetch(`/services/apexrest/planner/v1/time-off/${recordId}`, {
        method: 'DELETE'
    });
    return { success: true };
}

/** Offline no-op — there is no Lightning Data Service cache to invalidate. */
export function getRecordNotifyChange(_recordIds) {
    return undefined;
}

export function notifyRecordUpdateAvailable(_recordIds) {
    return Promise.resolve();
}
