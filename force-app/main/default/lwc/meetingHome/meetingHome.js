import { LightningElement, api } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import getHome from '@salesforce/apex/MeetingLifecycleController.getHome';
import approveMeeting from '@salesforce/apex/MeetingLifecycleController.approveMeeting';
import rejectMeeting from '@salesforce/apex/MeetingLifecycleController.rejectMeeting';
import {
    STAGES,
    dayParts,
    errorMessage,
    isQueued,
    money,
    pillClass,
    relativeLabel,
    statusLabel,
    timeLabel
} from 'c/meetingUtils';

export default class MeetingHome extends LightningElement {
    @api defaultTab = 'mine';

    home;
    loading = true;
    error;
    tab;
    stage = 'all';
    term = '';
    openId;
    creating = false;
    decision;
    decisionText = '';
    busy = false;

    connectedCallback() {
        this.tab = this.defaultTab || 'mine';
        this.load();
    }

    @api
    openMeeting(meetingId) {
        this.creating = false;
        this.openId = meetingId || null;
    }

    @api
    async refresh() {
        await this.load();
        const desk = this.template.querySelector('c-meeting-accounting-queue');
        if (desk) {
            desk.refresh();
        }
    }

    async load() {
        this.error = null;
        try {
            this.home = await getHome();
        } catch (e) {
            this.error = errorMessage(e);
        } finally {
            this.loading = false;
        }
    }

    get currency() {
        return (this.home && this.home.currencyCode) || 'EGP';
    }

    get firstName() {
        const name = (this.home && this.home.userName) || '';
        return name.split(' ')[0];
    }

    get greeting() {
        const hour = new Date().getHours();
        const part = hour < 12 ? 'Good morning' : hour < 18 ? 'Good afternoon' : 'Good evening';
        return this.firstName ? `${part}, ${this.firstName}` : part;
    }

    get mine() {
        return (this.home && this.home.mine) || [];
    }

    get approvals() {
        return (this.home && this.home.approvals) || [];
    }

    get showSpinner() {
        return this.loading && !this.home;
    }

    get tabs() {
        const list = [
            { value: 'mine', label: 'My meetings', count: this.mine.length },
            { value: 'approvals', label: 'Approvals', count: this.approvals.length }
        ];
        if (this.home && this.home.isAccounting) {
            list.push({ value: 'accounting', label: 'Accounting', count: this.home.accountingCount || 0 });
        }
        return list.map((t) => ({
            ...t,
            cls: `mx-tab ${t.value === this.tab ? 'mx-tab_active' : ''}`,
            selected: String(t.value === this.tab),
            hasCount: t.count > 0
        }));
    }

    get isMine() {
        return this.tab === 'mine';
    }

    get isApprovals() {
        return this.tab === 'approvals';
    }

    get isAccounting() {
        return this.tab === 'accounting';
    }

    get stageKpis() {
        return STAGES.map((s) => {
            const count = s.value === 'all' ? this.mine.length : this.mine.filter((m) => m.stage === s.value).length;
            return {
                ...s,
                count,
                cls: `mx-kpi kpi-btn ${s.value === this.stage ? 'mx-kpi_active' : ''}`
            };
        });
    }

    decorate(m) {
        const day = dayParts(m.startDateTime);
        const cost = m.actualCost !== null && m.actualCost !== undefined ? m.actualCost : m.plannedCost;
        return {
            ...m,
            key: m.id,
            day: day.day,
            month: day.month,
            time: timeLabel(m.startDateTime),
            statusText: statusLabel(m.status),
            statusPill: pillClass(m.status),
            costText: money(cost, this.currency),
            costLabel: m.actualCost !== null && m.actualCost !== undefined ? 'Actual' : 'Planned',
            plannedText: money(m.plannedCost, this.currency),
            waitingText: m.waitingSince ? relativeLabel(m.waitingSince) : '',
            showApprover: m.stage === 'waiting' && !!m.currentApproverName,
            showPayment: !!m.paymentStatus && m.paymentStatus !== 'Not Started',
            paymentPill: pillClass(m.paymentStatus),
            people: m.attendeeCount || 0
        };
    }

    get visibleMine() {
        const term = (this.term || '').toLowerCase();
        return this.mine
            .filter((m) => this.stage === 'all' || m.stage === this.stage)
            .filter(
                (m) =>
                    !term ||
                    [m.title, m.name, m.venue, m.department, m.activityType, m.brandName].some(
                        (v) => v && v.toLowerCase().includes(term)
                    )
            )
            .map((m) => this.decorate(m));
    }

    get hasMine() {
        return this.visibleMine.length > 0;
    }

    get showMineEmpty() {
        return !this.loading && !this.hasMine;
    }

    get mineEmptyText() {
        return this.mine.length
            ? 'No meetings match this filter.'
            : 'Plan your first meeting. It goes to the right approvers for its department and cost.';
    }

    get approvalCards() {
        return this.approvals.map((m) => this.decorate(m));
    }

    get hasApprovals() {
        return this.approvalCards.length > 0;
    }

    get showApprovalsEmpty() {
        return !this.loading && !this.hasApprovals;
    }

    get isDrawerOpen() {
        return !!this.openId || this.creating;
    }

    get isApproveDecision() {
        return this.decision && this.decision.kind === 'approve';
    }

    get isDecisionOpen() {
        return !!this.decision;
    }

    get decisionTitle() {
        return this.isApproveDecision ? 'Approve meeting' : 'Reject meeting';
    }

    get decisionLabel() {
        return this.isApproveDecision ? 'Comments (optional)' : 'Reason';
    }

    get decisionButton() {
        return this.isApproveDecision ? 'Approve' : 'Reject';
    }

    get decisionButtonClass() {
        return this.isApproveDecision ? 'mx-btn mx-btn_ok' : 'mx-btn mx-btn_danger';
    }

    get decisionDisabled() {
        return this.busy || (!this.isApproveDecision && !(this.decisionText || '').trim());
    }

    handleTab(event) {
        this.tab = event.currentTarget.dataset.value;
    }

    handleStage(event) {
        this.stage = event.currentTarget.dataset.value;
    }

    handleSearch(event) {
        this.term = event.target.value;
    }

    handleOpen(event) {
        this.creating = false;
        this.openId = event.currentTarget.dataset.id;
    }

    handleNew() {
        this.openId = null;
        this.creating = true;
    }

    handleClose() {
        this.openId = null;
        this.creating = false;
        this.load();
    }

    handleCreated(event) {
        this.creating = false;
        this.openId = event.detail && event.detail.meetingId;
        this.load();
    }

    handleChanged() {
        this.load();
    }

    handleDecision(event) {
        const { id, kind } = event.currentTarget.dataset;
        const card = this.approvals.find((m) => m.id === id);
        this.decision = { id, kind, title: card ? card.title : '' };
        this.decisionText = '';
    }

    handleDecisionText(event) {
        this.decisionText = event.target.value;
    }

    closeDecision() {
        if (!this.busy) {
            this.decision = null;
        }
    }

    stop(event) {
        event.stopPropagation();
    }

    async confirmDecision() {
        const { id, kind } = this.decision;
        this.busy = true;
        try {
            const result =
                kind === 'approve'
                    ? await approveMeeting({ meetingId: id, comments: this.decisionText })
                    : await rejectMeeting({ meetingId: id, reason: this.decisionText });
            const queued = isQueued(result);
            this.toast(
                queued ? 'Saved offline' : kind === 'approve' ? 'Approved' : 'Rejected',
                queued ? 'Your decision syncs when you are back online.' : '',
                queued ? 'info' : 'success'
            );
            this.decision = null;
            await this.load();
        } catch (e) {
            this.toast('Could not save', errorMessage(e), 'error');
        } finally {
            this.busy = false;
        }
    }

    toast(title, message, variant) {
        this.dispatchEvent(new ShowToastEvent({ title, message, variant }));
    }
}
