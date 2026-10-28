import { plannerApiFetch } from './restHelper.js';
import { queueOfflineAction } from 'c/clmOfflineSync';

export default async function completeSession(params = {}) {
    try {
        return await plannerApiFetch('/services/apexrest/clm/v1/sessions/complete', {
            method: 'POST',
            body: JSON.stringify({ sessionId: params.sessionId })
        });
    } catch (error) {
        await queueOfflineAction({
            actionType: 'COMPLETE_SESSION',
            clientSessionKey: params.sessionId,
            clientActionKey: `complete_${params.sessionId || 'local'}`,
            endedAtIso: new Date().toISOString()
        });
        return { queued: true };
    }
}
