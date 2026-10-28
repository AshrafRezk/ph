import { makeDualApex } from './_wireAdapter.js';
import { isOffline, plannerApiFetch } from './restHelper.js';
import {
    getAllPlannerCacheRows,
    getAllTodayPlanRows,
    getVisitPayload,
    putVisitPayload
} from 'c/clmOfflineStore';

// Offline stand-in for VisitCallReportController.getCallReportPayload (Aura-only).
// Builds the visit header from a read-only SOQL query so the Details section
// renders live online; offline the shell falls back to its IndexedDB cache.
// Related collections (attendees/products/samples) are loaded from SOQL so
// Dispense can scope sample/brand-reminder rows to the selected details.
const API_VERSION = 'v62.0';
const TEAM_MANAGER_ROLES = new Set(['District Manager', 'Region Manager']);
const MANAGER_ROLES = new Set(['District Manager', 'Region Manager', 'Line Manager', 'NSM']);
const SCHEDULE_EDITOR_ROLES = new Set([
    'District Manager',
    'Region Manager',
    'Line Manager',
    'NSM',
    'Area Manager',
    'National Sales Manager',
    'Business Unit Manager',
    'SFE',
    'Sales Force Excellence'
]);
const SERVICE_REQUEST_ROLES = new Set([
    'District Manager',
    'Region Manager',
    'Line Manager',
    'NSM',
    'Area Manager',
    'National Sales Manager',
    'Business Unit Manager'
]);
const TERRITORY_CACHE_KEY = 'zeta.pwa.sfTerritoryContext';

// Mirrors TerritoryManagementController.mapAssignmentRole (Apex) so the PWA derives
// the same assignment role as VisitActorAccess: User.Title first, then username suffix.
const TITLE_ROLE_ALIASES = {
    'business unit manager': 'Business Unit Manager',
    bum: 'Business Unit Manager',
    'national sales manager': 'National Sales Manager',
    nsm: 'National Sales Manager',
    'area manager': 'Area Manager',
    am: 'Area Manager',
    'brand manager': 'Brand Manager',
    brand: 'Brand Manager',
    'district manager': 'District Manager',
    dm: 'District Manager',
    trainer: 'Trainer',
    'field trainer': 'Trainer',
    'sales force excellence': 'SFE',
    sfe: 'SFE',
    'medical rep': 'Medical Rep',
    'medical representative': 'Medical Rep',
    mr: 'Medical Rep'
};
const USERNAME_ROLE_SUFFIXES = [
    ['.bum@', 'Business Unit Manager'],
    ['.nsm@', 'National Sales Manager'],
    ['.am@', 'Area Manager'],
    ['.brand@', 'Brand Manager'],
    ['.trainer@', 'Trainer'],
    ['.dm@', 'District Manager'],
    ['.mr@', 'Medical Rep']
];

export function mapAssignmentRole(title, username) {
    const normalizedTitle = String(title || '').trim();
    if (normalizedTitle) {
        return TITLE_ROLE_ALIASES[normalizedTitle.toLowerCase()] || normalizedTitle;
    }
    const name = String(username || '').toLowerCase();
    if (name === 'admin@pharma.eg') {
        return 'SFE';
    }
    for (const [suffix, role] of USERNAME_ROLE_SUFFIXES) {
        if (
            name.endsWith(`${suffix}pharma.demo`) ||
            name.endsWith(`${suffix}pharma.eg`)
        ) {
            return role;
        }
    }
    return 'Medical Rep';
}

function esc(value) {
    return String(value || '').replace(/\\/g, '\\\\').replace(/'/g, "\\'");
}

function currentUserId() {
    try {
        return String(
            (typeof globalThis !== 'undefined' && globalThis.PLANNER_USER_ID) ||
                localStorage.getItem('zeta.pwa.sfUserId') ||
                ''
        ).trim();
    } catch (_err) {
        return '';
    }
}

function readTerritoryCache() {
    try {
        const raw = localStorage.getItem(TERRITORY_CACHE_KEY);
        return raw ? JSON.parse(raw) : null;
    } catch (_err) {
        return null;
    }
}

function isRepLevel(level, typeValue, externalId) {
    const normalizedLevel = String(level || '').trim().toLowerCase();
    if (
        normalizedLevel === 'position' ||
        normalizedLevel === 'mr' ||
        normalizedLevel === 'medical rep'
    ) {
        return true;
    }
    const type = String(typeValue || '').trim();
    if (type === 'Position' || type === 'MR') {
        return true;
    }
    const ext = String(externalId || '');
    return ext.includes('_MR_') || ext.startsWith('TERR_POS_');
}

async function queryTerritories(ids) {
    const unique = [...new Set((ids || []).filter(Boolean))];
    if (!unique.length) {
        return [];
    }
    const idList = unique.map((id) => `'${esc(id)}'`).join(',');
    try {
        return await soqlMany(
            `SELECT Id, Name, External_ID__c, Territory_Type__c FROM Territory2 WHERE Id IN (${idList})`
        );
    } catch (_err) {
        return await soqlMany(
            `SELECT Id, Name, External_ID__c FROM Territory2 WHERE Id IN (${idList})`
        );
    }
}

function territoryTreeHasSubordinates(cache) {
    const walk = (nodes) =>
        (nodes || []).some(
            (node) =>
                node?.hasChildren === true ||
                (Array.isArray(node?.children) && node.children.length > 0) ||
                walk(node?.children)
        );
    return walk(cache?.tree);
}

async function assignedTerritoriesHaveChildren(territoryIds) {
    const unique = [...new Set((territoryIds || []).filter(Boolean))];
    if (!unique.length) {
        return false;
    }
    const idList = unique.map((id) => `'${esc(id)}'`).join(',');
    const children = await soqlMany(
        `SELECT Id FROM Territory2 WHERE ParentTerritory2Id IN (${idList}) LIMIT 1`
    ).catch(() => []);
    return children.length > 0;
}

async function resolveAlignedOnRepTerritory() {
    const cache = readTerritoryCache();
    if (territoryTreeHasSubordinates(cache)) {
        return false;
    }
    const userId = currentUserId();
    const assignments = userId
        ? await soqlMany(
              'SELECT RoleInTerritory2, Territory2Id FROM UserTerritory2Association ' +
                  `WHERE UserId = '${esc(userId)}'`
          ).catch(() => [])
        : [];
    if (assignments.some((row) => MANAGER_ROLES.has(row.RoleInTerritory2))) {
        return false;
    }
    if (await assignedTerritoriesHaveChildren(assignments.map((row) => row.Territory2Id))) {
        return false;
    }
    const assignedTerritories = await queryTerritories(assignments.map((row) => row.Territory2Id));
    const knownAssigned = assignedTerritories.filter(
        (row) => row.Territory_Type__c || row.External_ID__c
    );
    if (knownAssigned.length && !knownAssigned.every((row) => isRepLevel(null, row.Territory_Type__c, row.External_ID__c))) {
        return false;
    }
    if (assignments.length && !knownAssigned.length && !assignments.every((row) => row.RoleInTerritory2 === 'Medical Rep')) {
        return false;
    }

    if (cache && cache.usingAllAssigned === false && cache.selectedTerritoryId) {
        if (isRepLevel(cache.selectedLevel)) {
            return true;
        }
        const selected = (await queryTerritories([cache.selectedTerritoryId]))[0];
        if (selected && isRepLevel(null, selected.Territory_Type__c, selected.External_ID__c)) {
            return true;
        }
        if (selected && (selected.Territory_Type__c || selected.External_ID__c)) {
            return false;
        }
    }

    if (!assignments.length) {
        return false;
    }
    if (knownAssigned.length) {
        return knownAssigned.every((row) => isRepLevel(null, row.Territory_Type__c, row.External_ID__c));
    }
    return assignments.every((row) => row.RoleInTerritory2 === 'Medical Rep');
}

function formatDurationLabel(startDateTime, endDateTime) {
    if (!startDateTime || !endDateTime) {
        return null;
    }
    const minutes = Math.round((new Date(endDateTime) - new Date(startDateTime)) / 60000);
    if (!Number.isFinite(minutes) || minutes < 0) {
        return null;
    }
    if (minutes < 60) {
        return `${minutes} min`;
    }
    const hours = Math.floor(minutes / 60);
    const remainder = minutes % 60;
    return remainder === 0 ? `${hours} hr` : `${hours} hr ${remainder} min`;
}

async function resolveActorAccess() {
    const userId = currentUserId();
    if (!userId) {
        return { canEditSchedule: false, canViewServiceRequests: false };
    }
    const [user, assignments] = await Promise.all([
        soqlOne(
            `SELECT Profile.Name, Title, Username FROM User WHERE Id = '${esc(userId)}' LIMIT 1`
        ).catch(() => null),
        soqlMany(
            'SELECT RoleInTerritory2 FROM UserTerritory2Association ' +
                `WHERE UserId = '${esc(userId)}' AND RoleInTerritory2 != null`
        ).catch(() => [])
    ]);
    const isAdmin = user?.Profile?.Name === 'System Administrator';
    const roles = new Set(assignments.map((row) => row.RoleInTerritory2).filter(Boolean));
    // Server parity (VisitActorAccess.matchesRole): the User.Title-derived role counts
    // alongside territory-assignment roles.
    roles.add(mapAssignmentRole(user?.Title, user?.Username));
    const canEditSchedule =
        isAdmin || [...roles].some((role) => SCHEDULE_EDITOR_ROLES.has(role));
    const canViewServiceRequests =
        isAdmin || [...roles].some((role) => SERVICE_REQUEST_ROLES.has(role));
    return { canEditSchedule, canViewServiceRequests };
}

async function loadMedicalInquiryCount(visitId) {
    const rows = await soqlMany(
        `SELECT Id FROM Case WHERE Visit__c = '${esc(visitId)}' LIMIT 50`
    ).catch(() => []);
    return rows.length;
}

async function attachHeroFlags(payload, visitId) {
    if (!payload) {
        return payload;
    }
    try {
        payload.alignedOnRepTerritory = await resolveAlignedOnRepTerritory();
        payload.hasSubordinateTerritories =
            payload.hasSubordinateTerritories === true ||
            territoryTreeHasSubordinates(readTerritoryCache());
        if (payload.hasSubordinateTerritories) {
            payload.alignedOnRepTerritory = false;
        }
    } catch (_err) {
        payload.alignedOnRepTerritory = payload.alignedOnRepTerritory === true;
    }
    if (typeof payload.medicalInquiryCount !== 'number' && visitId) {
        try {
            payload.medicalInquiryCount = await loadMedicalInquiryCount(visitId);
        } catch (_err) {
            payload.medicalInquiryCount = 0;
        }
    }
    if (payload.visit) {
        if (!payload.visit.durationLabel) {
            payload.visit.durationLabel = formatDurationLabel(
                payload.visit.startDateTime,
                payload.visit.endDateTime
            );
        }
        try {
            const access = await resolveActorAccess();
            payload.visit.canEditSchedule = access.canEditSchedule;
            payload.visit.canViewServiceRequests = access.canViewServiceRequests;
        } catch (_err) {
            payload.visit.canEditSchedule = payload.visit.canEditSchedule === true;
            payload.visit.canViewServiceRequests = payload.visit.canViewServiceRequests === true;
        }
    }
    return payload;
}

async function soqlOne(query) {
    const path = `/services/data/${API_VERSION}/query?q=${encodeURIComponent(query)}`;
    const result = await plannerApiFetch(path);
    const records = result && Array.isArray(result.records) ? result.records : [];
    return records.length ? records[0] : null;
}

async function soqlMany(query) {
    const path = `/services/data/${API_VERSION}/query?q=${encodeURIComponent(query)}`;
    const result = await plannerApiFetch(path);
    return result && Array.isArray(result.records) ? result.records : [];
}

function mapVisit(v, teamContext) {
    const status = v.Status__c || 'Draft';
    const acct = v.Account__r || {};
    const rt = acct.RecordType || null;
    const assigned = v.Assigned_To__r || {};
    const companion = v.Double_Visit_With__r || {};
    return {
        id: v.Id,
        visitId: v.Id,
        name: v.Name,
        status,
        visitType: v.Visit_Type__c,
        startDateTime: v.Start_Date__c,
        endDateTime: v.End_Date__c,
        visitObjective: v.Visit_Objective__c,
        visitNotes: v.Visit_Notes__c,
        clmPresentation: v.CLM_Presentation__c,
        nextVisitDate: v.Next_Visit_Date__c,
        cancellationReason: v.Cancellation_Reason__c,
        isLocked: status === 'Completed' || status === 'Cancelled',
        isDoubleVisit: v.Is_Double_Visit__c === true,
        doubleVisitWithId: v.Double_Visit_With__c || null,
        doubleVisitWithName: companion.Name || null,
        defaultDoubleVisitWithId: teamContext.defaultUserId || null,
        defaultDoubleVisitWithName: teamContext.defaultUserName || null,
        coachingEventId: v.Coaching_Event__c || null,
        accountId: v.Account__c,
        accountName: acct.Name || null,
        accountCity: acct.BillingCity || null,
        accountSpecialty: acct.Specialty_1__c || null,
        accountRecordTypeDeveloperName: rt ? rt.DeveloperName : null,
        accountRecordTypeName: rt ? rt.Name : null,
        assignedToId: v.Assigned_To__c || null,
        assignedToName: assigned.Name || null,
        durationLabel: formatDurationLabel(v.Start_Date__c, v.End_Date__c)
    };
}

async function loadAttendees(visitId) {
    const rows = await soqlMany(
        'SELECT Id, Account__c, Account__r.Name, Account__r.Specialty_1__c, ' +
        'Account__r.RecordType.DeveloperName, Account__r.RecordType.Name ' +
        `FROM Visit_Attendee__c WHERE Visit__c = '${visitId}' ORDER BY CreatedDate ASC`
    );
    return rows.map((r, index) => {
        const acct = r.Account__r || {};
        const rt = acct.RecordType || null;
        return {
            id: r.Id,
            accountId: r.Account__c,
            accountName: acct.Name || null,
            specialty: acct.Specialty_1__c || null,
            recordTypeDeveloperName: rt ? rt.DeveloperName : null,
            accountTypeLabel: rt ? rt.Name : null,
            role: 'Attendee',
            isPrimary: index === 0,
            displayOrder: index + 1
        };
    });
}

async function loadProductDetails(visitId) {
    const rows = await soqlMany(
        'SELECT Id, Product2__c, Product2__r.Name, Product2__r.Product_Image_URL__c, ' +
            'Product2__r.Product_Type__c, Product2__r.Parent_Product__c, Product2__r.Parent_Product__r.Name, ' +
            'Product2__r.Primary_Brand__c, Display_Order__c, Detail_Type__c, Notes__c ' +
            `FROM Visit_Product_Detail__c WHERE Visit__c = '${esc(visitId)}' ` +
            'ORDER BY Display_Order__c ASC, CreatedDate ASC'
    );
    const details = rows.map((r) => {
        const product = r.Product2__r || {};
        const parent = product.Parent_Product__r || {};
        return {
            id: r.Id,
            productId: r.Product2__c,
            productName: product.Name || null,
            imageUrl: product.Product_Image_URL__c || null,
            productType: product.Product_Type__c || null,
            parentProductId: product.Parent_Product__c || null,
            brandName: parent.Name || product.Primary_Brand__c || product.Name || null,
            displayOrder: r.Display_Order__c,
            detailType: r.Detail_Type__c || 'Detail',
            notes: r.Notes__c || '',
            messages: []
        };
    });
    if (!details.length) {
        return details;
    }
    const detailIds = details.map((row) => row.id).filter(Boolean);
    const messages = await soqlMany(
        'SELECT Id, Visit_Product_Detail__c, Topic__c, Sentiment__c, Response__c ' +
            `FROM Visit_Product_Message__c WHERE Visit_Product_Detail__c IN (${quoteList(detailIds)}) ` +
            'ORDER BY CreatedDate ASC'
    ).catch(() => []);
    const byDetail = new Map(details.map((row) => [row.id, row]));
    messages.forEach((msg) => {
        const detail = byDetail.get(msg.Visit_Product_Detail__c);
        if (!detail) {
            return;
        }
        detail.messages.push({
            id: msg.Id,
            topic: msg.Topic__c,
            sentiment: msg.Sentiment__c,
            response: msg.Response__c
        });
    });
    return details;
}

async function loadSamples(visitId) {
    const rows = await soqlMany(
        'SELECT Id, Product2__c, Product2__r.Name, Product2__r.Product_Image_URL__c, ' +
            'Visit_Attendee__c, Visit_Attendee__r.Account__r.Name, Quantity__c, Lot_Number__c, Sample_Inventory__c ' +
            `FROM Visit_Sample__c WHERE Visit__c = '${esc(visitId)}' ORDER BY CreatedDate ASC`
    );
    return rows.map((r) => {
        const product = r.Product2__r || {};
        const attendee = r.Visit_Attendee__r || {};
        const account = attendee.Account__r || {};
        return {
            id: r.Id,
            productId: r.Product2__c,
            productName: product.Name || null,
            imageUrl: product.Product_Image_URL__c || null,
            visitAttendeeId: r.Visit_Attendee__c || null,
            attendeeName: account.Name || null,
            quantity: r.Quantity__c,
            lotNumber: r.Lot_Number__c || '',
            sampleInventoryId: r.Sample_Inventory__c || null
        };
    });
}

function quoteList(ids) {
    return ids.map((id) => `'${esc(id)}'`).join(',');
}

function emptyTeamContext() {
    return { defaultUserId: null, defaultUserName: null, members: [] };
}

function buildTeamMember(userId, name, role, territoryName, isManager, isDefault) {
    return {
        userId,
        name: name || null,
        role: role || null,
        territoryName: territoryName || null,
        isManager: isManager === true,
        isDefault: isDefault === true
    };
}

async function loadTeamCompanionContext(visit) {
    const context = emptyTeamContext();
    const assigneeId = visit.Assigned_To__c;
    const savedCompanionId = visit.Double_Visit_With__c;
    const assigned = visit.Assigned_To__r || {};
    const membersById = new Map();

    try {
        const seedRows = assigneeId
            ? await soqlMany(
                  'SELECT Territory2Id FROM UserTerritory2Association ' +
                      `WHERE UserId = '${assigneeId}'`
              )
            : [];
        const seedIds = seedRows.map((row) => row.Territory2Id).filter(Boolean);
        const ancestorChain = [];
        const seen = new Set();
        let currentId = seedIds[0] || null;
        let guard = 0;
        while (currentId && guard < 12) {
            guard += 1;
            if (seen.has(currentId)) {
                break;
            }
            seen.add(currentId);
            ancestorChain.push(currentId);
            const territory = await soqlOne(
                `SELECT ParentTerritory2Id FROM Territory2 WHERE Id = '${currentId}' LIMIT 1`
            );
            currentId = territory ? territory.ParentTerritory2Id : null;
        }

        const managerTerritoryId = ancestorChain.length > 1 ? ancestorChain[1] : ancestorChain[0];
        const teamTerritoryIds = new Set([...seedIds, ...ancestorChain]);
        if (managerTerritoryId) {
            const children = await soqlMany(
                'SELECT Id FROM Territory2 ' +
                    `WHERE ParentTerritory2Id = '${managerTerritoryId}'`
            );
            children.forEach((row) => {
                if (row.Id) {
                    teamTerritoryIds.add(row.Id);
                }
            });
            teamTerritoryIds.add(managerTerritoryId);
        }

        if (teamTerritoryIds.size) {
            const idList = [...teamTerritoryIds].map((id) => `'${id}'`).join(',');
            const assignments = await soqlMany(
                'SELECT UserId, User.Name, RoleInTerritory2, Territory2Id, Territory2.Name ' +
                    'FROM UserTerritory2Association ' +
                    `WHERE Territory2Id IN (${idList}) AND User.IsActive = true ` +
                    'ORDER BY RoleInTerritory2 ASC, User.Name ASC'
            );
            assignments.forEach((row) => {
                if (!row.UserId || row.UserId === assigneeId) {
                    return;
                }
                const isManager = TEAM_MANAGER_ROLES.has(row.RoleInTerritory2);
                const existing = membersById.get(row.UserId);
                if (!existing) {
                    membersById.set(
                        row.UserId,
                        buildTeamMember(
                            row.UserId,
                            row.User ? row.User.Name : null,
                            row.RoleInTerritory2,
                            row.Territory2 ? row.Territory2.Name : null,
                            isManager,
                            false
                        )
                    );
                } else if (isManager && !existing.isManager) {
                    existing.role = row.RoleInTerritory2;
                    existing.territoryName = row.Territory2 ? row.Territory2.Name : existing.territoryName;
                    existing.isManager = true;
                }
            });
        }

        for (const territoryId of ancestorChain) {
            const managerRow = await soqlOne(
                'SELECT UserId, User.Name FROM UserTerritory2Association ' +
                    `WHERE Territory2Id = '${territoryId}' ` +
                    "AND RoleInTerritory2 IN ('District Manager','Region Manager') " +
                    `${assigneeId ? `AND UserId != '${assigneeId}' ` : ''}` +
                    'AND User.IsActive = true ' +
                    'ORDER BY RoleInTerritory2 ASC, User.Name ASC LIMIT 1'
            );
            if (managerRow && managerRow.UserId) {
                context.defaultUserId = managerRow.UserId;
                context.defaultUserName = managerRow.User ? managerRow.User.Name : null;
                break;
            }
        }
    } catch (_error) {
        // Territory association is often hidden from field reps over REST.
    }

    if (!context.defaultUserId && assigned.ManagerId) {
        context.defaultUserId = assigned.ManagerId;
        context.defaultUserName = assigned.Manager ? assigned.Manager.Name : null;
    }

    if (context.defaultUserId && context.defaultUserId !== assigneeId && !membersById.has(context.defaultUserId)) {
        membersById.set(
            context.defaultUserId,
            buildTeamMember(
                context.defaultUserId,
                context.defaultUserName,
                'Manager',
                null,
                true,
                true
            )
        );
    }

    if (savedCompanionId && !membersById.has(savedCompanionId)) {
        const companion = visit.Double_Visit_With__r || {};
        membersById.set(
            savedCompanionId,
            buildTeamMember(savedCompanionId, companion.Name || null, null, null, false, false)
        );
    }

    if (context.defaultUserId && membersById.has(context.defaultUserId)) {
        const defaultMember = membersById.get(context.defaultUserId);
        defaultMember.isDefault = true;
        defaultMember.isManager = true;
        context.defaultUserName = defaultMember.name;
    }

    context.members = [...membersById.values()].sort((left, right) => {
        const rank = (member) => {
            if (context.defaultUserId && member.userId === context.defaultUserId) {
                return 0;
            }
            if (member.isManager) {
                return 1;
            }
            return 2;
        };
        const rankDelta = rank(left) - rank(right);
        if (rankDelta !== 0) {
            return rankDelta;
        }
        return String(left.name || '').localeCompare(String(right.name || ''));
    });
    return context;
}

function idsMatch(left, right) {
    const a = String(left || '');
    const b = String(right || '');
    if (!a || !b) {
        return false;
    }
    if (a === b) {
        return true;
    }
    return a.slice(0, 15) === b.slice(0, 15);
}

function payloadFromCachedVisit(visit, visitId) {
    if (!visit) {
        return null;
    }
    const status = visit.status || visit.Status__c || 'Draft';
    return {
        visit: {
            id: visit.id || visit.Id || visitId,
            visitId: visit.id || visit.Id || visitId,
            name: visit.name || visit.Name || visit.visitName,
            status,
            visitType: visit.visitType || visit.Visit_Type__c,
            startDateTime: visit.startDateTime || visit.Start_Date__c,
            endDateTime: visit.endDateTime || visit.End_Date__c,
            visitObjective: visit.visitObjective || visit.Visit_Objective__c,
            visitNotes: visit.visitNotes || visit.Visit_Notes__c,
            clmPresentation: visit.clmPresentation || visit.CLM_Presentation__c,
            nextVisitDate: visit.nextVisitDate || visit.Next_Visit_Date__c,
            cancellationReason: visit.cancellationReason || visit.Cancellation_Reason__c,
            isLocked: status === 'Completed' || status === 'Cancelled',
            isDoubleVisit: visit.isDoubleVisit === true || visit.Is_Double_Visit__c === true,
            doubleVisitWithId: visit.doubleVisitWithId || visit.Double_Visit_With__c || null,
            doubleVisitWithName: visit.doubleVisitWithName || null,
            defaultDoubleVisitWithId: null,
            defaultDoubleVisitWithName: null,
            coachingEventId: visit.coachingEventId || visit.Coaching_Event__c || null,
            accountId: visit.accountId || visit.Account__c,
            accountName: visit.accountName || visit.Name || null,
            accountCity: visit.accountCity || null,
            accountSpecialty: visit.accountSpecialty || null,
            accountRecordTypeDeveloperName: visit.accountRecordTypeDeveloperName || null,
            accountRecordTypeName: visit.accountRecordTypeName || null,
            assignedToId: visit.assignedToId || visit.Assigned_To__c || null,
            assignedToName: visit.assignedToName || null
        },
        attendees: visit.attendees || [],
        products: visit.products || [],
        samples: visit.samples || [],
        teamMembers: visit.teamMembers || [],
        clmSessions: visit.clmSessions || []
    };
}

function findVisitInList(list, visitId) {
    const rows = Array.isArray(list) ? list : [];
    return rows.find((row) => idsMatch(row?.id || row?.Id || row?.visitId, visitId)) || null;
}

async function loadCachedVisitPayload(visitId) {
    const direct = await getVisitPayload(visitId);
    if (direct?.visit) {
        return direct;
    }
    const todayRows = await getAllTodayPlanRows().catch(() => []);
    for (const row of todayRows) {
        const match = findVisitInList(row?.visits, visitId);
        if (match) {
            return payloadFromCachedVisit(match, visitId);
        }
    }
    const plannerRows = await getAllPlannerCacheRows().catch(() => []);
    for (const row of plannerRows) {
        const match = findVisitInList(row?.payload?.visits, visitId);
        if (match) {
            return payloadFromCachedVisit(match, visitId);
        }
    }
    return direct ? payloadFromCachedVisit(direct.visit || direct, visitId) : null;
}

async function loadCallReportPayload(params) {
    const visitId = params && params.visitId;
    if (!visitId) {
        return null;
    }
    if (isOffline()) {
        const cached = await loadCachedVisitPayload(visitId);
        if (cached) {
            return attachHeroFlags(cached, visitId);
        }
        throw new Error('Offline — this visit is not cached on this device.');
    }
    try {
        const visit = await soqlOne(
            'SELECT Id, Name, Status__c, Visit_Type__c, Start_Date__c, End_Date__c, ' +
                'Visit_Objective__c, Visit_Notes__c, CLM_Presentation__c, Next_Visit_Date__c, ' +
                'Cancellation_Reason__c, Is_Double_Visit__c, Double_Visit_With__c, Double_Visit_With__r.Name, ' +
                'Coaching_Event__c, Account__c, Assigned_To__c, Assigned_To__r.Name, ' +
                'Assigned_To__r.ManagerId, Assigned_To__r.Manager.Name, Account__r.Name, Account__r.BillingCity, ' +
                'Account__r.Specialty_1__c, Account__r.RecordType.DeveloperName, Account__r.RecordType.Name ' +
                `FROM Visit__c WHERE Id = '${visitId}' LIMIT 1`
        );
        if (!visit) {
            const cached = await loadCachedVisitPayload(visitId);
            return cached ? attachHeroFlags(cached, visitId) : null;
        }
        const attendees = await loadAttendees(visitId).catch(() => []);
        const products = await loadProductDetails(visitId).catch(() => []);
        const samples = await loadSamples(visitId).catch(() => []);
        const teamContext = await loadTeamCompanionContext(visit).catch(() => emptyTeamContext());
        const payload = {
            visit: mapVisit(visit, teamContext),
            attendees,
            products,
            samples,
            teamMembers: teamContext.members,
            clmSessions: []
        };
        await attachHeroFlags(payload, visitId);
        await putVisitPayload(visitId, payload);
        return payload;
    } catch (error) {
        const cached = await loadCachedVisitPayload(visitId);
        if (cached) {
            return attachHeroFlags(cached, visitId);
        }
        throw error;
    }
}

export default makeDualApex(loadCallReportPayload);
