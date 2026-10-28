import { plannerApiFetch } from './restHelper.js';
import { esc, apexError, currentUserId, API_VERSION } from './learningShared.js';

const TYPE_OBJECT = 'Employee_Expense__c';
const TYPE_FIELD = 'Type__c';
const READ = { bypassOfflineGate: true };

const FALLBACK_TYPES = [
    { label: 'Meal', value: 'Meal' },
    { label: 'Transportation', value: 'Transportation' },
    { label: 'Transport', value: 'Transport' },
    { label: 'Accommodation', value: 'Accommodation' },
    { label: 'Fuel', value: 'Fuel' },
    { label: 'Parking', value: 'Parking' },
    { label: 'Toll', value: 'Toll' },
    { label: 'Client Entertainment', value: 'Client Entertainment' },
    { label: 'Conference / Event', value: 'Conference_Event' },
    { label: 'Training', value: 'Training' },
    { label: 'Sample Expense', value: 'Sample Expense' },
    { label: 'Communication', value: 'Communication' },
    { label: 'Others', value: 'Others' }
];

let typeOptionsCache;

function isUnreachable(error) {
    const message = String(error?.message || error || '');
    return /no cached response|could not reach salesforce|^offline$/i.test(message);
}

export function requireUserId() {
    const userId = currentUserId();
    if (!userId) {
        throw apexError('Sign in again to manage expenses.');
    }
    return userId;
}

export async function loadTypeOptions() {
    if (typeOptionsCache) {
        return typeOptionsCache;
    }
    try {
        const describe = await plannerApiFetch(
            `/services/data/${API_VERSION}/sobjects/${TYPE_OBJECT}/describe`,
            READ
        );
        const field = (describe?.fields || []).find((entry) => entry.name === TYPE_FIELD);
        const options = (field?.picklistValues || [])
            .filter((entry) => entry.active !== false)
            .map((entry) => ({ label: entry.label, value: entry.value }));
        if (options.length) {
            typeOptionsCache = options;
            return typeOptionsCache;
        }
    } catch (error) {
        if (!isUnreachable(error)) {
            throw error;
        }
    }
    return FALLBACK_TYPES.map((entry) => ({ ...entry }));
}

export function typeLabel(typeValue, options) {
    const match = (options || []).find((entry) => entry.value === typeValue);
    if (match) {
        return match.label;
    }
    if (typeValue === 'Conference_Event') {
        return 'Conference / Event';
    }
    return typeValue || '';
}

export function mapExpense(row, options, managerName) {
    return {
        id: row.Id,
        name: row.Name,
        typeLabel: typeLabel(row.Type__c, options),
        typeValue: row.Type__c || null,
        description: row.Description__c || null,
        amount: row.Amount__c,
        expenseDate: row.Expense_Date__c,
        status: row.Status__c,
        managerName: managerName || row.Manager__r?.Name || null,
        rejectionReason: row.Rejection_Reason__c || null
    };
}

const EXPENSE_FIELDS =
    'Id, Name, Type__c, Description__c, Amount__c, Expense_Date__c, Status__c, Manager__c, Rejection_Reason__c, OwnerId, CreatedById';

async function expenseSoql(query) {
    const path = `/services/data/${API_VERSION}/query?q=${encodeURIComponent(query)}`;
    const result = await plannerApiFetch(path, READ);
    return result && Array.isArray(result.records) ? result.records : [];
}

async function managerNames(rows) {
    const ids = [...new Set(rows.map((row) => row.Manager__c).filter(Boolean))];
    if (!ids.length) {
        return {};
    }
    const users = await expenseSoql(
        `SELECT Id, Name FROM User WHERE Id IN (${ids.map((id) => `'${esc(id)}'`).join(',')})`
    );
    return Object.fromEntries(users.map((user) => [user.Id, user.Name]));
}

export async function queryMyExpenses(limitSize) {
    const userId = requireUserId();
    const safeLimit = !limitSize || limitSize < 1 ? 10 : Math.min(Number(limitSize), 200);
    const options = await loadTypeOptions();
    try {
        const rows = await expenseSoql(
            `SELECT ${EXPENSE_FIELDS} FROM Employee_Expense__c WHERE OwnerId = '${esc(userId)}' ORDER BY Expense_Date__c DESC, CreatedDate DESC LIMIT ${safeLimit}`
        );
        const names = await managerNames(rows);
        return rows.map((row) => mapExpense(row, options, names[row.Manager__c]));
    } catch (error) {
        if (isUnreachable(error)) {
            return [];
        }
        throw error;
    }
}

export async function queryExpenseDetail(expenseId) {
    const userId = requireUserId();
    if (!expenseId) {
        throw apexError('Expense Id is required.');
    }
    const options = await loadTypeOptions();
    const rows = await expenseSoql(
        `SELECT ${EXPENSE_FIELDS} FROM Employee_Expense__c WHERE Id = '${esc(expenseId)}' LIMIT 1`
    );
    const row = rows[0] || null;
    if (!row || row.OwnerId !== userId) {
        throw apexError('Expense not found or access denied.');
    }
    const names = await managerNames([row]);
    return mapExpense(row, options, names[row.Manager__c]);
}

async function attachInvoices(recordId, invoiceFiles) {
    if (!recordId || !Array.isArray(invoiceFiles) || !invoiceFiles.length) {
        return false;
    }
    let failed = false;
    for (const file of invoiceFiles) {
        const name = String(file?.name || '').trim();
        const base64 = String(file?.base64 || '').trim();
        if (!name || !base64) {
            continue;
        }
        try {
            await plannerApiFetch(`/services/data/${API_VERSION}/sobjects/ContentVersion`, {
                method: 'POST',
                body: JSON.stringify({
                    Title: name.replace(/\.[^.]+$/, '') || 'Invoice',
                    PathOnClient: name,
                    VersionData: base64,
                    FirstPublishLocationId: recordId
                })
            });
        } catch (_error) {
            failed = true;
        }
    }
    return failed;
}

export async function createExpense({ typeValue, amount, expenseDate, description, invoiceFiles }) {
    const userId = requireUserId();
    const options = await loadTypeOptions();
    if (!typeValue || !options.some((entry) => entry.value === typeValue)) {
        throw apexError('Select a valid expense type.');
    }
    if (amount == null || Number(amount) <= 0) {
        throw apexError('Enter an amount greater than zero.');
    }
    if (!expenseDate) {
        throw apexError('Expense date is required.');
    }
    const users = await expenseSoql(`SELECT Id, ManagerId FROM User WHERE Id = '${esc(userId)}' LIMIT 1`);
    const user = users[0] || null;
    if (!user?.ManagerId) {
        throw apexError(
            'Your manager is not set on your user profile. Ask your admin to assign a manager before submitting expenses.'
        );
    }
    let created;
    try {
        created = await plannerApiFetch(`/services/data/${API_VERSION}/sobjects/Employee_Expense__c`, {
            method: 'POST',
            body: JSON.stringify({
                Type__c: typeValue,
                Amount__c: Number(amount),
                Expense_Date__c: expenseDate,
                Description__c: description || null,
                Manager__c: user.ManagerId,
                Status__c: 'Pending'
            })
        });
    } catch (error) {
        throw apexError(error?.body?.message || error?.message || 'Unable to create the expense.');
    }
    if (!created?.id) {
        throw apexError('Unable to create the expense.');
    }
    try {
        await plannerApiFetch(`/services/data/${API_VERSION}/sobjects/Employee_Expense__Share`, {
            method: 'POST',
            body: JSON.stringify({
                ParentId: created.id,
                UserOrGroupId: user.ManagerId,
                AccessLevel: 'Edit',
                RowCause: 'Manual'
            })
        });
    } catch (_shareError) {
        // Sharing is best-effort. The Salesforce approval path still shares when the record is created in the org.
    }
    const detail = await queryExpenseDetail(created.id);
    detail.invoiceUploadFailed = await attachInvoices(created.id, invoiceFiles);
    return detail;
}

const OPEN_STATUSES = new Set(['Pending', 'Submitted', 'Rejected']);

async function loadOwnedExpense(expenseId) {
    const userId = requireUserId();
    if (!expenseId) {
        throw apexError('Expense Id is required.');
    }
    const matches = await expenseSoql(
        `SELECT Id, Status__c, OwnerId FROM Employee_Expense__c WHERE Id = '${esc(expenseId)}' LIMIT 1`
    );
    const row = matches[0] || null;
    if (!row || row.OwnerId !== userId) {
        throw apexError('Expense not found or access denied.');
    }
    return row;
}

export async function updateMyExpenseRecord({ expenseId, typeValue, amount, expenseDate, description, invoiceFiles }) {
    const options = await loadTypeOptions();
    if (!typeValue || !options.some((entry) => entry.value === typeValue)) {
        throw apexError('Select a valid expense type.');
    }
    if (amount == null || Number(amount) <= 0) {
        throw apexError('Enter an amount greater than zero.');
    }
    if (!expenseDate) {
        throw apexError('Expense date is required.');
    }
    const row = await loadOwnedExpense(expenseId);
    if (row.Status__c === 'Approved') {
        throw apexError('Approved expenses cannot be changed.');
    }
    const fields = {
        Type__c: typeValue,
        Amount__c: Number(amount),
        Expense_Date__c: expenseDate,
        Description__c: description || null
    };
    if (row.Status__c === 'Rejected') {
        fields.Status__c = 'Pending';
        fields.Rejection_Reason__c = null;
    }
    if (!OPEN_STATUSES.has(row.Status__c) && row.Status__c !== 'Rejected') {
        throw apexError('This expense can no longer be changed.');
    }
    try {
        await plannerApiFetch(`/services/data/${API_VERSION}/sobjects/Employee_Expense__c/${expenseId}`, {
            method: 'PATCH',
            body: JSON.stringify(fields)
        });
    } catch (error) {
        throw apexError(error?.body?.message || error?.message || 'Unable to update the expense.');
    }
    const detail = await queryExpenseDetail(expenseId);
    detail.invoiceUploadFailed = await attachInvoices(expenseId, invoiceFiles);
    return detail;
}

export async function deleteMyExpenseRecord(expenseId) {
    const row = await loadOwnedExpense(expenseId);
    if (row.Status__c === 'Approved') {
        throw apexError('Approved expenses cannot be deleted.');
    }
    if (!OPEN_STATUSES.has(row.Status__c)) {
        throw apexError('This expense can no longer be deleted.');
    }
    try {
        await plannerApiFetch(`/services/data/${API_VERSION}/sobjects/Employee_Expense__c/${expenseId}`, {
            method: 'DELETE'
        });
    } catch (error) {
        throw apexError(error?.body?.message || error?.message || 'Unable to delete the expense.');
    }
}

const PARENT_CHAIN = [
    'Territory2.ParentTerritory2Id',
    'Territory2.ParentTerritory2.ParentTerritory2Id',
    'Territory2.ParentTerritory2.ParentTerritory2.ParentTerritory2Id',
    'Territory2.ParentTerritory2.ParentTerritory2.ParentTerritory2.ParentTerritory2Id',
    'Territory2.ParentTerritory2.ParentTerritory2.ParentTerritory2.ParentTerritory2.ParentTerritory2Id'
].join(', ');

function ancestorIds(row) {
    const territory = row?.Territory2;
    const ids = [];
    let node = territory;
    for (let depth = 0; depth < 5 && node; depth += 1) {
        if (node.ParentTerritory2Id) {
            ids.push(node.ParentTerritory2Id);
        }
        if (depth === 4) {
            break;
        }
        node = node.ParentTerritory2;
    }
    return ids;
}

async function subordinateUserIds(userId) {
    const assignments = await expenseSoql(
        `SELECT UserId, Territory2Id, ${PARENT_CHAIN} FROM UserTerritory2Association WHERE Territory2Id != null`
    );
    const mine = new Set(
        assignments.filter((row) => row.UserId === userId).map((row) => row.Territory2Id).filter(Boolean)
    );
    if (!mine.size) {
        return [];
    }
    const people = new Set();
    assignments.forEach((row) => {
        if (!row.UserId || row.UserId === userId) {
            return;
        }
        if (ancestorIds(row).some((id) => mine.has(id))) {
            people.add(row.UserId);
        }
    });
    return [...people];
}

async function teamMemberIds(userId) {
    const ids = new Set(await subordinateUserIds(userId));
    const reports = await expenseSoql(
        `SELECT Id FROM User WHERE ManagerId = '${esc(userId)}' AND Id != '${esc(userId)}'`
    );
    reports.forEach((row) => {
        if (row.Id) {
            ids.add(row.Id);
        }
    });
    ids.delete(userId);
    return [...ids];
}

function canActOnExpense(row, userId, subordinates) {
    if (!row || !row.OwnerId || row.OwnerId === userId) {
        return false;
    }
    return row.Manager__c === userId || subordinates.has(row.OwnerId);
}

export async function queryTeamExpenses() {
    const userId = requireUserId();
    const options = await loadTypeOptions();
    let subordinates = [];
    try {
        subordinates = await teamMemberIds(userId);
    } catch (error) {
        if (!isUnreachable(error)) {
            throw error;
        }
    }
    const subordinateClause = subordinates.length
        ? ` OR OwnerId IN (${subordinates.map((id) => `'${esc(id)}'`).join(',')})`
        : '';
    let rows;
    try {
        rows = await expenseSoql(
            `SELECT Id, Name, Type__c, Amount__c, Expense_Date__c, Description__c, Status__c, Rejection_Reason__c, OwnerId, Owner.Name, Manager__c FROM Employee_Expense__c WHERE OwnerId != '${esc(userId)}' AND (Manager__c = '${esc(userId)}'${subordinateClause}) ORDER BY Expense_Date__c DESC, CreatedDate DESC LIMIT 200`
        );
    } catch (error) {
        if (isUnreachable(error)) {
            return [];
        }
        throw error;
    }
    const subordinateSet = new Set(subordinates);
    return rows
        .filter((row) => canActOnExpense(row, userId, subordinateSet) || row.Manager__c === userId)
        .map((row) => ({
            expenseId: row.Id,
            expenseName: row.Name,
            repName: row.Owner?.Name || '',
            typeLabel: typeLabel(row.Type__c, options),
            amount: row.Amount__c,
            expenseDate: row.Expense_Date__c,
            description: row.Description__c || null,
            status: row.Status__c,
            rejectionReason: row.Rejection_Reason__c || null,
            canAct:
                (row.Status__c === 'Pending' || row.Status__c === 'Submitted') &&
                canActOnExpense(row, userId, subordinateSet)
        }));
}

export async function queryPendingApprovals() {
    const userId = requireUserId();
    const options = await loadTypeOptions();
    let subordinates = [];
    try {
        subordinates = await teamMemberIds(userId);
    } catch (error) {
        if (!isUnreachable(error)) {
            throw error;
        }
    }
    const subordinateClause = subordinates.length
        ? ` OR OwnerId IN (${subordinates.map((id) => `'${esc(id)}'`).join(',')})`
        : '';
    let rows;
    try {
        rows = await expenseSoql(
            `SELECT Id, Name, Type__c, Amount__c, Expense_Date__c, Description__c, Status__c, OwnerId, Owner.Name, Manager__c FROM Employee_Expense__c WHERE Status__c IN ('Pending','Submitted') AND (OwnerId = '${esc(userId)}' OR Manager__c = '${esc(userId)}'${subordinateClause}) ORDER BY Expense_Date__c DESC LIMIT 200`
        );
    } catch (error) {
        if (isUnreachable(error)) {
            return [];
        }
        throw error;
    }
    const subordinateSet = new Set(subordinates);
    return rows
        .filter((row) => row.OwnerId === userId || canActOnExpense(row, userId, subordinateSet))
        .map((row) => ({
            expenseId: row.Id,
            expenseName: row.Name,
            repName: row.Owner?.Name || '',
            typeLabel: typeLabel(row.Type__c, options),
            amount: row.Amount__c,
            expenseDate: row.Expense_Date__c,
            description: row.Description__c || null,
            status: row.Status__c,
            canAct: canActOnExpense(row, userId, subordinateSet)
        }));
}

async function updateDecision(expenseId, fields) {
    const userId = requireUserId();
    if (!expenseId) {
        throw apexError('Expense Id is required.');
    }
    const matches = await expenseSoql(
        `SELECT Id, Status__c, OwnerId, Manager__c FROM Employee_Expense__c WHERE Id = '${esc(expenseId)}' LIMIT 1`
    );
    const row = matches[0] || null;
    if (!row) {
        throw apexError('Expense not found.');
    }
    if (row.OwnerId === userId) {
        throw apexError('You can view your own expense, but only your manager can approve or reject it.');
    }
    const subordinates = new Set(await teamMemberIds(userId));
    if (!canActOnExpense(row, userId, subordinates)) {
        throw apexError("Only the employee's manager can approve or reject.");
    }
    if (row.Status__c !== 'Pending' && row.Status__c !== 'Submitted') {
        throw apexError('Only pending expenses can be updated.');
    }
    try {
        await plannerApiFetch(`/services/data/${API_VERSION}/sobjects/Employee_Expense__c/${expenseId}`, {
            method: 'PATCH',
            body: JSON.stringify(fields)
        });
    } catch (error) {
        throw apexError(error?.body?.message || error?.message || 'Unable to update the expense.');
    }
}

export function approveExpenseRecord(expenseId) {
    return updateDecision(expenseId, { Status__c: 'Approved' });
}

function clockLabel(value) {
    const match = String(value || '').match(/T(\d{2}:\d{2})/);
    return match ? match[1] : '';
}

function nextIsoDay(day) {
    const next = new Date(`${day}T00:00:00Z`);
    next.setUTCDate(next.getUTCDate() + 1);
    return next.toISOString().slice(0, 10);
}

async function safeSoql(query) {
    try {
        return await expenseSoql(query);
    } catch (_error) {
        return [];
    }
}

export async function queryExpenseFormContext(expenseDate) {
    const userId = requireUserId();
    const day = String(expenseDate || '').slice(0, 10);
    const stops = [];
    if (/^\d{4}-\d{2}-\d{2}$/.test(day)) {
        const visits = await safeSoql(
            'SELECT Id, Name, Status__c, Start_Date__c, Account__r.Name, Account__r.BillingCity, ' +
                'Account__r.BillingLatitude, Account__r.BillingLongitude ' +
                `FROM Visit__c WHERE Assigned_To__c = '${esc(userId)}' AND Visit_Date__c = ${day} ` +
                'ORDER BY Start_Date__c ASC NULLS LAST LIMIT 40'
        );
        visits.forEach((visit) => {
            const account = visit.Account__r || {};
            stops.push({
                id: visit.Id,
                kind: 'Visit',
                title: account.Name || visit.Name || 'Visit',
                detail: [clockLabel(visit.Start_Date__c), account.BillingCity, visit.Status__c].filter(Boolean).join(' · '),
                latitude: account.BillingLatitude || null,
                longitude: account.BillingLongitude || null
            });
        });
        const nextDay = nextIsoDay(day);
        const timeOff = await safeSoql(
            'SELECT Id, Type__c, Stage__c, Start_Date_Time__c FROM Time_Off_Request__c ' +
                `WHERE OwnerId = '${esc(userId)}' AND Start_Date_Time__c >= ${day}T00:00:00Z ` +
                `AND Start_Date_Time__c < ${nextDay}T00:00:00Z LIMIT 20`
        );
        timeOff.forEach((row) => {
            stops.push({
                id: row.Id,
                kind: 'Time off',
                title: row.Type__c || 'Time off',
                detail: row.Stage__c || '',
                latitude: null,
                longitude: null
            });
        });
    }

    const attendees = [];
    const seen = new Set();
    const mine = await safeSoql(
        `SELECT Territory2Id FROM UserTerritory2Association WHERE UserId = '${esc(userId)}' AND Territory2Id != null LIMIT 50`
    );
    const territoryIds = mine.map((row) => row.Territory2Id).filter(Boolean);
    if (territoryIds.length) {
        const children = await safeSoql(
            `SELECT Id FROM Territory2 WHERE ParentTerritory2Id IN (${territoryIds.map((id) => `'${esc(id)}'`).join(',')}) LIMIT 100`
        );
        const allIds = [...new Set([...territoryIds, ...children.map((row) => row.Id).filter(Boolean)])];
        const members = await safeSoql(
            'SELECT UserId, User.Name, User.Title, Territory2.Name FROM UserTerritory2Association ' +
                `WHERE Territory2Id IN (${allIds.map((id) => `'${esc(id)}'`).join(',')}) AND User.IsActive = true ` +
                'ORDER BY User.Name LIMIT 200'
        );
        members.forEach((row) => {
            if (!row.UserId || seen.has(row.UserId)) {
                return;
            }
            seen.add(row.UserId);
            attendees.push({
                id: row.UserId,
                name: row.User?.Name || '',
                detail: [row.User?.Title, row.Territory2?.Name].filter(Boolean).join(' · ')
            });
        });
    }
    if (!attendees.length) {
        const me = await safeSoql(`SELECT ManagerId FROM User WHERE Id = '${esc(userId)}' LIMIT 1`);
        const managerId = me[0]?.ManagerId;
        const people = await safeSoql(
            'SELECT Id, Name, Title FROM User WHERE IsActive = true AND (' +
                `Id = '${esc(userId)}'` +
                (managerId ? ` OR Id = '${esc(managerId)}'` : '') +
                ` OR ManagerId = '${esc(userId)}') ORDER BY Name LIMIT 80`
        );
        people.forEach((person) => {
            attendees.push({
                id: person.Id,
                name: person.Name,
                detail: person.Title || ''
            });
        });
    }
    return { stops, attendees };
}

export function rejectExpenseRecord(expenseId, rejectionReason) {
    const reason = String(rejectionReason || '').trim();
    if (!reason) {
        throw apexError('Rejection reason is required.');
    }
    return updateDecision(expenseId, {
        Status__c: 'Rejected',
        Rejection_Reason__c: reason
    });
}
