import { plannerApiFetch } from './restHelper.js';
import { queueOfflineAction } from 'c/clmOfflineSync';

export default async function saveMessageResponses(params = {}) {
    try {
        return await plannerApiFetch('/services/apexrest/clm/v1/sessions/message-responses', {
            method: 'POST',
            body: JSON.stringify({
                sessionId: params.sessionId,
                responses: params.responses
            })
        });
    } catch (error) {
        await queueOfflineAction({
            actionType: 'SAVE_MESSAGE_RESPONSES',
            clientSessionKey: params.sessionId,
            clientActionKey: `msg_${params.sessionId || 'local'}`,
            responsesJson: JSON.stringify(params.responses || [])
        });
        return { queued: true };
    }
}
