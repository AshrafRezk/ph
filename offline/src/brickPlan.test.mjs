import assert from 'node:assert/strict';
import test from 'node:test';
import {
    buildVisitSlots,
    isHighClassification,
    parsePlanRequest,
    rankBricks,
    remainingWorkingDays
} from './brickPlan.js';

function account(overrides) {
    return {
        id: '001000000000001AAA',
        name: 'Dr One',
        classification: 'C',
        targetVisits: 0,
        actualVisits: 0,
        plannedVisits: 0,
        brick702Id: 'a0B000000000001AAA',
        brick702Name: 'Nasr City',
        brick148Id: 'a0B000000000010AAA',
        brick148Name: 'East Cairo',
        ...overrides
    };
}

test('class A variants count as high classification', () => {
    assert.equal(isHighClassification('A'), true);
    assert.equal(isHighClassification('A1'), true);
    assert.equal(isHighClassification('A+'), true);
    assert.equal(isHighClassification('Class A'), true);
    assert.equal(isHighClassification('B'), false);
    assert.equal(isHighClassification('C1'), false);
});

test('top bricks are the ones with open target visits or class A', () => {
    const ranked = rankBricks([
        account({ id: '1', name: 'Gap A', classification: 'A', targetVisits: 4, actualVisits: 1, brick702Name: 'Nasr City' }),
        account({ id: '2', name: 'Done', classification: 'C', targetVisits: 2, actualVisits: 2, brick702Id: 'a0B000000000002AAA', brick702Name: 'Maadi', brick148Name: 'South' }),
        account({
            id: '3',
            name: 'High only',
            classification: 'A+',
            targetVisits: 0,
            brick702Id: 'a0B000000000003AAA',
            brick702Name: 'Heliopolis',
            brick148Name: 'North'
        }),
        account({ id: '4', name: 'No signal', classification: 'C', targetVisits: 0, brick702Id: 'a0B000000000004AAA', brick702Name: 'Quiet' }),
        account({ id: '5', name: 'Second gap', classification: 'B', targetVisits: 3, actualVisits: 0, brick702Name: 'Nasr City' })
    ]);

    assert.deepEqual(ranked.top.map((brick) => brick.name), ['Nasr City', 'Heliopolis', 'Maadi']);
    assert.equal(ranked.all.some((brick) => brick.name === 'Quiet'), false);
    assert.equal(ranked.top[0].openVisits, 6);
    assert.equal(ranked.top[0].highCount, 1);
    assert.equal(ranked.top[0].zoneName, 'East Cairo');
    assert.deepEqual(ranked.top[0].accounts.map((row) => row.name), ['Gap A', 'Second gap']);
});

test('working days left skip Thursday, Friday, holidays, and full-day time off', () => {
    const days = remainingWorkingDays({
        now: new Date(2026, 8, 28, 10, 0, 0),
        weekStart: '2026-09-26',
        weekEnd: '2026-10-02',
        holidays: ['2026-09-29'],
        timeOff: [{ isFullDay: true, startDateTime: '2026-09-30T12:00:00' }]
    });
    assert.deepEqual(days.map((day) => day.iso), ['2026-09-28']);
});

test('slots fill the day from 9 and skip a busy hour', () => {
    const days = remainingWorkingDays({
        now: new Date(2026, 8, 28, 8, 0, 0),
        weekStart: '2026-09-28',
        weekEnd: '2026-09-30'
    }).filter((day) => day.iso === '2026-09-28');
    const slots = buildVisitSlots({
        accounts: [
            account({ id: '1', name: 'First', classification: 'A', targetVisits: 2 }),
            account({ id: '2', name: 'Second', classification: 'A', targetVisits: 2 })
        ],
        days,
        existingVisits: [
            {
                accountId: '9',
                status: 'Draft',
                startDateTime: new Date(2026, 8, 28, 9, 0, 0).toISOString(),
                endDateTime: new Date(2026, 8, 28, 10, 0, 0).toISOString()
            }
        ],
        dailyCap: 8,
        now: new Date(2026, 8, 28, 8, 0, 0)
    });
    assert.equal(slots.length, 2);
    assert.equal(slots[0].start.getHours(), 10);
    assert.equal(slots[1].start.getHours(), 11);
});

test('a week plan spreads visits across remaining working days', () => {
    const days = remainingWorkingDays({
        now: new Date(2026, 8, 26, 8, 0, 0),
        weekStart: '2026-09-26',
        weekEnd: '2026-10-02'
    });
    const slots = buildVisitSlots({
        accounts: ['One', 'Two', 'Three'].map((name, index) =>
            account({ id: String(index + 1), name, classification: 'A', targetVisits: 1 })
        ),
        days,
        existingVisits: [],
        dailyCap: 2,
        now: new Date(2026, 8, 26, 8, 0, 0)
    });
    assert.deepEqual(slots.map((slot) => slot.iso), ['2026-09-26', '2026-09-27', '2026-09-28']);
});

test('plan requests resolve a brick for the week or a selected day', () => {
    const ranked = rankBricks([
        account({ classification: 'A', targetVisits: 3, actualVisits: 0 }),
        account({
            id: '2',
            name: 'Other',
            classification: 'A',
            targetVisits: 1,
            brick702Id: 'a0B000000000002AAA',
            brick702Name: 'Maadi'
        })
    ]);
    const session = {
        bricks: ranked.all,
        now: new Date(2026, 8, 28, 9, 0, 0),
        weekStart: '2026-09-26',
        weekEnd: '2026-10-02',
        holidays: [],
        timeOff: []
    };

    assert.equal(parsePlanRequest('Which bricks should I plan?', session), null);
    assert.equal(parsePlanRequest('Plan the top brick this week', session).span, 'week');
    assert.equal(parsePlanRequest('Plan the top brick this week', session).brickKey, 'a0B000000000001AAA');

    const wednesday = parsePlanRequest('Plan Nasr City on Wednesday', session);
    assert.equal(wednesday.span, 'day');
    assert.equal(wednesday.date, '2026-09-30');

    const friday = parsePlanRequest('Plan Maadi on Friday', session);
    assert.match(friday.clarify, /Saturday through Wednesday/);

    const pickDay = parsePlanRequest('Plan a day in Maadi', session);
    assert.match(pickDay.clarify, /Which day/);
    assert.ok(pickDay.actions.some((action) => action.command.startsWith('date:a0B000000000002AAA:')));
});
