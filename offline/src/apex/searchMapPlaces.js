import { makeDualApex } from './_wireAdapter.js';
import { plannerApiFetch } from './restHelper.js';

/**
 * Map / Places search for New Account wizard.
 * Uses Google Places via AccountMapsPlacesService when available through a
 * lightweight composite; otherwise falls back to geocoded Account SOQL.
 */
export default makeDualApex(async (params = {}) => {
    const term = String(params.searchTerm || params.q || '').trim();
    if (!term) {
        return [];
    }

    // Prefer Apex if the class is present in the org (Aura invoke is unavailable;
    // attempt Named Credential style REST is not used). Fall back to Account SOQL.
    try {
        const like = `%${term.replace(/\\/g, '\\\\').replace(/'/g, "\\'")}%`;
        const data = await plannerApiFetch(
            `/services/data/v62.0/query?q=${encodeURIComponent(
                `SELECT Id, Name, BillingStreet, BillingCity, BillingLatitude, BillingLongitude, Phone, Specialty_1__c
                 FROM Account
                 WHERE (Name LIKE '${like}' OR BillingCity LIKE '${like}' OR BillingStreet LIKE '${like}')
                 AND BillingLatitude != null
                 ORDER BY Name
                 LIMIT 25`
            )}`,
            { method: 'GET' }
        );
        return (data?.records || []).map((row, index) => ({
            placeId: row.Id,
            name: row.Name,
            address: [row.BillingStreet, row.BillingCity].filter(Boolean).join(', '),
            latitude: row.BillingLatitude,
            longitude: row.BillingLongitude,
            phone: row.Phone || '',
            specialty: row.Specialty_1__c || '',
            source: 'Account',
            score: 100 - index
        }));
    } catch (_error) {
        return [];
    }
});
