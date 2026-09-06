import { makeDualApex } from './_wireAdapter.js';
import { plannerApiFetch } from './restHelper.js';

function escapeSoql(value) {
    return String(value || '').replace(/\\/g, '\\\\').replace(/'/g, "\\'");
}

export default makeDualApex(async (params = {}) => {
    const accountId = params.accountId;
    if (!accountId) {
        return null;
    }
    const id = escapeSoql(accountId);
    try {
        const acct = await plannerApiFetch(
            `/services/data/v62.0/query?q=${encodeURIComponent(
                `SELECT Id, Name, Account_Stage__c, RecordType.DeveloperName FROM Account WHERE Id = '${id}' LIMIT 1`
            )}`
        );
        const row = acct?.records?.[0];
        if (!row) {
            return null;
        }
        const stage = row.Account_Stage__c || 'Draft';
        return {
            accountId: row.Id,
            accountName: row.Name,
            currentStage: stage,
            currentStageLabel: stage,
            steps: [
                { value: 'Draft', label: 'Draft', isCurrent: stage === 'Draft' },
                { value: 'Active', label: 'Active', isCurrent: stage === 'Active' }
            ],
            canAdvance: true,
            canSendBack: false
        };
    } catch (_error) {
        return null;
    }
});
