import assert from 'node:assert/strict';
import test from 'node:test';
import { describeOutbox, reviveDeadRow, summarizeOutboxRows } from './outboxStats.js';

test('summarizeOutboxRows counts pending, failed and dead rows', () => {
    const summary = summarizeOutboxRows([
        { status: 'pending' },
        { status: 'failed' },
        { status: 'dead' },
        { status: 'dead' },
        {}
    ]);
    assert.deepEqual(summary, { pending: 2, failed: 1, dead: 2, unsynced: 5 });
    assert.deepEqual(summarizeOutboxRows(null), { pending: 0, failed: 0, dead: 0, unsynced: 0 });
});

test('reviveDeadRow resets retries and keeps the previous error', () => {
    const revived = reviveDeadRow(
        { id: 7, actionType: 'SAVE_CALL_REPORT', status: 'dead', retries: 5, lastError: 'Unsupported outbox action: SAVE_CALL_REPORT' },
        '2026-10-24T00:00:00.000Z'
    );
    assert.equal(revived.status, 'pending');
    assert.equal(revived.retries, 0);
    assert.equal(revived.lastError, null);
    assert.equal(revived.previousError, 'Unsupported outbox action: SAVE_CALL_REPORT');
    assert.equal(revived.id, 7);
    assert.equal(revived.requeuedAt, '2026-10-24T00:00:00.000Z');
});

test('describeOutbox hides when synced and flags dead rows', () => {
    assert.equal(describeOutbox({ unsynced: 0, dead: 0 }), '');
    assert.equal(describeOutbox({ unsynced: 3, dead: 0 }), '3 unsynced');
    assert.match(describeOutbox({ unsynced: 3, dead: 3 }), /not synced/);
    assert.match(describeOutbox({ unsynced: 4, dead: 1 }), /1 need retry/);
});
