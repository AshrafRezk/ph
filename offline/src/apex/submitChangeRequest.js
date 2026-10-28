import { makeDualApex } from './_wireAdapter.js';
import { soqlOne, apexError, esc } from './learningShared.js';
import { requireUnlockedVisit, createSObject } from './fieldWorkflowShared.js';
import getChangeRequests from './getChangeRequests.js';

function currentValue(account, changeType) {
    if (changeType === 'Name') return account.Name;
    if (changeType === 'Phone') return account.Phone;
    if (changeType === 'Email') return account.PersonEmail;
    if (changeType === 'Specialty') return account.Specialty_1__c;
    if (changeType === 'Address') {
        return [account.BillingStreet, account.BillingCity].filter(Boolean).join(', ');
    }
    return null;
}

export default makeDualApex(async (params = {}) => {
    const request = params.request || params;
    if (!request.changeType) {
        throw apexError('Select a change type.');
    }
    if (!String(request.proposedValue || '').trim()) {
        throw apexError('Enter the proposed value.');
    }
    const visit = await requireUnlockedVisit(request.visitId);
    if (!visit.Account__c) {
        throw apexError('This visit has no account.');
    }
    const account = await soqlOne(
        `SELECT Id, Name, Phone, PersonEmail, BillingStreet, BillingCity, Specialty_1__c FROM Account WHERE Id = '${esc(visit.Account__c)}' LIMIT 1`
    );
    await createSObject('Account_Change_Request__c', {
        Account__c: visit.Account__c,
        Visit__c: visit.Id,
        Change_Type__c: request.changeType,
        Current_Value__c: currentValue(account || {}, request.changeType),
        Proposed_Value__c: String(request.proposedValue).trim(),
        Reason__c: request.reason || null,
        Status__c: 'Submitted'
    });
    return getChangeRequests({ visitId: visit.Id });
});
