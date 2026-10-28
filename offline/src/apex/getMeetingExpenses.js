import { makeDualApex } from './_wireAdapter.js';
import { soql, apexError, esc } from './learningShared.js';

export default makeDualApex(async (params = {}) => {
    if (!params.meetingId) {
        throw apexError('Meeting Id is required.');
    }
    const rows = await soql(
        `SELECT Id, Name, Type__c, Amount__c, Status__c, Comments__c FROM Meeting_Expense__c WHERE Meeting__c = '${esc(params.meetingId)}' ORDER BY CreatedDate DESC LIMIT 50`
    );
    return rows.map((row) => ({
        id: row.Id,
        name: row.Name,
        type: row.Type__c,
        amount: row.Amount__c,
        status: row.Status__c,
        comments: row.Comments__c
    }));
});
