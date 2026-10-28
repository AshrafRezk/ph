import { makeDualApex } from './_wireAdapter.js';
import { soql } from './learningShared.js';
import { requireVisit, visitLocked, CHANGE_TYPE_OPTIONS, esc } from './fieldWorkflowShared.js';

export default makeDualApex(async (params = {}) => {
    const visit = await requireVisit(params.visitId);
    const accountId = visit.Account__c;
    const requests = accountId
        ? await soql(
              'SELECT Id, Name, Change_Type__c, Current_Value__c, Proposed_Value__c, Status__c, Reason__c ' +
                  `FROM Account_Change_Request__c WHERE Account__c = '${esc(accountId)}' ORDER BY CreatedDate DESC LIMIT 50`
          )
        : [];
    return {
        accountId,
        accountName: visit.Account__r?.Name,
        isLocked: visitLocked(visit),
        changeTypeOptions: CHANGE_TYPE_OPTIONS,
        requests: requests.map((row) => ({
            id: row.Id,
            name: row.Name,
            changeType: row.Change_Type__c,
            currentValue: row.Current_Value__c,
            proposedValue: row.Proposed_Value__c,
            status: row.Status__c,
            reason: row.Reason__c
        }))
    };
});
