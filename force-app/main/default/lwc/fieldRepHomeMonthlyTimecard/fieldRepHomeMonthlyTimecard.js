import { LightningElement, api, track } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';
import getMonthlyLeaveDetails from '@salesforce/apex/FieldRepHomeController.getMonthlyLeaveDetails';
import getMonthlyTimecardDetails from '@salesforce/apex/FieldRepHomeController.getMonthlyTimecardDetails';
import getMonthlyTimecardSummary from '@salesforce/apex/FieldRepHomeController.getMonthlyTimecardSummary';
import { registerOfflineListener } from 'c/clmOfflineSync';

function tile(id, label, value, help) {
    return {
        id,
        label,
        value: value ?? 0,
        help,
        ariaLabel: `View ${label} details`
    };
}

export default class FieldRepHomeMonthlyTimecard extends NavigationMixin(LightningElement) {
    @track isLoading = true;
    @track summary = {};
    @track showLeaveModal = false;
    @track leaveDetailsLoading = false;
    @track leaveDetails = null;
    @track showDetailModal = false;
    @track detailLoading = false;
    @track detail = null;

    _visibilityHandler;
    _unsubscribeOffline;

    connectedCallback() {
        this._visibilityHandler = () => {
            if (typeof document !== 'undefined' && document.visibilityState === 'visible') {
                void this.loadSummary();
            }
        };
        if (typeof document !== 'undefined') {
            document.addEventListener('visibilitychange', this._visibilityHandler);
        }
        this._unsubscribeOffline = registerOfflineListener((status) => {
            if (status?.phase === 'idle' && status?.synced > 0) {
                void this.loadSummary();
            }
            if (status?.phase === 'queued') {
                void this.loadSummary();
            }
        });
        void this.loadSummary();
    }

    disconnectedCallback() {
        if (typeof document !== 'undefined' && this._visibilityHandler) {
            document.removeEventListener('visibilitychange', this._visibilityHandler);
        }
        if (typeof this._unsubscribeOffline === 'function') {
            this._unsubscribeOffline();
        }
    }

    @api
    async refresh() {
        await this.loadSummary();
    }

    async loadSummary() {
        this.isLoading = true;
        try {
            const data = await getMonthlyTimecardSummary({ contextUserId: null });
            this.summary = {
                ...data,
                tiles: this.buildTiles(data)
            };
        } catch (e) {
            this.summary = { tiles: [] };
        } finally {
            this.isLoading = false;
        }
    }

    buildTiles(data) {
        const tiles = [
            tile(
                'field',
                'Field days',
                data?.fieldDays,
                'Org working weekdays this month, minus company public holidays and approved leave. Click for the day list.'
            ),
            tile(
                'coached',
                'Coached',
                data?.coachedDays,
                'Days this month where you received coaching events. Click to open those events.'
            ),
            tile(
                'activities',
                'Activities recorded',
                data?.activityDays,
                'Days with at least one completed field visit this month. Click for the day list.'
            ),
            tile(
                'completed',
                'Completed activities',
                data?.completedActivities ?? data?.submittedCalls,
                'Completed visits plus closed or concluded meetings this month. Click to open them.'
            ),
            tile(
                'potential',
                'Potential activities',
                data?.potentialActivities ?? data?.potentialVisits,
                'Planned visits and open meetings this month. Click to open them.'
            ),
            tile(
                'leaves',
                'Leaves',
                data?.leaveDays,
                'Approved and pending time-off days this month. Click to open each request.'
            )
        ];
        if (data?.isManager) {
            tiles.splice(
                2,
                0,
                tile(
                    'coaching',
                    'Coaching',
                    data?.coachingDays,
                    'Days you delivered coaching events to your team. Click to open those events.'
                )
            );
        }
        return tiles;
    }

    get hasTiles() {
        return (this.summary?.tiles || []).length > 0;
    }

    get monthLabel() {
        return this.summary?.monthLabel || 'This month';
    }

    get hasApprovedLeaves() {
        return (this.leaveDetails?.approvedRows || []).length > 0;
    }

    get hasPendingLeaves() {
        return (this.leaveDetails?.pendingRows || []).length > 0;
    }

    get hasLeaveRows() {
        return this.hasApprovedLeaves || this.hasPendingLeaves;
    }

    get approvedDaysLabel() {
        return `${this.leaveDetails?.approvedDays ?? 0} days`;
    }

    get pendingDaysLabel() {
        return `${this.leaveDetails?.pendingDays ?? 0} days`;
    }

    get leaveModalTitle() {
        return `Leave details — ${this.leaveDetails?.monthLabel || this.monthLabel}`;
    }

    get decoratedApprovedRows() {
        return this.decorateLeaveRows(this.leaveDetails?.approvedRows);
    }

    get decoratedPendingRows() {
        return this.decorateLeaveRows(this.leaveDetails?.pendingRows);
    }

    decorateLeaveRows(rows) {
        return (rows || []).map((row) => ({
            ...row,
            key: row.requestId,
            recordId: row.requestId,
            daysLabel: `${row.days ?? 0} day${Number(row.days) === 1 ? '' : 's'}`,
            rangeLabel: this.formatLeaveRange(row.startDateTime, row.endDateTime)
        }));
    }

    formatLeaveRange(start, end) {
        const startDate = start ? new Date(start) : null;
        const endDate = end ? new Date(end) : null;
        if (!startDate || Number.isNaN(startDate.getTime())) {
            return '—';
        }
        const startLabel = startDate.toLocaleDateString(undefined, {
            month: 'short',
            day: 'numeric'
        });
        if (!endDate || Number.isNaN(endDate.getTime())) {
            return startLabel;
        }
        const endLabel = endDate.toLocaleDateString(undefined, {
            month: 'short',
            day: 'numeric'
        });
        return startLabel === endLabel ? startLabel : `${startLabel} – ${endLabel}`;
    }

    get detailModalTitle() {
        const title = this.detail?.title || 'Details';
        const month = this.detail?.monthLabel || this.monthLabel;
        return `${title} — ${month}`;
    }

    get detailGroups() {
        return this.detail?.groups || [];
    }

    get hasDetailGroups() {
        return this.detailGroups.length > 0;
    }

    get detailEmptyMessage() {
        return this.detail?.emptyMessage || 'Nothing to show for this month.';
    }

    handleTileClick(event) {
        const tileId = event.currentTarget?.dataset?.tileId;
        if (!tileId) {
            return;
        }
        if (tileId === 'leaves') {
            void this.openLeaveModal();
            return;
        }
        void this.openDetailModal(tileId);
    }

    async openLeaveModal() {
        this.showLeaveModal = true;
        this.leaveDetailsLoading = true;
        this.leaveDetails = null;
        try {
            this.leaveDetails = await getMonthlyLeaveDetails({ contextUserId: null });
        } catch (e) {
            this.leaveDetails = {
                approvedDays: 0,
                pendingDays: 0,
                approvedRows: [],
                pendingRows: [],
                monthLabel: this.monthLabel
            };
        } finally {
            this.leaveDetailsLoading = false;
        }
    }

    handleCloseLeaveModal() {
        this.showLeaveModal = false;
    }

    async openDetailModal(tileId) {
        this.showDetailModal = true;
        this.detailLoading = true;
        this.detail = null;
        try {
            this.detail = await getMonthlyTimecardDetails({ contextUserId: null, tileId });
        } catch (e) {
            this.detail = {
                title: 'Details',
                monthLabel: this.monthLabel,
                emptyMessage: 'Details could not be loaded. Try again when you are online.',
                groups: []
            };
        } finally {
            this.detailLoading = false;
        }
    }

    handleCloseDetailModal() {
        this.showDetailModal = false;
    }

    handleOpenRecord(event) {
        event.stopPropagation();
        const recordId = event.currentTarget?.dataset?.recordId;
        const objectApiName = event.currentTarget?.dataset?.objectApiName;
        if (!recordId || !objectApiName) {
            return;
        }
        this.showDetailModal = false;
        this.showLeaveModal = false;
        this[NavigationMixin.Navigate]({
            type: 'standard__recordPage',
            attributes: {
                recordId,
                objectApiName,
                actionName: 'view'
            }
        });
    }

    handleModalContentClick(event) {
        event.stopPropagation();
    }
}