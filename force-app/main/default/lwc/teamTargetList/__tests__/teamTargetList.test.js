import { createElement } from 'lwc';
import TeamTargetList from 'c/teamTargetList';
import getTeamTargets from '@salesforce/apex/TeamTargetListController.getTeamTargets';
import setFrequency from '@salesforce/apex/TeamTargetListController.setFrequency';
import proposeForTargetList from '@salesforce/apex/TeamTargetListController.proposeForTargetList';

jest.mock('@salesforce/apex/TeamTargetListController.getTeamTargets', () => ({ default: jest.fn() }), { virtual: true });
jest.mock('@salesforce/apex/TeamTargetListController.setFrequency', () => ({ default: jest.fn() }), { virtual: true });
jest.mock('@salesforce/apex/TeamTargetListController.removeFromTargetList', () => ({ default: jest.fn() }), { virtual: true });
jest.mock('@salesforce/apex/TeamTargetListController.proposeForTargetList', () => ({ default: jest.fn() }), { virtual: true });

const OCT = '2026-10-01';
const NOV = '2026-11-01';
const DEC = '2026-12-01';

const cells = (oct, nov, dec, novBaseline = nov) => [
    { monthStart: OCT, frequency: oct, baseline: oct, editable: false },
    { monthStart: NOV, frequency: nov, baseline: novBaseline, editable: true },
    { monthStart: DEC, frequency: dec, baseline: dec, editable: true }
];

const page = (overrides = {}) => ({
    reps: [{ label: 'Rep One', value: '005A' }],
    repId: '005A',
    repName: 'Rep One',
    lineName: 'GIT-I',
    quarter: 'Q4-2026',
    frequencyPct: 10,
    removalPct: 10,
    months: [
        { monthStart: OCT, label: 'Oct 2026', editable: false, currentTotal: 6, baselineTotal: 6, deviationPct: 0 },
        { monthStart: NOV, label: 'Nov 2026', editable: true, currentTotal: 6, baselineTotal: 6, deviationPct: 0 },
        { monthStart: DEC, label: 'Dec 2026', editable: true, currentTotal: 6, baselineTotal: 6, deviationPct: 0 }
    ],
    removedThisQuarter: 0,
    removalLimit: 1,
    listSize: 2,
    rows: [
        { atfId: 'a1', accountId: '001A', accountName: 'Dr One', specialty: 'Cardiology', hcpClass: 'A2', months: cells(4, 4, 4) },
        { atfId: 'a2', accountId: '001B', accountName: 'Dr Two', specialty: 'Dermatology', hcpClass: 'B1', months: cells(2, 2, 2) }
    ],
    outOfTarget: [{ accountId: '001C', accountName: 'Dr Off', visits: 3, proposalStatus: null }],
    ...overrides
});

// eslint-disable-next-line @lwc/lwc/no-async-operation
const flush = () => new Promise((r) => setTimeout(r, 0));

describe('c-team-target-list', () => {
    afterEach(() => {
        while (document.body.firstChild) {
            document.body.removeChild(document.body.firstChild);
        }
        jest.clearAllMocks();
    });

    it('shows a column per month, closes past months and shows the limits', async () => {
        getTeamTargets.mockResolvedValue(page());
        const el = createElement('c-team-target-list', { is: TeamTargetList });
        el.quarter = 'Q4-2026';
        document.body.appendChild(el);
        await flush();
        expect(getTeamTargets).toHaveBeenCalledWith({ repId: null, quarter: 'Q4-2026' });
        const text = el.shadowRoot.textContent;
        expect(text).toContain('Dr One');
        expect(text).toContain('Oct 2026: 6 visits · closed');
        expect(text).toContain('Nov 2026: 6 visits');
        expect(text).toContain('Limit ±10% a month');
        expect(el.shadowRoot.querySelector(`button[data-month="${OCT}"]`)).toBeNull();
        expect(el.shadowRoot.querySelectorAll(`button[data-month="${NOV}"]`).length).toBe(4);
        expect(text).toContain('Removed this quarter 0 of 1 allowed');
        expect(text).toContain('Dr Off');
        expect(el.shadowRoot.querySelectorAll('.ttl-class')[0].textContent).toBe('A2');
    });

    it('adds one visit to one month and shows what it was', async () => {
        getTeamTargets.mockResolvedValue(page());
        const after = page();
        after.months[1] = { ...after.months[1], currentTotal: 7, deviationPct: 16.7 };
        after.rows[0] = { ...after.rows[0], months: cells(4, 5, 4, 4) };
        setFrequency.mockResolvedValue(after);
        const el = createElement('c-team-target-list', { is: TeamTargetList });
        document.body.appendChild(el);
        await flush();
        el.shadowRoot.querySelector(`button[data-id="a1"][data-month="${NOV}"][data-step="1"]`).click();
        await flush();
        expect(setFrequency).toHaveBeenCalledWith({ atfId: 'a1', frequency: 5, monthStart: NOV, quarter: 'Q4-2026' });
        expect(el.shadowRoot.textContent).toContain('was 4');
        expect(el.shadowRoot.textContent).toContain('Nov 2026: 7 visits · +16.7% from 6');
        expect(el.shadowRoot.textContent).toContain('Dec 2026: 6 visits');
    });

    it('shows the server refusal and proposes an off-list doctor', async () => {
        getTeamTargets.mockResolvedValue(page());
        setFrequency.mockRejectedValue({ body: { message: 'The limit is ±10%.' } });
        proposeForTargetList.mockResolvedValue(
            page({ outOfTarget: [{ accountId: '001C', accountName: 'Dr Off', visits: 3, proposalStatus: 'Pending FI' }] })
        );
        const el = createElement('c-team-target-list', { is: TeamTargetList });
        document.body.appendChild(el);
        await flush();
        el.shadowRoot.querySelector(`button[data-id="a2"][data-month="${DEC}"][data-step="1"]`).click();
        await flush();
        expect(el.shadowRoot.querySelector('.ttl-note--error').textContent).toContain('±10%');
        el.shadowRoot.querySelector('button[data-id="001C"]').click();
        await flush();
        expect(proposeForTargetList).toHaveBeenCalledWith({ repId: '005A', accountId: '001C' });
        expect(el.shadowRoot.textContent).toContain('Pending FI');
    });
});
