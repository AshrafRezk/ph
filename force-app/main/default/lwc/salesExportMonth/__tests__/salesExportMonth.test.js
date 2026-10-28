import { createElement } from 'lwc';
import SalesExportMonth, {
    HEADERS,
    UNFIND_HEADERS,
    TOTAL_HEADERS,
    monthToDate,
    toSheetRow,
    unfindPharmacies,
    totalsByDistributor
} from 'c/salesExportMonth';
import listDataSources from '@salesforce/apex/PharmacySalesExportController.listDataSources';
import getExportPage from '@salesforce/apex/PharmacySalesExportController.getExportPage';

jest.mock('@salesforce/apex/PharmacySalesExportController.listDataSources', () => ({ default: jest.fn() }), {
    virtual: true
});
jest.mock('@salesforce/apex/PharmacySalesExportController.getExportPage', () => ({ default: jest.fn() }), {
    virtual: true
});

const flushPromises = () => new Promise((resolve) => jest.requireActual('timers').setImmediate(resolve));

describe('salesExportMonth helpers', () => {
    it('maps a line to the sheet columns with product and revenue', () => {
        const row = toSheetRow({
            reportMonth: '2026-09',
            dataSource: 'EPDA',
            pharmacy: 'P1',
            product: 'Prod',
            productCode: 'C1',
            quantity: 10,
            unitPrice: 5,
            revenue: 50,
            priceSource: 'File'
        });
        expect(row).toHaveLength(HEADERS.length);
        expect(row[HEADERS.indexOf('Product')]).toBe('Prod');
        expect(row[HEADERS.indexOf('Revenue')]).toBe(50);
        expect(toSheetRow({})[HEADERS.indexOf('Unit price')]).toBe('');
    });

    it('says where the sale landed: bricks, pharmacy link and the aligned line, territory and rep', () => {
        const row = toSheetRow({
            linkedPharmacy: false,
            brick: 'Dayrout',
            brick148: 'BRICK1 ASSUIT I-N VALLEY',
            brickSource: 'Sales location',
            line: 'GIT-I; GIT-SALES',
            territory: 'GIT-I ASSUIT-A; GIT-S ASSUIT-SOHAG-QUENA-ASWAN',
            rep: 'Rep One'
        });
        expect(row).toHaveLength(HEADERS.length);
        expect(row[HEADERS.indexOf('Linked CRM pharmacy')]).toBe('N');
        expect(row[HEADERS.indexOf('702 brick')]).toBe('Dayrout');
        expect(row[HEADERS.indexOf('148 brick')]).toBe('BRICK1 ASSUIT I-N VALLEY');
        expect(row[HEADERS.indexOf('Brick source')]).toBe('Sales location');
        expect(row[HEADERS.indexOf('Line')]).toBe('GIT-I; GIT-SALES');
        expect(row[HEADERS.indexOf('Territory')]).toBe('GIT-I ASSUIT-A; GIT-S ASSUIT-SOHAG-QUENA-ASWAN');
        expect(row[HEADERS.indexOf('Rep')]).toBe('Rep One');
        expect(toSheetRow({ linkedPharmacy: true })[HEADERS.indexOf('Linked CRM pharmacy')]).toBe('Y');
    });

    it('carries sub type, chain, client, placement and tender columns', () => {
        const row = toSheetRow({
            mainType: 'Private',
            subType: 'Abdeen Ph',
            chain: 'Abdeen Ph',
            clientCode: 'C1',
            placement: 'Unfind pharmacy',
            tender: true,
            brand: 'Nexicure'
        });
        expect(row[HEADERS.indexOf('Sub type')]).toBe('Abdeen Ph');
        expect(row[HEADERS.indexOf('Chain')]).toBe('Abdeen Ph');
        expect(row[HEADERS.indexOf('Main type')]).toBe('Private');
        expect(row[HEADERS.indexOf('Client code')]).toBe('C1');
        expect(row[HEADERS.indexOf('Placement')]).toBe('Unfind pharmacy');
        expect(row[HEADERS.indexOf('Tender')]).toBe('Y');
        expect(row[HEADERS.indexOf('Brand')]).toBe('Nexicure');
    });

    it('lists every client not linked to a CRM pharmacy once, biggest value first', () => {
        const rows = [
            { dataSource: 'POS', clientCode: 'A', clientName: 'Small', quantity: 1, revenue: 10, placement: 'Placed' },
            { dataSource: 'POS', clientCode: 'B', clientName: 'Big', quantity: 2, revenue: 50, placement: 'Unfind pharmacy' },
            { dataSource: 'POS', clientCode: 'B', clientName: 'Big', quantity: 3, revenue: 70, placement: 'Unfind pharmacy' },
            { dataSource: 'POS', clientCode: 'L', linkedPharmacy: true, quantity: 9, revenue: 900 }
        ];
        const list = unfindPharmacies(rows);
        expect(list).toHaveLength(2);
        expect(list[0]).toHaveLength(UNFIND_HEADERS.length);
        expect(list[0][UNFIND_HEADERS.indexOf('Client code')]).toBe('B');
        expect(list[0][UNFIND_HEADERS.indexOf('Sales lines')]).toBe(2);
        expect(list[0][UNFIND_HEADERS.indexOf('Revenue')]).toBe(120);
    });

    it('totals each distributor, split placed and unfind, with a grand total', () => {
        const totals = totalsByDistributor([
            { dataSource: 'POS', quantity: 2, revenue: 20, placement: 'Placed', line: 'GIT-I' },
            { dataSource: 'POS', quantity: 3, revenue: 30, placement: 'Unfind pharmacy' },
            { dataSource: 'IbnSina', quantity: 1, revenue: 5, placement: 'Placed', line: 'CHC' }
        ]);
        expect(totals.map((t) => t[0])).toEqual(['IbnSina', 'POS', 'All']);
        const pos = totals[1];
        expect(pos).toHaveLength(TOTAL_HEADERS.length);
        expect(pos[TOTAL_HEADERS.indexOf('Unfind pharmacy revenue')]).toBe(30);
        expect(pos[TOTAL_HEADERS.indexOf('No line quantity')]).toBe(3);
        expect(totals[2][TOTAL_HEADERS.indexOf('Total revenue')]).toBe(55);
    });

    it('turns a date or month into the first of the month', () => {
        expect(monthToDate('2026-09-17')).toBe('2026-09-01');
        expect(monthToDate('2026-09')).toBe('2026-09-01');
        expect(monthToDate('')).toBeNull();
    });
});

describe('c-sales-export-month', () => {
    beforeEach(() => {
        listDataSources.mockReset();
        getExportPage.mockReset();
        globalThis.XLSX = {
            utils: {
                aoa_to_sheet: jest.fn((m) => ({ m })),
                book_new: jest.fn(() => ({ sheets: [] })),
                book_append_sheet: jest.fn()
            },
            write: jest.fn(() => new Uint8Array([1, 2, 3]))
        };
        global.URL.createObjectURL = jest.fn(() => 'blob:x');
        global.URL.revokeObjectURL = jest.fn();
        jest.spyOn(HTMLAnchorElement.prototype, 'click').mockImplementation(() => {});
    });

    afterEach(() => {
        while (document.body.firstChild) document.body.removeChild(document.body.firstChild);
        delete globalThis.XLSX;
        jest.restoreAllMocks();
    });

    it('pages through the month and builds one workbook', async () => {
        listDataSources.mockResolvedValue(['EPDA']);
        getExportPage
            .mockResolvedValueOnce({ rows: [{ product: 'A', revenue: 1 }], hasMore: true, nextCursor: 'x', total: 2 })
            .mockResolvedValueOnce({ rows: [{ product: 'B', revenue: 2 }], hasMore: false });
        const element = createElement('c-sales-export-month', { is: SalesExportMonth });
        document.body.appendChild(element);

        const input = element.shadowRoot.querySelector('lightning-input');
        input.value = '2026-09-17';
        input.dispatchEvent(new CustomEvent('change'));
        await flushPromises();
        expect(listDataSources).toHaveBeenCalledWith({ reportMonth: '2026-09-01' });

        element.shadowRoot.querySelector('lightning-button').click();
        await flushPromises();
        await flushPromises();

        expect(getExportPage).toHaveBeenCalledTimes(2);
        expect(getExportPage.mock.calls[1][0].cursor).toBe('x');
        const matrix = globalThis.XLSX.utils.aoa_to_sheet.mock.calls[0][0];
        expect(matrix[0]).toEqual(HEADERS);
        expect(matrix).toHaveLength(3);
        const sheetNames = globalThis.XLSX.utils.book_append_sheet.mock.calls.map((c) => c[2]);
        expect(sheetNames).toEqual(['Consolidated sales', 'Unfind pharmacies', 'Totals by distributor']);
        expect(globalThis.XLSX.write).toHaveBeenCalled();
    });
});
