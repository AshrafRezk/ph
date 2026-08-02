/**
 * Employee_Report_Details__c is a text formula using BR() — Apex/API returns HTML (<br>).
 */

const HTML_BREAK = /<br\s*\/?>/gi;
const BLOCK_BREAK = /<\/(?:p|div|tr|li|h[1-6])>\s*<(?:p|div|tr|li|h[1-6])[^>]*>/gi;
const BLOCK_END = /<\/(?:p|div|tr|li|h[1-6])>/gi;
const BLOCK_START = /<(?:p|div|tr|li|h[1-6])[^>]*>/gi;
const ANY_TAG = /<[^>]+>/g;

const REPORT_DETAIL_LABELS = ['Name', 'External ID', 'Profile', 'Segment', 'Company'];

/**
 * @param {string} raw
 * @returns {string[]}
 */
export function parseEmployeeReportDetails(raw) {
    if (!raw || typeof raw !== 'string') {
        return [];
    }

    let text = raw.replace(HTML_BREAK, '\n');
    text = text.replace(BLOCK_BREAK, '\n');
    text = text.replace(BLOCK_END, '\n');
    text = text.replace(BLOCK_START, '');
    text = decodeBasicHtmlEntities(text.replace(ANY_TAG, ''));

    return text
        .split(/\r?\n/)
        .map((line) => line.trim())
        .filter((line) => line.length > 0);
}

/**
 * Safe HTML for lightning-formatted-rich-text (formula output or plain newlines).
 * @param {string} raw
 * @returns {string}
 */
export function toReportDetailsHtml(raw) {
    const lines = parseEmployeeReportDetails(raw);
    if (lines.length === 0) {
        return '';
    }
    return lines.map(escapeHtml).join('<br/>');
}

/**
 * Labeled rows for Employee_Report_Details__c (fixed formula line order).
 * @param {string} raw
 * @returns {{ key: string, label: string, value: string }[]}
 */
export function parseEmployeeReportDetailRows(raw) {
    if (!raw || typeof raw !== 'string') {
        return [];
    }

    let text = raw.replace(HTML_BREAK, '\n');
    text = text.replace(BLOCK_BREAK, '\n');
    text = text.replace(BLOCK_END, '\n');
    text = text.replace(BLOCK_START, '');
    text = decodeBasicHtmlEntities(text.replace(ANY_TAG, ''));

    const lines = text.split(/\r?\n/).map((line) => line.trim());

    return REPORT_DETAIL_LABELS.map((label, index) => ({
        key: String(index),
        label,
        value: lines[index] || ''
    })).filter((row) => row.value.length > 0);
}

function decodeBasicHtmlEntities(value) {
    return value
        .replace(/&nbsp;/gi, ' ')
        .replace(/&amp;/gi, '&')
        .replace(/&lt;/gi, '<')
        .replace(/&gt;/gi, '>')
        .replace(/&quot;/gi, '"')
        .replace(/&#39;/g, "'")
        .replace(/&#(\d+);/g, (_, code) => String.fromCharCode(Number(code)));
}

function escapeHtml(text) {
    return text
        .replace(/&/g, '&amp;')
        .replace(/</g, '&lt;')
        .replace(/>/g, '&gt;')
        .replace(/"/g, '&quot;');
}
