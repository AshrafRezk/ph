import { makeDualApex } from './_wireAdapter.js';
import { plannerApiFetch } from './restHelper.js';
import { queueOfflineAction } from 'c/clmOfflineSync';
import { esc } from './learningShared.js';

const API_VERSION = 'v62.0';

function apexError(message) {
    const err = new Error(message);
    err.body = { message };
    return err;
}

async function soql(query, options = {}) {
    const path = `/services/data/${API_VERSION}/query?q=${encodeURIComponent(query)}`;
    const result = await plannerApiFetch(path, options.fresh ? { fresh: true } : {});
    return result && Array.isArray(result.records) ? result.records : [];
}

async function captureVisitConsent(params = {}) {
    const request = params.request || params;
    const visitId = request.visitId;
    const channel = request.channel;
    const consentType = request.consentType;
    const status = request.status || 'Granted';
    const signatureData = request.signatureData;
    const notes = request.notes;
    const accountId = request.accountId;

    if (!visitId) {
        throw apexError('Visit Id is required.');
    }
    if (!channel) {
        throw apexError('Select a channel.');
    }
    if (!consentType) {
        throw apexError('Select a consent type.');
    }
    if (status === 'Granted' && !signatureData) {
        throw apexError('Capture a signature before granting consent.');
    }

    const payload = {
        Visit__c: visitId,
        Account__c: accountId || null,
        Channel__c: channel,
        Consent_Type__c: consentType,
        Status__c: status,
        Captured_At__c: new Date().toISOString(),
        Signature_Data__c: signatureData || null,
        Notes__c: notes || null
    };

    try {
        const created = await plannerApiFetch(`/services/data/${API_VERSION}/sobjects/Visit_Consent__c`, {
            method: 'POST',
            body: JSON.stringify(payload)
        });
        const consentId = created?.id;
        if (!consentId) {
            throw apexError('Unable to save consent.');
        }
        const rows = await soql(
            `SELECT Id, Name FROM Visit_Consent__c WHERE Id = '${esc(consentId)}' LIMIT 1`,
            { fresh: true }
        );
        return {
            consentId,
            name: rows[0]?.Name || 'Consent'
        };
    } catch (error) {
        await queueOfflineAction({
            actionType: 'CAPTURE_CONSENT',
            visitId,
            clientActionKey: `consent_${visitId}_${channel}_${consentType}`,
            payloadJson: JSON.stringify(payload)
        });
        return { consentId: null, name: 'Queued offline', queued: true };
    }
}

export default makeDualApex(captureVisitConsent);
