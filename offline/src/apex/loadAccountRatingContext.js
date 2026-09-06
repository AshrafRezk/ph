import { makeDualApex } from './_wireAdapter.js';
import { plannerApiFetch } from './restHelper.js';

function escapeSoql(value) {
    return String(value || '').replace(/\\/g, '\\\\').replace(/'/g, "\\'");
}

export default makeDualApex(async (params = {}) => {
    const accountId = params.accountId;
    if (!accountId) {
        return {
            layoutId: null,
            layoutJson: null,
            accountVariant: 'HCP',
            alignedProducts: [],
            valuesJson: '{}'
        };
    }
    const id = escapeSoql(accountId);
    try {
        const acct = await plannerApiFetch(
            `/services/data/v62.0/query?q=${encodeURIComponent(
                `SELECT Id, Name, RecordType.DeveloperName, IsPersonAccount FROM Account WHERE Id = '${id}' LIMIT 1`
            )}`
        );
        const row = acct?.records?.[0];
        const developerName = row?.RecordType?.DeveloperName || '';
        const isHco = /hco|institution|pharmacy/i.test(developerName) || row?.IsPersonAccount === false;
        const variant = isHco ? 'HCO' : 'HCP';

        let layout = null;
        try {
            const layouts = await plannerApiFetch(
                `/services/data/v62.0/query?q=${encodeURIComponent(
                    `SELECT Id, Name, Fields_JSON__c, Account_Variant__c, Is_Active__c
                     FROM CLM_Rating_Layout__c
                     WHERE Is_Active__c = true
                     ORDER BY LastModifiedDate DESC
                     LIMIT 20`
                )}`
            );
            const records = layouts?.records || [];
            layout =
                records.find((r) => String(r.Account_Variant__c || '').toUpperCase() === variant) ||
                records[0] ||
                null;
        } catch (_layoutError) {
            layout = null;
        }

        let valuesJson = '{}';
        let territory2Id = null;
        let territoryName = null;
        try {
            const atf = await plannerApiFetch(
                `/services/data/v62.0/query?q=${encodeURIComponent(
                    `SELECT Id, Territory2Id, Territory2.Name, Rating_Values_JSON__c
                     FROM Account_Territory_Fields__c
                     WHERE Account__c = '${id}'
                     ORDER BY LastModifiedDate DESC
                     LIMIT 1`
                )}`
            );
            const atfRow = atf?.records?.[0];
            if (atfRow) {
                valuesJson = atfRow.Rating_Values_JSON__c || '{}';
                territory2Id = atfRow.Territory2Id || null;
                territoryName = atfRow.Territory2?.Name || null;
            }
        } catch (_atfError) {
            // optional
        }

        return {
            layoutId: layout?.Id || null,
            layoutJson: layout?.Fields_JSON__c || null,
            accountVariant: variant,
            territory2Id,
            territoryName,
            valuesJson,
            alignedProducts: []
        };
    } catch (_error) {
        return {
            layoutId: null,
            layoutJson: null,
            accountVariant: 'HCP',
            alignedProducts: [],
            valuesJson: '{}'
        };
    }
});
