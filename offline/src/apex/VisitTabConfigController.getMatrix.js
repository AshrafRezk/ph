import { makeDualApex } from './_wireAdapter.js';
import { plannerApiFetch } from './restHelper.js';
import {
    TAB_ORDER,
    TAB_LABELS,
    defaultVisitTabs,
    featureKeyFor,
    orderTabKeys,
    parseTabKeys
} from './visitTabCatalog.js';

async function getMatrix() {
    const typeData = await plannerApiFetch(
        '/services/data/v62.0/query?q=' +
            encodeURIComponent(
                "SELECT DeveloperName, Name FROM RecordType WHERE SObjectType = 'Account' AND IsActive = true ORDER BY Name"
            ),
        { fresh: true }
    );
    const savedData = await plannerApiFetch(
        '/services/data/v62.0/query?q=' +
            encodeURIComponent(
                "SELECT Feature_Key__c, Description__c FROM Field_App_Feature__c WHERE Feature_Key__c LIKE 'visitTabs.%'"
            ),
        { fresh: true }
    );
    const saved = new Map(
        (savedData?.records || []).map((row) => [row.Feature_Key__c, row.Description__c])
    );
    const columns = TAB_ORDER.map((key) => ({
        key,
        label: TAB_LABELS[key],
        locked: key === 'details'
    }));
    const rows = (typeData?.records || []).map((recordType) => {
        const developerName = recordType.DeveloperName;
        const savedRaw = saved.get(featureKeyFor(developerName));
        const enabled = new Set(
            saved.has(featureKeyFor(developerName))
                ? orderTabKeys(parseTabKeys(savedRaw))
                : defaultVisitTabs(developerName, recordType.Name)
        );
        enabled.add('details');
        return {
            developerName,
            label: recordType.Name,
            cells: TAB_ORDER.map((key) => ({
                key,
                enabled: enabled.has(key),
                locked: key === 'details'
            }))
        };
    });
    return { columns, rows };
}

export default makeDualApex(getMatrix);
