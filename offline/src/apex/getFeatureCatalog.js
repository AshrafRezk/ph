import { makeDualApex } from './_wireAdapter.js';
import { soql } from './learningShared.js';

export default makeDualApex(async () => {
    const rows = await soql(
        'SELECT Id, Name, Feature_Key__c, Description__c, Category__c, Is_Enabled__c, Sort_Order__c FROM Field_App_Feature__c ORDER BY Sort_Order__c ASC NULLS LAST, Name ASC'
    );
    return rows.map((row) => ({
        id: row.Id,
        key: row.Feature_Key__c,
        label: row.Name,
        description: row.Description__c,
        category: row.Category__c,
        enabled: row.Is_Enabled__c === true,
        sortOrder: row.Sort_Order__c
    }));
});
