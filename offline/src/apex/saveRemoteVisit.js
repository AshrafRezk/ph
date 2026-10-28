import { makeDualApex } from './_wireAdapter.js';
import { requireUnlockedVisit, updateSObject } from './fieldWorkflowShared.js';
import getRemoteVisit from './getRemoteVisit.js';

export default makeDualApex(async (params = {}) => {
    const visit = await requireUnlockedVisit(params.visitId);
    await updateSObject('Visit__c', visit.Id, {
        Is_Remote__c: params.isRemote === true,
        Remote_Join_Url__c: String(params.joinUrl || '').trim() || null
    });
    return getRemoteVisit({ visitId: visit.Id });
});
