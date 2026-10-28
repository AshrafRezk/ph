import { esc, soql } from './learningShared.js';

const ALL = 'All';
const STATUS_STRONG = 'Strong coverage';
const STATUS_IN_PROGRESS = 'In progress';
const FALLBACK_PLAN_NAME = 'Stakeholder coverage plan';

function option(label, value) {
    return { label, value };
}

function safeRate(numerator, denominator) {
    if (!denominator || denominator <= 0) {
        return 0;
    }
    return (Number(numerator || 0) / Number(denominator)) * 100;
}

function isActivePlanStatus(status) {
    const normalized = String(status || '').toLowerCase();
    return (
        normalized.includes('progress') ||
        normalized.includes('active') ||
        normalized === 'in progress' ||
        normalized.includes('coverage')
    );
}

function isCompletedObjectiveStatus(status) {
    const normalized = String(status || '').toLowerCase();
    return normalized.includes('complete') || normalized.includes('done') || normalized === 'completed';
}

function deriveAffiliationPlanStatus(stakeholderCount) {
    if (!stakeholderCount || stakeholderCount < 1) {
        return STATUS_IN_PROGRESS;
    }
    return stakeholderCount >= 5 ? STATUS_STRONG : STATUS_IN_PROGRESS;
}

function emptyPayload() {
    return {
        kpis: {
            totalPlans: 0,
            activePlans: 0,
            totalObjectives: 0,
            completedObjectives: 0,
            objectiveCompletionRate: 0,
            accountsWithStakeholders: 0,
            stakeholderCoveragePercent: 0
        },
        plans: [],
        objectives: [],
        stakeholders: []
    };
}

function idList(ids) {
    return [...ids].map((id) => `'${esc(id)}'`).join(',');
}

async function queryPlans(statusFilter) {
    let query = 'SELECT Id, Name, AccountId, Account.Name, Status, StartDate, EndDate FROM AccountPlan';
    if (statusFilter) {
        query += ` WHERE Status = '${esc(statusFilter)}'`;
    }
    query += ' ORDER BY LastModifiedDate DESC LIMIT 500';
    return soql(query);
}

async function loadObjectives(planIds) {
    const byPlan = new Map();
    if (!planIds.size) {
        return byPlan;
    }
    const rows = await soql(
        'SELECT Id, Name, Status, AccountPlanId, StartDate, EndDate FROM AccountPlanObjective ' +
            `WHERE AccountPlanId IN (${idList(planIds)}) ORDER BY Name LIMIT 2000`
    );
    rows.forEach((objective) => {
        const list = byPlan.get(objective.AccountPlanId) || [];
        list.push(objective);
        byPlan.set(objective.AccountPlanId, list);
    });
    return byPlan;
}

async function loadStakeholderCounts(accountIds) {
    const counts = new Map();
    if (!accountIds.size) {
        return counts;
    }
    const rows = await soql(
        'SELECT Primary_Account__c, COUNT(Id) total FROM Account_Affiliation__c ' +
            `WHERE Primary_Account__c IN (${idList(accountIds)}) AND Is_Active__c = TRUE ` +
            'GROUP BY Primary_Account__c'
    );
    rows.forEach((row) => {
        counts.set(row.Primary_Account__c, Number(row.total || 0));
    });
    return counts;
}

async function loadStakeholderAffiliations(accountIds) {
    if (!accountIds.size) {
        return [];
    }
    return soql(
        'SELECT Id, Primary_Account__c, Primary_Account__r.Name, Related_Account__r.Name, Role__c, Influence__c, Affiliation_Type__c, Is_Active__c ' +
            'FROM Account_Affiliation__c ' +
            `WHERE Primary_Account__c IN (${idList(accountIds)}) AND Is_Active__c = TRUE ` +
            'ORDER BY Primary_Account__r.Name, Related_Account__r.Name LIMIT 500'
    );
}

function mapStakeholderRows(affiliations) {
    return (affiliations || []).map((affiliation) => ({
        affiliationId: affiliation.Id,
        accountId: affiliation.Primary_Account__c,
        accountName: affiliation.Primary_Account__r?.Name || '',
        relatedAccountName: affiliation.Related_Account__r?.Name || '',
        role: affiliation.Role__c,
        influence: affiliation.Influence__c,
        affiliationType: affiliation.Affiliation_Type__c,
        isActive: affiliation.Is_Active__c
    }));
}

async function buildFromPlans(statusFilter) {
    const plans = await queryPlans(statusFilter);
    if (!plans.length) {
        return null;
    }
    const payload = emptyPayload();
    const planIds = new Set();
    const accountIds = new Set();
    plans.forEach((plan) => {
        planIds.add(plan.Id);
        if (plan.AccountId) {
            accountIds.add(plan.AccountId);
        }
    });
    const [objectivesByPlan, stakeholderCountByAccount, affiliations] = await Promise.all([
        loadObjectives(planIds),
        loadStakeholderCounts(accountIds),
        loadStakeholderAffiliations(accountIds)
    ]);

    let activePlans = 0;
    let totalObjectives = 0;
    let completedObjectives = 0;
    let accountsWithStakeholders = 0;

    plans.forEach((plan) => {
        const objectives = objectivesByPlan.get(plan.Id) || [];
        const stakeholderCount = stakeholderCountByAccount.get(plan.AccountId) || 0;
        const completed = objectives.filter((objective) => isCompletedObjectiveStatus(objective.Status)).length;
        totalObjectives += objectives.length;
        completedObjectives += completed;
        if (isActivePlanStatus(plan.Status)) {
            activePlans += 1;
        }
        if (stakeholderCount > 0 && plan.AccountId) {
            accountsWithStakeholders += 1;
        }
        const accountName = plan.Account?.Name || '';
        payload.plans.push({
            planId: plan.Id,
            planName: plan.Name,
            accountId: plan.AccountId,
            accountName,
            status: plan.Status,
            startDate: plan.StartDate,
            endDate: plan.EndDate,
            objectiveCount: objectives.length,
            completedObjectiveCount: completed,
            stakeholderCount,
            stakeholderCovered: stakeholderCount > 0
        });
        objectives.forEach((objective) => {
            payload.objectives.push({
                objectiveId: objective.Id,
                objectiveName: objective.Name,
                status: objective.Status,
                planId: plan.Id,
                planName: plan.Name,
                accountName,
                startDate: objective.StartDate,
                endDate: objective.EndDate
            });
        });
    });

    payload.stakeholders = mapStakeholderRows(affiliations);
    payload.kpis.totalPlans = plans.length;
    payload.kpis.activePlans = activePlans;
    payload.kpis.totalObjectives = totalObjectives;
    payload.kpis.completedObjectives = completedObjectives;
    payload.kpis.objectiveCompletionRate = safeRate(completedObjectives, totalObjectives);
    payload.kpis.accountsWithStakeholders = accountsWithStakeholders;
    payload.kpis.stakeholderCoveragePercent = safeRate(accountsWithStakeholders, plans.length);
    payload.plans.sort((left, right) => String(left.accountName).localeCompare(String(right.accountName)));
    return payload;
}

async function buildFromAffiliations(statusFilter) {
    const payload = emptyPayload();
    const aggregates = await soql(
        'SELECT Primary_Account__c, COUNT(Id) total FROM Account_Affiliation__c ' +
            'WHERE Primary_Account__c != NULL AND Is_Active__c = TRUE ' +
            'GROUP BY Primary_Account__c ORDER BY COUNT(Id) DESC LIMIT 100'
    );
    if (!aggregates.length) {
        return payload;
    }
    const stakeholderCountByAccount = new Map();
    aggregates.forEach((row) => {
        stakeholderCountByAccount.set(row.Primary_Account__c, Number(row.total || 0));
    });
    const accounts = await soql(
        `SELECT Id, Name FROM Account WHERE Id IN (${idList(stakeholderCountByAccount.keys())})`
    );
    const accountsById = new Map(accounts.map((account) => [account.Id, account]));
    const visibleAccountIds = new Set();
    let activePlans = 0;
    let accountsWithStakeholders = 0;

    stakeholderCountByAccount.forEach((stakeholderCount, accountId) => {
        const derivedStatus = deriveAffiliationPlanStatus(stakeholderCount);
        if (statusFilter && derivedStatus !== statusFilter) {
            return;
        }
        const account = accountsById.get(accountId);
        if (!account) {
            return;
        }
        visibleAccountIds.add(accountId);
        if (stakeholderCount > 0) {
            accountsWithStakeholders += 1;
        }
        if (isActivePlanStatus(derivedStatus)) {
            activePlans += 1;
        }
        payload.plans.push({
            planId: accountId,
            planName: FALLBACK_PLAN_NAME,
            accountId,
            accountName: account.Name,
            status: derivedStatus,
            startDate: null,
            endDate: null,
            objectiveCount: 0,
            completedObjectiveCount: 0,
            stakeholderCount,
            stakeholderCovered: stakeholderCount > 0
        });
    });

    payload.stakeholders = mapStakeholderRows(await loadStakeholderAffiliations(visibleAccountIds));
    payload.kpis.totalPlans = payload.plans.length;
    payload.kpis.activePlans = activePlans;
    payload.kpis.accountsWithStakeholders = accountsWithStakeholders;
    payload.kpis.stakeholderCoveragePercent = safeRate(accountsWithStakeholders, payload.plans.length);
    payload.plans.sort((left, right) => String(left.accountName).localeCompare(String(right.accountName)));
    return payload;
}

export async function loadFilterOptions() {
    const planStatuses = [option(ALL, ALL)];
    try {
        const rows = await soql(
            'SELECT Status FROM AccountPlan WHERE Status != NULL GROUP BY Status ORDER BY Status LIMIT 50'
        );
        rows.forEach((row) => {
            if (row.Status) {
                planStatuses.push(option(row.Status, row.Status));
            }
        });
    } catch (_err) {
        /* Account plans may be unavailable; affiliation statuses are added below. */
    }
    if (planStatuses.length === 1) {
        planStatuses.push(option(STATUS_STRONG, STATUS_STRONG));
        planStatuses.push(option(STATUS_IN_PROGRESS, STATUS_IN_PROGRESS));
    }
    return { planStatuses };
}

export async function loadDashboard(params = {}) {
    const requested = params.planStatus || ALL;
    const statusFilter = !requested || requested === ALL ? null : requested;
    try {
        const fromPlans = await buildFromPlans(statusFilter);
        if (fromPlans) {
            return fromPlans;
        }
    } catch (_err) {
        /* Fall through to affiliation coverage. */
    }
    return buildFromAffiliations(statusFilter);
}
