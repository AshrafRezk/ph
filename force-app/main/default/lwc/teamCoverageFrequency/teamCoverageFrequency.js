import getTeamCoverageFrequencyForScope from '@salesforce/apex/TotTeamCoverageController.getTeamCoverageFrequencyForScope';
import { LightningElement, api, wire } from 'lwc';
import { refreshApex } from '@salesforce/apex';

function num(value, digits = 1) {
    if (value == null) {
        return '0';
    }
    return Number(value).toFixed(digits);
}

function pct(value) {
    if (value == null) {
        return '0%';
    }
    const n = Number(value);
    const asPct = n <= 1 ? n * 100 : n;
    return `${Math.round(asPct)}%`;
}

export default class TeamCoverageFrequency extends LightningElement {
    _buTerritoryId = 'ALL';
    _lineTerritoryId = 'ALL';
    _districtTerritoryId = 'ALL';

    wiredResult;
    summary;
    errorMessage;
    isLoading = true;

    @api
    get buTerritoryId() {
        return this._buTerritoryId;
    }
    set buTerritoryId(value) {
        this._buTerritoryId = value || 'ALL';
    }

    @api
    get lineTerritoryId() {
        return this._lineTerritoryId;
    }
    set lineTerritoryId(value) {
        this._lineTerritoryId = value || 'ALL';
    }

    @api
    get districtTerritoryId() {
        return this._districtTerritoryId;
    }
    set districtTerritoryId(value) {
        this._districtTerritoryId = value || 'ALL';
    }

    @wire(getTeamCoverageFrequencyForScope, {
        buTerritoryId: '$_buTerritoryId',
        lineTerritoryId: '$_lineTerritoryId',
        districtTerritoryId: '$_districtTerritoryId'
    })
    wiredCoverage(result) {
        this.wiredResult = result;
        this.isLoading = false;
        const { data, error } = result;
        if (data) {
            this.summary = data;
            this.errorMessage = undefined;
        } else if (error) {
            this.summary = undefined;
            this.errorMessage = error.body?.message || 'Failed to load Team Coverage & Frequency.';
        }
    }

    get hasSummary() {
        return Boolean(this.summary);
    }

    get periodLabel() {
        return this.summary?.periodLabel || '';
    }

    get availableDaysDisplay() {
        return num(this.summary?.availableWorkingDays);
    }

    get availableDaysHint() {
        return `${num(this.summary?.calendarWorkingDays)} calendar − ${num(this.summary?.totDays)} TOT`;
    }

    get coverageDisplay() {
        return pct(this.summary?.totAdjustedCoveragePercent);
    }

    get coverageHint() {
        return 'Visits ÷ (target adjusted for TOT)';
    }

    get frequencyImpacted() {
        return this.summary?.frequencyImpacted === true;
    }

    get frequencyLabel() {
        return this.summary?.frequencyImpactLabel || 'On track';
    }

    get frequencyBadgeClass() {
        return this.frequencyImpacted ? 'impact-badge impact-warn' : 'impact-badge impact-ok';
    }

    get repRows() {
        return (this.summary?.reps || []).map((row) => ({
            ...row,
            key: row.employeeId,
            availableDisplay: num(row.availableWorkingDays),
            totDisplay: num(row.totDays),
            coverageDisplay: pct(row.totAdjustedCoveragePercent),
            rowClass: row.longTermLeave ? 'rep-row long-leave' : 'rep-row'
        }));
    }

    get hasReps() {
        return this.repRows.length > 0;
    }

    get emptyMessage() {
        return 'No medical reps with time cards for this month in the selected scope.';
    }

    async handleRefresh() {
        this.isLoading = true;
        try {
            await refreshApex(this.wiredResult);
        } finally {
            this.isLoading = false;
        }
    }
}