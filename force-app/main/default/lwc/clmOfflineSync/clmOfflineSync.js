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
// Manual override: 'online' | 'offline' | null. Lets an operator force a mode.
let manualOverride = null;
// Authoritative online flag. We DO NOT trust navigator.onLine to seed this: in
// the Salesforce Lightning container / installed PWA it is frequently a false
// negative (reports offline while the network is fine), which used to force the
// planner into an empty IndexedDB cache branch. Default online; only real
// signals (a failed Apex/network call, or the browser 'offline' event) flip it
// to offline, and any success flips it back.
let onlineState = true;

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
    if (manualOverride) {
        return manualOverride === 'offline';
    }
    return !onlineState;
}

// 'online' | 'offline' | null (null clears the override and resumes auto-detection).
export function setOfflineOverride(mode) {
    manualOverride = mode === 'online' || mode === 'offline' ? mode : null;
    notify({ phase: 'override', mode: manualOverride, offline: isOfflineMode() });
    if (!isOfflineMode()) {
        drainQueue();
    }
}

// Real-signal connectivity reporting. Callers invoke markOnline() after a
// successful server call and markOffline() after a network failure, so the
// online flag reflects actual reachability instead of navigator.onLine.
export function markOnline() {
    const wasOffline = !onlineState;
    onlineState = true;
    if (wasOffline) {
        notify({ phase: 'online', offline: false });
        drainQueue();
    }
}

export function markOffline() {
    if (onlineState) {
        onlineState = false;
        notify({ phase: 'offline', offline: true });
    }
}

function ensureOnlineListener() {
    if (listenerRegistered || typeof window === 'undefined') {
        return;
    }
    listenerRegistered = true;
    window.addEventListener('online', markOnline);
    window.addEventListener('offline', markOffline);
}

export async function queueOfflineAction(action) {
    console.log('[OfflineSync] [Step 1: Queue Action]', {
        actionType: action?.actionType,
        clientVisitKey: action?.clientVisitKey,
        clientActionKey: action?.clientActionKey,
        online: typeof navigator !== 'undefined' ? navigator.onLine : true
    });
    const id = await enqueueAction(action);
    const pendingCount = await countPendingActions();
    console.log(`[OfflineSync] [Step 2: Saved to IDB Outbox] Action ID: ${id}. Total pending: ${pendingCount}`);
    notify({ phase: 'queued', pending: pendingCount });
    if (!isOfflineMode()) {
        console.log('[OfflineSync] Online status detected; attempting immediate queue drain...');
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
    if (syncInFlight || isOfflineMode()) {
        if (syncInFlight) {
            console.log('[OfflineSync] Sync already in flight, skipping drain.');
        } else {
            console.log('[OfflineSync] Currently offline, holding outbox in IndexedDB.');
        }
        return { synced: 0 };
    }
    syncInFlight = true;
    notify({ phase: 'syncing' });
    let synced = 0;
    try {
        const pending = await getPendingActions();
        console.log(`[OfflineSync] [Step 3: Reconnection / Drain] Found ${pending.length} pending action(s) in outbox.`);
        if (!pending.length) {
            notify({ phase: 'idle', synced: 0, pending: 0 });
            return { synced: 0 };
        }
        const payload = pending.map(toApexAction);
        console.log('[OfflineSync] [Step 4: Syncing with Salesforce]', payload);
        const result = await syncOfflineActions({ actions: payload });
        markOnline();
        console.log('[OfflineSync] [Step 5: Salesforce Result Received]', result);
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
                console.warn(`[OfflineSync] Action failed for clientKey ${failureKey}. Retry #${retries}`);
                await updateAction(row.id, {
                    status: retries >= MAX_RETRIES ? 'dead' : 'failed',
                    retries,
                    lastError: result?.errorMessages?.[index] || 'Sync failed'
                });
            } else {
                console.log(`[OfflineSync] [Step 6: Outbox Cleanup] Successfully synced and removed action ID ${row.id}`);
                await removeAction(row.id);
                synced += 1;
            }
        }
        const remaining = await countPendingActions();
        console.log(`[OfflineSync] [Step 7: Finished] Synced: ${synced}, Remaining pending: ${remaining}`);
        notify({ phase: 'idle', synced, pending: remaining });
        return { synced, result, pending: remaining };
    } catch (error) {
        console.error('[OfflineSync] Drain queue error:', error);
        notify({ phase: 'error', error, pending: await countPendingActions() });
        throw error;
    } finally {
        syncInFlight = false;
    }
}

export function startSyncService() {
    ensureOnlineListener();
    if (!isOfflineMode()) {
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