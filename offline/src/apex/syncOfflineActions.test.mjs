import test from 'node:test';
import assert from 'node:assert/strict';
import { withClientVisitKeys } from './syncOfflineActions.js';

test('new-visit upsert carries its client key in the payload (D6-01)', () => {
    const [out] = withClientVisitKeys([
        {
            actionType: 'UPSERT_VISIT',
            clientVisitKey: 'visit_123e4567-e89b-12d3-a456-426614174000',
            payloadJson: JSON.stringify({ accountId: '001000000000001AAA', status: 'Draft' })
        }
    ]);
    const payload = JSON.parse(out.payloadJson);
    assert.equal(payload.clientVisitKey, 'visit_123e4567-e89b-12d3-a456-426614174000');
    assert.equal(payload.accountId, '001000000000001AAA');
});

test('edits of saved visits and other actions are untouched', () => {
    const edit = {
        actionType: 'UPSERT_VISIT',
        clientVisitKey: 'a0B000000000001AAA',
        payloadJson: JSON.stringify({ visitId: 'a0B000000000001AAA' })
    };
    const other = { actionType: 'DELETE_VISIT', clientVisitKey: 'visit_x', payloadJson: '{}' };
    const [a, b] = withClientVisitKeys([edit, other]);
    assert.equal(a, edit);
    assert.equal(b, other);
});

test('replaying the same action twice sends the same key', () => {
    const action = { actionType: 'UPSERT_VISIT', clientVisitKey: 'visit_abc', payloadJson: '{}' };
    const once = withClientVisitKeys([action]);
    const twice = withClientVisitKeys(once);
    assert.equal(twice[0].payloadJson, once[0].payloadJson);
});
