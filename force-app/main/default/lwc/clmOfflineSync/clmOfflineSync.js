import syncOfflineActions from '@salesforce/apex/ClmOfflineSyncController.syncOfflineActions';
import {
    countPendingActions,
    enqueueAction,
    getPendingActions,
    putClientKeyMapping,
    removeAction,
    updateAction,
    updateLocalSession
} from 'c/clmOfflineStore';

const MAX_RETRIES = 5;
const listeners = new Set();
let syncInFlight = false;
let listenerRegistered = false;

function notify(status) {
    listeners.forEach((listener) => {
        try {
            listener(status);
        } catch (error) {
            // eslint-disable-next-line no-console
            console.warn('CLM offline listener failed', error);
        }
    });
}

export function registerOfflineListener(listener) {
    listeners.add(listener);
    ensureOnlineListener();
    return () => listeners.delete(listener);
}

export function isOfflineMode() {
    return typeof navigator !== 'undefined' && !navigator.onLine;
}

function ensureOnlineListener() {
    if (listenerRegistered || typeof window === 'undefined') {
        return;
    }
    listenerRegistered = true;
    window.addEventListener('online', () => {
        drainQueue();
    });
}

export async function queueOfflineAction(action) {
    const id = await enqueueAction(action);
    notify({ phase: 'queued', pending: await countPendingActions() });
    if (typeof navigator !== 'undefined' && navigator.onLine) {
        drainQueue();
    }
    return id;
}

function actionFailureKey(row) {
    return (
        row.clientActionKey ||
        row.clientSessionKey ||
        row.clientVisitKey ||
        row.clientCoachingKey ||
        `${row.actionType}_${row.id}`
    );
}

function toApexAction(row) {
    return {
        actionType: row.actionType,
        clientActionKey: row.clientActionKey || actionFailureKey(row),
        clientSessionKey: row.clientSessionKey,
        clientVisitKey: row.clientVisitKey,
        clientCoachingKey: row.clientCoachingKey,
        visitId: row.visitId,
        presentationId: row.presentationId,
        startedAtIso: row.startedAtIso,
        sequenceId: row.sequenceId,
        dwellSeconds: row.dwellSeconds,
        trackingPaused: row.trackingPaused,
        responsesJson: row.responsesJson,
        ratingsJson: row.ratingsJson,
        layoutId: row.layoutId,
        endedAtIso: row.endedAtIso,
        slidesPresentedCount: row.slidesPresentedCount,
        totalDurationSeconds: row.totalDurationSeconds,
        callReportJson: row.callReportJson,
        payloadJson: row.payloadJson
    };
}

async function persistKeyMaps(result) {
    const sessionMap = result?.sessionIdByClientKey || {};
    const visitMap = result?.visitIdByClientKey || {};
    const coachingMap = result?.coachingIdByClientKey || {};

    Object.entries(sessionMap).forEach(([clientKey, serverSessionId]) => {
        updateLocalSession(clientKey, { serverSessionId, synced: true });
        putClientKeyMapping(clientKey, { type: 'session', serverId: serverSessionId });
    });
    for (const [clientKey, serverVisitId] of Object.entries(visitMap)) {
        await putClientKeyMapping(clientKey, { type: 'visit', serverId: serverVisitId });
        await updateLocalSession(clientKey, { serverVisitId, synced: true });
    }
    for (const [clientKey, serverCoachingId] of Object.entries(coachingMap)) {
        await putClientKeyMapping(clientKey, { type: 'coaching', serverId: serverCoachingId });
    }
}

export async function drainQueue() {
    if (syncInFlight || (typeof navigator !== 'undefined' && !navigator.onLine)) {
        return { synced: 0 };
    }
    syncInFlight = true;
    notify({ phase: 'syncing' });
    let synced = 0;
    try {
        const pending = await getPendingActions();
        if (!pending.length) {
            notify({ phase: 'idle', synced: 0, pending: 0 });
            return { synced: 0 };
        }
        const payload = pending.map(toApexAction);
        const result = await syncOfflineActions({ actions: payload });
        await persistKeyMaps(result);

        const failedKeys = new Set(result?.failedClientKeys || []);
        for (let index = 0; index < pending.length; index += 1) {
            const row = pending[index];
            const failureKey = actionFailureKey(row);
            const failed =
                failedKeys.has(failureKey) ||
                failedKeys.has(row.clientSessionKey) ||
                failedKeys.has(row.clientVisitKey) ||
                failedKeys.has(row.clientCoachingKey) ||
                failedKeys.has(row.actionType) ||
                failedKeys.has(row.clientActionKey);
            if (failed) {
                const retries = (row.retries || 0) + 1;
                await updateAction(row.id, {
                    status: retries >= MAX_RETRIES ? 'dead' : 'failed',
                    retries,
                    lastError: result?.errorMessages?.[index] || 'Sync failed'
                });
            } else {
                await removeAction(row.id);
                synced += 1;
            }
        }
        const remaining = await countPendingActions();
        notify({ phase: 'idle', synced, pending: remaining });
        return { synced, result, pending: remaining };
    } catch (error) {
        notify({ phase: 'error', error, pending: await countPendingActions() });
        throw error;
    } finally {
        syncInFlight = false;
    }
}

export function startSyncService() {
    ensureOnlineListener();
    if (typeof navigator !== 'undefined' && navigator.onLine) {
        drainQueue().catch((error) => {
            // eslint-disable-next-line no-console
            console.warn('CLM offline sync failed', error);
        });
    }
}

export async function resolveSessionId(session) {
    if (!session) {
        return null;
    }
    if (session.serverSessionId) {
        return session.serverSessionId;
    }
    if (session.id && String(session.id).length >= 15) {
        return session.id;
    }
    return session.clientSessionKey || session.id;
}

export async function getOfflineSyncStatus() {
    const pending = await countPendingActions();
    return {
        offline: isOfflineMode(),
        pending,
        syncing: syncInFlight
    };
}
