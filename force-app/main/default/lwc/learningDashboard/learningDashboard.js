import { LightningElement, api, wire } from 'lwc';
import { refreshApex } from '@salesforce/apex';
import getMyLearningStats from '@salesforce/apex/MyLearningController.getMyLearningStats';

export default class LearningDashboard extends LightningElement {
    stats;
    errorMessage;
    wiredStatsResult;
    _refreshKey;

    @api
    get refreshKey() {
        return this._refreshKey;
    }

    set refreshKey(value) {
        if (value !== this._refreshKey && this.wiredStatsResult) {
            refreshApex(this.wiredStatsResult);
        }
        this._refreshKey = value;
    }

    @wire(getMyLearningStats)
    wiredStats(result) {
        this.wiredStatsResult = result;
        const { data, error } = result;
        if (data) {
            this.stats = data;
            this.errorMessage = null;
        } else if (error) {
            this.stats = null;
            this.errorMessage =
                error?.body?.message || error?.message || 'Unable to load dashboard.';
        }
    }

    get hasStats() {
        return !!this.stats;
    }

    get statTiles() {
        if (!this.stats) {
            return [];
        }
        const s = this.stats;
        const tiles = [
            {
                id: 'inProgress',
                label: 'In Progress',
                value: String(s.inProgressCount || 0),
                hint: 'Courses you have started',
                cardClass: 'stat-tile'
            },
            {
                id: 'notStarted',
                label: 'Not Started',
                value: String(s.notStartedCount || 0),
                hint: 'Assigned courses not yet begun',
                cardClass: 'stat-tile'
            },
            {
                id: 'completed',
                label: 'Completed',
                value: String(s.completedCount || 0),
                hint: 'Courses finished',
                cardClass: 'stat-tile'
            },
            {
                id: 'missed',
                label: 'Missed',
                value: String(s.missedCount || 0),
                hint: 'Expired before completion',
                cardClass:
                    (s.missedCount || 0) > 0
                        ? 'stat-tile stat-tile-missed'
                        : 'stat-tile'
            },
            {
                id: 'hoursStudied',
                label: 'Hours Studied',
                value: String(s.totalStudyHours ?? 0),
                sublabel: 'hrs',
                hint: 'Total time on curriculum items',
                cardClass: 'stat-tile'
            },
            {
                id: 'completionRate',
                label: 'Completion Rate',
                value: `${Math.round(s.completionRate || 0)}%`,
                hint: 'Share of assigned courses completed',
                cardClass: 'stat-tile'
            },
            {
                id: 'certificates',
                label: 'Certificates',
                value: String(s.certificatesEarned || 0),
                hint: 'Certificates earned',
                cardClass: 'stat-tile'
            }
        ];

        if (s.averageScore != null) {
            tiles.push({
                id: 'averageScore',
                label: 'Average Score',
                value: `${Math.round(s.averageScore)}%`,
                hint: 'Average score on completed courses',
                cardClass: 'stat-tile'
            });
        }

        tiles.push({
            id: 'dueSoon',
            label: 'Due Soon',
            value: String(s.dueSoonCount || 0),
            hint: 'Courses ending within 7 days',
            cardClass:
                (s.dueSoonCount || 0) > 0 ? 'stat-tile stat-tile-highlight' : 'stat-tile'
        });

        return tiles;
    }
}