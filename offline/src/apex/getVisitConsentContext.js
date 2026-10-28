import { makeDualApex } from './_wireAdapter.js';
import { plannerApiFetch } from './restHelper.js';
import { esc } from './learningShared.js';

const API_VERSION = 'v62.0';

const CHANNELS = [
    { label: 'Visit', value: 'Visit' },
    { label: 'Samples', value: 'Samples' },
    { label: 'Email', value: 'Email' },
    { label: 'Phone', value: 'Phone' },
    { label: 'SMS', value: 'SMS' },
    { label: 'Remote', value: 'Remote' }
];

const CONSENT_TYPES = [
    { label: 'Detailing', value: 'Detailing' },
    { label: 'Samples', value: 'Samples' },
    { label: 'Contact Preferences', value: 'Contact Preferences' },
    { label: 'Privacy', value: 'Privacy' }
];

const STATUSES = [
    { label: 'Granted', value: 'Granted' },
    { label: 'Withdrawn', value: 'Withdrawn' }
];

async function soql(query, options = {}) {
    const path = `/services/data/${API_VERSION}/query?q=${encodeURIComponent(query)}`;
    const result = await plannerApiFetch(path, options.fresh ? { fresh: true } : {});
    return result && Array.isArray(result.records) ? result.records : [];
}

async function getVisitConsentContext(params = {}) {
    const visitId = params.visitId;
    if (!visitId) {
        const error = new Error('Visit Id is required.');
        error.body = { message: error.message };
        throw error;
    }
    const visits = await soql(
        `SELECT Id, Name, Status__c, Account__c, Account__r.Name FROM Visit__c WHERE Id = '${esc(visitId)}' LIMIT 1`,
        { fresh: true }
    );
    if (!visits.length) {
        const error = new Error('Visit not found.');
        error.body = { message: error.message };
        throw error;
    }
    const visit = visits[0];
    const consents = await soql(
        'SELECT Id, Name, Channel__c, Consent_Type__c, Status__c, Captured_At__c, Signature_Data__c, Notes__c ' +
            `FROM Visit_Consent__c WHERE Visit__c = '${esc(visitId)}' ORDER BY Captured_At__c DESC LIMIT 50`,
        { fresh: true }
    ).catch(() => []);
    return {
        visitId: visit.Id,
        visitName: visit.Name,
        accountId: visit.Account__c,
        accountName: visit.Account__r?.Name || null,
        isLocked: visit.Status__c === 'Completed' || visit.Status__c === 'Cancelled',
        channelOptions: CHANNELS,
        consentTypeOptions: CONSENT_TYPES,
        statusOptions: STATUSES,
        existingConsents: consents.map((row) => ({
            id: row.Id,
            name: row.Name,
            channel: row.Channel__c,
            consentType: row.Consent_Type__c,
            status: row.Status__c,
            capturedAt: row.Captured_At__c,
            hasSignature: Boolean(row.Signature_Data__c),
            notes: row.Notes__c
        }))
    };
}

export default makeDualApex(getVisitConsentContext);
