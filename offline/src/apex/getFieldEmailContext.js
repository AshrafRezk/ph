import { makeDualApex } from './_wireAdapter.js';
import { soqlOne, esc } from './learningShared.js';
import { requireVisit, visitLocked } from './fieldWorkflowShared.js';

export default makeDualApex(async (params = {}) => {
    const visit = await requireVisit(params.visitId);
    let toAddress = '';
    if (visit.Account__c) {
        const account = await soqlOne(
            `SELECT PersonEmail FROM Account WHERE Id = '${esc(visit.Account__c)}' LIMIT 1`
        );
        toAddress = account?.PersonEmail || '';
    }
    const accountName = visit.Account__r?.Name;
    return {
        toAddress,
        accountName,
        visitName: visit.Name,
        isLocked: visitLocked(visit),
        defaultSubject: accountName ? `Follow-up: ${accountName}` : 'Visit follow-up'
    };
});
