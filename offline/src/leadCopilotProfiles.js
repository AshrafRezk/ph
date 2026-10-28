import getTeamKpis from './apex/ManagementKpiController.getTeamKpis.js';
import getMyTeamTree from './apex/MyTeamController.getMyTeamTree.js';
import getKamDashboard from './apex/KamManagementController.getDashboardData.js';
import getPendingAccountApprovals from './apex/getPendingAccountApprovals.js';
import getPendingExpenseApprovals from './apex/getPendingExpenseApprovals.js';
import getPendingPlanApprovals from './apex/getPendingPlanApprovals.js';
import getPendingTimeOff from './apex/TimeOffRequestController.getPendingApprovals.js';
import getPendingMeetings from './apex/MeetingPlannerController.getPendingMeetingApprovals.js';
import { loadTileTargets } from './apex/getTileTargets.js';
import { cachePayload } from './views/tabCache.js';
import { summarizeDashboardCatalog, summarizeReportCatalog } from './analyticsBrief.js';

const REPORT_LIST_KEY = 'reports.catalog.v2';
const DASHBOARD_LIST_KEY = 'dashboards.catalog.v2';

const HUB_CARDS = [
    {
        id: 'working-days-analysis',
        title: 'Working Days Analysis',
        description: 'Working days, activity, visits, and time off by territory and month.'
    },
    {
        id: 'medical-rep-360',
        title: 'Medical Rep 360',
        description: 'Coverage, visit targets, CLM usage, and coaching trends.'
    }
];

function has(q, pattern) {
    return pattern.test(q);
}

function numbered(rows, format) {
    return rows.map((row, index) => `${index + 1}. ${format(row)}`).join('\n');
}

function settled(result) {
    return result && result.status === 'fulfilled' ? result.value : null;
}

function listOf(value) {
    if (Array.isArray(value)) return value;
    if (value && Array.isArray(value.rows)) return value.rows;
    if (value && Array.isArray(value.records)) return value.records;
    return [];
}

function pct(value) {
    const n = Number(value);
    if (!Number.isFinite(n)) return '\u2014';
    const shown = n <= 1 && n > 0 ? Math.round(n * 100) : Math.round(n);
    return `${shown}%`;
}

function asNumber(value) {
    if (typeof value === 'number' && Number.isFinite(value)) return value;
    const n = Number(String(value ?? '').replace(/[^0-9.-]/g, ''));
    return Number.isFinite(n) && /\d/.test(String(value ?? '')) ? n : null;
}

function rowLabel(row) {
    if (!row || typeof row !== 'object') return '';
    return (
        row.accountName ||
        row.repName ||
        row.employeeName ||
        row.requesterName ||
        row.ownerName ||
        row.name ||
        row.expenseName ||
        row.subject ||
        row.title ||
        ''
    );
}

function findNamed(q, rows) {
    const named = (rows || []).filter((row) => row && row.name);
    const exact = named
        .filter((row) => q.includes(String(row.name).toLowerCase()))
        .sort((a, b) => String(b.name).length - String(a.name).length);
    if (exact.length) return exact[0];
    const partial = named
        .map((row) => {
            const tokens = String(row.name)
                .toLowerCase()
                .split(/\s+/)
                .filter((token) => token.length > 3);
            const hits = tokens.filter((token) => q.includes(token)).length;
            return { row, hits, len: tokens.length };
        })
        .filter((item) => item.hits > 0 && item.hits >= Math.min(2, item.len))
        .sort((a, b) => b.hits - a.hits || String(b.row.name).length - String(a.row.name).length);
    return partial.length ? partial[0].row : null;
}

function openAction(objectApiName, id) {
    if (!id) return [];
    return [{ label: 'Open', command: `open:${objectApiName}:${id}` }];
}

function toneForPercent(value) {
    const n = Number(value);
    const shown = n <= 1 && n > 0 ? n * 100 : n;
    if (!Number.isFinite(shown)) return '';
    if (shown >= 80) return 'good';
    if (shown < 60) return 'warn';
    return '';
}

function reportListFrom(ctx) {
    if (ctx.analytics && ctx.analytics.kind === 'report-list') return ctx.analytics;
    return summarizeReportCatalog(cachePayload(REPORT_LIST_KEY) || []);
}

function dashboardListFrom(ctx) {
    if (ctx.analytics && ctx.analytics.kind === 'dashboard-list') return ctx.analytics;
    return summarizeDashboardCatalog(cachePayload(DASHBOARD_LIST_KEY) || []);
}

function formatLine(row) {
    return [row.format, row.folder].filter(Boolean).join(' \u00b7 ');
}

function describeReport(brief) {
    const totals = (brief.totals || []).map((item) => `${item.label} ${item.value}`).join(', ');
    const lines = [`${brief.name} is a ${String(brief.format || 'tabular').toLowerCase()} report${brief.folder ? ` in ${brief.folder}` : ''}.`];
    if (totals) lines.push(`Totals: ${totals}.`);
    if (brief.chart) lines.push(`Chart: ${brief.chart}.`);
    if ((brief.groups || []).length) {
        lines.push(
            `Top groups:\n${numbered(brief.groups.slice(0, 6), (group) => {
                const metrics = (group.metrics || []).map((item) => `${item.label} ${item.value}`).join(', ');
                return `${group.label} \u2014 ${group.count} record(s)${metrics ? `, ${metrics}` : ''}`;
            })}`
        );
    } else if ((brief.topRows || []).length) {
        lines.push(`First rows:\n${numbered(brief.topRows.slice(0, 5), (row) => row)}`);
    }
    if ((brief.filters || []).length) lines.push(`Filters: ${brief.filters.join('; ')}.`);
    if ((brief.columns || []).length) lines.push(`Columns: ${brief.columns.join(', ')}.`);
    if (brief.truncated) lines.push('Salesforce returned the first 2,000 rows.');
    return lines.join('\n');
}

function describeDashboard(brief) {
    const components = brief.components || [];
    const lines = [`${brief.name || 'This dashboard'}${brief.folder ? ` (${brief.folder})` : ''} has ${components.length} component(s).`];
    if (components.length) {
        lines.push(
            numbered(components.slice(0, 8), (component) => {
                const bits = [component.title || 'Untitled'];
                if (component.value) bits.push(component.value);
                if (component.note) bits.push(component.note);
                return bits.join(' \u2014 ');
            })
        );
    }
    const active = (brief.filters || []).filter((filter) => filter.value && filter.value !== 'All');
    if (active.length) lines.push(`Filters: ${active.map((filter) => `${filter.name} = ${filter.value}`).join('; ')}.`);
    return lines.join('\n');
}

function answerReport(brief, q) {
    const namedGroup = findNamed(q, (brief.groups || []).map((group) => ({ name: group.label, ...group })));
    if (namedGroup && has(q, /(group|breakdown|how many|count|what|show)/)) {
        const metrics = (namedGroup.metrics || []).map((item) => `${item.label} ${item.value}`).join(', ');
        return `${namedGroup.label}: ${namedGroup.count} record(s)${metrics ? `. ${metrics}` : ''}.`;
    }
    if (has(q, /(total|grand|how many|count|record|sum|average|kpi|number)/)) {
        return (brief.totals || []).length
            ? (brief.totals || []).map((item) => `${item.label}: ${item.value}`).join('\n')
            : 'This report has no totals yet.';
    }
    if (has(q, /(top|highest|largest|best|group|breakdown|leader)/)) {
        const groups = [...(brief.groups || [])].sort((a, b) => (b.count || 0) - (a.count || 0));
        return groups.length
            ? `Largest groups:\n${numbered(groups.slice(0, 6), (group) => `${group.label} \u2014 ${group.count}`)}`
            : 'This report is not grouped. Ask for the totals or the first rows.';
    }
    if (has(q, /(low|smallest|bottom|worst)/) && (brief.groups || []).length) {
        const groups = [...brief.groups].sort((a, b) => (a.count || 0) - (b.count || 0));
        return `Smallest groups:\n${numbered(groups.slice(0, 5), (group) => `${group.label} \u2014 ${group.count}`)}`;
    }
    if (has(q, /(chart|graph|visual)/)) {
        return brief.chart ? `The chart is a ${brief.chart}.` : 'This report has no chart.';
    }
    if (has(q, /(filter|criteria|where|limited)/)) {
        return (brief.filters || []).length ? `Filters:\n${numbered(brief.filters, (line) => line)}` : 'No filters are applied.';
    }
    if (has(q, /(column|field|what.{0,12}show)/)) {
        return (brief.columns || []).length ? `Columns: ${brief.columns.join(', ')}.` : 'No columns are on this report yet.';
    }
    if (has(q, /(row|detail|sample|first|example)/) && (brief.topRows || []).length) {
        return `First rows:\n${numbered(brief.topRows, (row) => row)}`;
    }
    return describeReport(brief);
}

function answerReportList(list, q) {
    const items = list.items || [];
    const named = findNamed(q, items);
    if (named) {
        return `${named.name} is a ${named.format || 'report'} in ${named.folder}.${named.description ? ` ${named.description}` : ''} Open it to see the chart and totals.`;
    }
    if (has(q, /(recent|last|ran|run)/)) {
        const recent = list.recent || [];
        return recent.length
            ? `Recently run:\n${numbered(recent, (row) => `${row.name} (${formatLine(row)})`)}`
            : 'Nothing in this list has a last-run date yet.';
    }
    if (has(q, /(folder|where)/)) {
        const folders = list.folders || [];
        return folders.length
            ? `Folders:\n${numbered(folders, (folder) => `${folder.name} \u2014 ${folder.count}`)}`
            : 'No report folders are in the list yet.';
    }
    if (has(q, /(how many|count|total)/)) {
        return `${list.total || 0} report(s) are available.`;
    }
    if (has(q, /(summary|matrix|tabular|format)/)) {
        const counts = { Tabular: 0, Summary: 0, Matrix: 0 };
        items.forEach((row) => {
            const key = row.format || 'Tabular';
            counts[key] = (counts[key] || 0) + 1;
        });
        return Object.entries(counts)
            .filter(([, count]) => count)
            .map(([format, count]) => `${format}: ${count}`)
            .join('\n') || 'No reports are loaded yet.';
    }
    if (!items.length) return 'The report list is still loading. Open a report once it appears and I can read its chart and totals.';
    const recent = (list.recent || []).slice(0, 5);
    return recent.length
        ? `${list.total} reports. Recently run:\n${numbered(recent, (row) => row.name)}`
        : `${list.total} reports across ${(list.folders || []).length} folder(s).`;
}

function answerDashboard(brief, q) {
    const components = brief.components || [];
    const named = findNamed(
        q,
        components.map((component) => ({ name: component.title, ...component }))
    );
    if (named) {
        return [named.title, named.value, named.note].filter(Boolean).join(' \u2014 ') || `${named.title} has no numbers yet.`;
    }
    if (has(q, /(filter)/)) {
        const filters = brief.filters || [];
        return filters.length
            ? `Dashboard filters:\n${numbered(filters, (filter) => `${filter.name}: ${filter.value || 'All'}`)}`
            : 'This dashboard has no filters.';
    }
    if (has(q, /(highest|top|largest|best|lowest|smallest)/)) {
        const ranked = components
            .map((component) => ({ ...component, n: asNumber(component.value) }))
            .filter((component) => component.n != null)
            .sort((a, b) => (has(q, /(low|small)/) ? a.n - b.n : b.n - a.n));
        if (ranked.length) {
            return `${has(q, /(low|small)/) ? 'Lowest' : 'Highest'} components:\n${numbered(ranked.slice(0, 5), (component) => `${component.title} \u2014 ${component.value}`)}`;
        }
    }
    if (!components.length) return `${brief.name || 'This dashboard'} has no components yet.`;
    return describeDashboard(brief);
}

function answerDashboardList(list, q) {
    const items = list.items || [];
    const named = findNamed(q, items);
    if (named) {
        return `${named.name} is in ${named.folder}.${named.description ? ` ${named.description}` : ''} Open it and I can read each component.`;
    }
    if (has(q, /(recent|viewed|last)/)) {
        const recent = list.recent || [];
        return recent.length
            ? `Recently viewed:\n${numbered(recent, (row) => `${row.name} (${row.folder})`)}`
            : 'Nothing in this list has been viewed yet.';
    }
    if (has(q, /(folder)/)) {
        return (list.folders || []).length
            ? `Folders:\n${numbered(list.folders, (folder) => `${folder.name} \u2014 ${folder.count}`)}`
            : 'No dashboard folders are in the list yet.';
    }
    if (has(q, /(how many|count|total)/)) return `${list.total || 0} dashboard(s) are available.`;
    if (!items.length) return 'The dashboard list is still loading. Open one and I can summarize its components.';
    const recent = (list.recent || []).slice(0, 5);
    return recent.length
        ? `${list.total} dashboards. Recently viewed:\n${numbered(recent, (row) => row.name)}`
        : `${list.total} dashboards across ${(list.folders || []).length} folder(s).`;
}

export async function loadReportProfile(ctx) {
    const detail = ctx.analytics && ctx.analytics.kind === 'report' ? ctx.analytics : null;
    if (detail) {
        const ready = detail.status === 'ready';
        return {
            subtitle: detail.name || 'Report',
            placeholder: 'Ask about totals, groups, or filters',
            chips: ready ? ['What are the totals?', 'What are the top groups?', 'What filters are on?'] : [],
            stats: (detail.totals || []).slice(0, 3).map((item) => ({ label: item.label, value: item.value })),
            sections: (detail.groups || []).length
                ? [
                      {
                          title: 'Top groups',
                          meta: detail.format,
                          items: detail.groups.slice(0, 6).map((group) => ({
                              title: group.label,
                              lines: [
                                  [`${group.count} records`, ...(group.metrics || []).map((item) => `${item.label} ${item.value}`)]
                                      .filter(Boolean)
                                      .join(' \u00b7 ')
                              ]
                          }))
                      }
                  ]
                : [],
            insights: ready
                ? [
                      `${detail.name}${detail.folder ? ` \u00b7 ${detail.folder}` : ''}.`,
                      (detail.totals || []).slice(0, 3).map((item) => `${item.label} ${item.value}`).join(' \u00b7 ') || 'No totals yet.',
                      detail.chart ? `Chart: ${detail.chart}.` : '',
                      (detail.filters || []).length ? `Filters: ${detail.filters.slice(0, 3).join('; ')}.` : '',
                      detail.truncated ? 'Showing the first 2,000 rows.' : ''
                  ].filter(Boolean)
                : [`Opening ${detail.name || 'this report'}. Totals and groups will show here as soon as it finishes running.`],
            answer: (q) => (ready ? answerReport(detail, q) : `Still running ${detail.name || 'this report'}. Ask again in a moment for the totals.`)
        };
    }
    const list = reportListFrom(ctx);
    const recent = list.recent || [];
    return {
        subtitle: 'Reports',
        placeholder: 'Ask which report to open',
        chips: ['What did I run recently?', 'Which folders are busiest?', 'How many reports?'],
        stats: [
            { label: 'Reports', value: list.total || 0 },
            { label: 'Folders', value: (list.folders || []).length }
        ],
        sections: recent.length
            ? [
                  {
                      title: 'Recently run',
                      items: recent.slice(0, 6).map((row) => ({
                          title: row.name,
                          lines: [formatLine(row)],
                          actions: openAction('Report', row.id)
                      }))
                  }
              ]
            : [],
        insights: list.total
            ? [
                  `${list.total} report(s) across ${(list.folders || []).length} folder(s).`,
                  recent.length ? `Latest: ${recent.slice(0, 3).map((row) => row.name).join(', ')}.` : 'Open a report and I will read its chart, totals, and top groups.'
              ]
            : ['Loading the report list. Open a report and I will read its chart and totals.'],
        answer: (q) => answerReportList(list, q)
    };
}

export async function loadDashboardProfile(ctx) {
    const detail = ctx.analytics && ctx.analytics.kind === 'dashboard' ? ctx.analytics : null;
    if (detail) {
        const components = detail.components || [];
        const ready = detail.status === 'ready' && components.length > 0;
        return {
            subtitle: detail.name || 'Dashboard',
            placeholder: 'Ask about a component or filter',
            chips: ready ? ['Summarize this dashboard', 'Which component is highest?', 'What filters are on?'] : [],
            stats: [
                { label: 'Components', value: components.length },
                { label: 'Filters', value: (detail.filters || []).length }
            ],
            sections: components.length
                ? [
                      {
                          title: 'Components',
                          items: components.slice(0, 8).map((component) => ({
                              title: component.title || 'Untitled',
                              lines: [[component.value, component.note].filter(Boolean).join(' \u00b7 ')].filter(Boolean),
                              actions: openAction('Report', component.reportId)
                          }))
                      }
                  ]
                : [],
            insights: [
                `${detail.name || 'Dashboard'}${detail.folder ? ` \u00b7 ${detail.folder}` : ''}.`,
                ready
                    ? components
                          .slice(0, 4)
                          .map((component) => [component.title, component.value].filter(Boolean).join(' '))
                          .join(' \u00b7 ')
                    : 'Components will appear here as soon as the dashboard finishes loading.'
            ].filter(Boolean),
            answer: (q) => (detail.status === 'loading' && !components.length ? `Still loading ${detail.name || 'this dashboard'}.` : answerDashboard(detail, q))
        };
    }
    const list = dashboardListFrom(ctx);
    const recent = list.recent || [];
    return {
        subtitle: 'Dashboards',
        placeholder: 'Ask which dashboard to open',
        chips: ['What did I view recently?', 'Which folders are busiest?', 'How many dashboards?'],
        stats: [
            { label: 'Dashboards', value: list.total || 0 },
            { label: 'Folders', value: (list.folders || []).length }
        ],
        sections: recent.length
            ? [
                  {
                      title: 'Recently viewed',
                      items: recent.slice(0, 6).map((row) => ({
                          title: row.name,
                          lines: [row.folder],
                          actions: openAction('Dashboard', row.id)
                      }))
                  }
              ]
            : [],
        insights: list.total
            ? [
                  `${list.total} dashboard(s) across ${(list.folders || []).length} folder(s).`,
                  recent.length
                      ? `Latest: ${recent.slice(0, 3).map((row) => row.name).join(', ')}.`
                      : 'Open a dashboard and I will read each component.'
              ]
            : ['Loading dashboards. Open one and I will summarize its components.'],
        answer: (q) => answerDashboardList(list, q)
    };
}

function walkTeam(nodes, territories, people) {
    (nodes || []).forEach((node) => {
        territories.push({ name: node.name || 'Territory', level: node.level || '' });
        (node.users || []).forEach((person) => {
            people.push({
                name: person.name || 'Teammate',
                role: person.role || '',
                territory: node.name || ''
            });
        });
        walkTeam(node.children, territories, people);
    });
}

function approvalBucket(label, rows) {
    const items = listOf(rows);
    const waiting = items.filter((row) => row && row.canAct !== false);
    return {
        label,
        count: waiting.length,
        names: waiting.map(rowLabel).filter(Boolean).slice(0, 5)
    };
}

export async function loadWorkforceProfile() {
    let kpis = null;
    let error = '';
    try {
        kpis = await getTeamKpis({});
    } catch (err) {
        error = err && err.message ? err.message : 'Team KPIs are unavailable.';
    }
    kpis = kpis || {};
    const probation = kpis.probationReps || [];
    const weak = [...(kpis.drillDown || [])]
        .filter((row) => row && row.label && row.coveragePercent != null)
        .sort((a, b) => Number(a.coveragePercent) - Number(b.coveragePercent))
        .slice(0, 5);
    const declining = (kpis.coachingRepTrends || []).filter((row) => row && row.trend === 'declining').slice(0, 5);
    const insights = [];
    if (error && kpis.coveragePercent == null) insights.push(error);
    if (kpis.coveragePercent != null) insights.push(`Coverage ${pct(kpis.coveragePercent)} \u00b7 visit rate ${pct(kpis.actualVisitRate)}.`);
    if (kpis.visitsThisMonth != null) insights.push(`${kpis.visitsThisMonth} visits this month across ${kpis.totalReps || 0} rep(s).`);
    if (kpis.coachingDays != null) {
        insights.push(
            `Coaching ${kpis.coachingDays} day(s) \u00b7 ${kpis.coachedReps || 0} of ${kpis.totalReps || 0} reps coached.`
        );
    }
    if (probation.length) insights.push(`${probation.length} rep(s) still on probation.`);
    insights.push('Report modules here: Working Days Analysis and Medical Rep 360.');
    return {
        subtitle: 'Workforce',
        placeholder: 'Ask about coverage, coaching, or probation',
        chips: ['How is coverage?', 'Who is on probation?', 'Who is coaching down?'],
        stats: [
            { label: 'Coverage', value: pct(kpis.coveragePercent), tone: toneForPercent(kpis.coveragePercent) },
            { label: 'Visit rate', value: pct(kpis.actualVisitRate), tone: toneForPercent(kpis.actualVisitRate) },
            { label: 'Visits', value: kpis.visitsThisMonth || 0 },
            { label: 'Coaching days', value: kpis.coachingDays || 0 }
        ],
        sections: [
            weak.length
                ? {
                      title: 'Lowest coverage',
                      items: weak.map((row) => ({
                          title: row.label,
                          lines: [[`Coverage ${pct(row.coveragePercent)}`, row.actualVisitRate != null ? `visits ${pct(row.actualVisitRate)}` : ''].filter(Boolean).join(' \u00b7 ')]
                      }))
                  }
                : null,
            probation.length
                ? {
                      title: 'On probation',
                      items: probation.slice(0, 6).map((rep) => ({
                          title: rep.name || 'Rep',
                          lines: [[rep.territoryLine, rep.daysRemaining != null ? `${rep.daysRemaining} days left` : ''].filter(Boolean).join(' \u00b7 ')]
                      }))
                  }
                : null
        ].filter(Boolean),
        insights: insights.length ? insights : ['Workforce KPIs are still loading.'],
        answer(q) {
            const module = findNamed(q, HUB_CARDS.map((card) => ({ ...card, name: card.title })));
            if (module) return `${module.title}: ${module.description}`;
            if (has(q, /(probation|new hire|hire)/)) {
                return probation.length
                    ? `On probation:\n${numbered(probation.slice(0, 8), (rep) => `${rep.name}${rep.daysRemaining != null ? ` \u2014 ${rep.daysRemaining} days left` : ''}`)}`
                    : 'No reps are on probation.';
            }
            if (has(q, /(coach)/)) {
                const base = `Coaching days ${kpis.coachingDays || 0}. ${kpis.coachedReps || 0} of ${kpis.totalReps || 0} reps coached. CLM usage ${pct(kpis.clmUsageRate)}.`;
                return declining.length
                    ? `${base}\nDeclining:\n${numbered(declining, (rep) => `${rep.repName} \u2014 ${pct(rep.latestScore)}`)}`
                    : base;
            }
            if (has(q, /(coverage|visit|am |pm |gap|low)/)) {
                const head = `Coverage ${pct(kpis.coveragePercent)}. Visit rate ${pct(kpis.actualVisitRate)} (AM ${pct(kpis.amVisitRate)}, PM ${pct(kpis.pmVisitRate)}). KOL coverage ${pct(kpis.kolCoveragePercent)}.`;
                return weak.length
                    ? `${head}\nLowest coverage:\n${numbered(weak, (row) => `${row.label} \u2014 ${pct(row.coveragePercent)}`)}`
                    : head;
            }
            if (has(q, /(clm|presentation|deck)/)) {
                return `CLM usage ${pct(kpis.clmUsageRate)}. ${kpis.clmSessionsThisMonth || 0} sessions this month, ${kpis.clmPresentationsUsed || 0} of ${kpis.totalClmPresentations || 0} presentations used.`;
            }
            return insights.join('\n');
        }
    };
}

export async function loadMyTeamProfile() {
    const [treeResult, accountResult, expenseResult, planResult, timeResult, meetingResult] = await Promise.allSettled([
        getMyTeamTree({}),
        getPendingAccountApprovals(),
        getPendingExpenseApprovals(),
        getPendingPlanApprovals(),
        getPendingTimeOff({}),
        getPendingMeetings({})
    ]);
    const territories = [];
    const people = [];
    walkTeam(Array.isArray(settled(treeResult)) ? settled(treeResult) : [], territories, people);
    const buckets = [
        approvalBucket('Account class', settled(accountResult)),
        approvalBucket('Expenses', settled(expenseResult)),
        approvalBucket('Visits', settled(planResult)),
        approvalBucket('Time off', settled(timeResult)),
        approvalBucket('Meetings', settled(meetingResult))
    ].filter((bucket) => bucket.count > 0);
    const waiting = buckets.reduce((sum, bucket) => sum + bucket.count, 0);
    const insights = [
        people.length
            ? `${people.length} people across ${territories.length} territories.`
            : 'No subordinate territories are assigned to you.'
    ];
    if (waiting) insights.push(`${waiting} item(s) waiting on you: ${buckets.map((bucket) => `${bucket.count} ${bucket.label.toLowerCase()}`).join(', ')}.`);
    else insights.push('Nothing is waiting for your approval.');
    return {
        subtitle: 'My Team',
        placeholder: 'Ask who is on the team or what needs approval',
        chips: ['Who is on my team?', 'What needs my approval?'],
        stats: [
            { label: 'People', value: people.length },
            { label: 'Territories', value: territories.length },
            { label: 'To approve', value: waiting, tone: waiting ? 'warn' : 'good' }
        ],
        sections: [
            buckets.length
                ? {
                      title: 'Waiting on you',
                      items: buckets.map((bucket) => ({
                          title: `${bucket.count} ${bucket.label}`,
                          lines: [bucket.names.join(', ')]
                      }))
                  }
                : null,
            people.length
                ? {
                      title: 'Team',
                      meta: `${people.length}`,
                      items: people.slice(0, 8).map((person) => ({
                          title: person.name,
                          lines: [[person.role, person.territory].filter(Boolean).join(' \u00b7 ')]
                      }))
                  }
                : null
        ].filter(Boolean),
        insights,
        answer(q) {
            if (has(q, /(approv|pending|waiting|expense|time off|meeting|class)/)) {
                return buckets.length
                    ? `Waiting on you:\n${numbered(buckets, (bucket) => `${bucket.count} ${bucket.label}${bucket.names.length ? ` \u2014 ${bucket.names.join(', ')}` : ''}`)}`
                    : 'Nothing is waiting for your approval.';
            }
            const named = findNamed(q, people);
            if (named) return `${named.name}${named.role ? `, ${named.role}` : ''}${named.territory ? ` \u00b7 ${named.territory}` : ''}.`;
            if (has(q, /(who|team|people|territor|report)/)) {
                return people.length
                    ? `Your team:\n${numbered(people.slice(0, 12), (person) => `${person.name}${person.territory ? ` \u2014 ${person.territory}` : ''}`)}`
                    : 'No subordinate territories are assigned to you.';
            }
            return insights.join('\n');
        }
    };
}

export async function loadKamProfile() {
    let data = null;
    let error = '';
    try {
        data = await getKamDashboard({});
    } catch (err) {
        error = err && err.message ? err.message : 'Key account data is unavailable.';
    }
    const kpis = (data && data.kpis) || {};
    const plans = (data && data.plans) || [];
    const thin = [...plans].filter((plan) => (plan.stakeholderCount || 0) < 3).slice(0, 6);
    const openObjectives = ((data && data.objectives) || []).filter((row) => {
        const status = String(row.status || '').toLowerCase();
        return status && !status.includes('complete') && !status.includes('done');
    });
    const insights = [];
    if (error && !plans.length) insights.push(error);
    insights.push(`${kpis.totalPlans || 0} key accounts, ${kpis.activePlans || 0} in motion.`);
    insights.push(`Objectives ${pct(kpis.objectiveCompletionRate)} complete (${kpis.completedObjectives || 0} of ${kpis.totalObjectives || 0}).`);
    insights.push(`Stakeholder coverage ${pct(kpis.stakeholderCoveragePercent)}.`);
    return {
        subtitle: 'Key accounts',
        placeholder: 'Ask about coverage or objectives',
        chips: ['How are key accounts?', 'Which accounts need stakeholders?', 'How are objectives?'],
        stats: [
            { label: 'Accounts', value: kpis.totalPlans || 0 },
            { label: 'Objectives', value: pct(kpis.objectiveCompletionRate), tone: toneForPercent(kpis.objectiveCompletionRate) },
            { label: 'Stakeholders', value: pct(kpis.stakeholderCoveragePercent), tone: toneForPercent(kpis.stakeholderCoveragePercent) }
        ],
        sections: [
            {
                title: 'Needs stakeholders',
                empty: 'Every visible account has a stakeholder map.',
                items: thin.map((plan) => ({
                    title: plan.accountName || plan.planName || 'Account',
                    lines: [
                        [
                            plan.status,
                            `${plan.stakeholderCount || 0} stakeholders`,
                            plan.objectiveCount ? `${plan.completedObjectiveCount || 0}/${plan.objectiveCount} objectives` : ''
                        ]
                            .filter(Boolean)
                            .join(' \u00b7 ')
                    ]
                }))
            }
        ],
        insights,
        answer(q) {
            const named = findNamed(
                q,
                plans.map((plan) => ({ name: plan.accountName, ...plan }))
            );
            if (named) {
                return `${named.accountName}: ${named.status || 'plan'} \u00b7 ${named.stakeholderCount || 0} stakeholders \u00b7 ${named.completedObjectiveCount || 0}/${named.objectiveCount || 0} objectives.`;
            }
            if (has(q, /(stakeholder|coverage|thin|missing|who)/)) {
                return thin.length
                    ? `Accounts with fewer than 3 stakeholders:\n${numbered(thin, (plan) => `${plan.accountName} \u2014 ${plan.stakeholderCount || 0}`)}`
                    : 'Every visible account has at least 3 stakeholders.';
            }
            if (has(q, /(objective|goal|target)/)) {
                const head = `${kpis.completedObjectives || 0} of ${kpis.totalObjectives || 0} objectives are done (${pct(kpis.objectiveCompletionRate)}).`;
                return openObjectives.length
                    ? `${head}\nStill open:\n${numbered(openObjectives.slice(0, 6), (row) => `${row.objectiveName} \u2014 ${row.accountName || row.status || ''}`)}`
                    : head;
            }
            return insights.join('\n');
        }
    };
}

export async function loadReportsHubProfile() {
    let targets = {};
    try {
        targets = (await loadTileTargets()) || {};
    } catch (_err) {
        targets = {};
    }
    const cards = HUB_CARDS.map((card) => {
        const target = targets[card.id] || {};
        return { ...card, ...target, accessible: target.accessible === true };
    });
    const openCards = cards.filter((card) => card.accessible);
    return {
        subtitle: 'Reports hub',
        placeholder: 'Ask which report to open',
        chips: ['Which reports can I open?', 'What is Medical Rep 360?'],
        stats: [
            { label: 'Available', value: openCards.length },
            { label: 'Modules', value: cards.length }
        ],
        sections: [
            {
                title: 'Modules',
                items: cards.map((card) => ({
                    title: card.title,
                    lines: [card.accessible ? card.description : 'Not available for your profile.'],
                    actions: card.accessible
                        ? card.recordId
                            ? openAction(card.objectApiName || 'Report', card.recordId)
                            : card.apiName
                              ? openAction('Tab', card.apiName)
                              : []
                        : []
                }))
            }
        ],
        insights: [
            openCards.length
                ? `You can open ${openCards.map((card) => card.title).join(', ')}.`
                : 'None of the hub modules are available for this profile yet.'
        ],
        answer(q) {
            const named = findNamed(q, cards);
            if (named) {
                return named.accessible
                    ? `${named.title}: ${named.description}`
                    : `${named.title} is not available for your profile.`;
            }
            if (has(q, /(open|available|which|access)/)) {
                return openCards.length
                    ? `Available:\n${numbered(openCards, (card) => `${card.title} \u2014 ${card.description}`)}`
                    : 'None of the hub modules are available for your profile.';
            }
            return cards.map((card) => `${card.title}: ${card.accessible ? card.description : 'not available'}`).join('\n');
        }
    };
}
