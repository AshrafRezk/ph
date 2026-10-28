import { createElement } from 'lwc';
import RepSalesVsTarget from 'c/repSalesVsTarget';
import getMySalesVsTarget from '@salesforce/apex/RepSalesTargetController.getMySalesVsTarget';
import { subscribeTerritoryContext } from 'c/territoryContextClient';

jest.mock(
    '@salesforce/apex/RepSalesTargetController.getMySalesVsTarget',
    () => ({ default: jest.fn() }),
    { virtual: true }
);
jest.mock(
    '@salesforce/apex/RepSalesTargetController.getMySalesByBrick',
    () => ({ default: jest.fn() }),
    { virtual: true }
);
jest.mock('@salesforce/resourceUrl/leaflet', () => ({ default: 'leaflet' }), { virtual: true });
jest.mock('c/plannerMapPins', () => ({ ensureLeaflet: jest.fn() }), { virtual: true });
jest.mock(
    'c/fieldFeatureFlags',
    () => ({ isFieldFeatureEnabled: () => true, loadFieldFeatures: () => Promise.resolve() }),
    { virtual: true }
);
jest.mock(
    'c/territoryContextClient',
    () => ({ subscribeTerritoryContext: jest.fn(() => ({})), unsubscribeTerritoryContext: jest.fn() }),
    { virtual: true }
);

function payload(brickCount, revenue) {
    return {
        brickCount,
        productCount: 3,
        months: [{ monthKey: '2026-09', monthLabel: 'Sep 2026', quantity: 10, revenue, achievementPercent: null }]
    };
}

function deferred() {
    let resolve;
    const promise = new Promise((r) => {
        resolve = r;
    });
    return { promise, resolve };
}

// eslint-disable-next-line @lwc/lwc/no-async-operation
const flush = () => new Promise((r) => setTimeout(r, 0));

function territoryHandler() {
    const calls = subscribeTerritoryContext.mock.calls;
    return calls[calls.length - 1][1];
}

describe('c-rep-sales-vs-target', () => {
    afterEach(() => {
        while (document.body.firstChild) {
            document.body.removeChild(document.body.firstChild);
        }
        jest.clearAllMocks();
    });

    it('reloads right after a territory switch', async () => {
        getMySalesVsTarget.mockResolvedValueOnce(payload(40, 1000)).mockResolvedValueOnce(payload(7, 2000));
        const el = createElement('c-rep-sales-vs-target', { is: RepSalesVsTarget });
        document.body.appendChild(el);
        await flush();
        expect(el.shadowRoot.querySelector('.sales-scope').textContent).toContain('40 bricks');

        territoryHandler()({ territoryId: '0MI000000000001', usingAllAssigned: false });
        await flush();

        expect(getMySalesVsTarget).toHaveBeenCalledTimes(2);
        expect(el.shadowRoot.querySelector('.sales-scope').textContent).toContain('7 bricks');
    });

    it('ignores a late answer for the previous territory', async () => {
        const first = deferred();
        getMySalesVsTarget.mockReturnValueOnce(first.promise).mockResolvedValueOnce(payload(7, 2000));
        const el = createElement('c-rep-sales-vs-target', { is: RepSalesVsTarget });
        document.body.appendChild(el);
        await flush();

        territoryHandler()({ territoryId: '0MI000000000001', usingAllAssigned: false });
        await flush();
        first.resolve(payload(40, 1000));
        await flush();

        expect(el.shadowRoot.querySelector('.sales-scope').textContent).toContain('7 bricks');
    });

    it('shows the rep share when visits are summarised', async () => {
        getMySalesVsTarget.mockResolvedValueOnce({
            ...payload(47, 4000),
            visitedBrickCount: 5,
            shareAvailable: true,
            shareQuantity: 10,
            shareRevenue: 1000,
            sharePercent: 25,
            months: [
                {
                    monthKey: '2026-09',
                    monthLabel: 'Sep 2026',
                    quantity: 40,
                    revenue: 4000,
                    shareQuantity: 10,
                    shareRevenue: 1000,
                    sharePercent: 25
                }
            ]
        });
        const el = createElement('c-rep-sales-vs-target', { is: RepSalesVsTarget });
        document.body.appendChild(el);
        await flush();

        expect(el.shadowRoot.querySelector('.sales-scope').textContent).toContain('47 bricks (5 from your visits)');
        expect(el.shadowRoot.querySelector('.share-summary').textContent).toContain('(25%)');
        expect(el.shadowRoot.querySelector('.month-share').textContent).toContain('Your share 10 units');
    });

    it('says the share is not ready before the nightly summary', async () => {
        getMySalesVsTarget.mockResolvedValueOnce({ ...payload(3, 100), shareAvailable: false });
        const el = createElement('c-rep-sales-vs-target', { is: RepSalesVsTarget });
        document.body.appendChild(el);
        await flush();

        expect(el.shadowRoot.querySelector('.share-summary')).toBeNull();
        expect(el.shadowRoot.querySelector('.month-share')).toBeNull();
        const notes = [...el.shadowRoot.querySelectorAll('.sales-footnote')].map((n) => n.textContent).join(' ');
        expect(notes).toContain('summarised (nightly)');
    });
});
