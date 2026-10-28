import { makeDualApex } from './_wireAdapter.js';
import { plannerApiFetch } from './restHelper.js';

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

const PATH = [
    'Draft',
    'Pending DM',
    'Pending SFE',
    'Pending BU Approval',
    'FI Validation',
    'Active',
    'Inactive',
    'Duplicate'
];

function labelOf(api) {
    return LABELS[api] || api;
}

function nextForward(current) {
    const index = FORWARD_CHAIN.indexOf(current);
    if (index < 0 || index >= FORWARD_CHAIN.length - 1) {
        return null;
    }
    return FORWARD_CHAIN[index + 1];
}

function previousStage(current) {
    if (current === 'Inactive' || current === 'Duplicate') {
        return 'Active';
    }
    const index = FORWARD_CHAIN.indexOf(current);
    if (index <= 0) {
        return null;
    }
    return FORWARD_CHAIN[index - 1];
}

function buildSteps(current) {
    const currentIndex = PATH.indexOf(current);
    return PATH.map((api) => {
        const inForward = FORWARD_CHAIN.includes(current) && FORWARD_CHAIN.includes(api);
        return {
            apiName: api,
            label: labelOf(api),
            current: api === current,
            terminal: api === 'Inactive' || api === 'Duplicate',
            complete: inForward && currentIndex > FORWARD_CHAIN.indexOf(api)
        };
    });
}

function toView(row) {
    const current = row.Account_Stage__c || 'Draft';
    const nextApi = nextForward(current);
    const previousApi = previousStage(current);
    return {
        currentApi: current,
        currentLabel: labelOf(current),
        nextApi,
        nextLabel: nextApi ? labelOf(nextApi) : null,
        canAdvance: Boolean(nextApi),
        previousApi,
        previousLabel: previousApi ? labelOf(previousApi) : null,
        canSendBack: Boolean(previousApi),
        lastMessage: row.Stage_Send_Back_Message__c || null,
        history: row.Stage_History__c || null,
        inactiveReason: row.Inactive_Reason__c || null,
        duplicateOfId: row.Duplicate_Of__c || null,
        duplicateOfName: row.Duplicate_Of__r?.Name || null,
        steps: buildSteps(current),
        inactiveReasons: [],
        // Filled from the server below; hidden until the server says the user may close accounts out.
        canMarkInactive: false,
        canMarkDuplicate: false
    };
}

async function closeOutPermissions(accountId) {
    try {
        // Cached like other GETs, so the last answer still applies offline.
        const perms = await plannerApiFetch(
            `/services/apexrest/account-stage/v1/permissions?accountId=${encodeURIComponent(accountId)}`
        );
        return {
            canMarkInactive: perms?.canMarkInactive === true,
            canMarkDuplicate: perms?.canMarkDuplicate === true
        };
    } catch (_error) {
        return { canMarkInactive: false, canMarkDuplicate: false };
    }
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
                `SELECT Id, Name, Account_Stage__c, Stage_Send_Back_Message__c, Stage_History__c,
                        Inactive_Reason__c, Duplicate_Of__c, Duplicate_Of__r.Name
                 FROM Account WHERE Id = '${id}' LIMIT 1`
            )}`
        );
        const row = acct?.records?.[0];
        if (!row) {
            return null;
        }
        return { ...toView(row), ...(await closeOutPermissions(accountId)) };
    } catch (_error) {
        return null;
    }
});
