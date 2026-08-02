import { LightningElement, wire } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { refreshApex } from '@salesforce/apex';
import getFilterOptions from '@salesforce/apex/EmployeeTimeCardPaceController.getFilterOptions';
import getPaceDetail from '@salesforce/apex/EmployeeTimeCardPaceController.getPaceDetail';
import getPaceTeamGrid from '@salesforce/apex/EmployeeTimeCardPaceController.getPaceTeamGrid';
import getMonthlyPerformanceCsv from '@salesforce/apex/EmployeeTimeCardPaceExportController.getMonthlyPerformanceCsv';
import getExecutiveReportPageUrl from '@salesforce/apex/EmployeeTimeCardPaceExportController.getExecutiveReportPageUrl';
import hasSalaryPermission from '@salesforce/customPermission/Manage_Monthly_Salaries';
import CLOUDASTICK_LOGO from '@salesforce/resourceUrl/CloudastickLogo';
import { parseEmployeeReportDetailRows } from 'c/reportDetailsFormat';
import { getCompanyBrand } from 'c/companyBranding';

const EMPLOYEE_CARD_DETAIL_LABELS = {
    'External ID': 'ID No',
    Segment: 'Segment',
    Company: 'Company'
};

const CLOUDASTICK_SITE_URL = 'https://www.cloudastick.org';

const STATUS_LABELS = {
    ahead: 'Ahead',
    on_track: 'On track',
    behind: 'Behind',
    critical: 'Critical',
    not_applicable: 'N/A'
};

const CURRENCY_CODE = 'EGP';
const CURRENCY_LOCALE = 'en-EG';
const TEAM_VIEW_VALUE = '__team__';
const TEAM_PAGE_SIZE = 12;
const FILTER_ALL = '__all__';

const PACE_STATUS_OPTIONS = [
    { label: 'All statuses', value: FILTER_ALL },
    { label: 'Ahead', value: 'ahead' },
    { label: 'On track', value: 'on_track' },
    { label: 'Behind', value: 'behind' },
    { label: 'Critical', value: 'critical' }
];

const TEAM_SORT_OPTIONS = [
    { label: 'Name A–Z', value: 'name_asc' },
    { label: 'Name Z–A', value: 'name_desc' }
];

const SCORE_SALARY_BADGE_KEYS = new Set(['score_hunter']);

export default class EmployeePaceDashboard extends LightningElement {
    cloudastickLogoUrl = CLOUDASTICK_LOGO;
    cloudastickSiteUrl = CLOUDASTICK_SITE_URL;

    filterOptions;
    selectedMonth;
    selectedUserId;
    detail;
    teamGrid;
    teamPage = 1;
    teamFilterStatus = FILTER_ALL;
    teamFilterCompany = FILTER_ALL;
    teamFilterSegment = FILTER_ALL;
    teamMinCallRate = '';
    teamMaxCallRate = '';
    teamMinRevPercent = '';
    teamMaxRevPercent = '';
    teamSort = 'name_asc';
    userSelectionInitialized = false;
    employeeSearchTerm = '';
    employeeLogoFailed = false;
    activeBrandKey = 'mokhtabar';
    isLoading = false;
    isExporting = false;
    errorMessage;
    wiredFilterResult;

    @wire(getFilterOptions)
    wiredFilters(result) {
        this.wiredFilterResult = result;
        if (result.data) {
            this.filterOptions = result.data;
            if (!this.selectedMonth) {
                this.selectedMonth = result.data.defaultMonthValue;
            }
            if (!this.userSelectionInitialized && result.data.defaultUserId) {
                this.selectedUserId = result.data.defaultUserId;
                this.userSelectionInitialized = true;
            }
            this.loadView();
        } else if (result.error) {
            this.errorMessage = this.reduceError(result.error);
        }
    }

    get canViewTeam() {
        return this.filterOptions?.canViewTeam === true;
    }

    get canExportPerformance() {
        return hasSalaryPermission === true;
    }

    get monthOptions() {
        return this.filterOptions?.monthOptions ?? [];
    }

    get monthOptionIndex() {
        return this.monthOptions.findIndex((opt) => opt.value === this.selectedMonth);
    }

    get isPrevMonthDisabled() {
        const idx = this.monthOptionIndex;
        return idx < 0 || idx >= this.monthOptions.length - 1;
    }

    get isNextMonthDisabled() {
        return this.monthOptionIndex <= 0;
    }

    get userOptions() {
        if (!this.canViewTeam) {
            return this.filterOptions?.userOptions ?? [];
        }
        const team = [{ label: 'Team pace', value: TEAM_VIEW_VALUE }];
        const users = this.filterOptions?.userOptions ?? [];
        return team.concat(users);
    }

    get filteredUserOptions() {
        const term = (this.employeeSearchTerm || '').trim().toLowerCase();
        const users = this.filterOptions?.userOptions ?? [];
        const filtered = term ? users.filter((opt) => this.matchesEmployeeSearch(opt, term)) : users;
        const searching = term.length > 0;

        const userOptions = filtered.map((opt) => {
            const label =
                searching && opt.company ? `${opt.label} · ${opt.company}` : opt.label;
            return { label, value: opt.value };
        });

        if (!this.canViewTeam) {
            return userOptions;
        }

        return [{ label: 'Team pace', value: TEAM_VIEW_VALUE }].concat(userOptions);
    }

    matchesEmployeeSearch(opt, term) {
        const fields = [
            opt.label,
            opt.value,
            opt.company,
            opt.externalId,
            opt.businessSegment
        ];
        return fields.some((field) => field && String(field).toLowerCase().includes(term));
    }

    get showTeamGrid() {
        return this.canViewTeam && this.selectedUserId === TEAM_VIEW_VALUE;
    }

    get isMyPaceView() {
        return !this.showTeamGrid;
    }

    get myPaceChipClass() {
        return this.isMyPaceView ? 'pace-chip pace-chip_active' : 'pace-chip';
    }

    get teamChipClass() {
        return this.showTeamGrid ? 'pace-chip pace-chip_active' : 'pace-chip';
    }

    get teamTotalPages() {
        if (!this.teamGrid?.totalCount) {
            return 1;
        }
        const size = this.teamGrid.pageSize || TEAM_PAGE_SIZE;
        return Math.max(1, Math.ceil(this.teamGrid.totalCount / size));
    }

    get teamPaginationLabel() {
        if (!this.teamGrid?.totalCount) {
            return '';
        }
        const page = this.teamGrid.page || 1;
        const size = this.teamGrid.pageSize || TEAM_PAGE_SIZE;
        const start = (page - 1) * size + 1;
        const end = Math.min(page * size, this.teamGrid.totalCount);
        return `Showing ${start}–${end} of ${this.teamGrid.totalCount}`;
    }

    get isTeamFirstPage() {
        return (this.teamGrid?.page || 1) <= 1;
    }

    get isTeamLastPage() {
        return (this.teamGrid?.page || 1) >= this.teamTotalPages;
    }

    get teamCurrentPage() {
        return this.teamGrid?.page || this.teamPage || 1;
    }

    get paceStatusFilterOptions() {
        return PACE_STATUS_OPTIONS;
    }

    get teamSortOptions() {
        return TEAM_SORT_OPTIONS;
    }

    get companyFilterOptions() {
        return this.withAllOption(this.filterOptions?.companyOptions);
    }

    get businessSegmentFilterOptions() {
        return this.withAllOption(this.filterOptions?.businessSegmentOptions);
    }

    get hasTeamRows() {
        return (this.formattedTeamRows?.length ?? 0) > 0;
    }

    get hasActiveTeamFilters() {
        return (
            this.teamFilterStatus !== FILTER_ALL ||
            this.teamFilterCompany !== FILTER_ALL ||
            this.teamFilterSegment !== FILTER_ALL ||
            this.teamMinCallRate !== '' ||
            this.teamMaxCallRate !== '' ||
            this.teamMinRevPercent !== '' ||
            this.teamMaxRevPercent !== '' ||
            this.teamSort !== 'name_asc'
        );
    }

    withAllOption(options) {
        const all = [{ label: 'All', value: FILTER_ALL }];
        return all.concat(options ?? []);
    }

    get showDetail() {
        return !this.showTeamGrid;
    }

    get hasDetail() {
        return this.detail?.timeCardId;
    }

    get brands() {
        return (this.detail?.brands ?? []).filter((b) => b.applicable !== false);
    }

    get activeBrand() {
        const applicable = this.brands;
        return applicable.find((b) => b.brandKey === this.activeBrandKey) ?? applicable[0];
    }

    get brandTabs() {
        return this.brands.map((b) => ({
            key: b.brandKey,
            label: b.brandLabel,
            className: b.brandKey === this.activeBrandKey ? 'brand-tab active' : 'brand-tab'
        }));
    }

    get employeeCompanyLabel() {
        return this.detail?.employeeCompany || '';
    }

    get hasEmployeeCompany() {
        return Boolean(this.employeeCompanyLabel);
    }

    get hasEmployeeReportDetails() {
        return this.employeeReportDetailRows.length > 0;
    }

    get showEmployeeIdCard() {
        return Boolean(this.employeeCardName);
    }

    get employeeReportDetailRows() {
        return parseEmployeeReportDetailRows(this.detail?.employeeReportDetails);
    }

    get employeeCardName() {
        const nameRow = this.employeeReportDetailRows.find((row) => row.label === 'Name');
        return nameRow?.value || this.detail?.employeeName || '';
    }

    get employeeCardProfile() {
        const profileRow = this.employeeReportDetailRows.find((row) => row.label === 'Profile');
        return profileRow?.value || '';
    }

    get hasEmployeeCardProfile() {
        return Boolean(this.employeeCardProfile);
    }

    get employeeCardCompany() {
        const companyRow = this.employeeReportDetailRows.find((row) => row.label === 'Company');
        return companyRow?.value || this.detail?.employeeCompany || '';
    }

    get employeeCompanyBrand() {
        return getCompanyBrand(this.employeeCardCompany);
    }

    get hasEmployeeCompanyLogo() {
        return Boolean(this.employeeCompanyBrand?.logoUrl) && !this.employeeLogoFailed;
    }

    handleEmployeeLogoError() {
        this.employeeLogoFailed = true;
    }

    get employeeCompanyLogoUrl() {
        return this.employeeCompanyBrand?.logoUrl || '';
    }

    get employeeCompanyMonogram() {
        return this.employeeCompanyBrand?.monogram || '?';
    }

    get employeeIdCardHeaderStyle() {
        const brand = this.employeeCompanyBrand;
        return `--employee-card-header: ${brand.headerColor}; --employee-card-header-dark: ${brand.headerColorDark}; --employee-card-accent: ${brand.monogramColor};`;
    }

    get employeeIdCardDetailRows() {
        return this.employeeReportDetailRows
            .filter((row) => row.label !== 'Name' && row.label !== 'Profile')
            .map((row) => ({
                key: row.key,
                label: EMPLOYEE_CARD_DETAIL_LABELS[row.label] || row.label,
                value: row.value
            }));
    }

    get workingDaysLabel() {
        const wd = this.detail?.workingDays;
        if (!wd) {
            return '';
        }
        return `Day ${wd.elapsedWorkingDays} of ${wd.totalWorkingDays} working days`;
    }

    get heroRevenueMetric() {
        return this.detail?.rollupTotalRevenue ?? this.detail?.rollupWalkInRevenue;
    }

    get revenueProgressStyle() {
        return this.progressStyle(this.heroRevenueMetric?.currentAchPercent);
    }

    get visitsProgressStyle() {
        return this.progressStyle(this.detail?.rollupWalkInVisits?.currentAchPercent);
    }

    get projectedRevenueLabel() {
        const m = this.heroRevenueMetric;
        if (!m) {
            return '';
        }
        return `At this pace: ~${this.formatCurrency(m.projectedActual)} total revenue (${this.formatPercent(m.projectedAchPercent)} of target)`;
    }

    get showCommissionProjection() {
        return this.detail?.commissions?.projectedFinalCommission != null;
    }

    get projectedCommissionValue() {
        return this.formatCurrency(this.detail?.commissions?.projectedFinalCommission);
    }

    get payrollMonthName() {
        const year = this.detail?.year;
        const month = this.detail?.month;
        if (!year || !month) {
            return null;
        }
        let payrollYear = year;
        let payrollMonth = month + 1;
        if (payrollMonth > 12) {
            payrollMonth = 1;
            payrollYear += 1;
        }
        return new Intl.DateTimeFormat('en-US', { month: 'long' }).format(
            new Date(payrollYear, payrollMonth - 1, 1)
        );
    }

    get projectedCommissionPayrollLabel() {
        const payrollMonth = this.payrollMonthName;
        if (!payrollMonth) {
            return this.projectedCommissionValue;
        }
        return `${this.projectedCommissionValue} in ${payrollMonth}'s Payroll`;
    }

    get currentCommissionLabel() {
        const current = this.detail?.commissions?.currentFinalCommission;
        if (current == null) {
            return '';
        }
        return `Current: ${this.formatCurrency(current)}`;
    }

    get hasCommissionBreakdown() {
        return Boolean(this.commissionBreakdownLabel);
    }

    get commissionBreakdownLabel() {
        const c = this.detail?.commissions;
        if (!c) {
            return '';
        }
        const walkIn = c.projectedWalkInScoreCommission ?? c.projectedTotalWalkInChannel ?? 0;
        const corporate = c.projectedCorporateScoreCommission ?? c.projectedTotalCorporateChannel ?? 0;
        if (walkIn <= 0 && corporate <= 0) {
            return '';
        }
        const uncapped = c.projectedUncappedFinalCommission ?? Math.max(walkIn + corporate, (c.projectedTotalWalkInChannel ?? 0) + (c.projectedTotalCorporateChannel ?? 0));
        return `Effective commission: ${this.formatCurrency(uncapped)} (best of scheme totals vs score commission)`;
    }

    get activitySummary() {
        return this.detail?.activitySummary;
    }

    get hasActivitySummary() {
        return this.activitySummary != null;
    }

    get streakLabel() {
        const days = this.activitySummary?.visitStreakDays ?? this.detail?.streakDays ?? 0;
        return days === 1 ? '1 day visit streak' : `${days} day visit streak`;
    }

    get timeOffLabel() {
        const days = this.activitySummary?.timeOffDays ?? 0;
        if (days === 0) {
            return 'No time off';
        }
        return days === 1 ? '1 day time off' : `${this.formatDecimal(days)} days time off`;
    }

    get callRateLabel() {
        return this.formatPercent(this.activitySummary?.callRatePercent);
    }

    get callRateDetailLabel() {
        const actual = this.activitySummary?.callRateActual ?? 0;
        const target = this.activitySummary?.callRateTarget ?? 0;
        return `${this.formatNumber(actual)} / ${this.formatNumber(target)} calls`;
    }

    get callRateProgressStyle() {
        return this.progressStyle(Math.min(100, this.activitySummary?.callRatePercent || 0));
    }

    get callRateStatusLabel() {
        return this.statusLabel(this.activitySummary?.callRateStatus || 'behind');
    }

    get callRateStatusClass() {
        return this.statusClass(this.activitySummary?.callRateStatus || 'behind');
    }

    get activityStats() {
        const a = this.activitySummary;
        if (!a) {
            return [];
        }
        return [
            {
                key: 'am',
                label: 'AM visits',
                tag: 'Corporate',
                tagTitle: 'Morning corporate visits',
                tagClass: 'pace-activity__tag pace-activity__tag_corporate',
                value: this.formatNumber(a.amVisits)
            },
            {
                key: 'pm',
                label: 'PM visits',
                tag: 'Doctor',
                tagTitle: 'Medical professional — evening visits to private clinics & polyclinics',
                tagClass: 'pace-activity__tag pace-activity__tag_doctor',
                value: this.formatNumber(a.pmVisits)
            },
            { key: 'coach', label: 'Coaching', value: this.formatNumber(a.coachingVisits) },
            { key: 'tot', label: 'Time-off taken', value: this.formatDecimal(a.totDays) }
        ];
    }

    get badges() {
        return (this.detail?.badges ?? [])
            .filter((b) => !SCORE_SALARY_BADGE_KEYS.has(b.badgeKey))
            .map((b) => ({
                ...b,
                chipClass: b.earned ? 'badge-chip earned' : 'badge-chip locked',
                cardClass: b.earned ? 'pace-badge-card earned' : 'pace-badge-card locked',
                iconVariant: b.earned ? 'success' : undefined,
                criteriaText: this.stripSalaryLingo(b.criteria ? `Unlock: ${b.criteria}` : ''),
                detailText: this.stripSalaryLingo(
                    b.earned ? b.earnedReason || b.description || '' : b.howToEarn || b.description || ''
                ),
                statusLabel: b.earned ? 'Unlocked!' : 'How to unlock',
                statusClass: b.earned ? 'pace-badge-card__status earned' : 'pace-badge-card__status locked'
            }));
    }

    get nextBestActions() {
        return (this.detail?.nextBestActions ?? []).filter(
            (action) => !this.isScoreOrSalaryAction(action)
        );
    }

    isScoreOrSalaryAction(action) {
        const haystack = `${action?.title || ''} ${action?.body || ''}`.toLowerCase();
        return (
            haystack.includes('salary') ||
            haystack.includes('score') ||
            haystack.includes('commission')
        );
    }

    stripSalaryLingo(text) {
        if (!text) {
            return '';
        }
        return text
            .replace(/\([^)]*salary[^)]*\)/gi, '')
            .replace(/basic salary[^.]*\.?/gi, '')
            .replace(/mid tier[^.]*top tier[^.]*\.?/gi, '')
            .replace(/\d+[–-]\d+\s*score\s*pts[^.]*salary[^.]*\.?/gi, '')
            .replace(/\s+/g, ' ')
            .trim();
    }

    get formattedTeamRows() {
        return (this.teamGrid?.rows ?? []).map((row) => ({
            timeCardId: row.timeCardId,
            employeeUserId: row.employeeUserId,
            employeeName: row.employeeName,
            projectedWalkInRevenueAchPercent: Math.round(row.projectedWalkInRevenueAchPercent || 0),
            projectedWalkInVisitsAchPercent: Math.round(row.projectedWalkInVisitsAchPercent || 0),
            callRatePercent: Math.round(row.callRatePercent || 0),
            badgeCountEarned: row.badgeCountEarned,
            streakDays: row.streakDays,
            timeOffDays: this.formatDecimal(row.timeOffDays || 0),
            statusLabel: this.statusLabel(row.overallPaceStatus),
            statusClass: this.statusClass(row.overallPaceStatus)
        }));
    }

    get visitsProgressStyle() {
        return this.callRateProgressStyle;
    }

    get visitsAchLabel() {
        return this.callRateLabel;
    }

    get visitsStatusLabel() {
        return this.callRateStatusLabel;
    }

    get visitsStatusClass() {
        return this.callRateStatusClass;
    }

    get revenueAchLabel() {
        if (this.detail?.revenueDataNotSynced) {
            return '—';
        }
        return this.formatPercent(this.heroRevenueMetric?.currentAchPercent);
    }

    get revenueDetailLabel() {
        if (this.detail?.revenueDataNotSynced) {
            return 'Awaiting revenue sync';
        }
        const m = this.heroRevenueMetric;
        const actual = m?.actual ?? 0;
        const target = m?.target ?? 0;
        if (target > 0) {
            return `${this.formatCurrency(actual)} / ${this.formatCurrency(target)}`;
        }
        return `${this.formatCurrency(actual)} achieved · no target set`;
    }

    get revenueStatusLabel() {
        return this.statusLabel(this.heroRevenueMetric?.paceStatus);
    }

    get revenueStatusClass() {
        return this.statusClass(this.heroRevenueMetric?.paceStatus);
    }

    get activeBrandMetrics() {
        const b = this.activeBrand;
        if (!b) {
            return [];
        }
        return [b.walkInRevenue, b.walkInVisits, b.corpRevenue, b.corpVisits]
            .filter(Boolean)
            .map((m) => this.formatMetric(m));
    }

    syncActiveBrandKey() {
        const applicable = this.brands;
        if (!applicable.length) {
            return;
        }
        const stillValid = applicable.some((b) => b.brandKey === this.activeBrandKey);
        if (!stillValid) {
            this.activeBrandKey = applicable[0].brandKey;
        }
    }

    formatMetric(metric) {
        const pct = metric.currentAchPercent || 0;
        const projPct = metric.projectedAchPercent || 0;
        const isCount = metric.valueType === 'count';
        const actual = metric.actual ?? 0;
        const target = metric.target ?? 0;
        const projected = metric.projectedActual ?? 0;
        const formatQty = (value) => (isCount ? this.formatNumber(Math.round(value)) : this.formatCurrency(value));
        const unitSuffix = isCount ? ' target visits' : ' target';

        const achievedQuantity =
            target > 0
                ? `${formatQty(actual)} of ${formatQty(target)}${unitSuffix}`
                : `${formatQty(actual)}${isCount ? ' visits' : ''} achieved · no target set`;

        const projectedQuantity =
            target > 0
                ? `~${formatQty(projected)}${isCount ? ' visits' : ''} projected month-end`
                : `~${formatQty(projected)}${isCount ? ' visits' : ''} projected`;

        const projectionPace = `Projection ${this.statusLabel(metric.paceStatus).toLowerCase()} (${this.formatPercent(projPct)} of target)`;

        return {
            ...metric,
            statusLabel: this.statusLabel(metric.paceStatus),
            statusClass: this.statusClass(metric.paceStatus),
            barStyle: `width: ${Math.min(100, pct)}%`,
            achievedLine: `${achievedQuantity} · ${this.formatPercent(pct)} now`,
            projectedLine: `${projectedQuantity} · ${projectionPace}`
        };
    }

    get pendingBanner() {
        return this.detail?.targetCalculationPending === true;
    }

    get targetCalcFailedBanner() {
        return (
            this.detail?.targetCalculationPending !== true &&
            !!this.detail?.targetCalculationError
        );
    }

    get targetCalcFailedMessage() {
        return this.detail?.targetCalculationError;
    }

    get revenueNotSyncedBanner() {
        return this.detail?.revenueDataNotSynced === true;
    }

    get revenueSyncMessage() {
        return 'Revenue data for this month is not yet synchronized. Once targets and achievements are loaded, pace metrics will update here.';
    }

    handleMonthChange(event) {
        this.selectedMonth = event.detail.value;
        this.teamPage = 1;
        this.loadView();
    }

    handlePrevMonth() {
        const idx = this.monthOptionIndex;
        if (idx >= 0 && idx < this.monthOptions.length - 1) {
            this.selectedMonth = this.monthOptions[idx + 1].value;
            this.teamPage = 1;
            this.loadView();
        }
    }

    handleNextMonth() {
        const idx = this.monthOptionIndex;
        if (idx > 0) {
            this.selectedMonth = this.monthOptions[idx - 1].value;
            this.teamPage = 1;
            this.loadView();
        }
    }

    handleEmployeeSearchChange(event) {
        this.employeeSearchTerm = event.detail.value;
    }

    handleUserChange(event) {
        this.selectedUserId = event.detail.value;
        this.employeeSearchTerm = '';
        this.teamPage = 1;
        this.loadView();
    }

    handleBrandTab(event) {
        this.activeBrandKey = event.currentTarget.dataset.key;
    }

    handleRefresh() {
        refreshApex(this.wiredFilterResult);
        this.loadView();
    }

    async handleExportCsv() {
        if (!this.selectedMonth) {
            return;
        }
        this.isExporting = true;
        try {
            const { year, month } = this.parseMonth(this.selectedMonth);
            const csv = await getMonthlyPerformanceCsv({ year, month });
            const monthPart = month < 10 ? `0${month}` : String(month);
            this.downloadCsv(csv, `employee_monthly_targets_${year}_${monthPart}.csv`);
            this.showToast('Export ready', 'Monthly performance CSV downloaded.', 'success');
        } catch (error) {
            this.showToast('Export failed', this.reduceError(error), 'error');
        } finally {
            this.isExporting = false;
        }
    }

    async handleExportPdf() {
        if (!this.selectedMonth) {
            return;
        }
        this.isExporting = true;
        try {
            const { year, month } = this.parseMonth(this.selectedMonth);
            const url = await getExecutiveReportPageUrl({ year, month });
            window.open(url, '_blank');
            this.showToast('Export ready', 'Executive PDF opened in a new tab.', 'success');
        } catch (error) {
            this.showToast('Export failed', this.reduceError(error), 'error');
        } finally {
            this.isExporting = false;
        }
    }

    downloadCsv(content, filename) {
        const blob = new Blob([content], { type: 'text/csv;charset=utf-8;' });
        const link = document.createElement('a');
        link.href = URL.createObjectURL(blob);
        link.download = filename;
        link.click();
        URL.revokeObjectURL(link.href);
    }

    showToast(title, message, variant) {
        this.dispatchEvent(new ShowToastEvent({ title, message, variant }));
    }

    handleMyPace() {
        this.selectedUserId = this.filterOptions?.defaultUserId || '';
        this.teamPage = 1;
        this.loadView();
    }

    handleViewTeam() {
        this.selectedUserId = TEAM_VIEW_VALUE;
        this.teamPage = 1;
        this.loadView();
    }

    handleTeamPrevPage() {
        if (this.teamPage > 1) {
            this.teamPage -= 1;
            this.loadTeamGrid();
            this.scrollTeamIntoView();
        }
    }

    handleTeamNextPage() {
        if (this.teamPage < this.teamTotalPages) {
            this.teamPage += 1;
            this.loadTeamGrid();
            this.scrollTeamIntoView();
        }
    }

    handleTeamFilterChange(event) {
        const field = event.target.dataset.filter;
        if (!field) {
            return;
        }
        this[field] = event.detail.value;
        this.teamPage = 1;
        this.loadTeamGrid();
    }

    handleTeamNumberFilterChange(event) {
        const field = event.target.dataset.filter;
        if (!field) {
            return;
        }
        this[field] = event.detail.value;
    }

    handleTeamNumberFilterCommit() {
        this.teamPage = 1;
        this.loadTeamGrid();
    }

    handleClearTeamFilters() {
        this.teamFilterStatus = FILTER_ALL;
        this.teamFilterCompany = FILTER_ALL;
        this.teamFilterSegment = FILTER_ALL;
        this.teamMinCallRate = '';
        this.teamMaxCallRate = '';
        this.teamMinRevPercent = '';
        this.teamMaxRevPercent = '';
        this.teamSort = 'name_asc';
        this.teamPage = 1;
        this.loadTeamGrid();
    }

    scrollTeamIntoView() {
        const teamSection = this.template.querySelector('.pace-team');
        if (teamSection) {
            teamSection.scrollIntoView({ behavior: 'smooth', block: 'start' });
        }
    }

    handleTeamRowClick(event) {
        this.selectedUserId = event.currentTarget.dataset.userId;
        this.loadView();
    }

    async loadView() {
        if (!this.selectedMonth) {
            return;
        }
        this.isLoading = true;
        this.errorMessage = null;
        try {
            const { year, month } = this.parseMonth(this.selectedMonth);
            if (this.showTeamGrid) {
                await this.loadTeamGrid();
                this.detail = null;
            } else {
                const userId = this.selectedUserId || this.filterOptions?.defaultUserId;
                this.employeeLogoFailed = false;
                this.detail = await getPaceDetail({ year, month, userId });
                this.syncActiveBrandKey();
                this.teamGrid = null;
            }
        } catch (error) {
            this.errorMessage = this.reduceError(error);
        } finally {
            this.isLoading = false;
        }
    }

    async loadTeamGrid() {
        const { year, month } = this.parseMonth(this.selectedMonth);
        this.teamGrid = await getPaceTeamGrid({
            year,
            month,
            page: this.teamPage,
            pageSize: TEAM_PAGE_SIZE,
            filters: this.buildTeamFiltersPayload()
        });
    }

    buildTeamFiltersPayload() {
        const [sortField, sortDirection] = (this.teamSort || 'name_asc').split('_');
        return {
            paceStatus: this.teamFilterStatus,
            company: this.teamFilterCompany,
            businessSegment: this.teamFilterSegment,
            minCallRate: this.parseOptionalNumber(this.teamMinCallRate),
            maxCallRate: this.parseOptionalNumber(this.teamMaxCallRate),
            minRevPercent: this.parseOptionalNumber(this.teamMinRevPercent),
            maxRevPercent: this.parseOptionalNumber(this.teamMaxRevPercent),
            sortField,
            sortDirection
        };
    }

    parseOptionalNumber(value) {
        if (value === '' || value == null) {
            return null;
        }
        const parsed = Number(value);
        return Number.isFinite(parsed) ? parsed : null;
    }

    parseMonth(monthValue) {
        const parts = monthValue.split('-');
        return { year: parseInt(parts[0], 10), month: parseInt(parts[1], 10) };
    }

    progressStyle(percent) {
        const p = Math.min(100, Math.max(0, percent || 0));
        return `width: ${p}%`;
    }

    formatPercent(value) {
        if (value == null) {
            return '0%';
        }
        return `${Math.round(value)}%`;
    }

    formatNumber(value) {
        if (value == null) {
            return '0';
        }
        return new Intl.NumberFormat().format(Math.round(value));
    }

    formatDecimal(value) {
        if (value == null) {
            return '0';
        }
        const rounded = Math.round(value * 10) / 10;
        return Number.isInteger(rounded) ? String(rounded) : rounded.toFixed(1);
    }

    formatCurrency(value) {
        if (value == null) {
            return new Intl.NumberFormat(CURRENCY_LOCALE, {
                style: 'currency',
                currency: CURRENCY_CODE,
                maximumFractionDigits: 0
            }).format(0);
        }
        return new Intl.NumberFormat(CURRENCY_LOCALE, {
            style: 'currency',
            currency: CURRENCY_CODE,
            maximumFractionDigits: 0
        }).format(value);
    }

    statusLabel(status) {
        return STATUS_LABELS[status] || status;
    }

    statusClass(status) {
        return `pace-pill pace-pill_${status || 'behind'}`;
    }

    reduceError(error) {
        if (Array.isArray(error?.body)) {
            return error.body.map((e) => e.message).join(', ');
        }
        return error?.body?.message || error?.message || 'Unknown error';
    }
}
