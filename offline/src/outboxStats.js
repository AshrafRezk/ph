// Pure helpers for the offline outbox (no browser / module-alias imports so they are unit-testable).

// Bump when the server learns to handle outbox action types it used to reject
// (e.g. PlannerMobileRestService now accepts SAVE_CALL_REPORT, CLM session actions and
// account actions). On the next launch every `dead` action is given a fresh set of retries.
export const OUTBOX_SERVER_REVISION = '2026-10-24-outbox-v2';
export const OUTBOX_REVISION_KEY = 'zeta.pwa.outboxServerRevision';

export function summarizeOutboxRows(rows) {
    const list = Array.isArray(rows) ? rows : [];
    let pending = 0;
    let failed = 0;
    let dead = 0;
    for (const row of list) {
        const status = row?.status || 'pending';
        if (status === 'dead') {
            dead += 1;
        } else if (status === 'failed') {
            failed += 1;
        } else {
            pending += 1;
        }
    }
    return { pending, failed, dead, unsynced: pending + failed + dead };
}

export function reviveDeadRow(row, nowIso = new Date().toISOString()) {
    return {
        ...row,
        status: 'pending',
        retries: 0,
        requeuedAt: nowIso,
        previousError: row?.lastError || row?.previousError || null,
        lastError: null
    };
}

export function describeOutbox(summary) {
    if (!summary || !summary.unsynced) {
        return '';
    }
    if (summary.dead > 0) {
        return summary.dead === summary.unsynced
            ? `${summary.dead} not synced - tap to retry`
            : `${summary.unsynced} unsynced (${summary.dead} need retry) - tap to retry`;
    }
    return `${summary.unsynced} unsynced`;
}
