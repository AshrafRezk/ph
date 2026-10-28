import { createElement } from 'lwc';
import DistributorsManagement from 'c/distributorsManagement';
import ingestNormalizedRows from '@salesforce/apex/DistributorsManagementController.ingestNormalizedRows';
import markImportBatchFailed from '@salesforce/apex/DistributorsManagementController.markImportBatchFailed';
import getImportBatches from '@salesforce/apex/DistributorsManagementController.getImportBatches';

import epdaFixture from './fixtures/epda-tabular.json';

jest.mock(
    '@salesforce/apex/DistributorsManagementController.ingestNormalizedRows',
    () => ({ default: jest.fn() }),
    { virtual: true }
);
jest.mock(
    '@salesforce/apex/DistributorsManagementController.markImportBatchFailed',
    () => ({ default: jest.fn() }),
    { virtual: true }
);
jest.mock(
    '@salesforce/apex/DistributorsManagementController.getImportBatches',
    () => ({ default: jest.fn() }),
    { virtual: true }
);

// eslint-disable-next-line @lwc/lwc/no-async-operation
const flush = () => new Promise((resolve) => setTimeout(resolve, 0));

function mountComponent() {
    const element = createElement('c-distributors-management', { is: DistributorsManagement });
    document.body.appendChild(element);
    return element;
}

// LWC sets label / type as properties (not attributes), so find inputs by property.
function inputByLabel(element, label) {
    return [...element.shadowRoot.querySelectorAll('lightning-input')].find((i) => i.label === label);
}

function monthInput(element) {
    return inputByLabel(element, 'Report month (YYYY-MM)');
}

function monthValue(element) {
    return monthInput(element).value;
}

async function pickMonth(element, value) {
    const input = monthInput(element);
    input.value = value;
    input.dispatchEvent(new CustomEvent('change', { detail: { value } }));
    await flush();
}

async function chooseFile(element, name = 'bيع عملاء.xlsx') {
    const input = [...element.shadowRoot.querySelectorAll('lightning-input')].find((i) => i.type === 'file');
    const file = { name, arrayBuffer: () => Promise.resolve(new ArrayBuffer(8)) };
    Object.defineProperty(input, 'files', { value: [file], configurable: true });
    input.dispatchEvent(new CustomEvent('change'));
    await flush();
    await flush();
}

describe('c-distributors-management import', () => {
    beforeEach(() => {
        // The SheetJS static resource is replaced by a stub that returns a ready-made workbook.
        globalThis.XLSX = {
            read: () => ({ SheetNames: epdaFixture.sheetNames, Sheets: epdaFixture.sheets }),
            utils: { sheet_to_json: (sheet) => sheet }
        };
        ingestNormalizedRows.mockReset();
        markImportBatchFailed.mockReset();
        getImportBatches.mockResolvedValue([]);
    });

    afterEach(() => {
        while (document.body.firstChild) {
            document.body.removeChild(document.body.firstChild);
        }
    });

    it('fills the report month from the file when the user has not picked one', async () => {
        const element = mountComponent();
        await flush();
        await chooseFile(element);
        expect(monthValue(element)).toBe('2026-06');
    });

    it('never replaces a month the user picked with the month detected in the file', async () => {
        const element = mountComponent();
        await flush();
        await pickMonth(element, '2026-05');
        await chooseFile(element);
        expect(monthValue(element)).toBe('2026-05');
        const notice = [...element.shadowRoot.querySelectorAll('p.warn')].map((p) => p.textContent).join(' ');
        expect(notice).toContain('2026-06');
        expect(notice).toContain('2026-05');
    });

    it('marks the batch failed in the browser when a chunk fails', async () => {
        ingestNormalizedRows.mockResolvedValueOnce({ batchId: 'a0f000000000001AAA', message: 'ok', status: 'Uploading' });
        ingestNormalizedRows.mockRejectedValueOnce({ body: { message: 'Chunk exploded' } });
        markImportBatchFailed.mockResolvedValue({ status: 'Failed' });

        const element = mountComponent();
        await flush();
        // Force several chunks so the second one fails: 2000 synthetic rows from the fixture row.
        const sheet = epdaFixture.sheets.Sheet1;
        const many = [sheet[0]];
        for (let i = 0; i < 2000; i++) {
            many.push(sheet[1]);
        }
        globalThis.XLSX.read = () => ({ SheetNames: ['Sheet1'], Sheets: { Sheet1: many } });
        const maxRows = inputByLabel(element, 'Max rows (pilot)');
        maxRows.value = 0;
        maxRows.dispatchEvent(new CustomEvent('change'));
        await flush();
        await chooseFile(element);

        const importButton = [...element.shadowRoot.querySelectorAll('lightning-button')].find((b) =>
            String(b.label).startsWith('Import')
        );
        expect(importButton).not.toBeNull();
        importButton.click();
        await flush();
        await flush();
        await flush();

        expect(ingestNormalizedRows).toHaveBeenCalledTimes(2);
        const firstCall = ingestNormalizedRows.mock.calls[0][0];
        expect(firstCall.chunkIndex).toBe(0);
        expect(firstCall.totalChunks).toBe(2);
        expect(firstCall.reportMonth).toBe('2026-06');
        expect(markImportBatchFailed).toHaveBeenCalledTimes(1);
        expect(markImportBatchFailed.mock.calls[0][0].batchId).toBe('a0f000000000001AAA');
    });
});
