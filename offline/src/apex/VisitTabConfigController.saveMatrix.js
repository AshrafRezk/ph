import { plannerApiFetch } from './restHelper.js';
import { makeDualApex } from './_wireAdapter.js';
import getMatrix from './VisitTabConfigController.getMatrix.js';
import { TAB_LABELS, featureKeyFor, orderTabKeys } from './visitTabCatalog.js';

async function saveMatrix(params = {}) {
    const rows = JSON.parse(params.rowsJson || '[]');
    const records = (Array.isArray(rows) ? rows : [])
        .filter((row) => row && row.developerName)
        .map((row) => {
            const tabs = orderTabKeys(
                (row.tabs || []).filter((key) => TAB_LABELS[key])
            );
            const label = String(row.label || row.developerName).slice(0, 80);
            return {
                attributes: { type: 'Field_App_Feature__c' },
                Feature_Key__c: featureKeyFor(row.developerName),
                Name: label,
                Description__c: tabs.join(','),
                Category__c: 'Visit',
                Sort_Order__c: 900,
                Is_Enabled__c: true
            };
        });
    if (!records.length) {
        throw new Error('No account record types were updated.');
    }
    await plannerApiFetch(
        '/services/data/v62.0/composite/sobjects/Field_App_Feature__c/Feature_Key__c',
        {
            method: 'PATCH',
            body: JSON.stringify({ allOrNone: true, records })
        }
    );
    return getMatrix();
}

export default makeDualApex(saveMatrix);
