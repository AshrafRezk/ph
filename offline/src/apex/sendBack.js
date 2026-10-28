import { makeDualApex } from './_wireAdapter.js';
import { plannerApiFetch } from './restHelper.js';
import getStage from './getStage.js';

function escapeSoql(value) {
    return String(value || '').replace(/\\/g, '\\\\').replace(/'/g, "\\'");
}

const FORWARD_CHAIN = [
    'Draft',
    'Pending DM',
    'Pending SFE',
    'Pending BU Approval',
    'FI Validation',
    'Active'
];

export default makeDualApex(async (params = {}) => {
    const accountId = params.accountId;
    const message = params.message || '';
    if (!accountId) {
        throw new Error('Account Id is required.');
    }
    const result = await plannerApiFetch(
        `/services/data/v62.0/query?q=${encodeURIComponent(
            `SELECT Id, Account_Stage__c, Stage_History__c FROM Account WHERE Id = '${escapeSoql(accountId)}' LIMIT 1`
        )}`
    );
    const row = result?.records?.[0];
    if (!row) {
        throw new Error('Account not found.');
    }
    const current = row.Account_Stage__c || 'Draft';
    let previous;
    if (current === 'Inactive' || current === 'Duplicate') {
        previous = 'Active';
    } else {
        const index = FORWARD_CHAIN.indexOf(current);
        if (index <= 0) {
            throw new Error(`This account cannot be thrown back from ${current}.`);
        }
        previous = FORWARD_CHAIN[index - 1];
    }
    const historyLine = `${new Date().toISOString()} · Sent back to ${previous}${message ? `: ${message}` : ''}`;
    const history = row.Stage_History__c
        ? `${row.Stage_History__c}\n${historyLine}`
        : historyLine;
    await plannerApiFetch(`/services/data/v62.0/sobjects/Account/${encodeURIComponent(accountId)}`, {
        method: 'PATCH',
        body: JSON.stringify({
            Account_Stage__c: previous,
            Stage_Send_Back_Message__c: message || null,
            Stage_History__c: history
        })
    });
    return getStage({ accountId });
});
