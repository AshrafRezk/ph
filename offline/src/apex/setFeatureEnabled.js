import { makeDualApex } from './_wireAdapter.js';
import { soqlOne, esc, apexError } from './learningShared.js';
import { updateSObject } from './fieldWorkflowShared.js';

export default makeDualApex(async (params = {}) => {
    const featureKey = params.featureKey;
    const enabled = params.enabled === true;
    if (!featureKey) {
        throw apexError('Feature key is required.');
    }
    const record = await soqlOne(
        `SELECT Id, Name, Feature_Key__c, Description__c, Category__c, Is_Enabled__c, Sort_Order__c FROM Field_App_Feature__c WHERE Feature_Key__c = '${esc(featureKey)}' LIMIT 1`,
        { fresh: true }
    );
    if (!record) {
        throw apexError('Unknown feature: ' + featureKey);
    }
    await updateSObject('Field_App_Feature__c', record.Id, { Is_Enabled__c: enabled });
    return {
        id: record.Id,
        key: record.Feature_Key__c,
        label: record.Name,
        description: record.Description__c,
        category: record.Category__c,
        enabled,
        sortOrder: record.Sort_Order__c
    };
});
