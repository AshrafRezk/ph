/**
 * Planner fixtures for the store-review demo. Answers `/planner/v1/*` and `/planner/assist/v1/*`
 * (week, accounts, targets, time off, meetings, assist, writes) from the shared seed.
 * Home (`home/*`) and Accounts tab (`accounts-tab/*`) paths are left to their own fixtures.
 */
import {
    DEMO_USER_ID,
    DEMO_MANAGER_ID,
    DEMO_TERRITORY,
    DEMO_ACCOUNTS,
    DEMO_PRODUCTS,
    demoVisits,
    todayIso,
    accountById
} from '../demoSeed.js';

const PLANNER_PREFIX = '/services/apexrest/planner/v1/';
const ASSIST_PREFIX = '/services/apexrest/planner/assist/v1/';
const DISTRICT_ID = '0MIDEMO00000000002';
const PLANNED_VISIT_TYPE = 'Planned (Automatically)';

let writeCounter = 0;

/** yyyy-mm-dd plus `days`, in UTC so it never stalls across time zones (seed addDays can). */
function shiftDate(dateIso, days) {
    const d = new Date(`${dateIso}T00:00:00Z`);
    d.setUTCDate(d.getUTCDate() + days);
    return d.toISOString().slice(0, 10);
}

/** Fresh 18-char demo id with the given 3-char key prefix. */
function newId(prefix) {
    writeCounter += 1;
    return `${prefix}DEMO${String(Date.now()).slice(-7)}${String(writeCounter).padStart(4, '0')}`.slice(0, 18);
}

/** Local `yyyy-mm-ddThh:mm:ss` to the UTC ISO string Apex serializes. */
function utc(localDateTime) {
    const d = new Date(localDateTime);
    return Number.isNaN(d.getTime()) ? null : d.toISOString();
}

function inRange(dateIso, start, end) {
    return (!start || dateIso >= start) && (!end || dateIso <= end);
}

/** Monday of the week holding `dateIso`. */
function weekStartOf(dateIso) {
    const d = new Date(`${dateIso}T00:00:00Z`);
    const shift = (d.getUTCDay() + 6) % 7;
    return shiftDate(dateIso, -shift);
}

// ---------------------------------------------------------------------------
// Accounts
// ---------------------------------------------------------------------------

const RECORD_TYPES = {
    HCP: { developerName: 'Medical_Professional_HCP', label: 'Medical Professional (HCP)' },
    Pharmacy: { developerName: 'Pharmacy', label: 'Pharmacy' },
    Clinic: { developerName: 'Institution_HCO', label: 'Institution (HCO)' },
    Hospital: { developerName: 'Institution_HCO', label: 'Institution (HCO)' }
};

function recordTypeOf(account) {
    return RECORD_TYPES[account.kind] || RECORD_TYPES.HCP;
}

/** A/B/C call class to the letter+number code the planner displays (A1–C3). */
function classCodeOf(account) {
    const tier = account.frequency >= 4 ? 1 : account.frequency >= 2 ? 2 : 3;
    return `${account.classCode}${tier}`;
}

const BRICK_702_NAMES = [...new Set(DEMO_ACCOUNTS.map((a) => a.brick))].sort();
const BRICK_148_NAMES = [...new Set(DEMO_ACCOUNTS.map((a) => a.city))].sort();

function brick148Id(city) {
    return `a0BDEMO1${String(BRICK_148_NAMES.indexOf(city) + 1).padStart(10, '0')}`;
}

function brick702Id(brick) {
    return `a0BDEMO7${String(BRICK_702_NAMES.indexOf(brick) + 1).padStart(10, '0')}`;
}

function completedVisitCount(accountId) {
    return demoVisits().filter((v) => v.accountId === accountId && v.status === 'Completed').length;
}

function frequencyStatus(actual, target) {
    if (actual > target) return 'MCF';
    if (actual === target || (target === 0 && actual > 0)) return 'RCF';
    return 'LCF';
}

/** FieldPlannerController.AccountSummary plus the pace fields the planner list reads. */
function accountSummary(account) {
    const rt = recordTypeOf(account);
    const actual = completedVisitCount(account.id);
    const target = account.frequency;
    const planned = demoVisits().filter((v) => v.accountId === account.id && v.status === 'Planned').length;
    const status = frequencyStatus(actual, target);
    return {
        id: account.id,
        name: account.name,
        specialty: account.specialty,
        specialtyApiValue: account.specialty,
        classification: classCodeOf(account),
        city: account.city,
        street: `${account.brick} main street`,
        latitude: account.lat,
        longitude: account.lng,
        phone: account.phone,
        recordTypeName: rt.label,
        recordTypeDeveloperName: rt.developerName,
        brickId: brick702Id(account.brick),
        brickName: account.brick,
        brick148Id: brick148Id(account.city),
        brick148Name: account.city,
        brick702Id: brick702Id(account.brick),
        brick702Name: account.brick,
        frequencyStatus: status,
        actualVisits: actual,
        targetVisits: target,
        plannedVisits: planned,
        paceStatus: status === 'LCF' ? 'behind' : 'on-track',
        paceStatusLabel: status === 'LCF' ? 'Behind frequency' : 'On track'
    };
}

function filterOptions() {
    const specialties = [...new Set(DEMO_ACCOUNTS.map((a) => a.specialty))].sort();
    const classes = [...new Set(DEMO_ACCOUNTS.map(classCodeOf))].sort();
    return {
        specialtyOptions: [
            { label: 'All Specialties', value: 'All' },
            ...specialties.map((s) => ({ label: s, value: s }))
        ],
        classificationOptions: [
            { label: 'All Classifications', value: 'All' },
            ...classes.map((c) => ({ label: c, value: c }))
        ],
        brickOptions: [
            { label: 'All Bricks', value: 'All' },
            ...BRICK_702_NAMES.map((b) => ({ label: b, value: brick702Id(b) }))
        ],
        brick148Options: [
            { label: 'All 148 bricks', value: 'All' },
            ...BRICK_148_NAMES.map((c) => ({ label: c, value: brick148Id(c) }))
        ],
        brick702Options: [
            { label: 'All 702 bricks', value: 'All' },
            ...BRICK_702_NAMES.map((b) => {
                const city = DEMO_ACCOUNTS.find((a) => a.brick === b).city;
                return { label: b, value: brick702Id(b), parentValue: brick148Id(city) };
            })
        ]
    };
}

function accountRecordTypes() {
    const seen = new Map();
    DEMO_ACCOUNTS.forEach((a) => {
        const rt = recordTypeOf(a);
        seen.set(rt.developerName, rt);
    });
    return [...seen.values()].map((rt) => ({
        label: rt.label,
        value: rt.developerName,
        developerName: rt.developerName
    }));
}

/** POST accounts/search — PlannerMobileRestService.cls:431. */
function searchAccounts(body = {}) {
    const term = String(body.searchTerm || '').trim().toLowerCase();
    const recordTypes = Array.isArray(body.recordTypeDeveloperNames) ? body.recordTypeDeveloperNames.filter((rt) => rt && rt !== 'All') : [];
    const brick = body.brick702Id || body.brick148Id || body.brickId || '';
    const pageSize = Number(body.pageSize) || 50;
    const offset = Number(body.pageToken) || 0;
    const rows = DEMO_ACCOUNTS.map(accountSummary).filter((a) => {
        if (term && !`${a.name} ${a.specialty} ${a.city} ${a.brickName}`.toLowerCase().includes(term)) return false;
        if (recordTypes.length && !recordTypes.includes(a.recordTypeDeveloperName)) return false;
        if (body.specialty && body.specialty !== 'All' && a.specialty !== body.specialty) return false;
        if (body.classification && body.classification !== 'All' && a.classification !== body.classification) return false;
        if (brick && brick !== 'All' && ![a.brick702Id, a.brick148Id, a.brickId].includes(brick)) return false;
        return true;
    });
    const page = rows.slice(offset, offset + pageSize);
    const hasMore = offset + pageSize < rows.length;
    return {
        accounts: page,
        hasMore,
        totalCount: rows.length,
        nextPageToken: hasMore ? String(offset + pageSize) : null,
        totalSize: rows.length
    };
}

// ---------------------------------------------------------------------------
// Visits, time off, meetings
// ---------------------------------------------------------------------------

/** Seed status to the Visit__c Status__c picklist (Draft/Submitted/Scheduled/Completed/Cancelled). */
function visitStatus(seedStatus) {
    return seedStatus === 'Planned' ? 'Scheduled' : seedStatus;
}

/** FieldPlannerController.VisitSummary (FieldPlannerController.cls:141). */
function visitSummary(visit) {
    const account = visit.account || accountById(visit.accountId);
    const rt = account ? recordTypeOf(account) : RECORD_TYPES.HCP;
    return {
        id: visit.id,
        name: visit.name,
        accountId: visit.accountId,
        accountName: visit.accountName,
        status: visitStatus(visit.status),
        visitType: PLANNED_VISIT_TYPE,
        startDateTime: utc(visit.start),
        endDateTime: utc(visit.end),
        accountLatitude: account ? account.lat : null,
        accountLongitude: account ? account.lng : null,
        accountSpecialty: account ? account.specialty : null,
        accountRecordTypeName: rt.label,
        accountRecordTypeDeveloperName: rt.developerName,
        cancellationReason: null,
        zetaProjectId: null,
        zetaProjectName: null,
        visitObjective: `Detail ${DEMO_PRODUCTS[0].brand} and ${DEMO_PRODUCTS[2].brand}`
    };
}

const EDITS_KEY = 'zeta.pwa.demoVisitEdits';

/** Visits the reviewer created or changed, kept on the device: id -> VisitSummary or { deleted }. */
function readEdits() {
    try {
        return JSON.parse(globalThis.localStorage?.getItem(EDITS_KEY) || '{}') || {};
    } catch (_err) {
        return {};
    }
}

function saveEdits(edits) {
    try {
        globalThis.localStorage?.setItem(EDITS_KEY, JSON.stringify(edits));
    } catch (_err) {
        /* private mode: edits last for this page only */
    }
}

function rememberVisits(result) {
    const list = (Array.isArray(result) ? result : [result]).filter((v) => v && v.id && v.startDateTime !== undefined);
    if (!list.length) return;
    const edits = readEdits();
    list.forEach((v) => {
        edits[v.id] = v;
    });
    saveEdits(edits);
}

function forgetVisit(visitId) {
    if (!visitId) return;
    const edits = readEdits();
    edits[visitId] = { deleted: true };
    saveEdits(edits);
}

function localDateOf(isoDateTime) {
    const d = new Date(isoDateTime);
    return Number.isNaN(d.getTime())
        ? String(isoDateTime || '').slice(0, 10)
        : `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, '0')}-${String(d.getDate()).padStart(2, '0')}`;
}

function weekVisits(start, end) {
    const edits = readEdits();
    const seeded = demoVisits()
        .filter((v) => !edits[v.id])
        .map(visitSummary);
    const edited = Object.values(edits).filter((v) => v && !v.deleted && v.startDateTime);
    return [...seeded, ...edited].filter((v) => inRange(localDateOf(v.startDateTime), start, end));
}

/** Time off blocks relative to today: one approved training, one draft leave next week. */
function demoTimeOff() {
    const today = todayIso();
    const trainingDay = shiftDate(today, 3);
    const leaveDay = shiftDate(today, 8);
    return [
        {
            id: 'a0TDEMO00000000001',
            name: 'TOT-DEMO-0001',
            typeLabel: 'Training',
            typeValue: 'Training',
            spanType: 'Hours',
            durationHours: '2',
            stage: 'Approved',
            startDateTime: utc(`${trainingDay}T14:00:00`),
            endDateTime: utc(`${trainingDay}T16:00:00`),
            isFullDay: false,
            comments: 'Product training session',
            date: trainingDay
        },
        {
            id: 'a0TDEMO00000000002',
            name: 'TOT-DEMO-0002',
            typeLabel: 'Annual Leave',
            typeValue: 'Annual Leave',
            spanType: 'Full_Day',
            durationHours: null,
            stage: 'Draft',
            startDateTime: utc(`${leaveDay}T09:00:00`),
            endDateTime: utc(`${leaveDay}T17:00:00`),
            isFullDay: true,
            comments: '',
            date: leaveDay
        }
    ];
}

function timeOffBlocks(start, end) {
    return demoTimeOff()
        .filter((t) => inRange(t.date, start, end))
        .map(({ date, ...rest }) => rest);
}

const MEETING_RECORD_TYPES = [
    { label: 'Advisory Board', value: 'Advisory_Board' },
    { label: 'Promotional Activity', value: 'Promotional_Activity' },
    { label: 'Regional Standalone', value: 'Regional_Standalone' },
    { label: 'Speaker Meeting', value: 'Speaker_Meeting' }
];

const DEMO_PROJECTS = [
    { id: 'a0PDEMO00000000001', name: 'Cardiora awareness month' },
    { id: 'a0PDEMO00000000002', name: 'Lipovia launch wave' }
];

/** MeetingPlannerController.MeetingSummary (MeetingPlannerController.cls:2). */
function demoMeetings(start, end) {
    const day = shiftDate(todayIso(), 2);
    const rows = [
        {
            id: 'a0MDEMO00000000001',
            name: 'MTG-DEMO-0001',
            title: 'Cardiora round-table',
            status: 'Approved',
            recordTypeDeveloperName: 'Speaker_Meeting',
            recordTypeLabel: 'Speaker Meeting',
            startDateTime: utc(`${day}T15:00:00`),
            endDateTime: utc(`${day}T16:30:00`),
            pharmaProjectId: DEMO_PROJECTS[0].id,
            pharmaProjectName: DEMO_PROJECTS[0].name,
            date: day
        }
    ];
    return rows.filter((m) => inRange(m.date, start, end)).map(({ date, ...rest }) => rest);
}

/** GET week — PlannerMobileRestService.cls:51 plus the meetings/publicHolidayDates the shim reads. */
function weekPayload(params) {
    const start = params.get('weekStart') || weekStartOf(todayIso());
    const end = params.get('weekEnd') || shiftDate(start, 6);
    const tot = timeOffBlocks(start, end);
    return {
        weekStart: start,
        weekEnd: end,
        visits: weekVisits(start, end),
        timeOff: tot,
        timeOffBlocks: tot,
        meetings: demoMeetings(start, end),
        publicHolidayDates: []
    };
}

// ---------------------------------------------------------------------------
// Targets and assist
// ---------------------------------------------------------------------------

/** FieldPlannerController.AccountVisitTarget (FieldPlannerController.cls:79). */
function visitTargets() {
    return DEMO_ACCOUNTS.map((a) => {
        const actual = completedVisitCount(a.id);
        return {
            accountId: a.id,
            accountName: a.name,
            latitude: a.lat,
            longitude: a.lng,
            targetVisitFrequency: a.frequency,
            actualVisits: actual,
            visitGap: Math.max(0, a.frequency - actual),
            frequencyStatus: frequencyStatus(actual, a.frequency),
            potentiality: a.classCode === 'A' ? 'High' : a.classCode === 'B' ? 'Medium' : 'Low'
        };
    });
}

/** FieldPlannerAssistController.WeeklyPlanRecommendations (FieldPlannerAssistController.cls:24). */
function weekRecommendations(params) {
    const start = params.get('weekStart') || weekStartOf(todayIso());
    const end = params.get('weekEnd') || shiftDate(start, 6);
    const visits = demoVisits().filter((v) => inRange(v.date, start, end));
    const recommendations = visitTargets()
        .filter((t) => t.visitGap > 0)
        .map((t) => {
            const plannedCount = visits.filter((v) => v.accountId === t.accountId).length;
            return {
                ...t,
                plannedThisWeek: plannedCount > 0,
                plannedCountThisWeek: plannedCount,
                reason:
                    plannedCount > 0
                        ? 'Already on this week — keep coverage'
                        : t.frequencyStatus === 'LCF'
                          ? 'Behind frequency (LCF) — plan a draft visit'
                          : 'Below target — add to this week'
            };
        })
        .sort((a, b) => Number(a.plannedThisWeek) - Number(b.plannedThisWeek) || b.visitGap - a.visitGap)
        .map((row, i) => ({ ...row, rank: i + 1 }));
    const today = todayIso();
    let remaining = 0;
    for (let d = today > start ? today : start, i = 0; d <= end && i < 14; d = shiftDate(d, 1), i += 1) {
        const dow = new Date(`${d}T00:00:00Z`).getUTCDay();
        if (dow !== 5) remaining += 1;
    }
    const planned = visits.filter((v) => v.status !== 'Cancelled').length;
    const workingDays = 6;
    const daily = Math.round((planned / workingDays) * 10) / 10;
    const toAdd = recommendations.filter((r) => !r.plannedThisWeek).length;
    return {
        recommendations,
        forecast: {
            plannedVisitCount: planned,
            remainingWorkingDays: remaining,
            dailyFrequency: daily,
            paceLabel: daily >= 4 ? 'On track' : daily >= 2 ? 'Needs a few more visits' : 'Behind pace',
            recommendationCount: recommendations.length,
            projectedDailyIfAdded: Math.round(((planned + toAdd) / workingDays) * 10) / 10
        }
    };
}

function askAnswer(body = {}) {
    const start = body.weekStart || weekStartOf(todayIso());
    const recs = weekRecommendations(new URLSearchParams({ weekStart: start, weekEnd: shiftDate(start, 6) }));
    const next = recs.recommendations.filter((r) => !r.plannedThisWeek).slice(0, 3);
    const names = next.map((r) => r.accountName).join(', ');
    return {
        answer:
            `This week has ${recs.forecast.plannedVisitCount} visits planned (${recs.forecast.dailyFrequency} per day, ${recs.forecast.paceLabel.toLowerCase()}).` +
            (names ? ` To close frequency gaps, consider adding ${names}.` : ' Your targets are covered for this week.') +
            ' (Demo answer from sample data.)',
        contextSummary: `${recs.forecast.plannedVisitCount} planned · ${recs.recommendations.length} recommendations · ${DEMO_TERRITORY.name}`
    };
}

// ---------------------------------------------------------------------------
// User, territory, approvals
// ---------------------------------------------------------------------------

/** PlannerMobileRestService.buildCurrentUserProfile (PlannerMobileRestService.cls:1074). */
function currentUserProfile() {
    return {
        id: DEMO_USER_ID,
        firstName: 'Demo',
        lastName: 'Field Rep',
        name: 'Demo Field Rep',
        email: 'review.demo@zeta-copilot.app',
        username: 'review.demo@zeta-copilot.app',
        title: 'Medical Representative',
        phone: '+20 100 000 0100',
        mobilePhone: '+20 100 000 0100',
        smallPhotoUrl: null,
        mediumPhotoUrl: null,
        fullPhotoUrl: null,
        photoUrl: null,
        lastLoginDate: `${todayIso()}T07:30:00.000Z`,
        profileName: 'Field Rep',
        managerId: DEMO_MANAGER_ID,
        managerName: DEMO_TERRITORY.managerName,
        managerSource: 'territory',
        roleInTerritory: 'Medical Rep',
        territoryId: DEMO_TERRITORY.id,
        territoryName: DEMO_TERRITORY.name,
        territoryLevel: 'Territory',
        usingAllAssigned: true,
        hasAssignment: true
    };
}

/** TerritoryContextService.SwitcherContext (TerritoryContextService.cls:14). */
function territoryContext(selectedId) {
    const usingAll = !selectedId;
    return {
        selectedTerritoryId: usingAll ? null : DEMO_TERRITORY.id,
        selectedTerritoryName: usingAll ? 'All assigned territories' : DEMO_TERRITORY.name,
        selectedLevel: usingAll ? null : 'Territory',
        usingAllAssigned: usingAll,
        hasAssignment: true,
        tree: [
            {
                id: DISTRICT_ID,
                name: DEMO_TERRITORY.district,
                externalId: 'DEMO-DM-CAIRO',
                level: 'District',
                parentId: null,
                hasChildren: true,
                children: [
                    {
                        id: DEMO_TERRITORY.id,
                        name: DEMO_TERRITORY.name,
                        externalId: 'DEMO-CARDIO-CAIRO-EAST',
                        level: 'Territory',
                        parentId: DISTRICT_ID,
                        hasChildren: false,
                        children: []
                    }
                ]
            }
        ]
    };
}

/** FieldPlannerController.PlannerViewerContext (FieldPlannerController.cls:122), rep in self mode. */
function viewerContext() {
    return {
        viewerMode: 'self',
        canSwitchView: false,
        canApproveTeamPlans: false,
        topTerritoryId: null,
        topTerritoryName: null,
        defaultUserId: DEMO_USER_ID,
        assignedTerritoryIds: [DEMO_TERRITORY.id],
        options: []
    };
}

/** TimeOffRequestController.RequestSummary list (TimeOffRequestController.cls:3). */
function myTimeOffRequests(limit) {
    return demoTimeOff()
        .slice(0, limit)
        .map((t) => ({
            id: t.id,
            name: t.name,
            typeLabel: t.typeLabel,
            spanType: t.spanType,
            workingDays: t.isFullDay ? 1 : 0.25,
            startDate: t.date,
            endDate: t.date,
            stage: t.stage,
            createdDate: `${shiftDate(todayIso(), -2)}T08:00:00.000Z`
        }));
}

/** First brick-growth alert shape read by main.js and getPhysicianMovementAlerts.js. */
function brickAlerts() {
    const brick = 'Nasr City 2';
    const doctors = DEMO_ACCOUNTS.filter((a) => a.brick === brick);
    return [
        {
            brickId: brick702Id(brick),
            brickName: brick,
            growthPercent: 18,
            month: todayIso().slice(0, 7),
            doctors: doctors.map((a) => ({
                accountId: a.id,
                accountName: a.name,
                classification: classCodeOf(a),
                specialty: a.specialty
            }))
        }
    ];
}

function classificationSuggestions() {
    const account = DEMO_ACCOUNTS[3];
    return [
        {
            id: 'a0SDEMO00000000001',
            suggestionId: 'a0SDEMO00000000001',
            accountId: account.id,
            accountName: account.name,
            currentClass: classCodeOf(account),
            suggestedClass: 'A2',
            reason: 'Prescribing trend up for three months (sample data).',
            status: 'Pending',
            createdDate: `${shiftDate(todayIso(), -1)}T09:00:00.000Z`
        }
    ];
}

// ---------------------------------------------------------------------------
// Writes (stateless echoes)
// ---------------------------------------------------------------------------

function isDemoId(value) {
    return /^[a-zA-Z0-9]{18}$/.test(String(value || ''));
}

/** POST visits/upsert — returns FieldPlannerController.VisitSummary. */
function upsertVisit(body = {}) {
    const account = accountById(body.accountId);
    const rt = account ? recordTypeOf(account) : null;
    const project = DEMO_PROJECTS.find((p) => p.id === body.zetaProjectId) || null;
    const existing = demoVisits().find((v) => v.id === body.visitId);
    return {
        id: isDemoId(body.visitId) ? body.visitId : newId('a0V'),
        name: existing ? existing.name : `V-DEMO-${String(100 + writeCounter).padStart(4, '0')}`,
        accountId: account ? account.id : null,
        accountName: account ? account.name : null,
        status: body.status || 'Draft',
        visitType: body.visitType || PLANNED_VISIT_TYPE,
        startDateTime: body.startDateTime || null,
        endDateTime: body.endDateTime || null,
        accountLatitude: account ? account.lat : null,
        accountLongitude: account ? account.lng : null,
        accountSpecialty: account ? account.specialty : null,
        accountRecordTypeName: rt ? rt.label : null,
        accountRecordTypeDeveloperName: rt ? rt.developerName : null,
        cancellationReason: body.cancellationReason || null,
        zetaProjectId: project ? project.id : null,
        zetaProjectName: project ? project.name : null,
        visitObjective: body.visitObjective || null
    };
}

function seedVisitSummary(visitId, overrides = {}) {
    const edited = readEdits()[visitId];
    const seed = demoVisits().find((v) => v.id === visitId);
    const base = edited && !edited.deleted ? edited : seed ? visitSummary(seed) : upsertVisit({ visitId });
    return { ...base, ...overrides };
}

/** POST mutate/visits/reschedule — list of VisitSummary with the new times. */
function rescheduleVisits(body = {}) {
    const moves = Array.isArray(body.moves) ? body.moves : [];
    return moves
        .filter((m) => m && m.visitId)
        .map((m) =>
            seedVisitSummary(m.visitId, {
                startDateTime: m.startDateTime,
                endDateTime: m.endDateTime,
                status: 'Draft'
            })
        );
}

/** POST visits/copy-day — VisitSummary list cloned onto the target date as drafts. */
function copyDay(body = {}) {
    if (!body.sourceDate || !body.targetDate) return [];
    return demoVisits()
        .filter((v) => v.date === body.sourceDate && v.status !== 'Cancelled')
        .map((v) => {
            const startTime = v.start.slice(10);
            const endTime = v.end.slice(10);
            return {
                ...visitSummary(v),
                id: newId('a0V'),
                name: `V-DEMO-${String(200 + writeCounter).padStart(4, '0')}`,
                status: 'Draft',
                startDateTime: utc(`${body.targetDate}${startTime}`),
                endDateTime: utc(`${body.targetDate}${endTime}`)
            };
        });
}

/** POST visits/copy-week — FieldPlannerAssistController.CopyWeekResult (cls:29). */
function copyWeek(body = {}) {
    const target = body.targetWeekStart || weekStartOf(todayIso());
    const source = shiftDate(target, -7);
    const visits = demoVisits()
        .filter((v) => inRange(v.date, source, shiftDate(source, 6)))
        .map((v) => {
            const shifted = shiftDate(v.date, 7);
            return {
                ...visitSummary(v),
                id: newId('a0V'),
                status: 'Draft',
                startDateTime: utc(`${shifted}${v.start.slice(10)}`),
                endDateTime: utc(`${shifted}${v.end.slice(10)}`)
            };
        });
    return { createdCount: visits.length, skippedCount: 0, visits };
}

/** POST visits/submit-week — FieldPlannerController.WeekSubmitResult (cls:280). */
function submitWeek(body = {}) {
    const start = body.weekStart || weekStartOf(todayIso());
    const end = body.weekEnd || shiftDate(start, 6);
    const visits = weekVisits(start, end)
        .filter((v) => v.status === 'Draft' || v.status === 'Scheduled')
        .map((v) => ({ ...v, status: 'Submitted' }));
    return { submittedCount: visits.length, failedCount: 0, visits, errors: [] };
}

/** POST time-off — FieldPlannerController.TotSummary (cls:227). */
function createTimeOff(body = {}) {
    const start = body.startDateTime || utc(`${todayIso()}T09:00:00`);
    const fullDay = body.spanType !== 'Hours';
    const hours = Number(body.durationHours) || 8;
    const end = new Date(new Date(start).getTime() + hours * 3600 * 1000).toISOString();
    return {
        id: newId('a0T'),
        name: `TOT-DEMO-${String(100 + writeCounter).padStart(4, '0')}`,
        typeLabel: body.typeValue || 'Time Off',
        typeValue: body.typeValue || null,
        spanType: body.spanType || 'Full_Day',
        durationHours: body.durationHours || null,
        stage: body.stage || 'Draft',
        startDateTime: start,
        endDateTime: end,
        isFullDay: fullDay,
        comments: body.comments || ''
    };
}

/** POST time-off/update — FieldPlannerAssistController.TotSummary (cls:35). */
function updateTimeOff(body = {}) {
    const seed = demoTimeOff().find((t) => t.id === body.timeOffId);
    return {
        id: body.timeOffId || newId('a0T'),
        name: seed ? seed.name : 'TOT-DEMO',
        typeLabel: seed ? seed.typeLabel : 'Time Off',
        spanType: seed ? seed.spanType : 'Hours',
        stage: seed ? seed.stage : 'Draft',
        startDateTime: seed ? seed.startDateTime : null,
        endDateTime: body.endDateTime || (seed ? seed.endDateTime : null),
        isFullDay: seed ? seed.isFullDay : false
    };
}

/** POST meetings / meetings/update — MeetingPlannerController.MeetingSummary. */
function saveMeeting(body = {}, isNew) {
    const rt = MEETING_RECORD_TYPES.find((r) => r.value === body.recordTypeDeveloperName) || MEETING_RECORD_TYPES[3];
    const project = DEMO_PROJECTS.find((p) => p.id === body.pharmaProjectId) || null;
    const seed = demoMeetings().find((m) => m.id === body.meetingId);
    return {
        ...(seed || {}),
        id: isNew ? newId('a0M') : body.meetingId,
        name: seed ? seed.name : `MTG-DEMO-${String(100 + writeCounter).padStart(4, '0')}`,
        title: body.title || (seed ? seed.title : rt.label),
        status: seed ? seed.status : 'Draft',
        recordTypeDeveloperName: seed ? seed.recordTypeDeveloperName : rt.value,
        recordTypeLabel: seed ? seed.recordTypeLabel : rt.label,
        startDateTime: body.startDateTime || (seed ? seed.startDateTime : null),
        endDateTime: body.endDateTime || (seed ? seed.endDateTime : null),
        pharmaProjectId: project ? project.id : seed ? seed.pharmaProjectId : null,
        pharmaProjectName: project ? project.name : seed ? seed.pharmaProjectName : null
    };
}

/** POST outbox — PlannerMobileRestService.drainOutbox (cls:733). */
function drainOutbox(body = {}) {
    const actions = Array.isArray(body.actions) ? body.actions : [];
    return {
        results: actions.map((action) => {
            const map = {};
            const type = action.actionType;
            if ((type === 'UPSERT_VISIT' || type === 'SUBMIT_VISIT') && action.clientVisitKey) {
                map[action.clientVisitKey] = isDemoId(action.clientVisitKey) ? action.clientVisitKey : newId('a0V');
            } else if (type === 'CREATE_MEETING' && action.clientActionKey) {
                map[action.clientActionKey] = newId('a0M');
            } else if (type === 'CREATE_TIME_OFF' && (action.clientActionKey || action.id)) {
                map[action.clientActionKey || action.id] = newId('a0T');
            }
            return { id: action.id, success: true, error: null, visitIdByClientKey: map };
        })
    };
}

// ---------------------------------------------------------------------------
// Router
// ---------------------------------------------------------------------------

function handleGet(route, params) {
    switch (route) {
        case 'me':
            return currentUserProfile();
        case 'territory-context':
            return territoryContext(null);
        case 'viewer-context':
            return viewerContext();
        case 'week':
            return weekPayload(params);
        case 'accounts/map':
            return DEMO_ACCOUNTS.map(accountSummary);
        case 'accounts/filters':
            return filterOptions();
        case 'accounts/record-types':
            return accountRecordTypes();
        case 'projects':
            // Apex sends {id,name}; the planner reads {label,value}. Send both.
            return DEMO_PROJECTS.map((p) => ({ id: p.id, name: p.name, label: p.name, value: p.id, status: 'Active', campaignType: 'Promotional' }));
        case 'targets':
            return visitTargets();
        case 'week-recommendations':
            return weekRecommendations(params);
        case 'brick-alerts':
            // Launch toasts would cover the header during review; keep the demo quiet.
            return [];
        case 'classification-suggestions':
            return [];
        case 'meetings':
            return demoMeetings(params.get('weekStart'), params.get('weekEnd'));
        case 'meetings/record-types':
            return MEETING_RECORD_TYPES;
        case 'time-off':
            return myTimeOffRequests(Math.min(Math.max(Number(params.get('limitSize')) || 10, 1), 50));
        case 'time-off/approval-target': {
            const id = params.get('timeOffId');
            const seed = demoTimeOff().find((t) => t.id === id) || demoTimeOff()[0];
            return {
                timeOffId: id || seed.id,
                userId: DEMO_USER_ID,
                userName: 'Demo Field Rep',
                territoryId: DEMO_TERRITORY.id,
                territoryName: DEMO_TERRITORY.name,
                startDateTime: seed.startDateTime,
                stage: seed.stage,
                typeLabel: seed.typeLabel
            };
        }
        case 'visits/pending-approvals':
            return [];
        default:
            return undefined;
    }
}

function handlePost(route, body) {
    switch (route) {
        case 'territory-context':
            return territoryContext(body && body.territoryId);
        case 'me/photo':
            return currentUserProfile();
        case 'accounts/search':
            return searchAccounts(body || {});
        case 'visits/upsert':
            return upsertVisit(body || {});
        case 'visits/reschedule':
            return rescheduleVisits(body || {});
        case 'visits/delete':
        case 'time-off/delete':
        case 'meetings/delete':
            return { ok: true };
        case 'visits/submit':
            return seedVisitSummary(body && body.visitId, { status: 'Submitted' });
        case 'visits/submit-week':
            return submitWeek(body || {});
        case 'visits/approve':
            return seedVisitSummary(body && body.visitId, { status: 'Scheduled' });
        case 'visits/reject':
            return seedVisitSummary(body && body.visitId, { status: 'Draft', cancellationReason: (body && body.rejectionReason) || null });
        case 'visits/copy-day':
            return copyDay(body || {});
        case 'visits/copy-week':
            return copyWeek(body || {});
        case 'agent/ask':
            return askAnswer(body || {});
        case 'time-off':
            return createTimeOff(body || {});
        case 'time-off/update':
            return updateTimeOff(body || {});
        case 'time-off/approve':
            return { success: true, id: body && body.requestId, stage: 'Approved' };
        case 'time-off/reject':
            return { success: true, id: body && body.requestId, stage: 'Rejected' };
        case 'meetings':
            return saveMeeting(body || {}, true);
        case 'meetings/update':
            return saveMeeting(body || {}, false);
        case 'meetings/approve':
            return { ...saveMeeting(body || {}, false), status: 'Approved' };
        case 'meetings/reject':
            return { ...saveMeeting(body || {}, false), status: 'Rejected' };
        case 'classification-suggestions/approve':
        case 'classification-suggestions/reject':
            return { success: true, suggestionId: body && body.suggestionId };
        case 'classification-suggestions/suggest':
            return classificationSuggestions()[0];
        case 'outbox':
            return drainOutbox(body || {});
        default:
            return undefined;
    }
}

/** Planner route relative to `/planner/v1/` or `/planner/assist/v1/`, with `mutate/` folded in. */
function plannerRoute(path) {
    let route = null;
    if (path.startsWith(PLANNER_PREFIX)) route = path.slice(PLANNER_PREFIX.length);
    else if (path.startsWith(ASSIST_PREFIX)) route = path.slice(ASSIST_PREFIX.length);
    if (route == null) return null;
    route = route.replace(/\/+$/, '');
    if (route.startsWith('mutate/')) route = route.slice('mutate/'.length);
    return route;
}

/** Return the JSON body for this request, or undefined if not handled. path has no query string. */
export function handle(path, params, method, body) {
    const route = plannerRoute(String(path || ''));
    if (route == null || route.startsWith('home/') || route.startsWith('accounts-tab/')) {
        return undefined;
    }
    const query = params instanceof URLSearchParams ? params : new URLSearchParams(params || '');
    const verb = String(method || 'GET').toUpperCase();
    if (verb === 'GET') return handleGet(route, query);
    if (verb === 'POST' || verb === 'PATCH' || verb === 'PUT') {
        if (route === 'visits/delete') forgetVisit(body && (body.visitId || body.id));
        const result = handlePost(route, body);
        if (route.startsWith('visits/') && route !== 'visits/delete') rememberVisits(result);
        return result;
    }
    return undefined;
}

/**
 * Return an array of SOQL records for this object, or undefined if not handled.
 * The planner only falls back to SOQL for its own time off list.
 */
export function query(objectApiName, soql) {
    if (objectApiName !== 'Time_Off_Request__c') {
        return undefined;
    }
    return demoTimeOff().map((t) => ({
        attributes: { type: 'Time_Off_Request__c' },
        Id: t.id,
        Name: t.name,
        Type__c: t.typeLabel,
        Span_Type__c: t.spanType,
        Working_Day_Equivalent__c: t.isFullDay ? 1 : 0.25,
        Start_Date__c: t.date,
        End_Date__c: t.date,
        Start_Date_Time__c: t.startDateTime,
        End_Date_Time__c: t.endDateTime,
        Stage__c: t.stage,
        Comments__c: t.comments,
        CreatedDate: `${shiftDate(todayIso(), -2)}T08:00:00.000Z`,
        CreatedById: DEMO_USER_ID,
        CreatedBy: { attributes: { type: 'User' }, Name: 'Demo Field Rep' }
    }));
}

/** Keeps the Planner in step when the visit shell saves a call report (see demoData outbox merge). */
export function markVisitStatus(visitId, status) {
    if (!visitId || !status) return;
    rememberVisits(seedVisitSummary(visitId, { status }));
}

/** Planner half of POST /planner/v1/outbox: new ids for queued planner creates. */
export function outboxResults(body) {
    return drainOutbox(body || {}).results;
}
