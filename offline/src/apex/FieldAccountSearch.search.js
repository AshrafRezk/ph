import { makeDualApex } from './_wireAdapter.js';
import { plannerApiFetch } from './restHelper.js';
import { prepareNameRomanizer } from '../nameRomanizer.js';
import { lookupNeedles, scoreCandidate, toHit } from '../accountLookupSearch.js';

function soqlEscape(value) {
    return String(value || '').replace(/\\/g, '\\\\').replace(/'/g, "\\'");
}

async function queryNames(needles) {
    const clauses = needles
        .filter((needle) => String(needle || '').trim().length >= 3)
        .map((needle) => `Name LIKE '%${soqlEscape(needle)}%'`);
    if (!clauses.length) return [];
    const soql =
        'SELECT Id, Name, RecordType.Name, RecordType.DeveloperName FROM Account WHERE (' +
        clauses.join(' OR ') +
        ') ORDER BY Name LIMIT 40';
    const data = await plannerApiFetch(`/services/data/v62.0/query?q=${encodeURIComponent(soql)}`);
    return data?.records || [];
}

async function search(params = {}) {
    const term = String(params.term || '').trim();
    if (import.meta.env.DEV && globalThis.__ZETA_LOOKUP_PREVIEW__?.search) {
        return globalThis.__ZETA_LOOKUP_PREVIEW__.search(term);
    }
    if (term.length < 2) return [];
    const index = await prepareNameRomanizer();
    let needles = lookupNeedles(index, term, false);
    let rows = await queryNames(needles);
    if (!rows.length) {
        needles = lookupNeedles(index, term, true);
        rows = await queryNames(needles);
    }
    return rows
        .map((row) => ({ ...toHit(row), score: scoreCandidate(term, row.Name, needles) }))
        .filter((row) => row.score >= 40)
        .sort((left, right) => right.score - left.score || left.accountName.localeCompare(right.accountName))
        .slice(0, 12);
}

export default makeDualApex(search);
