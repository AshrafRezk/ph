import { makeDualApex } from './_wireAdapter.js';
import { plannerApiFetch, isNetworkError, isOffline } from './restHelper.js';
import { queueOfflineAction } from 'c/clmOfflineSync';
import getStage from './getStage.js';

function escapeSoql(value) {
    return String(value || '').replace(/\\/g, '\\\\').replace(/'/g, "\\'");
}

function historyLine(fromStage, masterName) {
    const stamp = new Date().toISOString().slice(0, 16).replace('T', ' ');
    return `${stamp} | Offline | Marked duplicate of ${masterName} | ${fromStage} → Duplicate`;
}

export default makeDualApex(async (params = {}) => {
    const accountId = params.accountId;
    const duplicateOfId = params.duplicateOfId;
    if (!accountId) {
        throw new Error('Account Id is required.');
    }
    if (!duplicateOfId) {
        throw new Error('Select the original account this record duplicates.');
    }
    if (duplicateOfId === accountId) {
        throw new Error('Select a different account. A record cannot be a duplicate of itself.');
    }

    const masterResult = await plannerApiFetch(
        `/services/data/v62.0/query?q=${encodeURIComponent(
            `SELECT Id, Name FROM Account WHERE Id = '${escapeSoql(duplicateOfId)}' LIMIT 1`
        )}`
    );
    const master = masterResult?.records?.[0];
    if (!master) {
        throw new Error('The selected original account was not found.');
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
    if (current === 'Duplicate') {
        throw new Error('This account is already marked as a duplicate.');
    }
    const history = row.Stage_History__c
        ? `${row.Stage_History__c}\n${historyLine(current, master.Name)}`
        : historyLine(current, master.Name);
    const body = {
        Account_Stage__c: 'Duplicate',
        Account_Status__c: 'Inactive',
        Duplicate_Of__c: duplicateOfId,
        Inactive_Reason__c: null,
        Stage_History__c: history
    };
    try {
        if (isOffline()) {
            throw new Error('offline');
        }
        // Online goes through AccountStageService, so the SFE / FI / BU / admin rule applies here too.
        await plannerApiFetch('/services/apexrest/account-stage/v1/mark-duplicate', {
            method: 'POST',
            fresh: true,
            body: JSON.stringify({ accountId, duplicateOfId })
        });
    } catch (error) {
        if (!isOffline() && !isNetworkError(error) && error?.message !== 'offline') {
            throw error;
        }
        await queueOfflineAction({
            actionType: 'MARK_ACCOUNT_DUPLICATE',
            accountId,
            clientActionKey: `duplicate_${accountId}_${Date.now()}`,
            payloadJson: JSON.stringify({ accountId, duplicateOfId, body })
        });
    }
    return getStage({ accountId });
});
