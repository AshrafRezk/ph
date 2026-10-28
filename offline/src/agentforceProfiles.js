import getWeeklyPlanRecommendations from './apex/getWeeklyPlanRecommendations.js';
import getPhysicianMovementAlerts from './apex/getPhysicianMovementAlerts.js';
import { loadHomeDashboard } from './apex/homeDashboard.js';
import getAccountsTabPage from './apex/getAccountsTabPage.js';
import getAccountVisitContext from './apex/getAccountVisitContext.js';
import getAccountRoi from './apex/getAccountRoi.js';
import getVisitContextInsights from './apex/getVisitContextInsights.js';
import getClassEnginePage from './apex/ClassEngineController.getPage.js';
import fetchPlannerData from './apex/fetchPlannerData.js';
import getMapAccounts from './apex/getMapAccounts.js';
import upsertVisit from './apex/upsertVisit.js';
import { isOffline } from './apex/restHelper.js';
import getRepPresentationManifest from './apex/getRepPresentationManifest.js';
import getMyCourses from './apex/getMyCourses.js';
import { errorMessage } from './views/viewUtils.js';
import {
    loadDashboardProfile,
    loadKamProfile,
    loadMyTeamProfile,
    loadReportProfile,
    loadReportsHubProfile,
    loadWorkforceProfile
} from './leadCopilotProfiles.js';
import {
    loadCareCoachHome,
    loadCareCoachKnowledge,
    loadCareCoachOrders,
    loadCareCoachPatients,
    loadCareCoachPlanner,
    loadCareCoachProducts
} from './careCoachCopilot.js';
import {
    DEFAULT_DAILY_CAP,
    brickSummaryLine,
    buildVisitSlots,
    describePlan,
    parsePlanRequest,
    rankBricks,
    remainingWorkingDays
} from './brickPlan.js';

const MAX_ROWS = 6;

function startOfWeek(date) {
    const d = new Date(date);
    const daysFromSaturday = (d.getDay() + 1) % 7;
    d.setDate(d.getDate() - daysFromSaturday);
    d.setHours(0, 0, 0, 0);
    return d;
}

function addDays(date, days) {
    const d = new Date(date);
    d.setDate(d.getDate() + days);
    return d;
}

export function toApexDate(date) {
    const pad = (n) => String(n).padStart(2, '0');
    return `${date.getFullYear()}-${pad(date.getMonth() + 1)}-${pad(date.getDate())}`;
}

export function weekRange() {
    const start = startOfWeek(new Date());
    return { start, end: addDays(start, 6) };
}

function formatDateLabel(date) {
    return date.toLocaleDateString(undefined, { month: 'short', day: 'numeric' });
}

function formatTime(value) {
    if (!value) return '';
    const d = new Date(value);
    if (Number.isNaN(d.getTime())) return '';
    return d.toLocaleTimeString(undefined, { hour: 'numeric', minute: '2-digit' });
}

function formatDay(value) {
    if (!value) return '';
    const d = new Date(value);
    if (Number.isNaN(d.getTime())) return '';
    return d.toLocaleDateString(undefined, { weekday: 'short', month: 'short', day: 'numeric' });
}

function pct(value) {
    const n = Number(value);
    return Number.isFinite(n) ? `${Math.round(n)}%` : '\u2014';
}

function num(value) {
    const n = Number(value);
    return Number.isFinite(n) ? Math.round(n * 10) / 10 : 0;
}

function has(q, pattern) {
    return pattern.test(q);
}

function numbered(rows, format) {
    return rows.map((row, index) => `${index + 1}. ${format(row)}`).join('\n');
}

function settledValue(result) {
    return result && result.status === 'fulfilled' ? result.value : null;
}

// ---------- Planner ----------

function answerFromMovement(q, movementItems, movementError) {
    if (!has(q, /(sales|sell-?out|brick|movement|physician|doctor|classif|rating|alert|hcp)/)) {
        return null;
    }
    if (movementError && !movementItems.length) {
        return `I could not load physician movement from sales data: ${movementError}`;
    }
    if (!movementItems.length) {
        return 'No physician movement or brick sales alerts showed up in the last two months.';
    }
    return `Physician movement from sales data:\n${numbered(movementItems.slice(0, 8), (row) => row.detail || row.title)}`;
}

let plannerSession = null;

function asAccountList(payload) {
    if (Array.isArray(payload)) return payload;
    if (payload && Array.isArray(payload.accounts)) return payload.accounts;
    return [];
}

function rememberPlannerSession(session) {
    plannerSession = session;
}

export function plannerDayChoices(brickKey) {
    if (!plannerSession) return null;
    const brick = (plannerSession.bricks || []).find((row) => row.key === brickKey);
    if (!brick) return null;
    plannerSession.now = new Date();
    return { brick, days: remainingWorkingDays(plannerSession) };
}

export async function planBrickVisits(intent = {}) {
    if (isOffline()) {
        return 'Planning visits needs an internet connection. Reconnect and try again.';
    }
    if (!plannerSession) {
        return 'Open the assistant on the planner so I can read your bricks first.';
    }
    const brick = (plannerSession.bricks || []).find((row) => row.key === intent.brickKey);
    if (!brick) {
        return 'I could not find that brick among accounts with target visits or class A.';
    }
    plannerSession.now = new Date();
    const workingDays = remainingWorkingDays(plannerSession);
    const days = intent.span === 'day'
        ? workingDays.filter((day) => day.iso === intent.date)
        : workingDays;
    if (!days.length) {
        return intent.span === 'day'
            ? 'That day is not an open working day this week.'
            : `${brick.name} has no working days left this week (Saturday through Wednesday).`;
    }
    const slots = buildVisitSlots({
        accounts: brick.accounts,
        days,
        existingVisits: plannerSession.visits || [],
        dailyCap: plannerSession.dailyCap || DEFAULT_DAILY_CAP,
        now: plannerSession.now || new Date()
    });
    if (!slots.length) {
        return describePlan(brick.name, slots);
    }
    const failures = [];
    for (let index = 0; index < slots.length; index += 3) {
        const batch = slots.slice(index, index + 3);
        const results = await Promise.all(
            batch.map(async (slot) => {
                try {
                    await upsertVisit({
                        accountId: slot.accountId,
                        startDateTime: slot.startDateTime,
                        endDateTime: slot.endDateTime,
                        status: 'Draft',
                        visitType: 'Planned (Automatically)',
                        visitObjective: `Planned in ${brick.name}`
                    });
                    return null;
                } catch (error) {
                    return errorMessage(error) || 'Could not save a visit.';
                }
            })
        );
        results.forEach((failure, offset) => {
            if (failure) failures.push({ slot: batch[offset], failure });
        });
    }
    const saved = slots.filter((slot) => !failures.some((row) => row.slot === slot));
    const savedIds = new Set(saved.map((slot) => slot.accountId));
    plannerSession.visits = [...(plannerSession.visits || []), ...saved];
    plannerSession.bricks.forEach((row) => {
        row.accounts = (row.accounts || []).filter((account) => !savedIds.has(account.id));
    });
    try {
        await fetchPlannerData({
            weekStart: plannerSession.weekStart,
            weekEnd: plannerSession.weekEnd,
            fresh: true
        });
    } catch (_error) {
        /* the drafts are saved; the calendar refresh can retry */
    }
    const summary = describePlan(brick.name, saved);
    if (!failures.length) return summary;
    return `${summary}\n${failures.length} visit${failures.length === 1 ? '' : 's'} could not be saved.`;
}

async function loadPlanner() {
    const { start, end } = weekRange();
    const now = new Date();
    const [recsResult, movementResult, mapResult, weekResult] = await Promise.allSettled([
        getWeeklyPlanRecommendations({ weekStart: toApexDate(start), weekEnd: toApexDate(end) }),
        getPhysicianMovementAlerts(),
        getMapAccounts({}),
        fetchPlannerData({ weekStart: toApexDate(start), weekEnd: toApexDate(end) })
    ]);
    const recsPayload = settledValue(recsResult);
    const movementPayload = settledValue(movementResult);
    const weekPayload = settledValue(weekResult) || {};
    const ranked = rankBricks(asAccountList(settledValue(mapResult)));
    const mapError = mapResult.status === 'rejected'
        ? errorMessage(mapResult.reason) || 'Could not load bricks.'
        : '';
    const recsError = recsResult.status === 'rejected'
        ? errorMessage(recsResult.reason) || 'Could not load week recommendations.'
        : '';
    const movementError = movementResult.status === 'rejected'
        ? errorMessage(movementResult.reason) || 'Could not load physician movement alerts.'
        : '';
    const forecast = (recsPayload && recsPayload.forecast) || null;
    rememberPlannerSession({
        bricks: ranked.all,
        weekStart: toApexDate(start),
        weekEnd: toApexDate(end),
        holidays: weekPayload.publicHolidayDates || [],
        timeOff: weekPayload.timeOffBlocks || [],
        visits: weekPayload.visits || [],
        dailyCap: (forecast && forecast.dailyCallTarget) || DEFAULT_DAILY_CAP,
        now
    });
    const recs = ((recsPayload && recsPayload.recommendations) || []).map((row) => ({
        ...row,
        gapLabel:
            row.visitGap != null
                ? `${row.actualVisits || 0}/${row.targetVisitFrequency || 0} \u00b7 gap ${row.visitGap}`
                : row.frequencyStatus || ''
    }));
    const movementItems = (movementPayload && movementPayload.items) || [];
    const movementInsights = (movementPayload && movementPayload.insights) || [];
    const uncovered = recs.filter((row) => !row.plannedThisWeek);

    const insights = [`Week of ${formatDateLabel(start)} \u2013 ${formatDateLabel(end)}.`];
    if (ranked.top.length) {
        insights.push(`Bricks to plan: ${ranked.top.map((brick) => brick.name).join(', ')}.`);
    } else if (!mapError) {
        insights.push('No account is assigned to a brick yet, so there is no zone to route.');
    }
    if (forecast) {
        insights.push(
            `Pace: ${forecast.paceLabel || '\u2014'} \u00b7 ${forecast.dailyFrequency || 0} visits/day over ${
                forecast.remainingWorkingDays || 0
            } remaining working days.`
        );
    }
    movementInsights.slice(0, 6).forEach((line) => insights.push(line));
    if (uncovered.length) {
        insights.push(`Priority to plan: ${uncovered.slice(0, 3).map((row) => row.accountName).join(', ')}.`);
    }

    return {
        subtitle: 'Planner \u00b7 bricks to plan',
        placeholder: 'Ask which brick to plan, or plan a day',
        chips: ['Which bricks should I plan?', 'Plan the top brick this week', 'How is my pace?'],
        remoteAsk: true,
        stats: forecast
            ? [
                  { label: 'Planned', value: forecast.plannedVisitCount || 0 },
                  { label: 'Visits / day', value: forecast.dailyFrequency || 0 },
                  { label: 'To plan', value: uncovered.length, tone: uncovered.length ? 'warn' : 'good' }
              ]
            : [],
        sections: [
            {
                title: 'Bricks to plan',
                meta: 'Top 3',
                empty: mapError || 'No account is assigned to a brick yet. Once a 702 brick or zone is set, the top three show up here.',
                items: ranked.top.map((brick) => ({
                    title: brick.name,
                    lines: [brickSummaryLine(brick)],
                    actions: [
                        { label: 'Plan week', command: `week:${brick.key}` },
                        { label: 'Plan a day', command: `day:${brick.key}` }
                    ]
                }))
            },
            ...(movementItems.length || movementError
                ? [
                      {
                          title: 'Physician movement',
                          empty: movementError,
                          items: movementItems.map((row) => ({
                              title: row.title || row.accountName || 'Alert',
                              lines: [row.detail],
                              accountId: row.accountId,
                              action: 'Plan'
                          }))
                      }
                  ]
                : []),
            {
                title: 'Week recommendations',
                meta: forecast ? forecast.paceLabel || '' : '',
                empty: recsError || 'No open frequency gaps for this week.',
                items: recs.map((row) => ({
                    title: row.accountName || 'Account',
                    lines: [row.gapLabel, row.reason],
                    accountId: row.accountId,
                    action: 'Add draft'
                }))
            }
        ],
        insights,
        planRequest(text) {
            if (plannerSession) plannerSession.now = new Date();
            return parsePlanRequest(text, plannerSession);
        },
        answer(q) {
            if (has(q, /(brick|zone)/) && !has(q, /(sales|sell-?out|movement|alert)/)) {
                return ranked.top.length
                    ? `Bricks to plan:\n${numbered(ranked.top, (brick) => `${brick.name} \u2014 ${brickSummaryLine(brick)}`)}`
                    : 'No account is assigned to a brick yet, so I cannot rank a zone. I look for bricks whose accounts still have target visits, or class A.';
            }
            const movement = answerFromMovement(q, movementItems, movementError);
            if (movement) return movement;
            if (has(q, /(behind|recommend|who|priorit|lcf|gap)/) && uncovered.length) {
                return `Accounts to plan this week:\n${numbered(uncovered.slice(0, 5), (row) => `${row.accountName} \u2014 ${row.gapLabel}`)}`;
            }
            if (has(q, /(pace|frequency|per day|daily)/) && forecast) {
                return `${forecast.plannedVisitCount || 0} visits planned, ${forecast.dailyFrequency || 0}/day over ${
                    forecast.remainingWorkingDays || 0
                } remaining working days. Pace: ${forecast.paceLabel || '\u2014'}.`;
            }
            return null;
        }
    };
}

// ---------- Home ----------

async function loadHome() {
    const dash = await loadHomeDashboard({});
    const metrics = (dash && dash.metrics) || {};
    const todayVisits = (dash && dash.todayVisits) || [];
    const todayTimeOff = (dash && dash.todayTimeOff) || [];
    const nbc = (dash && dash.nextBestCustomers) || [];
    const byClass = (metrics.byClassification || []).filter((row) => row && row.classification);
    const weakest = byClass
        .filter((row) => Number(row.targetVisits) > 0)
        .sort((a, b) => num(a.visitCoveragePercent) - num(b.visitCoveragePercent))[0];

    const coverageLine = `Visit coverage ${pct(metrics.visitCoveragePercent)} \u00b7 customer coverage ${pct(
        metrics.customerCoveragePercent
    )} \u00b7 RF ${pct(metrics.rfPercentTotal)}. AM attainment ${pct(
        metrics.amAttainmentPercent
    )} on hospitals. PM attainment ${pct(metrics.pmAttainmentPercent)} on HCP, clinic, and pharmacy.`;
    const callsLine = `${num(metrics.actualVisitsTotal)} of ${num(metrics.targetVisitsTotal)} target visits done, ${num(
        metrics.remainingCalls
    )} calls remaining this cycle.`;
    const insights = [coverageLine, callsLine];
    if (weakest) {
        insights.push(`Weakest class: ${weakest.classification} at ${pct(weakest.visitCoveragePercent)} visit coverage.`);
    }
    insights.push(
        todayVisits.length
            ? `${todayVisits.length} visit(s) today${todayTimeOff.length ? ` and ${todayTimeOff.length} time-off block(s)` : ''}.`
            : todayTimeOff.length
              ? 'Time off today \u2014 no visits scheduled.'
              : 'Nothing scheduled today yet.'
    );
    const unplannedNbc = nbc.filter((row) => !row.plannedToday);
    if (unplannedNbc.length) {
        insights.push(`Best next customer: ${unplannedNbc[0].accountName}.`);
    }

    const visitLine = (v) => `${formatTime(v.startDateTime)} \u2014 ${v.accountName || v.name || 'Visit'} (${v.status || '\u2014'})`;
    const nbcLine = (row) =>
        `${row.accountName} \u2014 ${num(row.actualVisits)}/${num(row.targetVisits)}, gap ${num(row.visitGap)}${
            row.calculatedClassification ? `, class ${row.calculatedClassification}` : ''
        }${row.plannedToday ? ', planned today' : ''}`;

    return {
        subtitle: 'Home \u00b7 today & coverage',
        placeholder: 'Ask about today, coverage, or who to see next',
        chips: ['Who should I see next?', "What's on today?", 'How is my coverage?'],
        stats: [
            { label: 'Visit coverage', value: pct(metrics.visitCoveragePercent), tone: num(metrics.visitCoveragePercent) < 50 ? 'warn' : '' },
            { label: 'AM attainment', value: pct(metrics.amAttainmentPercent), tone: num(metrics.amAttainmentPercent) < 50 ? 'warn' : '' },
            { label: 'PM attainment', value: pct(metrics.pmAttainmentPercent), tone: num(metrics.pmAttainmentPercent) < 50 ? 'warn' : '' },
            { label: 'Calls left', value: num(metrics.remainingCalls) },
            { label: 'Today', value: todayVisits.length }
        ],
        sections: [
            {
                title: "Today's visits",
                meta: todayVisits.length ? `${todayVisits.length} scheduled` : '',
                empty: 'No visits scheduled today.',
                items: todayVisits.map((v) => ({
                    title: v.accountName || v.name || 'Visit',
                    lines: [`${formatTime(v.startDateTime)} \u00b7 ${v.status || ''}`]
                }))
            },
            {
                title: 'Next best customers',
                empty: 'No next-best customers right now.',
                items: nbc.map((row) => ({
                    title: row.accountName || 'Account',
                    lines: [
                        `${num(row.actualVisits)}/${num(row.targetVisits)} \u00b7 gap ${num(row.visitGap)}${
                            row.calculatedClassification ? ` \u00b7 ${row.calculatedClassification}` : ''
                        }`,
                        row.description
                    ],
                    accountId: row.plannedToday ? null : row.accountId,
                    action: 'Plan'
                }))
            }
        ],
        insights,
        answer(q) {
            if (has(q, /(who|next|best|recommend|priorit|should i see)/)) {
                return nbc.length
                    ? `Next best customers:\n${numbered(nbc.slice(0, 5), nbcLine)}`
                    : 'No next-best customers are listed right now.';
            }
            if (has(q, /(time off|tot|leave|vacation)/)) {
                return todayTimeOff.length
                    ? `Time off today: ${todayTimeOff.map((t) => t.typeLabel || t.name).join(', ')}.`
                    : 'No time off today.';
            }
            if (has(q, /(today|schedule|agenda|on for|visits)/)) {
                return todayVisits.length
                    ? `Today's visits:\n${numbered(todayVisits.slice(0, 10), visitLine)}`
                    : 'No visits are scheduled today.';
            }
            if (has(q, /(cover|rf|lf|mf|target|remaining|progress|class)/)) {
                const classLines = byClass
                    .map((row) => `${row.classification}: ${pct(row.visitCoveragePercent)} visit coverage, RF ${pct(row.rfPercent)}`)
                    .join('\n');
                return [coverageLine, callsLine, classLines].filter(Boolean).join('\n');
            }
            return null;
        }
    };
}

// ---------- Accounts tab ----------

function isBehind(row) {
    return row && (row.paceStatus === 'behind' || row.paceStatus === 'critical');
}

async function loadAccountsTab() {
    const page = await getAccountsTabPage({ scope: 'in', offset: 0, pageSize: 100 });
    const rows = (page && page.rows) || [];
    const behind = rows
        .filter(isBehind)
        .sort((a, b) => num(b.targetVisits) - num(b.actualVisits) - (num(a.targetVisits) - num(a.actualVisits)));
    const kols = rows.filter((row) => row.isKol);
    const classCounts = {};
    rows.forEach((row) => {
        const key = row.classification || 'Unclassified';
        classCounts[key] = (classCounts[key] || 0) + 1;
    });
    const classMix = Object.keys(classCounts)
        .sort()
        .map((key) => `${key} ${classCounts[key]}`)
        .join(', ');

    const insights = [];
    if (page && page.hasTimeCard === false) {
        insights.push('No active plan cycle (time card) for this month.');
    }
    insights.push(
        `${page && page.monthLabel ? `${page.monthLabel}: ` : ''}${num(page && page.inPlanCount)} in plan, ${num(
            page && page.outPlanCount
        )} out of plan.`
    );
    insights.push(`${num(page && page.behindPaceCount)} account(s) behind visit pace.`);
    if (classMix) insights.push(`Class mix (in plan): ${classMix}.`);
    if (kols.length) insights.push(`${kols.length} KOL(s) in plan.`);

    const behindLine = (row) =>
        `${row.accountName} \u2014 ${num(row.actualVisits)}/${num(row.targetVisits)} visits${
            row.classification ? `, class ${row.classification}` : ''
        }${row.specialty ? `, ${row.specialty}` : ''}`;

    return {
        subtitle: 'Accounts \u00b7 plan-cycle worklist',
        placeholder: 'Ask who is behind, class mix, or KOLs in plan',
        chips: ['Who is behind pace?', 'What is my class mix?', 'Which KOLs are in plan?'],
        stats: [
            { label: 'In plan', value: num(page && page.inPlanCount) },
            { label: 'Behind pace', value: num(page && page.behindPaceCount), tone: num(page && page.behindPaceCount) ? 'warn' : 'good' },
            { label: 'KOLs', value: kols.length }
        ],
        sections: [
            {
                title: 'Behind pace',
                meta: `${num(page && page.behindPaceCount)} behind`,
                empty: 'No in-plan accounts are behind pace.',
                items: behind.map((row) => ({
                    title: row.accountName || 'Account',
                    lines: [
                        `${num(row.actualVisits)}/${num(row.targetVisits)} visits \u00b7 ${row.paceStatusLabel || row.paceStatus}`,
                        [row.classification, row.specialty].filter(Boolean).join(' \u00b7 ')
                    ],
                    accountId: row.accountId,
                    action: 'Plan'
                }))
            }
        ],
        insights,
        answer(q) {
            if (has(q, /(kol|key opinion)/)) {
                return kols.length
                    ? `KOLs in plan:\n${numbered(kols.slice(0, 8), (row) => `${row.accountName}${row.specialty ? ` (${row.specialty})` : ''}`)}`
                    : 'No KOLs are in plan this cycle.';
            }
            if (has(q, /(class|mix|a1|b1|c1|segment)/)) {
                return classMix ? `Class mix (in plan): ${classMix}.` : 'No classification data for in-plan accounts.';
            }
            if (has(q, /(behind|pace|gap|who|priorit|visit next|critical)/)) {
                return behind.length
                    ? `Behind pace (${behind.length}):\n${numbered(behind.slice(0, 8), behindLine)}`
                    : 'No in-plan accounts are behind pace.';
            }
            if (has(q, /(how many|count|in plan|out of plan|total)/)) {
                return insights.slice(0, 2).join(' ');
            }
            return null;
        }
    };
}

// ---------- Account record (overlay) ----------

async function loadAccountRecord(ctx) {
    const accountId = ctx.record && ctx.record.recordId;
    const [visitResult, roiResult] = await Promise.allSettled([
        getAccountVisitContext({ accountId }),
        getAccountRoi({ accountId })
    ]);
    const visit = settledValue(visitResult) || {};
    const roi = settledValue(roiResult) || {};
    const name = visit.accountName || roi.accountName || 'This account';
    const future = visit.futureVisits || [];
    const previous = visit.previousVisits || [];
    const productRanks = roi.productRanks || [];

    const insights = [];
    insights.push(
        future.length
            ? `Next visit: ${formatDay(future[0].startDateTime)} (${future[0].status || '\u2014'}).`
            : 'No visit planned for the rest of this month.'
    );
    if (previous.length) {
        insights.push(`Last visit: ${formatDay(previous[0].startDateTime)} (${previous[0].status || '\u2014'}).`);
    }
    if (roi.hasProducts) {
        if (roi.gapValue) insights.push(`Potential gap: ${roi.currencyIsoCode || ''} ${Math.round(roi.gapValue).toLocaleString('en-US')}.`);
        if (roi.roiMultiple != null) insights.push(`ROI multiple: ${num(roi.roiMultiple)}x on ${roi.currencyIsoCode || ''} ${Math.round(roi.totalSpendYtd || 0).toLocaleString('en-US')} YTD spend.`);
    }
    if (roi.callToAction) insights.push(roi.callToAction);

    const visitLine = (v) => `${formatDay(v.startDateTime)} ${formatTime(v.startDateTime)} \u2014 ${v.status || '\u2014'}`;

    return {
        title: name,
        subtitle: `Account \u00b7 ${ctx.tabLabel || 'record'}`,
        placeholder: `Ask about ${name}: last visit, next visit, ROI`,
        chips: ['When did I last visit?', 'Is a visit planned?', 'What is the ROI?'],
        stats: [
            { label: 'Upcoming', value: future.length, tone: future.length ? 'good' : 'warn' },
            { label: 'Recent visits', value: previous.length },
            { label: 'ROI', value: roi.roiMultiple != null ? `${num(roi.roiMultiple)}x` : '\u2014' }
        ],
        sections: [
            {
                title: 'Upcoming visits',
                empty: 'Nothing planned for the rest of this month.',
                items: future.length
                    ? future.map((v) => ({ title: formatDay(v.startDateTime), lines: [`${formatTime(v.startDateTime)} \u00b7 ${v.status || ''}`] }))
                    : [{ title: 'No visit planned this month', lines: ['Add a draft visit in the planner.'], accountId, action: 'Plan' }]
            },
            {
                title: 'Recent visits',
                empty: 'No previous visits found.',
                items: previous.map((v) => ({ title: formatDay(v.startDateTime), lines: [v.status] }))
            }
        ],
        insights,
        answer(q) {
            if (has(q, /(roi|return|spend|gap|potential|sales|product)/)) {
                if (!roi.hasProducts) return `No product or spend data is available for ${name}.`;
                const ranks = productRanks
                    .slice(0, 5)
                    .map((p, index) => `${index + 1}. ${p.productName || p.name || 'Product'}`)
                    .join('\n');
                return [insights.filter((line) => /gap|ROI/.test(line)).join(' '), roi.callToAction, ranks]
                    .filter(Boolean)
                    .join('\n');
            }
            if (has(q, /(last|previous|recent|history|when did)/)) {
                return previous.length
                    ? `Recent visits to ${name}:\n${numbered(previous, visitLine)}`
                    : `No previous visits to ${name} were found.`;
            }
            if (has(q, /(next|planned|upcoming|schedule|plan)/)) {
                return future.length
                    ? `Planned visits to ${name}:\n${numbered(future, visitLine)}`
                    : `No visit to ${name} is planned for the rest of this month.`;
            }
            return null;
        }
    };
}

// ---------- Visit call ----------

async function loadVisitCall(ctx) {
    if (!ctx.visitId) {
        return {
            subtitle: 'Visit call',
            placeholder: 'Open a visit to ask about it',
            chips: [],
            sections: [],
            insights: ['No visit is open. Open a visit from the planner or home to get call prep here.'],
            answer: () => 'No visit is open yet. Open one from the planner or home.'
        };
    }
    const payload = (await getVisitContextInsights({ visitId: ctx.visitId })) || {};
    const summary = payload.visitSummary || {};
    const prior = payload.zetaPriorVisits || [];
    const mine = payload.territoryPriorVisits || [];
    const name = summary.accountName || 'This visit';
    const productsSeen = [...new Set(prior.map((v) => v.productsDiscussed).filter(Boolean).flatMap((p) => String(p).split(/[;,]/).map((s) => s.trim())).filter(Boolean))];

    const insights = [];
    insights.push(
        `${formatDay(summary.startDateTime)} ${formatTime(summary.startDateTime)} \u00b7 ${summary.status || '\u2014'}.`
    );
    if (summary.objective) insights.push(`Objective: ${summary.objective}.`);
    if (summary.productsDiscussed) insights.push(`Products on this call: ${summary.productsDiscussed}.`);
    insights.push(
        prior.length
            ? `${prior.length} prior visit(s) by the team, ${mine.length} by you. Last: ${formatDay(prior[0].startDateTime)}.`
            : 'First recorded visit to this account.'
    );
    if (productsSeen.length) insights.push(`Previously discussed: ${productsSeen.slice(0, 5).join(', ')}.`);

    const priorLine = (v) =>
        `${formatDay(v.startDateTime)}${v.repName ? ` (${v.repName})` : ''}${v.productsDiscussed ? ` \u2014 ${v.productsDiscussed}` : ''}${
            v.notesSnippet ? `: ${v.notesSnippet}` : ''
        }`;

    return {
        title: name,
        subtitle: 'Visit call \u00b7 call prep',
        placeholder: `Ask about ${name}: last visit, products, notes`,
        chips: ['What happened last visit?', 'Which products were discussed?', 'Give me a call brief'],
        stats: [
            { label: 'Status', value: summary.status || '\u2014' },
            { label: 'Prior visits', value: prior.length },
            { label: 'By you', value: mine.length }
        ],
        sections: [
            {
                title: 'Prior visits',
                meta: prior.length ? `${prior.length} found` : '',
                empty: 'No prior visits to this account.',
                items: prior.map((v) => ({
                    title: `${formatDay(v.startDateTime)}${v.repName ? ` \u00b7 ${v.repName}` : ''}`,
                    lines: [v.productsDiscussed, v.notesSnippet]
                }))
            }
        ],
        insights,
        answer(q) {
            if (has(q, /(product|detail|brand|drug)/)) {
                const current = summary.productsDiscussed ? `On this call: ${summary.productsDiscussed}.` : '';
                const before = productsSeen.length ? `Discussed before: ${productsSeen.join(', ')}.` : 'No products recorded on prior visits.';
                return [current, before].filter(Boolean).join('\n');
            }
            if (has(q, /(last|previous|prior|history|happened|notes)/)) {
                return prior.length
                    ? `Prior visits to ${name}:\n${numbered(prior.slice(0, 5), priorLine)}`
                    : `No prior visits to ${name} were found.`;
            }
            if (has(q, /(brief|prep|summary|objective|goal|what should)/)) {
                return `${name}\n${insights.join('\n')}`;
            }
            return null;
        }
    };
}

// ---------- Class engine ----------

async function loadClassEngine() {
    const page = (await getClassEnginePage({})) || {};
    const cycle = page.cycle || {};
    const accounts = page.accounts || [];
    const missing = accounts.filter((row) => !row.chosenClass);
    const counts = {};
    accounts.forEach((row) => {
        const key = row.chosenClass || row.rxClass || 'Unclassified';
        counts[key] = (counts[key] || 0) + 1;
    });
    const mix = Object.keys(counts)
        .sort()
        .map((key) => `${key} ${counts[key]}`)
        .join(', ');
    const insights = [
        `Cycle ${cycle.quarter || '\u2014'} \u00b7 status ${cycle.status || 'Draft'}.`,
        `${accounts.length} account(s), ${missing.length} still without a chosen class.`
    ];
    if (mix) insights.push(`Class mix: ${mix}.`);

    return {
        subtitle: 'Class engine \u00b7 quarterly classification',
        placeholder: 'Ask who still needs a class, or the class mix',
        chips: ['Who still needs a class?', 'What is the class mix?', 'What is the cycle status?'],
        stats: [
            { label: 'Status', value: cycle.status || 'Draft' },
            { label: 'Accounts', value: accounts.length },
            { label: 'Need class', value: missing.length, tone: missing.length ? 'warn' : 'good' }
        ],
        sections: [
            {
                title: 'Needs a chosen class',
                meta: `${missing.length} left`,
                empty: 'Every account has a chosen class.',
                items: missing.map((row) => ({
                    title: row.accountName || 'Account',
                    lines: [row.rxClass ? `Suggested: ${row.rxClass}` : '']
                }))
            }
        ],
        insights,
        answer(q) {
            if (has(q, /(need|missing|left|who|without|pending)/)) {
                return missing.length
                    ? `Still need a chosen class (${missing.length}):\n${numbered(missing.slice(0, 10), (row) => `${row.accountName}${row.rxClass ? ` \u2014 suggested ${row.rxClass}` : ''}`)}`
                    : 'Every account already has a chosen class.';
            }
            if (has(q, /(mix|distribution|how many|count)/)) return mix ? `Class mix: ${mix}.` : 'No classes yet.';
            if (has(q, /(status|cycle|submit|approv|quarter)/)) return insights[0];
            return null;
        }
    };
}

// ---------- Time off ----------

async function loadTimeOff() {
    const { start, end } = weekRange();
    const data = (await fetchPlannerData({ weekStart: toApexDate(start), weekEnd: toApexDate(end) })) || {};
    const blocks = data.timeOffBlocks || [];
    const holidays = data.publicHolidayDates || [];
    const line = (t) =>
        `${t.typeLabel || t.name || 'Time off'} \u2014 ${formatDay(t.startDateTime)}${
            t.isFullDay ? '' : ` ${formatTime(t.startDateTime)}\u2013${formatTime(t.endDateTime)}`
        }${t.stage ? ` (${t.stage})` : ''}`;
    const insights = [
        `Week of ${formatDateLabel(start)} \u2013 ${formatDateLabel(end)}.`,
        blocks.length ? `${blocks.length} time-off block(s) this week.` : 'No time off this week.'
    ];
    if (holidays.length) insights.push(`Public holidays: ${holidays.map((d) => formatDay(d)).join(', ')}.`);
    const pending = blocks.filter((t) => t.stage && !/approv/i.test(t.stage));
    if (pending.length) insights.push(`${pending.length} request(s) not approved yet.`);

    return {
        subtitle: 'Time off \u00b7 this week',
        placeholder: 'Ask about time off or holidays this week',
        chips: ['What time off do I have?', 'Any holidays this week?'],
        stats: [
            { label: 'Time off', value: blocks.length },
            { label: 'Not approved', value: pending.length, tone: pending.length ? 'warn' : '' },
            { label: 'Holidays', value: holidays.length }
        ],
        sections: [
            {
                title: 'Time off this week',
                empty: 'No time off this week.',
                items: blocks.map((t) => ({ title: t.typeLabel || t.name || 'Time off', lines: [line(t), t.stage] }))
            }
        ],
        insights,
        answer(q) {
            if (has(q, /holiday/)) return holidays.length ? insights[2] : 'No public holidays this week.';
            if (has(q, /(time off|tot|leave|pending|approv|request|off)/)) {
                return blocks.length ? `Time off this week:\n${numbered(blocks, line)}` : 'No time off this week.';
            }
            return null;
        }
    };
}

// ---------- CLM ----------

async function loadClm() {
    const entries = (await getRepPresentationManifest()) || [];
    const byProduct = {};
    entries.forEach((e) => {
        const key = e.productName || 'General';
        (byProduct[key] = byProduct[key] || []).push(e);
    });
    const products = Object.keys(byProduct).sort();
    return {
        subtitle: 'CLM \u00b7 presentations',
        placeholder: 'Ask which presentations exist for a product',
        chips: ['Which presentations are available?', 'Which products have decks?'],
        stats: [
            { label: 'Presentations', value: entries.length },
            { label: 'Products', value: products.length }
        ],
        sections: [
            {
                title: 'Available presentations',
                meta: `${entries.length} total`,
                empty: 'No presentations available.',
                items: entries.map((e) => ({
                    title: e.name,
                    lines: [[e.productName, e.slideCount ? `${e.slideCount} slides` : ''].filter(Boolean).join(' \u00b7 ')]
                }))
            }
        ],
        insights: [
            `${entries.length} presentation(s) across ${products.length} product(s).`,
            products.length ? `Products: ${products.join(', ')}.` : ''
        ].filter(Boolean),
        answer(q) {
            const product = products.find((p) => q.includes(p.toLowerCase()));
            if (product) {
                return `${product} presentations:\n${numbered(byProduct[product], (e) => `${e.name}${e.slideCount ? ` (${e.slideCount} slides)` : ''}`)}`;
            }
            if (has(q, /(product|brand)/)) return products.length ? `Products with decks: ${products.join(', ')}.` : 'No decks yet.';
            if (has(q, /(presentation|deck|available|clm|slide)/)) {
                return entries.length ? `Available presentations:\n${numbered(entries.slice(0, 10), (e) => e.name)}` : 'No presentations available.';
            }
            return null;
        }
    };
}

// ---------- Learning ----------

async function loadLearning() {
    const courses = (await getMyCourses()) || [];
    const open = courses.filter((c) => c.status !== 'Completed');
    const done = courses.length - open.length;
    return {
        subtitle: 'My learning \u00b7 courses',
        placeholder: 'Ask what courses are left',
        chips: ['What courses are left?', 'How much have I completed?'],
        stats: [
            { label: 'Completed', value: `${done}/${courses.length}`, tone: open.length ? '' : 'good' },
            { label: 'Open', value: open.length, tone: open.length ? 'warn' : '' }
        ],
        sections: [
            {
                title: 'In progress / not started',
                meta: `${open.length} open`,
                empty: 'All courses are completed.',
                items: open.map((c) => ({ title: c.title || 'Course', lines: [`${c.status} \u00b7 ${num(c.progress)}%`] }))
            }
        ],
        insights: [`${done} of ${courses.length} course(s) completed.`],
        answer(q) {
            if (has(q, /(left|open|todo|remaining|next|not started|in progress|which)/)) {
                return open.length
                    ? `Open courses:\n${numbered(open, (c) => `${c.title} \u2014 ${c.status}, ${num(c.progress)}%`)}`
                    : 'All your courses are completed.';
            }
            if (has(q, /(complete|done|progress|certificate)/)) return `${done} of ${courses.length} course(s) completed.`;
            return null;
        }
    };
}

// ---------- Generic (reports, dashboards, chatter, lists) ----------

const GENERIC_HINTS = {
    'view-chatter': 'Your Chatter feed and posts.',
    'view-entity': 'Search, filter, or open a record from the list.',
    'view-kpis': 'Your SFE framework scorecard — coverage, right frequency, daily call rate, and visit coverage.',
    'view-unsupported': 'This tab opens in Salesforce.'
};

async function loadGeneric(ctx) {
    const label = ctx.tabLabel || 'This tab';
    return {
        subtitle: label,
        placeholder: `Ask about ${label}`,
        chips: [],
        sections: [],
        insights: [`You are on ${label}. ${GENERIC_HINTS[ctx.panel] || ''}`.trim()],
        answer: () =>
            `I don't have insights for ${label} yet. Open Home, Planner, Accounts, or a visit for guidance based on your data.`
    };
}

const LOADERS = {
    home: loadHome,
    planner: loadPlanner,
    accounts: loadAccountsTab,
    account: loadAccountRecord,
    visit: loadVisitCall,
    classEngine: loadClassEngine,
    timeoff: loadTimeOff,
    clm: loadClm,
    learning: loadLearning,
    report: loadReportProfile,
    dashboard: loadDashboardProfile,
    workforce: loadWorkforceProfile,
    myTeam: loadMyTeamProfile,
    kam: loadKamProfile,
    reportsHub: loadReportsHubProfile,
    ccHome: loadCareCoachHome,
    ccPatients: loadCareCoachPatients,
    ccPlanner: loadCareCoachPlanner,
    ccProducts: loadCareCoachProducts,
    ccOrders: loadCareCoachOrders,
    ccKnowledge: loadCareCoachKnowledge,
    generic: loadGeneric
};

const PANEL_PROFILES = {
    'view-home': 'home',
    'view-field-requests': 'requests',
    'view-field-orders': 'orders',
    'view-planner': 'planner',
    'view-accounts': 'accounts',
    'view-visitcall': 'visit',
    'view-class-engine': 'classEngine',
    'view-kpis': 'generic',
    'view-timeoff': 'timeoff',
    'view-clm': 'clm',
    'view-learning': 'learning',
    'view-reports': 'report',
    'view-dashboards': 'dashboard',
    'view-workforce': 'workforce',
    'view-my-team': 'myTeam',
    'view-kam': 'kam',
    'view-reports-hub': 'reportsHub',
    'view-care-coach-home': 'ccHome',
    'view-care-coach-patients': 'ccPatients',
    'view-care-coach-planner': 'ccPlanner',
    'view-care-coach-products': 'ccProducts',
    'view-care-coach-orders': 'ccOrders',
    'view-care-coach-knowledge': 'ccKnowledge'
};

const LABEL_PROFILES = {
    reports: 'report',
    dashboards: 'dashboard',
    workforce: 'workforce',
    'management home': 'workforce',
    'my team': 'myTeam',
    'reports hub': 'reportsHub'
};

export function profileKeyFor(ctx) {
    if (ctx.record && ctx.record.recordId && ctx.record.objectApiName === 'Account') return 'account';
    if (PANEL_PROFILES[ctx.panel]) return PANEL_PROFILES[ctx.panel];
    const label = String(ctx.tabLabel || '').trim().toLowerCase();
    if (LABEL_PROFILES[label]) return LABEL_PROFILES[label];
    if (label.includes('kam')) return 'kam';
    return 'generic';
}

export async function loadProfile(ctx) {
    const loader = LOADERS[profileKeyFor(ctx)] || loadGeneric;
    return loader(ctx);
}
