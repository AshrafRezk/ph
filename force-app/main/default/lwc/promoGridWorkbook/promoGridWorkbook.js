/**
 * Pure helpers for Promo Grid template / export / import workbooks.
 * Sheet layout: Instructions, Products, Specialties, Classes, Lists.
 */

export const SHEET_INSTRUCTIONS = 'Instructions';
export const SHEET_PRODUCTS = 'Products';
export const SHEET_SPECIALTIES = 'Specialties';
export const SHEET_CLASSES = 'Classes';
export const SHEET_LISTS = 'Lists';

export const PRODUCT_HEADERS = ['Line', 'Product_Code', 'Product_Name', 'Weight_Percentage'];
export const SPECIALTY_HEADERS = ['Line', 'Specialty', 'List_Percentage'];
export const CLASS_HEADERS = ['Line', 'Class', 'List_Percentage', 'Target_Monthly_Visits'];

const INSTRUCTION_LINES = [
    'Zeta Pharma — Promo Grid template',
    'Fill Products, Specialties, and Classes. Each data sheet has a Line column.',
    'Product weights for a line must sum to 100%. Specialty list % and class list % must each sum to 100%.',
    'Match Line by name (e.g. GIT-I). Match products by Product_Code (or exact Product_Name if no code).',
    'Specialty accepts the label or API value. Class values: A1, A2, A3, B1, B2, B3, C1, C2, C3.',
    'Percentages: enter 40 or 40%. Leave percentage blank to skip a pre-filled row.',
    'Import replaces a line section only when that section has at least one percentage filled.',
    'Blank sections are left untouched. See the Lists sheet for valid Line / Specialty / Class values.'
];

/**
 * @param {object} data ExportPayload from PromoGridTransferService.getPromoGridExport
 * @param {{ includeValues?: boolean }} [options]
 * @returns {{ sheetNames: string[], sheets: Record<string, any[][]> }}
 */
export function buildPromoGridMatrices(data, options = {}) {
    const includeValues = options.includeValues === true || data?.includeValues === true;
    const lines = Array.isArray(data?.lines) ? data.lines : [];
    const specialtyLabels = Array.isArray(data?.specialtyLabels) ? data.specialtyLabels : [];
    const classCodes = Array.isArray(data?.classCodes) && data.classCodes.length
        ? data.classCodes
        : ['A1', 'A2', 'A3', 'B1', 'B2', 'B3', 'C1', 'C2', 'C3'];

    const instructions = INSTRUCTION_LINES.map((line) => [line]);

    const products = [PRODUCT_HEADERS.slice()];
    const specialties = [SPECIALTY_HEADERS.slice()];
    const classes = [CLASS_HEADERS.slice()];

    for (const line of lines) {
        const lineName = line?.lineName || '';
        for (const product of line?.products || []) {
            products.push([
                lineName,
                blankToEmpty(product?.productCode),
                blankToEmpty(product?.productName),
                includeValues ? percentOrEmpty(product?.weightPercentage) : ''
            ]);
        }
        for (const specialty of line?.specialties || []) {
            specialties.push([
                lineName,
                blankToEmpty(specialty?.specialtyLabel || specialty?.specialty),
                includeValues ? percentOrEmpty(specialty?.listPercentage) : ''
            ]);
        }
        for (const classRow of line?.classes || []) {
            classes.push([
                lineName,
                blankToEmpty(classRow?.classCode),
                includeValues ? percentOrEmpty(classRow?.listPercentage) : '',
                includeValues ? numberOrEmpty(classRow?.targetMonthlyVisits) : ''
            ]);
        }
    }

    const lists = [['Line', 'Specialty', 'Class']];
    const maxRows = Math.max(lines.length, specialtyLabels.length, classCodes.length);
    for (let i = 0; i < maxRows; i++) {
        lists.push([
            i < lines.length ? lines[i].lineName || '' : '',
            i < specialtyLabels.length ? specialtyLabels[i] : '',
            i < classCodes.length ? classCodes[i] : ''
        ]);
    }

    return {
        sheetNames: [
            SHEET_INSTRUCTIONS,
            SHEET_PRODUCTS,
            SHEET_SPECIALTIES,
            SHEET_CLASSES,
            SHEET_LISTS
        ],
        sheets: {
            [SHEET_INSTRUCTIONS]: instructions,
            [SHEET_PRODUCTS]: products,
            [SHEET_SPECIALTIES]: specialties,
            [SHEET_CLASSES]: classes,
            [SHEET_LISTS]: lists
        }
    };
}

/**
 * @param {Record<string, any[][]>} sheetsByName matrix per sheet name
 * @returns {{ lines: object[], parseErrors: string[] }}
 */
export function parsePromoGridMatrices(sheetsByName) {
    const parseErrors = [];
    const sheets = sheetsByName || {};
    const hasProducts = hasSheet(sheets, SHEET_PRODUCTS);
    const hasSpecialties = hasSheet(sheets, SHEET_SPECIALTIES);
    const hasClasses = hasSheet(sheets, SHEET_CLASSES);

    if (!hasProducts && !hasSpecialties && !hasClasses) {
        parseErrors.push(
            'This file is not the Promo Grid template. Expected Products, Specialties, and/or Classes sheets.'
        );
        return { lines: [], parseErrors };
    }

    const byLine = new Map();

    if (hasProducts) {
        const parsed = parseSheet(sheets, SHEET_PRODUCTS, PRODUCT_HEADERS, parseErrors);
        for (const row of parsed.rows) {
            const lineName = asString(row.Line);
            if (!lineName) {
                continue;
            }
            const line = ensureLine(byLine, lineName);
            line.products.push({
                excelRow: row.__excelRow,
                productCode: asString(row.Product_Code) || null,
                productName: asString(row.Product_Name) || null,
                weightPercentage: parsePercent(row.Weight_Percentage)
            });
        }
    } else {
        parseErrors.push('Missing sheet: Products');
    }

    if (hasSpecialties) {
        const parsed = parseSheet(sheets, SHEET_SPECIALTIES, SPECIALTY_HEADERS, parseErrors);
        for (const row of parsed.rows) {
            const lineName = asString(row.Line);
            if (!lineName) {
                continue;
            }
            const line = ensureLine(byLine, lineName);
            line.specialties.push({
                excelRow: row.__excelRow,
                specialty: asString(row.Specialty) || null,
                listPercentage: parsePercent(row.List_Percentage)
            });
        }
    } else {
        parseErrors.push('Missing sheet: Specialties');
    }

    if (hasClasses) {
        const parsed = parseSheet(sheets, SHEET_CLASSES, CLASS_HEADERS, parseErrors);
        for (const row of parsed.rows) {
            const lineName = asString(row.Line);
            if (!lineName) {
                continue;
            }
            const line = ensureLine(byLine, lineName);
            line.classes.push({
                excelRow: row.__excelRow,
                classCode: asString(row.Class) || null,
                listPercentage: parsePercent(row.List_Percentage),
                targetMonthlyVisits: parseWholeNumber(row.Target_Monthly_Visits)
            });
        }
    } else {
        parseErrors.push('Missing sheet: Classes');
    }

    return {
        lines: Array.from(byLine.values()),
        parseErrors
    };
}

function ensureLine(byLine, lineName) {
    if (!byLine.has(lineName)) {
        byLine.set(lineName, {
            lineName,
            products: [],
            specialties: [],
            classes: []
        });
    }
    return byLine.get(lineName);
}

function hasSheet(sheets, name) {
    const key = Object.keys(sheets || {}).find((k) => normalizeHeader(k) === normalizeHeader(name));
    return Boolean(key && Array.isArray(sheets[key]));
}

function getSheet(sheets, name) {
    const key = Object.keys(sheets || {}).find((k) => normalizeHeader(k) === normalizeHeader(name));
    return key ? sheets[key] : null;
}

function parseSheet(sheets, sheetName, expectedHeaders, parseErrors) {
    const matrix = getSheet(sheets, sheetName);
    if (!matrix || matrix.length === 0) {
        parseErrors.push(`${sheetName}: sheet is empty.`);
        return { rows: [] };
    }
    const headerRow = matrix[0] || [];
    const indexByHeader = {};
    headerRow.forEach((cell, idx) => {
        const key = normalizeHeader(cell);
        if (key) {
            indexByHeader[key] = idx;
        }
    });

    for (const expected of expectedHeaders) {
        if (indexByHeader[normalizeHeader(expected)] === undefined) {
            parseErrors.push(`${sheetName}: missing header "${expected}".`);
        }
    }

    const rows = [];
    for (let r = 1; r < matrix.length; r++) {
        const cells = matrix[r] || [];
        if (!cells.some((cell) => cell !== null && cell !== undefined && String(cell).trim() !== '')) {
            continue;
        }
        const row = { __excelRow: r + 1 };
        for (const expected of expectedHeaders) {
            const idx = indexByHeader[normalizeHeader(expected)];
            row[expected] = idx === undefined ? null : cells[idx];
        }
        rows.push(row);
    }
    return { rows };
}

export function normalizeHeader(value) {
    if (value === null || value === undefined) {
        return '';
    }
    return String(value)
        .trim()
        .toLowerCase()
        .replace(/[\s_]+/g, '');
}

export function parsePercent(value) {
    if (value === null || value === undefined || value === '') {
        return null;
    }
    if (typeof value === 'number') {
        if (Number.isNaN(value)) {
            return null;
        }
        // Excel percent-formatted cells arrive as ratios in (0, 1), e.g. 0.4 = 40%.
        // Exact 1 is left as 1% so typed ones are not turned into 100.
        if (value > 0 && value < 1) {
            return round1(value * 100);
        }
        return round1(value);
    }
    let text = String(value).trim();
    if (!text) {
        return null;
    }
    const hasPercent = text.endsWith('%');
    if (hasPercent) {
        text = text.slice(0, -1).trim();
    }
    const number = Number(text.replace(/,/g, ''));
    if (Number.isNaN(number)) {
        return null;
    }
    if (!hasPercent && number > 0 && number < 1) {
        return round1(number * 100);
    }
    return round1(number);
}

export function parseWholeNumber(value) {
    if (value === null || value === undefined || value === '') {
        return null;
    }
    const number = typeof value === 'number' ? value : Number(String(value).trim().replace(/,/g, ''));
    if (Number.isNaN(number)) {
        return null;
    }
    return number;
}

function percentOrEmpty(value) {
    if (value === null || value === undefined || value === '') {
        return '';
    }
    const number = Number(value);
    return Number.isNaN(number) ? '' : number;
}

function numberOrEmpty(value) {
    if (value === null || value === undefined || value === '') {
        return '';
    }
    const number = Number(value);
    return Number.isNaN(number) ? '' : number;
}

function blankToEmpty(value) {
    if (value === null || value === undefined) {
        return '';
    }
    return String(value);
}

function asString(value) {
    if (value === null || value === undefined) {
        return '';
    }
    return String(value).trim();
}

function round1(value) {
    return Math.round(value * 10) / 10;
}
