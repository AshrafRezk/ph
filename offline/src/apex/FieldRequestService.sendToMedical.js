import { makeDualApex } from './_wireAdapter.js';
import { plannerApiFetch } from './restHelper.js';

async function sendToMedical(params = {}) {
    const requestId = params.requestId;
    let ownerId = null;
    try {
        const soql =
            "SELECT Id FROM Group WHERE Type = 'Queue' AND DeveloperName = 'Medical_Affairs' LIMIT 1";
        const data = await plannerApiFetch(
            `/services/data/v62.0/query?q=${encodeURIComponent(soql)}`
        );
        ownerId = data?.records?.[0]?.Id || null;
    } catch (_err) {
        ownerId = null;
    }
    const body = {
        Status__c: 'With Medical',
        Decision_Notes__c: params.notes || null,
        Decision_Date__c: new Date().toISOString()
    };
    if (ownerId) {
        body.OwnerId = ownerId;
    }
    await plannerApiFetch(`/services/data/v62.0/sobjects/Field_Request__c/${requestId}`, {
        method: 'PATCH',
        body: JSON.stringify(body)
    });
    return { id: requestId, status: 'With Medical', statusLabel: 'With medical' };
}

export default makeDualApex(sendToMedical);
