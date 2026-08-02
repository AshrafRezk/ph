import { LightningElement, wire } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { refreshApex } from '@salesforce/apex';
import getFilterOptions from '@salesforce/apex/EmployeeTimeCardPaceController.getFilterOptions';
import getPaceDetail from '@salesforce/apex/EmployeeTimeCardPaceController.getPaceDetail';
import getPaceTeamGrid from '@salesforce/apex/EmployeeTimeCardPaceController.getPaceTeamGrid';
import getMonthlyPerformanceCsv from '@salesforce/apex/EmployeeTimeCardPaceExportController.getMonthlyPerformanceCsv';
import { parseEmployeeReportDetailRows } from 'c/reportDetailsFormat';

const STATUS_LABELS = {
    ahead: 'Ahead',
    on_track: 'On track',
    behind: 'Behind',
    critical: 'Critical',
    not_applicable: 'N/A'
};

const TEAM_VIEW_VALUE = '__team__';
const FILTER_ALL = '__all__';
const TEAM_PAGE_SIZE = 12;

export default class EmployeePaceDashboard extends LightningElement {
    filterOptions;
    selectedMonth;
    selectedUserId;
    detail;
    teamGrid;
    teamPage = 1;
    teamFilterStatus = FILTER_ALL;
    teamFilterCompany = FILTER_ALL;
    teamFilterSegment = FILTER_ALL;
    userSelectionInitialized = false;
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
        return this.canViewTeam;
    }

    get monthOptions() {
        return this.filterOptions?.monthOptions || [];
    }

    get showTeamGrid() {
        return this.canViewTeam && this.selectedUserId === TEAM_VIEW_VALUE;
    }

    get showDetail() {
        return !this.showTeamGrid;
    }

    get hasDetail() {
        return this.detail?.timeCardId != null;
    }

    get workingDaysLabel() {
        const wd = this.detail?.workingDays;
        if (!wd) {
            return '';
        }
        return `Day ${wd.dayOfMonth} - ${wd.elapsedWorkingDays} / ${wd.totalWorkingDays} working days`;
    }

    get revenueAchLabel() {
        return this.formatPercent(this.detail?.walkInRevenue?.currentAchPercent);
    }

    get visitsAchLabel() {
        return this.formatPercent(this.detail?.walkInVisits?.currentAchPercent);
    }

    get revenueStatusLabel() {
        return STATUS_LABELS[this.detail?.walkInRevenue?.paceStatus] || '';
    }

    get visitsStatusLabel() {
        return STATUS_LABELS[this.detail?.walkInVisits?.paceStatus] || '';
    }

    get revenueStatusClass() {
        return `pace-status pace-status_${this.detail?.walkInRevenue?.paceStatus || 'behind'}`;
    }

    get visitsStatusClass() {
        return `pace-status pace-status_${this.detail?.walkInVisits?.paceStatus || 'behind'}`;
    }

    get projectedRevenueLabel() {
        const m = this.detail?.walkInRevenue;
        if (!m) {
            return '';
        }
        return `Projected walk-in revenue: ${this.formatPercent(m.projectedAchPercent)} of target`;
    }

    get projectedVisitsLabel() {
        const m = this.detail?.walkInVisits;
        if (!m) {
            return '';
        }
        return `Projected walk-in visits: ${this.formatPercent(m.projectedAchPercent)} of target`;
    }

    get streakLabel() {
        return `${this.detail?.streakDays || 0}-day visit streak`;
    }

    get timeOffLabel() {
        const days = this.detail?.activitySummary?.timeOffDays || 0;
        return `${days} time-off days`;
    }

    get formattedBadges() {
        return (this.detail?.badges || []).map((badge) => ({
            ...badge,
            badgeClass: badge.earned ? 'pace-badge pace-badge_earned' : 'pace-badge'
        }));
    }

    get employeeDetailRows() {
        return parseEmployeeReportDetailRows(this.detail?.employeeReportDetails);
    }

    get formattedTeamRows() {
        return (this.teamGrid?.rows || []).map((row) => ({
            ...row,
            statusLabel: STATUS_LABELS[row.overallPaceStatus] || row.overallPaceStatus,
            statusClass: `pace-status pace-status_${row.overallPaceStatus || 'behind'}`
        }));
    }

    get hasTeamRows() {
        return (this.teamGrid?.rows || []).length > 0;
    }

    get teamCurrentPage() {
        return this.teamGrid?.page || this.teamPage;
    }

    get teamTotalPages() {
        const total = this.teamGrid?.totalCount || 0;
        const size = this.teamGrid?.pageSize || TEAM_PAGE_SIZE;
        return Math.max(1, Math.ceil(total / size));
    }

    get isTeamFirstPage() {
        return this.teamCurrentPage <= 1;
    }

    get isTeamLastPage() {
        return this.teamCurrentPage >= this.teamTotalPages;
    }

    get teamPaginationLabel() {
        const total = this.teamGrid?.totalCount || 0;
        return `${total} team member${total === 1 ? '' : 's'}`;
    }

    get companyFilterOptions() {
        return [{ label: 'All companies', value: FILTER_ALL }, ...(this.filterOptions?.companyOptions || [])];
    }

    get businessSegmentFilterOptions() {
        return [{ label: 'All segments', value: FILTER_ALL }, ...(this.filterOptions?.businessSegmentOptions || [])];
    }

    get paceStatusFilterOptions() {
        return [
            { label: 'All statuses', value: FILTER_ALL },
            { label: 'Ahead', value: 'ahead' },
            { label: 'On track', value: 'on_track' },
            { label: 'Behind', value: 'behind' },
            { label: 'Critical', value: 'critical' }
        ];
    }

    get myPaceChipClass() {
        return `pace-chip${this.selectedUserId !== TEAM_VIEW_VALUE ? ' pace-chip_active' : ''}`;
    }

    get teamChipClass() {
        return `pace-chip${this.selectedUserId === TEAM_VIEW_VALUE ? ' pace-chip_active' : ''}`;
    }

    handleMonthChange(event) {
        this.selectedMonth = event.detail.value;
        this.teamPage = 1;
        this.loadView();
    }

    handleUserChange(event) {
        this.selectedUserId = event.detail.value;
        this.teamPage = 1;
        this.loadView();
    }

    handleMyPace() {
        if (this.filterOptions?.defaultUserId) {
            this.selectedUserId = this.filterOptions.defaultUserId;
            this.loadView();
        }
    }

    handleViewTeam() {
        this.selectedUserId = TEAM_VIEW_VALUE;
        this.teamPage = 1;
        this.loadView();
    }

    handleTeamFilterChange(event) {
        const field = event.target.dataset.filter;
        if (field) {
            this[field] = event.detail.value;
            this.teamPage = 1;
            this.loadTeamGrid();
        }
    }

    handleTeamRowClick(event) {
        const userId = event.currentTarget.dataset.userId;
        if (userId) {
            this.selectedUserId = userId;
            this.loadView();
        }
    }

    handleTeamPrevPage() {
        if (!this.isTeamFirstPage) {
            this.teamPage -= 1;
            this.loadTeamGrid();
        }
    }

    handleTeamNextPage() {
        if (!this.isTeamLastPage) {
            this.teamPage += 1;
            this.loadTeamGrid();
        }
    }

    handleRefresh() {
        refreshApex(this.wiredFilterResult).then(() => this.loadView());
    }

    async handleExportCsv() {
        this.isExporting = true;
        try {
            const { year, month } = this.parseMonthValue(this.selectedMonth);
            const csv = await getMonthlyPerformanceCsv({ year, month });
            const blob = new Blob([csv], { type: 'text/csv;charset=utf-8;' });
            const link = document.createElement('a');
            link.href = URL.createObjectURL(blob);
            link.download = `pace-performance-${this.selectedMonth}.csv`;
            link.click();
            URL.revokeObjectURL(link.href);
        } catch (e) {
            this.showToast('Export failed', this.reduceError(e), 'error');
        } finally {
            this.isExporting = false;
        }
    }

    loadView() {
        if (this.showTeamGrid) {
            this.loadTeamGrid();
        } else {
            this.loadDetail();
        }
    }

    async loadDetail() {
        if (!this.selectedMonth || !this.selectedUserId) {
            return;
        }
        this.isLoading = true;
        this.errorMessage = null;
        try {
            const { year, month } = this.parseMonthValue(this.selectedMonth);
            this.detail = await getPaceDetail({ year, month, userId: this.selectedUserId });
        } catch (e) {
            this.errorMessage = this.reduceError(e);
            this.detail = null;
        } finally {
            this.isLoading = false;
        }
    }

    async loadTeamGrid() {
        if (!this.selectedMonth) {
            return;
        }
        this.isLoading = true;
        this.errorMessage = null;
        try {
            const { year, month } = this.parseMonthValue(this.selectedMonth);
            this.teamGrid = await getPaceTeamGrid({
                year,
                month,
                page: this.teamPage,
                pageSize: TEAM_PAGE_SIZE,
                filters: {
                    paceStatus: this.teamFilterStatus,
                    company: this.teamFilterCompany,
                    businessSegment: this.teamFilterSegment
                }
            });
        } catch (e) {
            this.errorMessage = this.reduceError(e);
            this.teamGrid = null;
        } finally {
            this.isLoading = false;
        }
    }

    parseMonthValue(monthValue) {
        const [year, month] = (monthValue || '').split('-').map((v) => parseInt(v, 10));
        return { year, month };
    }

    formatPercent(value) {
        if (value == null || Number.isNaN(Number(value))) {
            return '0%';
        }
        return `${Math.round(Number(value))}%`;
    }

    reduceError(error) {
        if (Array.isArray(error?.body)) {
            return error.body.map((e) => e.message).join(', ');
        }
        return error?.body?.message || error?.message || 'Unknown error';
    }

    showToast(title, message, variant) {
        this.dispatchEvent(new ShowToastEvent({ title, message, variant }));
    }
}
