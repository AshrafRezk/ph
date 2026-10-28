import assert from 'node:assert/strict';
import test from 'node:test';
import {
    applyPendingActions,
    isSalesforceId
} from '../../../force-app/main/default/lwc/plannerPendingMerge/plannerPendingMerge.js';

test('client visit keys are not Salesforce ids', () => {
    assert.equal(isSalesforceId('visit_d0a71644-cde3-4fd6-b714-23cc9579519a'), false);
    assert.equal(isSalesforceId('tot_d0a71644-cde3-4fd6-b714-23cc9579519a'), false);
    assert.equal(isSalesforceId('001000000000001AAA'), true);
    assert.equal(isSalesforceId('001000000000001'), true);
});

test('removing a queued local visit drops it from the week', () => {
    const merged = applyPendingActions(
        { visits: [], timeOffBlocks: [], meetings: [] },
        [
            {
                actionType: 'UPSERT_VISIT',
                clientVisitKey: 'visit_d0a71644-cde3-4fd6-b714-23cc9579519a',
                payloadJson: JSON.stringify({
                    accountId: '001000000000001AAA',
                    startDateTime: '2026-09-28T08:30:00.000Z',
                    endDateTime: '2026-09-28T09:30:00.000Z',
                    status: 'Draft',
                    accountName: 'Mona Ali 59'
                })
            },
            {
                actionType: 'DELETE_VISIT',
                clientVisitKey: 'visit_d0a71644-cde3-4fd6-b714-23cc9579519a',
                payloadJson: JSON.stringify({
                    visitId: 'visit_d0a71644-cde3-4fd6-b714-23cc9579519a'
                })
            }
        ]
    );
    assert.equal(merged.visits.length, 0);
});

test('editing a queued visit keeps one row and the latest times', () => {
    const key = 'visit_abc';
    const merged = applyPendingActions({ visits: [] }, [
        {
            actionType: 'UPSERT_VISIT',
            clientVisitKey: key,
            payloadJson: JSON.stringify({
                startDateTime: '2026-09-28T08:00:00.000Z',
                endDateTime: '2026-09-28T09:00:00.000Z',
                status: 'Draft'
            })
        },
        {
            actionType: 'UPSERT_VISIT',
            clientVisitKey: key,
            payloadJson: JSON.stringify({
                visitId: key,
                startDateTime: '2026-09-28T11:30:00.000Z',
                endDateTime: '2026-09-28T12:30:00.000Z',
                status: 'Draft'
            })
        }
    ]);
    assert.equal(merged.visits.length, 1);
    assert.equal(merged.visits[0].id, key);
    assert.equal(merged.visits[0].startDateTime, '2026-09-28T11:30:00.000Z');
});

test('queued TOT and meeting create, edit, and remove stay local', () => {
    const merged = applyPendingActions({ timeOffBlocks: [], meetings: [] }, [
        {
            actionType: 'CREATE_TIME_OFF',
            clientActionKey: 'tot_1',
            payloadJson: JSON.stringify({
                typeValue: 'Training',
                spanType: 'Hours',
                durationHours: '2',
                startDateTime: '2026-09-28T08:00:00.000Z',
                stage: 'Draft'
            })
        },
        {
            actionType: 'UPDATE_TIME_OFF',
            clientActionKey: 'tot_1',
            payloadJson: JSON.stringify({
                timeOffId: 'tot_1',
                endDateTime: '2026-09-28T12:00:00.000Z',
                durationHours: '4'
            })
        },
        {
            actionType: 'CREATE_MEETING',
            clientActionKey: 'meeting_1',
            payloadJson: JSON.stringify({
                title: 'Cycle',
                startDateTime: '2026-09-28T10:00:00.000Z',
                endDateTime: '2026-09-28T11:00:00.000Z',
                status: 'Draft'
            })
        },
        {
            actionType: 'DELETE_MEETING',
            clientActionKey: 'meeting_1',
            payloadJson: JSON.stringify({ meetingId: 'meeting_1' })
        }
    ]);
    assert.equal(merged.timeOffBlocks.length, 1);
    assert.equal(merged.timeOffBlocks[0].endDateTime, '2026-09-28T12:00:00.000Z');
    assert.equal(merged.meetings.length, 0);
});
