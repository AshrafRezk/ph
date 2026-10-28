import { createElement } from 'lwc';
import MonthlyDataPack from 'c/monthlyDataPack';
import getHooks from '@salesforce/apex/DataPackImportService.getHooks';
import findDuplicateFingerprints from '@salesforce/apex/DataPackImportService.findDuplicateFingerprints';
import stageChunk from '@salesforce/apex/DataPackImportService.stageChunk';
import getBatchStatuses from '@salesforce/apex/DataPackImportService.getBatchStatuses';
import getBatchErrorCsv from '@salesforce/apex/DataPackImportService.getBatchErrorCsv';
import ingestNormalizedRows from '@salesforce/apex/DistributorsManagementController.ingestNormalizedRows';
import markImportBatchFailed from '@salesforce/apex/DistributorsManagementController.markImportBatchFailed';

import epdaFixture from '../../distributorsManagement/__tests__/fixtures/epda-tabular.json';

const JSZip = require('../../../staticresources/jszip/jszip.min.js');

jest.mock('@salesforce/apex/DataPackImportService.getHooks', () => ({ default: jest.fn() }), { virtual: true });
jest.mock('@salesforce/apex/DataPackImportService.findDuplicateFingerprints', () => ({ default: jest.fn() }), { virtual: true });
jest.mock('@salesforce/apex/DataPackImportService.stageChunk', () => ({ default: jest.fn() }), { virtual: true });
jest.mock('@salesforce/apex/DataPackImportService.getBatchStatuses', () => ({ default: jest.fn() }), { virtual: true });
jest.mock('@salesforce/apex/DataPackImportService.getBatchErrorCsv', () => ({ default: jest.fn() }), { virtual: true });
jest.mock('@salesforce/apex/DistributorsManagementController.ingestNormalizedRows', () => ({ default: jest.fn() }), { virtual: true });
jest.mock('@salesforce/apex/DistributorsManagementController.markImportBatchFailed', () => ({ default: jest.fn() }), { virtual: true });

// eslint-disable-next-line @lwc/lwc/no-async-operation
const flush = () => new Promise((resolve) => setTimeout(resolve, 0));
async function settle(times = 12) {
    for (let i = 0; i < times; i++) {
        // eslint-disable-next-line no-await-in-loop
        await flush();
    }
}

const LEAVE_HEADER = ['Employee', 'Code', 'Team', 'Type', 'From', 'Start Shift', 'To', 'End Shift', 'Description', 'Balance', 'Has Attachment', 'StatusText', 'Date Added', 'Added By'];
const TOT_HEADER = ['Employee', 'Code', 'Team', 'Type', 'From', 'Start Shift', 'To', 'End Shift', 'Description', 'Has Attachment', 'StatusText', 'Date Added', 'Added By'];
const VISIT_HEADER = ['Customer', 'Customer', 'Clinic Group', 'Specialty', 'Date', 'Time', 'Employee', 'Team', 'Coach Employee', 'Spot Employee', 'Area', 'Platform', 'Platform Description', 'GPS Deviation', 'Duration', 'Comments', 'Products', 'SpotCall', 'Coached', 'Planned', 'OutOfBoundaries', 'Status'];

// Each fake "file" holds the id of a workbook; the XLSX stub turns the bytes back into that workbook.
const WORKBOOKS = {
    leave: {
        SheetNames: ['Sheet1'],
        Sheets: {
            Sheet1: [
                LEAVE_HEADER,
                ['Milad', '1851', 'GIT-II', 'Emergency Leave', '2026-09-29', 'PM', '2026-09-29', 'PM', '..', null, false, 'Approved', '2026-10-05', 'x'],
                ['Bad', '', 'GIT-II', 'Emergency Leave', '2026-09-29', 'PM', '2026-09-29', 'PM', '..', null, false, 'Approved', '2026-10-05', 'x']
            ]
        }
    },
    tot: {
        SheetNames: ['Sheet1'],
        Sheets: {
            Sheet1: [
                TOT_HEADER,
                ['Mostafa', '207', 'DIAB-I', 'Office Work', '2026-09-30', 'AM', '2026-09-30', 'PM', null, false, 'Approved', '2026-10-13', 'x']
            ]
        }
    },
    epda: { SheetNames: epdaFixture.sheetNames, Sheets: epdaFixture.sheets },
    visit: {
        SheetNames: ['May'],
        Sheets: { May: Object.assign([VISIT_HEADER, ['Doctor', 'X', null, 'Neuro', '2026-05-31', null, 'Rep', 'ORTHO-II']], { '!ref': 'A1:V6', '!fullref': 'A1:V101994' }) }
    }
};

async function buildPack() {
    const inner = new JSZip();
    inner.file('Leave Details Sep2026.xlsx', 'leave');
    inner.file('Time Off Territory Details Sep 2026.xlsx', 'tot');
    const outer = new JSZip();
    outer.file('22Oct/epda sales aug.xlsx', 'epda');
    outer.file('22Oct/MAY Visits.xlsx', 'visit');
    outer.file('22Oct/hr.zip', await inner.generateAsync({ type: 'uint8array' }));
    outer.file('22Oct/__MACOSX/._x', 'junk');
    return outer.generateAsync({ type: 'uint8array' });
}

function mount() {
    const element = createElement('c-monthly-data-pack', { is: MonthlyDataPack });
    document.body.appendChild(element);
    return element;
}

async function dropZip(element) {
    const bytes = await buildPack();
    const input = [...element.shadowRoot.querySelectorAll('lightning-input')].find((i) => i.type === 'file');
    const file = { name: '22Oct.zip', arrayBuffer: () => Promise.resolve(bytes.buffer.slice(bytes.byteOffset, bytes.byteOffset + bytes.byteLength)) };
    Object.defineProperty(input, 'files', { value: [file], configurable: true });
    input.dispatchEvent(new CustomEvent('change'));
    await settle();
}

function rows(element) {
    return [...element.shadowRoot.querySelectorAll('table.dp-table tbody tr')].map((tr) => tr.textContent.replace(/\s+/g, ' ').trim());
}

function button(element, labelStart) {
    return [...element.shadowRoot.querySelectorAll('lightning-button')].find((b) => String(b.label).startsWith(labelStart));
}

describe('c-monthly-data-pack', () => {
    beforeEach(() => {
        window.JSZip = JSZip;
        globalThis.XLSX = {
            read: (bytes) => {
                const id = Buffer.from(bytes).toString();
                if (!WORKBOOKS[id]) throw new Error(`unreadable file ${id}`);
                return WORKBOOKS[id];
            },
            utils: { sheet_to_json: (sheet) => sheet }
        };
        getHooks.mockResolvedValue({ historicalVisitFlag: false, visitMessage: 'Historical visits stay in preview.' });
        findDuplicateFingerprints.mockResolvedValue([]);
        stageChunk.mockReset();
        ingestNormalizedRows.mockReset();
        markImportBatchFailed.mockReset();
        getBatchStatuses.mockReset();
        getBatchErrorCsv.mockReset();
    });

    afterEach(() => {
        while (document.body.firstChild) document.body.removeChild(document.body.firstChild);
        delete window.JSZip;
    });

    it('unpacks the nested zip, recognises each file and keeps visits as preview only', async () => {
        const element = mount();
        await settle(2);
        await dropZip(element);
        const text = rows(element);
        expect(text).toHaveLength(4);
        const joined = text.join('\n');
        expect(joined).toContain('Leave Details Sep2026.xlsx');
        expect(joined).toContain('Time Off Territory Details Sep 2026.xlsx');
        expect(joined).toMatch(/epda sales aug\.xlsx.*EPDA sales/);
        const visit = text.find((t) => t.startsWith('MAY Visits.xlsx') || t.includes('MAY Visits.xlsx'));
        expect(visit).toContain('Preview only');
        expect(visit).toContain('101,993');
        // The visit row's checkbox is disabled; the other three are selected.
        const boxes = [...element.shadowRoot.querySelectorAll('table.dp-table tbody lightning-input')];
        expect(boxes.filter((b) => b.checked)).toHaveLength(3);
        expect(boxes.filter((b) => b.disabled)).toHaveLength(1);
        // The month comes from the sales file dates only (the EPDA fixture is June); leave/TOT use their own dates.
        const month = [...element.shadowRoot.querySelectorAll('lightning-input')].find((i) => i.label === 'Report month (YYYY-MM)');
        expect(month.value).toBe('2026-06');
    });

    it('imports sales through the existing staged path and leave/TOT through the data pack path, then offers the error CSV', async () => {
        ingestNormalizedRows.mockResolvedValue({ batchId: 'a0f000000000001AAA', status: 'Queued', message: 'queued' });
        stageChunk.mockResolvedValueOnce({ batchId: 'a0f000000000002AAA', status: 'Queued' });
        stageChunk.mockResolvedValueOnce({ batchId: 'a0f000000000003AAA', status: 'Queued' });
        getBatchStatuses.mockResolvedValue([
            { batchId: 'a0f000000000001AAA', batchName: 'SDIB-1', status: 'Completed', rowsInserted: 5, rowsUpdated: 0, rowsFailed: 0, chunksExpected: 1, chunksProcessed: 1 },
            { batchId: 'a0f000000000002AAA', batchName: 'SDIB-2', status: 'Completed', rowsInserted: 1, rowsUpdated: 0, rowsFailed: 0, chunksExpected: 1, chunksProcessed: 1 },
            { batchId: 'a0f000000000003AAA', batchName: 'SDIB-3', status: 'Completed', rowsInserted: 1, rowsUpdated: 0, rowsFailed: 0, chunksExpected: 1, chunksProcessed: 1 }
        ]);

        const element = mount();
        await settle(2);
        await dropZip(element);

        const monthInput = [...element.shadowRoot.querySelectorAll('lightning-input')].find((i) => i.label === 'Report month (YYYY-MM)');
        monthInput.value = '2026-09';
        monthInput.dispatchEvent(new CustomEvent('change'));
        await settle(2);

        button(element, 'Import selected').click();
        await settle(20);

        expect(ingestNormalizedRows).toHaveBeenCalledTimes(1);
        const sales = ingestNormalizedRows.mock.calls[0][0];
        expect(sales.distributorCode).toBe('EPDA');
        expect(sales.reportMonth).toBe('2026-09');
        expect(sales.finalize).toBe(true);
        expect(sales.fileName).toMatch(/^epda sales aug\.xlsx \[sha:[0-9a-f]{16}\]$/);
        expect(sales.totalChunks).toBe(1);

        expect(stageChunk).toHaveBeenCalledTimes(2);
        const kinds = stageChunk.mock.calls.map((c) => c[0].kind).sort();
        expect(kinds).toEqual(['LEAVE', 'TOT']);
        const leaveCall = stageChunk.mock.calls.find((c) => c[0].kind === 'LEAVE')[0];
        const leaveRows = JSON.parse(leaveCall.rowsJson);
        expect(leaveRows).toHaveLength(1); // the row without a code never leaves the browser
        expect(leaveRows[0].employeeCode).toBe('1851');
        expect(leaveCall.fingerprint).toHaveLength(16);
        expect(leaveCall.reportMonth).toBe('2026-09'); // from the leave file's own dates, not the sales month field

        const progress = rows(element).filter((t) => /SDIB-\d/.test(t));
        expect(progress).toHaveLength(3);
        expect(progress.every((t) => t.includes('Completed'))).toBe(true);

        // Error CSV merges the browser reject with each server CSV.
        getBatchErrorCsv.mockImplementation(({ batchId }) =>
            Promise.resolve(`kind,source_file,source_row,employee_code,employee_name,type,from,to,severity,message\nTOT,x.xlsx,9,NOPE,,,,,error,from ${batchId}`)
        );
        const created = [];
        const origCreate = URL.createObjectURL;
        URL.createObjectURL = jest.fn((blob) => {
            created.push(blob);
            return 'blob:test';
        });
        const clickSpy = jest.spyOn(HTMLAnchorElement.prototype, 'click').mockImplementation(() => {});
        const downloadButton = button(element, 'Download error CSV');
        expect(downloadButton.disabled).toBe(false);
        downloadButton.click();
        await settle(6);
        URL.createObjectURL = origCreate;
        expect(clickSpy).toHaveBeenCalledTimes(1);
        clickSpy.mockRestore();
        expect(getBatchErrorCsv).toHaveBeenCalledTimes(3);
        expect(created).toHaveLength(1);
    });

    it('marks a batch failed when a chunk upload fails and still lists it', async () => {
        ingestNormalizedRows.mockResolvedValue({ batchId: 'a0f000000000001AAA', status: 'Queued' });
        stageChunk.mockRejectedValue({ body: { message: 'Chunk exploded' } });
        getBatchStatuses.mockResolvedValue([]);
        markImportBatchFailed.mockResolvedValue({ status: 'Failed' });
        const element = mount();
        await settle(2);
        await dropZip(element);
        const monthInput = [...element.shadowRoot.querySelectorAll('lightning-input')].find((i) => i.label === 'Report month (YYYY-MM)');
        monthInput.value = '2026-09';
        monthInput.dispatchEvent(new CustomEvent('change'));
        await settle(2);
        button(element, 'Import selected').click();
        await settle(20);
        const failed = rows(element).filter((t) => t.includes('Failed'));
        expect(failed.length).toBeGreaterThanOrEqual(2); // leave and TOT
    });

    it('warns about a file whose bytes were already imported and leaves it unticked', async () => {
        findDuplicateFingerprints.mockImplementation(({ fingerprints }) =>
            Promise.resolve([{ fingerprint: fingerprints[0], batchName: 'SDIB-00009', status: 'Completed' }])
        );
        const element = mount();
        await settle(2);
        await dropZip(element);
        const joined = rows(element).join('\n');
        expect(joined).toContain('Already imported');
        expect(joined).toContain('SDIB-00009');
    });
});
