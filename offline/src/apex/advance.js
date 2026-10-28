import { makeDualApex } from './_wireAdapter.js';
import { plannerApiFetch, isNetworkError, isOffline } from './restHelper.js';
import { queueOfflineAction } from 'c/clmOfflineSync';
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

const LABELS = {
    Draft: 'Draft',
    'Pending DM': 'DM Approval',
    'Pending SFE': 'SFE Approval',
    'Pending BU Approval': 'BU Approval',
    'FI Validation': 'FI Validation',
    Active: 'Active',
    Inactive: 'Inactive',
    Duplicate: 'Duplicate'
};

function historyLine(fromStage, toStage) {
    const stamp = new Date().toISOString().slice(0, 16).replace('T', ' ');
    return `${stamp} | Offline | Advanced | ${fromStage} → ${toStage}`;
}

function optimisticView(row, next) {
    const current = next;
    const index = FORWARD_CHAIN.indexOf(current);
    const nextApi = index >= 0 && index < FORWARD_CHAIN.length - 1 ? FORWARD_CHAIN[index + 1] : null;
    return {
        currentApi: current,
        currentLabel: LABELS[current] || current,
        nextApi,
        nextLabel: nextApi ? LABELS[nextApi] || nextApi : null,
        canAdvance: Boolean(nextApi),
        previousApi: row.Account_Stage__c || 'Draft',
        previousLabel: LABELS[row.Account_Stage__c] || row.Account_Stage__c,
        canSendBack: true,
        lastMessage: row.Stage_Send_Back_Message__c || null,
        history: row.Stage_History__c || null,
        inactiveReason: null,
        duplicateOfId: null,
        duplicateOfName: null,
        steps: [],
        inactiveReasons: []
    };
}

async function patchAdvance(accountId, current, next, existingHistory) {
    const history = existingHistory
        ? `${existingHistory}\n${historyLine(current, next)}`
        : historyLine(current, next);
    const body = {
        Account_Stage__c: next,
        Stage_History__c: history
    };
    if (next === 'Active') {
        body.Account_Status__c = 'Active';
    }
    await plannerApiFetch(`/services/data/v62.0/sobjects/Account/${encodeURIComponent(accountId)}`, {
        method: 'PATCH',
        body: JSON.stringify(body)
    });
    return history;
}

export default makeDualApex(async (params = {}) => {
    const accountId = params.accountId;
    if (!accountId) {
        throw new Error('Account Id is required.');
    }
    const result = await plannerApiFetch(
        `/services/data/v62.0/query?q=${encodeURIComponent(
            `SELECT Id, Account_Stage__c, Stage_History__c, Stage_Send_Back_Message__c FROM Account WHERE Id = '${escapeSoql(accountId)}' LIMIT 1`
        )}`
    );
    const row = result?.records?.[0];
    if (!row) {
        throw new Error('Account not found.');
    }
    const current = row.Account_Stage__c || 'Draft';
    const index = FORWARD_CHAIN.indexOf(current);
    if (index < 0 || index >= FORWARD_CHAIN.length - 1) {
        throw new Error(`This account cannot be advanced from ${current}.`);
    }
    const next = FORWARD_CHAIN[index + 1];
    let queued = false;
    try {
        if (isOffline()) {
            throw new Error('offline');
        }
        row.Stage_History__c = await patchAdvance(accountId, current, next, row.Stage_History__c);
        row.Account_Stage__c = next;
    } catch (error) {
        if (!isOffline() && !isNetworkError(error) && error?.message !== 'offline') {
            throw error;
        }
        queued = true;
        row.Account_Stage__c = next;
        row.Stage_History__c = row.Stage_History__c
            ? `${row.Stage_History__c}\n${historyLine(current, next)}`
            : historyLine(current, next);
        await queueOfflineAction({
            actionType: 'ADVANCE_ACCOUNT_STAGE',
            accountId,
            clientActionKey: `advance_${accountId}_${Date.now()}`,
            payloadJson: JSON.stringify({
                accountId,
                fromStage: current,
                toStage: next,
                history: row.Stage_History__c
            })
        });
    }
    if (queued) {
        return optimisticView({ ...row, Account_Stage__c: current }, next);
    }
    try {
        return await getStage({ accountId });
    } catch (_err) {
        return optimisticView({ ...row, Account_Stage__c: current }, next);
    }
});
