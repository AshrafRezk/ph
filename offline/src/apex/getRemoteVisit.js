import { makeDualApex } from './_wireAdapter.js';
import { requireVisit, visitLocked } from './fieldWorkflowShared.js';

export default makeDualApex(async (params = {}) => {
    const visit = await requireVisit(params.visitId, 'Is_Remote__c, Remote_Join_Url__c');
    return {
        isRemote: visit.Is_Remote__c === true,
        joinUrl: visit.Remote_Join_Url__c || '',
        isLocked: visitLocked(visit)
    };
});
