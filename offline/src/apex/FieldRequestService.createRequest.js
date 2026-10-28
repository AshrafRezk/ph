import { makeDualApex } from './_wireAdapter.js';
import { plannerApiFetch } from './restHelper.js';
import { isOfflineMode, queueOfflineAction } from 'c/clmOfflineSync';
import { newClientKey } from 'c/clmOfflineStore';

function esc(value) {
    return String(value || '').replace(/\\/g, '\\\\').replace(/'/g, "\\'");
}

async function soql(query) {
    const data = await plannerApiFetch(
        `/services/data/v62.0/query?q=${encodeURIComponent(query)}`
    );
    return data?.records || [];
}

async function createRequest(params = {}) {
    const input = params.input || params;
    if (!input?.accountId) {
        throw Object.assign(new Error('Choose an account for this request.'), {
            body: { message: 'Choose an account for this request.' }
        });
    }
    if (!String(input.summary || '').trim()) {
        throw Object.assign(new Error('Write a short summary of what is needed.'), {
            body: { message: 'Write a short summary of what is needed.' }
        });
    }

    const kindKey = String(input.kind || '').toLowerCase();
    const kind =
        kindKey === 'medical' ? 'Medical' : kindKey === 'marketing' ? 'Marketing' : 'Field';
    const requestType =
        input.requestType || (kind === 'Medical' ? 'Efficacy' : 'Other');
    const status = kind === 'Medical' ? 'With Medical' : 'With Manager';

    const payload = {
        Account__c: input.accountId,
        Visit__c: input.visitId || null,
        Product__c: input.productId || null,
        Kind__c: kind,
        Request_Type__c: requestType,
        Urgency__c: input.urgency || 'Normal',
        Summary__c: String(input.summary).trim(),
        Source__c: input.source || 'Home',
        Status__c: status,
        Submitted_Date__c: new Date().toISOString()
    };

    if (kind === 'Marketing' && !input.requestType) {
        throw Object.assign(new Error('Choose a marketing service.'), {
            body: { message: 'Choose a marketing service.' }
        });
    }

    if (isOfflineMode()) {
        const clientKey = newClientKey('field-request');
        await queueOfflineAction({
            actionType: 'CREATE_FIELD_REQUEST',
            clientActionKey: clientKey,
            payloadJson: JSON.stringify(payload)
        });
        return {
            id: clientKey,
            name: 'Pending sync',
            accountId: input.accountId,
            kind,
            requestType,
            status,
            statusLabel: kind === 'Medical' ? 'With medical' : 'With your manager',
            summary: payload.Summary__c,
            offline: true
        };
    }

    if (kind === 'Marketing') {
        try {
            const types = await soql(
                `SELECT Id FROM Service_Request_Type__c WHERE Category__c = 'Marketing' AND Name = '${esc(requestType)}' AND Is_Active__c = TRUE LIMIT 1`
            );
            if (types[0]?.Id) {
                payload.Service_Type__c = types[0].Id;
            }
        } catch (_err) {
            // Request_Type__c text still records the service
        }
    }

    try {
        const identity = await plannerApiFetch('/services/oauth2/userinfo');
        if (identity?.user_id) {
            payload.Requested_By__c = identity.user_id;
            const users = await soql(
                `SELECT ManagerId FROM User WHERE Id = '${esc(identity.user_id)}' LIMIT 1`
            );
            const managerId = users[0]?.ManagerId || null;
            if (managerId) {
                payload.Manager__c = managerId;
                if (kind === 'Field') {
                    payload.OwnerId = managerId;
                }
            }
        }
    } catch (_err) {
        // continue without requester if identity is unavailable
    }

    if (kind === 'Medical') {
        const queues = await soql(
            "SELECT Id FROM Group WHERE Type = 'Queue' AND DeveloperName = 'Medical_Affairs' LIMIT 1"
        );
        if (queues[0]?.Id) {
            payload.OwnerId = queues[0].Id;
        }
    }

    const created = await plannerApiFetch('/services/data/v62.0/sobjects/Field_Request__c', {
        method: 'POST',
        body: JSON.stringify(payload)
    });
    return {
        id: created.id,
        name: created.id,
        accountId: input.accountId,
        visitId: input.visitId || null,
        kind,
        requestType,
        status,
        statusLabel: kind === 'Medical' ? 'With medical' : 'With your manager',
        summary: payload.Summary__c
    };
}

export default makeDualApex(createRequest);
