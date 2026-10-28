import { makeDualApex } from './_wireAdapter.js';
import { currentUserId, esc, soql } from './learningShared.js';

const MANAGER_ROLES = new Set([
    'District Manager',
    'Region Manager',
    'Line Manager',
    'NSM',
    'National Sales Manager',
    'Area Manager',
    'Business Unit Manager',
    'Brand Manager',
    'Trainer'
]);

function sameId(left, right) {
    return String(left || '').slice(0, 15) === String(right || '').slice(0, 15);
}

async function subordinateContext(userId) {
    const assignments = await soql(
        'SELECT Territory2Id, RoleInTerritory2 FROM UserTerritory2Association ' +
            `WHERE UserId = '${esc(userId)}' AND RoleInTerritory2 != null`
    );
    const roots = [
        ...new Set(
            assignments
                .filter((row) => MANAGER_ROLES.has(row.RoleInTerritory2))
                .map((row) => row.Territory2Id)
                .filter(Boolean)
        )
    ];
    if (!roots.length) {
        return { isManager: false, userIds: [], territoryNames: new Map() };
    }
    const tree = new Set(roots);
    let frontier = [...roots];
    for (let depth = 0; depth < 8 && frontier.length; depth += 1) {
        const children = await soql(
            `SELECT Id FROM Territory2 WHERE ParentTerritory2Id IN (${frontier
                .map((id) => `'${esc(id)}'`)
                .join(',')})`
        );
        frontier = [];
        children.forEach((child) => {
            if (child.Id && !tree.has(child.Id)) {
                tree.add(child.Id);
                frontier.push(child.Id);
            }
        });
    }
    const members = await soql(
        'SELECT UserId, User.Name, Territory2.Name FROM UserTerritory2Association ' +
            `WHERE Territory2Id IN (${[...tree].map((id) => `'${esc(id)}'`).join(',')}) ` +
            'AND User.IsActive = true'
    );
    const territoryNames = new Map();
    const userIds = [];
    members.forEach((row) => {
        if (!row.UserId || sameId(row.UserId, userId)) {
            return;
        }
        if (!territoryNames.has(row.UserId)) {
            territoryNames.set(row.UserId, []);
            userIds.push(row.UserId);
        }
        const name = row.Territory2 && row.Territory2.Name;
        const names = territoryNames.get(row.UserId);
        if (name && !names.includes(name)) {
            names.push(name);
        }
    });
    return { isManager: true, userIds, territoryNames };
}

export async function loadTeamLearning() {
    const userId = currentUserId();
    if (!userId) {
        return { isManager: false, rows: [] };
    }
    const context = await subordinateContext(userId);
    if (!context.isManager || !context.userIds.length) {
        return { isManager: context.isManager, rows: [] };
    }
    const rows = await soql(
        'SELECT Id, Status__c, Progress__c, Learner__c, Learner__r.Name, Material__r.Title__c, ' +
            'Material__r.Effective_End_Date__c ' +
            'FROM Learning_Material_Instance__c ' +
            `WHERE Learner__c IN (${context.userIds.map((id) => `'${esc(id)}'`).join(',')}) ` +
            "AND Material__r.Material_Type__c = 'Course' " +
            'ORDER BY Learner__r.Name, Material__r.Title__c'
    );
    return {
        isManager: true,
        rows: rows
            .filter((row) => !sameId(row.Learner__c, userId))
            .map((row) => ({
                instanceId: row.Id,
                learnerId: row.Learner__c,
                learnerName: row.Learner__r && row.Learner__r.Name,
                territoryName: (context.territoryNames.get(row.Learner__c) || []).join(', '),
                title: row.Material__r && row.Material__r.Title__c,
                status: row.Status__c || 'Not Started',
                progress: Number(row.Progress__c) || 0,
                effectiveEndDate: row.Material__r && row.Material__r.Effective_End_Date__c
            }))
    };
}

export default makeDualApex(loadTeamLearning);
