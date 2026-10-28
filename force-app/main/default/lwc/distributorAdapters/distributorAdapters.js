/**
 * Client-side Excel normalizers for distributor sales files (SheetJS workbook).
 * Each adapter returns { rows, warnings, sheetUsed, distributorCode, reportCadence }
 * where rows match Apex ingest shape.
 */

function cell(row, key) {
    if (!row || key == null) return '';
    const v = row[key];
    return v == null ? '' : String(v).trim();
}

/**
 * Parse a numeric cell. Handles plain numbers and distributor text such as
 * "$1,234.500", "-$1449.000", "1,587.000", "(250.00)" and "12 EGP".
 * Returns null when the cell is blank or not numeric.
 */
export function parseNumber(v) {
    if (v == null || v === '') return null;
    if (typeof v === 'number') return Number.isFinite(v) ? v : null;
    let s = String(v).trim();
    if (!s) return null;
    let negative = false;
    if (/^\(.*\)$/.test(s)) {
        negative = true;
        s = s.slice(1, -1);
    }
    s = s.replace(/[\s\u00a0]/g, '');
    if (s.startsWith('-') || s.startsWith('\u2212')) {
        negative = !negative;
        s = s.slice(1);
    } else if (s.endsWith('-') && s.length > 1) {
        negative = !negative;
        s = s.slice(0, -1);
    }
    // currency symbols / codes either side of the digits
    s = s.replace(/^(?:[$\u20ac\u00a3]|egp|usd|le|l\.e\.?|\u062c\.?\u0645\.?)/i, '');
    s = s.replace(/(?:[$\u20ac\u00a3]|egp|usd|le|l\.e\.?|\u062c\.?\u0645\.?)$/i, '');
    if (s.startsWith('-')) {
        negative = !negative;
        s = s.slice(1);
    }
    s = s.replace(/,/g, '');
    if (!/^\d*\.?\d+$|^\d+\.$/.test(s)) return null;
    const n = Number(s);
    if (!Number.isFinite(n)) return null;
    return negative ? -n : n;
}

function num(row, key) {
    if (!row || key == null) return null;
    return parseNumber(row[key]);
}

function pad2(n) {
    return String(n).padStart(2, '0');
}

function isoFromParts(y, m, d) {
    const year = Number(y);
    const month = Number(m);
    const day = Number(d);
    if (!(year >= 2000 && year <= 2100) || month < 1 || month > 12 || day < 1 || day > 31) return '';
    return `${year}-${pad2(month)}-${pad2(day)}`;
}

function expandYear(y) {
    const s = String(y);
    if (s.length === 4) return Number(s);
    const n = Number(s);
    return n < 70 ? 2000 + n : 1900 + n;
}

/**
 * Normalise a distributor date cell to YYYY-MM-DD, or '' when it is not a date.
 * Supported: m/d/yy and m/d/yyyy (POS, US order), yyyymmdd (IBNSINA), yyyy-mm-dd[ hh:mm:ss],
 * yyyy/mm/dd, dd-mm-yyyy (Sofico) and Excel serial numbers.
 */
export function parseSheetDate(v) {
    if (v == null || v === '') return '';
    if (typeof v === 'number') {
        if (v > 30000 && v < 80000) {
            const ms = Math.round((v - 25569) * 86400 * 1000);
            const d = new Date(ms);
            return isoFromParts(d.getUTCFullYear(), d.getUTCMonth() + 1, d.getUTCDate());
        }
        return parseSheetDate(String(v));
    }
    const s = String(v).trim();
    if (!s) return '';
    let m = s.match(/^(\d{4})[-/.](\d{1,2})[-/.](\d{1,2})(?:[T\s].*)?$/);
    if (m) return isoFromParts(m[1], m[2], m[3]);
    m = s.match(/^(\d{4})(\d{2})(\d{2})$/);
    if (m) return isoFromParts(m[1], m[2], m[3]);
    m = s.match(/^(\d{1,2})-(\d{1,2})-(\d{4})(?:[T\s].*)?$/);
    if (m) return isoFromParts(m[3], m[2], m[1]);
    m = s.match(/^(\d{1,2})\/(\d{1,2})\/(\d{2}|\d{4})(?:[T\s].*)?$/);
    if (m) {
        let month = Number(m[1]);
        let day = Number(m[2]);
        if (month > 12 && day <= 12) {
            [month, day] = [day, month];
        }
        return isoFromParts(expandYear(m[3]), month, day);
    }
    if (/^\d{5}(\.\d+)?$/.test(s)) return parseSheetDate(Number(s));
    return '';
}

function dateCell(row, key) {
    const raw = cell(row, key);
    return parseSheetDate(raw) || raw;
}

function normHeader(c) {
    return c == null
        ? ''
        : String(c)
              .replace(/[\u00a0\s]+/g, ' ')
              .trim()
              .toLowerCase();
}

/**
 * Find the header row by WHOLE-CELL matches (never substring matches).
 * `groups` is a list of alternative-name lists; every group must match at least one cell.
 * Example: [['item code'], ['client code', 'customer code']]
 */
function findHeaderRow(matrix, groups, maxScan = 25) {
    const wanted = groups.map((g) => g.map((n) => normHeader(n)));
    for (let i = 0; i < Math.min(matrix.length, maxScan); i++) {
        const cells = new Set((matrix[i] || []).map(normHeader).filter(Boolean));
        if (wanted.every((alts) => alts.some((a) => cells.has(a)))) {
            return i;
        }
    }
    return -1;
}

/** Header names present in `headers` (whole-cell, case-insensitive) mapped back to the original text. */
function pickHeader(headers, ...names) {
    const lookup = new Map();
    headers.forEach((h) => {
        const k = normHeader(h);
        if (k && !lookup.has(k)) lookup.set(k, h);
    });
    for (const n of names) {
        const hit = lookup.get(normHeader(n));
        if (hit) return hit;
    }
    return null;
}

function matrixToObjects(matrix, headerIndex) {
    const headers = matrix[headerIndex].map((c) => (c == null ? '' : String(c).trim()));
    const rows = [];
    for (let i = headerIndex + 1; i < matrix.length; i++) {
        const line = matrix[i];
        if (!line || line.every((c) => c == null || String(c).trim() === '')) continue;
        const obj = {};
        headers.forEach((h, idx) => {
            if (h) obj[h] = line[idx];
        });
        rows.push(obj);
    }
    return rows;
}

function getXlsx() {
    // eslint-disable-next-line no-undef
    const x = typeof XLSX !== 'undefined' ? XLSX : globalThis.XLSX || window.XLSX;
    if (!x) {
        throw new Error('SheetJS is not loaded.');
    }
    return x;
}

function sheetToMatrix(workbook, sheetName) {
    const sheet = workbook.Sheets[sheetName];
    if (!sheet) return [];
    return getXlsx().utils.sheet_to_json(sheet, { header: 1, defval: null, raw: false });
}

function pickSheet(workbook, predicates) {
    for (const name of workbook.SheetNames) {
        for (const pred of predicates) {
            if (pred(name)) return name;
        }
    }
    return workbook.SheetNames[0];
}

function sheetNamesBlob(workbook) {
    return (workbook?.SheetNames || []).join(' | ').toLowerCase();
}

function headerBlob(workbook, maxSheets = 4) {
    const parts = [];
    for (const name of (workbook?.SheetNames || []).slice(0, maxSheets)) {
        const matrix = sheetToMatrix(workbook, name);
        if (!matrix.length) continue;
        const headerIdx = Math.min(2, matrix.length - 1);
        for (let i = 0; i <= headerIdx; i++) {
            parts.push(
                (matrix[i] || [])
                    .map((c) => (c == null ? '' : String(c)))
                    .join(' ')
                    .toLowerCase()
            );
        }
    }
    return parts.join(' | ');
}

export const DISTRIBUTOR_OPTIONS = [
    { label: 'Zeta Direct', value: 'Direct' },
    { label: 'IBNSINA', value: 'IBNSINA' },
    { label: 'Sofico', value: 'Sofico' },
    { label: 'Egydrug', value: 'Egydrug' },
    { label: 'POS', value: 'POS' },
    { label: 'Elezaby', value: 'Elezaby' },
    { label: 'EPDA', value: 'EPDA' }
];

export const REPORT_CADENCE_OPTIONS = [
    { label: 'Auto-detect', value: '' },
    { label: 'Monthly', value: 'Monthly' },
    { label: 'Weekly', value: 'Weekly' }
];

export function detectDistributor(fileName) {
    const n = (fileName || '').toLowerCase();
    if (n.includes('direct') || n.includes('zeta direct') || n.includes('zeta-direct')) return 'Direct';
    if (n.includes('ibn') || n.includes('ibnsina')) return 'IBNSINA';
    if (n.includes('sofico')) return 'Sofico';
    if (n.includes('egydrug') || n.includes('egydurg')) return 'Egydrug';
    if (n.includes('elezaby') || n.includes('ezzaby') || n.includes('ezzabi')) return 'Elezaby';
    if (n.includes('ebda') || n.includes('epda')) return 'EPDA';
    if (n.includes('pos') || n.includes('customer sales') || n.includes('tender sales')) return 'POS';
    return '';
}

/**
 * Detect distributor from workbook sheet names / header fingerprints.
 * Needed because many native files are named only "ZETA PHARM ...".
 */
export function detectDistributorFromWorkbook(workbook) {
    const sheets = sheetNamesBlob(workbook);
    const headers = headerBlob(workbook);

    if (
        sheets.includes('pharmacy sales') ||
        sheets.includes('branches sales') ||
        headers.includes('egydrug_customer_type') ||
        (headers.includes('item_code') && headers.includes('customer_code') && headers.includes('qty_invoice'))
    ) {
        return 'Egydrug';
    }
    // EPDA tabular customer-sales sheet (AccountSerial / ProductSerial / SalesOrReturnQty)
    if (
        (headers.includes('accountserial') && headers.includes('productserial')) ||
        headers.includes('salesorreturnqty')
    ) {
        return 'EPDA';
    }
    // POS tender sales (Ship-To / Material / Sales\Returns Qty) - check before IBNSINA name heuristics
    if (headers.includes('sales\\returns qty') || (headers.includes('ship-to') && headers.includes('p. invoice'))) {
        return 'POS';
    }
    if (
        sheets.includes('salesbyclient') ||
        headers.includes('upa order number') ||
        (headers.includes('item code') && headers.includes('client code') && headers.includes('brick'))
    ) {
        return 'IBNSINA';
    }
    if (
        headers.includes('itemide') ||
        headers.includes('soldqty') ||
        headers.includes('iqvibrickcode') ||
        (sheets.includes('zeta') && headers.includes('customercode'))
    ) {
        return 'Sofico';
    }
    if (headers.includes('ean11') && headers.includes('branch name')) {
        return 'Elezaby';
    }
    if (headers.includes('mat. code') || headers.includes('mat code') || headers.includes('sal. district')) {
        return 'POS';
    }
    return '';
}

export function detectReportCadence(workbook, fileName) {
    const sheets = sheetNamesBlob(workbook);
    const n = (fileName || '').toLowerCase();
    if (
        sheets.includes('monthly stocks') ||
        sheets.includes('total monthly') ||
        n.includes('monthly')
    ) {
        return 'Monthly';
    }
    if (
        sheets.includes('current stock') ||
        sheets.includes('total daily') ||
        n.includes('weekly') ||
        n.includes('daily')
    ) {
        return 'Weekly';
    }
    return '';
}

export function parseDistributorWorkbook(workbook, distributorCode, fileName) {
    const fromName = detectDistributor(fileName);
    const fromContent = detectDistributorFromWorkbook(workbook);
    const code = distributorCode || fromName || fromContent;
    const reportCadence = detectReportCadence(workbook, fileName);
    let result;
    switch (code) {
        case 'Direct':
            result = parseZetaDirect(workbook);
            break;
        case 'IBNSINA':
            result = parseIbnsina(workbook);
            break;
        case 'Sofico':
            result = parseSofico(workbook);
            break;
        case 'Egydrug':
            result = parseEgydrug(workbook);
            break;
        case 'POS':
            result = parsePos(workbook);
            break;
        case 'Elezaby':
            result = parseElezaby(workbook);
            break;
        case 'EPDA':
        case 'Ebda':
            result = parseEpda(workbook);
            break;
        default:
            result = {
                rows: [],
                warnings: [
                    'Could not detect distributor from file name or sheet layout. Select a distributor and try again.'
                ],
                sheetUsed: null,
                distributorCode: ''
            };
    }
    result.reportCadence = reportCadence;
    result.detectedMonth = detectReportMonth(result.rows);
    result.detectedFrom = distributorCode ? 'manual' : fromName ? 'filename' : fromContent ? 'workbook' : 'none';
    if (reportCadence) {
        result.warnings = result.warnings || [];
        // informational only - cadence does not change the sales-sheet parser
        if (!result.warnings.some((w) => /cadence/i.test(w))) {
            result.warnings.push(`Detected report cadence: ${reportCadence} (sales sheets use the same layout).`);
        }
    }
    return result;
}

/**
 * Zeta Direct closing: one row per customer x product, e.g.
 * Distributor Name, CustomerIDName, Subtype, Unit, Line, Brand, Code, Product, ..., P.P, Units In Market, Bonus In Market.
 * Code is the Zeta product code. The customer is CustomerIDName ("1000036019_<name>"), else Distributor Name.
 * Bonus In Market is never counted. The month cells hold only "Sep" / "july", so the month comes from the import form.
 * Monthly workbooks may open on a pivot sheet (Row Labels / Sum of Units In Market), so every sheet is tried.
 */
const DIRECT_ITEM_HEADERS = ['code', 'product code', 'item code', 'zeta code', 'sku'];
const DIRECT_QTY_HEADERS = ['units in market', 'qty', 'quantity', 'units'];
const DIRECT_CLIENT_HEADERS = ['customeridname', 'distributor name', 'customer', 'customer name', 'client', 'client name', 'name'];

function parseZetaDirect(workbook) {
    const warnings = [
        'Zeta Direct: quantity and month are stored; achievement uses public/tender policy prices, not file unit price.'
    ];
    for (const sheetName of workbook.SheetNames) {
        const matrix = sheetToMatrix(workbook, sheetName);
        const headerIdx = findHeaderRow(matrix, [DIRECT_ITEM_HEADERS, DIRECT_QTY_HEADERS, DIRECT_CLIENT_HEADERS]);
        if (headerIdx < 0) continue;
        const headers = (matrix[headerIdx] || []).map((c) => (c == null ? '' : String(c).trim()));
        const itemKey = pickHeader(headers, ...DIRECT_ITEM_HEADERS);
        const qtyKey = pickHeader(headers, ...DIRECT_QTY_HEADERS);
        const clientKey = pickHeader(headers, ...DIRECT_CLIENT_HEADERS);
        const clientNameKey = pickHeader(headers, 'distributor name', 'customer name', 'client name', 'name');
        const productNameKey = pickHeader(headers, 'product', 'product name', 'item name');
        const subtypeKey = pickHeader(headers, 'subtype');
        const priceKey = pickHeader(headers, 'p.p', 'price', 'unit price');
        const rows = [];
        for (const o of matrixToObjects(matrix, headerIdx)) {
            const itemCode = cell(o, itemKey);
            const clientCode = cell(o, clientKey);
            const qty = num(o, qtyKey);
            if (!itemCode || !clientCode || qty == null || qty === 0) continue;
            const price = priceKey ? num(o, priceKey) : null;
            rows.push({
                distributorCode: 'Direct',
                itemCode,
                itemName: productNameKey ? cell(o, productNameKey) : '',
                clientCode,
                clientName: (clientNameKey ? cell(o, clientNameKey) : '') || clientCode,
                clientSubtype: subtypeKey ? cell(o, subtypeKey) : '',
                address: '',
                governorate: '',
                brickCode: '',
                brickName: '',
                quantity: qty,
                revenue: price != null ? price * qty : null,
                unitPrice: price,
                reportMonth: '',
                transactionDate: '',
                sourceSheet: sheetName
            });
        }
        if (rows.length) {
            return { rows, warnings, sheetUsed: sheetName, distributorCode: 'Direct' };
        }
        warnings.push(`Zeta Direct: header found on ${sheetName} but no data rows.`);
    }
    return {
        rows: [],
        warnings: warnings.concat([
            'Could not find Direct sales headers (Code / Units In Market / CustomerIDName or Distributor Name). Pivot sheets are skipped.'
        ]),
        sheetUsed: workbook.SheetNames[0] || null,
        distributorCode: 'Direct'
    };
}

/** IBNSINA: "Sales by client" (monthly / weekly) and the Tender (UPA) report. */
function parseIbnsinaClientSheet(workbook, sheetName) {
    const matrix = sheetToMatrix(workbook, sheetName);
    const headerIdx = findHeaderRow(matrix, [['item code'], ['client code']]);
    if (headerIdx < 0) return null;
    const objects = matrixToObjects(matrix, headerIdx);
    const rows = [];
    for (const o of objects) {
        const itemCode = cell(o, 'Item Code');
        const clientCode = cell(o, 'Client Code');
        if (!itemCode || !clientCode) continue;
        // Quantity is the paid units; Total Quantity adds the Free Unit bonus, which is never a sale.
        const paidQty = num(o, 'Quantity');
        rows.push({
            distributorCode: 'IBNSINA',
            itemCode,
            itemName: cell(o, 'Item Name'),
            clientCode,
            clientName: cell(o, 'Client Name'),
            address: cell(o, 'Address_En') || cell(o, 'Address_Ar') || cell(o, 'Address'),
            governorate: cell(o, 'Governorate Name'),
            brickCode: cell(o, 'Brick'),
            brickName: cell(o, 'Brick Name'),
            quantity: paidQty != null ? paidQty : num(o, 'Total Quantity'),
            revenue: num(o, 'Net'),
            unitPrice: null,
            reportMonth: dateCell(o, 'Date'),
            transactionDate: dateCell(o, 'Date'),
            sourceSheet: sheetName
        });
    }
    return { rows, layout: 'client' };
}

function parseIbnsinaTenderSheet(workbook, sheetName) {
    const matrix = sheetToMatrix(workbook, sheetName);
    const headerIdx = findHeaderRow(matrix, [['item code'], ['customer code'], ['invoice qty']]);
    if (headerIdx < 0) return null;
    const objects = matrixToObjects(matrix, headerIdx);
    const rows = [];
    for (const o of objects) {
        const itemCode = cell(o, 'Item Code');
        const clientCode = cell(o, 'Customer Code');
        if (!itemCode || !clientCode) continue;
        const invoiceDate = dateCell(o, 'Invoice Date') || dateCell(o, 'Planned Date') || dateCell(o, 'Order date');
        const tenderType = cell(o, 'Tender Type');
        const itemName = cell(o, 'Item Name');
        rows.push({
            distributorCode: 'IBNSINA',
            itemCode,
            itemName,
            clientCode,
            clientName: cell(o, 'Customer Name'),
            address: '',
            governorate: cell(o, 'City'),
            brickCode: '',
            brickName: '',
            quantity: num(o, 'Invoice Qty'),
            revenue: num(o, 'Line Amount'),
            unitPrice: null,
            reportMonth: invoiceDate,
            transactionDate: invoiceDate,
            isTender: true,
            isUPA: /^upa$/i.test(tenderType) || /\(upa\)/i.test(itemName),
            tenderType,
            sourceSheet: sheetName
        });
    }
    return { rows, layout: 'tender' };
}

function parseIbnsina(workbook) {
    const warnings = [];
    const rows = [];
    const used = [];
    for (const name of workbook.SheetNames) {
        const parsed = parseIbnsinaClientSheet(workbook, name) || parseIbnsinaTenderSheet(workbook, name);
        if (!parsed) continue;
        used.push(name);
        rows.push(...parsed.rows);
        if (parsed.layout === 'tender') {
            warnings.push(`IBNSINA tender (UPA) layout on ${name}: rows are flagged tender; quantity is Invoice Qty.`);
        }
    }
    if (!used.length) {
        return {
            rows: [],
            warnings: ['IBNSINA: could not find a Sales-by-client or Tender header (Item Code + Client Code / Customer Code).'],
            sheetUsed: workbook.SheetNames[0] || null,
            distributorCode: 'IBNSINA'
        };
    }
    if (!rows.length) warnings.push('IBNSINA: no data rows parsed.');
    return { rows, warnings, sheetUsed: used.join(' + '), distributorCode: 'IBNSINA' };
}

function parseSofico(workbook) {
    const warnings = [];
    let chosen = pickSheet(workbook, [(n) => /zeta/i.test(n), (n) => /sales|cust/i.test(n)]);
    let matrix = sheetToMatrix(workbook, chosen);
    const salesGroups = [['customercode', 'orderaccount'], ['itemide', 'itemid']];
    let headerIdx = findHeaderRow(matrix, salesGroups);
    if (headerIdx < 0) {
        const stockIdx = findHeaderRow(matrix, [['material desc.']]);
        return {
            rows: [],
            warnings: [
                stockIdx >= 0
                    ? 'Sofico STOCK sheet is not supported for sell-out import.'
                    : 'Sofico: could not find sales header (stock files are unsupported).'
            ],
            sheetUsed: chosen,
            distributorCode: 'Sofico'
        };
    }
    const objects = matrixToObjects(matrix, headerIdx);
    const rows = [];
    for (const o of objects) {
        const itemCode = cell(o, 'ITEMIDE') || cell(o, 'ITEMID');
        const clientCode = cell(o, 'CUSTOMERCODE') || cell(o, 'ORDERACCOUNT');
        if (!itemCode || !clientCode) continue;
        // Sold less returned units. BOUNSQTY / RETURNBOUNSQTY are bonus and never count (NET SALES includes them).
        const sold = num(o, 'SOLDQTY');
        const returned = num(o, 'RETURNQTY');
        rows.push({
            distributorCode: 'Sofico',
            itemCode,
            itemName: cell(o, 'ITEMNAME'),
            clientCode,
            clientName: cell(o, 'CUSTOMERNAME') || cell(o, 'CUSTOMERNAME0013'),
            address: cell(o, 'ADDRESS') || cell(o, 'ADDRESSSHIP'),
            governorate: cell(o, 'GOVER'),
            brickCode: cell(o, 'IQVIBRICKCODE'),
            brickName: cell(o, 'IQVIBRICKCODE'),
            quantity: sold != null || returned != null ? (sold || 0) + (returned || 0) : num(o, 'NET SALES'),
            revenue: num(o, 'TOTALVALUE'),
            unitPrice: num(o, 'SALESPIRCE') || num(o, 'SALESPIRCE2'),
            reportMonth: dateCell(o, 'BILLINGDATE') || dateCell(o, 'FROMDATE'),
            transactionDate: dateCell(o, 'BILLINGDATE')
        });
    }
    if (!rows.length) warnings.push('Sofico: no data rows parsed.');
    return { rows, warnings, sheetUsed: chosen, distributorCode: 'Sofico' };
}

function parseEgydrugSheet(workbook, sheetName) {
    const matrix = sheetToMatrix(workbook, sheetName);
    const headerIdx = findHeaderRow(matrix, [['item_code'], ['customer_code', 'branch_code']]);
    if (headerIdx < 0) {
        return { rows: [], warning: `Egydrug: header not found on ${sheetName}.` };
    }
    const objects = matrixToObjects(matrix, headerIdx);
    const rows = [];
    for (const o of objects) {
        const itemCode = cell(o, 'ITEM_CODE');
        // Prefer pharmacy/customer; fall back to branch as sellout point when needed
        const clientCode =
            cell(o, 'CUSTOMER_CODE') || cell(o, 'BRANCH_CODE') || cell(o, 'COMPANY_ENTITY_CODE');
        if (!itemCode || !clientCode) continue;
        // Bonus lines (ITEM_OUT_STATUS 5 / بونص) are free goods, never sales.
        if (cell(o, 'ITEM_OUT_STATUS') === '5' || /بونص/.test(cell(o, 'INV_ITEM_OUT_STATUS'))) continue;
        const qtyInvoice = num(o, 'QTY_INVOICE');
        const returnQty = num(o, 'RETURN_QTY') || 0;
        // QUANTITY is packs including loose units (1 strip of 3 = 0.333); QTY_PACK drops the loose units.
        const qtyFull = num(o, 'QUANTITY');
        const qtyPack = num(o, 'QTY_PACK');
        let quantity = qtyInvoice != null ? qtyInvoice : qtyFull != null ? qtyFull : qtyPack;
        if (quantity == null && returnQty) {
            quantity = returnQty;
        }
        rows.push({
            distributorCode: 'Egydrug',
            itemCode,
            itemName: cell(o, 'ITEM_NAME') || cell(o, 'ITEM_NAME_ENG'),
            clientCode,
            clientName: cell(o, 'CUSTOMER_NAME') || cell(o, 'BRANCH_NAME'),
            address: cell(o, 'CUSTOMER_ADDRESS') || '',
            governorate: cleanEgydrugPlace(cell(o, 'PROVINCE_NAME')),
            brickCode: cell(o, 'BRANCH_CODE') || '',
            brickName: cell(o, 'BRANCH_NAME') || '',
            quantity,
            revenue: firstNumber(o, 'TOTAL_VALUE_INVOICE', 'VALUE', 'TOTAL_PRICE'),
            unitPrice: firstNumber(o, 'PHARMAIST_PRICE', 'PHARM_PRICE', 'BASE_PRICE'),
            reportMonth: dateCell(o, 'INVOICE_DATE'),
            transactionDate: dateCell(o, 'INVOICE_DATE'),
            sourceSheet: sheetName
        });
    }
    return { rows, warning: rows.length ? null : `Egydrug: no data rows on ${sheetName}.` };
}

/** First of `keys` with a numeric cell (0 counts, so a free line keeps value 0). */
function firstNumber(row, ...keys) {
    for (const k of keys) {
        const n = num(row, k);
        if (n != null) return n;
    }
    return null;
}

function cleanEgydrugPlace(v) {
    const s = (v || '').trim();
    if (!s || s === '0' || s === '-' || s.toLowerCase() === 'null' || s.toLowerCase() === 'n/a') {
        return '';
    }
    return s;
}

function parseEgydrug(workbook) {
    const warnings = [];
    const salesSheets = [];
    for (const n of workbook.SheetNames) {
        if (/^pharmacy sales$/i.test(n.trim()) || /^branches sales$/i.test(n.trim())) {
            salesSheets.push(n);
        }
    }
    // Prefer Branches Sales first (better addresses for geocoding), then Pharmacy Sales
    salesSheets.sort((a, b) => {
        const score = (n) => (/branches/i.test(n) ? 0 : 1);
        return score(a) - score(b);
    });
    if (!salesSheets.length) {
        return {
            rows: [],
            warnings: ['Egydrug: Pharmacy Sales / Branches Sales sheet not found.'],
            sheetUsed: null,
            distributorCode: 'Egydrug'
        };
    }
    const rows = [];
    for (const sheetName of salesSheets) {
        const parsed = parseEgydrugSheet(workbook, sheetName);
        if (parsed.warning) warnings.push(parsed.warning);
        rows.push(...parsed.rows);
    }
    if (!rows.length) warnings.push('Egydrug: no data rows parsed.');
    return {
        rows,
        warnings,
        sheetUsed: salesSheets.join(' + '),
        distributorCode: 'Egydrug'
    };
}

/** POS: "customer sales" (Data sheet) and the tender sales layout (Ship-To / Material). */
function parsePosCustomerSheet(workbook, sheetName) {
    const matrix = sheetToMatrix(workbook, sheetName);
    const headerIdx = findHeaderRow(matrix, [['customer'], ['mat. code', 'mat code']]);
    if (headerIdx < 0) return null;
    const objects = matrixToObjects(matrix, headerIdx);
    const rows = [];
    for (const o of objects) {
        const itemCode = cell(o, 'Mat. Code') || cell(o, 'Mat Code');
        const clientCode = cell(o, 'Customer');
        if (!itemCode || !clientCode) continue;
        rows.push({
            distributorCode: 'POS',
            itemCode: itemCode.replace(/\s+/g, ''),
            itemName: cell(o, 'Mat. Desc.') || cell(o, 'Mat Desc.'),
            clientCode,
            clientName: cell(o, 'Customer Name'),
            address: cell(o, 'Customer Address'),
            governorate: cell(o, 'Sal. Dist. Desc.'),
            brickCode: cell(o, 'Sal. District'),
            brickName: cell(o, 'Sal. Dist. Desc.'),
            quantity: num(o, 'Qty'),
            revenue: num(o, 'Value'),
            unitPrice: null,
            reportMonth: dateCell(o, 'Invoice Date'),
            transactionDate: dateCell(o, 'Invoice Date'),
            sourceSheet: sheetName
        });
    }
    return { rows, layout: 'customer' };
}

function parsePosTenderSheet(workbook, sheetName) {
    const matrix = sheetToMatrix(workbook, sheetName);
    const headerIdx = findHeaderRow(matrix, [['ship-to'], ['material'], ['sales\\returns qty']]);
    if (headerIdx < 0) return null;
    const objects = matrixToObjects(matrix, headerIdx);
    const rows = [];
    for (const o of objects) {
        const itemCode = cell(o, 'Material');
        const clientCode = cell(o, 'Ship-To');
        // The report ends with a grand-total line that has no ship-to / material.
        if (!itemCode || !clientCode) continue;
        rows.push({
            distributorCode: 'POS',
            itemCode: itemCode.replace(/\s+/g, ''),
            itemName: cell(o, 'Item Description'),
            clientCode,
            clientName: cell(o, 'Ship-to party'),
            address: cell(o, 'Street'),
            governorate: '',
            brickCode: cell(o, 'SDst'),
            brickName: cell(o, 'Sales District'),
            quantity: num(o, 'Sales\\Returns Qty'),
            revenue: num(o, 'Sales\\Returns Value'),
            unitPrice: null,
            reportMonth: dateCell(o, 'Delivery Date'),
            transactionDate: dateCell(o, 'Delivery Date'),
            isTender: true,
            tenderType: cell(o, 'Short Description'),
            sourceSheet: sheetName
        });
    }
    return { rows, layout: 'tender' };
}

function parsePos(workbook) {
    const warnings = [];
    const rows = [];
    const used = [];
    for (const name of workbook.SheetNames) {
        const parsed = parsePosCustomerSheet(workbook, name) || parsePosTenderSheet(workbook, name);
        if (!parsed) continue;
        used.push(name);
        rows.push(...parsed.rows);
        if (parsed.layout === 'tender') {
            warnings.push(`POS tender layout on ${name}: rows are flagged tender; bonus / free units are excluded.`);
        }
    }
    if (!used.length) {
        return {
            rows: [],
            warnings: ['POS: customer sales or tender header not found (stock/purchasing .xls may need conversion).'],
            sheetUsed: workbook.SheetNames[0] || null,
            distributorCode: 'POS'
        };
    }
    if (!rows.length) warnings.push('POS: no data rows parsed.');
    return { rows, warnings, sheetUsed: used.join(' + '), distributorCode: 'POS' };
}

function parseElezaby(workbook) {
    const warnings = [];
    const chosen = workbook.SheetNames[0];
    const matrix = sheetToMatrix(workbook, chosen);
    const headerIdx = findHeaderRow(matrix, [['branch'], ['ean11']]);
    if (headerIdx < 0) {
        return {
            rows: [],
            warnings: ['Elezaby: header not found.'],
            sheetUsed: chosen,
            distributorCode: 'Elezaby'
        };
    }
    const objects = matrixToObjects(matrix, headerIdx);
    const rows = [];
    for (const o of objects) {
        const itemCode = cell(o, 'Ean11') || cell(o, 'EAN11');
        const clientCode = cell(o, 'Branch');
        if (!itemCode || !clientCode) continue;
        rows.push({
            distributorCode: 'Elezaby',
            itemCode,
            itemName: cell(o, 'Mat Desc') || cell(o, 'Mat Desc.'),
            clientCode,
            clientName: cell(o, 'Branch Name'),
            address: '',
            governorate: '',
            brickCode: clientCode,
            brickName: cell(o, 'Branch Name'),
            quantity: num(o, 'Qty'),
            revenue: num(o, 'Sales Measures.Sales') != null ? num(o, 'Sales Measures.Sales') : num(o, 'Sales'),
            unitPrice: null,
            reportMonth: dateCell(o, 'Post Date'),
            transactionDate: dateCell(o, 'Post Date')
        });
    }
    if (!rows.length) warnings.push('Elezaby: no data rows (branch used as sellout point).');
    return { rows, warnings, sheetUsed: chosen, distributorCode: 'Elezaby' };
}

/**
 * EPDA (Ebda) tabular customer-sales sheet:
 * BranchID, branchName, Transdate, TerritoryName, AccountSerial, AccountName, Address,
 * ProductSerial, ProductName, SalesOrReturnQty, SalesOrReturnBonus, TrxNumber, UnitSalesPrice, LineValue, Distributor.
 * Bonus quantity is never counted as a sale. The Crystal-report .xls files carry no such header and are skipped.
 */
const EPDA_ITEM_HEADERS = ['productserial', 'item code', 'item_code', 'material code', 'mat. code', 'mat code'];
const EPDA_CLIENT_HEADERS = ['accountserial', 'customer code', 'client code'];
const EPDA_QTY_HEADERS = ['salesorreturnqty', 'qty', 'quantity', 'sold qty'];

function parseEpda(workbook) {
    const warnings = [];
    for (const name of workbook.SheetNames) {
        const matrix = sheetToMatrix(workbook, name);
        const headerIdx = findHeaderRow(matrix, [EPDA_ITEM_HEADERS, EPDA_CLIENT_HEADERS, EPDA_QTY_HEADERS]);
        if (headerIdx < 0) continue;
        const headers = (matrix[headerIdx] || []).map((c) => (c == null ? '' : String(c).trim()));
        const objects = matrixToObjects(matrix, headerIdx);
        const itemKey = pickHeader(headers, ...EPDA_ITEM_HEADERS);
        const nameKey = pickHeader(headers, 'productname', 'item name', 'mat. desc.', 'material desc');
        const clientKey = pickHeader(headers, ...EPDA_CLIENT_HEADERS);
        const clientNameKey = pickHeader(headers, 'accountname', 'customer name', 'client name');
        const addrKey = pickHeader(headers, 'address');
        const qtyKey = pickHeader(headers, ...EPDA_QTY_HEADERS);
        const valueKey = pickHeader(headers, 'linevalue', 'value');
        const priceKey = pickHeader(headers, 'unitsalesprice', 'unit price');
        const dateKey = pickHeader(headers, 'transdate', 'invoice date', 'date');
        const territoryKey = pickHeader(headers, 'territoryname');
        const branchKey = pickHeader(headers, 'branchname');
        const rows = [];
        for (const o of objects) {
            const itemCode = cell(o, itemKey);
            const clientCode = cell(o, clientKey);
            if (!itemCode || !clientCode) continue;
            rows.push({
                distributorCode: 'EPDA',
                itemCode,
                itemName: nameKey ? cell(o, nameKey) : '',
                clientCode,
                clientName: clientNameKey ? cell(o, clientNameKey) : '',
                address: addrKey ? cell(o, addrKey) : '',
                governorate: '',
                brickCode: '',
                brickName: territoryKey ? cell(o, territoryKey) : '',
                branchName: branchKey ? cell(o, branchKey) : '',
                quantity: num(o, qtyKey),
                revenue: valueKey ? num(o, valueKey) : null,
                unitPrice: priceKey ? num(o, priceKey) : null,
                reportMonth: dateKey ? dateCell(o, dateKey) : '',
                transactionDate: dateKey ? dateCell(o, dateKey) : '',
                sourceSheet: name
            });
        }
        if (rows.length) {
            return { rows, warnings, sheetUsed: name, distributorCode: 'EPDA' };
        }
        warnings.push(`EPDA: header found on ${name} but no data rows.`);
    }
    return {
        rows: [],
        warnings: warnings.concat([
            'EPDA: no tabular sales sheet (needs AccountSerial, ProductSerial, SalesOrReturnQty). Unpack the nested zip and upload the customer-sales .xlsx, not the Crystal report .xls.'
        ]),
        sheetUsed: null,
        distributorCode: 'EPDA'
    };
}

/**
 * Most frequent YYYY-MM in the parsed rows (by transaction date). Returns '' when no row has a usable date.
 * The caller must NEVER let this replace a month the user already picked.
 */
export function detectReportMonth(rows) {
    const counts = new Map();
    for (const r of rows || []) {
        const iso = parseSheetDate(r.reportMonth) || parseSheetDate(r.transactionDate);
        if (!iso) continue;
        const ym = iso.slice(0, 7);
        counts.set(ym, (counts.get(ym) || 0) + 1);
    }
    let best = '';
    let bestCount = 0;
    for (const [ym, n] of counts) {
        if (n > bestCount || (n === bestCount && ym > best)) {
            best = ym;
            bestCount = n;
        }
    }
    return best;
}

/** Legacy helper: detected month, or the current month when nothing could be detected. */
export function inferReportMonth(rows) {
    const detected = detectReportMonth(rows);
    if (detected) return detected;
    const now = new Date();
    return `${now.getFullYear()}-${pad2(now.getMonth() + 1)}`;
}

/** True when `value` is a valid YYYY-MM report month. */
export function isValidReportMonth(value) {
    return /^20\d{2}-(0[1-9]|1[0-2])$/.test(String(value || '').trim());
}
