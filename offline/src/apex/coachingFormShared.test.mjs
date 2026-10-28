import assert from 'node:assert/strict';
import test from 'node:test';
import {
    buildCoachingResponses,
    readCreatedCoachingEventId
} from './coachingFormShared.js';

const templateJson = JSON.stringify({
    questions: [{ id: 'q1', type: 'scale', question: 'Opening', section: 'Call' }]
});

const visit = {
    accountName: 'City Pharmacy',
    visitObjective: 'Review the new launch',
    visitNotes: 'Asked about stock'
};

test('prefill off still builds a response payload', () => {
    const raw = buildCoachingResponses(templateJson, visit, false);
    const parsed = JSON.parse(raw);
    assert.deepEqual(parsed.answers, []);
    assert.equal(parsed.prefillSource, undefined);
});

test('prefill on seeds the first competency without throwing', () => {
    const parsed = JSON.parse(buildCoachingResponses(templateJson, visit, true));
    assert.equal(parsed.answers.length, 1);
    assert.equal(parsed.answers[0].questionId, 'q1');
    assert.match(parsed.answers[0].managerComments, /City Pharmacy/);
    assert.match(parsed.answers[0].managerComments, /Review the new launch/);
    assert.equal(parsed.prefillSource, 'visit');
});

test('bad template JSON does not fail prefill', () => {
    const parsed = JSON.parse(buildCoachingResponses('{not json', visit, true));
    assert.deepEqual(parsed.answers, []);
});

test('a null create result does not throw when reading the coaching event id', () => {
    assert.equal(readCreatedCoachingEventId(null), null);
    assert.equal(readCreatedCoachingEventId(undefined), null);
    assert.equal(readCreatedCoachingEventId({ coachingEventId: 'a01000000000001AAA' }), 'a01000000000001AAA');
    assert.equal(readCreatedCoachingEventId({ id: 'a01000000000002AAA' }), 'a01000000000002AAA');
});
