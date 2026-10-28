import { plannerApiFetch } from './restHelper.js';

function actionFailureKey(row) {
    return (
        row.clientActionKey ||
        row.clientSessionKey ||
        row.clientVisitKey ||
        row.clientCoachingKey ||
        row.id ||
        row.actionType
    );
}

function normalizeOutboxResult(raw, actions) {
    if (raw && Array.isArray(raw.failedClientKeys)) {
        return raw;
    }
    const results = raw?.results || [];
    const failedClientKeys = [];
    // One entry per action (null on success): the drain loop reads errorMessages[index].
    const errorMessages = [];
    const visitIdByClientKey = { ...(raw?.visitIdByClientKey || {}) };
    const sessionIdByClientKey = { ...(raw?.sessionIdByClientKey || {}) };
    results.forEach((item, index) => {
        const row = actions[index] || {};
        const key = actionFailureKey(row) || item?.id;
        Object.assign(visitIdByClientKey, item?.visitIdByClientKey || {});
        Object.assign(sessionIdByClientKey, item?.sessionIdByClientKey || {});
        if (item && item.success === false) {
            if (key) {
                failedClientKeys.push(key);
            }
            errorMessages[index] = item.error || 'Sync failed';
        } else {
            errorMessages[index] = null;
        }
    });
    return {
        failedClientKeys,
        errorMessages,
        visitIdByClientKey,
        sessionIdByClientKey,
        coachingIdByClientKey: raw?.coachingIdByClientKey || {}
    };
}

function isSalesforceId(value) {
    return typeof value === 'string' && /^[a-zA-Z0-9]{15}([a-zA-Z0-9]{3})?$/.test(value);
}

/**
 * D6-01: every new-visit upsert carries its client key inside the payload too, so the server
 * stores it in Client_Visit_Key__c and a replayed upsert updates that visit instead of
 * inserting a duplicate. Edits of saved visits (Salesforce Id key) are left as they are.
 */
export function withClientVisitKeys(actions = []) {
    return actions.map((action) => {
        if (action?.actionType !== 'UPSERT_VISIT') {
            return action;
        }
        const key = action.clientVisitKey;
        if (!key || isSalesforceId(key)) {
            return action;
        }
        let payload = {};
        try {
            payload = action.payloadJson ? JSON.parse(action.payloadJson) : {};
        } catch (e) {
            return action;
        }
        if (payload.visitId || payload.clientVisitKey === key) {
            return action;
        }
        return { ...action, payloadJson: JSON.stringify({ ...payload, clientVisitKey: key }) };
    });
}

export default async function syncOfflineActions(params = {}) {
    console.log('[OfflineSync] Sending pending outbox actions to Salesforce backend...', params);
    try {
        const actions = withClientVisitKeys(params.actions || []);
        const result = await plannerApiFetch('/services/apexrest/planner/v1/outbox', {
            method: 'POST',
            body: JSON.stringify({ ...params, actions })
        });
        const normalized = normalizeOutboxResult(result, actions);
        console.log('[OfflineSync] Sync completed with result:', normalized);
        return normalized;
    } catch (error) {
        console.error('[OfflineSync] Sync failed with error:', error);
        throw error;
    }
}
