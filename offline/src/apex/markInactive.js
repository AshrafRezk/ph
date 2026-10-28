import { makeDualApex } from './_wireAdapter.js';
import { plannerApiFetch, isNetworkError, isOffline } from './restHelper.js';
import { queueOfflineAction } from 'c/clmOfflineSync';
import getStage from './getStage.js';

function escapeSoql(value) {
    return String(value || '').replace(/\\/g, '\\\\').replace(/'/g, "\\'");
}

function historyLine(fromStage, reason) {
    const stamp = new Date().toISOString().slice(0, 16).replace('T', ' ');
    return `${stamp} | Offline | Marked inactive | ${fromStage} → Inactive | Reason: ${reason}`;
}

export default makeDualApex(async (params = {}) => {
    const accountId = params.accountId;
    const reason = String(params.reason || '').trim();
    if (!accountId) {
        throw new Error('Account Id is required.');
    }
    if (!reason) {
        throw new Error('Choose an inactive reason.');
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
    if (current === 'Inactive') {
        throw new Error('This account is already inactive.');
    }
    const history = row.Stage_History__c
        ? `${row.Stage_History__c}\n${historyLine(current, reason)}`
        : historyLine(current, reason);
    const body = {
        Account_Stage__c: 'Inactive',
        Account_Status__c: 'Inactive',
        Inactive_Reason__c: reason,
        Duplicate_Of__c: null,
        Stage_History__c: history
    };
    try {
        if (isOffline()) {
            throw new Error('offline');
        }
        // Online goes through AccountStageService, so the SFE / FI / BU / admin rule applies here too.
        await plannerApiFetch('/services/apexrest/account-stage/v1/mark-inactive', {
            method: 'POST',
            fresh: true,
            body: JSON.stringify({ accountId, reason })
        });
    } catch (error) {
        if (!isOffline() && !isNetworkError(error) && error?.message !== 'offline') {
            throw error;
        }
        await queueOfflineAction({
            actionType: 'MARK_ACCOUNT_INACTIVE',
            accountId,
            clientActionKey: `inactive_${accountId}_${Date.now()}`,
            payloadJson: JSON.stringify({ accountId, reason, body })
        });
    }
    return getStage({ accountId });
});
