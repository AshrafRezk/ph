/**
 * Pure helpers for the Monthly data pack card. No DOM, no Apex: everything here is unit tested.
 *
 * File kinds the card knows about (extend KINDS + classifyWorkbook + normalise* to add one):
 *   SALES  EPDA / POS / IBNSINA (and the other distributor layouts) -> DistributorsManagementController.ingestNormalizedRows
 *   LEAVE  HR "Leave Details" export                                  -> DataPackImportService (PACK:LEAVE)
 *   TOT    HR "Time Off Territory Details" export                     -> DataPackImportService (PACK:TOT)
 *   VISIT  Mobile visit log (about 100k rows per month)                -> DataPackImportService (PACK:VISIT) when flag exists
 */
import {
    detectDistributor,
    detectDistributorFromWorkbook,
    isValidReportMonth,
    parseSheetDate
} from 'c/distributorAdapters';

export const KINDS = {
    SALES: 'SALES',
    LEAVE: 'LEAVE',
    TOT: 'TOT',
    VISIT: 'VISIT',
    UNKNOWN: 'UNKNOWN'
};

export const KIND_LABELS = {
    SALES: 'Sales',
    LEAVE: 'Leave',
    TOT: 'Time off territory',
    VISIT: 'Visits',
    UNKNOWN: 'Not recognised'
};

export const SPREADSHEET_EXT = /\.(xlsx|xlsm|xls|csv)$/i;
const NOISE_PATH = /(^|\/)(__MACOSX|\.DS_Store|Thumbs\.db)(\/|$)|(^|\/)~\$/i;

export const ERROR_HEADER = 'kind,source_file,source_row,employee_code,employee_name,type,from,to,severity,message';

export const LEAVE_TOT_CHUNK = 150;
export const VISIT_CHUNK = 80;
export const SALES_CHUNK = 1500;

// ---------- unzip ----------

/** True for entries we never want (macOS resource forks, lock files, folders). */
export function isNoise(path) {
    return NOISE_PATH.test(String(path || ''));
}

/**
 * Unpack a zip held in memory, descending into nested zips.
 * Returns { entries, skipped } where entries are spreadsheet files:
 *   { path, name, size, data (Uint8Array), viaArchives: ['outer.zip', 'inner.zip'] }
 * and skipped are { path, reason } for everything else.
 */
export async function unpackArchive(buffer, JSZip, options = {}) {
    const maxDepth = options.maxDepth || 5;
    const maxEntries = options.maxEntries || 400;
    const entries = [];
    const skipped = [];

    /* eslint-disable no-await-in-loop */
    async function walk(data, prefix, via, depth) {
        const zip = await JSZip.loadAsync(data);
        const names = Object.keys(zip.files);
        for (const name of names) {
            const file = zip.files[name];
            if (file.dir) continue;
            const path = prefix + name;
            if (isNoise(name)) {
                skipped.push({ path, reason: 'system file' });
                continue;
            }
            if (/\.zip$/i.test(name)) {
                if (depth >= maxDepth) {
                    skipped.push({ path, reason: `nested deeper than ${maxDepth} levels` });
                    continue;
                }
                const inner = await file.async('uint8array');
                await walk(inner, `${path}!/`, [...via, name.split('/').pop()], depth + 1);
                continue;
            }
            if (!SPREADSHEET_EXT.test(name)) {
                skipped.push({ path, reason: 'not a spreadsheet' });
                continue;
            }
            if (entries.length >= maxEntries) {
                skipped.push({ path, reason: `more than ${maxEntries} files` });
                continue;
            }
            const bytes = await file.async('uint8array');
            entries.push({
                path,
                name: name.split('/').pop(),
                size: bytes.length,
                data: bytes,
                viaArchives: via
            });
        }
    }

    /* eslint-enable no-await-in-loop */
    await walk(buffer, '', [], 0);
    return { entries, skipped };
}

// ---------- fingerprint ----------

function fnv1a(bytes) {
    let h1 = 0x811c9dc5;
    let h2 = 0x01000193;
    for (let i = 0; i < bytes.length; i++) {
        h1 = Math.imul(h1 ^ bytes[i], 0x01000193) >>> 0;
        h2 = Math.imul(h2 + bytes[i], 0x85ebca6b) >>> 0;
    }
    return h1.toString(16).padStart(8, '0') + h2.toString(16).padStart(8, '0');
}

/** SHA-256 when the browser has it, otherwise a 64-bit FNV style hash. Same bytes always give the same value. */
export async function fingerprintBytes(bytes) {
    const subtle = globalThis.crypto && globalThis.crypto.subtle;
    if (subtle && typeof subtle.digest === 'function') {
        try {
            const digest = await subtle.digest('SHA-256', bytes);
            const hex = Array.from(new Uint8Array(digest))
                .map((b) => b.toString(16).padStart(2, '0'))
                .join('');
            return { algorithm: 'sha256', hash: hex, short: hex.slice(0, 16) };
        } catch (e) { // eslint-disable-line no-unused-vars
            // fall through to the portable hash
        }
    }
    const hash = fnv1a(bytes);
    return { algorithm: 'fnv', hash, short: hash.slice(0, 16) };
}

/** Tag appended to Sales_Data_Import_Batch__c.File_Name__c so a repeat upload can be spotted. Matches Apex fingerprintTag. */
export function fingerprintTag(short) {
    return short ? ` [sha:${String(short).slice(0, 16)}]` : '';
}

export function batchFileName(name, short) {
    return `${String(name || 'file.xlsx').slice(0, 230)}${fingerprintTag(short)}`;
}

// ---------- classify ----------

function norm(c) {
    return c == null
        ? ''
        : String(c)
              .replace(/[\u00a0\s]+/g, ' ')
              .trim()
              .toLowerCase();
}

function headerSet(matrix, maxRows = 6) {
    const set = new Set();
    for (let i = 0; i < Math.min(matrix.length, maxRows); i++) {
        (matrix[i] || []).forEach((c) => {
            const n = norm(c);
            if (n) set.add(n);
        });
    }
    return set;
}

export function readFirstRows(workbook, XLSX, maxRows = 6) {
    const name = workbook.SheetNames && workbook.SheetNames[0];
    const sheet = name && workbook.Sheets[name];
    if (!sheet) return [];
    return XLSX.utils.sheet_to_json(sheet, { header: 1, defval: null, raw: false }).slice(0, maxRows);
}

/**
 * Decide what a workbook is. `firstRows` is the first few rows of the first sheet (matrix).
 * Whole-cell header matches only, never substring matches.
 */
export function classifyWorkbook(workbook, fileName, firstRows) {
    const headers = headerSet(firstRows || []);
    const lowerName = String(fileName || '').toLowerCase();
    const hasShifts = headers.has('start shift') && headers.has('end shift');
    if (hasShifts && headers.has('statustext') && headers.has('employee') && headers.has('code')) {
        if (headers.has('balance') || /leave/.test(lowerName)) {
            return { kind: KINDS.LEAVE, label: 'Leave details', reason: 'Employee / Code / Start Shift / Balance headers' };
        }
        return { kind: KINDS.TOT, label: 'Time off territory', reason: 'Employee / Code / Start Shift headers without Balance' };
    }
    if (headers.has('employee') && headers.has('customer') && headers.has('platform') && headers.has('planned') && headers.has('date')) {
        return { kind: KINDS.VISIT, label: 'Visit log', reason: 'Customer / Employee / Platform / Planned headers' };
    }
    const fromName = detectDistributor(fileName);
    let fromContent = '';
    try {
        fromContent = detectDistributorFromWorkbook(workbook);
    } catch (e) { // eslint-disable-line no-unused-vars
        fromContent = '';
    }
    // Content wins over the file name (names like "ZETA PHARM ..." say nothing).
    const code = fromContent || fromName;
    if (code) {
        return {
            kind: KINDS.SALES,
            distributorCode: code,
            label: `${code} sales`,
            reason: fromContent ? 'sheet layout' : 'file name'
        };
    }
    return { kind: KINDS.UNKNOWN, label: 'Not recognised', reason: 'No known header layout' };
}

// ---------- leave / TOT rows ----------

function findHeaderRow(matrix, required, maxScan = 10) {
    for (let i = 0; i < Math.min(matrix.length, maxScan); i++) {
        const cells = new Set((matrix[i] || []).map(norm).filter(Boolean));
        if (required.every((r) => cells.has(r))) return i;
    }
    return -1;
}

function cellText(v) {
    return v == null ? '' : String(v).trim();
}

function cleanCode(v) {
    const s = cellText(v);
    return /^\d+\.0+$/.test(s) ? s.replace(/\.0+$/, '') : s;
}

/**
 * Turn the HR leave / TOT matrix into rows for DataPackImportService.
 * @returns {{ rows: object[], errors: object[], months: Object<string, number> }}
 *   errors are CSV-ready objects for rows that never leave the browser.
 */
export function normaliseTimeOffRows(matrix, kind, sourceFile) {
    const required = ['employee', 'code', 'from', 'to', 'statustext'];
    const headerIndex = findHeaderRow(matrix || [], required);
    const rows = [];
    const errors = [];
    const months = {};
    if (headerIndex < 0) {
        errors.push(
            errorRecord({
                kind,
                sourceFile,
                sourceRow: '',
                severity: 'error',
                message: 'Header row not found (needs Employee, Code, From, To, StatusText).'
            })
        );
        return { rows, errors, months };
    }
    const headers = matrix[headerIndex].map(norm);
    const col = (name) => headers.indexOf(name);
    const idx = {
        employee: col('employee'),
        code: col('code'),
        team: col('team'),
        type: col('type'),
        from: col('from'),
        startShift: col('start shift'),
        to: col('to'),
        endShift: col('end shift'),
        description: col('description'),
        status: col('statustext')
    };
    for (let i = headerIndex + 1; i < matrix.length; i++) {
        const line = matrix[i];
        if (!line || line.every((c) => c == null || cellText(c) === '')) continue;
        const sourceRow = i + 1;
        const row = {
            sourceRow,
            employeeCode: cleanCode(line[idx.code]),
            employeeName: cellText(line[idx.employee]),
            team: idx.team >= 0 ? cellText(line[idx.team]) : '',
            type: idx.type >= 0 ? cellText(line[idx.type]) : '',
            from: parseSheetDate(line[idx.from]),
            startShift: idx.startShift >= 0 ? cellText(line[idx.startShift]).toUpperCase() : '',
            to: parseSheetDate(line[idx.to]),
            endShift: idx.endShift >= 0 ? cellText(line[idx.endShift]).toUpperCase() : '',
            description: idx.description >= 0 ? cellText(line[idx.description]) : '',
            status: idx.status >= 0 ? cellText(line[idx.status]) : ''
        };
        let problem = '';
        if (!row.employeeCode) problem = 'Employee code is blank.';
        else if (!row.type) problem = 'Type is blank.';
        else if (!row.from || !row.to) problem = `From / To is not a date (${cellText(line[idx.from])} / ${cellText(line[idx.to])}).`;
        else if (row.to < row.from) problem = 'To date is before From date.';
        if (problem) {
            errors.push(errorRecord({ kind, sourceFile, severity: 'error', message: problem, ...row }));
            continue;
        }
        rows.push(row);
        const ym = row.from.slice(0, 7);
        months[ym] = (months[ym] || 0) + 1;
    }
    return { rows, errors, months };
}

export function majorityMonth(counts) {
    let best = '';
    let bestCount = 0;
    Object.keys(counts || {}).forEach((ym) => {
        if (counts[ym] > bestCount || (counts[ym] === bestCount && ym > best)) {
            best = ym;
            bestCount = counts[ym];
        }
    });
    return best;
}

/**
 * Turn a mobile visit log matrix into rows for DataPackImportService (PACK:VISIT).
 * Header has two "Customer" columns: type (Doctor/Pharmacy/...) then name.
 * @returns {{ rows: object[], errors: object[], months: Object<string, number> }}
 */
export function normaliseVisitRows(matrix, sourceFile) {
    const rows = [];
    const errors = [];
    const months = {};
    if (!matrix || !matrix.length) {
        errors.push(
            errorRecord({
                kind: KINDS.VISIT,
                sourceFile,
                severity: 'error',
                message: 'Visit sheet is empty.'
            })
        );
        return { rows, errors, months };
    }
    const headerIndex = findVisitHeaderRow(matrix);
    if (headerIndex < 0) {
        errors.push(
            errorRecord({
                kind: KINDS.VISIT,
                sourceFile,
                severity: 'error',
                message: 'Header row not found (needs Customer, Date, Employee, Planned, Status).'
            })
        );
        return { rows, errors, months };
    }
    const header = matrix[headerIndex] || [];
    const idx = visitColumnIndex(header);
    for (let i = headerIndex + 1; i < matrix.length; i++) {
        const line = matrix[i];
        if (!line || line.every((c) => c == null || cellText(c) === '')) continue;
        const sourceRow = i + 1;
        const row = {
            sourceRow,
            employeeCode: '',
            employeeName: cellText(line[idx.employee]),
            customerType: cellText(line[idx.customerType]),
            customerName: cellText(line[idx.customerName]),
            type: cellText(line[idx.customerName]),
            visitDate: parseSheetDate(line[idx.date]),
            from: parseSheetDate(line[idx.date]),
            to: parseSheetDate(line[idx.date]),
            planned: cellText(line[idx.planned]),
            status: cellText(line[idx.status]),
            comments: idx.comments >= 0 ? cellText(line[idx.comments]) : '',
            products: idx.products >= 0 ? cellText(line[idx.products]) : '',
            team: idx.team >= 0 ? cellText(line[idx.team]) : ''
        };
        let problem = '';
        if (!row.employeeName) problem = 'Employee name is blank.';
        else if (!row.customerName) problem = 'Customer name is blank.';
        else if (!row.visitDate) problem = `Visit date is not a date (${cellText(line[idx.date])}).`;
        else if (!row.planned) problem = 'Planned flag is blank.';
        else if (!row.status) problem = 'Status is blank.';
        if (problem) {
            errors.push(errorRecord({ kind: KINDS.VISIT, sourceFile, severity: 'error', message: problem, ...row }));
            continue;
        }
        rows.push(row);
        const ym = row.visitDate.slice(0, 7);
        months[ym] = (months[ym] || 0) + 1;
    }
    return { rows, errors, months };
}

function findVisitHeaderRow(matrix, maxScan = 6) {
    for (let i = 0; i < Math.min(matrix.length, maxScan); i++) {
        const cells = (matrix[i] || []).map(norm);
        const set = new Set(cells.filter(Boolean));
        if (set.has('customer') && set.has('employee') && set.has('date') && set.has('planned') && set.has('status')) {
            return i;
        }
    }
    return -1;
}

function visitColumnIndex(header) {
    const norms = (header || []).map(norm);
    const first = (name) => norms.indexOf(name);
    const customerIndexes = [];
    norms.forEach((n, i) => {
        if (n === 'customer') customerIndexes.push(i);
    });
    return {
        customerType: customerIndexes[0] >= 0 ? customerIndexes[0] : -1,
        customerName: customerIndexes.length > 1 ? customerIndexes[1] : customerIndexes[0] >= 0 ? customerIndexes[0] : -1,
        date: first('date'),
        employee: first('employee'),
        team: first('team'),
        planned: first('planned'),
        status: first('status'),
        comments: first('comments'),
        products: first('products')
    };
}

/** Row count of the first sheet from the sheet range, without parsing every cell. */
export function sheetRowEstimate(workbook) {
    const name = workbook.SheetNames && workbook.SheetNames[0];
    const sheet = name && workbook.Sheets[name];
    const ref = sheet && (sheet['!fullref'] || sheet['!ref']);
    const match = ref && String(ref).match(/[A-Z]+(\d+):[A-Z]+(\d+)/);
    if (!match) return 0;
    return Math.max(0, Number(match[2]) - Number(match[1]));
}

// ---------- errors ----------

export function errorRecord(partial) {
    return {
        kind: partial.kind || '',
        sourceFile: partial.sourceFile || '',
        sourceRow: partial.sourceRow == null ? '' : partial.sourceRow,
        employeeCode: partial.employeeCode || '',
        employeeName: partial.employeeName || '',
        type: partial.type || '',
        from: partial.from || '',
        to: partial.to || '',
        severity: partial.severity || 'error',
        message: partial.message || ''
    };
}

export function csvEscape(value) {
    const v = value == null ? '' : String(value);
    return /[",\r\n]/.test(v) ? `"${v.replace(/"/g, '""')}"` : v;
}

/** Browser-side rejects as CSV lines (no header). Same columns as DataPackImportService.ERROR_HEADER. */
export function errorLines(records) {
    return (records || []).map((r) =>
        [r.kind, r.sourceFile, r.sourceRow, r.employeeCode, r.employeeName, r.type, r.from, r.to, r.severity, r.message]
            .map(csvEscape)
            .join(',')
    );
}

/**
 * One downloadable CSV: browser rejects, then each server CSV (header lines dropped, they all share ERROR_HEADER
 * except sales batch logs which have their own columns and are appended as their own block).
 */
export function mergeErrorCsv(clientRecords, serverCsvs) {
    const out = [ERROR_HEADER, ...errorLines(clientRecords)];
    const extraBlocks = [];
    (serverCsvs || []).forEach((csv) => {
        if (!csv) return;
        const lines = String(csv).split('\n');
        const header = lines.shift();
        const body = lines.filter((l) => l.trim() !== '');
        if (header === ERROR_HEADER) {
            out.push(...body);
        } else if (body.length) {
            extraBlocks.push('', header, ...body);
        }
    });
    return [...out, ...extraBlocks].join('\n') + '\n';
}

// ---------- helpers ----------

export function chunkArray(items, size) {
    const out = [];
    for (let i = 0; i < items.length; i += size) out.push(items.slice(i, i + size));
    return out;
}

export function formatBytes(n) {
    if (!Number.isFinite(n)) return '';
    if (n < 1024) return `${n} B`;
    if (n < 1024 * 1024) return `${(n / 1024).toFixed(1)} KB`;
    return `${(n / 1024 / 1024).toFixed(1)} MB`;
}

export { isValidReportMonth };

/** Sales rows with no item or client code are rejected by the server; catch them here so they land in the error CSV. */
export function splitSalesRows(rows, sourceFile) {
    const good = [];
    const errors = [];
    (rows || []).forEach((row, i) => {
        if (!String(row.itemCode || '').trim() || !String(row.clientCode || '').trim()) {
            errors.push(
                errorRecord({
                    kind: 'SALES',
                    sourceFile,
                    sourceRow: i + 1,
                    employeeCode: row.clientCode || '',
                    employeeName: row.clientName || '',
                    type: row.itemName || row.itemCode || '',
                    severity: 'error',
                    message: 'Row has no item code or no client code.'
                })
            );
        } else {
            good.push(row);
        }
    });
    return { good, errors };
}
