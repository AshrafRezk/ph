import { plannerApiFetch } from './restHelper.js';
import { queueOfflineAction } from 'c/clmOfflineSync';

export default async function cancelSession(params = {}) {
    try {
        return await plannerApiFetch('/services/apexrest/clm/v1/sessions/cancel', {
            method: 'POST',
            body: JSON.stringify({ sessionId: params.sessionId })
        });
    } catch (error) {
        await queueOfflineAction({
            actionType: 'CANCEL_SESSION',
            clientSessionKey: params.sessionId,
            clientActionKey: `cancel_${params.sessionId || 'local'}`
        });
        return { queued: true };
    }
}
