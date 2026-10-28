import { plannerApiFetch } from './restHelper.js';

export default async function saveCopilotNavigation({ appKey, tabsJson } = {}) {
    const tabs = JSON.parse(tabsJson || '[]');
    const records = tabs
        .filter((tab) => tab && tab.key)
        .map((tab, index) => ({
            attributes: { type: 'Field_App_Feature__c' },
            Feature_Key__c: `nav.${appKey}.${tab.key}`,
            Name: String(tab.label || tab.key).slice(0, 80),
            Description__c: appKey,
            Sort_Order__c: index + 1,
            Is_Enabled__c: tab.enabled === true
        }));
    if (!records.length) {
        return null;
    }
    return plannerApiFetch('/services/data/v62.0/composite/sobjects/Field_App_Feature__c/Feature_Key__c', {
        method: 'PATCH',
        body: JSON.stringify({ allOrNone: true, records })
    });
}
