// Care Coach Co-pilot answers for the field assistant. Each tab loads the
// same data the screen shows (respecting PSP / company view and my patients /
// all coaches) and can answer the questions a coach actually asks.
import getContext from './apex/CareCoachAccess.getContext.js';
import getHomeData from './apex/CareCoachHomeController.getHomeData.js';
import getPatients from './apex/CareCoachPatientService.getPatients.js';
import getPlannerData from './apex/CareCoachPlannerController.getPlannerData.js';
import getProducts from './apex/CareCoachCatalogController.getProducts.js';
import getOrders from './apex/CareCoachOrderService.getOrders.js';
import getScripts from './apex/CareCoachCatalogController.getScripts.js';
import getScript from './apex/CareCoachCatalogController.getScript.js';

const FRESH_MS = 20000;
const STATUSES = ['Ongoing', 'Pending', 'Dropped (Switched)', 'Dropped (Stopped)', 'Unknown (Failed calls)'];
const CLOSED_ORDERS = new Set(['Delivered', 'Cancelled']);
const TAB_TARGETS = [
    ['home', 'Care_Coach_Home'],
    ['patient', 'Care_Coach_Patients'],
    ['planner', 'Care_Coach_Planner'],
    ['product', 'Care_Coach_Products'],
    ['order', 'Care_Coach_Orders'],
    ['knowledge', 'Care_Coach_Knowledge'],
    ['script', 'Care_Coach_Knowledge']
];
const STOP = new Set([
    'what', 'should', 'about', 'the', 'how', 'say', 'tell', 'patient', 'patients', 'script', 'scripts',
    'which', 'for', 'with', 'does', 'can', 'you', 'are', 'this', 'that', 'your', 'from', 'have', 'has',
    'who', 'need', 'needs', 'and', 'any', 'most', 'into', 'please', 'show', 'list'
]);

const cache = { key: '', entries: {} };
const tickets = {};
let ticket = 0;
let contextScope;

export function careCoachViewKey() {
    try {
        const mode = sessionStorage.getItem('careCoach.viewMode') === 'company' ? 'company' : 'psp';
        const scope = sessionStorage.getItem('careCoach.scope') || 'default';
        return `${mode}:${scope}`;
    } catch (_err) {
        return 'psp:default';
    }
}

function has(q, pattern) {
    return pattern.test(q);
}

function nfmt(value) {
    const n = Number(value);
    return Number.isFinite(n) ? n.toLocaleString() : '0';
}

function countOf(counts, status) {
    if (!counts) return 0;
    const n = Number(counts[status]);
    return Number.isFinite(n) ? n : 0;
}

function numbered(rows, format) {
    return rows.map((row, index) => `${index + 1}. ${format(row)}`).join('\n');
}

function isSameDay(value, day) {
    const d = value instanceof Date ? value : new Date(value);
    if (Number.isNaN(d.getTime())) return false;
    return d.getFullYear() === day.getFullYear() && d.getMonth() === day.getMonth() && d.getDate() === day.getDate();
}

function formatWhen(value) {
    if (!value) return '';
    const d = new Date(value);
    if (Number.isNaN(d.getTime())) return '';
    const time = d.toLocaleTimeString(undefined, { hour: 'numeric', minute: '2-digit' });
    if (isSameDay(d, new Date())) return time;
    const day = d.toLocaleDateString(undefined, { weekday: 'short', month: 'short', day: 'numeric' });
    return `${day} ${time}`;
}

function formatDateOnly(value) {
    if (!value) return '';
    const match = String(value).match(/^(\d{4})-(\d{2})-(\d{2})/);
    const d = match ? new Date(Number(match[1]), Number(match[2]) - 1, Number(match[3])) : new Date(value);
    if (Number.isNaN(d.getTime())) return '';
    return d.toLocaleDateString(undefined, { month: 'short', day: 'numeric' });
}

function plain(text) {
    return String(text || '')
        .replace(/<\s*br\s*\/?>/gi, '\n')
        .replace(/<\/p>/gi, '\n')
        .replace(/<[^>]+>/g, '')
        .replace(/&nbsp;/g, ' ')
        .replace(/&amp;/g, '&')
        .replace(/&lt;/g, '<')
        .replace(/&gt;/g, '>')
        .replace(/[ \t]+\n/g, '\n')
        .replace(/\n{3,}/g, '\n\n')
        .trim();
}

function clip(text, max = 900) {
    const clean = plain(text);
    if (clean.length <= max) return clean;
    const cut = clean.slice(0, max);
    const last = cut.lastIndexOf(' ');
    return `${(last > 500 ? cut.slice(0, last) : cut).trim()}…`;
}

function startOfWeek(date) {
    const d = new Date(date.getFullYear(), date.getMonth(), date.getDate());
    d.setDate(d.getDate() - d.getDay());
    return d;
}

function toIsoDate(date) {
    const pad = (n) => String(n).padStart(2, '0');
    return `${date.getFullYear()}-${pad(date.getMonth() + 1)}-${pad(date.getDate())}`;
}

function scopeLabel(scope) {
    return scope === 'mine' ? 'My patients' : 'All coaches';
}

function maskNote(masked) {
    return masked ? 'Company view is on, so patient names are initials.' : '';
}

function shortName(name) {
    return String(name || 'Patient').split('·')[0].trim().slice(0, 22) || 'Patient';
}

function openActions(rows, nameOf, idOf) {
    return (rows || [])
        .filter((row) => idOf(row))
        .slice(0, 4)
        .map((row) => ({ label: `Open ${shortName(nameOf(row))}`, command: `cc:patient:${idOf(row)}` }));
}

function replyList(intro, rows, format, actions) {
    const text = rows && rows.length ? `${intro}\n${numbered(rows, format)}` : intro;
    return actions && actions.length ? { text, actions } : text;
}

function patientLine(patient) {
    const phone = patient.mobile || patient.phone;
    const bits = [patient.status, patient.productName, patient.adherence, patient.lastCallDate ? `last call ${formatDateOnly(patient.lastCallDate)}` : 'never called', phone].filter(Boolean);
    return `${patient.displayName || patient.patientNumber || 'Patient'} — ${bits.join(' · ')}`;
}

function patientItem(patient) {
    const phone = patient.mobile || patient.phone;
    return {
        title: patient.displayName || patient.patientNumber || 'Patient',
        lines: [
            [patient.status, patient.productName, patient.adherence].filter(Boolean).join(' · '),
            [patient.lastCallDate ? `Last call ${formatDateOnly(patient.lastCallDate)}` : 'Never called', phone, patient.coachName].filter(Boolean).join(' · ')
        ].filter(Boolean),
        actions: patient.id ? [{ label: 'Open', command: `cc:patient:${patient.id}` }] : []
    };
}

function workLine(item) {
    const bits = [formatWhen(item.startTime), item.reason, item.productName, item.risk ? `Risk ${item.risk}` : '', item.detail].filter(Boolean);
    return `${item.patientName || 'Patient'} — ${bits.join(' · ') || item.status || 'Planned'}`;
}

function workItem(item) {
    return {
        title: item.patientName || 'Patient',
        lines: [[formatWhen(item.startTime), item.reason, item.productName].filter(Boolean).join(' · '), item.detail || (item.risk ? `Risk ${item.risk}` : '')].filter(Boolean),
        actions: item.patientId ? [{ label: 'Open', command: `cc:patient:${item.patientId}` }] : []
    };
}

async function viewPrefs() {
    let mode = 'psp';
    let stored = '';
    try {
        mode = sessionStorage.getItem('careCoach.viewMode') === 'company' ? 'company' : 'psp';
        stored = sessionStorage.getItem('careCoach.scope') || '';
    } catch (_err) {
        /* private mode */
    }
    let scope = stored === 'mine' || stored === 'all' ? stored : '';
    if (!scope) {
        if (!contextScope) {
            contextScope = getContext()
                .then((ctx) => (ctx && ctx.defaultScope) || 'all')
                .catch(() => 'all');
        }
        scope = await contextScope;
        if (scope !== 'mine' && scope !== 'all') scope = 'all';
    }
    return { mode, scope, key: `${mode}:${scope}` };
}

async function cacheFor() {
    const prefs = await viewPrefs();
    if (cache.key !== prefs.key) {
        cache.key = prefs.key;
        cache.entries = {};
    }
    return { prefs, entries: cache.entries };
}

async function ensure(name, loader) {
    const { prefs, entries } = await cacheFor();
    const hit = entries[name];
    if (hit && Date.now() - hit.at < FRESH_MS) return hit.value;
    const mine = ++ticket;
    tickets[name] = mine;
    const value = await loader(prefs);
    if (tickets[name] === mine) entries[name] = { at: Date.now(), value };
    return value;
}

async function refresh(name, loader) {
    const { entries } = await cacheFor();
    delete entries[name];
    tickets[name] = ++ticket;
    return ensure(name, loader);
}

function fetchPatients(extra, prefs) {
    return getPatients({
        filtersJson: JSON.stringify({ mode: prefs.mode, scope: prefs.scope, limitSize: 8, offsetSize: 0, ...extra })
    });
}

async function loadPatientSnapshot(prefs) {
    const [allResult, pendingResult, riskResult, failedResult] = await Promise.allSettled([
        fetchPatients({ limitSize: 1 }, prefs),
        fetchPatients({ status: 'Pending', limitSize: 30 }, prefs),
        fetchPatients({ adherence: 'High risk', limitSize: 8 }, prefs),
        fetchPatients({ status: 'Unknown (Failed calls)', limitSize: 8 }, prefs)
    ]);
    if (allResult.status !== 'fulfilled') throw allResult.reason;
    const page = allResult.value || {};
    const pendingPage = pendingResult.status === 'fulfilled' ? pendingResult.value : {};
    const riskPage = riskResult.status === 'fulfilled' ? riskResult.value : {};
    const failedPage = failedResult.status === 'fulfilled' ? failedResult.value : {};
    return {
        page,
        pending: pendingPage.rows || [],
        risk: riskPage.rows || [],
        riskTotal: riskPage.total,
        failed: failedPage.rows || []
    };
}

function loadHome(prefs) {
    return getHomeData({ mode: prefs.mode, scope: prefs.scope, coachId: null });
}

function loadPlanner(prefs) {
    const start = startOfWeek(new Date());
    return getPlannerData({ startDate: toIsoDate(start), days: 7, mode: prefs.mode });
}

function loadProducts(prefs) {
    return getProducts({ scope: prefs.scope });
}

function loadOrders(prefs) {
    return getOrders({ mode: prefs.mode, scope: prefs.scope, days: 90 });
}

function loadScripts() {
    return getScripts({ search: null, productId: null, category: null, publishedOnly: true });
}

const ensureHome = () => ensure('home', loadHome);
const ensurePatients = () => ensure('patients', loadPatientSnapshot);
const ensurePlanner = () => ensure('planner', loadPlanner);
const ensureProducts = () => ensure('products', loadProducts);
const ensureOrders = () => ensure('orders', loadOrders);
const ensureScripts = () => ensure('scripts', loadScripts);

function shell(tab, profile) {
    return {
        title: 'Care Coach',
        ...profile,
        answer(q) {
            return answerQuestion(q, tab);
        }
    };
}

function statusMix(counts) {
    return STATUSES.map((status) => `${status} ${nfmt(countOf(counts, status))}`).join(' · ');
}

function homeProfile(data) {
    const scope = scopeLabel(data.scope);
    const today = data.today || [];
    const overdue = data.overdue || [];
    const alerts = data.aiAlerts || [];
    const coaches = [...(data.coaches || [])].sort((a, b) => (b.pending || 0) - (a.pending || 0) || (b.total || 0) - (a.total || 0));
    const retention = data.retentionRate == null ? '—' : `${data.retentionRate}%`;
    const reach = data.reachRate == null ? '—' : `${data.reachRate}%`;
    const insights = [
        `${nfmt(data.totalPatients)} patients in ${scope.toLowerCase()}. ${nfmt(data.newThisMonth)} new this month, ${nfmt(data.newLastMonth)} last month.`,
        `Retention ${retention}. Reach rate ${reach} over the last 30 days.`,
        today.length ? `${today.length} call(s) planned today.` : 'No calls planned today.',
        overdue.length ? `${overdue.length} overdue follow-up(s).` : 'No overdue follow-ups.',
        maskNote(data.masked)
    ].filter(Boolean);
    const sections = [
        {
            title: 'Call today',
            meta: String(today.length),
            empty: 'No calls planned today.',
            items: today.slice(0, 6).map(workItem)
        }
    ];
    if (overdue.length) {
        sections.push({ title: 'Overdue follow-ups', meta: String(overdue.length), items: overdue.slice(0, 6).map(workItem) });
    }
    if (alerts.length) {
        sections.push({ title: 'AI alerts', meta: 'High risk or adverse event', items: alerts.slice(0, 5).map(workItem) });
    }
    if (coaches.length) {
        sections.push({
            title: 'Coaches with the most pending',
            items: coaches.slice(0, 5).map((coach) => ({
                title: coach.coachName || 'Coach',
                lines: [`${nfmt(coach.pending)} pending · ${nfmt(coach.ongoing)} ongoing · ${nfmt(coach.dropped)} dropped · ${nfmt(coach.reachedThisMonth)} reached this month`]
            }))
        });
    }
    return shell('home', {
        subtitle: `${scope} · today`,
        placeholder: 'Ask who to call, or how retention is doing',
        chips: ['Who should I call today?', "What's overdue?", 'How is retention?', 'Any high-risk patients?'],
        stats: [
            { label: 'Patients', value: nfmt(data.totalPatients) },
            { label: 'New', value: nfmt(data.newThisMonth) },
            { label: 'Retention', value: retention, tone: data.retentionRate == null ? '' : Number(data.retentionRate) < 70 ? 'warn' : 'good' },
            { label: 'Overdue', value: overdue.length, tone: overdue.length ? 'warn' : 'good' }
        ],
        insights,
        sections
    });
}

function patientsProfile(snap) {
    const page = snap.page || {};
    const counts = page.statusCounts || {};
    const scope = scopeLabel(page.scope);
    const pending = [...(snap.pending || [])].sort((a, b) => Number(Boolean(a.lastCallDate)) - Number(Boolean(b.lastCallDate)));
    const never = pending.filter((patient) => !patient.lastCallDate);
    const riskTotal = snap.riskTotal == null ? (snap.risk || []).length : snap.riskTotal;
    const insights = [
        `${nfmt(page.total)} patients. ${statusMix(counts)}.`,
        `${nfmt(riskTotal)} high-risk patient(s).`,
        never.length ? `${never.length} of the newest pending patients have never been called.` : '',
        maskNote(page.masked)
    ].filter(Boolean);
    const sections = [];
    if ((snap.risk || []).length) {
        sections.push({ title: 'High risk', meta: nfmt(riskTotal), items: snap.risk.slice(0, 5).map(patientItem) });
    }
    sections.push({
        title: 'Pending to start',
        meta: nfmt(countOf(counts, 'Pending')),
        empty: 'No pending patients.',
        items: pending.slice(0, 5).map(patientItem)
    });
    if ((snap.failed || []).length) {
        sections.push({
            title: 'Failed calls',
            meta: nfmt(countOf(counts, 'Unknown (Failed calls)')),
            items: snap.failed.slice(0, 4).map(patientItem)
        });
    }
    return shell('patients', {
        subtitle: `${scope} · status and risk`,
        placeholder: 'Ask who is pending, high risk, or look up a name',
        chips: ['Who is pending?', 'Who is high risk?', 'Who has failed calls?', 'Break down each status'],
        stats: [
            { label: 'Patients', value: nfmt(page.total) },
            { label: 'Pending', value: nfmt(countOf(counts, 'Pending')), tone: countOf(counts, 'Pending') ? 'warn' : '' },
            { label: 'High risk', value: nfmt(riskTotal), tone: riskTotal ? 'warn' : 'good' },
            { label: 'Failed calls', value: nfmt(countOf(counts, 'Unknown (Failed calls)')), tone: countOf(counts, 'Unknown (Failed calls)') ? 'warn' : '' }
        ],
        insights,
        sections
    });
}

function plannerProfile(data) {
    const today = new Date();
    const calls = (data.calls || []).filter((call) => isSameDay(call.startTime, today)).sort((a, b) => new Date(a.startTime) - new Date(b.startTime));
    const due = [...(data.patients || [])].filter((patient) => patient.followUpDue).sort((a, b) => (b.riskScore || 0) - (a.riskScore || 0));
    const risk = (data.patients || []).filter((patient) => patient.adherence === 'High risk');
    const timeOff = data.timeOffs || [];
    const insights = [
        `${calls.length} call(s) on your calendar today.`,
        `${due.length} patient(s) need a follow-up (no next call, and never reached or last call over 14 days ago).`,
        `${risk.length} high-risk patient(s) on your active list.`,
        timeOff.length ? `${timeOff.length} time-off block(s) this week.` : 'No time off this week.',
        'The planner is your own patients, even when other tabs are set to all coaches.',
        maskNote(data.masked)
    ].filter(Boolean);
    const sections = [
        {
            title: "Today's calls",
            meta: String(calls.length),
            empty: 'Nothing on your calendar today.',
            items: calls.slice(0, 6).map((call) => ({
                title: call.patientName || 'Patient',
                lines: [[formatWhen(call.startTime), call.reason || call.status, call.productName].filter(Boolean).join(' · ')].filter(Boolean),
                actions: call.patientId ? [{ label: 'Open', command: `cc:patient:${call.patientId}` }] : []
            }))
        },
        {
            title: 'Follow-up due',
            meta: String(due.length),
            empty: 'No follow-ups are due.',
            items: due.slice(0, 5).map(patientItem)
        }
    ];
    if (timeOff.length) {
        sections.push({
            title: 'Time off this week',
            items: timeOff.slice(0, 4).map((block) => ({
                title: block.name || block.type || 'Time off',
                lines: [[block.type, block.stage, formatWhen(block.startTime)].filter(Boolean).join(' · ')].filter(Boolean)
            }))
        });
    }
    return shell('planner', {
        subtitle: 'Your week',
        placeholder: "Ask what's on today, or who needs a follow-up",
        chips: ["What's on today?", 'Who needs a follow-up?', 'Any time off this week?', 'Who is high risk?'],
        stats: [
            { label: 'Today', value: calls.length },
            { label: 'Follow-up', value: due.length, tone: due.length ? 'warn' : 'good' },
            { label: 'High risk', value: risk.length, tone: risk.length ? 'warn' : '' },
            { label: 'Time off', value: timeOff.length }
        ],
        insights,
        sections
    });
}

function flattenProducts(groups) {
    const rows = [];
    (groups || []).forEach((group) => {
        (group.products || []).forEach((product) => {
            rows.push({ ...product, therapyArea: product.therapyArea || group.therapyArea });
        });
    });
    return rows;
}

function productItem(product) {
    const actions = [];
    if (product.id) {
        actions.push({ label: 'Patients', command: `cc:product:${product.id}` });
        actions.push({ label: 'Scripts', command: `cc:scripts:${product.id}` });
    }
    return {
        title: product.name || 'Product',
        lines: [
            [product.therapyArea, `${nfmt(product.totalPatients)} patients`, `${nfmt(product.ongoing)} ongoing`, `${nfmt(product.pending)} pending`, `${nfmt(product.dropped)} dropped`].filter(Boolean).join(' · '),
            `${nfmt(product.ordersThisMonth)} orders · ${nfmt(product.unitsThisMonth)} units this month · ${nfmt(product.scripts)} scripts`
        ],
        actions
    };
}

function productsProfile(groups) {
    const products = flattenProducts(groups);
    const patients = products.reduce((sum, product) => sum + (product.totalPatients || 0), 0);
    const dropped = products.reduce((sum, product) => sum + (product.dropped || 0), 0);
    const orders = products.reduce((sum, product) => sum + (product.ordersThisMonth || 0), 0);
    const largest = [...products].sort((a, b) => (b.totalPatients || 0) - (a.totalPatients || 0));
    const dropping = [...products].filter((product) => product.dropped > 0).sort((a, b) => b.dropped - a.dropped);
    const top = largest[0];
    const insights = [
        products.length ? `${products.length} programme product(s), ${nfmt(patients)} patients, ${nfmt(dropped)} dropped.` : 'No programme products yet.',
        top ? `${top.name} is the largest, with ${nfmt(top.totalPatients)} patients.` : '',
        `${nfmt(orders)} order(s) placed this month.`
    ].filter(Boolean);
    const sections = [
        {
            title: 'Largest programmes',
            empty: 'No programme products yet.',
            items: largest.slice(0, 4).map(productItem)
        }
    ];
    if (dropping.length) {
        sections.push({ title: 'Most dropped', items: dropping.slice(0, 3).map(productItem) });
    }
    return shell('products', {
        subtitle: 'Programmes',
        placeholder: 'Ask which therapy needs attention',
        chips: ['Which product has the most patients?', 'Where are patients dropping?', 'How are orders this month?', 'Which product has the most scripts?'],
        stats: [
            { label: 'Products', value: products.length },
            { label: 'Patients', value: nfmt(patients) },
            { label: 'Dropped', value: nfmt(dropped), tone: dropped ? 'warn' : 'good' },
            { label: 'Orders', value: nfmt(orders) }
        ],
        insights,
        sections
    });
}

function orderCount(board, status) {
    const row = (board.totals || []).find((total) => total.status === status);
    return row ? row.count || 0 : 0;
}

function orderLine(order) {
    const when = order.overdue ? 'overdue' : order.promisedDate ? `promised ${formatDateOnly(order.promisedDate)}` : 'no promise date';
    return `${order.orderNumber || 'Order'} — ${order.patientName || 'Patient'} · ${[order.productName, order.status, when].filter(Boolean).join(' · ')}`;
}

function orderItem(order) {
    return {
        title: `${order.orderNumber || 'Order'} · ${order.patientName || 'Patient'}`,
        lines: [[order.productName, order.status, order.overdue ? 'Overdue' : order.promisedDate ? `Promised ${formatDateOnly(order.promisedDate)}` : ''].filter(Boolean).join(' · ')],
        actions: order.patientId ? [{ label: 'Patient', command: `cc:patient:${order.patientId}` }] : []
    };
}

function ordersProfile(board) {
    const data = board || {};
    board = data;
    const open = (board.totals || []).filter((total) => !CLOSED_ORDERS.has(total.status)).reduce((sum, total) => sum + (total.count || 0), 0);
    const overdue = (board.orders || []).filter((order) => order.overdue);
    const due = (board.orders || []).filter((order) => !order.overdue && !CLOSED_ORDERS.has(order.status) && order.daysToPromise != null && order.daysToPromise <= 7);
    const insights = [
        `${nfmt(board.overdueCount)} open order(s) are past the promised date. ${nfmt(board.dueThisWeek)} due in the next 7 days.`,
        `${nfmt(open)} still open: ${nfmt(orderCount(board, 'Requested'))} requested, ${nfmt(orderCount(board, 'Approved'))} approved, ${nfmt(orderCount(board, 'Dispatched'))} dispatched.`,
        `${nfmt(orderCount(board, 'Delivered'))} delivered in this list.`,
        'Figures cover the last 90 days.',
        maskNote(board.masked)
    ].filter(Boolean);
    return shell('orders', {
        subtitle: 'Last 90 days',
        placeholder: 'Ask which orders are overdue',
        chips: ['Which orders are overdue?', "What's due this week?", 'How many orders are still open?', "What's been dispatched?"],
        stats: [
            { label: 'Overdue', value: nfmt(board.overdueCount), tone: board.overdueCount ? 'warn' : 'good' },
            { label: 'Due 7 days', value: nfmt(board.dueThisWeek), tone: board.dueThisWeek ? 'warn' : '' },
            { label: 'Open', value: nfmt(open) },
            { label: 'Delivered', value: nfmt(orderCount(board, 'Delivered')), tone: 'good' }
        ],
        insights,
        sections: [
            {
                title: 'Overdue',
                meta: nfmt(board.overdueCount),
                empty: 'No open order is past its promised date.',
                items: overdue.slice(0, 5).map(orderItem)
            },
            {
                title: 'Due this week',
                meta: nfmt(board.dueThisWeek),
                empty: 'Nothing else is due in the next 7 days.',
                items: due.slice(0, 4).map(orderItem)
            }
        ]
    });
}

function knowledgeProfile(scripts) {
    const rows = scripts || [];
    const products = new Set(rows.map((script) => script.productName).filter(Boolean));
    const byCategory = {};
    rows.forEach((script) => {
        const category = script.category || 'Other';
        byCategory[category] = (byCategory[category] || 0) + 1;
    });
    const helpful = [...rows].sort((a, b) => (b.helpful || 0) - (a.helpful || 0));
    const insights = [
        rows.length ? `${rows.length} published script(s) across ${products.size} product(s).` : 'No published care scripts yet.',
        Object.keys(byCategory).length ? `Topics: ${Object.entries(byCategory).map(([category, count]) => `${category} (${count})`).join(', ')}.` : ''
    ].filter(Boolean);
    return shell('knowledge', {
        subtitle: 'Care scripts',
        placeholder: 'Ask what to say about side effects or adherence',
        chips: ['What should I say about side effects?', 'Adherence scripts', 'Storage and handling', 'Which scripts help the most?'],
        stats: [
            { label: 'Scripts', value: rows.length },
            { label: 'Products', value: products.size },
            { label: 'Topics', value: Object.keys(byCategory).length }
        ],
        insights,
        sections: [
            {
                title: 'Most helpful',
                empty: 'No published care scripts yet.',
                items: helpful.slice(0, 5).map((script) => ({
                    title: script.title || script.scriptNumber || 'Script',
                    lines: [[script.productName, script.category, script.helpful ? `${script.helpful} helpful` : ''].filter(Boolean).join(' · '), script.summary || script.question].filter(Boolean),
                    actions: script.id ? [{ label: 'Open', command: `cc:script:${script.id}` }] : []
                }))
            }
        ]
    });
}

async function answerPatientSearch(term) {
    const { prefs } = await cacheFor();
    const page = await fetchPatients({ search: term, limitSize: 8 }, prefs);
    const rows = page.rows || [];
    if (!rows.length) {
        const hint = page.masked ? ' Company view only matches initials and the patient number.' : '';
        return `No patient matched “${term}”.${hint}`;
    }
    return replyList(
        `${nfmt(page.total)} patient(s) matched “${term}”.`,
        rows.slice(0, 6),
        patientLine,
        openActions(rows, (patient) => patient.displayName, (patient) => patient.id)
    );
}

async function answerCallNext() {
    const home = await ensureHome();
    const today = home.today || [];
    const overdue = home.overdue || [];
    if (!today.length && !overdue.length) {
        const snap = await ensurePatients();
        const risk = snap.risk || [];
        if (!risk.length) return 'Nothing is booked today, nothing is overdue, and no high-risk patients came back.';
        return replyList(
            'Nothing is booked today and nothing is overdue. Start with these high-risk patients:',
            risk.slice(0, 6),
            patientLine,
            openActions(risk, (patient) => patient.displayName, (patient) => patient.id)
        );
    }
    const parts = [];
    if (today.length) parts.push(`Today:\n${numbered(today.slice(0, 6), workLine)}`);
    if (overdue.length) parts.push(`Overdue:\n${numbered(overdue.slice(0, 6), workLine)}`);
    return {
        text: parts.join('\n\n'),
        actions: openActions([...today, ...overdue], (item) => item.patientName, (item) => item.patientId)
    };
}

async function answerPlannerToday() {
    const data = await ensurePlanner();
    const today = new Date();
    const calls = (data.calls || []).filter((call) => isSameDay(call.startTime, today)).sort((a, b) => new Date(a.startTime) - new Date(b.startTime));
    if (!calls.length) return "Nothing is on your calendar today. Ask who needs a follow-up if you want patients to book.";
    return replyList(
        `${calls.length} call(s) today:`,
        calls.slice(0, 8),
        (call) => `${call.patientName || 'Patient'} — ${[formatWhen(call.startTime), call.reason || call.status, call.productName].filter(Boolean).join(' · ')}`,
        openActions(calls, (call) => call.patientName, (call) => call.patientId)
    );
}

async function answerFollowUp() {
    const data = await ensurePlanner();
    const due = [...(data.patients || [])].filter((patient) => patient.followUpDue).sort((a, b) => (b.riskScore || 0) - (a.riskScore || 0));
    if (!due.length) return 'No follow-up is due on your own patients. A follow-up is due when there is no next call, and they were never reached or the last call was over 14 days ago.';
    return replyList(
        `${due.length} of your patients need a follow-up:`,
        due.slice(0, 8),
        patientLine,
        openActions(due, (patient) => patient.displayName, (patient) => patient.id)
    );
}

async function answerTimeOff() {
    const data = await ensurePlanner();
    const blocks = data.timeOffs || [];
    if (!blocks.length) return 'No time off on your planner this week.';
    return `Time off this week:\n${numbered(blocks.slice(0, 6), (block) => [block.name || block.type || 'Time off', block.stage, formatWhen(block.startTime)].filter(Boolean).join(' — '))}`;
}

async function answerRisk() {
    const snap = await ensurePatients();
    const rows = snap.risk || [];
    const total = snap.riskTotal == null ? rows.length : snap.riskTotal;
    if (!total) return 'No patients are marked high risk.';
    return replyList(
        `${nfmt(total)} high-risk patient(s). Newest enrollments:`,
        rows.slice(0, 6),
        patientLine,
        openActions(rows, (patient) => patient.displayName, (patient) => patient.id)
    );
}

async function answerStatus(status) {
    const { prefs } = await cacheFor();
    const page = await fetchPatients({ status, limitSize: 8 }, prefs);
    const rows = page.rows || [];
    const actions = [{ label: 'View on Patients', command: `cc:status:${status}` }, ...openActions(rows, (patient) => patient.displayName, (patient) => patient.id)];
    if (!page.total) return { text: `No patients are ${status}.`, actions: actions.slice(0, 1) };
    return replyList(`${nfmt(page.total)} patient(s) are ${status}. Newest enrollments:`, rows.slice(0, 6), patientLine, actions);
}

async function answerDropped(q) {
    if (has(q, /switch/)) return answerStatus('Dropped (Switched)');
    if (has(q, /stop/)) return answerStatus('Dropped (Stopped)');
    const snap = await ensurePatients();
    const counts = (snap.page && snap.page.statusCounts) || {};
    const switched = countOf(counts, 'Dropped (Switched)');
    const stopped = countOf(counts, 'Dropped (Stopped)');
    return {
        text: `Dropped (Switched): ${nfmt(switched)}. Dropped (Stopped): ${nfmt(stopped)}.`,
        actions: [
            { label: 'Switched', command: 'cc:status:Dropped (Switched)' },
            { label: 'Stopped', command: 'cc:status:Dropped (Stopped)' }
        ]
    };
}

async function answerStatusMix() {
    const snap = await ensurePatients();
    const page = snap.page || {};
    return {
        text: `${nfmt(page.total)} patients.\n${statusMix(page.statusCounts)}`,
        actions: [
            { label: 'Pending', command: 'cc:status:Pending' },
            { label: 'Ongoing', command: 'cc:status:Ongoing' },
            { label: 'Failed calls', command: 'cc:status:Unknown (Failed calls)' }
        ]
    };
}

async function answerKpis() {
    const data = await ensureHome();
    const retention = data.retentionRate == null ? 'not available' : `${data.retentionRate}%`;
    const reach = data.reachRate == null ? 'not available' : `${data.reachRate}%`;
    const delta = data.newLastMonth ? Math.round(((data.newThisMonth - data.newLastMonth) * 100) / data.newLastMonth) : null;
    const trend = delta == null ? `${nfmt(data.newLastMonth)} last month` : `${delta >= 0 ? '+' : ''}${delta}% versus last month`;
    return `${nfmt(data.totalPatients)} patients in ${scopeLabel(data.scope).toLowerCase()}. Retention ${retention} (ongoing versus dropped). Reach rate ${reach} on calls in the last 30 days. ${nfmt(data.newThisMonth)} new this month, ${trend}.`;
}

async function answerCoaches() {
    const data = await ensureHome();
    const coaches = [...(data.coaches || [])].sort((a, b) => (b.pending || 0) - (a.pending || 0));
    if (!coaches.length) return 'Coach comparison is available on all-coaches view. Switch the page to All coaches and ask again.';
    return `Coaches, most pending first:\n${numbered(coaches.slice(0, 6), (coach) => `${coach.coachName}: ${nfmt(coach.pending)} pending, ${nfmt(coach.ongoing)} ongoing, ${nfmt(coach.dropped)} dropped, ${nfmt(coach.reachedThisMonth)} reached this month`)}`;
}

function money(value, code) {
    const n = Number(value);
    if (!Number.isFinite(n)) return '0';
    try {
        return new Intl.NumberFormat(undefined, { style: 'currency', currency: code || 'USD', maximumFractionDigits: 0 }).format(n);
    } catch (_err) {
        return `${Math.round(n)} ${code || ''}`.trim();
    }
}

async function answerOrders(q) {
    const board = await ensureOrders();
    const orders = board.orders || [];
    if (has(q, /overdue/)) {
        const rows = orders.filter((order) => order.overdue);
        const intro = `${nfmt(board.overdueCount)} open order(s) are past the promised date.`;
        if (!rows.length) return intro;
        return replyList(intro, rows.slice(0, 6), orderLine, openActions(rows, (order) => order.patientName, (order) => order.patientId));
    }
    if (has(q, /this week|due/)) {
        const rows = orders.filter((order) => !order.overdue && !CLOSED_ORDERS.has(order.status) && order.daysToPromise != null && order.daysToPromise >= 0 && order.daysToPromise <= 7);
        const intro = `${nfmt(board.dueThisWeek)} open order(s) are due in the next 7 days.`;
        if (!rows.length) return intro;
        return replyList(intro, rows.slice(0, 6), orderLine, openActions(rows, (order) => order.patientName, (order) => order.patientId));
    }
    if (has(q, /dispatch/)) {
        const rows = orders.filter((order) => order.status === 'Dispatched');
        return replyList(`${nfmt(orderCount(board, 'Dispatched'))} dispatched.`, rows.slice(0, 6), orderLine, openActions(rows, (order) => order.patientName, (order) => order.patientId));
    }
    const open = (board.totals || []).filter((total) => !CLOSED_ORDERS.has(total.status)).reduce((sum, total) => sum + (total.count || 0), 0);
    const value = (board.totals || []).reduce((sum, total) => sum + Number(total.value || 0), 0);
    return `${nfmt(open)} order(s) are still open (requested, approved, or dispatched) and ${nfmt(orderCount(board, 'Delivered'))} are delivered, over the last 90 days. ${nfmt(board.overdueCount)} are overdue. Listed value ${money(value, board.currencyCode)}.`;
}

function productMention(q, products) {
    return products.find((product) => product.name && q.includes(String(product.name).toLowerCase()));
}

async function answerProducts(q) {
    const products = flattenProducts(await ensureProducts());
    if (!products.length) return 'No programme products are set up yet.';
    const named = productMention(q, products);
    if (named) {
        return {
            text: `${named.name} (${named.therapyArea || 'therapy'}): ${nfmt(named.totalPatients)} patients, ${nfmt(named.ongoing)} ongoing, ${nfmt(named.pending)} pending, ${nfmt(named.dropped)} dropped. ${nfmt(named.newThisMonth)} new this month. ${nfmt(named.ordersThisMonth)} orders, ${nfmt(named.unitsThisMonth)} units. ${nfmt(named.scripts)} care script(s).`,
            actions: named.id
                ? [
                      { label: 'Patients', command: `cc:product:${named.id}` },
                      { label: 'Scripts', command: `cc:scripts:${named.id}` }
                  ]
                : []
        };
    }
    if (has(q, /drop/)) {
        const dropping = [...products].filter((product) => product.dropped > 0).sort((a, b) => b.dropped - a.dropped);
        if (!dropping.length) return 'No dropped patients on these products.';
        return `Patients dropped by product:\n${numbered(dropping.slice(0, 6), (product) => `${product.name}: ${nfmt(product.dropped)} dropped of ${nfmt(product.totalPatients)}`)}`;
    }
    if (has(q, /script/)) {
        const ranked = [...products].sort((a, b) => (b.scripts || 0) - (a.scripts || 0));
        return `Care scripts by product:\n${numbered(ranked.slice(0, 6), (product) => `${product.name}: ${nfmt(product.scripts)}`)}`;
    }
    if (has(q, /order|unit/)) {
        const ranked = [...products].sort((a, b) => (b.ordersThisMonth || 0) - (a.ordersThisMonth || 0));
        return `Orders this month:\n${numbered(ranked.slice(0, 6), (product) => `${product.name}: ${nfmt(product.ordersThisMonth)} orders, ${nfmt(product.unitsThisMonth)} units`)}`;
    }
    const ranked = [...products].sort((a, b) => (b.totalPatients || 0) - (a.totalPatients || 0));
    return `Products by patients:\n${numbered(ranked.slice(0, 6), (product) => `${product.name}: ${nfmt(product.totalPatients)} patients, ${nfmt(product.pending)} pending, ${nfmt(product.dropped)} dropped`)}`;
}

function scoreScript(script, q) {
    const hay = `${script.title || ''} ${script.question || ''} ${script.summary || ''} ${script.category || ''} ${script.productName || ''}`.toLowerCase();
    const tokens = q.split(/[^a-z0-9]+/).filter((token) => token.length > 2 && !STOP.has(token));
    if (!tokens.length) return 0;
    let score = tokens.reduce((sum, token) => sum + (hay.includes(token) ? 1 : 0), 0);
    if (script.category && q.includes(String(script.category).toLowerCase())) score += 3;
    if (script.productName && q.includes(String(script.productName).toLowerCase())) score += 3;
    return score;
}

async function answerKnowledge(q) {
    const scripts = (await ensureScripts()) || [];
    if (!scripts.length) return 'No published care scripts yet. Publish a script on the Knowledge tab and I can quote it.';
    if (has(q, /(helpful|most used|popular|best script|help the most)/)) {
        const top = [...scripts].sort((a, b) => (b.helpful || 0) - (a.helpful || 0)).slice(0, 5);
        return {
            text: `Most helpful scripts:\n${numbered(top, (script) => `${script.title || script.scriptNumber} — ${[script.productName, script.category, script.helpful ? `${script.helpful} helpful` : ''].filter(Boolean).join(' · ')}`)}`,
            actions: top[0] && top[0].id ? [{ label: 'Open top script', command: `cc:script:${top[0].id}` }] : []
        };
    }
    const ranked = scripts
        .map((script) => ({ script, score: scoreScript(script, q) }))
        .filter((row) => row.score > 0)
        .sort((a, b) => b.score - a.score);
    if (!ranked.length) {
        const topics = [...new Set(scripts.map((script) => script.category).filter(Boolean))];
        return `I couldn't match that to a published script. Topics on file: ${topics.join(', ') || 'none listed'}. Ask about side effects, adherence, storage, or a product name.`;
    }
    const best = ranked[0].script;
    let full = best;
    try {
        full = (await getScript({ scriptId: best.id })) || best;
    } catch (_err) {
        full = best;
    }
    const body = clip(full.answer || full.summary || full.question || 'This script has no answer text yet.');
    const also = ranked
        .slice(1, 3)
        .map((row) => row.script.title)
        .filter(Boolean);
    const heading = [full.title || best.title, full.productName || best.productName].filter(Boolean).join(' · ');
    return {
        text: `${heading}\n${body}${also.length ? `\n\nAlso see: ${also.join('; ')}.` : ''}`,
        actions: best.id ? [{ label: 'Open script', command: `cc:script:${best.id}` }] : []
    };
}

function lookupName(q) {
    const match = q.match(/\b(?:find|search|look up|lookup|who is|open)\s+(.+?)\??$/);
    if (!match) return '';
    const term = match[1].replace(/^(the|a|an|patient|patients)\s+/, '').trim();
    if (term.length < 2) return '';
    if (/^(home|patients?|planner|products?|orders?|knowledge|scripts?)$/.test(term)) return '';
    if (/\b(pending|ongoing|dropped|risk|failed|order|script|product|today|overdue|status|retention|adherence)\b/.test(term)) return '';
    return term;
}

function openTabIntent(q) {
    if (!/\b(open|go to|show me|take me to|switch to)\b/.test(q)) return null;
    if (/\b(pending|risk|overdue|dropped|failed|side effect)\b/.test(q)) return null;
    const hit = TAB_TARGETS.find(([word]) => new RegExp(`\\b${word}s?\\b`).test(q));
    if (!hit) return null;
    return { navigate: `cc:tab:${hit[1]}` };
}

const HELP = {
    home: 'I can tell you who to call today, what is overdue, how retention and reach are doing, and which coaches have the most pending patients. You can also look a patient up by name.',
    patients: 'I can break down status, list pending, high-risk, and failed-call patients, and look someone up by name or patient number. Open takes you to that patient.',
    planner: 'I can read today’s calls, who on your list needs a follow-up, high-risk patients, and time off this week.',
    products: 'I can compare products by patients, drops, and orders this month, and open the patients or scripts for one of them.',
    orders: 'I can list overdue orders, what is due this week, and how many are requested, approved, dispatched, or delivered.',
    knowledge: 'Ask what to say about side effects, adherence, storage, or a product. I quote the published care script and can open it.'
};

async function answerQuestion(q, tab) {
    const text = String(q || '').trim().toLowerCase();
    if (!text) return null;
    if (has(text, /^(hi|hello|hey|help)\b/) || has(text, /what can you/)) return HELP[tab] || HELP.home;
    const patientNumber = text.match(/\bpat-?\d{3,}\b/i);
    if (patientNumber) return answerPatientSearch(patientNumber[0]);
    const destination = openTabIntent(text);
    if (destination) return destination;
    const name = lookupName(text);
    if (name) return answerPatientSearch(name);

    if (has(text, /what.?s on today|today'?s (call|schedule|calendar)|on (my|the) calendar/)) {
        return tab === 'planner' ? answerPlannerToday() : answerCallNext();
    }
    if (has(text, /what.?s overdue|overdue follow/)) return tab === 'orders' ? answerOrders(text) : answerCallNext();
    if (has(text, /who should i call|who (do|should) i call|call next|who to call/)) return answerCallNext();
    if (has(text, /follow-?up/)) return answerFollowUp();
    if (has(text, /time off|vacation|annual leave|on leave/)) return answerTimeOff();
    if (has(text, /high[- ]risk|at risk/)) return answerRisk();
    if (has(text, /failed call|couldn'?t reach|not reached|unknown status/)) return answerStatus('Unknown (Failed calls)');
    if (has(text, /\bpending\b/)) return answerStatus('Pending');
    if (has(text, /\bongoing\b|active patients/)) return answerStatus('Ongoing');
    if (has(text, /dropped|switched|stopped/)) return answerDropped(text);
    if (has(text, /each status|status mix|break down|breakdown|how many patient/)) return answerStatusMix();
    if (has(text, /retention|reach rate|new this month|how (are|is) (we|the programme|the program|my (book|panel))/)) return answerKpis();
    if (has(text, /which coach|coach performance|coaches/)) return answerCoaches();
    if (has(text, /which product/) && has(text, /script/)) return answerProducts(text);
    if (has(text, /script|what should i say|how do i explain|side effect|storage|reimbursement|administration|disease education|adherence script/)) {
        return answerKnowledge(text);
    }
    if ((tab === 'products' || has(text, /product|therapy/)) && has(text, /\b(orders?|units?)\b/)) return answerProducts(text);
    if (has(text, /\borders?\b|dispatch|deliver|promised/)) return answerOrders(text);
    if (has(text, /product|therapy|programme|program/)) return answerProducts(text);
    if (tab === 'knowledge' && text.split(/\s+/).length >= 2) return answerKnowledge(text);
    if (tab === 'orders' && has(text, /overdue|due/)) return answerOrders(text);
    return null;
}

export function loadCareCoachHome() {
    return refresh('home', loadHome).then(homeProfile);
}

export function loadCareCoachPatients() {
    return refresh('patients', loadPatientSnapshot).then(patientsProfile);
}

export function loadCareCoachPlanner() {
    return refresh('planner', loadPlanner).then(plannerProfile);
}

export function loadCareCoachProducts() {
    return refresh('products', loadProducts).then(productsProfile);
}

export function loadCareCoachOrders() {
    return refresh('orders', loadOrders).then(ordersProfile);
}

export function loadCareCoachKnowledge() {
    return refresh('scripts', loadScripts).then(knowledgeProfile);
}
