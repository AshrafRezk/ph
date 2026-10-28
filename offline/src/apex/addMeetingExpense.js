import { makeDualApex } from './_wireAdapter.js';
import { soqlOne, apexError, esc } from './learningShared.js';
import { createSObject } from './fieldWorkflowShared.js';

export default makeDualApex(async (params = {}) => {
    if (!params.meetingId) {
        throw apexError('Meeting Id is required.');
    }
    if (!params.expenseType) {
        throw apexError('Select an expense type.');
    }
    if (!(Number(params.amount) > 0)) {
        throw apexError('Enter an amount greater than zero.');
    }
    const meeting = await soqlOne(`SELECT Id FROM Meeting__c WHERE Id = '${esc(params.meetingId)}' LIMIT 1`);
    if (!meeting) {
        throw apexError('Meeting not found.');
    }
    const recordType = await soqlOne(
        "SELECT Id FROM RecordType WHERE SobjectType = 'Meeting_Expense__c' AND DeveloperName = 'Actual' AND IsActive = true LIMIT 1"
    );
    const payload = {
        Meeting__c: params.meetingId,
        Type__c: params.expenseType,
        Amount__c: Number(params.amount),
        Status__c: 'Draft',
        Comments__c: params.comments || null,
        Date_Time__c: new Date().toISOString(),
        Currency_Code__c: 'EGP'
    };
    if (recordType?.Id) {
        payload.RecordTypeId = recordType.Id;
    }
    const id = await createSObject('Meeting_Expense__c', payload);
    return {
        id,
        type: params.expenseType,
        amount: Number(params.amount),
        status: 'Draft',
        comments: params.comments || null
    };
});
