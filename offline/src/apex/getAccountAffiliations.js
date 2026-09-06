import { makeDualApex } from './_wireAdapter.js';
import { plannerApiFetch } from './restHelper.js';

const API_VERSION = 'v62.0';

async function soql(query) {
    const path = `/services/data/${API_VERSION}/query?q=${encodeURIComponent(query)}`;
    const result = await plannerApiFetch(path);
    return result && Array.isArray(result.records) ? result.records : [];
}

function esc(value) {
    return String(value || '').replace(/'/g, "\\'");
}

function emptyGraph(offset = 0, pageSize = 50) {
    return {
        nodes: [],
        edges: [],
        totalCount: 0,
        offset,
        pageSize,
        recordsReturned: 0,
        hasMore: false
    };
}

function parseFilters(filtersJson, accountId) {
    const filters = {
        relationType: 'All',
        showInactive: false,
        showOutsideTerritory: true,
        direction: 'All',
        role: 'All',
        strength: 'All',
        accountIds: accountId ? [String(accountId)] : []
    };
    if (!filtersJson) return filters;
    try {
        const parsed = typeof filtersJson === 'string' ? JSON.parse(filtersJson) : filtersJson;
        if (parsed && typeof parsed === 'object') {
            Object.assign(filters, parsed);
            if (!Array.isArray(filters.accountIds) || !filters.accountIds.length) {
                filters.accountIds = accountId ? [String(accountId)] : [];
            }
        }
    } catch (_err) {
        /* ignore */
    }
    return filters;
}

async function loadAffiliations(config) {
    const accountId = config && (config.accountId || config.Id);
    if (!accountId) {
        return emptyGraph();
    }
    const filters = parseFilters(config.filtersJson, accountId);
    const offset = Math.max(0, Number(config.offset) || 0);
    const pageSize = Math.min(100, Math.max(1, Number(config.pageSize) || 50));
    const seedIds = (filters.accountIds || []).map(String).filter(Boolean);
    if (!seedIds.length) {
        return emptyGraph(offset, pageSize);
    }

    const inList = seedIds.map((id) => `'${esc(id)}'`).join(',');
    let where =
        `(Primary_Account__c IN (${inList}) OR Related_Account__c IN (${inList}))`;
    if (!filters.showInactive) where += ' AND Is_Active__c = true';
    if (!filters.showOutsideTerritory) where += ' AND Outside_Territory__c = false';
    if (filters.relationType && filters.relationType !== 'All') {
        where += ` AND Affiliation_Type__c = '${esc(filters.relationType)}'`;
    }
    if (filters.role && filters.role !== 'All') {
        where += ` AND Role__c = '${esc(filters.role)}'`;
    }
    if (filters.strength && filters.strength !== 'All') {
        where += ` AND Strength__c = '${esc(filters.strength)}'`;
    }

    let totalCount = 0;
    try {
        const countRows = await soql(
            `SELECT COUNT() FROM Account_Affiliation__c WHERE ${where}`
        );
        // COUNT() responses come back as { totalSize } via REST, but soql helper returns records.
        // Fall back to querying and using length if needed.
        totalCount = Array.isArray(countRows) ? countRows.length : 0;
    } catch (_err) {
        totalCount = 0;
    }

    let rows = [];
    try {
        const countResult = await plannerApiFetch(
            `/services/data/${API_VERSION}/query?q=${encodeURIComponent(
                `SELECT COUNT() FROM Account_Affiliation__c WHERE ${where}`
            )}`
        );
        if (countResult && typeof countResult.totalSize === 'number') {
            totalCount = countResult.totalSize;
        }
        rows = await soql(
            'SELECT Id, Primary_Account__c, Related_Account__c, Affiliation_Type__c,' +
                ' Description__c, Is_Active__c, Outside_Territory__c, Role__c, Strength__c,' +
                ' Primary_Account__r.Name, Primary_Account__r.RecordType.Name,' +
                ' Related_Account__r.Name, Related_Account__r.RecordType.Name' +
                ' FROM Account_Affiliation__c' +
                ` WHERE ${where}` +
                ' ORDER BY Primary_Account__r.Name, Id' +
                ` LIMIT ${pageSize} OFFSET ${offset}`
        );
    } catch (err) {
        console.warn('[Affiliations] query failed', err);
        return emptyGraph(offset, pageSize);
    }

    const nodeMap = new Map();
    const edges = [];
    const edgeKeys = new Set();

    const addNode = (id, name, accountType, isActive) => {
        if (!id || nodeMap.has(id)) return;
        nodeMap.set(id, {
            id: String(id),
            name: name || String(id),
            accountType: accountType || null,
            isActive: isActive !== false,
            hasMoreAffiliations: false
        });
    };

    // Seed account
    try {
        const seeds = await soql(
            `SELECT Id, Name, RecordType.Name FROM Account WHERE Id IN (${inList})`
        );
        seeds.forEach((acct) => {
            addNode(acct.Id, acct.Name, acct.RecordType?.Name, true);
        });
    } catch (_err) {
        seedIds.forEach((id) => addNode(id, id, null, true));
    }

    rows.forEach((aff) => {
        const primary = aff.Primary_Account__c;
        const related = aff.Related_Account__c;
        addNode(
            primary,
            aff.Primary_Account__r?.Name,
            aff.Primary_Account__r?.RecordType?.Name,
            aff.Is_Active__c
        );
        addNode(
            related,
            aff.Related_Account__r?.Name,
            aff.Related_Account__r?.RecordType?.Name,
            aff.Is_Active__c
        );
        const fromId = filters.direction === 'Related→Primary' ? related : primary;
        const toId = filters.direction === 'Related→Primary' ? primary : related;
        const edgeKey = `${fromId}-${toId}-${aff.Id}`;
        if (!edgeKeys.has(edgeKey)) {
            edges.push({
                fromId: String(fromId),
                toId: String(toId),
                relationType: aff.Affiliation_Type__c,
                description: aff.Description__c,
                affiliationId: aff.Id
            });
            edgeKeys.add(edgeKey);
        }
    });

    const hasMore = offset + rows.length < totalCount;
    const nodes = Array.from(nodeMap.values());
    nodes.forEach((node) => {
        if (seedIds.includes(node.id)) node.hasMoreAffiliations = hasMore;
    });

    return {
        nodes,
        edges,
        totalCount,
        offset,
        pageSize,
        recordsReturned: rows.length,
        hasMore
    };
}

export default makeDualApex(loadAffiliations);
