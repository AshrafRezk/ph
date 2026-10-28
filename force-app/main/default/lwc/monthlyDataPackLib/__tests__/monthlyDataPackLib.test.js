import {
    KINDS,
    ERROR_HEADER,
    batchFileName,
    chunkArray,
    classifyWorkbook,
    csvEscape,
    errorLines,
    errorRecord,
    fingerprintBytes,
    fingerprintTag,
    isNoise,
    majorityMonth,
    mergeErrorCsv,
    normaliseTimeOffRows,
    normaliseVisitRows,
    sheetRowEstimate,
    splitSalesRows,
    unpackArchive
} from '../monthlyDataPackLib';

import epdaFixture from '../../distributorsManagement/__tests__/fixtures/epda-tabular.json';
import posTenderFixture from '../../distributorsManagement/__tests__/fixtures/pos-tender.json';
import ibnsinaFixture from '../../distributorsManagement/__tests__/fixtures/ibnsina-tender.json';

// The real JSZip build that ships as a static resource (UMD, so require() returns the constructor).
const JSZip = require('../../../staticresources/jszip/jszip.min.js');

// The adapters read sheets through globalThis.XLSX; fixtures store each sheet as an already-parsed matrix.
globalThis.XLSX = { utils: { sheet_to_json: (sheet) => sheet } };

function workbookFrom(fixture) {
    return { SheetNames: fixture.sheetNames, Sheets: fixture.sheets };
}

function matrixWorkbook(matrix) {
    return { SheetNames: ['Sheet1'], Sheets: { Sheet1: matrix } };
}

const LEAVE_HEADER = [
    'Employee', 'Code', 'Team', 'Type', 'From', 'Start Shift', 'To', 'End Shift',
    'Description', 'Balance', 'Has Attachment', 'StatusText', 'Date Added', 'Added By'
];
const TOT_HEADER = [
    'Employee', 'Code', 'Team', 'Type', 'From', 'Start Shift', 'To', 'End Shift',
    'Description', 'Has Attachment', 'StatusText', 'Date Added', 'Added By'
];
const VISIT_HEADER = [
    'Customer', 'Customer', 'Clinic Group', 'Specialty', 'Date', 'Time', 'Employee', 'Team',
    'Coach Employee', 'Spot Employee', 'Area', 'Platform', 'Platform Description', 'GPS Deviation',
    'Duration', 'Comments', 'Products', 'SpotCall', 'Coached', 'Planned', 'OutOfBoundaries', 'Status'
];

describe('unpackArchive', () => {
    async function buildNested() {
        const inner = new JSZip();
        inner.file('POS/pos tender sales (40).XLSX', 'pos-bytes');
        inner.file('__MACOSX/._junk', 'x');
        const deeper = new JSZip();
        deeper.file('Leave Details Sep2026.xlsx', 'leave-bytes');
        inner.file('sub/deeper.zip', await deeper.generateAsync({ type: 'uint8array' }));
        const outer = new JSZip();
        outer.file('22Oct/epda sales aug.xlsx', 'epda-bytes');
        outer.file('22Oct/readme.txt', 'not a sheet');
        outer.file('22Oct/~$lock.xlsx', 'lock');
        outer.file('22Oct/inner pack.zip', await inner.generateAsync({ type: 'uint8array' }));
        return outer.generateAsync({ type: 'uint8array' });
    }

    it('unpacks nested zips and keeps only real spreadsheets', async () => {
        const { entries, skipped } = await unpackArchive(await buildNested(), JSZip);
        const names = entries.map((e) => e.name).sort();
        expect(names).toEqual(['Leave Details Sep2026.xlsx', 'epda sales aug.xlsx', 'pos tender sales (40).XLSX']);
        const leave = entries.find((e) => e.name.startsWith('Leave'));
        expect(leave.viaArchives).toEqual(['inner pack.zip', 'deeper.zip']);
        expect(leave.path).toBe('22Oct/inner pack.zip!/sub/deeper.zip!/Leave Details Sep2026.xlsx');
        expect(Buffer.from(leave.data).toString()).toBe('leave-bytes');
        const reasons = skipped.map((s) => s.reason);
        expect(reasons).toContain('not a spreadsheet');
        expect(reasons).toContain('system file');
    });

    it('stops at the nesting limit instead of recursing forever', async () => {
        let bytes = await (async () => {
            const z = new JSZip();
            z.file('a.xlsx', 'a');
            return z.generateAsync({ type: 'uint8array' });
        })();
        for (let i = 0; i < 4; i++) {
            const z = new JSZip();
            z.file(`level${i}.zip`, bytes);
            // eslint-disable-next-line no-await-in-loop
            bytes = await z.generateAsync({ type: 'uint8array' });
        }
        const limited = await unpackArchive(bytes, JSZip, { maxDepth: 2 });
        expect(limited.entries).toHaveLength(0);
        expect(limited.skipped.some((s) => /nested deeper/.test(s.reason))).toBe(true);
        const full = await unpackArchive(bytes, JSZip, { maxDepth: 6 });
        expect(full.entries).toHaveLength(1);
    });

    it('flags noise paths', () => {
        expect(isNoise('__MACOSX/x/._a.xlsx')).toBe(true);
        expect(isNoise('22Oct/~$a.xlsx')).toBe(true);
        expect(isNoise('22Oct/a.xlsx')).toBe(false);
    });
});

describe('fingerprint', () => {
    it('is stable for the same bytes and different for different bytes', async () => {
        const a = await fingerprintBytes(new Uint8Array([1, 2, 3]));
        const b = await fingerprintBytes(new Uint8Array([1, 2, 3]));
        const c = await fingerprintBytes(new Uint8Array([1, 2, 4]));
        expect(a.hash).toBe(b.hash);
        expect(a.hash).not.toBe(c.hash);
        expect(a.short).toHaveLength(16);
    });

    it('tags the batch file name like Apex does', () => {
        expect(fingerprintTag('0123456789abcdefXYZ')).toBe(' [sha:0123456789abcdef]');
        expect(batchFileName('epda sales aug.xlsx', '0123456789abcdef')).toBe('epda sales aug.xlsx [sha:0123456789abcdef]');
        expect(fingerprintTag('')).toBe('');
    });
});

describe('classifyWorkbook', () => {
    it('recognises the three sales layouts from content', () => {
        expect(classifyWorkbook(workbookFrom(epdaFixture), 'epda sales aug.xlsx', epdaFixture.sheets.Sheet1.slice(0, 6))).toMatchObject({
            kind: KINDS.SALES,
            distributorCode: 'EPDA'
        });
        const posSheet = posTenderFixture.sheets[posTenderFixture.sheetNames[0]];
        expect(classifyWorkbook(workbookFrom(posTenderFixture), 'pos tender sales (40).XLSX', posSheet.slice(0, 6))).toMatchObject({
            kind: KINDS.SALES,
            distributorCode: 'POS'
        });
        const ibnSheet = ibnsinaFixture.sheets[ibnsinaFixture.sheetNames[0]];
        expect(
            classifyWorkbook(workbookFrom(ibnsinaFixture), 'Monthly_Sales_By_Client_Report_Tender_For_ZETA_PHARM_(TN)(IbnSinaTenderSales).xlsx', ibnSheet.slice(0, 6))
        ).toMatchObject({ kind: KINDS.SALES, distributorCode: 'IBNSINA' });
    });

    it('tells leave from time off territory by the Balance column', () => {
        const leave = classifyWorkbook(matrixWorkbook([LEAVE_HEADER]), 'Leave Details Sep2026.xlsx', [LEAVE_HEADER]);
        const tot = classifyWorkbook(matrixWorkbook([TOT_HEADER]), 'Time Off Territory Details Sep 2026.xlsx', [TOT_HEADER]);
        expect(leave.kind).toBe(KINDS.LEAVE);
        expect(tot.kind).toBe(KINDS.TOT);
    });

    it('recognises the visit log and leaves unknown files unknown', () => {
        expect(classifyWorkbook(matrixWorkbook([VISIT_HEADER]), 'MAY Visits.xlsx', [VISIT_HEADER]).kind).toBe(KINDS.VISIT);
        const unknown = classifyWorkbook(matrixWorkbook([['a', 'b']]), 'notes.xlsx', [['a', 'b']]);
        expect(unknown.kind).toBe(KINDS.UNKNOWN);
    });
});

describe('normaliseVisitRows', () => {
    it('maps the dual Customer columns and rejects blank employee or date', () => {
        const matrix = [
            VISIT_HEADER,
            ['Doctor', 'خالد الشرقاوي', null, 'Neuro', '2026-05-31', null, 'Abanob Ashraf', 'ORTHO-II', null, null, 'ميت غمر', 'Android', null, 0, 5, 'note', null, 'Normal', 'Not coached', 'Unplanned', 'x', 'Approved'],
            ['Doctor', 'محمد عطيه', null, 'Ortho', '2026-05-31', null, '', 'ORTHO-II', null, null, 'ميت غمر', 'Android', null, 0, 3, null, null, 'Normal', 'Not coached', 'Planned', 'x', 'Approved'],
            ['Pharmacy', 'صيدلية النور', null, null, 'bad-date', null, 'Rep', 'T', null, null, null, 'Android', null, 0, 1, null, null, 'Normal', 'Not coached', 'Planned', 'x', 'Approved']
        ];
        const { rows, errors, months } = normaliseVisitRows(matrix, 'MAY Visits.xlsx');
        expect(rows).toHaveLength(1);
        expect(rows[0]).toMatchObject({
            sourceRow: 2,
            customerType: 'Doctor',
            customerName: 'خالد الشرقاوي',
            employeeName: 'Abanob Ashraf',
            visitDate: '2026-05-31',
            planned: 'Unplanned',
            status: 'Approved'
        });
        expect(errors.map((e) => e.sourceRow)).toEqual([3, 4]);
        expect(months).toEqual({ '2026-05': 1 });
    });
});

describe('normaliseTimeOffRows', () => {
    const matrix = [
        LEAVE_HEADER,
        ['Milad Aziz', '1851', 'GIT-II', 'Emergency Leave', '2026-09-29', 'PM', '2026-09-29', 'PM', '..', null, false, 'Approved', '2026-10-05', 'x'],
        ['Shady Basta', 1898.0, 'DIAB-I', 'Annual Vacation', '9/28/26', 'AM', '9/30/26', 'PM', null, null, false, 'Pending', '2026-10-04', 'x'],
        ['No Code', '', 'T', 'Annual Vacation', '2026-09-01', 'AM', '2026-09-01', 'PM', null, null, false, 'Approved', null, null],
        ['Bad Date', '77', 'T', 'Annual Vacation', 'soon', 'AM', '2026-09-01', 'PM', null, null, false, 'Approved', null, null],
        ['Backwards', '78', 'T', 'Annual Vacation', '2026-09-05', 'AM', '2026-09-01', 'PM', null, null, false, 'Approved', null, null],
        [null, null, null, null, null, null, null, null, null, null, null, null, null, null]
    ];

    it('builds Apex-ready rows and sends bad rows to the error list with their sheet row number', () => {
        const { rows, errors, months } = normaliseTimeOffRows(matrix, KINDS.LEAVE, 'Leave Details Sep2026.xlsx');
        expect(rows).toHaveLength(2);
        expect(rows[0]).toMatchObject({
            sourceRow: 2,
            employeeCode: '1851',
            type: 'Emergency Leave',
            from: '2026-09-29',
            startShift: 'PM',
            endShift: 'PM',
            status: 'Approved'
        });
        expect(rows[1]).toMatchObject({ employeeCode: '1898', from: '2026-09-28', to: '2026-09-30' });
        expect(errors.map((e) => e.sourceRow)).toEqual([4, 5, 6]);
        expect(errors[0].message).toMatch(/code is blank/i);
        expect(errors[1].message).toMatch(/not a date/i);
        expect(errors[2].message).toMatch(/before From/i);
        expect(months).toEqual({ '2026-09': 2 });
        expect(majorityMonth(months)).toBe('2026-09');
    });

    it('reports a missing header row instead of throwing', () => {
        const { rows, errors } = normaliseTimeOffRows([['x', 'y']], KINDS.TOT, 'bad.xlsx');
        expect(rows).toHaveLength(0);
        expect(errors[0].message).toMatch(/Header row not found/);
    });
});

describe('error CSV', () => {
    it('escapes commas, quotes and newlines', () => {
        expect(csvEscape('a,b')).toBe('"a,b"');
        expect(csvEscape('say "hi"')).toBe('"say ""hi"""');
        expect(csvEscape('x')).toBe('x');
    });

    it('merges browser rejects with the server CSV under one header', () => {
        const client = [errorRecord({ kind: 'LEAVE', sourceFile: 'a.xlsx', sourceRow: 4, message: 'Employee code is blank.' })];
        expect(errorLines(client)[0]).toBe('LEAVE,a.xlsx,4,,,,,,error,Employee code is blank.');
        const server = `${ERROR_HEADER}\nTOT,b.xlsx,7,NOPE,Test,Office Work,2026-09-06,2026-09-06,error,No Salesforce user\n`;
        const salesLog = 'batch,file,severity,message\nSDIB-1,x.xlsx,log,Something happened';
        const merged = mergeErrorCsv(client, [server, salesLog, '']);
        const lines = merged.trim().split('\n');
        expect(lines[0]).toBe(ERROR_HEADER);
        expect(lines[1]).toContain('Employee code is blank.');
        expect(lines[2]).toContain('NOPE');
        expect(lines).toContain('batch,file,severity,message');
        expect(lines[lines.length - 1]).toBe('SDIB-1,x.xlsx,log,Something happened');
    });
});

describe('helpers', () => {
    it('chunks arrays', () => {
        expect(chunkArray([1, 2, 3, 4, 5], 2)).toEqual([[1, 2], [3, 4], [5]]);
        expect(chunkArray([], 3)).toEqual([]);
    });

    it('estimates rows from the full range even when only a few rows were read', () => {
        expect(sheetRowEstimate({ SheetNames: ['May'], Sheets: { May: { '!ref': 'A1:V6', '!fullref': 'A1:V101994' } } })).toBe(101993);
        expect(sheetRowEstimate({ SheetNames: ['S'], Sheets: { S: { '!ref': 'A1:C11' } } })).toBe(10);
        expect(sheetRowEstimate({ SheetNames: [], Sheets: {} })).toBe(0);
    });

    it('splits sales rows that cannot be imported', () => {
        const { good, errors } = splitSalesRows(
            [
                { itemCode: 'A', clientCode: 'C1' },
                { itemCode: '', clientCode: 'C2', clientName: 'Pharm' },
                { itemCode: 'B', clientCode: '' }
            ],
            'epda.xlsx'
        );
        expect(good).toHaveLength(1);
        expect(errors.map((e) => e.sourceRow)).toEqual([2, 3]);
        expect(errors[0].kind).toBe('SALES');
    });
});
