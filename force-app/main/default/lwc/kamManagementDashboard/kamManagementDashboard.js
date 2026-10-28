import { LightningElement, track, wire } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { NavigationMixin } from 'lightning/navigation';
import getDashboardData from '@salesforce/apex/KamManagementController.getDashboardData';
import getFilterOptions from '@salesforce/apex/KamManagementController.getFilterOptions';

function pctNumber(value) {
    return Math.round(Number(value || 0));
}

function pctDisplay(value) {
    return `${pctNumber(value)}%`;
}

function statusTone(status) {
    const normalized = (status || '').toLowerCase();
    if (normalized.includes('strong') || normalized.includes('track') || normalized.includes('complete')) {
        return 'on-track';
    }
    if (normalized.includes('progress') || normalized.includes('risk')) {
        return 'at-risk';
    }
    return 'behind';
}

const BUCKET_FILTER = {
    'On track': 'Strong coverage',
    'At risk': 'In progress',
    Behind: 'In progress'
};

export default class KamManagementDashboard extends NavigationMixin(LightningElement) {
    @track dashboardData;
    @track isLoading = true;
    @track planStatus = 'All';
    @track filterOptions;

    connectedCallback() {
        this.refreshDashboard();
    }

    @wire(getFilterOptions)
    wiredFilterOptions({ data, error }) {
        if (data) {
            this.filterOptions = data;
        } else if (error) {
            this.toast('Filter error', this.reduceError(error), 'error');
        }
    }

    get planStatusOptions() {
        return this.filterOptions?.planStatuses || [{ label: 'All', value: 'All' }];
    }

    get portfolio() {
        return this.dashboardData?.portfolio || {};
    }

    get hasPortfolio() {
        return (this.portfolio.accountsTracked || 0) > 0;
    }

    get executiveKpis() {
        const p = this.portfolio;
        return [
            {
                id: 'execution',
                label: 'KAM plan execution',
                value: pctDisplay(p.planExecutionPercent),
                hint: `${p.accountsOnTrack || 0} of ${p.accountsTracked || 0} accounts on track`,
                filterValue: 'Strong coverage',
                scrollTarget: 'accounts-section'
            },
            {
                id: 'coverage',
                label: 'Stakeholder coverage',
                value: pctDisplay(p.stakeholderCoveragePercent),
                hint: `${p.totalStakeholderLinks || 0} stakeholders · ${p.accountsWithStakeholders || 0} accounts mapped`,
                filterValue: 'All',
                scrollTarget: 'stakeholders-section'
            },
            {
                id: 'objectives',
                label: 'Objectives achieved',
                value: pctDisplay(p.objectiveCompletionRate),
                hint: `${p.completedObjectives || 0} of ${p.totalObjectives || 0} objectives`,
                filterValue: 'All',
                scrollTarget: 'objectives-section'
            },
            {
                id: 'visits',
                label: 'Upcoming visits',
                value: String(p.upcomingVisitsCount || 0),
                hint: 'Next 30 days on key accounts',
                filterValue: null,
                scrollTarget: 'activities-section'
            }
        ];
    }

    get donutStyle() {
        const buckets = this.dashboardData?.planBuckets || [];
        const onTrack = buckets.find((b) => b.bucket === 'On track')?.percent || 0;
        const atRisk = buckets.find((b) => b.bucket === 'At risk')?.percent || 0;
        const behind = buckets.find((b) => b.bucket === 'Behind')?.percent || 0;
        const p1 = pctNumber(onTrack);
        const p2 = p1 + pctNumber(atRisk);
        return `background: conic-gradient(
            #2e844a 0% ${p1}%,
            #fe9339 ${p1}% ${p2}%,
            #c23934 ${p2}% 100%
        );`;
    }

    get donutCenterLabel() {
        return String(this.portfolio.accountsTracked || 0);
    }

    get planLegend() {
        return (this.dashboardData?.planBuckets || []).map((bucket) => ({
            ...bucket,
            key: bucket.bucket,
            percentLabel: pctDisplay(bucket.percent),
            legendClass: `legend-dot legend-dot--${bucket.bucket.replace(/\s/g, '-').toLowerCase()}`
        }));
    }

    get stakeholderBars() {
        const max = Math.max(
            1,
            ...(this.dashboardData?.stakeholderRoles || []).map((row) => row.count || 0)
        );
        return (this.dashboardData?.stakeholderRoles || []).map((row) => ({
            ...row,
            key: row.roleLabel,
            barStyle: `width: ${Math.round(((row.count || 0) / max) * 100)}%;`
        }));
    }

    get objectiveBars() {
        return (this.dashboardData?.objectiveStates || []).map((row) => ({
            ...row,
            key: row.stateLabel,
            percentLabel: pctDisplay(row.percent),
            barStyle: `width: ${Math.max(pctNumber(row.percent), 2)}%;`,
            barClass: `objective-bar objective-bar--${row.stateLabel.replace(/\s/g, '-').toLowerCase()}`
        }));
    }

    get accountRows() {
        return (this.dashboardData?.topAccounts || []).map((row) => ({
            ...row,
            key: row.accountId,
            objectiveDisplay: pctDisplay(row.objectivePercent),
            statusClass: `row-status row-status--${statusTone(row.planStatus)}`
        }));
    }

    get activityRows() {
        return (this.dashboardData?.recentActivities || []).map((row) => ({
            ...row,
            key: row.visitId,
            dateLabel: row.visitDateLabel || '—'
        }));
    }

    get alertRows() {
        return (this.dashboardData?.alerts || []).map((row) => ({
            ...row,
            key: row.alertKey,
            icon: row.severity === 'warning' ? 'utility:warning' : 'utility:info',
            rowClass: `alert-row alert-row--${row.severity}`
        }));
    }

    get hasActivities() {
        return this.activityRows.length > 0;
    }

    get hasAlerts() {
        return this.alertRows.length > 0;
    }

    handlePlanStatusChange(event) {
        this.planStatus = event.detail.value;
        this.refreshDashboard();
    }

    handleResetFilters() {
        this.planStatus = 'All';
        this.refreshDashboard();
    }

    handleKpiClick(event) {
        const filterValue = event.currentTarget.dataset.filter;
        const scrollTarget = event.currentTarget.dataset.scroll;
        if (filterValue && filterValue !== 'All') {
            this.planStatus = filterValue;
            this.refreshDashboard().then(() => this.scrollToSection(scrollTarget));
            return;
        }
        this.scrollToSection(scrollTarget);
    }

    handleLegendClick(event) {
        const bucket = event.currentTarget.dataset.bucket;
        const filterValue = BUCKET_FILTER[bucket];
        if (filterValue) {
            this.planStatus = filterValue;
            this.refreshDashboard();
        }
    }

    handleAccountClick(event) {
        const accountId = event.currentTarget.dataset.accountId;
        this.navigateToRecord(accountId, 'Account');
    }

    handleVisitClick(event) {
        const visitId = event.currentTarget.dataset.visitId;
        this.navigateToRecord(visitId, 'Visit__c');
    }

    handleAlertClick(event) {
        const accountId = event.currentTarget.dataset.accountId;
        this.navigateToRecord(accountId, 'Account');
    }

    navigateToRecord(recordId, objectApiName) {
        if (!recordId) {
            return;
        }
        this[NavigationMixin.Navigate]({
            type: 'standard__recordPage',
            attributes: { recordId, objectApiName, actionName: 'view' }
        });
    }

    scrollToSection(sectionId) {
        if (!sectionId) {
            return;
        }
        const section = this.template.querySelector(`[data-section="${sectionId}"]`);
        section?.scrollIntoView({ behavior: 'smooth', block: 'start' });
    }

    async refreshDashboard() {
        this.isLoading = true;
        try {
            this.dashboardData = await getDashboardData({ planStatus: this.planStatus });
        } catch (error) {
            this.dashboardData = null;
            this.toast('Dashboard error', this.reduceError(error), 'error');
        } finally {
            this.isLoading = false;
        }
    }

    toast(title, message, variant) {
        this.dispatchEvent(new ShowToastEvent({ title, message, variant }));
    }

    reduceError(error) {
        return error?.body?.message || error?.message || 'Unknown error';
    }
}