import { createElement } from 'lwc';
import BricksManagementConsole from 'c/bricksManagementConsole';
import getBrickMap from '@salesforce/apex/BricksManagementController.getBrickMap';
import getSalesPoints from '@salesforce/apex/BricksManagementController.getSalesPoints';
import saveBrickRegion from '@salesforce/apex/BricksManagementController.saveBrickRegion';
import saveBrickDetails from '@salesforce/apex/BricksManagementController.saveBrickDetails';
import locatePoint from '@salesforce/apex/BricksManagementController.locatePoint';
import getBrickPharmacies from '@salesforce/apex/BricksManagementController.getBrickPharmacies';
import getBrickTerritories from '@salesforce/apex/BricksManagementController.getBrickTerritories';
import suggestRegionFromName from '@salesforce/apex/BricksManagementController.suggestRegionFromName';
import getTerritoryTree from '@salesforce/apex/TerritoryManagementController.getTerritoryTree';
import getBrickClients from '@salesforce/apex/BricksManagementController.getBrickClients';
import getSalesFilters from '@salesforce/apex/BrickSalesMapController.getSalesFilters';
import getSalesChunk from '@salesforce/apex/BrickSalesMapController.getSalesChunk';
import getBrickSales from '@salesforce/apex/BrickSalesMapController.getBrickSales';
import getUnplacedSales from '@salesforce/apex/BrickSalesMapController.getUnplacedSales';
import getDistributorCounts from '@salesforce/apex/BrickSalesMapController.getDistributorCounts';

jest.mock('@salesforce/apex/BricksManagementController.getBrickMap', () => ({ default: jest.fn() }), { virtual: true });
jest.mock('@salesforce/apex/BricksManagementController.getSalesPoints', () => ({ default: jest.fn() }), { virtual: true });
jest.mock('@salesforce/apex/BricksManagementController.saveBrickDetails', () => ({ default: jest.fn() }), { virtual: true });
jest.mock('@salesforce/apex/BricksManagementController.saveBrickRegion', () => ({ default: jest.fn() }), { virtual: true });
jest.mock('@salesforce/apex/BricksManagementController.locatePoint', () => ({ default: jest.fn() }), { virtual: true });
jest.mock('@salesforce/apex/BricksManagementController.startSalesPlacement', () => ({ default: jest.fn() }), { virtual: true });
jest.mock('@salesforce/apex/BricksManagementController.getSalesPlacementStatus', () => ({ default: jest.fn() }), { virtual: true });
jest.mock('@salesforce/apex/BricksManagementController.getBrickTerritories', () => ({ default: jest.fn() }), { virtual: true });
jest.mock('@salesforce/apex/BricksManagementController.removeBrickTerritory', () => ({ default: jest.fn() }), { virtual: true });
jest.mock('@salesforce/apex/BricksManagementController.assignBrickToTerritory', () => ({ default: jest.fn() }), { virtual: true });
jest.mock('@salesforce/apex/BricksManagementController.getBrickPharmacies', () => ({ default: jest.fn() }), { virtual: true });
jest.mock('@salesforce/apex/BricksManagementController.searchPharmacyOptions', () => ({ default: jest.fn() }), { virtual: true });
jest.mock('@salesforce/apex/BricksManagementController.addPharmacyToBrick', () => ({ default: jest.fn() }), { virtual: true });
jest.mock('@salesforce/apex/BricksManagementController.removePharmacyFromBrick', () => ({ default: jest.fn() }), { virtual: true });
jest.mock('@salesforce/apex/BricksManagementController.deleteBrick', () => ({ default: jest.fn() }), { virtual: true });
jest.mock('@salesforce/apex/BricksManagementController.suggestRegionFromName', () => ({ default: jest.fn() }), { virtual: true });
jest.mock('@salesforce/apex/BricksManagementController.applyImsOutlines', () => ({ default: jest.fn() }), { virtual: true });
jest.mock('@salesforce/apex/BricksManagementController.getBrickClients', () => ({ default: jest.fn() }), { virtual: true });
jest.mock('@salesforce/apex/TerritoryManagementController.getTerritoryTree', () => ({ default: jest.fn() }), { virtual: true });
jest.mock('@salesforce/apex/BrickSalesMapController.getSalesFilters', () => ({ default: jest.fn() }), { virtual: true });
jest.mock('@salesforce/apex/BrickSalesMapController.getSalesChunk', () => ({ default: jest.fn() }), { virtual: true });
jest.mock('@salesforce/apex/BrickSalesMapController.getBrickSales', () => ({ default: jest.fn() }), { virtual: true });
jest.mock('@salesforce/apex/BrickSalesMapController.getUnplacedSales', () => ({ default: jest.fn() }), { virtual: true });
jest.mock('@salesforce/apex/BrickSalesMapController.getDistributorCounts', () => ({ default: jest.fn() }), { virtual: true });
jest.mock('lightning/confirm', () => ({ default: { open: jest.fn(() => Promise.resolve(true)) } }), { virtual: true });

const REGION = JSON.stringify({
    type: 'Polygon',
    coordinates: [[[31.29, 30.09], [31.31, 30.09], [31.31, 30.11], [31.29, 30.11], [31.29, 30.09]]]
});

function mapData() {
    return {
        level: '702',
        canEdit: true,
        bricks: [
            { id: 'a0B000000000001AAA', name: 'Nasr City 1', code: 'Nasr City 1', level: '702', parentId: 'a0B000000000009AAA', parentName: 'BRICK1 CAIRO EAST', isActive: true, accountSelectable: true, geometry: REGION, areaKm2: 4.26, clientCount: 2, regionSource: 'Drawn' },
            { id: 'a0B000000000002AAA', name: 'Heliopolis 3', code: 'HEL3', level: '702', parentId: 'a0B000000000009AAA', parentName: 'BRICK1 CAIRO EAST', isActive: false, accountSelectable: true, geometry: null, clientCount: 0 }
        ],
        parents: [{ id: 'a0B000000000009AAA', name: 'BRICK1 CAIRO EAST', level: '148' }],
        children: [],
        stats: { total702: 2, mapped702: 1, total148: 1, mapped148: 0, clientsTotal: 3, clientsWithLocation: 3, clientsPlaced: 2, clientsApproximate: 1, clientsOutside: 0, clientsNoLocation: 0 },
        job: null
    };
}

const POINTS = [
    { id: 'p1', name: 'Seif Pharmacy', distributor: 'Egydrug', lat: 30.1, lng: 31.3, placement: 'In region', brick702Id: 'a0B000000000001AAA' },
    { id: 'p2', name: 'El Ezaby', distributor: 'Egydrug', lat: 30.1, lng: 31.3, placement: 'Approximate location', precision: 'City' }
];

// eslint-disable-next-line @lwc/lwc/no-async-operation
const flush = () => new Promise((resolve) => setTimeout(resolve, 0));
const settle = (n) => Array.from({ length: n }).reduce((p) => p.then(flush), Promise.resolve());

async function mount() {
    getBrickMap.mockResolvedValue(mapData());
    getSalesPoints.mockResolvedValue(POINTS);
    getTerritoryTree.mockResolvedValue([{ id: '0MI000000000001AAA', name: 'Cairo', children: [] }]);
    getBrickPharmacies.mockResolvedValue([]);
    getBrickTerritories.mockResolvedValue([]);
    getBrickClients.mockResolvedValue(null);
    const el = createElement('c-bricks-management-console', { is: BricksManagementConsole });
    document.body.appendChild(el);
    await flush();
    await flush();
    const frame = el.shadowRoot.querySelector('iframe.bm-frame');
    const sent = [];
    frame.contentWindow.postMessage = jest.fn((msg) => sent.push(msg));
    return { el, frame, sent };
}

function fromMap(frame, data) {
    window.dispatchEvent(new MessageEvent('message', { data, origin: window.location.origin, source: frame.contentWindow }));
}

describe('c-bricks-management-console', () => {
    afterEach(() => {
        while (document.body.firstChild) document.body.removeChild(document.body.firstChild);
        jest.clearAllMocks();
    });

    it('lists bricks with their region state and coverage numbers', async () => {
        const { el } = await mount();
        const rows = el.shadowRoot.querySelectorAll('.bm-row');
        expect(rows).toHaveLength(2);
        expect(rows[0].textContent).toContain('Nasr City 1');
        expect(rows[0].textContent).toContain('4.26 km²');
        expect(rows[1].textContent).toContain('No region');
        expect(rows[1].textContent).toContain('Inactive');
        expect(el.shadowRoot.querySelector('.bm-stats').textContent).toContain('2 / 3');
        expect(getBrickMap).toHaveBeenCalledWith({ level: '702' });
    });

    it('filters the list by region and search text', async () => {
        const { el } = await mount();
        el.shadowRoot.querySelector('.bm-chip-btn[data-value="unmapped"]').click();
        await flush();
        expect(el.shadowRoot.querySelectorAll('.bm-row')).toHaveLength(1);
        el.shadowRoot.querySelector('.bm-chip-btn[data-value="all"]').click();
        const search = el.shadowRoot.querySelector('lightning-input');
        search.value = 'cairo east';
        search.dispatchEvent(new CustomEvent('change'));
        await flush();
        expect(el.shadowRoot.querySelectorAll('.bm-row')).toHaveLength(2);
    });

    it('says every brick has a region when the No region filter is empty', async () => {
        const data = mapData();
        data.bricks[1].geometry = REGION;
        getBrickMap.mockResolvedValue(data);
        getSalesPoints.mockResolvedValue(POINTS);
        getTerritoryTree.mockResolvedValue([]);
        const el = createElement('c-bricks-management-console', { is: BricksManagementConsole });
        document.body.appendChild(el);
        await flush();
        await flush();
        el.shadowRoot.querySelector('iframe.bm-frame').contentWindow.postMessage = jest.fn();
        el.shadowRoot.querySelector('.bm-chip-btn[data-value="unmapped"]').click();
        await flush();
        expect(el.shadowRoot.querySelectorAll('.bm-row')).toHaveLength(0);
        expect(el.shadowRoot.querySelector('.bm-empty').textContent).toBe('Every brick at this level has a region.');
    });

    it('lists every client placed in the selected brick, not only geocoded ones, with its latest sales', async () => {
        const { el } = await mount();
        getBrickClients.mockResolvedValue({
            total: 59,
            clients: [{ id: 'c1', name: 'Mina Pharmacy', distributor: 'Egydrug', address: 'Midan El Abbasiya', placement: 'Address match' }],
            salesMonth: '2026-09-01',
            salesLines: 195,
            salesQuantity: 536.6,
            salesRevenue: 120000
        });
        el.shadowRoot.querySelector('.bm-row').click();
        await flush();
        await flush();
        expect(getBrickClients).toHaveBeenCalledWith({ brickId: 'a0B000000000001AAA', level: '702' });
        const detail = el.shadowRoot.querySelector('.bm-detail').textContent;
        expect(detail).toContain('59 clients');
        expect(detail).toContain('Midan El Abbasiya');
        expect(detail).toContain('195 lines');
    });

    it('starts the map with the bricks once the frame loads, and trusts only its own frame', async () => {
        const { el, frame, sent } = await mount();
        frame.dispatchEvent(new CustomEvent('load'));
        const init = sent.find((m) => m.type === 'HOST_INIT');
        expect(init.level).toBe('702');
        expect(init.bricks).toHaveLength(2);
        expect(init.points).toHaveLength(2);
        expect(init.canEdit).toBe(true);

        window.dispatchEvent(new MessageEvent('message', { data: { type: 'HOST_BRICK_SELECT', id: 'a0B000000000001AAA' }, origin: 'https://evil.example', source: frame.contentWindow }));
        await flush();
        expect(el.shadowRoot.querySelector('.bm-detail')).toBeNull();

        fromMap(frame, { type: 'HOST_READY' });
        fromMap(frame, { type: 'HOST_BRICK_SELECT', id: 'a0B000000000001AAA' });
        await flush();
        const detail = el.shadowRoot.querySelector('.bm-detail');
        expect(detail.textContent).toContain('Nasr City 1');
        expect(detail.textContent).toContain('Seif Pharmacy');
    });

    it('saves a region drawn on the map and ends the edit', async () => {
        const { el, frame, sent } = await mount();
        frame.dispatchEvent(new CustomEvent('load'));
        fromMap(frame, { type: 'HOST_READY' });
        fromMap(frame, { type: 'HOST_BRICK_SELECT', id: 'a0B000000000002AAA' });
        await flush();
        const draw = [...el.shadowRoot.querySelectorAll('lightning-button')].find((b) => b.label === 'Draw region');
        draw.click();
        expect(sent.find((m) => m.type === 'HOST_EDIT')).toEqual({ type: 'HOST_EDIT', id: 'a0B000000000002AAA', mode: 'draw' });

        saveBrickRegion.mockResolvedValue({ id: 'a0B000000000002AAA' });
        const geometry = JSON.parse(REGION);
        fromMap(frame, { type: 'HOST_REGION_SAVE', id: 'a0B000000000002AAA', geometry, source: 'Drawn' });
        await flush();
        await flush();
        expect(saveBrickRegion).toHaveBeenCalledWith({ brickId: 'a0B000000000002AAA', geometry: JSON.stringify(geometry), source: 'Drawn' });
        expect(sent.some((m) => m.type === 'HOST_UPDATE')).toBe(true);
        expect(sent.find((m) => m.type === 'HOST_EDIT_END')).toMatchObject({ id: 'a0B000000000002AAA', message: 'Region saved.' });
    });

    it('sends a save error back to the map editor', async () => {
        const { frame, sent } = await mount();
        frame.dispatchEvent(new CustomEvent('load'));
        fromMap(frame, { type: 'HOST_READY' });
        saveBrickRegion.mockRejectedValue({ body: { message: 'The region has more than 5000 points. Simplify the outline.' } });
        fromMap(frame, { type: 'HOST_REGION_SAVE', id: 'a0B000000000001AAA', geometry: JSON.parse(REGION), source: 'Drawn' });
        await flush();
        await flush();
        expect(sent.find((m) => m.type === 'HOST_EDIT_ERROR').message).toContain('Simplify');
    });

    it('answers a find-brick click with the bricks at that point', async () => {
        const { frame, sent } = await mount();
        frame.dispatchEvent(new CustomEvent('load'));
        fromMap(frame, { type: 'HOST_READY' });
        locatePoint.mockResolvedValue({ status: 'In region', brick702Name: 'Nasr City 1', brick148Name: 'BRICK1 CAIRO EAST' });
        fromMap(frame, { type: 'HOST_LOCATE_POINT', seq: 4, lat: 30.1, lng: 31.3 });
        await flush();
        await flush();
        expect(locatePoint).toHaveBeenCalledWith({ latitude: 30.1, longitude: 31.3 });
        expect(sent.find((m) => m.type === 'HOST_LOCATE_RESULT')).toMatchObject({ seq: 4, brick702Name: 'Nasr City 1' });
    });

    it('opens the HAP editor with an OSM outline for the IMS brick name', async () => {
        const { el, frame, sent } = await mount();
        frame.dispatchEvent(new CustomEvent('load'));
        fromMap(frame, { type: 'HOST_READY' });
        fromMap(frame, { type: 'HOST_BRICK_SELECT', id: 'a0B000000000002AAA' });
        await flush();
        suggestRegionFromName.mockResolvedValue({
            geometry: JSON.stringify(JSON.parse(REGION)),
            source: 'Imported',
            displayName: 'Heliopolis, Cairo, Egypt'
        });
        [...el.shadowRoot.querySelectorAll('lightning-button')].find((b) => b.label === 'Suggest from OSM').click();
        await flush();
        await flush();
        expect(suggestRegionFromName).toHaveBeenCalledWith({ brickId: 'a0B000000000002AAA' });
        expect(sent.find((m) => m.type === 'HOST_EDIT')).toMatchObject({
            type: 'HOST_EDIT',
            id: 'a0B000000000002AAA',
            mode: 'edit',
            source: 'Imported'
        });
    });

    it('saves brick details with the current level', async () => {
        const { el, frame } = await mount();
        frame.dispatchEvent(new CustomEvent('load'));
        fromMap(frame, { type: 'HOST_READY' });
        fromMap(frame, { type: 'HOST_BRICK_SELECT', id: 'a0B000000000001AAA' });
        await flush();
        const name = el.shadowRoot.querySelector('.bm-detail lightning-input[data-field="name"]');
        name.value = 'Nasr City One';
        name.dispatchEvent(new CustomEvent('change', { detail: { value: 'Nasr City One' } }));
        await flush();
        saveBrickDetails.mockResolvedValue({ ...mapData().bricks[0], name: 'Nasr City One' });
        [...el.shadowRoot.querySelectorAll('lightning-button')].find((b) => b.label === 'Save details').click();
        await flush();
        expect(saveBrickDetails).toHaveBeenCalledWith({
            input: expect.objectContaining({ recordId: 'a0B000000000001AAA', level: '702', name: 'Nasr City One', parentId: 'a0B000000000009AAA' })
        });
    });
});

describe('c-bricks-management-console sales view', () => {
    const A = '01t000000000001AAA';
    const B = '01t000000000002AAA';
    const BRICK = 'a0B000000000001AAA';
    const FILTERS = {
        placed: [
            { source: 'IbnSina', month: '2026-09-01', productId: A, productName: 'Alpha', lines: 3 },
            { source: 'POS', month: '2026-09-01', productId: B, productName: 'Beta', lines: 2 },
            { source: 'IbnSina', month: '2026-08-01', productId: A, productName: 'Alpha', lines: 1 }
        ],
        unplaced: [{ source: 'IbnSina', month: '2026-09-01', productId: A, productName: 'Alpha', lines: 4 }]
    };
    const CHUNKS = {
        '2026-09-01': {
            bricks: [
                { brickId: BRICK, source: 'IbnSina', lines: 3, quantity: 30, revenue: 3000 },
                { brickId: BRICK, source: 'POS', lines: 2, quantity: 5, revenue: 500 }
            ],
            products: [
                { productId: A, productName: 'Alpha', source: 'IbnSina', lines: 3, quantity: 30, revenue: 3000 },
                { productId: B, productName: 'Beta', source: 'POS', lines: 2, quantity: 5, revenue: 500 }
            ]
        },
        '2026-08-01': {
            bricks: [{ brickId: BRICK, source: 'IbnSina', lines: 1, quantity: 10, revenue: 1000 }],
            products: [{ productId: A, productName: 'Alpha', source: 'IbnSina', lines: 1, quantity: 10, revenue: 1000 }]
        }
    };

    afterEach(() => {
        while (document.body.firstChild) document.body.removeChild(document.body.firstChild);
        jest.clearAllMocks();
    });

    async function openSales() {
        const ctx = await mount();
        getSalesFilters.mockResolvedValue(FILTERS);
        getSalesChunk.mockImplementation(({ month }) => Promise.resolve(CHUNKS[month]));
        getDistributorCounts.mockResolvedValue({
            sources: [
                { source: 'IbnSina', lines: 3, addressLines: 2, pointLines: 1, otherLines: 0, bricks: 1, unplacedRows: 4 },
                { source: 'POS', lines: 2, addressLines: 2, pointLines: 0, otherLines: 0, bricks: 1, unplacedRows: 0 }
            ],
            bricks: []
        });
        ctx.el.shadowRoot.querySelector('.bm-seg-btn[data-value="sales"]').click();
        await settle(8);
        return ctx;
    }

    function pick(el, cls, value) {
        el.shadowRoot.querySelector(cls).dispatchEvent(new CustomEvent('change', { detail: { value } }));
    }

    it('opens on the latest loaded month and shows sales per distributor and top products', async () => {
        const { el, sent } = await openSales();
        expect(el.shadowRoot.querySelector('.bm-note_warn').textContent).toContain('September 2026');
        expect(getSalesChunk).toHaveBeenCalledTimes(1);
        expect(getSalesChunk).toHaveBeenCalledWith({ level: '702', month: '2026-09-01', productIds: [A, B] });
        expect(getDistributorCounts).toHaveBeenCalledWith({ level: '702', startMonth: '2026-09-01', endMonth: '2026-09-01', productId: null });

        const chips = el.shadowRoot.querySelector('.bm-stats').textContent;
        expect(chips).toContain('EGP 3,500');
        expect(chips).not.toContain('with region');

        const rows = el.shadowRoot.querySelectorAll('.bm-dist-row');
        expect(rows).toHaveLength(4);
        expect(rows[1].textContent).toContain('IbnSina');
        expect(rows[1].textContent).toContain('EGP 3,000');
        expect(rows[1].textContent).toContain('85.7%');
        expect(rows[2].textContent).toContain('POS');
        expect(rows[3].textContent).toContain('All distributors');

        const top = el.shadowRoot.querySelectorAll('.bm-top-list li');
        expect(top).toHaveLength(2);
        expect(top[0].textContent).toContain('Alpha');

        const heat = sent.filter((m) => m.type === 'HOST_HEAT').pop().heat;
        expect(heat.values[BRICK].revenue).toBe(3500);
        expect(heat.sources[BRICK]).toBe('IbnSina EGP 3K · POS EGP 500');
        expect(el.shadowRoot.querySelector('.bm-row').textContent).toContain('IbnSina EGP 3K');
    });

    it('picking a distributor reshades without reading again', async () => {
        const { el, sent } = await openSales();
        el.shadowRoot.querySelectorAll('.bm-dist-row')[2].click();
        await settle(3);
        expect(getSalesChunk).toHaveBeenCalledTimes(1);
        expect(sent.filter((m) => m.type === 'HOST_HEAT').pop().heat.values[BRICK].revenue).toBe(500);
        expect(el.shadowRoot.querySelector('.bm-top h4').textContent).toContain('POS');
        expect(el.shadowRoot.querySelectorAll('.bm-top-list li')).toHaveLength(1);
    });

    it('a quarter reads each month and adds them up', async () => {
        const { el, sent } = await openSales();
        pick(el, '.bm-sales-quarter', '2026-Q3');
        await settle(8);
        expect(getSalesChunk).toHaveBeenCalledWith({ level: '702', month: '2026-08-01', productIds: [A] });
        expect(getDistributorCounts).toHaveBeenLastCalledWith({ level: '702', startMonth: '2026-07-01', endMonth: '2026-09-01', productId: null });
        expect(sent.filter((m) => m.type === 'HOST_HEAT').pop().heat.values[BRICK].revenue).toBe(4500);
        expect(el.shadowRoot.querySelector('.bm-sales-line').textContent).toContain('Jul – Sep 2026');
        expect(el.shadowRoot.querySelector('.bm-note_warn')).toBeNull();
    });

    it('start and end months set a custom range', async () => {
        const { el } = await openSales();
        pick(el, '.bm-sales-start', '2026-08-01');
        await settle(8);
        expect(getDistributorCounts).toHaveBeenLastCalledWith({ level: '702', startMonth: '2026-08-01', endMonth: '2026-09-01', productId: null });
        pick(el, '.bm-sales-end', '2026-08-01');
        await settle(8);
        expect(getDistributorCounts).toHaveBeenLastCalledWith({ level: '702', startMonth: '2026-08-01', endMonth: '2026-08-01', productId: null });
    });

    it('shows the brick breakdown by distributor and product', async () => {
        const { el, frame } = await openSales();
        getBrickSales.mockResolvedValue({
            lines: 3,
            quantity: 30,
            revenue: 3000,
            clientCount: 1,
            products: [{ productId: A, productName: 'Alpha', lines: 3, quantity: 30, revenue: 3000 }],
            clients: [{ clientId: 'a1C000000000001AAA', name: 'Seif', code: 'S1', distributor: 'IbnSina', placement: 'In region', lines: 3, quantity: 30, revenue: 3000 }]
        });
        fromMap(frame, { type: 'HOST_BRICK_SELECT', id: BRICK });
        await settle(4);
        expect(getBrickSales).toHaveBeenLastCalledWith({ brickId: BRICK, level: '702', source: null, startMonth: '2026-09-01', endMonth: '2026-09-01', productId: null });
        const detail = el.shadowRoot.querySelector('.bm-detail').textContent;
        expect(detail).toContain('Sales lines by distributor');
        expect(detail).toContain('EGP 3K · 3 lines');
        expect(detail).toContain('By product');
        expect(detail).toContain('Seif');
    });

    it('lists unplaced clients on the Not placed tab', async () => {
        const { el } = await openSales();
        getUnplacedSales.mockResolvedValue({
            lines: 4,
            quantity: 8,
            revenue: 800,
            clientCount: 1,
            placedSinceLines: 1,
            placedSinceRevenue: 70,
            products: [{ productId: A, productName: 'Alpha', lines: 4, quantity: 8, revenue: 800 }],
            clients: [{ clientId: 'a1C000000000002AAA', name: 'Nowhere', code: 'N1', distributor: 'IbnSina', placement: 'No location', lines: 4, quantity: 8, revenue: 800 }]
        });
        el.shadowRoot.querySelector('.bm-seg-btn[data-value="unplaced"]').click();
        await settle(4);
        expect(getUnplacedSales).toHaveBeenCalledWith({ source: null, startMonth: '2026-09-01', endMonth: '2026-09-01', productId: null });
        const panel = el.shadowRoot.querySelector('.bm-unplaced').textContent;
        expect(panel).toContain('EGP 800');
        expect(panel).toContain('Nowhere');
        expect(panel).toContain('placed since the import');
        expect(el.shadowRoot.querySelector('main').className).toContain('bm-map_covered');
    });

    it('goes back to the region numbers and clears the shading on Regions', async () => {
        const { el, sent } = await openSales();
        el.shadowRoot.querySelector('.bm-seg-btn[data-value="regions"]').click();
        await flush();
        expect(sent.filter((m) => m.type === 'HOST_HEAT').pop().heat).toBeNull();
        expect(el.shadowRoot.querySelector('.bm-sales-bar')).toBeNull();
        expect(el.shadowRoot.querySelector('.bm-stats').textContent).toContain('2 / 3');
    });
});
