import { LightningElement, track, wire } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import Id from '@salesforce/user/Id';
import { MessageContext } from 'lightning/messageService';
import {
    subscribeTerritoryContext,
    unsubscribeTerritoryContext
} from 'c/territoryContextClient';

import getHomeMetrics from '@salesforce/apex/FieldRepHomeController.getHomeMetrics';
import getAccountCoverageRows from '@salesforce/apex/FieldRepHomeController.getAccountCoverageRows';
import getHomeFilterOptions from '@salesforce/apex/FieldRepHomeController.getHomeFilterOptions';
import getPerformanceGamification from '@salesforce/apex/FieldRepHomeController.getPerformanceGamification';
import getPerformanceRankings from '@salesforce/apex/FieldRepHomeController.getPerformanceRankings';
import upsertVisit from '@salesforce/apex/FieldPlannerController.upsertVisit';
import { getHomeMetricsCache, getUserHomeMetricsKey, newClientKey, putHomeMetrics } from 'c/clmOfflineStore';
import { isOfflineMode, queueOfflineAction } from 'c/clmOfflineSync';

const BADGE_DEFINITIONS = [
    {
        id: 'coverage_champion',
        label: 'Coverage Champion',
        icon: '🏆',
        hint: 'Reach 80% visit coverage this cycle',
        earnDescription: '80% visit coverage this month'
    },
    {
        id: 'on_target',
        label: 'On Target',
        icon: '🎯',
        hint: 'Achieve 100% of your call plan',
        earnDescription: '100% of your call plan'
    },
    {
        id: 'class_a_ace',
        label: 'Class A Ace',
        icon: '⭐',
        hint: 'Reach 90% Class A visit coverage',
        earnDescription: '90% Class A account coverage'
    },
    {
        id: 'streak_starter',
        label: 'Streak Starter',
        icon: '🔥',
        hint: 'Log visits on 3 consecutive working days',
        earnDescription: '3-day activity streak'
    },
    {
        id: 'perfect_week',
        label: 'Perfect Week',
        icon: '📅',
        hint: 'Visit accounts every weekday this week',
        earnDescription: 'visits on all 5 weekdays this week'
    },
    {
        id: 'early_bird',
        label: 'Early Bird',
        icon: '🌅',
        hint: 'Check in before 9 AM on any field day',
        earnDescription: 'check-in before 9 AM'
    }
];

const CLASS_COLORS = {
    A1: { accent: '#014486', bg: 'rgba(1, 118, 211, 0.14)' },
    A2: { accent: '#0176d3', bg: 'rgba(1, 118, 211, 0.09)' },
    A3: { accent: '#4a9eed', bg: 'rgba(1, 118, 211, 0.05)' },
    B1: { accent: '#1b5e20', bg: 'rgba(46, 132, 74, 0.14)' },
    B2: { accent: '#2e844a', bg: 'rgba(46, 132, 74, 0.09)' },
    B3: { accent: '#5cb176', bg: 'rgba(46, 132, 74, 0.05)' },
    C1: { accent: '#8c4b00', bg: 'rgba(254, 147, 57, 0.16)' },
    C2: { accent: '#dd7a01', bg: 'rgba(254, 147, 57, 0.1)' },
    C3: { accent: '#fe9339', bg: 'rgba(254, 147, 57, 0.06)' },
    Other: { accent: '#706e6b', bg: 'rgba(112, 110, 107, 0.08)' }
};

const MATRIX_CLASSES = ['A1', 'A2', 'A3', 'B1', 'B2', 'B3', 'C1', 'C2', 'C3'];
const FILTER_VALUES = ['All', ...MATRIX_CLASSES];
const DRILL_MODES = {
    ALL: 'all',
    ACHIEVEMENT: 'achievement',
    CUSTOMER: 'customer',
    RF: 'rf',
    REMAINING: 'remaining'
};
const DRILL_SORT = {
    [DRILL_MODES.ACHIEVEMENT]: { field: 'reach', direction: 'asc' },
    [DRILL_MODES.REMAINING]: { field: 'gap', direction: 'desc' },
    [DRILL_MODES.CUSTOMER]: { field: 'class', direction: 'asc' },
    [DRILL_MODES.RF]: { field: 'gap', direction: 'desc' }
};
const KPI_HELP = {
    visit: 'Completed vs target visits this month. Click to see who is behind plan — lowest reach first.',
    customer: 'Share of in-plan accounts visited at least once. Click to see who has not been visited yet.',
    rf: 'Share of in-plan accounts at or above target frequency. Click to see LCF accounts that still need calls.',
    remaining: 'Total visits still needed to hit plan. Click to see the biggest remaining gaps — then plan those calls.'
};
const PLANNER_TAB_API = 'Field_Rep_Planner';
const DAY_START_HOUR = 6;
const DAY_END_HOUR = 20;
const SLOT_MINUTES = 30;
const RING_RADIUS = 28;
const RING_CIRCUMFERENCE = 2 * Math.PI * RING_RADIUS;

const TIER_CONFIG = {
    starter: {
        label: 'Starter',
        icon: '🌱',
        accent: '#8b9196',
        gradientStart: '#c4c9ce',
        gradientEnd: '#8b9196',
        bg: 'rgba(139, 145, 150, 0.07)'
    },
    builder: {
        label: 'Builder',
        icon: '🔨',
        accent: '#cd7f32',
        gradientStart: '#e8a857',
        gradientEnd: '#b5651d',
        bg: 'rgba(205, 127, 50, 0.09)'
    },
    achiever: {
        label: 'Achiever',
        icon: '⚡',
        accent: '#0176d3',
        gradientStart: '#4a9eed',
        gradientEnd: '#014486',
        bg: 'rgba(1, 118, 211, 0.08)'
    },
    champion: {
        label: 'Champion',
        icon: '🏆',
        accent: '#f4b400',
        gradientStart: '#ffd54f',
        gradientEnd: '#e6a200',
        bg: 'rgba(244, 180, 0, 0.1)'
    },
    legend: {
        label: 'Legend',
        icon: '⭐',
        accent: '#7c4dff',
        gradientStart: '#b388ff',
        gradientEnd: '#651fff',
        bg: 'rgba(124, 77, 255, 0.1)'
    }
};

const NEXT_TIER = {
    starter: { threshold: 25, label: 'Builder' },
    builder: { threshold: 50, label: 'Achiever' },
    achiever: { threshold: 80, label: 'Champion' },
    champion: { threshold: 100, label: 'Legend' }
};

const TIER_TAGLINES = {
    starter: ['Keep pushing!', 'Every visit counts', 'Build your foundation'],
    builder: ['Almost there!', 'Building momentum', 'Keep climbing'],
    achiever: ['On fire!', 'Strong progress', "You're crushing it"],
    champion: ['Champion level!', 'So close to Legend', 'Elite performance'],
    legend: ['Legend status!', 'Maximum impact!', 'At the top!']
};

const KPI_MILESTONES = [25, 50, 80, 100];
const ACCOUNT_PAGE_SIZE = 8;
const SEARCH_DEBOUNCE_MS = 200;
const CLASS_SORT_ORDER = {
    A1: 0,
    A2: 1,
    A3: 2,
    B1: 3,
    B2: 4,
    B3: 5,
    C1: 6,
    C2: 7,
    C3: 8,
    Other: 9
};
const STATUS_SORT_ORDER = { LCF: 0, RCF: 1, MCF: 2 };
const SORTABLE_ACCOUNT_FIELDS = ['name', 'class', 'reach', 'status', 'gap'];

function normalizeClass(value) {
    if (!value) {
        return 'Other';
    }
    const compact = String(value).trim().toUpperCase().replace(/[^A-C0-9]/g, '');
    if (/^[ABC][123]$/.test(compact)) {
        return compact;
    }
    return 'Other';
}

function ringOffset(percent) {
    const p = Math.min(100, Math.max(0, Math.round(percent || 0)));
    return RING_CIRCUMFERENCE - (p / 100) * RING_CIRCUMFERENCE;
}

function ringStroke(percent) {
    const offset = ringOffset(percent);
    return `stroke-dasharray: ${RING_CIRCUMFERENCE}; stroke-dashoffset: ${offset};`;
}

function ceilToNextSlot(date) {
    const d = new Date(date);
    const minutes = d.getMinutes();
    const add = minutes % SLOT_MINUTES === 0 ? SLOT_MINUTES : SLOT_MINUTES - (minutes % SLOT_MINUTES);
    d.setMinutes(minutes + add);
    d.setSeconds(0, 0);
    return d;
}

function clampToWorkingHours(date) {
    const d = new Date(date);
    if (d.getHours() < DAY_START_HOUR) {
        d.setHours(DAY_START_HOUR, 0, 0, 0);
    }
    if (d.getHours() >= DAY_END_HOUR) {
        d.setDate(d.getDate() + 1);
        d.setHours(DAY_START_HOUR, 0, 0, 0);
    }
    return d;
}

function resolveTierId(percent) {
    const p = Math.round(percent || 0);
    if (p >= 100) {
        return 'legend';
    }
    if (p >= 80) {
        return 'champion';
    }
    if (p >= 50) {
        return 'achiever';
    }
    if (p >= 25) {
        return 'builder';
    }
    return 'starter';
}

function taglineForTier(tierId, percent) {
    const lines = TIER_TAGLINES[tierId] || TIER_TAGLINES.starter;
    return lines[Math.floor((percent || 0) / 10) % lines.length];
}

function isMilestonePercent(percent) {
    const p = Math.round(percent || 0);
    return KPI_MILESTONES.some((milestone) => p === milestone || (milestone === 100 && p > 100));
}

function buildKpiCard(id, label, hint, percent, options = {}) {
    const percentDisplay = Math.round(percent || 0);
    const tierId = resolveTierId(percentDisplay);
    const tier = TIER_CONFIG[tierId];
    const offset = ringOffset(percentDisplay);
    const next = NEXT_TIER[tierId];
    const gap = next ? Math.max(0, next.threshold - percentDisplay) : 0;
    const countLabel = options.countLabel || null;
    const subLabel = options.subLabel || null;
    const helpContent = KPI_HELP[id] || hint;
    const isCounter = options.isCounter === true;

    return {
        id,
        label,
        hint,
        helpContent,
        percentDisplay,
        countLabel,
        subLabel,
        isCounter,
        tierId,
        tierLabel: tier.label,
        tierIcon: tier.icon,
        tierAriaLabel: `Tier: ${tier.label}`,
        tagline: taglineForTier(tierId, percentDisplay),
        ringStyle: isCounter ? '' : `stroke-dasharray: ${RING_CIRCUMFERENCE}; stroke-dashoffset: ${offset};`,
        cardClass: `kpi-card kpi-card-tier-${tierId}${tierId === 'legend' ? ' kpi-card-legend' : ''}${options.isActive ? ' kpi-card-active' : ''}${isCounter ? ' kpi-card-counter' : ''}`,
        cardStyle: `border-left-color: ${tier.accent}; background: linear-gradient(135deg, ${tier.bg} 0%, #fff 100%);`,
        ringFillClass: `kpi-ring-fill kpi-ring-fill-tier-${tierId}${tierId === 'legend' ? ' kpi-ring-legend-pulse' : ''}`,
        tierPillClass: `kpi-tier-pill kpi-tier-pill-${tierId}`,
        showNextTier: !isCounter && Boolean(next && gap > 0),
        nextTierLabel: next ? `${gap}% to ${next.label}` : '',
        showMilestoneSparkle: !isCounter && isMilestonePercent(percentDisplay),
        showRing: !isCounter,
        showCounter: isCounter,
        isActive: Boolean(options.isActive),
        ariaPressed: options.isActive ? 'true' : 'false',
        clickHint: options.isActive ? 'Click to clear' : 'Click for accounts',
        ariaLabel: isCounter
            ? `${label}: ${countLabel}`
            : `${label}: ${countLabel || percentDisplay + ' percent'}, ${tier.label} tier. ${taglineForTier(tierId, percentDisplay)}`
    };
}

const EMPTY_METRICS = {
    visitCoveragePercentDisplay: 0,
    customerCoveragePercentDisplay: 0,
    rfPercentTotalDisplay: 0,
    actualVisitsTotalDisplay: 0,
    targetVisitsTotalDisplay: 0,
    remainingCallsDisplay: 0,
    plannedVisitsTotalDisplay: 0,
    visitCountLabel: '0/0',
    visitPlannedLabel: '0 planned',
    customerCountLabel: '0/0',
    rfCountLabel: '0/0',
    visitRingStroke: ringStroke(0),
    customerRingStroke: ringStroke(0),
    rfRingStroke: ringStroke(0),
    byClassification: []
};

const EMPTY_GAMIFICATION = {
    userFirstName: '',
    streaks: { activityStreak: 0, coverageStreak: 0 },
    badges: []
};

const EMPTY_RANKINGS = {
    buName: '',
    buRank: null,
    buTotal: 0,
    companyRank: null,
    companyTotal: 0,
    myCoveragePercent: 0,
    top5InBu: [],
    top5Company: [],
    personAbove: null,
    isFirstInBu: false
};

function currentMonthStartIso() {
    const now = new Date();
    const year = now.getFullYear();
    const month = String(now.getMonth() + 1).padStart(2, '0');
    return `${year}-${month}-01`;
}

function tokenizeSearch(raw) {
    return (raw || '')
        .trim()
        .toLowerCase()
        .split(/\s+/)
        .filter(Boolean);
}

function classSortValue(row) {
    const clazz = normalizeClass(row.calculatedClassification || row.filterClass);
    return CLASS_SORT_ORDER[clazz] ?? 99;
}

function statusSortValue(row) {
    const status = row.frequencyStatus || '';
    return STATUS_SORT_ORDER[status] ?? 99;
}

function compareAccountRows(a, b, field, direction) {
    const dir = direction === 'desc' ? -1 : 1;
    let cmp = 0;

    switch (field) {
        case 'name':
            cmp = (a.accountNameLower || '').localeCompare(b.accountNameLower || '', undefined, {
                sensitivity: 'base'
            });
            break;
        case 'class':
            cmp = classSortValue(a) - classSortValue(b);
            break;
        case 'reach':
            cmp = (a.reachPercent ?? -1) - (b.reachPercent ?? -1);
            break;
        case 'status':
            cmp = statusSortValue(a) - statusSortValue(b);
            break;
        case 'gap':
            cmp = (a.visitGap ?? 0) - (b.visitGap ?? 0);
            break;
        default:
            cmp = 0;
    }

    if (cmp !== 0) {
        return cmp * dir;
    }

    return (a.accountNameLower || '').localeCompare(b.accountNameLower || '', undefined, {
        sensitivity: 'base'
    });
}

function sortAccountRows(rows, field, direction) {
    const sortField = SORTABLE_ACCOUNT_FIELDS.includes(field) ? field : 'name';
    const sortDirection = direction === 'desc' ? 'desc' : 'asc';
    return [...(rows || [])].sort((a, b) => compareAccountRows(a, b, sortField, sortDirection));
}

function matchesAccountSearch(row, rawTerm) {
    const tokens = tokenizeSearch(rawTerm);
    if (!tokens.length) {
        return true;
    }
    return tokens.every((token) => {
        if (row.searchText.includes(token)) {
            return true;
        }
        if (row.accountNameLower?.startsWith(token)) {
            return true;
        }
        if (token === 'lcf' && row.frequencyStatus === 'LCF') {
            return true;
        }
        if (token === 'rcf' && row.frequencyStatus === 'RCF') {
            return true;
        }
        if (token === 'mcf' && row.frequencyStatus === 'MCF') {
            return true;
        }
        if (token === 'visited' && row.isVisited) {
            return true;
        }
        if (token === 'unvisited' && !row.isVisited) {
            return true;
        }
        return false;
    });
}

export default class FieldRepHomeMetrics extends NavigationMixin(LightningElement) {
    @track isLoading = true;
    @track metrics = { ...EMPTY_METRICS };
    @track gamification = { ...EMPTY_GAMIFICATION };
    @track rankings = { ...EMPTY_RANKINGS };
    @track leaderboardScope = 'bu';
    @track displayAccountRows = [];
    @track selectedFilter = 'All';
    @track selectedRecordType = 'All';
    @track selectedSubtype = 'All';
    @track selectedHcpClassification = 'All';
    @track selectedBrick = 'All';
    @track drillMode = DRILL_MODES.ALL;
    @track filterOptions = {
        recordTypes: [],
        subtypes: [],
        classifications: [],
        bricks: []
    };
    @track searchTerm = '';
    @track currentPage = 1;
    @track sortField = 'name';
    @track sortDirection = 'asc';
    @track isSearching = false;
    @track showMoreFilters = false;
    @track planningAccountId = null;

    allAccountRows = [];
    classFilteredRows = [];
    filteredAccountRows = [];
    @track searchDraft = '';
    @track showBadgeModal = false;
    @track badgeModalTitle = '';
    @track badgeModalMessage = '';
    searchDebounceTimer;
    _messageContext;
    territoryContextSubscription;

    @wire(MessageContext)
    wiredMessageContext(value) {
        this._messageContext = value;
        this.subscribeTerritoryContext();
    }

    get byClassification() {
        return (this.metrics?.byClassification || []).map((row) => {
            const visitPct = Math.round(row.visitCoveragePercentDisplay ?? row.visitCoveragePercent ?? 0);
            const colors = CLASS_COLORS[row.classification] || CLASS_COLORS.Other;
            const isClassActive = this.selectedFilter === row.classification;
            const accountCount = row.accountCount || 0;
            return {
                ...row,
                visitCoveragePercentDisplay: visitPct,
                customerCoveragePercentDisplay: Math.round(
                    row.customerCoveragePercentDisplay ?? row.customerCoveragePercent ?? 0
                ),
                rfPercentDisplay: Math.round(row.rfPercentDisplay ?? row.rfPercent ?? 0),
                lfPercentDisplay: Math.round(row.lfPercentDisplay ?? row.lfPercent ?? 0),
                progressStyle: row.progressStyle || `width: ${visitPct}%`,
                tileStyle: `border-left: 4px solid ${colors.accent}; background: ${colors.bg}`,
                tileClass: `class-card${isClassActive ? ' class-card-active' : ''}${accountCount === 0 ? ' class-card-empty' : ''}`,
                classificationKey: row.classification,
                accountCountLabel: accountCount === 1 ? '1 account' : `${accountCount} accounts`
            };
        });
    }

    get filterChips() {
        return FILTER_VALUES.map((value) => ({
            value,
            label: value === 'All' ? 'All' : value,
            isActive: this.selectedFilter === value,
            chipClass: `filter-chip${this.selectedFilter === value ? ' filter-chip-active' : ''}`
        }));
    }

    get hasAccountRows() {
        return (this.displayAccountRows || []).length > 0;
    }

    get accountCountLabel() {
        const total = this.filteredAccountRows?.length || 0;
        if (total === 0) {
            return this.searchTerm ? 'No matches' : '0 accounts';
        }
        if (total === 1) {
            return '1 account';
        }
        if (this.searchTerm) {
            return `${total} matches`;
        }
        return `${total} accounts`;
    }

    get isDrillActive() {
        return this.drillMode !== DRILL_MODES.ALL || this.selectedFilter !== 'All';
    }

    get accountsSectionClass() {
        return this.isDrillActive ? 'accounts-section accounts-section-open' : 'accounts-section';
    }

    get accountTableHeaders() {
        const columns = [
            { id: 'name', label: 'Account', sortable: true, sortField: 'name' },
            { id: 'class', label: 'Class', sortable: true, sortField: 'class' },
            { id: 'call-plan', label: 'Call plan', sortable: false },
            { id: 'gap', label: 'Remaining', sortable: true, sortField: 'gap' },
            { id: 'why', label: 'Why', sortable: false },
            { id: 'action', label: 'Action', sortable: false }
        ];

        return columns.map((column) => {
            if (!column.sortable) {
                return {
                    ...column,
                    headerClass: 'account-head-cell'
                };
            }

            const isActive = this.sortField === column.sortField;
            const indicator = isActive
                ? this.sortDirection === 'asc'
                    ? '↑'
                    : '↓'
                : '↕';

            return {
                ...column,
                headerClass: `account-head-cell sortable-header${isActive ? ' sortable-header-active' : ''}`,
                sortIndicator: indicator,
                ariaSort: isActive ? (this.sortDirection === 'asc' ? 'ascending' : 'descending') : 'none'
            };
        });
    }

    get rangeLabel() {
        const total = this.filteredAccountRows?.length || 0;
        if (total === 0) {
            return '';
        }
        const start = (this.currentPage - 1) * ACCOUNT_PAGE_SIZE + 1;
        const end = Math.min(this.currentPage * ACCOUNT_PAGE_SIZE, total);
        return `Showing ${start}–${end} of ${total}`;
    }

    get showPagination() {
        return (this.filteredAccountRows?.length || 0) > ACCOUNT_PAGE_SIZE;
    }

    get hasPreviousPage() {
        return this.currentPage > 1;
    }

    get hasNextPage() {
        return this.currentPage < this.totalPages;
    }

    get totalPages() {
        const total = this.filteredAccountRows?.length || 0;
        return Math.max(1, Math.ceil(total / ACCOUNT_PAGE_SIZE));
    }

    get pageLabel() {
        return `Page ${this.currentPage} of ${this.totalPages}`;
    }

    get isPrevDisabled() {
        return !this.hasPreviousPage;
    }

    get isNextDisabled() {
        return !this.hasNextPage;
    }

    get hasSearchTerm() {
        return Boolean((this.searchDraft || this.searchTerm || '').trim());
    }

    get showStreakBanner() {
        return (this.gamification?.streaks?.activityStreak || 0) > 0
            || (this.gamification?.streaks?.coverageStreak || 0) > 0;
    }

    get activityStreakLabel() {
        const days = this.gamification?.streaks?.activityStreak || 0;
        if (days <= 0) {
            return '';
        }
        return `🔥 ${days}-day activity streak`;
    }

    get coverageStreakLabel() {
        const days = this.gamification?.streaks?.coverageStreak || 0;
        if (days <= 0) {
            return '';
        }
        return `📈 ${days}-day coverage streak`;
    }

    get showActivityStreak() {
        return (this.gamification?.streaks?.activityStreak || 0) > 0;
    }

    get showCoverageStreak() {
        return (this.gamification?.streaks?.coverageStreak || 0) > 0;
    }

    get achievementBadges() {
        const earnedById = new Map(
            (this.gamification?.badges || []).map((badge) => [badge.badgeId, badge])
        );
        return BADGE_DEFINITIONS.map((definition) => {
            const serverBadge = earnedById.get(definition.id) || {};
            const earned = Boolean(serverBadge.earned);
            const progress = Math.round(serverBadge.progressPercent || 0);
            return {
                ...definition,
                earned,
                progress,
                progressLabel: earned ? 'Earned' : `${progress}%`,
                chipClass: `achievement-badge${earned ? ' achievement-badge-earned' : ' achievement-badge-locked'}`,
                tooltip: earned ? `${definition.label} — earned!` : `${definition.hint} (${progress}% there)`
            };
        });
    }

    get earnedBadgeCount() {
        return (this.achievementBadges || []).filter((badge) => badge.earned).length;
    }

    get achievementSummary() {
        const earned = this.earnedBadgeCount;
        const total = BADGE_DEFINITIONS.length;
        return `${earned} of ${total} earned`;
    }

    get userFirstName() {
        const name = (this.gamification?.userFirstName || '').trim();
        return name || 'there';
    }

    get metricsReady() {
        return this.metrics?.visitCoveragePercentDisplay != null;
    }

    get kpiCards() {
        const visitPct = this.metrics?.visitCoveragePercentDisplay || 0;
        const customerPct = this.metrics?.customerCoveragePercentDisplay || 0;
        const rfPct = this.metrics?.rfPercentTotalDisplay || 0;
        const activeDrill = this.drillMode;
        return [
            buildKpiCard(
                'visit',
                'Visits Achievement',
                'Actual vs target visits',
                visitPct,
                {
                    countLabel: this.metrics?.visitCountLabel,
                    subLabel: this.metrics?.visitPlannedLabel,
                    isActive: activeDrill === DRILL_MODES.ACHIEVEMENT
                }
            ),
            buildKpiCard(
                'customer',
                'Customer Coverage',
                'Accounts visited this cycle',
                customerPct,
                {
                    countLabel: this.metrics?.customerCountLabel,
                    isActive: activeDrill === DRILL_MODES.CUSTOMER
                }
            ),
            buildKpiCard(
                'rf',
                'Right Frequency',
                'Customers at or above target frequency',
                rfPct,
                {
                    countLabel: this.metrics?.rfCountLabel,
                    isActive: activeDrill === DRILL_MODES.RF
                }
            ),
            buildKpiCard(
                'remaining',
                'Remaining Calls',
                'Calls still needed to hit plan',
                0,
                {
                    countLabel: String(this.metrics?.remainingCallsDisplay || 0),
                    isCounter: true,
                    isActive: activeDrill === DRILL_MODES.REMAINING
                }
            )
        ];
    }

    get recordTypeOptions() {
        return this.filterOptions?.recordTypes || [];
    }

    get subtypeOptions() {
        return this.filterOptions?.subtypes || [];
    }

    get classificationOptions() {
        return this.filterOptions?.classifications || [];
    }

    get brickOptions() {
        return this.filterOptions?.bricks || [];
    }

    get drillPanelTitle() {
        switch (this.drillMode) {
            case DRILL_MODES.ACHIEVEMENT:
                return 'Behind on visits';
            case DRILL_MODES.CUSTOMER:
                return 'Not visited this cycle';
            case DRILL_MODES.RF:
                return 'Below target frequency';
            case DRILL_MODES.REMAINING:
                return 'Remaining call gap';
            default:
                return this.selectedFilter !== 'All' ? `Class ${this.selectedFilter} accounts` : 'Priority accounts';
        }
    }

    get drillModeLabel() {
        switch (this.drillMode) {
            case DRILL_MODES.ACHIEVEMENT:
                return 'Lowest reach first';
            case DRILL_MODES.CUSTOMER:
                return 'Unvisited in-plan';
            case DRILL_MODES.RF:
                return 'LCF accounts';
            case DRILL_MODES.REMAINING:
                return 'Biggest gaps first';
            default:
                return this.selectedFilter !== 'All' ? `Class ${this.selectedFilter}` : '';
        }
    }

    get showDrillModeLabel() {
        return this.isDrillActive;
    }

    get drillInsight() {
        const rows = this.filteredAccountRows || [];
        const count = rows.length;
        if (count === 0) {
            return this.emptyStateMessage;
        }
        const remaining = rows.reduce((sum, row) => sum + Math.max(0, Math.round(row.visitGap || 0)), 0);
        const accountWord = count === 1 ? 'account' : 'accounts';
        const callWord = remaining === 1 ? 'call' : 'calls';
        switch (this.drillMode) {
            case DRILL_MODES.ACHIEVEMENT:
                return `${count} ${accountWord} behind plan · ${remaining} ${callWord} to catch up`;
            case DRILL_MODES.CUSTOMER:
                return `${count} unvisited ${accountWord} — plan a first call this cycle`;
            case DRILL_MODES.RF:
                return `${count} ${accountWord} below frequency · ${remaining} ${callWord} still needed`;
            case DRILL_MODES.REMAINING:
                return `${remaining} remaining ${callWord} across ${count} ${accountWord}`;
            default:
                return remaining > 0
                    ? `${count} ${accountWord} · ${remaining} remaining ${callWord}`
                    : `${count} ${accountWord}`;
        }
    }

    get emptyStateMessage() {
        if (this.hasSearchTerm) {
            return 'No accounts match your search.';
        }
        const hasTargets = (this.allAccountRows || []).some((row) => (row.targetVisits || 0) > 0);
        const hasRows = (this.allAccountRows || []).length > 0;
        if (!hasRows) {
            return 'No in-plan accounts on this month’s time card yet.';
        }
        if (
            !hasTargets &&
            (this.drillMode === DRILL_MODES.ACHIEVEMENT || this.drillMode === DRILL_MODES.REMAINING)
        ) {
            return 'No call-plan targets this month yet. Once targets are loaded, this list shows who is behind so you can plan the gap.';
        }
        switch (this.drillMode) {
            case DRILL_MODES.ACHIEVEMENT:
            case DRILL_MODES.REMAINING:
                return 'You are on target — no remaining visits on the filtered accounts.';
            case DRILL_MODES.CUSTOMER:
                return 'Every in-plan account has been visited this cycle.';
            case DRILL_MODES.RF:
                return 'No accounts are below target frequency (LCF).';
            default:
                return 'No accounts match this filter.';
        }
    }

    get moreFiltersLabel() {
        return this.showMoreFilters ? 'Hide filters' : 'More filters';
    }

    get showRankings() {
        return (this.rankings?.buTotal || 0) > 0 || (this.rankings?.companyTotal || 0) > 0;
    }

    get buRankLabel() {
        const rank = this.rankings?.buRank;
        const total = this.rankings?.buTotal || 0;
        const bu = (this.rankings?.buName || 'your team').trim();
        if (!rank || total <= 0) {
            return '—';
        }
        return `#${rank} of ${total} in ${bu}`;
    }

    get companyRankLabel() {
        const rank = this.rankings?.companyRank;
        const total = this.rankings?.companyTotal || 0;
        if (!rank || total <= 0) {
            return '—';
        }
        return `#${rank} of ${total} reps`;
    }

    get myCoverageDisplay() {
        return Math.round(this.rankings?.myCoveragePercent || 0);
    }

    get showCatchUpCard() {
        return Boolean(this.rankings?.personAbove) && !this.rankings?.isFirstInBu;
    }

    get showFirstPlaceCard() {
        return Boolean(this.rankings?.isFirstInBu);
    }

    get catchUpMessage() {
        const above = this.rankings?.personAbove;
        if (!above) {
            return '';
        }
        const aboveCoverage = Math.round(above.coveragePercent || 0);
        const myCoverage = this.myCoverageDisplay;
        const gap = Math.max(0.1, Math.round((above.gapPercent || 0) * 10) / 10);
        return `${above.name} is #${above.rank} — ${aboveCoverage}% coverage. You're #${this.rankings.buRank} at ${myCoverage}%. ${gap}% to catch up!`;
    }

    get firstPlaceMessage() {
        const bu = (this.rankings?.buName || 'your team').trim();
        return `You're #1 in ${bu}! 🏆 Keep it up.`;
    }

    get leaderboardRows() {
        const source = this.leaderboardScope === 'company'
            ? (this.rankings?.top5Company || [])
            : (this.rankings?.top5InBu || []);
        return source.map((row) => ({
            ...row,
            coverageDisplay: `${Math.round(row.coveragePercent || 0)}%`,
            rowClass: `leaderboard-row${row.isCurrentUser ? ' leaderboard-row-you' : ''}`,
            showBadge: Boolean(row.badgeIcon),
            rankLabel: `#${row.rank}`
        }));
    }

    get leaderboardScopeLabel() {
        return this.leaderboardScope === 'company' ? 'Company-wide' : (this.rankings?.buName || 'Your BU');
    }

    get isBuScopeActive() {
        return this.leaderboardScope === 'bu';
    }

    get isCompanyScopeActive() {
        return this.leaderboardScope === 'company';
    }

    get buScopeChipClass() {
        return `scope-chip${this.isBuScopeActive ? ' scope-chip-active' : ''}`;
    }

    get companyScopeChipClass() {
        return `scope-chip${this.isCompanyScopeActive ? ' scope-chip-active' : ''}`;
    }

    connectedCallback() {
        this.subscribeTerritoryContext();
        this.init();
    }

    disconnectedCallback() {
        if (this.searchDebounceTimer) {
            clearTimeout(this.searchDebounceTimer);
        }
        unsubscribeTerritoryContext(this.territoryContextSubscription);
        this.territoryContextSubscription = undefined;
    }

    subscribeTerritoryContext() {
        if (this.territoryContextSubscription || !this._messageContext) {
            return;
        }
        this.territoryContextSubscription = subscribeTerritoryContext(this._messageContext, () => {
            void this.init();
        });
    }

    async init() {
        this.isLoading = true;
        try {
            if (isOfflineMode()) {
                const cached = await getHomeMetricsCache(getUserHomeMetricsKey(Id));
                if (cached) {
                    this.applyCachedBundle(cached);
                } else {
                    throw new Error('Home metrics are not cached for offline use.');
                }
            } else {
            const [metrics, rows, gamification, rankings, filterOpts] = await Promise.all([
                getHomeMetrics({ contextUserId: null }),
                getAccountCoverageRows({
                    contextUserId: null,
                    classificationFilter: 'All',
                    recordTypeFilter: 'All',
                    subtypeFilter: 'All',
                    hcpClassificationFilter: 'All',
                    brickFilter: null
                }),
                getPerformanceGamification({ contextUserId: null, monthStart: currentMonthStartIso() }),
                getPerformanceRankings({ contextUserId: null }),
                getHomeFilterOptions({ contextUserId: null })
            ]);

            this.filterOptions = filterOpts || this.filterOptions;

            const safeMetrics = metrics || { ...EMPTY_METRICS, byClassification: [] };
            const safeRows = rows || [];
            const actualTotal = Math.round(safeMetrics.actualVisitsTotal || 0);
            const targetTotal = Math.round(safeMetrics.targetVisitsTotal || 0);
            // RF count from rows for accurate display
            const rfCount = safeRows.filter(
                (r) => r.frequencyStatus === 'RCF' || r.frequencyStatus === 'MCF'
            ).length;
            const totalAccounts = safeRows.length;
            const visitedCount = safeRows.filter((r) => r.isVisited).length;

            safeMetrics.byClassification = (safeMetrics.byClassification || []).map((row) => {
                const visitPct = Math.round(row.visitCoveragePercent || 0);
                return {
                    ...row,
                    visitCoveragePercentDisplay: visitPct,
                    customerCoveragePercentDisplay: Math.round(row.customerCoveragePercent || 0),
                    rfPercentDisplay: Math.round(row.rfPercent || 0),
                    lfPercentDisplay: Math.round(row.lfPercent || 0),
                    progressStyle: `width: ${visitPct}%`
                };
            });

            const plannedTotal = Math.round(safeMetrics.plannedVisitsTotal || 0);

            this.metrics = {
                ...safeMetrics,
                visitCoveragePercentDisplay: Math.round(safeMetrics.visitCoveragePercent || 0),
                customerCoveragePercentDisplay: Math.round(safeMetrics.customerCoveragePercent || 0),
                rfPercentTotalDisplay: Math.round(safeMetrics.rfPercentTotal || 0),
                actualVisitsTotalDisplay: actualTotal,
                targetVisitsTotalDisplay: targetTotal,
                plannedVisitsTotalDisplay: plannedTotal,
                remainingCallsDisplay: Math.round(safeMetrics.remainingCalls || 0),
                visitCountLabel: `${actualTotal}/${targetTotal}`,
                visitPlannedLabel: `${plannedTotal} planned`,
                customerCountLabel: `${visitedCount}/${totalAccounts}`,
                rfCountLabel: `${rfCount}/${totalAccounts}`,
                visitRingStroke: ringStroke(safeMetrics.visitCoveragePercent),
                customerRingStroke: ringStroke(safeMetrics.customerCoveragePercent),
                rfRingStroke: ringStroke(safeMetrics.rfPercentTotal)
            };
            this.gamification = gamification || { ...EMPTY_GAMIFICATION };
            this.rankings = rankings || { ...EMPTY_RANKINGS };

            this.allAccountRows = safeRows.map((row) => this.enrichAccountRow(row));
            this.applyClassFilter();

            await putHomeMetrics(getUserHomeMetricsKey(Id), {
                metrics: this.metrics,
                gamification: this.gamification,
                rankings: this.rankings,
                allAccountRows: this.allAccountRows
            });
            }
        } catch (e) {
            const cached = await getHomeMetricsCache(getUserHomeMetricsKey(Id));
            if (cached) {
                this.applyCachedBundle(cached);
            } else {
            this.metrics = { ...EMPTY_METRICS };
            this.gamification = { ...EMPTY_GAMIFICATION };
            this.rankings = { ...EMPTY_RANKINGS };
            this.allAccountRows = [];
            this.classFilteredRows = [];
            this.filteredAccountRows = [];
            this.displayAccountRows = [];
            this.searchDraft = '';
            this.showErrorToast(e, 'Unable to load rep metrics.');
            }
        } finally {
            this.isLoading = false;
        }
    }

    applyCachedBundle(cached) {
        this.metrics = cached.metrics || { ...EMPTY_METRICS };
        this.gamification = cached.gamification || { ...EMPTY_GAMIFICATION };
        this.rankings = cached.rankings || { ...EMPTY_RANKINGS };
        this.allAccountRows = cached.allAccountRows || [];
        this.applyClassFilter();
    }

    enrichAccountRow(row) {
        const filterClass = normalizeClass(
            row.hcpClassification || row.matrixRating || row.calculatedClassification
        );
        const actual = Math.round(row.actualVisits || 0);
        const target = Math.round(row.targetVisits || 0);
        const visitPct = target > 0 ? Math.min(100, Math.round((actual / target) * 100)) : 0;
        const status = row.frequencyStatus || '';

        let statusClass = 'status-neutral';
        if (status === 'LCF') {
            statusClass = 'status-lcf';
        } else if (status === 'RCF') {
            statusClass = 'status-rcf';
        } else if (status === 'MCF') {
            statusClass = 'status-mcf';
        }

        const accountNameLower = (row.accountName || '').toLowerCase();

        return {
            ...row,
            filterClass,
            accountNameLower,
            callPlanLabel: `${actual} / ${target}`,
            reachDisplay: row.reachPercent != null ? `${Math.round(row.reachPercent)}%` : '—',
            visitedLabel: row.isVisited ? 'Visited' : 'Not visited',
            visitedClass: row.isVisited ? 'visited-yes' : 'visited-no',
            statusClass,
            progressStyle: `width: ${visitPct}%`,
            gapDisplay: Math.round(row.visitGap || 0),
            cityLine: [row.brickName, row.city].filter(Boolean).join(' · '),
            searchText: [
                row.accountName,
                row.specialty,
                row.city,
                row.frequencyStatus,
                row.calculatedClassification,
                row.hcpClassification,
                row.recordTypeLabel,
                row.accountSubtype,
                row.brickName,
                row.potential,
                row.penetration,
                row.isVisited ? 'visited' : 'not visited'
            ]
                .filter(Boolean)
                .join(' ')
                .toLowerCase()
        };
    }

    whyForRow(row) {
        const gap = Math.round(row.visitGap || 0);
        const plan = row.callPlanLabel || '0 / 0';
        switch (this.drillMode) {
            case DRILL_MODES.REMAINING:
                return gap > 0 ? `${gap} ${gap === 1 ? 'call' : 'calls'} still needed` : 'On target';
            case DRILL_MODES.ACHIEVEMENT:
                return gap > 0 ? `${plan} — behind plan` : 'On target';
            case DRILL_MODES.CUSTOMER:
                return row.isVisited ? 'Visited this cycle' : 'Not visited this cycle';
            case DRILL_MODES.RF:
                if (row.frequencyStatus === 'LCF') {
                    return `Below frequency (${plan})`;
                }
                return row.frequencyStatus ? `${row.frequencyStatus} · ${plan}` : plan;
            default:
                if (gap > 0) {
                    return `${gap} remaining`;
                }
                return row.isVisited ? 'Visited' : 'Not visited';
        }
    }

    decorateDisplayRow(row) {
        const gap = Math.round(row.visitGap || 0);
        const isPlanning = this.planningAccountId === row.accountId;
        return {
            ...row,
            whyLabel: this.whyForRow(row),
            remainingLabel: String(Math.max(0, gap)),
            remainingClass: gap > 0 ? 'remaining-yes' : 'remaining-zero',
            planLabel: isPlanning ? 'Planning…' : 'Plan visit',
            planDisabled: isPlanning
        };
    }

    applyClassFilter() {
        const filter = this.selectedFilter || 'All';
        let rows =
            filter === 'All'
                ? this.allAccountRows
                : this.allAccountRows.filter((row) => row.filterClass === filter);

        rows = this.applyRecordFilters(rows);
        rows = this.applyDrillFilter(rows);
        this.classFilteredRows = rows;
        this.currentPage = 1;
        this.applySearch();
    }

    applyRecordFilters(rows) {
        let result = [...(rows || [])];
        if (this.selectedRecordType && this.selectedRecordType !== 'All') {
            result = result.filter((row) => row.recordTypeDeveloperName === this.selectedRecordType);
        }
        if (this.selectedSubtype && this.selectedSubtype !== 'All') {
            result = result.filter((row) => row.accountSubtype === this.selectedSubtype);
        }
        if (this.selectedHcpClassification && this.selectedHcpClassification !== 'All') {
            result = result.filter(
                (row) => (row.hcpClassification || '').toUpperCase() === this.selectedHcpClassification.toUpperCase()
            );
        }
        if (this.selectedBrick && this.selectedBrick !== 'All') {
            result = result.filter((row) => row.brickId === this.selectedBrick);
        }
        return result;
    }

    applyDrillFilter(rows) {
        switch (this.drillMode) {
            case DRILL_MODES.ACHIEVEMENT:
            case DRILL_MODES.REMAINING:
                return rows.filter((row) => (row.visitGap || 0) > 0);
            case DRILL_MODES.CUSTOMER:
                return rows.filter((row) => !row.isVisited);
            case DRILL_MODES.RF:
                return rows.filter((row) => row.frequencyStatus === 'LCF' || (row.visitGap || 0) > 0);
            default:
                return rows;
        }
    }

    applySearch() {
        const term = (this.searchDraft || '').trim();
        this.searchTerm = term.toLowerCase();
        this.filteredAccountRows = term
            ? this.classFilteredRows.filter((row) => matchesAccountSearch(row, term))
            : [...this.classFilteredRows];
        this.currentPage = 1;
        this.updatePage();
        this.isSearching = false;
    }

    scheduleSearch(event) {
        this.searchDraft = event?.target?.value || '';
        this.isSearching = true;
        clearTimeout(this.searchDebounceTimer);
        this.searchDebounceTimer = window.setTimeout(() => {
            this.applySearch();
        }, SEARCH_DEBOUNCE_MS);
    }

    commitSearch(event) {
        this.searchDraft = event?.target?.value || '';
        clearTimeout(this.searchDebounceTimer);
        this.applySearch();
    }

    clearSearch() {
        this.searchDraft = '';
        this.searchTerm = '';
        const input = this.template.querySelector('.account-search-input');
        if (input) {
            input.value = '';
            input.focus();
        }
        clearTimeout(this.searchDebounceTimer);
        this.applySearch();
    }

    updatePage() {
        const total = this.filteredAccountRows?.length || 0;
        const maxPage = Math.max(1, Math.ceil(total / ACCOUNT_PAGE_SIZE));
        if (this.currentPage > maxPage) {
            this.currentPage = maxPage;
        }

        const sortedRows = sortAccountRows(
            this.filteredAccountRows,
            this.sortField,
            this.sortDirection
        );
        const start = (this.currentPage - 1) * ACCOUNT_PAGE_SIZE;
        this.displayAccountRows = sortedRows
            .slice(start, start + ACCOUNT_PAGE_SIZE)
            .map((row) => this.decorateDisplayRow(row));
    }

    handleSort(event) {
        const field = event?.currentTarget?.dataset?.sortField;
        if (!field || !SORTABLE_ACCOUNT_FIELDS.includes(field)) {
            return;
        }

        if (this.sortField === field) {
            this.sortDirection = this.sortDirection === 'asc' ? 'desc' : 'asc';
        } else {
            this.sortField = field;
            this.sortDirection = 'asc';
        }

        this.currentPage = 1;
        this.updatePage();
    }

    handlePreviousPage() {
        if (!this.hasPreviousPage) {
            return;
        }
        this.currentPage -= 1;
        this.updatePage();
    }

    handleNextPage() {
        if (!this.hasNextPage) {
            return;
        }
        this.currentPage += 1;
        this.updatePage();
    }

    handleFilter(event) {
        const value = event?.currentTarget?.dataset?.value;
        if (!value || value === this.selectedFilter) {
            return;
        }
        this.selectedFilter = value;
        this.applyClassFilter();
    }

    applyDrillSort(mode) {
        const next = DRILL_SORT[mode];
        if (!next) {
            this.sortField = 'gap';
            this.sortDirection = 'desc';
            return;
        }
        this.sortField = next.field;
        this.sortDirection = next.direction;
    }

    scrollToDrill() {
        window.setTimeout(() => {
            const panel = this.template.querySelector('.accounts-section');
            panel?.scrollIntoView({ behavior: 'smooth', block: 'start' });
        }, 0);
    }

    handleKpiDrill(event) {
        const kpiId = event?.currentTarget?.dataset?.kpiId;
        if (!kpiId) {
            return;
        }
        const modeMap = {
            visit: DRILL_MODES.ACHIEVEMENT,
            customer: DRILL_MODES.CUSTOMER,
            rf: DRILL_MODES.RF,
            remaining: DRILL_MODES.REMAINING
        };
        const nextMode = modeMap[kpiId];
        if (!nextMode) {
            return;
        }
        const turningOff = this.drillMode === nextMode;
        this.drillMode = turningOff ? DRILL_MODES.ALL : nextMode;
        if (!turningOff) {
            this.applyDrillSort(nextMode);
        }
        this.applyClassFilter();
        if (!turningOff) {
            this.scrollToDrill();
        }
    }

    handleClassDrill(event) {
        const classKey = event?.currentTarget?.dataset?.classKey;
        if (!classKey) {
            return;
        }
        const turningOff = this.selectedFilter === classKey;
        this.selectedFilter = turningOff ? 'All' : classKey;
        if (!turningOff && this.drillMode === DRILL_MODES.ALL) {
            this.applyDrillSort(DRILL_MODES.REMAINING);
        }
        this.applyClassFilter();
        if (!turningOff) {
            this.scrollToDrill();
        }
    }

    handleRecordTypeChange(event) {
        this.selectedRecordType = event.detail.value;
        this.applyClassFilter();
    }

    handleSubtypeChange(event) {
        this.selectedSubtype = event.detail.value;
        this.applyClassFilter();
    }

    handleHcpClassificationChange(event) {
        this.selectedHcpClassification = event.detail.value;
        this.applyClassFilter();
    }

    handleBrickChange(event) {
        this.selectedBrick = event.detail.value;
        this.applyClassFilter();
    }

    handleClearDrill() {
        this.drillMode = DRILL_MODES.ALL;
        this.selectedFilter = 'All';
        this.sortField = 'name';
        this.sortDirection = 'asc';
        this.applyClassFilter();
    }

    handleToggleMoreFilters() {
        this.showMoreFilters = !this.showMoreFilters;
    }

    handleOpenPlanner() {
        this[NavigationMixin.Navigate]({
            type: 'standard__navItemPage',
            attributes: { apiName: PLANNER_TAB_API }
        });
    }

    async handlePlanVisit(event) {
        event?.stopPropagation?.();
        const accountId = event?.currentTarget?.dataset?.accountId;
        if (!accountId || this.planningAccountId) {
            return;
        }

        this.planningAccountId = accountId;
        this.updatePage();
        try {
            const start = clampToWorkingHours(ceilToNextSlot(new Date()));
            const end = new Date(start.getTime() + 60 * 60000);

            if (isOfflineMode()) {
                const clientVisitKey = newClientKey('visit');
                await queueOfflineAction({
                    actionType: 'UPSERT_VISIT',
                    clientVisitKey,
                    clientActionKey: clientVisitKey,
                    payloadJson: JSON.stringify({
                        accountId,
                        startDateTime: start.toISOString(),
                        endDateTime: end.toISOString(),
                        status: 'Draft',
                        visitType: 'Planned (Automatically)'
                    })
                });
                this.showToast(
                    'Queued offline',
                    'Draft visit will be created when you are back online.',
                    'success'
                );
                return;
            }

            const created = await upsertVisit({
                visitId: null,
                accountId,
                startDateTime: start.toISOString(),
                endDateTime: end.toISOString(),
                status: 'Draft',
                visitType: 'Planned (Automatically)',
                cancellationReason: null,
                zetaProjectId: null,
                visitObjective: null
            });

            this.showToast('Draft created', 'Opening the visit so you can finish planning.', 'success');
            this[NavigationMixin.Navigate]({
                type: 'standard__recordPage',
                attributes: { recordId: created.id, objectApiName: 'Visit__c', actionName: 'view' }
            });
        } catch (e) {
            this.showErrorToast(e, 'Unable to create a draft visit.');
        } finally {
            this.planningAccountId = null;
            this.updatePage();
        }
    }

    handleStopHelpClick(event) {
        event.stopPropagation();
    }

    handleLeaderboardScope(event) {
        const scope = event?.currentTarget?.dataset?.scope;
        if (!scope || scope === this.leaderboardScope) {
            return;
        }
        this.leaderboardScope = scope;
    }

    handleBadgeClick(event) {
        const badgeId = event?.currentTarget?.dataset?.badgeId;
        if (!badgeId) {
            return;
        }
        const badge = (this.achievementBadges || []).find((item) => item.id === badgeId);
        if (!badge) {
            return;
        }

        const firstName = this.userFirstName;
        this.badgeModalTitle = `${badge.icon} ${badge.label}`;
        if (badge.earned) {
            this.badgeModalMessage = `Hello ${firstName}, you have completed ${badge.earnDescription} and earned the ${badge.label} badge!`;
        } else {
            this.badgeModalMessage = `Hello ${firstName}, keep going! ${badge.progress}% toward ${badge.label} — ${badge.hint}`;
        }
        this.showBadgeModal = true;
    }

    handleCloseBadgeModal() {
        this.showBadgeModal = false;
        this.badgeModalTitle = '';
        this.badgeModalMessage = '';
    }

    handleOpenAccount(event) {
        const accountId = event?.currentTarget?.dataset?.accountId;
        if (!accountId) {
            return;
        }
        this[NavigationMixin.Navigate]({
            type: 'standard__recordPage',
            attributes: { recordId: accountId, objectApiName: 'Account', actionName: 'view' }
        });
    }

    showToast(title, message, variant) {
        this.dispatchEvent(new ShowToastEvent({ title, message, variant }));
    }

    showErrorToast(error, fallbackMessage) {
        const message = this.reduceError(error) || fallbackMessage;
        this.dispatchEvent(new ShowToastEvent({ title: 'Error', message, variant: 'error' }));
    }

    reduceError(error) {
        if (!error) {
            return null;
        }
        if (typeof error === 'string') {
            return error;
        }
        return (
            error?.body?.message ||
            error?.message ||
            (Array.isArray(error?.body) ? error.body.map((e) => e.message).join(', ') : null)
        );
    }
}
