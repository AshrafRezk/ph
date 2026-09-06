import { makeDualApex } from './_wireAdapter.js';
import { plannerApiFetch } from './restHelper.js';

function escapeSoql(value) {
    return String(value || '').replace(/\\/g, '\\\\').replace(/'/g, "\\'");
}

function tokenize(term) {
    return String(term || '')
        .toLowerCase()
        .replace(/[^\p{L}\p{N}\s.-]/gu, ' ')
        .split(/\s+/)
        .map((t) => t.replace(/\.$/, ''))
        .filter((t) => t && !['dr', 'mr', 'mrs', 'ms', 'prof', 'doctor'].includes(t));
}

export default makeDualApex(async (params = {}) => {
    const term = String(params.searchTerm || params.q || '').trim();
    const recordTypeId = params.recordTypeId || null;
    if (!term) {
        return [];
    }
    const tokens = tokenize(term);
    if (!tokens.length) {
        return [];
    }
    const clauses = tokens.map((token) => {
        const like = `%${escapeSoql(token)}%`;
        return `(Name LIKE '${like}' OR FirstName LIKE '${like}' OR LastName LIKE '${like}' OR BillingCity LIKE '${like}')`;
    });
    let soql = `SELECT Id, Name, FirstName, LastName, BillingCity, PersonMobilePhone, Phone, Specialty_1__c, Brick_148__c, Brick_702__c
        FROM Account
        WHERE (${clauses.join(' AND ')})`;
    if (recordTypeId) {
        soql += ` AND RecordTypeId = '${escapeSoql(recordTypeId)}'`;
    }
    soql += ' ORDER BY Name LIMIT 40';
    try {
        const data = await plannerApiFetch(
            `/services/data/v62.0/query?q=${encodeURIComponent(soql)}`,
            { method: 'GET' }
        );
        return (data?.records || []).map((row, index) => ({
            accountId: row.Id,
            name: row.Name,
            city: row.BillingCity || '',
            specialty: row.Specialty_1__c || '',
            phone: row.PersonMobilePhone || row.Phone || '',
            brick148Label: row.Brick_148__c || '',
            brick702Label: row.Brick_702__c || '',
            matchKind: 'Cognitive',
            score: 100 - index,
            matchReason: `Matched “${term}”`
        }));
    } catch (_e) {
        return [];
    }
});
