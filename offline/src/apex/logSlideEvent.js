import { plannerApiFetch } from './restHelper.js';
import { queueOfflineAction } from 'c/clmOfflineSync';

export default async function logSlideEvent(params = {}) {
    try {
        return await plannerApiFetch('/services/apexrest/clm/v1/sessions/slide-event', {
            method: 'POST',
            body: JSON.stringify({
                sessionId: params.sessionId,
                sequenceId: params.sequenceId,
                dwellSeconds: params.dwellSeconds,
                trackingPaused: params.trackingPaused
            })
        });
    } catch (error) {
        await queueOfflineAction({
            actionType: 'LOG_SLIDE_EVENT',
            clientSessionKey: params.clientSessionKey || params.sessionId,
            clientActionKey: `slide_${params.clientSessionKey || params.sessionId || 'local'}_${params.sequenceId || 'seq'}`,
            sequenceId: params.sequenceId,
            dwellSeconds: params.dwellSeconds,
            trackingPaused: params.trackingPaused
        });
        return { queued: true };
    }
}
