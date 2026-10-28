import {
    getClientKeyMapping,
    getPendingActions,
    newClientKey,
    removeAction,
    updateAction
} from 'c/clmOfflineStore';
import { queueOfflineAction } from 'c/clmOfflineSync';
import {
    applyPendingActions,
    isSalesforceId,
    parseActionPayload,
    salesforceIdOrNull
} from 'c/plannerPendingMerge';

export { applyPendingActions, isSalesforceId, salesforceIdOrNull };

export async function resolveServerId(id) {
    const direct = salesforceIdOrNull(id);
    if (direct) {
        return direct;
    }
    if (!id) {
        return null;
    }
    try {
        const mapping = await getClientKeyMapping(String(id));
        return salesforceIdOrNull(mapping?.serverId);
    } catch (_err) {
        return null;
    }
}

export async function applyPendingOverlay(payload = {}) {
    let pending = [];
    try {
        pending = await getPendingActions();
    } catch (_err) {
        pending = [];
    }
    return applyPendingActions(payload, pending);
}

function rowMatchesId(row, wanted) {
    const payload = parseActionPayload(row.payloadJson);
    const keys = [
        row.clientVisitKey,
        row.clientActionKey,
        row.visitId,
        payload.visitId,
        payload.timeOffId,
        payload.meetingId,
        payload.clientVisitKey
    ];
    if (keys.some((key) => key && wanted.has(String(key)))) {
        return { payload, matched: true };
    }
    if ((payload.visitIds || []).some((id) => wanted.has(String(id)))) {
        return { payload, matched: true };
    }
    return { payload, matched: false };
}

export async function dropPendingForIds(ids) {
    const wanted = new Set((ids || []).filter(Boolean).map(String));
    if (!wanted.size) {
        return;
    }
    const pending = await getPendingActions();
    for (const row of pending) {
        const { payload, matched } = rowMatchesId(row, wanted);
        if (!matched) {
            continue;
        }
        if (row.actionType === 'RESCHEDULE_VISITS' && Array.isArray(payload.visitIds) && payload.visitIds.length > 1) {
            const keepIds = [];
            const starts = [];
            const ends = [];
            payload.visitIds.forEach((id, index) => {
                if (!wanted.has(String(id))) {
                    keepIds.push(id);
                    starts.push((payload.startDateTimes || [])[index]);
                    ends.push((payload.endDateTimes || [])[index]);
                }
            });
            if (!keepIds.length) {
                await removeAction(row.id);
            } else {
                await updateAction(row.id, {
                    payloadJson: JSON.stringify({
                        ...payload,
                        visitIds: keepIds,
                        startDateTimes: starts,
                        endDateTimes: ends
                    })
                });
            }
            continue;
        }
        await removeAction(row.id);
    }
}

export async function savePendingVisit({ clientVisitKey, serverVisitId, payload }) {
    const key = clientVisitKey || newClientKey('visit');
    const visitId = salesforceIdOrNull(serverVisitId);
    const body = { ...payload, visitId: visitId || null };
    const pending = await getPendingActions();
    const existing = pending.find((row) => {
        if (row.actionType !== 'UPSERT_VISIT') {
            return false;
        }
        const queued = parseActionPayload(row.payloadJson);
        return (
            row.clientVisitKey === key ||
            (visitId && (row.visitId === visitId || queued.visitId === visitId))
        );
    });
    if (existing) {
        await updateAction(existing.id, {
            status: 'pending',
            retries: 0,
            clientVisitKey: existing.clientVisitKey || key,
            visitId,
            payloadJson: JSON.stringify(body)
        });
        return { clientVisitKey: existing.clientVisitKey || key, visitId };
    }
    await queueOfflineAction({
        actionType: 'UPSERT_VISIT',
        clientVisitKey: key,
        clientActionKey: newClientKey('upsert'),
        visitId,
        payloadJson: JSON.stringify(body)
    });
    return { clientVisitKey: key, visitId };
}

export async function patchPendingByType(actionType, clientKey, patch) {
    if (!clientKey) {
        return false;
    }
    const pending = await getPendingActions();
    const existing = pending.find((row) => {
        if (row.actionType !== actionType) {
            return false;
        }
        return row.clientActionKey === clientKey || row.clientVisitKey === clientKey;
    });
    if (!existing) {
        return false;
    }
    const payload = { ...parseActionPayload(existing.payloadJson), ...patch };
    await updateAction(existing.id, {
        status: 'pending',
        retries: 0,
        payloadJson: JSON.stringify(payload)
    });
    return true;
}
