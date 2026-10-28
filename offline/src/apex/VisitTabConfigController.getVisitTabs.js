import { makeDualApex } from './_wireAdapter.js';
import { plannerApiFetch } from './restHelper.js';
import { defaultVisitTabs, featureKeyFor, orderTabKeys, parseTabKeys } from './visitTabCatalog.js';

function esc(value) {
    return String(value || '').replace(/\\/g, '\\\\').replace(/'/g, "\\'");
}

async function getVisitTabs(params = {}) {
    const developerName = params.developerName || '';
    const recordTypeName = params.recordTypeName || '';
    const defaults = defaultVisitTabs(developerName, recordTypeName);
    if (!developerName) {
        return defaults;
    }
    try {
        const soql =
            'SELECT Description__c FROM Field_App_Feature__c ' +
            `WHERE Feature_Key__c = '${esc(featureKeyFor(developerName))}' LIMIT 1`;
        const data = await plannerApiFetch(
            `/services/data/v62.0/query?q=${encodeURIComponent(soql)}`,
            { fresh: true }
        );
        const raw = data?.records?.[0]?.Description__c;
        if (!raw) {
            return defaults;
        }
        const keys = orderTabKeys(parseTabKeys(raw));
        return keys.length ? keys : defaults;
    } catch (_err) {
        return defaults;
    }
}

export default makeDualApex(getVisitTabs);
