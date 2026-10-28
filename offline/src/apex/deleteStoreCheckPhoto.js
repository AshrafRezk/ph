import { makeDualApex } from './_wireAdapter.js';
import { soql, apexError } from './learningShared.js';
import { requireUnlockedVisit, deleteSObject, esc } from './fieldWorkflowShared.js';
import getStoreCheck from './getStoreCheck.js';

export default makeDualApex(async (params = {}) => {
    const visit = await requireUnlockedVisit(params.visitId);
    const contentDocumentId = params.contentDocumentId;
    if (!contentDocumentId) {
        throw apexError('Photo Id is required.');
    }
    const checks = await soql(
        `SELECT Id FROM Store_Check__c WHERE Visit__c = '${esc(visit.Id)}' ORDER BY CreatedDate DESC LIMIT 5`
    );
    const ids = checks.map((row) => `'${esc(row.Id)}'`).join(',');
    const links = ids
        ? await soql(
              'SELECT Id FROM ContentDocumentLink ' +
                  `WHERE ContentDocumentId = '${esc(contentDocumentId)}' AND LinkedEntityId IN (${ids})`
          )
        : [];
    if (!links.length) {
        throw apexError('Photo is not on this store check.');
    }
    await deleteSObject('ContentDocument', contentDocumentId);
    return getStoreCheck({ visitId: visit.Id });
});
