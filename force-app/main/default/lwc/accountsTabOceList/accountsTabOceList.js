import { LightningElement, api, track } from 'lwc';
import { accountThemeFor, accountTypeIconUrl } from 'c/accountTypeTheme';
import getAccountHealthInsight from '@salesforce/apex/AccountsTabController.getAccountHealthInsight';

const HEALTH_CLASS = {
    healthy: 'health-meter health-green',
    warning: 'health-meter health-yellow',
    unhealthy: 'health-meter health-red',
    na: 'health-meter health-na'
};

const HEALTH_STATUS_RANK = {
    healthy: 3,
    warning: 2,
    unhealthy: 1,
    na: 0
};

const TEXT_SORT_FIELDS = new Set(['name', 'classification', 'specialty']);

const SORTABLE_COLUMNS = [
    { id: 'name', label: 'Account', sortField: 'name', colClass: 'col-account' },
    { id: 'class', label: 'Class', sortField: 'classification', colClass: 'col-class' },
    { id: 'plan', label: 'Plan', sortField: 'plan', colClass: 'col-plan' },
    { id: 'visits', label: 'Visits', sortField: 'visits', colClass: 'col-visits' },
    { id: 'gap', label: 'Gap', sortField: 'gap', colClass: 'col-gap' },
    { id: 'health', label: 'Connection Health', sortField: 'health', colClass: 'col-health' },
    { id: 'score', label: 'Score', sortField: 'agentforceScore', colClass: 'col-score' },
    { id: 'specialty', label: 'Specialty', sortField: 'specialty', colClass: 'col-specialty' }
];

function stageBadgeClassFor(lane) {
    const classes = ['oce-stage-badge'];
    if (lane === 'needsYou') {
        classes.push('oce-stage-badge-needs');
    } else if (lane === 'withManager') {
        classes.push('oce-stage-badge-wait');
    } else if (lane === 'withSfe') {
        classes.push('oce-stage-badge-sfe');
    }
    return classes.join(' ');
}

function isBlankDisplay(value) {
    if (value == null) {
        return true;
    }
    const text = String(value).trim();
    return text === '' || text === '—' || text === '-' || text === '–';
}

/** Class badges must be letter+number (A1–C3). Bare A/B/C becomes —. */
function formatLetterNumberClass(raw) {
    if (raw == null || raw === '') {
        return '—';
    }
    const key = String(raw).trim().toUpperCase();
    if (/^[ABC][123]$/.test(key)) {
        return key;
    }
    return '—';
}

function compareText(left, right) {
    return String(left || '').localeCompare(String(right || ''), undefined, {
        numeric: true,
        sensitivity: 'base'
    });
}

function toSortNumber(value, emptyValue) {
    if (value == null || value === '' || Number.isNaN(Number(value))) {
        return emptyValue;
    }
    return Number(value);
}

function healthSortValue(row) {
    if (row?.healthScore != null && row.healthScore !== '' && !Number.isNaN(Number(row.healthScore))) {
        return Number(row.healthScore);
    }
    const status = row?.healthStatus || 'na';
    return Object.prototype.hasOwnProperty.call(HEALTH_STATUS_RANK, status)
        ? HEALTH_STATUS_RANK[status]
        : -1;
}

function daysSinceDate(value) {
    if (!value) {
        return null;
    }
    const parsed = new Date(value);
    if (Number.isNaN(parsed.getTime())) {
        return null;
    }
    const today = new Date();
    today.setHours(0, 0, 0, 0);
    const day = new Date(parsed);
    day.setHours(0, 0, 0, 0);
    return Math.round((today.getTime() - day.getTime()) / 86400000);
}

function recencyLabel(daysSince) {
    if (daysSince == null) {
        return 'No completed visit';
    }
    if (daysSince <= 0) {
        return 'Visited today';
    }
    if (daysSince === 1) {
        return 'Visited yesterday';
    }
    return `${daysSince} days ago`;
}

function historyStatusClass(status) {
    const key = String(status || '').toLowerCase();
    if (key === 'completed') {
        return 'history-status history-status-done';
    }
    if (key === 'scheduled' || key === 'rescheduled' || key === 'draft') {
        return 'history-status history-status-planned';
    }
    if (key === 'submitted') {
        return 'history-status history-status-submitted';
    }
    return 'history-status';
}

function buildInsights(row, daysSince) {
    const insights = [];
    if (daysSince == null) {
        insights.push({
            id: 'recency',
            label: 'Recency',
            text: 'No completed calls on record yet.',
            toneClass: 'insight-card insight-warn'
        });
    } else if (daysSince <= 14) {
        insights.push({
            id: 'recency',
            label: 'Recency',
            text: `Engagement is warm — last seen ${recencyLabel(daysSince).toLowerCase()}.`,
            toneClass: 'insight-card insight-good'
        });
    } else if (daysSince <= 30) {
        insights.push({
            id: 'recency',
            label: 'Recency',
            text: `Last visit was ${daysSince} days ago — a follow-up will protect the cycle.`,
            toneClass: 'insight-card insight-warn'
        });
    } else {
        insights.push({
            id: 'recency',
            label: 'Recency',
            text: `Account is going cold (${daysSince} days since last visit).`,
            toneClass: 'insight-card insight-bad'
        });
    }

    if (row.inPlanCycle && row.targetVisits != null) {
        const actual = row.actualVisits || 0;
        const target = row.targetVisits;
        const gap = row.visitGap != null ? Number(row.visitGap) : Math.max(0, target - actual);
        if (gap <= 0) {
            insights.push({
                id: 'coverage',
                label: 'Coverage',
                text: `Cycle coverage is complete (${actual}/${target}).`,
                toneClass: 'insight-card insight-good'
            });
        } else if (gap <= 2) {
            insights.push({
                id: 'coverage',
                label: 'Coverage',
                text: `${actual} of ${target} cycle visits done — ${gap} still open.`,
                toneClass: 'insight-card insight-warn'
            });
        } else {
            insights.push({
                id: 'coverage',
                label: 'Coverage',
                text: `Behind coverage: ${actual}/${target} with a gap of ${gap}.`,
                toneClass: 'insight-card insight-bad'
            });
        }
    } else {
        insights.push({
            id: 'coverage',
            label: 'Plan',
            text: 'Out of this cycle — use a visit only if the relationship needs a touch.',
            toneClass: 'insight-card insight-neutral'
        });
    }

    if (row.paceStatus === 'ahead' || row.paceStatus === 'on_track') {
        insights.push({
            id: 'pace',
            label: 'Pace',
            text: row.paceStatus === 'ahead' ? 'Visit pace is ahead of the month.' : 'Visit pace is on track.',
            toneClass: 'insight-card insight-good'
        });
    } else if (row.paceStatus === 'behind') {
        insights.push({
            id: 'pace',
            label: 'Pace',
            text: 'Visit pace is behind — add calls to the planner this week.',
            toneClass: 'insight-card insight-warn'
        });
    } else if (row.paceStatus === 'critical') {
        insights.push({
            id: 'pace',
            label: 'Pace',
            text: 'Critical visit gap versus working days left.',
            toneClass: 'insight-card insight-bad'
        });
    }

    if (isBlankDisplay(row.nextVisitDisplay)) {
        insights.push({
            id: 'next',
            label: 'Next visit',
            text: row.inPlanCycle
                ? 'No upcoming visit is locked in for this cycle.'
                : 'No upcoming visit is scheduled.',
            toneClass: 'insight-card insight-warn'
        });
    } else {
        insights.push({
            id: 'next',
            label: 'Next visit',
            text: `Next call is planned for ${row.nextVisitDisplay}.`,
            toneClass: 'insight-card insight-good'
        });
    }
    return insights;
}

function buildNextBestAction(row, daysSince) {
    const isKol = row.isKol === true;
    const classCode = formatLetterNumberClass(row.matrixRating || row.classification);
    const classA = classCode.startsWith('A');
    const rtdEligible = isKol || classA;
    const hasNext = !isBlankDisplay(row.nextVisitDisplay);
    const gap = Number(row.visitGap);
    const hasGap = Number.isFinite(gap) && gap > 0;
    const health = row.healthStatus;
    const rtdSecondary = rtdEligible
        ? {
              key: 'rtd',
              action: 'rtd',
              buttonLabel: 'Schedule RTD meeting',
              title: isKol ? 'KOL round-table' : 'Class A RTD',
              reason: isKol
                  ? 'A round-table lets this KOL influence several HCPs in one sitting.'
                  : 'Class A accounts convert better when pulled into an RTD with peers.'
          }
        : null;

    if (daysSince == null) {
        return {
            key: 'visit',
            action: 'plan',
            buttonLabel: 'Plan first visit',
            title: 'Start the relationship',
            reason: 'There is no completed call on record. A first visit is the next best action.',
            cardClass: 'nba-card nba-urgent',
            secondary: rtdSecondary
        };
    }
    if (health === 'unhealthy' || daysSince > 45 || gap >= 4) {
        return {
            key: 'visit',
            action: 'plan',
            buttonLabel: 'Plan a visit',
            title: 'Urgent follow-up visit',
            reason:
                daysSince > 45
                    ? `Last seen ${daysSince} days ago — a 1:1 visit will recover the account faster than a meeting.`
                    : 'Coverage or health is off track. Book a visit before adding meeting workload.',
            cardClass: 'nba-card nba-urgent',
            secondary: rtdSecondary
        };
    }
    if (health === 'warning' || hasGap || !hasNext) {
        if (rtdEligible && daysSince <= 21 && hasNext) {
            return {
                key: 'rtd',
                action: 'rtd',
                buttonLabel: 'Schedule RTD meeting',
                title: isKol ? 'Next: RTD with this KOL' : 'Next: RTD meeting',
                reason:
                    'The next visit is already planned. An RTD meeting is the higher-leverage move now.',
                cardClass: 'nba-card nba-rtd',
                secondary: {
                    key: 'visit',
                    action: 'plan',
                    buttonLabel: 'Plan another visit',
                    title: 'Extra call',
                    reason: 'Add a 1:1 if you still have cycle gap to close.'
                }
            };
        }
        return {
            key: 'visit',
            action: 'plan',
            buttonLabel: 'Plan a visit',
            title: hasNext ? 'Add a follow-up visit' : 'Lock the next visit',
            reason: hasNext
                ? 'Health or coverage still needs a 1:1 touch this cycle.'
                : 'No upcoming visit is planned — book the next call while the relationship is warm.',
            cardClass: 'nba-card nba-action',
            secondary: rtdSecondary
        };
    }
    if (rtdEligible) {
        return {
            key: 'rtd',
            action: 'rtd',
            buttonLabel: 'Schedule RTD meeting',
            title: isKol ? 'Healthy KOL — multiply reach' : 'Healthy Class A — host an RTD',
            reason: isKol
                ? 'Cadence is healthy. An RTD or speaker meeting uses this KOL as an amplifier.'
                : 'Cadence is healthy. An RTD with peers is the next growth move.',
            cardClass: 'nba-card nba-rtd',
            secondary: {
                key: 'visit',
                action: 'plan',
                buttonLabel: 'Plan extra visit',
                title: 'Optional call',
                reason: 'Keep a courtesy visit if you want extra face time.'
            }
        };
    }
    return {
        key: 'visit',
        action: 'plan',
        buttonLabel: 'Plan extra visit',
        title: 'On cadence',
        reason: hasNext
            ? `Next visit is ${row.nextVisitDisplay}. An extra call is optional.`
            : 'Account is healthy — lock a courtesy visit if you have open slots.',
        cardClass: 'nba-card nba-steady',
        secondary: null
    };
}

function healthBannerClass(status) {
    if (status === 'healthy') {
        return 'health-banner health-banner-good';
    }
    if (status === 'warning') {
        return 'health-banner health-banner-warn';
    }
    if (status === 'unhealthy') {
        return 'health-banner health-banner-bad';
    }
    return 'health-banner';
}

function scoreBarClass(status) {
    if (status === 'healthy') {
        return 'score-bar-fill score-bar-good';
    }
    if (status === 'warning') {
        return 'score-bar-fill score-bar-warn';
    }
    if (status === 'unhealthy') {
        return 'score-bar-fill score-bar-bad';
    }
    return 'score-bar-fill';
}

function buildHealthModalRow(row, insight, loading) {
    const healthStatus = row.healthStatus || 'na';
    const healthLabel =
        healthStatus === 'healthy'
            ? 'Healthy'
            : healthStatus === 'warning'
              ? 'At risk'
              : healthStatus === 'unhealthy'
                ? 'Unhealthy'
                : '—';
    const score = row.healthScore == null || Number.isNaN(Number(row.healthScore))
        ? null
        : Math.round(Number(row.healthScore));
    const scorePercent = score == null ? 0 : Math.max(0, Math.min(100, score));
    const daysSince = daysSinceDate(row.lastVisitDate);
    const metaParts = [
        row.classification ? `Class ${row.classification}` : null,
        row.specialty || null,
        row.isKol === true ? 'KOL' : null,
        row.planCycleLabel || (row.inPlanCycle ? 'In cycle' : 'Out of cycle')
    ].filter(Boolean);
    const history = (insight?.history || []).map((item, index) => ({
        id: item.visitId || `hist-${index}`,
        dateDisplay: item.dateDisplay || '—',
        status: item.status || 'Unknown',
        visitType: item.visitType || 'Visit',
        statusClass: historyStatusClass(item.status)
    }));
    const affiliations = (insight?.affiliations || []).map((item, index) => ({
        id: item.affiliationId || item.relatedAccountId || `aff-${index}`,
        name: item.name,
        relationType: item.relationType || 'Affiliate',
        role: item.role || '',
        accountType: item.accountType || '',
        relatedAccountId: item.relatedAccountId,
        meta: [item.relationType, item.role, item.accountType].filter(Boolean).join(' · ')
    }));
    const nba = buildNextBestAction(row, daysSince);
    return {
        accountId: row.accountId,
        accountName: row.accountName,
        healthStatus,
        healthLabel,
        bannerClass: healthBannerClass(healthStatus),
        scoreDisplay: score == null ? '—' : String(score),
        scorePercent,
        scoreBarStyle: `width: ${scorePercent}%`,
        scoreBarClass: scoreBarClass(healthStatus),
        metaLine: metaParts.join(' · '),
        lastVisitDisplay: row.lastVisitDisplay || '—',
        nextVisitDisplay: row.nextVisitDisplay || '—',
        recencyLabel: recencyLabel(daysSince),
        coverageLabel:
            row.inPlanCycle && row.targetVisits != null
                ? `${row.actualVisits || 0}/${row.targetVisits}`
                : '—',
        paceLabel: row.paceStatusLabel || '—',
        insights: buildInsights(row, daysSince),
        nba,
        secondaryNba: nba.secondary,
        history,
        affiliations,
        historyLoading: loading === true,
        hasHistory: history.length > 0,
        hasAffiliations: affiliations.length > 0
    };
}

function compareRows(a, b, field, direction) {
    const dir = direction === 'asc' ? 1 : -1;
    let cmp = 0;
    switch (field) {
        case 'name':
            cmp = compareText(a.accountName, b.accountName);
            break;
        case 'classification':
            cmp = toSortNumber(a.classificationRank, 0) - toSortNumber(b.classificationRank, 0);
            if (cmp === 0) {
                cmp = compareText(a.classification, b.classification);
            }
            break;
        case 'plan':
            cmp = Number(Boolean(a.inPlanCycle)) - Number(Boolean(b.inPlanCycle));
            break;
        case 'visits':
            cmp = toSortNumber(a.actualVisits, 0) - toSortNumber(b.actualVisits, 0);
            break;
        case 'gap':
            cmp = toSortNumber(a.visitGap, -1) - toSortNumber(b.visitGap, -1);
            break;
        case 'health':
            cmp = healthSortValue(a) - healthSortValue(b);
            break;
        case 'agentforceScore':
            cmp = toSortNumber(a.agentforceScore, 0) - toSortNumber(b.agentforceScore, 0);
            break;
        case 'specialty':
            cmp = compareText(a.specialty, b.specialty);
            break;
        default:
            cmp = 0;
    }
    if (cmp !== 0) {
        return cmp * dir;
    }
    return compareText(a.accountName, b.accountName);
}

export default class AccountsTabOceList extends LightningElement {
    @api rows = [];
    @api isLoading = false;

    _compact = false;

    @api
    get compact() {
        return this._compact;
    }
    set compact(value) {
        this._compact = value === true || value === 'true';
    }

    _sortBy;
    _sortDirection;
    @track localSortBy;
    @track localSortDirection;

    @api
    get sortBy() {
        return this._sortBy;
    }
    set sortBy(value) {
        this._sortBy = value;
        this.localSortBy = value;
    }

    @api
    get sortDirection() {
        return this._sortDirection;
    }
    set sortDirection(value) {
        this._sortDirection = value;
        this.localSortDirection = value;
    }

    @track showDuplicateModal = false;
    duplicateAccountId;
    @track showHealthModal = false;
    @track healthModalRow = null;
    healthInsightToken = 0;
    modalRestoreFocusEl = null;
    didFocusHealthModal = false;

    renderedCallback() {
        // Move focus into the modal when it opens (accessibility + prevents weird "out of focus" feel on mobile).
        if (this.showHealthModal && !this.didFocusHealthModal) {
            this.didFocusHealthModal = true;
            const closeBtn = this.template.querySelector('.health-modal-close');
            if (closeBtn && typeof closeBtn.focus === 'function') {
                closeBtn.focus();
            }
        }

        // Restore focus when the modal closes.
        if (!this.showHealthModal && this.didFocusHealthModal) {
            this.didFocusHealthModal = false;
            if (
                this.modalRestoreFocusEl &&
                typeof this.modalRestoreFocusEl.focus === 'function'
            ) {
                this.modalRestoreFocusEl.focus();
            }
            this.modalRestoreFocusEl = null;
        }
    }

    get hasRows() {
        return (this.rows || []).length > 0;
    }

    get listRootClass() {
        return this.compact ? 'oce-list oce-list-compact' : 'oce-list';
    }

    get showInitialSpinner() {
        return this.isLoading && !this.hasRows;
    }

    get showTable() {
        return this.hasRows || !this.isLoading;
    }

    get isRefreshing() {
        return this.isLoading && this.hasRows;
    }

    get activeSortBy() {
        return this.localSortBy || this._sortBy;
    }

    get activeSortDirection() {
        return this.localSortDirection || this._sortDirection || 'desc';
    }

    get displayRows() {
        const mapped = (this.rows || []).map((row) => {
            const pinKind = row.pinKind || 'hcp';
            const theme = accountThemeFor(row.recordTypeDeveloperName, row.recordTypeName);
            const iconKind = theme.kind === 'account' ? (pinKind === 'hco' ? 'hco' : 'hcp') : theme.kind;
            const pinLabel = theme.kind === 'account'
                ? (row.accountSubtype || (pinKind === 'hco' ? 'HCO' : 'HCP'))
                : theme.label;
            const classification = formatLetterNumberClass(
                row.matrixRating || row.classification
            );
            const specialty = row.specialty || null;
            const city = row.city || null;
            const metaParts = [pinLabel, city].filter(Boolean);
            if (!city && row.addressLine) {
                metaParts.push(row.addressLine);
            }
            if (row.nurtureLane && row.submittedByName) {
                metaParts.push(row.submittedByName);
            }
            const healthStatus = row.healthStatus || 'na';
            const isHcp = pinKind === 'hcp';
            const lastVisitRaw = isBlankDisplay(row.lastVisitDisplay)
                ? null
                : row.lastVisitDisplay;
            const showHealth = isHcp && healthStatus !== 'na';
            const classLetter = classification && classification !== '—'
                ? classification.charAt(0).toUpperCase()
                : '';

            return {
                ...row,
                pinKind,
                typeIconName: iconKind === 'hco' ? 'standard:account' : iconKind === 'pharmacy' ? 'standard:location' : 'standard:contact',
                typeIconUrl: theme.iconUrl || accountTypeIconUrl(iconKind),
                pinLabel,
                typeIconClass: `account-type-icon account-type-icon-${iconKind}`,
                riskDotClass: {
                    High: 'risk-dot-high',
                    Med: 'risk-dot-med',
                    Low: 'risk-dot-low'
                }[row.agentforceRisk] || 'risk-dot-low',
                classificationDisplay: classification,
                classBadgeClass: {
                    A: 'oce-class-badge oce-class-a',
                    B: 'oce-class-badge oce-class-b',
                    C: 'oce-class-badge oce-class-c'
                }[classLetter] || 'oce-class-badge',
                metaLine: metaParts.join(' · '),
                planCycleDisplay: row.planCycleLabel || (row.inPlanCycle ? 'In' : 'Out'),
                planBadgeClass: row.inPlanCycle ? 'oce-plan oce-plan-in' : 'oce-plan oce-plan-out',
                callPlanLabel:
                    row.inPlanCycle && row.targetVisits != null
                        ? `${row.actualVisits || 0}/${row.targetVisits}`
                        : row.callPlanFrequency != null
                          ? `${row.actualVisits || 0}/${row.callPlanFrequency}`
                          : '—',
                // Out of a plan cycle (e.g. a DM viewing the team), fall back to the target-list frequency.
                plannedPlanLabel:
                    row.inPlanCycle && row.targetVisits != null
                        ? `Planned ${row.plannedVisits || 0}/${row.targetVisits}`
                        : row.callPlanFrequency != null
                          ? `Frequency ${row.callPlanFrequency}/month`
                          : 'No target',
                gapDisplay:
                    row.inPlanCycle && row.visitGap != null ? String(row.visitGap) : '—',
                healthClass: HEALTH_CLASS[healthStatus] || HEALTH_CLASS.na,
                healthLabel: isHcp
                    ? healthStatus === 'healthy'
                        ? 'Healthy'
                        : healthStatus === 'warning'
                          ? 'At risk'
                          : healthStatus === 'unhealthy'
                            ? 'Unhealthy'
                            : '—'
                    : '—',
                showHealth,
                showLastVisit: showHealth && Boolean(lastVisitRaw),
                lastVisitCell: lastVisitRaw,
                scoreDisplay:
                    row.agentforceScoreDisplay ||
                    (row.agentforceScore != null
                        ? Number(row.agentforceScore).toFixed(1)
                        : '—'),
                specialtyDisplay: specialty || '—',
                kolSwitchClass: row.isKol === true ? 'kol-switch kol-switch-on' : 'kol-switch',
                kolAriaChecked: row.isKol === true ? 'true' : 'false',
                kolButtonTitle:
                    row.isKol === true
                        ? 'KOL is on for this territory. Click to turn off.'
                        : 'KOL is off for this territory. Click to turn on.',
                kolBusy: row.kolBusy === true,
                showStageBadge:
                    Boolean(row.accountStageLabel) &&
                    row.accountStage !== 'Active' &&
                    row.accountStage != null,
                selectLabel: `Select ${row.accountName || 'account'}`,
                showNurtureWait: Boolean(row.nurtureWaitLabel),
                showDuplicateCheck: Boolean(row.showApprovalActions) || Boolean(row.nurtureWaitLabel),
                showPlanActions: !row.showApprovalActions && !row.nurtureWaitLabel,
                stageBadgeClass: stageBadgeClassFor(row.nurtureLane)
            };
        });
        const sortField = this.activeSortBy;
        const sortDirection = this.activeSortDirection === 'asc' ? 'asc' : 'desc';
        if (!sortField) {
            return mapped;
        }
        return mapped.sort((left, right) => compareRows(left, right, sortField, sortDirection));
    }

    get tableHeaders() {
        const activeField = this.activeSortBy;
        const activeDirection = this.activeSortDirection;
        return SORTABLE_COLUMNS.map((column) => {
            const isActive = Boolean(column.sortField) && activeField === column.sortField;
            const nextDirection = isActive
                ? activeDirection === 'asc'
                    ? 'desc'
                    : 'asc'
                : TEXT_SORT_FIELDS.has(column.sortField)
                  ? 'asc'
                  : 'desc';
            const directionLabel = isActive
                ? activeDirection === 'asc'
                    ? 'ascending'
                    : 'descending'
                : 'unsorted';
            return {
                ...column,
                sortable: Boolean(column.sortField),
                headerClass: `oce-th ${column.colClass}${isActive ? ' oce-th-active' : ''}`,
                buttonClass: `oce-th-button${isActive ? ' oce-th-button-active' : ''}`,
                sortIconClass: `oce-sort${isActive ? ` oce-sort-${activeDirection}` : ''}`,
                ariaSort: isActive
                    ? activeDirection === 'asc'
                        ? 'ascending'
                        : 'descending'
                    : 'none',
                sortTitle: isActive
                    ? `Sorted by ${column.label} (${directionLabel}). Click to sort ${nextDirection === 'asc' ? 'ascending' : 'descending'}.`
                    : `Sort by ${column.label}`
            };
        });
    }

    handleHeaderSort(event) {
        event.preventDefault();
        event.stopPropagation();
        const target = event.currentTarget;
        const columnId = target?.getAttribute('data-id') || target?.dataset?.id;
        const column = SORTABLE_COLUMNS.find((item) => item.id === columnId);
        const sortField =
            column?.sortField ||
            target?.dataset?.sortField ||
            target?.getAttribute('data-sort-field') ||
            target?.getAttribute('data-field') ||
            target?.dataset?.field;
        if (!sortField) {
            return;
        }
        const nextDirection =
            this.activeSortBy === sortField
                ? this.activeSortDirection === 'asc'
                    ? 'desc'
                    : 'asc'
                : TEXT_SORT_FIELDS.has(sortField)
                  ? 'asc'
                  : 'desc';
        this.localSortBy = sortField;
        this.localSortDirection = nextDirection;
        this.dispatchEvent(
            new CustomEvent('columnsort', {
                detail: { sortField, sortDirection: nextDirection },
                bubbles: true,
                composed: true
            })
        );
    }

    handleHealthClick(event) {
        // Save the element currently focused so we can restore focus when the modal closes.
        this.modalRestoreFocusEl = document.activeElement;
        const accountId = event.currentTarget.dataset.id;
        const row = (this.rows || []).find((item) => item.accountId === accountId);
        if (!row || row.pinKind !== 'hcp') {
            return;
        }
        const token = ++this.healthInsightToken;
        this.healthModalRow = buildHealthModalRow(row, null, true);
        this.showHealthModal = true;
        this.loadHealthInsight(row, token);
    }

    async loadHealthInsight(row, token) {
        try {
            const insight = await getAccountHealthInsight({ accountId: row.accountId });
            if (token !== this.healthInsightToken) {
                return;
            }
            this.healthModalRow = buildHealthModalRow(row, insight, false);
        } catch (error) {
            if (token !== this.healthInsightToken) {
                return;
            }
            this.healthModalRow = buildHealthModalRow(row, { history: [], affiliations: [] }, false);
        }
    }

    handleCloseHealthModal(event) {
        event?.stopPropagation?.();
        event?.preventDefault?.();
        this.healthInsightToken += 1;
        this.showHealthModal = false;
        this.healthModalRow = null;
    }

    handleHealthOverlayClick(event) {
        if (event.target === event.currentTarget) {
            this.handleCloseHealthModal();
        }
    }

    stopHealthSheetClick(event) {
        event.stopPropagation();
    }

    handleHealthNbaClick(event) {
        const action = event.currentTarget.dataset.action;
        const accountId = this.healthModalRow?.accountId;
        if (!accountId || !action) {
            return;
        }
        this.handleCloseHealthModal();
        this.dispatchEvent(
            new CustomEvent('rowaction', {
                detail: { accountId, action },
                bubbles: true,
                composed: true
            })
        );
    }

    handleAffiliationClick(event) {
        const accountId = event.currentTarget.dataset.id;
        if (!accountId) {
            return;
        }
        this.handleCloseHealthModal();
        this.dispatchEvent(
            new CustomEvent('rowaction', {
                detail: { accountId, action: 'view' },
                bubbles: true,
                composed: true
            })
        );
    }

    get showApprovalSelect() {
        return (this.rows || []).some((row) => row.showApprovalActions);
    }

    get approvalHeaderChecked() {
        const actionable = (this.rows || []).filter((row) => row.showApprovalActions);
        return actionable.length > 0 && actionable.every((row) => row.approvalSelected);
    }

    handleApprovalToggle(event) {
        event.stopPropagation();
        const accountId = event.target.dataset.id;
        this.dispatchEvent(
            new CustomEvent('approvalselectionchange', {
                detail: { accountId, selected: event.target.checked },
                bubbles: true,
                composed: true
            })
        );
    }

    handleApprovalToggleAll(event) {
        this.dispatchEvent(
            new CustomEvent('approvalselectionchange', {
                detail: { all: true, selected: event.target.checked },
                bubbles: true,
                composed: true
            })
        );
    }

    handleOpenDuplicate(event) {
        event.preventDefault();
        event.stopPropagation();
        const accountId = event.currentTarget.dataset.id;
        if (!accountId) {
            return;
        }
        this.duplicateAccountId = accountId;
        this.showDuplicateModal = true;
    }

    handleCloseDuplicate(event) {
        event?.stopPropagation?.();
        event?.preventDefault?.();
        this.showDuplicateModal = false;
        this.duplicateAccountId = null;
    }

    handleDuplicateOverlayClick(event) {
        if (event.target === event.currentTarget) {
            this.handleCloseDuplicate();
        }
    }

    handleDuplicateChange() {
        this.dispatchEvent(new CustomEvent('duplicatechange', { bubbles: true, composed: true }));
    }

    handleQuickAction(event) {
        event.preventDefault();
        event.stopPropagation();
        const accountId = event.currentTarget.dataset.id;
        const action = event.currentTarget.dataset.action;
        if (!accountId || !action) {
            return;
        }
        this.dispatchEvent(
            new CustomEvent('rowaction', {
                detail: { accountId, action },
                bubbles: true,
                composed: true
            })
        );
    }

    handleApprovalRejectionChange(event) {
        this.dispatchEvent(
            new CustomEvent('approvalrejectionchange', {
                detail: {
                    accountId: event.target.dataset.accountId,
                    value: event.detail.value
                },
                bubbles: true,
                composed: true
            })
        );
    }

    handleAccountClick(event) {
        event.preventDefault();
        const accountId = event.currentTarget.dataset.id;
        this.dispatchEvent(
            new CustomEvent('rowaction', {
                detail: { accountId, action: 'view' },
                bubbles: true,
                composed: true
            })
        );
    }
}