import { makeDualApex } from './_wireAdapter.js';
import { plannerApiFetch } from './restHelper.js';

function escapeSoql(value) {
    return String(value || '').replace(/\\/g, '\\\\').replace(/'/g, "\\'");
}

export default makeDualApex(async (params = {}) => {
    const term = String(params.searchTerm || params.q || '').trim();
    if (!term) return [];
    const like = `%${escapeSoql(term)}%`;
    const soql = `SELECT Id, Name, BillingCity, PersonMobilePhone, Phone, Specialty_1__c
        FROM Account
        WHERE Name LIKE '${like}'
        ORDER BY Name
        LIMIT 25`;
    try {
        const data = await plannerApiFetch(
            `/services/data/v59.0/query?q=${encodeURIComponent(soql)}`,
            { method: 'GET' }
        );
        return (data?.records || []).map((row, index) => ({
            accountId: row.Id,
            name: row.Name,
            city: row.BillingCity || '',
            specialty: row.Specialty_1__c || '',
            phone: row.PersonMobilePhone || row.Phone || '',
            matchKind: 'Name',
            score: 100 - index,
            matchReason: `Matched name “${term}”`
        }));
    } catch (_e) {
        return [];
    }
});
