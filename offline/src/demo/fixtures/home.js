/**
 * Home, app shell, Accounts tab and My Learning fixtures for the store-review demo.
 * Answers the Field Co-pilot app nav (UI API apps + /tabs), feature flags, the home
 * dashboard bundle, monthly timecard, next best customers, notifications, the
 * Accounts tab REST routes, the Account record panels and their SOQL reads.
 * Everything is built from the shared seed so Home, Planner and Accounts agree.
 */
import {
    DEMO_USER_ID,
    DEMO_MANAGER_ID,
    DEMO_TERRITORY,
    DEMO_ACCOUNTS,
    DEMO_PRODUCTS,
    DEMO_COURSES,
    demoVisits,
    todayIso,
    addDays,
    accountById
} from '../demoSeed.js';

const DISTRICT_ID = '0MIDEMO00000000002';
const APP_ID = '02uDEMO00000000001';
const PLANNER_PREFIX = '/services/apexrest/planner/v1/';
const ACCOUNTS_TAB_PREFIX = '/services/apexrest/accounts-tab/v1/';
const PLANNED_VISIT_TYPE = 'Planned (Automatically)';

let writeCounter = 0;

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

/** 15/18-char tolerant id compare. Demo ids share their first 15 chars, so 18-char ids compare in full. */
function sameId(left, right) {
    const a = String(left || '');
    const b = String(right || '');
    if (a.length === 18 && b.length === 18) return a === b;
    return a.slice(0, 15) === b.slice(0, 15);
}

function monthLabel() {
    return new Date().toLocaleDateString('en-US', { month: 'long', year: 'numeric' });
}

function round1(value) {
    return Math.round(value * 10) / 10;
}

// ---------------------------------------------------------------------------
// App shell: Field Co-pilot nav (fetchAppTabs.js) and feature flags
// ---------------------------------------------------------------------------

/** Tab keys main.js maps in APP_TAB_VIEWS (main.js:1982). */
const FIELD_TABS = [
    ['Field_Rep_Home_App', 'Home', 'TabFlexiPage'],
    ['Field_Rep_Planner', 'Planner', 'TabAura'],
    ['Accounts_Tab', 'Accounts', 'TabFlexiPage'],
    ['Field_Requests', 'Requests', 'TabFlexiPage'],
    ['Field_Orders', 'Orders', 'TabFlexiPage'],
    ['Field_KPIs', 'KPIs', 'TabFlexiPage'],
    ['My_Learning', 'My Learning', 'TabFlexiPage'],
    ['Class_Engine', 'Class Engine', 'TabFlexiPage'],
    ['CLM_Presentations', 'CLM Presentations', 'TabFlexiPage'],
    ['Reports_Hub', 'Reports Hub', 'TabFlexiPage']
];

function navItems() {
    return FIELD_TABS.map(([developerName, label, itemType], i) => ({
        id: `0LTDEMO${String(i + 1).padStart(11, '0')}`,
        developerName,
        label,
        itemType,
        objectApiName: null,
        iconUrl: null,
        pageReference: { type: 'standard__navItemPage', attributes: { apiName: developerName } }
    }));
}

/** UI API App (read by fetchAppTabs.js mapOrgApp / normalizeTabs). */
function fieldApp() {
    return {
        appId: APP_ID,
        id: APP_ID,
        developerName: 'LightningSales',
        label: 'Field Co-pilot',
        description: 'Home, planner, accounts, CLM & time off — full offline support.',
        formFactors: ['Large', 'Small'],
        selected: true,
        iconUrl: null,
        navItems: navItems()
    };
}

/** GET /services/data/vXX/tabs (fetchAppTabs.js fetchTabsFromOrg). */
function allTabs() {
    return FIELD_TABS.map(([name, label]) => ({
        name,
        label,
        sobjectName: null,
        iconUrl: null,
        miniIconUrl: null,
        custom: true,
        url: `/lightning/n/${name}`
    }));
}

/** Feature keys from getEnabledFeatureMap.js DEFAULTS and FieldAppFeatureController.cls:36 CATALOG. */
const FEATURES = [
    ['home.officeMessages', 'Home office messages', 'Home', true],
    ['home.beInTheKnow', 'Be in the know', 'Home', true],
    ['home.accountsNurturing', 'Accounts nurturing', 'Home', true],
    ['home.yourPerformance', 'Your performance', 'Home', true],
    ['home.todayPlan', "Today's plan", 'Home', true],
    ['home.nextBestCustomer', 'Next best customer', 'Home', true],
    ['home.reports', 'Reports', 'Home', true],
    ['metric.visit', 'Visit coverage ring', 'Home', true],
    ['metric.customer', 'Customer coverage ring', 'Home', true],
    ['metric.rf', 'Reach frequency ring', 'Home', true],
    ['metric.remaining', 'Remaining calls', 'Home', true],
    ['metric.am', 'AM attainment', 'Home', true],
    ['metric.pm', 'PM attainment', 'Home', true],
    ['planner.mapRoute', 'Map route', 'Planner', true],
    ['planner.copyPrevious', 'Copy previous week', 'Planner', true],
    ['planner.addMeeting', 'Add meeting', 'Planner', true],
    ['planner.timeOff', 'Time off', 'Planner', true],
    ['classEngine', 'Class Engine', 'Accounts', true],
    ['requests.enabled', 'Requests', 'Requests', true],
    ['requests.medical', 'Medical requests', 'Requests', true],
    ['requests.marketing', 'Marketing requests', 'Requests', true],
    ['requests.type.device', 'Device requests', 'Requests', true],
    ['requests.type.material', 'Material requests', 'Requests', true],
    ['requests.type.followUp', 'Follow-up requests', 'Requests', true],
    ['requests.type.sample', 'Sample requests', 'Requests', true],
    ['requests.type.other', 'Other requests', 'Requests', true],
    ['hcp.products', 'HCP products', 'HCP', true],
    ['hcp.news', 'HCP news', 'HCP', true],
    ['hcp.home', 'HCP home', 'HCP', true],
    ['hcp.events', 'HCP events', 'HCP', true],
    ['hcp.requests', 'HCP requests', 'HCP', true],
    ['consent', 'Capture Consent', 'Visit', true],
    ['medicalInquiry', 'Medical Inquiry', 'Visit', true],
    ['samples', 'Sample Dispense', 'Visit', true],
    ['clm', 'CLM Presentations', 'Visit', true],
    ['coaching', 'Visit Coaching', 'Visit', true],
    ['whatsapp', 'WhatsApp Messages', 'Visit', false],
    ['surveys', 'In-call Product Survey', 'Visit', true],
    ['storeCheck', 'Store Check', 'Visit', true],
    ['orders', 'Visit Orders', 'Visit', true],
    ['fieldEmail', 'Field Email', 'Visit', true],
    ['remoteVisit', 'Remote Visit', 'Visit', true],
    ['voiceNotes', 'Voice Notes', 'Visit', true],
    ['dcr', 'Data Change Requests', 'Accounts', true],
    ['meetingExpenses', 'Meeting Expenses', 'Planner', true],
    ['activityPlan', 'Activity Plan Widget', 'Home', true],
    ['nextBestCustomer', 'Next Best Customer', 'Home', true],
    // Field AI / Agentforce stays off in the demo.
    ['agentforce', 'Agentforce', 'Home', false]
];

function featureRows() {
    return FEATURES.map(([key, name, category, enabled], i) => ({
        attributes: { type: 'Field_App_Feature__c' },
        Id: `a0XDEMO${String(i + 1).padStart(11, '0')}`,
        Name: name,
        Feature_Key__c: key,
        Description__c: `${name} for the field app.`,
        Category__c: category,
        Is_Enabled__c: enabled,
        Sort_Order__c: (i + 1) * 10
    }));
}

// ---------------------------------------------------------------------------
// Accounts: record types, class codes, bricks (same rules as fixtures/planner.js)
// ---------------------------------------------------------------------------

const RECORD_TYPES = {
    HCP: { id: '012DEMO00000000001', developerName: 'Medical_Professional_HCP', label: 'Medical Professional (HCP)', filterKey: 'HCP', isPerson: true },
    Pharmacy: { id: '012DEMO00000000002', developerName: 'Pharmacy', label: 'Pharmacy', filterKey: 'Pharmacy', isPerson: false },
    Clinic: { id: '012DEMO00000000003', developerName: 'Institution_HCO', label: 'Institution (HCO)', filterKey: 'Institution_HCO', isPerson: false },
    Hospital: { id: '012DEMO00000000003', developerName: 'Institution_HCO', label: 'Institution (HCO)', filterKey: 'Institution_HCO', isPerson: false }
};

const FILTER_LABELS = {
    Institution_HCO: 'Institution (HCO)',
    HCP: 'Medical Professional (HCP)',
    Pharmacy: 'Pharmacies'
};

function recordTypeOf(account) {
    return RECORD_TYPES[account.kind] || RECORD_TYPES.HCP;
}

function pinKindOf(account) {
    if (account.kind === 'Pharmacy') return 'pharmacy';
    if (account.kind === 'HCP') return 'hcp';
    return 'hco';
}

/** A/B/C call class to the A1–C3 code the app displays. */
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

function accountIndex(account) {
    return DEMO_ACCOUNTS.indexOf(account);
}

/**
 * Month-to-date completed calls per account (seed order). Seed visits cover the last week;
 * the rest are earlier calls this cycle, so coverage lands near 70%.
 */
const MONTH_ACTUALS = [3, 3, 2, 2, 0, 3, 2, 2, 4, 0, 2, 0];

function seedVisitsFor(accountId) {
    return demoVisits().filter((v) => v.accountId === accountId);
}

/** Earlier completed calls this month that are not in the seed visit list. */
function earlierCallsFor(account) {
    const idx = accountIndex(account);
    const seedDone = seedVisitsFor(account.id).filter((v) => v.status === 'Completed').length;
    const extra = Math.max(0, MONTH_ACTUALS[idx] - seedDone);
    const today = todayIso();
    const rows = [];
    for (let k = 0; k < extra; k += 1) {
        const date = addDays(today, -8 - ((idx * 2 + k * 5) % 12));
        rows.push({
            id: null,
            name: `V-DEMO-H${String(idx + 1).padStart(2, '0')}${k + 1}`,
            accountId: account.id,
            accountName: account.name,
            date,
            start: `${date}T10:00:00`,
            end: `${date}T11:00:00`,
            status: 'Completed'
        });
    }
    return rows;
}

/** Completed calls this month: seed completed + earlier calls, newest first. */
function completedCallsFor(account) {
    const seedDone = seedVisitsFor(account.id).filter((v) => v.status === 'Completed');
    return [...seedDone, ...earlierCallsFor(account)].sort((a, b) => (a.start < b.start ? 1 : -1));
}

function frequencyStatus(actual, target) {
    if (actual > target) return 'MCF';
    if (actual === target || (target === 0 && actual > 0)) return 'RCF';
    return 'LCF';
}

/** Share of the month already worked (drives pace / projected percent). */
function paceRatio() {
    const now = new Date();
    const days = new Date(now.getFullYear(), now.getMonth() + 1, 0).getDate();
    return Math.min(1, Math.max(0.1, now.getDate() / days));
}

function paceStatusFromProjected(projected) {
    if (projected >= 100) return 'ahead';
    if (projected >= 90) return 'on_track';
    if (projected >= 50) return 'behind';
    return 'critical';
}

const PACE_LABELS = { ahead: 'Ahead', on_track: 'On Track', behind: 'Behind', critical: 'Critical', na: 'N/A' };
const RISK_BY_PACE = { critical: 'High', behind: 'Med' };

function formatVisitDate(iso) {
    if (!iso) return '—';
    const d = new Date(iso);
    return Number.isNaN(d.getTime())
        ? '—'
        : d.toLocaleDateString('en-US', { month: 'short', day: 'numeric', year: 'numeric' });
}

/** Per-account call plan numbers shared by Home, Accounts tab and the account panels. */
function accountStats(account) {
    const target = account.frequency;
    const done = completedCallsFor(account);
    const actual = done.length;
    const today = todayIso();
    const planned = seedVisitsFor(account.id).filter((v) => v.status === 'Planned');
    const upcoming = planned.filter((v) => v.date >= today).sort((a, b) => (a.start < b.start ? -1 : 1));
    const gap = Math.max(0, target - actual);
    const projected = target > 0 ? Math.round((actual / paceRatio() / target) * 100) : null;
    const pace = target > 0 ? (actual === 0 ? 'critical' : paceStatusFromProjected(projected)) : 'na';
    return {
        target,
        actual,
        gap,
        planned: planned.length,
        plannedToday: planned.some((v) => v.date === today),
        reach: target > 0 ? Math.round((actual / target) * 100) : 0,
        projected,
        pace,
        status: frequencyStatus(actual, target),
        lastVisit: done.length ? utc(done[0].start) : null,
        nextVisit: upcoming.length ? utc(upcoming[0].start) : null
    };
}

function healthOf(account, stats) {
    if (pinKindOf(account) !== 'hcp') {
        return { score: null, status: 'na', recommendations: [] };
    }
    const score = Math.min(95, Math.round(35 + stats.reach * 0.5 + (stats.nextVisit ? 10 : 0)));
    const status = score >= 70 ? 'healthy' : score >= 45 ? 'warning' : 'unhealthy';
    const recommendations = [];
    if (stats.gap > 0) recommendations.push(`Plan ${stats.gap} more call${stats.gap === 1 ? '' : 's'} this month.`);
    if (!stats.nextVisit) recommendations.push('No upcoming visit is planned.');
    return { score, status, recommendations };
}

/** AccountsTabController.AccountsTabRow (AccountsTabController.cls:342). */
function accountsTabRow(account) {
    const rt = recordTypeOf(account);
    const stats = accountStats(account);
    const health = healthOf(account, stats);
    const code = classCodeOf(account);
    const score = round1(stats.gap * 15 + ({ A: 30, B: 20, C: 10 }[account.classCode] || 0) / 10);
    return {
        accountId: account.id,
        accountName: account.name,
        accountUrl: `/lightning/r/Account/${account.id}/view`,
        specialty: account.specialty,
        city: account.city,
        recordTypeName: rt.label,
        recordTypeDeveloperName: rt.developerName,
        accountSubtype: account.kind === 'HCP' ? account.specialty : account.kind,
        latitude: account.lat,
        longitude: account.lng,
        classification: code,
        matrixRating: code,
        potential: account.classCode === 'A' ? 'High' : account.classCode === 'B' ? 'Medium' : 'Low',
        penetration: stats.reach >= 75 ? 'High' : stats.reach >= 40 ? 'Medium' : 'Low',
        isKol: account.id === DEMO_ACCOUNTS[0].id,
        inPlanCycle: true,
        planCycleLabel: 'In',
        targetVisits: stats.target,
        actualVisits: stats.actual,
        visitGap: stats.gap,
        reachPercent: stats.reach,
        projectedPercent: stats.projected,
        paceStatus: stats.pace,
        paceStatusLabel: PACE_LABELS[stats.pace],
        frequencyStatus: stats.status,
        agentforceScore: score,
        agentforceRisk: RISK_BY_PACE[stats.pace] || 'Low',
        classificationRank: { A: 1, B: 2, C: 3 }[account.classCode] || 9,
        pinKind: pinKindOf(account),
        lastVisitDate: stats.lastVisit,
        nextVisitDate: stats.nextVisit,
        plannedVisits: stats.planned,
        addressLine: `${account.brick} main street, ${account.city}, Cairo`,
        brickId: brick702Id(account.brick),
        brickName: account.brick,
        healthScore: health.score,
        healthStatus: health.status,
        healthRecommendations: health.recommendations,
        lastVisitDisplay: formatVisitDate(stats.lastVisit),
        nextVisitDisplay: formatVisitDate(stats.nextVisit)
    };
}

const SORTERS = {
    name: (r) => r.accountName.toLowerCase(),
    classification: (r) => r.classification || 'Z',
    gap: (r) => r.visitGap || 0,
    visits: (r) => r.actualVisits || 0,
    health: (r) => (r.healthScore == null ? -1 : r.healthScore),
    lastVisit: (r) => r.lastVisitDate || '',
    agentforceScore: (r) => r.agentforceScore || 0
};

/** Rows matching the Accounts tab query params, before paging. */
function filteredTabRows(params, { ignoreRecordType = false } = {}) {
    const scope = params.get('scope') || 'both';
    if (scope === 'out') return [];
    const term = String(params.get('searchTerm') || '').trim().toLowerCase();
    const recordType = params.get('recordTypeDeveloperName');
    const classification = params.get('classification');
    const brickId = params.get('brickId');
    const specialty = params.get('specialtyFilter');
    const ids = String(params.get('accountIds') || '').split(',').map((s) => s.trim()).filter(Boolean);
    return DEMO_ACCOUNTS.filter((a) => {
        if (ids.length && !ids.some((id) => sameId(id, a.id))) return false;
        if (term && ![a.name, a.specialty, a.city, a.brick].join(' ').toLowerCase().includes(term)) return false;
        if (!ignoreRecordType && recordType && recordType !== 'All' && recordTypeOf(a).filterKey !== recordType) return false;
        if (classification && classification !== 'All' && classCodeOf(a) !== classification) return false;
        if (brickId && brickId !== 'All' && !sameId(brickId, brick702Id(a.brick)) && !sameId(brickId, brick148Id(a.city))) return false;
        if (specialty && specialty !== 'All' && a.specialty !== specialty) return false;
        return true;
    }).map(accountsTabRow);
}

function recordTypeCounts(rows) {
    const counts = [{ label: 'All', value: 'All', count: rows.length }];
    ['Institution_HCO', 'HCP', 'Pharmacy'].forEach((key) => {
        const count = rows.filter((r) => recordTypeOf(accountById(r.accountId)).filterKey === key).length;
        if (count) counts.push({ label: FILTER_LABELS[key], value: key, count });
    });
    return counts;
}

/** AccountsTabController.AccountsTabPage (AccountsTabController.cls:312). */
function accountsTabPage(params, mapOnly = false) {
    const all = filteredTabRows(params);
    const sortBy = params.get('sortBy') || 'agentforceScore';
    const dir = params.get('sortDirection') === 'asc' ? 1 : -1;
    const key = SORTERS[sortBy] || SORTERS.agentforceScore;
    const sorted = all.slice().sort((a, b) => {
        const left = key(a);
        const right = key(b);
        if (left === right) return a.accountName.localeCompare(b.accountName);
        return left > right ? dir : -dir;
    });
    const geo = sorted.filter((r) => r.latitude != null && r.longitude != null);
    const source = mapOnly ? geo : sorted;
    const offset = Math.max(0, Number(params.get('offset')) || 0);
    const pageSize = Math.max(1, Number(params.get('pageSize')) || (mapOnly ? 5 : 10));
    return {
        rows: source.slice(offset, offset + pageSize),
        totalCount: all.length,
        inPlanCount: all.filter((r) => r.inPlanCycle).length,
        outPlanCount: 0,
        behindPaceCount: all.filter((r) => r.paceStatus === 'behind' || r.paceStatus === 'critical').length,
        hasTimeCard: true,
        monthLabel: monthLabel(),
        recordTypeCounts: recordTypeCounts(filteredTabRows(params, { ignoreRecordType: true })),
        mapEligibleCount: geo.length
    };
}

function recordTypeFilterOptions() {
    return [
        { label: 'All', value: 'All' },
        { label: FILTER_LABELS.Institution_HCO, value: 'Institution_HCO' },
        { label: FILTER_LABELS.HCP, value: 'HCP' },
        { label: FILTER_LABELS.Pharmacy, value: 'Pharmacy' }
    ];
}

/** AccountsTabController.CreateRecordTypeOption (AccountsTabController.cls:53). */
function createableRecordTypes() {
    return [
        { recordTypeId: RECORD_TYPES.HCP.id, developerName: 'Medical_Professional_HCP', label: 'Medical Professional (HCP)', description: 'Doctor or other prescriber.', iconName: 'standard:person_account', isPersonAccount: true },
        { recordTypeId: RECORD_TYPES.Pharmacy.id, developerName: 'Pharmacy', label: 'Pharmacy', description: 'Retail or hospital pharmacy.', iconName: 'standard:store', isPersonAccount: false },
        { recordTypeId: RECORD_TYPES.Hospital.id, developerName: 'Institution_HCO', label: 'Institution (HCO)', description: 'Hospital, clinic or medical center.', iconName: 'standard:account', isPersonAccount: false }
    ];
}

function pick(values) {
    return values.map((v) => ({ label: v, value: v }));
}

/** AccountsTabController.WizardCreateOptions (AccountsTabController.cls:255). */
function wizardOptions() {
    const bricks148 = BRICK_148_NAMES.map((city) => ({
        brickId: brick148Id(city),
        label: city,
        level: '148',
        parentBrickId: null,
        zoneBrickId: null,
        governorate: 'Cairo',
        city
    }));
    const bricks702 = BRICK_702_NAMES.map((brick) => {
        const city = DEMO_ACCOUNTS.find((a) => a.brick === brick).city;
        return {
            brickId: brick702Id(brick),
            label: brick,
            level: '702',
            parentBrickId: brick148Id(city),
            zoneBrickId: null,
            governorate: 'Cairo',
            city
        };
    });
    return {
        specialtyOptions: pick(['Cardiology', 'Endocrinology', 'General Practice', 'Internal Medicine']),
        pharmacyTypeOptions: pick(['Retail', 'Chain', 'Hospital Pharmacy']),
        institutionTypeOptions: pick(['Hospital', 'Clinic', 'Medical Center']),
        governorateOptions: pick(['Cairo']),
        areaOptions: pick(BRICK_148_NAMES),
        bricks70: [],
        bricks148,
        bricks702
    };
}

/** AccountsTabController.MasterSearchRow (AccountsTabController.cls:68). */
function masterSearch(body = {}) {
    const term = String(body.searchTerm || '').trim().toLowerCase();
    return DEMO_ACCOUNTS.filter((a) => !term || a.name.toLowerCase().includes(term) || a.phone.replace(/\s/g, '').includes(term.replace(/\s/g, '')))
        .slice(0, 20)
        .map((a, i) => ({
            accountId: a.id,
            name: a.name,
            accountNumber: `DEMO-${String(i + 1).padStart(4, '0')}`,
            brickName: a.brick,
            location: `${a.city}, Cairo`,
            specialty: a.specialty,
            phone: a.phone,
            recordTypeLabel: recordTypeOf(a).label,
            matchKind: 'name',
            score: 90 - i,
            isPersonAccount: recordTypeOf(a).isPerson
        }));
}

function csvExport(params) {
    const rows = filteredTabRows(params);
    const header = 'Account,Specialty,City,Class,Target,Actual,Gap';
    const lines = rows.map((r) =>
        [r.accountName, r.specialty, r.city, r.classification, r.targetVisits, r.actualVisits, r.visitGap]
            .map((v) => `"${String(v == null ? '' : v).replace(/"/g, '""')}"`)
            .join(',')
    );
    return [header, ...lines].join('\n');
}

/** AccountDuplicateCheckService result read by c/accountDuplicateCheck. */
function duplicateCheck(accountId) {
    const account = accountById(accountId);
    return {
        accountId,
        accountName: account ? account.name : null,
        recordTypeName: account ? recordTypeOf(account).label : null,
        hasMatches: false,
        highestPercent: 0,
        matches: [],
        canReport: true,
        canMerge: false
    };
}

// ---------------------------------------------------------------------------
// Home dashboard (PlannerMobileRestService.cls:1012 buildHomeDashboard)
// ---------------------------------------------------------------------------

/** FieldRepHomeController.AccountCoverageRow (FieldRepHomeController.cls:57). */
function coverageRow(account) {
    const rt = recordTypeOf(account);
    const stats = accountStats(account);
    const code = classCodeOf(account);
    return {
        accountId: account.id,
        accountName: account.name,
        specialty: account.specialty,
        city: account.city,
        latitude: account.lat,
        longitude: account.lng,
        potential: account.classCode === 'A' ? 'High' : account.classCode === 'B' ? 'Medium' : 'Low',
        penetration: stats.reach >= 75 ? 'High' : stats.reach >= 40 ? 'Medium' : 'Low',
        matrixRating: code,
        calculatedClassification: code,
        potentialityOnTarget: account.classCode === 'C' ? 'Low' : 'High',
        actualVisits: stats.actual,
        targetVisits: stats.target,
        visitGap: stats.gap,
        reachPercent: stats.reach,
        frequencyStatus: stats.status,
        isVisited: stats.actual > 0,
        recordTypeDeveloperName: rt.developerName,
        recordTypeLabel: rt.label,
        accountSubtype: account.kind === 'HCP' ? account.specialty : account.kind,
        hcpClassification: code,
        brickId: brick702Id(account.brick),
        brickName: account.brick
    };
}

function pct(part, whole) {
    return whole > 0 ? round1((part / whole) * 100) : 0;
}

/** FieldRepHomeController.HomeMetrics (FieldRepHomeController.cls:21) plus fields getHomeMetrics.js expects. */
function homeMetrics() {
    const rows = DEMO_ACCOUNTS.map((a) => ({ account: a, stats: accountStats(a) }));
    const sum = (list, fn) => list.reduce((acc, item) => acc + fn(item), 0);
    const target = sum(rows, (r) => r.stats.target);
    const actual = sum(rows, (r) => r.stats.actual);
    const covered = sum(rows, (r) => Math.min(r.stats.actual, r.stats.target));
    const today = todayIso();
    const planned = demoVisits().filter((v) => v.status === 'Planned' && v.date >= today).length;
    const am = rows.filter((r) => r.account.channel === 'AM');
    const pm = rows.filter((r) => r.account.channel === 'PM');
    const plannedFor = (list) =>
        demoVisits().filter((v) => v.status === 'Planned' && v.date >= today && list.some((r) => r.account.id === v.accountId)).length;
    const classes = [...new Set(DEMO_ACCOUNTS.map(classCodeOf))].sort();
    const byClassification = classes.map((code) => {
        const list = rows.filter((r) => classCodeOf(r.account) === code);
        const t = sum(list, (r) => r.stats.target);
        return {
            classification: code,
            visitCoveragePercent: pct(sum(list, (r) => Math.min(r.stats.actual, r.stats.target)), t),
            customerCoveragePercent: pct(list.filter((r) => r.stats.actual > 0).length, list.length),
            lfPercent: pct(list.filter((r) => r.stats.status === 'LCF').length, list.length),
            rfPercent: pct(list.filter((r) => r.stats.status === 'RCF').length, list.length),
            mfPercent: pct(list.filter((r) => r.stats.status === 'MCF').length, list.length),
            accountCount: list.length,
            actualVisits: sum(list, (r) => r.stats.actual),
            targetVisits: t
        };
    });
    const amTarget = sum(am, (r) => r.stats.target);
    const amActual = sum(am, (r) => r.stats.actual);
    const pmTarget = sum(pm, (r) => r.stats.target);
    const pmActual = sum(pm, (r) => r.stats.actual);
    return {
        visitCoveragePercent: pct(covered, target),
        customerCoveragePercent: pct(rows.filter((r) => r.stats.actual > 0).length, rows.length),
        lfPercentTotal: pct(rows.filter((r) => r.stats.status === 'LCF').length, rows.length),
        rfPercentTotal: pct(rows.filter((r) => r.stats.status !== 'LCF').length, rows.length),
        mfPercentTotal: pct(rows.filter((r) => r.stats.status === 'MCF').length, rows.length),
        actualVisitsTotal: actual,
        targetVisitsTotal: target,
        plannedVisitsTotal: planned,
        remainingCalls: sum(rows, (r) => r.stats.gap),
        amAttainmentPercent: pct(amActual, amTarget),
        amActualVisits: amActual,
        amTargetVisits: amTarget,
        amPlannedVisits: plannedFor(am),
        pmAttainmentPercent: pct(pmActual, pmTarget),
        pmActualVisits: pmActual,
        pmTargetVisits: pmTarget,
        pmPlannedVisits: plannedFor(pm),
        targetCallRate: 8,
        targetAmCallRate: 3,
        targetPmCallRate: 5,
        actualCallRate: 6.5,
        actualAmCallRate: 2.5,
        actualPmCallRate: 4,
        byClassification
    };
}

/** FieldRepHomeController.PerformanceGamification (FieldRepHomeController.cls:124). */
function gamification() {
    return {
        userFirstName: 'Demo',
        streaks: { activityStreak: 5, coverageStreak: 2 },
        badges: [
            { badgeId: 'coverage_champion', earned: false, progressPercent: 72 },
            { badgeId: 'on_target', earned: true, progressPercent: 100 },
            { badgeId: 'class_a_ace', earned: false, progressPercent: 80 },
            { badgeId: 'streak_starter', earned: true, progressPercent: 100 },
            { badgeId: 'perfect_week', earned: false, progressPercent: 60 },
            { badgeId: 'early_bird', earned: true, progressPercent: 100 }
        ]
    };
}

/** FieldRepHomeController.PerformanceRankings (FieldRepHomeController.cls:146). Names are invented. */
function rankings() {
    const mine = homeMetrics().visitCoveragePercent;
    const icons = ['🥇', '🥈', '🥉'];
    const peers = [
        ['005DEMO00000000011', 'Demo Rep Salma', 84],
        ['005DEMO00000000012', 'Demo Rep Ahmed', 78],
        [DEMO_USER_ID, 'Demo Field Rep', mine],
        ['005DEMO00000000013', 'Demo Rep Mona', 66],
        ['005DEMO00000000014', 'Demo Rep Tamer', 61]
    ];
    const entry = ([userId, name, coverage], i) => ({
        rank: i + 1,
        name,
        userId,
        coveragePercent: coverage,
        isCurrentUser: userId === DEMO_USER_ID,
        badgeIcon: icons[i] || null
    });
    const company = [
        ['005DEMO00000000021', 'Demo Rep Hoda', 91],
        ['005DEMO00000000022', 'Demo Rep Karim', 88],
        ['005DEMO00000000011', 'Demo Rep Salma', 84],
        ['005DEMO00000000023', 'Demo Rep Rana', 82],
        ['005DEMO00000000012', 'Demo Rep Ahmed', 78]
    ];
    return {
        buName: DEMO_TERRITORY.line,
        buRank: 3,
        buTotal: 8,
        companyRank: 9,
        companyTotal: 36,
        myCoveragePercent: mine,
        top5InBu: peers.map(entry),
        top5Company: company.map(entry),
        personAbove: { name: 'Demo Rep Ahmed', rank: 2, coveragePercent: 78, gapPercent: round1(78 - mine) },
        isFirstInBu: false
    };
}

function workingDaysSoFar() {
    const now = new Date();
    let count = 0;
    for (let day = 1; day <= now.getDate(); day += 1) {
        const dow = new Date(now.getFullYear(), now.getMonth(), day).getDay();
        if (dow !== 5 && dow !== 6) count += 1;
    }
    return count;
}

/** FieldRepHomeController.MonthlyTimecardSummary (FieldRepHomeController.cls:398). */
function timecardSummary() {
    const metrics = homeMetrics();
    const fieldDays = Math.max(1, workingDaysSoFar() - 1);
    const submittedCalls = metrics.actualVisitsTotal;
    const potentialVisits = metrics.plannedVisitsTotal;
    return {
        fieldDays,
        coachedDays: 1,
        coachingDays: 0,
        activityDays: fieldDays,
        submittedCalls,
        potentialVisits,
        completedMeetings: 0,
        potentialMeetings: 0,
        completedActivities: submittedCalls,
        potentialActivities: potentialVisits,
        leaveDays: 0,
        sickLeaveDays: 0,
        annualVacationDays: 0,
        conferenceDays: 0,
        publicHolidayDays: 0,
        isManager: false,
        monthLabel: monthLabel()
    };
}

function dayLabel(dateIso) {
    return new Date(`${dateIso}T00:00:00`).toLocaleDateString('en-US', { weekday: 'short', month: 'short', day: 'numeric' });
}

function visitDetailRow(v, i) {
    return {
        key: v.id || `${v.name}-${i}`,
        title: v.accountName,
        subtitle: dayLabel(v.date),
        meta: v.status === 'Planned' ? 'Scheduled' : 'Completed',
        recordId: v.id || null,
        objectApiName: v.id ? 'Visit__c' : null
    };
}

/** FieldRepHomeController.MonthlyTimecardDetails (FieldRepHomeController.cls:434). */
function timecardDetails(tileId) {
    const titles = {
        field: 'Field days',
        coached: 'Coached',
        coaching: 'Coaching',
        activities: 'Activities recorded',
        completed: 'Completed activities',
        potential: 'Potential activities'
    };
    const completed = DEMO_ACCOUNTS.flatMap(completedCallsFor).sort((a, b) => (a.start < b.start ? 1 : -1));
    const today = todayIso();
    const potential = demoVisits().filter((v) => v.status === 'Planned' && v.date >= today);
    let groups = [];
    if (tileId === 'completed' || tileId === 'activities' || tileId === 'field') {
        if (tileId === 'completed') {
            groups = [{ key: 'visits', label: 'Visits', totalLabel: String(completed.length), rows: completed.map(visitDetailRow) }];
        } else {
            const byDay = new Map();
            completed.forEach((v) => byDay.set(v.date, (byDay.get(v.date) || 0) + 1));
            const rows = [...byDay.entries()].map(([date, count]) => ({
                key: date,
                title: dayLabel(date),
                subtitle: `${count} call${count === 1 ? '' : 's'}`,
                meta: 'Field day',
                recordId: null,
                objectApiName: null
            }));
            groups = [{ key: 'days', label: 'Days', totalLabel: String(rows.length), rows }];
        }
    } else if (tileId === 'potential') {
        groups = [{ key: 'visits', label: 'Scheduled visits', totalLabel: String(potential.length), rows: potential.map(visitDetailRow) }];
    } else if (tileId === 'coached') {
        const date = addDays(today, -4);
        groups = [{
            key: 'coaching',
            label: 'Coaching days',
            totalLabel: '1',
            rows: [{ key: 'coached-1', title: dayLabel(date), subtitle: `Field coaching with ${DEMO_TERRITORY.managerName}`, meta: 'Coached', recordId: null, objectApiName: null }]
        }];
    }
    return {
        tileId,
        title: titles[tileId] || 'Details',
        monthLabel: monthLabel(),
        emptyMessage: 'Nothing recorded for this card yet this month.',
        groups
    };
}

/** FieldRepHomeController.MonthlyLeaveDetails (FieldRepHomeController.cls:453). No leave taken this month. */
function leaveDetails() {
    return { approvedDays: 0, pendingDays: 0, approvedRows: [], pendingRows: [], monthLabel: monthLabel() };
}

/** FieldPlannerController.VisitSummary, same shape as fixtures/planner.js visitSummary. */
function visitSummary(visit) {
    const account = visit.account || accountById(visit.accountId);
    const rt = account ? recordTypeOf(account) : RECORD_TYPES.HCP;
    return {
        id: visit.id,
        name: visit.name,
        accountId: visit.accountId,
        accountName: visit.accountName,
        status: visit.status === 'Planned' ? 'Scheduled' : visit.status,
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

function todayVisits(dateIso) {
    const day = dateIso || todayIso();
    return demoVisits().filter((v) => v.date === day).map(visitSummary);
}

/** FieldRepHomeController.NextBestCustomerRow (FieldRepHomeController.cls:90). */
function nextBestCustomers(limit) {
    const rows = DEMO_ACCOUNTS.map((a) => ({ account: a, stats: accountStats(a) }))
        .filter((r) => r.stats.gap > 0)
        .map(({ account, stats }) => {
            const code = classCodeOf(account);
            const weight = { A: 30, B: 20, C: 10 }[account.classCode] || 0;
            const urgency = stats.gap >= 3 || (account.classCode === 'A' && stats.gap >= 2)
                ? 'High'
                : stats.gap >= 2 || account.classCode === 'A' ? 'Medium' : 'Low';
            const parts = [`${stats.gap} call${stats.gap === 1 ? '' : 's'} behind plan`, `Class ${code}`];
            if (!stats.planned) parts.push('Not planned yet');
            else if (stats.plannedToday) parts.push('Planned today');
            return {
                rank: 0,
                accountId: account.id,
                accountName: account.name,
                specialty: account.specialty,
                actualVisits: stats.actual,
                targetVisits: stats.target,
                visitGap: stats.gap,
                planned: stats.planned > 0,
                plannedToday: stats.plannedToday,
                score: weight + stats.gap * 15,
                potential: account.classCode === 'A' ? 'High' : account.classCode === 'B' ? 'Medium' : 'Low',
                penetration: stats.reach >= 40 ? 'Medium' : 'Low',
                calculatedClassification: code,
                urgency,
                description: parts.join(' · ')
            };
        })
        .sort((a, b) => b.score - a.score || a.accountName.localeCompare(b.accountName));
    return rows.slice(0, Math.max(1, limit || 5)).map((row, i) => ({ ...row, rank: i + 1 }));
}

/** HomeOfficeMessageController.HomeOfficeMessageRow (HomeOfficeMessageController.cls:6). */
function officeMessages() {
    const today = todayIso();
    return [
        {
            recordId: 'a0HDEMO00000000001',
            subject: 'Cardiora detailing focus this month',
            body: 'Lead with blood pressure control data and check sample stock before each call.',
            authorName: 'Demo Marketing Team',
            publishedOn: utc(`${today}T08:00:00`),
            publishedLabel: 'Today',
            priority: 'High',
            audienceLabel: DEMO_TERRITORY.line,
            isHighPriority: true
        },
        {
            recordId: 'a0HDEMO00000000002',
            subject: 'Cycle meeting next week',
            body: 'District cycle meeting on Sunday at 9:00. Bring your call plan for the next cycle.',
            authorName: DEMO_TERRITORY.managerName,
            publishedOn: utc(`${addDays(today, -3)}T09:30:00`),
            publishedLabel: '',
            priority: 'Normal',
            audienceLabel: DEMO_TERRITORY.district,
            isHighPriority: false
        }
    ];
}

function homeDashboard() {
    return {
        asOf: todayIso(),
        userId: DEMO_USER_ID,
        metrics: homeMetrics(),
        gamification: gamification(),
        rankings: rankings(),
        accountCoverageRows: DEMO_ACCOUNTS.map(coverageRow),
        monthlyTimecard: timecardSummary(),
        messages: officeMessages(),
        todayVisits: todayVisits(),
        todayTimeOff: [],
        nextBestCustomers: nextBestCustomers(5)
    };
}

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

// ---------------------------------------------------------------------------
// Notifications and Chatter user
// ---------------------------------------------------------------------------

function notifications() {
    const today = todayIso();
    const rows = [
        {
            id: '0MLDEMO00000000001',
            type: 'visit_reminder',
            messageTitle: 'Visit reminder',
            messageBody: `${DEMO_ACCOUNTS[2].name} is planned for today at 11:30.`,
            mostRecentActivityDate: utc(`${today}T07:45:00`),
            read: false,
            seen: false,
            target: DEMO_ACCOUNTS[2].id,
            url: `/lightning/r/Account/${DEMO_ACCOUNTS[2].id}/view`
        },
        {
            id: '0MLDEMO00000000002',
            type: 'learning',
            messageTitle: 'New course assigned',
            messageBody: `${DEMO_COURSES[1].title} is waiting in My Learning.`,
            mostRecentActivityDate: utc(`${addDays(today, -1)}T12:10:00`),
            read: false,
            seen: false,
            target: null,
            url: ''
        },
        {
            id: '0MLDEMO00000000003',
            type: 'plan_approved',
            messageTitle: 'Weekly plan approved',
            messageBody: `${DEMO_TERRITORY.managerName} approved your plan for this week.`,
            mostRecentActivityDate: utc(`${addDays(today, -2)}T16:20:00`),
            read: true,
            seen: true,
            target: null,
            url: ''
        }
    ];
    return { notifications: rows, unseenCount: rows.filter((r) => !r.seen).length, currentPageUrl: null, nextPageUrl: null };
}

function chatterMe() {
    return {
        id: DEMO_USER_ID,
        name: 'Demo Field Rep',
        displayName: 'Demo Field Rep',
        firstName: 'Demo',
        lastName: 'Field Rep',
        title: 'Medical Representative',
        email: 'review.demo@zeta-copilot.app',
        username: 'review.demo@zeta-copilot.app',
        companyName: 'Demo Pharma',
        managerId: DEMO_MANAGER_ID,
        managerName: DEMO_TERRITORY.managerName,
        isActive: true,
        type: 'User',
        userType: 'Internal',
        photo: { smallPhotoUrl: null, mediumPhotoUrl: null, fullEmailPhotoUrl: null, photoVersionId: null }
    };
}

// ---------------------------------------------------------------------------
// Account record (record.html UI API read and raw sObject read)
// ---------------------------------------------------------------------------

function accountFields(account) {
    const rt = recordTypeOf(account);
    const nameParts = account.name.replace(/^Dr\.\s*/, '').split(' ');
    return {
        Id: account.id,
        Name: account.name,
        FirstName: rt.isPerson ? nameParts[0] : null,
        LastName: rt.isPerson ? nameParts.slice(1).join(' ') : null,
        IsPersonAccount: rt.isPerson,
        RecordTypeId: rt.id,
        Phone: account.phone,
        BillingStreet: `${account.brick} main street`,
        BillingCity: account.city,
        BillingState: 'Cairo',
        BillingCountry: 'Egypt',
        BillingLatitude: account.lat,
        BillingLongitude: account.lng,
        Specialty__c: account.specialty,
        Classification__c: classCodeOf(account),
        Account_Stage__c: 'Active',
        Stage_Send_Back_Message__c: null,
        Stage_History__c: null,
        Inactive_Reason__c: null,
        Duplicate_Of__c: null,
        Rating: account.classCode === 'A' ? 'Hot' : account.classCode === 'B' ? 'Warm' : 'Cold',
        AnnualRevenue: null,
        NumberOfEmployees: null,
        OwnerId: DEMO_USER_ID
    };
}

/** SOQL / sObject row for an Account, with relationship objects. */
function accountRecord(account) {
    const rt = recordTypeOf(account);
    return {
        attributes: { type: 'Account', url: `/services/data/v62.0/sobjects/Account/${account.id}` },
        ...accountFields(account),
        RecordType: { attributes: { type: 'RecordType' }, Id: rt.id, Name: rt.label, DeveloperName: rt.developerName },
        Duplicate_Of__r: null,
        Owner: { attributes: { type: 'User' }, Id: DEMO_USER_ID, Name: 'Demo Field Rep' }
    };
}

const RECORD_UI_FIELDS = [
    ['Name', 'Account Name', 'String'],
    ['Specialty__c', 'Specialty', 'Picklist'],
    ['Classification__c', 'Classification', 'String'],
    ['Phone', 'Phone', 'Phone'],
    ['BillingStreet', 'Street', 'TextArea'],
    ['BillingCity', 'City', 'String'],
    ['Account_Stage__c', 'Stage', 'Picklist'],
    ['Rating', 'Rating', 'Picklist']
];

/** UI API record-ui read by public/record.js extractLayoutGroups. */
function accountRecordUi(account) {
    const values = accountFields(account);
    const rt = recordTypeOf(account);
    const fields = {};
    const fieldInfos = {};
    RECORD_UI_FIELDS.forEach(([api, label, dataType]) => {
        const value = values[api];
        fields[api] = { value, displayValue: value == null ? null : String(value) };
        fieldInfos[api] = { apiName: api, label, dataType };
    });
    const row = (items) => ({ layoutItems: items.map(([api, label]) => ({ label, layoutComponents: [{ componentType: 'Field', apiName: api }] })) });
    return {
        records: {
            [account.id]: { apiName: 'Account', id: account.id, recordTypeId: rt.id, fields }
        },
        objectInfos: { Account: { apiName: 'Account', label: 'Account', fields: fieldInfos } },
        layouts: {
            Account: {
                [rt.id]: {
                    Full: {
                        View: {
                            sections: [
                                { heading: 'Account Information', useHeading: true, layoutRows: [row(RECORD_UI_FIELDS.slice(0, 2)), row(RECORD_UI_FIELDS.slice(2, 4))] },
                                { heading: 'Address & Status', useHeading: true, layoutRows: [row(RECORD_UI_FIELDS.slice(4, 6)), row(RECORD_UI_FIELDS.slice(6, 8))] }
                            ]
                        }
                    }
                }
            }
        }
    };
}

function globalDescribe() {
    const list = [
        ['Account', 'Account', '001'],
        ['User', 'User', '005'],
        ['Visit__c', 'Visit', 'a0V'],
        ['Learning_Material_Instance__c', 'Learning Material Instance', 'a0L'],
        ['Product2', 'Product', '01t']
    ];
    return {
        encoding: 'UTF-8',
        maxBatchSize: 200,
        sobjects: list.map(([name, label, keyPrefix]) => ({ name, label, keyPrefix, queryable: true, retrieveable: true }))
    };
}

// ---------------------------------------------------------------------------
// SOQL helpers
// ---------------------------------------------------------------------------

/** Literal values a SOQL filters `field` on (`= 'x'` or `IN ('x','y')`), or null when unfiltered. */
function filterValues(soql, field) {
    const eq = new RegExp(`(?<![\\w.])${field}\\s*=\\s*'([^']*)'`, 'i').exec(soql);
    if (eq) return [eq[1]];
    const inList = new RegExp(`(?<![\\w.])${field}\\s+IN\\s*\\(([^)]*)\\)`, 'i').exec(soql);
    if (inList) {
        return [...inList[1].matchAll(/'([^']*)'/g)].map((m) => m[1]);
    }
    return null;
}

function filterBy(rows, soql, field, get) {
    const values = filterValues(soql, field);
    if (!values) return rows;
    return rows.filter((row) => values.some((v) => sameId(v, get(row))));
}

function isDemoUser(soql, field) {
    const values = filterValues(soql, field);
    return !values || values.some((v) => sameId(v, DEMO_USER_ID));
}

// ---------------------------------------------------------------------------
// Users and territories
// ---------------------------------------------------------------------------

function userRows() {
    const user = (id, first, last, title, profile, managerId) => ({
        attributes: { type: 'User' },
        Id: id,
        Name: `${first} ${last}`,
        FirstName: first,
        LastName: last,
        Title: title,
        Username: `${first}.${last}`.toLowerCase().replace(/\s+/g, '') + '@demo.invalid',
        Email: `${first}.${last}`.toLowerCase().replace(/\s+/g, '') + '@demo.invalid',
        IsActive: true,
        ManagerId: managerId,
        Manager: managerId ? { attributes: { type: 'User' }, Id: managerId, Name: DEMO_TERRITORY.managerName } : null,
        Profile: { attributes: { type: 'Profile' }, Name: profile },
        SmallPhotoUrl: null,
        MediumPhotoUrl: null,
        FullPhotoUrl: null,
        TimeZoneSidKey: 'Africa/Cairo',
        LanguageLocaleKey: 'en_US'
    });
    const rep = user(DEMO_USER_ID, 'Demo', 'Field Rep', 'Medical Representative', 'Field Rep', DEMO_MANAGER_ID);
    rep.Username = 'review.demo@zeta-copilot.app';
    rep.Email = 'review.demo@zeta-copilot.app';
    return [rep, user(DEMO_MANAGER_ID, 'Demo District', 'Manager', 'District Manager', 'Field Manager', null)];
}

function territoryRows() {
    const territory = (id, name, externalId, type, parentId, parentName) => ({
        attributes: { type: 'Territory2' },
        Id: id,
        Name: name,
        DeveloperName: externalId.replace(/-/g, '_'),
        External_ID__c: externalId,
        Territory_Type__c: type,
        ParentTerritory2Id: parentId,
        ParentTerritory2: parentId ? { attributes: { type: 'Territory2' }, Id: parentId, Name: parentName, ParentTerritory2Id: null, ParentTerritory2: null } : null,
        Territory2Type: { attributes: { type: 'Territory2Type' }, MasterLabel: type, DeveloperName: type }
    });
    return [
        territory(DISTRICT_ID, DEMO_TERRITORY.district, 'DEMO-DM-CAIRO', 'District', null, null),
        territory(DEMO_TERRITORY.id, DEMO_TERRITORY.name, 'DEMO-CARDIO-CAIRO-EAST', 'Territory', DISTRICT_ID, DEMO_TERRITORY.district)
    ];
}

function seatRows() {
    const territories = territoryRows();
    const users = userRows();
    const seat = (id, user, territory, role) => ({
        attributes: { type: 'UserTerritory2Association' },
        Id: id,
        UserId: user.Id,
        User: { attributes: { type: 'User' }, Id: user.Id, Name: user.Name, Title: user.Title, IsActive: true },
        Territory2Id: territory.Id,
        Territory2: territory,
        RoleInTerritory2: role,
        IsActive: true
    });
    return [
        seat('0R0DEMO00000000001', users[0], territories[1], 'Medical Rep'),
        seat('0R0DEMO00000000002', users[1], territories[0], 'District Manager')
    ];
}

// ---------------------------------------------------------------------------
// Account panels: territory ratings, products, affiliations, visits
// ---------------------------------------------------------------------------

const DETAIL_PRODUCTS = DEMO_PRODUCTS.filter((p) => p.type === 'Detail');

function productRows() {
    return DEMO_PRODUCTS.map((p) => ({
        attributes: { type: 'Product2' },
        Id: p.id,
        Name: p.name,
        ProductCode: p.code,
        External_ID__c: p.code,
        Family: p.brand,
        IsActive: true,
        Product_Image_URL__c: null,
        Description: `${p.brand} (demo product)`
    }));
}

function alignmentRows() {
    return DETAIL_PRODUCTS.map((p, i) => ({
        attributes: { type: 'Product_Territory_Alignment__c' },
        Id: `a0YDEMO${String(i + 1).padStart(11, '0')}`,
        Product2_Id__c: p.id,
        Territory2_Id__c: DEMO_TERRITORY.id,
        Is_Active__c: true
    }));
}

function atfRows() {
    return DEMO_ACCOUNTS.map((a, i) => {
        const code = classCodeOf(a);
        return {
            attributes: { type: 'Account_Territory_Fields__c' },
            Id: `a0ZDEMO${String(i + 1).padStart(11, '0')}`,
            Account__c: a.id,
            Territory2_Id__c: DEMO_TERRITORY.id,
            Is_Active__c: true,
            Is_KOL__c: i === 0,
            KOL_In_What__c: i === 0 ? 'Key Scientific Leader' : null,
            Has_KOLs__c: a.kind === 'Hospital',
            KOL_Profile__c: null,
            Is_Speaker__c: i === 0,
            HCP_Classification__c: a.kind === 'HCP' ? code : null,
            Potential__c: a.classCode === 'A' ? 80 : a.classCode === 'B' ? 55 : 30,
            Penetration__c: Math.min(100, accountStats(a).reach),
            Matrix_Rating__c: code,
            Classification__c: code
        };
    });
}

function atpfRows() {
    return DEMO_ACCOUNTS.flatMap((a, i) =>
        DETAIL_PRODUCTS.map((p, j) => {
            const base = { A: 70, B: 50, C: 30 }[a.classCode] || 40;
            return {
                attributes: { type: 'Account_Territory_Product_Fields__c' },
                Id: `a0WDEMO${String(i * 10 + j + 1).padStart(11, '0')}`,
                Account__c: a.id,
                Product2_Id__c: p.id,
                Territory2_Id__c: DEMO_TERRITORY.id,
                Is_Active__c: true,
                Potential__c: base + j * 5,
                Penetration__c: Math.max(10, base - 20 - j * 5),
                Rx_Per_Week__c: Math.max(1, Math.round(base / 10) - j),
                Adoption__c: j === 0 ? 'Advocate' : 'Trial',
                Loyalty__c: j === 0 ? 'High' : 'Medium',
                Product_Matrix_Rating__c: classCodeOf(a),
                Target_Visit_Frequency__c: a.frequency,
                Notes__c: null
            };
        })
    );
}

function ratingLayoutRows() {
    const territoryFields = [
        { objectApiName: 'Account_Territory_Fields__c', fieldApiName: 'HCP_Classification__c', label: 'Classification', widget: 'picklist', order: 10 },
        { objectApiName: 'Account_Territory_Fields__c', fieldApiName: 'Is_Speaker__c', label: 'Is Speaker', widget: 'toggle', order: 20 },
        { objectApiName: 'Account_Territory_Fields__c', fieldApiName: 'Is_KOL__c', label: 'Is KOL', widget: 'toggle', order: 30 }
    ];
    const productFields = [
        { objectApiName: 'Account_Territory_Product_Fields__c', fieldApiName: 'Potential__c', label: 'Potentiality', widget: 'numberDonut', order: 5 },
        { objectApiName: 'Account_Territory_Product_Fields__c', fieldApiName: 'Penetration__c', label: 'Penetration', widget: 'numberDonut', order: 8 },
        { objectApiName: 'Account_Territory_Product_Fields__c', fieldApiName: 'Rx_Per_Week__c', label: 'Rx per week', widget: 'number', order: 20 }
    ];
    const layout = (n, variant, sections) => ({
        attributes: { type: 'CLM_Rating_Layout__c' },
        Id: `a0RDEMO${String(n).padStart(11, '0')}`,
        Name: `Demo ${variant} rating layout`,
        Status__c: 'Deployed',
        LastModifiedDate: `${addDays(todayIso(), -20)}T08:00:00.000+0000`,
        Fields_JSON__c: JSON.stringify({ accountVariant: variant, sections })
    });
    return [
        layout(1, 'HCP', { account: [], accountTerritory: territoryFields, accountTerritoryProduct: productFields }),
        layout(2, 'HCO', { account: [], accountTerritory: territoryFields.slice(1), accountTerritoryProduct: productFields })
    ];
}

/** HCP ↔ HCO / pharmacy links, all within the demo territory. */
const AFFILIATIONS = [
    [2, 11, 'Works At', 'Consultant', 'Strong'],
    [3, 11, 'Works At', 'Specialist', 'Strong'],
    [6, 11, 'Works At', 'Head of Unit', 'Strong'],
    [1, 8, 'Works At', 'Consultant', 'Medium'],
    [1, 9, 'Prescribes Via', 'Prescriber', 'Strong'],
    [4, 9, 'Prescribes Via', 'Prescriber', 'Medium'],
    [7, 9, 'Prescribes Via', 'Prescriber', 'Medium'],
    [3, 10, 'Prescribes Via', 'Prescriber', 'Weak']
];

function affiliationRows() {
    const rel = (account) => {
        const rt = recordTypeOf(account);
        return {
            attributes: { type: 'Account' },
            Id: account.id,
            Name: account.name,
            RecordType: { attributes: { type: 'RecordType' }, Name: rt.label, DeveloperName: rt.developerName }
        };
    };
    return AFFILIATIONS.map(([from, to, type, role, strength], i) => {
        const primary = DEMO_ACCOUNTS[from - 1];
        const related = DEMO_ACCOUNTS[to - 1];
        return {
            attributes: { type: 'Account_Affiliation__c' },
            Id: `a0FDEMO${String(i + 1).padStart(11, '0')}`,
            Primary_Account__c: primary.id,
            Related_Account__c: related.id,
            Primary_Account__r: rel(primary),
            Related_Account__r: rel(related),
            Affiliation_Type__c: type,
            Role__c: role,
            Strength__c: strength,
            Description__c: `${primary.name} — ${type.toLowerCase()} ${related.name}`,
            Is_Active__c: true,
            Outside_Territory__c: false
        };
    });
}

/** Visit__c rows for one account (account panels and record.html activity). */
function accountVisitRows(accountId, soql) {
    const account = accountById(accountId);
    if (!account) return [];
    const today = todayIso();
    const seed = seedVisitsFor(account.id).map((v) => ({ ...v, history: false }));
    const all = [...seed, ...earlierCallsFor(account).map((v) => ({ ...v, history: true }))];
    let rows = all;
    if (/Start_Date__c\s*>=/i.test(soql)) {
        rows = all.filter((v) => v.status === 'Planned' && v.date >= today);
    } else if (/Start_Date__c\s*</i.test(soql)) {
        rows = all.filter((v) => v.date < today || v.status === 'Completed');
    }
    const asc = /ORDER BY\s+Start_Date__c\s+ASC/i.test(soql);
    rows.sort((a, b) => (a.start < b.start ? (asc ? -1 : 1) : asc ? 1 : -1));
    return rows.map((v, i) => ({
        attributes: { type: 'Visit__c' },
        Id: v.id || `a0VDEMOH${String(accountIndex(account) + 1).padStart(4, '0')}${String(i + 1).padStart(6, '0')}`,
        Name: v.name,
        Status__c: v.status === 'Planned' ? 'Scheduled' : v.status,
        Start_Date__c: utc(v.start),
        End_Date__c: utc(v.end),
        Account__c: account.id,
        Account__r: { attributes: { type: 'Account' }, Id: account.id, Name: account.name },
        OwnerId: DEMO_USER_ID
    }));
}

// ---------------------------------------------------------------------------
// My Learning (learningShared.js)
// ---------------------------------------------------------------------------

const LESSON_TITLES = [
    ['Mechanism of action', 'Dosing and titration', 'Key messages quiz review'],
    ['Lipid targets in practice', 'Handling objections', 'Launch call flow'],
    ['Samples and documentation', 'Gifts and hospitality rules', 'Reporting adverse events']
];

function courseMaterialId(n) {
    return `a0MDEMO${String(n).padStart(11, '0')}`;
}

function lessonMaterialId(n, l) {
    return `a0MDEMO${String(n * 10 + l).padStart(11, '0')}`;
}

function lessonStatus(course, l) {
    if (course.progress >= 100) return 'Completed';
    if (course.progress <= 0) return 'Not Started';
    const done = Math.floor((course.progress / 100) * 3);
    if (l <= done) return 'Completed';
    return l === done + 1 ? 'In Progress' : 'Not Started';
}

function learningMaterials() {
    return DEMO_COURSES.flatMap((course, i) => {
        const n = i + 1;
        const parent = {
            attributes: { type: 'Learning_Material__c' },
            Id: courseMaterialId(n),
            Name: course.title,
            Title__c: course.title,
            Description__c: course.description,
            Material_Type__c: 'Course',
            Material_URL__c: null,
            Duration__c: 30,
            Parent_Material__c: null,
            Issue_Certificate__c: true,
            Active__c: true,
            Effective_End_Date__c: addDays(todayIso(), 45)
        };
        const lessons = LESSON_TITLES[i].map((title, k) => ({
            attributes: { type: 'Learning_Material__c' },
            Id: lessonMaterialId(n, k + 1),
            Name: title,
            Title__c: title,
            Description__c: `${course.title}: ${title.toLowerCase()}.`,
            Material_Type__c: 'Article',
            Material_URL__c: null,
            Duration__c: 10,
            Parent_Material__c: courseMaterialId(n),
            Issue_Certificate__c: false,
            Active__c: true,
            Effective_End_Date__c: null
        }));
        return [parent, ...lessons];
    });
}

function learningInstances() {
    const materials = new Map(learningMaterials().map((m) => [m.Id, m]));
    const today = todayIso();
    const learner = { attributes: { type: 'User' }, Id: DEMO_USER_ID, Name: 'Demo Field Rep' };
    const instance = (id, materialId, status, progress) => {
        const m = materials.get(materialId);
        return {
            attributes: { type: 'Learning_Material_Instance__c' },
            Id: id,
            Material__c: materialId,
            Material__r: {
                attributes: { type: 'Learning_Material__c' },
                Id: materialId,
                Title__c: m.Title__c,
                Description__c: m.Description__c,
                Material_Type__c: m.Material_Type__c,
                Material_URL__c: m.Material_URL__c,
                Duration__c: m.Duration__c,
                Parent_Material__c: m.Parent_Material__c,
                Issue_Certificate__c: m.Issue_Certificate__c,
                Effective_End_Date__c: m.Effective_End_Date__c
            },
            Learner__c: DEMO_USER_ID,
            Learner__r: learner,
            Status__c: status,
            Progress__c: progress,
            Score__c: status === 'Completed' ? 100 : null,
            Attempt_Number__c: status === 'Not Started' ? 0 : 1,
            Started_On__c: status === 'Not Started' ? null : utc(`${addDays(today, -10)}T09:00:00`),
            Completed_On__c: status === 'Completed' ? utc(`${addDays(today, -7)}T10:00:00`) : null
        };
    };
    return DEMO_COURSES.flatMap((course, i) => {
        const n = i + 1;
        const lessons = [1, 2, 3].map((l) => {
            const status = lessonStatus(course, l);
            return instance(
                `a0LDEMO${String(100 + n * 10 + l).padStart(11, '0')}`,
                lessonMaterialId(n, l),
                status,
                status === 'Completed' ? 100 : status === 'In Progress' ? 50 : 0
            );
        });
        return [instance(course.id, courseMaterialId(n), course.status, course.progress), ...lessons];
    });
}

// ---------------------------------------------------------------------------
// Routes
// ---------------------------------------------------------------------------

function routeAfter(path, prefix) {
    return path.startsWith(prefix) ? path.slice(prefix.length).replace(/\/+$/, '') : null;
}

function plannerGet(route, params) {
    switch (route) {
        case 'home/dashboard':
            return homeDashboard();
        case 'home/today-plan': {
            const planDate = params.get('planDate') || todayIso();
            return { userId: DEMO_USER_ID, planDate, visits: todayVisits(planDate), timeOff: [], viewerContext: viewerContext() };
        }
        case 'home/next-best-customers':
            return { userId: DEMO_USER_ID, rows: nextBestCustomers(Number(params.get('limitSize')) || 5) };
        case 'home/monthly-timecard':
            return timecardSummary();
        case 'home/monthly-timecard/details':
            return timecardDetails(params.get('tileId') || '');
        case 'home/monthly-timecard/leaves':
            return leaveDetails();
        case 'home/messages/composer':
            return { canCompose: false, canPostThisMonth: false, audienceLabel: DEMO_TERRITORY.district };
        case 'accounts-tab/page':
            return accountsTabPage(params);
        case 'accounts-tab/map-points':
            return accountsTabPage(params, true);
        case 'accounts-tab/record-type-options':
            return recordTypeFilterOptions();
        default:
            return undefined;
    }
}

function accountsTabRoute(route, params, method, body) {
    if (method === 'GET') {
        switch (route) {
            case 'pending-approvals':
                return [];
            case 'approval-manager':
                return false;
            case 'createable-record-types':
                return createableRecordTypes();
            case 'wizard-options':
                return wizardOptions();
            case 'duplicate-check':
                return duplicateCheck(params.get('accountId'));
            case 'nurture-summary':
                return { needsYou: 0, withManager: 1, withSfe: 0, total: 1 };
            case 'export':
                return csvExport(params);
            default:
                return undefined;
        }
    }
    switch (route) {
        case 'master-search':
            return masterSearch(body || {});
        case 'map-places':
            return { places: [], centerLat: 30.07, centerLng: 31.31, radiusMeters: 5000 };
        case 'set-kol':
            return {
                isKol: body?.isKol === true,
                territoryName: DEMO_TERRITORY.name,
                message: body?.isKol === true ? 'Marked as KOL.' : 'KOL flag removed.'
            };
        case 'create':
            return { accountId: newId('001'), message: 'Account submitted for approval.', dataQualityScore: 82 };
        default:
            return undefined;
    }
}

/** JSON body for this request, or undefined if not handled. path has no query string. */
export function handle(path, params, method, body) {
    const p = String(path || '');
    const query = params instanceof URLSearchParams ? params : new URLSearchParams(params || '');
    const verb = String(method || 'GET').toUpperCase();

    const plannerRoute = routeAfter(p, PLANNER_PREFIX);
    if (plannerRoute != null) {
        return verb === 'GET' ? plannerGet(plannerRoute, query) : undefined;
    }
    const tabRoute = routeAfter(p, ACCOUNTS_TAB_PREFIX);
    if (tabRoute != null) {
        let payload = body;
        if (typeof payload === 'string') {
            try {
                payload = JSON.parse(payload);
            } catch (_err) {
                payload = {};
            }
        }
        return accountsTabRoute(tabRoute, query, verb, payload);
    }

    const data = /^\/services\/data\/v[\d.]+(\/.*)$/.exec(p);
    if (!data || verb !== 'GET') return undefined;
    const rest = data[1].replace(/\/+$/, '');

    if (rest === '/ui-api/apps') return { apps: [fieldApp()] };
    const appDetail = /^\/ui-api\/apps\/([^/]+)$/.exec(rest);
    if (appDetail) {
        const id = decodeURIComponent(appDetail[1]);
        return id === APP_ID || /^(LightningSales|PharmaField)$/i.test(id) ? fieldApp() : undefined;
    }
    if (rest === '/tabs') return allTabs();
    if (rest === '/connect/notifications') return notifications();
    if (rest === '/chatter/users/me') return chatterMe();
    if (rest === '/sobjects') return globalDescribe();

    const recordUi = /^\/ui-api\/record-ui\/([^/]+)$/.exec(rest);
    if (recordUi) {
        const account = accountById(decodeURIComponent(recordUi[1]));
        return account ? accountRecordUi(account) : undefined;
    }
    const sobject = /^\/sobjects\/Account\/([^/]+)$/.exec(rest);
    if (sobject && sobject[1] !== 'describe') {
        const account = accountById(decodeURIComponent(sobject[1]));
        return account ? accountRecord(account) : undefined;
    }
    return undefined;
}

/** Array of SOQL records for this object, or undefined if not handled. */
export function query(objectApiName, soql) {
    const q = String(soql || '');
    switch (objectApiName) {
        case 'Field_App_Feature__c':
            // nav.% (copilotNav.js) and visitTabs.% rows are left to their defaults.
            if (/Feature_Key__c\s+LIKE/i.test(q) || /Feature_Key__c\s*=/i.test(q)) return undefined;
            return featureRows();
        case 'Account':
            return filterBy(DEMO_ACCOUNTS, q, 'Id', (a) => a.id).map(accountRecord);
        case 'User': {
            let rows = filterBy(userRows(), q, 'Id', (u) => u.Id);
            rows = filterBy(rows, q, 'ManagerId', (u) => u.ManagerId);
            return rows;
        }
        case 'Territory2': {
            let rows = filterBy(territoryRows(), q, 'Id', (t) => t.Id);
            rows = filterBy(rows, q, 'ParentTerritory2Id', (t) => t.ParentTerritory2Id);
            return rows;
        }
        case 'UserTerritory2Association': {
            let rows = filterBy(seatRows(), q, 'UserId', (s) => s.UserId);
            rows = filterBy(rows, q, 'Territory2Id', (s) => s.Territory2Id);
            return rows;
        }
        case 'PermissionSetAssignment':
            return [];
        case 'Home_Office_Message__c':
            return officeMessages().map((m) => ({
                attributes: { type: 'Home_Office_Message__c' },
                Id: m.recordId,
                Name: m.subject,
                Message_Body__c: m.body,
                Audience_Scope__c: m.audienceLabel,
                Priority__c: m.priority,
                Published_On__c: m.publishedOn,
                Is_Active__c: true,
                Author__r: { attributes: { type: 'User' }, Name: m.authorName }
            }));
        case 'Learning_Material_Instance__c': {
            if (!isDemoUser(q, 'Learner__c')) return [];
            let rows = learningInstances();
            if (/Material_Type__c\s*=\s*'Course'/i.test(q)) {
                rows = rows.filter((r) => r.Material__r.Material_Type__c === 'Course');
            }
            rows = filterBy(rows, q, 'Id', (r) => r.Id);
            rows = filterBy(rows, q, 'Material__c', (r) => r.Material__c);
            return rows;
        }
        case 'Learning_Material__c': {
            let rows = learningMaterials();
            if (/Active__c\s*=\s*true/i.test(q)) rows = rows.filter((r) => r.Active__c);
            rows = filterBy(rows, q, 'Parent_Material__c', (r) => r.Parent_Material__c);
            rows = filterBy(rows, q, 'Id', (r) => r.Id);
            return rows;
        }
        case 'Product2': {
            let rows = filterBy(productRows(), q, 'Id', (r) => r.Id);
            rows = filterBy(rows, q, 'External_ID__c', (r) => r.External_ID__c);
            return rows;
        }
        case 'Product_Territory_Alignment__c':
            return alignmentRows();
        case 'Account_Territory_Fields__c':
            return filterBy(atfRows(), q, 'Account__c', (r) => r.Account__c);
        case 'Account_Territory_Product_Fields__c':
            return filterBy(atpfRows(), q, 'Account__c', (r) => r.Account__c);
        case 'CLM_Rating_Layout__c':
            return ratingLayoutRows();
        case 'Account_Affiliation__c': {
            const ids = [...(filterValues(q, 'Primary_Account__c') || []), ...(filterValues(q, 'Related_Account__c') || [])];
            const rows = affiliationRows();
            if (!ids.length) return rows;
            return rows.filter((r) => ids.some((id) => sameId(id, r.Primary_Account__c) || sameId(id, r.Related_Account__c)));
        }
        case 'Visit__c': {
            // Only the per-account reads (account panels, record.html); other Visit__c queries belong to the visit fixtures.
            const ids = filterValues(q, 'Account__c');
            if (!ids || !ids.length) return undefined;
            return ids.flatMap((id) => accountVisitRows(id, q));
        }
        default:
            return undefined;
    }
}
