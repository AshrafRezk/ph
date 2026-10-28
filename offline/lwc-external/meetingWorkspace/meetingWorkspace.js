import { LightningElement, api } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { notifyRecordUpdateAvailable } from 'lightning/uiRecordApi';
import getWorkspace from '@salesforce/apex/MeetingLifecycleController.getWorkspace';
import getOptions from '@salesforce/apex/MeetingLifecycleController.getOptions';
import saveMeeting from '@salesforce/apex/MeetingLifecycleController.saveMeeting';
import addServiceItem from '@salesforce/apex/MeetingLifecycleController.addServiceItem';
import removeServiceItem from '@salesforce/apex/MeetingLifecycleController.removeServiceItem';
import addAttendee from '@salesforce/apex/MeetingLifecycleController.addAttendee';
import removeAttendee from '@salesforce/apex/MeetingLifecycleController.removeAttendee';
import setAttendance from '@salesforce/apex/MeetingLifecycleController.setAttendance';
import searchPeople from '@salesforce/apex/MeetingLifecycleController.searchPeople';
import submitMeeting from '@salesforce/apex/MeetingLifecycleController.submitMeeting';
import approveMeeting from '@salesforce/apex/MeetingLifecycleController.approveMeeting';
import rejectMeeting from '@salesforce/apex/MeetingLifecycleController.rejectMeeting';
import markExecuted from '@salesforce/apex/MeetingLifecycleController.markExecuted';
import submitDeposit from '@salesforce/apex/MeetingLifecycleController.submitDeposit';
import submitActualCost from '@salesforce/apex/MeetingLifecycleController.submitActualCost';
import uploadInvoice from '@salesforce/apex/MeetingLifecycleController.uploadInvoice';
import recordPayment from '@salesforce/apex/MeetingLifecycleController.recordPayment';
import sendBackToBusiness from '@salesforce/apex/MeetingLifecycleController.sendBackToBusiness';
import closeMeeting from '@salesforce/apex/MeetingLifecycleController.closeMeeting';
import cancelMeeting from '@salesforce/apex/MeetingLifecycleController.cancelMeeting';
import inviteAttendees from '@salesforce/apex/MeetingLifecycleController.inviteAttendees';
import addGuestInvitation from '@salesforce/apex/MeetingLifecycleController.addGuestInvitation';
import markInvitationSent from '@salesforce/apex/MeetingLifecycleController.markInvitationSent';
import setInvitationActive from '@salesforce/apex/MeetingLifecycleController.setInvitationActive';
import sendInvitationEmail from '@salesforce/apex/MeetingLifecycleController.sendInvitationEmail';
import suggestPlan from '@salesforce/apex/MeetingPlanAssistant.suggest';
import {
    dateLabel,
    dateTimeLabel,
    errorMessage,
    fromLocalInput,
    initials,
    isQueued,
    money,
    pillClass,
    readFileAsBase64,
    relativeLabel,
    statusLabel,
    timeLabel,
    toLocalInput
} from 'c/meetingUtils';

const TRACK = [
    { key: 'plan', label: 'Plan' },
    { key: 'approval', label: 'Approval' },
    { key: 'run', label: 'Run' },
    { key: 'cost', label: 'Cost' },
    { key: 'accounting', label: 'Accounting' },
    { key: 'closed', label: 'Closed' }
];

const KIND_LABELS = { hcp: 'HCP', employee: 'Colleague', guest: 'Guest' };
const EMPTY_SERVICE = { serviceId: '', vendorId: '', description: '', quantity: 1, unitCost: '' };
// Fired by the field app when changes queued offline reach Salesforce.
const OFFLINE_SYNC_EVENT = 'zeta-meeting-outbox';

export default class MeetingWorkspace extends NavigationMixin(LightningElement) {
    @api embedded = false;
    @api defaultStart;
    @api defaultEnd;

    ws;
    options;
    loading = false;
    busy = false;
    loadError;
    tab = 'overview';
    editing = false;
    form = {};
    modal;
    modalText = '';
    moneyForm = {};
    moneyFile;
    personKind = 'hcp';
    personTerm = '';
    personResults = [];
    searching = false;
    guestName = '';
    serviceForm = { ...EMPTY_SERVICE };
    inviteName = '';
    invitePhone = '';
    inviteEmail = '';
    qrInvitation;
    emailInvitation;
    emailAddress = '';
    showScanner = false;
    suggestions;
    suggesting = false;
    suggestError;
    _meetingId;
    _recordId;
    _searchTimer;

    @api
    get recordId() {
        return this._recordId;
    }
    set recordId(value) {
        const changed = value !== this._recordId;
        this._recordId = value;
        if (changed && value && !this._meetingId && this._connected) {
            this.load();
        }
    }

    @api
    get meetingId() {
        return this._meetingId;
    }
    set meetingId(value) {
        const changed = value !== this._meetingId;
        this._meetingId = value;
        if (changed && this._connected) {
            this.reset();
            this.load();
        }
    }

    get currentId() {
        return this._meetingId || this._recordId;
    }

    connectedCallback() {
        this._connected = true;
        this._onOfflineSync = (event) => {
            if (event.detail && event.detail.synced && this.currentId) {
                this.load();
            }
        };
        window.addEventListener(OFFLINE_SYNC_EVENT, this._onOfflineSync);
        this.loadOptions();
        if (this.currentId) {
            this.load();
        } else {
            this.startCreate();
        }
    }

    disconnectedCallback() {
        this._connected = false;
        window.removeEventListener(OFFLINE_SYNC_EVENT, this._onOfflineSync);
        clearTimeout(this._searchTimer);
    }

    reset() {
        this.ws = null;
        this.tab = 'overview';
        this.editing = false;
        this.modal = null;
        this.personResults = [];
        this.personTerm = '';
        this.serviceForm = { ...EMPTY_SERVICE };
        this.suggestions = null;
        this.suggestError = null;
    }

    async loadOptions() {
        try {
            this.options = await getOptions();
        } catch (e) {
            this.options = { departments: [], activityTypes: [], types: [], services: [], vendors: [], brands: [] };
        }
    }

    async load() {
        if (!this.currentId) {
            return;
        }
        this.loading = !this.ws;
        this.loadError = null;
        try {
            const data = await getWorkspace({ meetingId: this.currentId });
            if (data) {
                this.ws = data;
                this.editing = false;
                if (!this.allowedKinds.includes(this.personKind)) {
                    this.personKind = this.allowedKinds[0];
                }
                if (!this.tabs.some((t) => t.key === this.tab)) {
                    this.tab = 'overview';
                }
            }
        } catch (e) {
            this.loadError = errorMessage(e);
        } finally {
            this.loading = false;
        }
    }

    // ---------------------------------------------------------------- derived view

    get isCreate() {
        return !this.currentId;
    }

    get showSpinner() {
        return this.loading && !this.ws;
    }

    get hasWorkspace() {
        return !!this.ws && !this.editing;
    }

    get m() {
        return this.ws ? this.ws.meeting : {};
    }

    get actions() {
        return (this.ws && this.ws.actions) || {};
    }

    get currency() {
        return (this.ws && this.ws.currencyCode) || (this.options && this.options.currencyCode) || 'EGP';
    }

    get statusPill() {
        return pillClass(this.m.status);
    }
    get statusText() {
        return statusLabel(this.m.status);
    }
    get approvalPill() {
        return pillClass(this.m.approvalStatus);
    }
    get paymentPill() {
        return pillClass(this.m.paymentStatus);
    }
    get showPaymentPill() {
        return this.m.paymentStatus && this.m.paymentStatus !== 'Not Started';
    }

    get whenText() {
        if (!this.m.startDateTime) {
            return 'No date set';
        }
        const sameDay = this.m.endDateTime && dateLabel(this.m.startDateTime) === dateLabel(this.m.endDateTime);
        return sameDay
            ? `${dateLabel(this.m.startDateTime)} · ${timeLabel(this.m.startDateTime)}–${timeLabel(this.m.endDateTime)}`
            : `${dateTimeLabel(this.m.startDateTime)} → ${dateTimeLabel(this.m.endDateTime)}`;
    }

    get isLegacy() {
        return this.ws && !this.m.lifecycle;
    }

    get isCancelled() {
        return this.m.status === 'Cancelled';
    }

    get track() {
        const index = this.trackIndex;
        return TRACK.map((step, i) => ({
            ...step,
            number: i + 1,
            cls: `track__step ${i < index ? 'track__step_done' : ''} ${i === index ? 'track__step_current' : ''}`
        }));
    }

    get trackIndex() {
        const m = this.m;
        if (m.status === 'Closed') return 5;
        if (m.status === 'Draft' || m.status === 'Rejected') return 0;
        if (m.approvalStatus === 'In Approval' && !m.actualCost) return 1;
        if (m.status === 'Approved') return 2;
        if (['In Accounting', 'Partial Paid', 'Paid'].includes(m.paymentStatus) && m.actualCost !== null && m.actualCost !== undefined) {
            return 4;
        }
        return 3;
    }

    get nextStepHint() {
        const m = this.m;
        const a = this.actions;
        if (this.isCancelled) return 'This meeting was cancelled.';
        if (a.canApprove) return 'Your decision is needed on this meeting.';
        if (m.status === 'Draft' && m.approvalStatus === 'Rejected') return 'Rejected. Update the plan and submit again.';
        if (m.status === 'Draft') return 'Add people and services, then submit for approval.';
        if (m.approvalStatus === 'In Approval') {
            return m.currentApproverName ? `Waiting on ${m.currentApproverName}.` : 'Waiting for approval.';
        }
        if (m.status === 'Approved') return 'Approved. Send invitations, run the meeting, then mark it as held.';
        if (m.paymentStatus === 'Returned to Business') return 'Returned. Fix the cost or invoice and send it again.';
        if (m.paymentStatus === 'In Accounting') return 'With accounting for payment.';
        if (m.paymentStatus === 'Partial Paid') return 'Partly paid. Accounting will pay the rest.';
        if (m.paymentStatus === 'Paid' && a.canClose) return 'Fully paid. You can close the meeting.';
        if (m.status === 'Concluded' && !m.actualCost) return 'Held. Enter the actual cost with the invoice.';
        return '';
    }

    /** Rules for this meeting's activity type, set by SFE in Admin Console > Meetings Setup. */
    get typeConfig() {
        return (this.ws && this.ws.typeConfig) || {};
    }

    get tabs() {
        const ws = this.ws || {};
        const labels = {
            overview: 'Overview',
            plan: 'Suggestions',
            people: 'People',
            cost: 'Services & cost',
            invites: 'Invitations',
            history: 'History',
            apm: 'HCP APM'
        };
        const counts = {
            people: (ws.members || []).length,
            cost: (ws.services || []).length,
            invites: (ws.invitations || []).length
        };
        let keys = this.typeConfig.workspaceTabs;
        if (!keys || !keys.length) {
            keys = ['overview', 'people', 'cost', 'history'];
            if (this.typeConfig.showSuggestions !== false && this.canSuggest) {
                keys.splice(1, 0, 'plan');
            }
            if (this.typeConfig.showInvitations !== false || (ws.invitations || []).length) {
                keys.splice(keys.indexOf('history'), 0, 'invites');
            }
            keys.push('apm');
        }
        const list = keys
            .filter((key) => {
                if (key === 'plan') {
                    return this.canSuggest && this.typeConfig.showSuggestions !== false;
                }
                if (key === 'invites') {
                    return this.typeConfig.showInvitations !== false || (ws.invitations || []).length;
                }
                return !!labels[key];
            })
            .map((key) => ({
                key,
                label: labels[key] || key,
                count: counts[key]
            }));
        return list.map((t) => ({ ...t, cls: `mx-tab ${t.key === this.tab ? 'mx-tab_active' : ''}`, hasCount: !!t.count }));
    }

    get isOverview() {
        return this.tab === 'overview';
    }
    get isPeople() {
        return this.tab === 'people';
    }
    get isCost() {
        return this.tab === 'cost';
    }
    get isInvites() {
        return this.tab === 'invites';
    }
    get isHistory() {
        return this.tab === 'history';
    }
    get isPlan() {
        return this.tab === 'plan' && this.canSuggest && this.typeConfig.showSuggestions !== false;
    }
    get isApm() {
        return this.tab === 'apm';
    }

    get hcpInvitees() {
        return ((this.ws && this.ws.members) || []).filter(
            (m) => m.accountId && (m.memberType === 'HCP' || m.recordType === 'HCP' || !m.isColleague)
        );
    }

    // ---- plan assistant
    get canSuggest() {
        return !!(this.actions.canEdit && this.m.status === 'Draft');
    }
    get suggestBasis() {
        return this.suggestions ? this.suggestions.basis : '';
    }
    get budgetHint() {
        const b = this.suggestions && this.suggestions.budget;
        if (!b) {
            return null;
        }
        const tone = { above: 'mx-banner_bad', below: 'mx-banner_warn', within: 'mx-banner_ok' }[b.verdict] || 'mx-banner_info';
        return {
            cls: `mx-banner ${tone} budget`,
            message: b.message,
            perGuest: `${money(b.perAttendeeLow, this.currency)} to ${money(b.perAttendeeHigh, this.currency)} per guest, typically ${money(b.perAttendeeTypical, this.currency)}`
        };
    }
    get suggestedInvitees() {
        return ((this.suggestions && this.suggestions.invitees) || []).map((s) => ({
            ...s,
            key: s.accountId,
            initials: initials(s.name),
            detail: [s.specialty, s.tier ? `Tier ${s.tier}` : null].filter(Boolean).join(' · '),
            scoreCls: `mx-pill ${s.score >= 60 ? 'mx-pill_ok' : s.score >= 35 ? 'mx-pill_info' : 'mx-pill_neutral'}`
        }));
    }
    get hasSuggestedInvitees() {
        return this.suggestedInvitees.length > 0;
    }
    get suggestedServices() {
        return ((this.suggestions && this.suggestions.services) || []).map((s) => ({
            ...s,
            key: s.serviceId,
            line: `${s.quantity} × ${money(s.unitCost, this.currency)}${s.vendorName ? ' · ' + s.vendorName : ''}`,
            total: money(s.amount, this.currency)
        }));
    }
    get hasSuggestedServices() {
        return this.suggestedServices.length > 0;
    }
    get topInviteeLabel() {
        return `Add top ${Math.min(5, this.suggestedInvitees.length)}`;
    }

    // ---- approval path
    get steps() {
        return ((this.ws && this.ws.steps) || []).map((s) => ({
            ...s,
            key: s.id,
            initials: initials(s.approverName || s.role),
            pill: pillClass(s.status),
            dotCls: `path__dot path__dot_${(s.status || 'Waiting').toLowerCase()}`,
            when: s.decidedAt ? dateTimeLabel(s.decidedAt) : '',
            who: s.approverName || 'No approver found'
        }));
    }
    get hasSteps() {
        return this.steps.length > 0;
    }
    get hasEarlierSteps() {
        return ((this.ws && this.ws.earlierSteps) || []).length > 0;
    }
    get earlierRoundsText() {
        const rounds = new Set(((this.ws && this.ws.earlierSteps) || []).map((s) => s.round));
        return `${rounds.size} earlier approval round${rounds.size === 1 ? '' : 's'} in history`;
    }

    // ---- money
    get costRows() {
        const m = this.m;
        const c = this.currency;
        const rows = [
            { key: 'planned', label: 'Planned', value: money(m.plannedCost || 0, c) },
            { key: 'approved', label: 'Approved', value: money(m.approvedPlannedCost, c) },
            { key: 'deposit', label: 'Deposit', value: money(m.depositAmount, c) },
            { key: 'actual', label: 'Actual', value: money(m.actualCost, c), note: this.actualNote },
            { key: 'paid', label: 'Paid', value: money(m.paidAmount || 0, c) },
            { key: 'remaining', label: 'Remaining', value: money(m.remainingAmount || 0, c), strong: true }
        ];
        return rows.map((r) => ({ ...r, cls: r.strong ? 'cost__value cost__value_strong' : 'cost__value' }));
    }

    get remainingText() {
        return money(this.m.remainingAmount || 0, this.currency);
    }

    get actualNote() {
        const pct = this.ws && this.ws.actualIncreasePct;
        if (pct === null || pct === undefined) {
            return null;
        }
        const sign = pct > 0 ? '+' : '';
        return `${sign}${pct}% vs plan`;
    }

    get paidPct() {
        const m = this.m;
        const due = m.actualCost !== null && m.actualCost !== undefined ? m.actualCost : m.depositAmount;
        if (!due) {
            return 0;
        }
        return Math.max(0, Math.min(100, Math.round(((m.paidAmount || 0) / due) * 100)));
    }

    get paidBarStyle() {
        return `width:${this.paidPct}%`;
    }

    get hasAccountingNotes() {
        return !!(this.ws && this.ws.accountingNotes);
    }

    // ---- people
    get members() {
        return ((this.ws && this.ws.members) || []).map((p) => ({
            ...p,
            key: p.id,
            initials: initials(p.name),
            kindLabel: KIND_LABELS[p.kind] || 'Guest',
            avatarCls: `mx-avatar ${p.kind === 'hcp' ? 'mx-avatar_hcp' : ''} ${p.kind === 'guest' ? 'mx-avatar_guest' : ''}`,
            statusPill: pillClass(p.status),
            attendancePill: pillClass(p.attendance),
            attended: p.attendance === 'Attended',
            missed: p.attendance === 'Did Not Attend',
            attendedCls: `mx-btn mx-btn_small ${p.attendance === 'Attended' ? 'mx-btn_ok' : ''}`,
            missedCls: `mx-btn mx-btn_small ${p.attendance === 'Did Not Attend' ? 'mx-btn_danger' : ''}`
        }));
    }
    get hasMembers() {
        return this.members.length > 0;
    }
    get hcpCount() {
        return this.members.filter((p) => p.kind === 'hcp').length;
    }
    get attendedCount() {
        return this.members.filter((p) => p.attended).length;
    }
    get allowedKinds() {
        const c = this.typeConfig;
        const kinds = [];
        if (c.allowHcps !== false) kinds.push('hcp');
        if (c.allowColleagues !== false) kinds.push('employee');
        if (c.allowGuests !== false) kinds.push('guest');
        return kinds.length ? kinds : ['employee'];
    }
    get personKinds() {
        return this.allowedKinds.map((value) => ({
            value,
            label: KIND_LABELS[value],
            cls: `mx-chip ${value === this.personKind ? 'mx-chip_active' : ''}`
        }));
    }
    get showKindChips() {
        return this.allowedKinds.length > 1;
    }
    get peopleEmptyText() {
        const parts = [];
        const c = this.typeConfig;
        if (c.allowHcps !== false) parts.push(c.requireTargetHcps ? 'HCPs from your target list' : 'HCPs');
        if (c.allowColleagues !== false) parts.push('colleagues');
        if (c.allowGuests !== false) parts.push('walk-in guests');
        return `Add ${parts.join(', ').replace(/, ([^,]*)$/, ' or $1')}.`;
    }
    get peopleSubtitle() {
        const ws = this.ws || {};
        const base = `${this.members.length} on the list · ${this.attendedCount} attended`;
        if (this.typeConfig.minAttendancePct === null || this.typeConfig.minAttendancePct === undefined) {
            return base;
        }
        const pct = ws.attendancePct === null || ws.attendancePct === undefined ? 0 : ws.attendancePct;
        return `${base} · ${pct}% attendance (target ${this.typeConfig.minAttendancePct}%)`;
    }
    get attendanceBanner() {
        const c = this.typeConfig;
        const ws = this.ws || {};
        if (c.minAttendancePct === null || c.minAttendancePct === undefined || !this.members.length) {
            return null;
        }
        const unmarked = this.members.length - (ws.attendanceMarked || 0);
        if (unmarked > 0) {
            return { cls: 'mx-banner mx-banner_info', text: `Mark attendance for everyone before you mark the session as held (${unmarked} left).` };
        }
        const below = (ws.attendancePct || 0) < c.minAttendancePct;
        return {
            cls: `mx-banner ${below ? 'mx-banner_warn' : 'mx-banner_ok'}`,
            text: below
                ? `Attendance is ${ws.attendancePct}%, below the ${c.minAttendancePct}% target.`
                : `Attendance is ${ws.attendancePct}%, on target.`
        };
    }
    get isGuestKind() {
        return this.personKind === 'guest';
    }
    get personPlaceholder() {
        if (this.personKind === 'employee') return 'Search colleagues by name';
        return this.ws && this.ws.requiresHcp ? 'Search your target-list HCPs' : 'Search HCPs by name';
    }
    get hasPersonResults() {
        return this.personResults.length > 0;
    }
    get noMatchText() {
        if (this.personKind === 'hcp' && this.typeConfig.requireTargetHcps) {
            return 'No matches. HCPs must be on your call-plan target list for this month.';
        }
        return 'No matches.';
    }
    get showHcpGlance() {
        return this.typeConfig.allowHcps !== false || this.hcpCount > 0;
    }
    get showInviteGlance() {
        return this.typeConfig.showInvitations !== false;
    }
    get showNoPersonResults() {
        return !this.searching && this.personTerm && this.personTerm.length >= 2 && !this.personResults.length;
    }

    // ---- services
    get services() {
        return ((this.ws && this.ws.services) || []).map((s) => ({
            ...s,
            key: s.id,
            unitText: money(s.unitCost, this.currency),
            amountText: money(s.amount, this.currency)
        }));
    }
    get hasServices() {
        return this.services.length > 0;
    }
    get plannedTotal() {
        return money(this.m.plannedCost || 0, this.currency);
    }
    get serviceOptions() {
        const dept = this.ws ? this.m.department : this.form.department;
        return ((this.options && this.options.services) || [])
            .filter((o) => !o.detail || o.detail === 'All' || !dept || o.detail === dept)
            .map((o) => ({ ...o, selected: o.value === this.serviceForm.serviceId }));
    }
    get vendorOptions() {
        return ((this.options && this.options.vendors) || []).map((o) => ({
            ...o,
            text: o.detail ? `${o.label} · ${o.detail}` : o.label,
            selected: o.value === this.serviceForm.vendorId
        }));
    }
    get noServiceCatalog() {
        return this.options && (!this.options.services || this.options.services.length === 0);
    }
    get serviceLineTotal() {
        const total = Number(this.serviceForm.quantity || 0) * Number(this.serviceForm.unitCost || 0);
        return money(total, this.currency);
    }

    get files() {
        return ((this.ws && this.ws.files) || []).map((f) => ({
            ...f,
            key: f.documentId,
            label: f.extension ? `${f.title}.${f.extension}` : f.title,
            sizeText: f.size ? `${Math.max(1, Math.round(f.size / 1024))} KB` : '',
            when: dateLabel(f.createdDate)
        }));
    }
    get hasFiles() {
        return this.files.length > 0;
    }
    get payments() {
        return ((this.ws && this.ws.payments) || []).map((p) => ({
            ...p,
            key: p.id,
            amountText: money(p.amount, this.currency),
            when: dateLabel(p.paidOn)
        }));
    }
    get hasPayments() {
        return this.payments.length > 0;
    }

    // ---- invitations
    get invitations() {
        return ((this.ws && this.ws.invitations) || []).map((i) => ({
            ...i,
            key: i.id,
            initials: initials(i.guestName),
            pill: pillClass(i.status),
            scansText: i.scans ? `Link opened ${i.scans === 1 ? 'once' : i.scans + ' times'}` : 'Not opened',
            sentText: i.sentAt ? `Sent ${relativeLabel(i.sentAt)}` : '',
            arrivedText: i.checkedInAt ? `Arrived ${arrivalLabel(i.checkedInAt, this.m.startDateTime)}` : '',
            arrivedTitle: i.checkedInAt ? `Scanned at the door ${dateTimeLabel(i.checkedInAt)}` : '',
            inactive: i.active === false,
            synced: i.pending !== true,
            rowCls: `mx-list__item ${i.active === false ? 'invite_inactive' : ''}`,
            toggleLabel: i.active === false ? 'Turn on' : 'Turn off'
        }));
    }
    get hasInvitations() {
        return this.invitations.length > 0;
    }
    get confirmedCount() {
        return this.invitations.filter((i) => i.status === 'Confirmed' || i.status === 'Checked In').length;
    }
    get checkedInCount() {
        return this.invitations.filter((i) => i.status === 'Checked In').length;
    }
    get activeInviteCount() {
        return this.invitations.filter((i) => i.active !== false).length;
    }
    get siteMissing() {
        return this.ws && !this.ws.siteReady;
    }

    // ---- history
    get history() {
        return ((this.ws && this.ws.history) || []).map((h) => ({
            ...h,
            key: h.id,
            title: this.historyTitle(h),
            when: dateTimeLabel(h.changedAt)
        }));
    }
    get hasHistory() {
        return this.history.length > 0;
    }

    historyTitle(h) {
        const labels = {
            create: 'Created',
            submit: 'Submitted for approval',
            'approve-step': 'Step approved',
            approve: 'Fully approved',
            reject: 'Rejected',
            execute: 'Marked as held',
            deposit: 'Deposit requested',
            'actual-cost': 'Actual cost entered',
            'actual-cost-reapproval': 'Re-approval needed',
            payment: 'Payment recorded',
            'send-back': 'Sent back by accounting',
            close: 'Closed',
            cancel: 'Cancelled'
        };
        return labels[h.action] || statusLabel(h.toStatus) || h.action;
    }

    // ---- form
    get formType() {
        return ((this.options && this.options.types) || []).find((t) => t.activityType === this.form.activityType);
    }
    get departmentOptions() {
        const all = (this.options && this.options.departments) || [];
        const allowed = this.formType && this.formType.departments && this.formType.departments.length ? this.formType.departments : null;
        return all
            .filter((o) => !allowed || allowed.includes(o.value))
            .map((o) => ({ ...o, selected: o.value === this.form.department }));
    }
    get formTypeDescription() {
        return this.formType ? this.formType.description : '';
    }
    get noTypesAvailable() {
        return !!this.options && !((this.options.activityTypes || []).length);
    }
    get activityOptions() {
        const list = [...((this.options && this.options.activityTypes) || [])];
        if (this.form.activityType && !list.some((o) => o.value === this.form.activityType)) {
            list.push({ label: this.form.activityType, value: this.form.activityType });
        }
        return list.map((o) => ({
            ...o,
            selected: o.value === this.form.activityType
        }));
    }
    get brandOptions() {
        return ((this.options && this.options.brands) || []).map((o) => ({ ...o, selected: o.value === this.form.brandId }));
    }
    get formTitle() {
        return this.isCreate ? 'New meeting' : 'Edit meeting';
    }
    get hcpTypeHint() {
        const t = this.formType;
        if (!t) {
            return '';
        }
        const notes = [];
        if (t.requireTargetHcps) notes.push('needs HCPs from your call-plan target list before you submit');
        else if (t.minHcps > 0) notes.push(`needs at least ${t.minHcps} HCP${t.minHcps === 1 ? '' : 's'}`);
        if (t.allowHcps === false) notes.push('is for employees only');
        if (t.requireBrand) notes.push('needs a brand');
        if (t.minAttendancePct !== null && t.minAttendancePct !== undefined) notes.push(`tracks attendance (target ${t.minAttendancePct}%)`);
        return notes.length ? `${t.label} ${notes.join(', ')}.` : '';
    }

    // ---- modal
    get isModal() {
        return !!this.modal;
    }
    get modalTitle() {
        return {
            approve: 'Approve meeting',
            reject: 'Reject meeting',
            cancel: 'Cancel meeting',
            deposit: 'Request a deposit',
            actual: 'Enter the actual cost',
            pay: 'Record a payment',
            sendback: 'Send back to the requester',
            qr: 'Invitation link QR',
            email: 'Email the invitation'
        }[this.modal];
    }
    get isEmailModal() {
        return this.modal === 'email';
    }
    get emailGuestName() {
        return this.emailInvitation ? this.emailInvitation.guestName : 'The guest';
    }
    get isTextModal() {
        return ['approve', 'reject', 'cancel', 'sendback'].includes(this.modal);
    }
    get modalTextLabel() {
        return {
            approve: 'Comment (optional)',
            reject: 'Why are you rejecting it?',
            cancel: 'Why is it cancelled?',
            sendback: 'What should the requester fix?'
        }[this.modal];
    }
    get isMoneyModal() {
        return ['deposit', 'actual', 'pay'].includes(this.modal);
    }
    get isFileModal() {
        return this.modal === 'deposit' || this.modal === 'actual';
    }
    get isPayModal() {
        return this.modal === 'pay';
    }
    get isActualModal() {
        return this.modal === 'actual';
    }
    get isQrModal() {
        return this.modal === 'qr';
    }
    get actualPreview() {
        if (this.modal !== 'actual' || !this.moneyForm.amount) {
            return null;
        }
        const base = this.m.approvedPlannedCost || this.m.plannedCost || 0;
        const amount = Number(this.moneyForm.amount);
        const pct = base > 0 ? ((amount - base) / base) * 100 : amount > 0 ? 100 : 0;
        const threshold = (this.ws && this.ws.thresholdPct) || 10;
        const over = pct >= threshold;
        return {
            cls: `mx-banner ${over ? 'mx-banner_warn' : 'mx-banner_ok'}`,
            text: over
                ? `${pct.toFixed(1)}% over the approved plan. This goes back through approval before accounting.`
                : `${pct.toFixed(1)}% against the approved plan. This goes straight to accounting.`
        };
    }
    get hasExistingInvoice() {
        return this.hasFiles;
    }
    get fileHint() {
        if (this.moneyFile) {
            return this.moneyFile.fileName;
        }
        if (this.hasExistingInvoice) {
            return 'An invoice is already attached. Add another if needed.';
        }
        return this.invoiceRequired ? 'Attach the invoice (PDF or photo). It is required.' : 'Attach the invoice (PDF or photo) if you have one.';
    }
    get invoiceRequired() {
        return this.typeConfig.requireInvoice !== false;
    }
    get invoiceNote() {
        return this.invoiceRequired
            ? 'Deposit and actual cost need an invoice before they go to accounting.'
            : 'Invoices are optional for this meeting type.';
    }
    get modalConfirmLabel() {
        return {
            approve: 'Approve',
            reject: 'Reject',
            cancel: 'Cancel meeting',
            deposit: 'Send to accounting',
            actual: 'Submit cost',
            pay: 'Record payment',
            sendback: 'Send back',
            email: 'Send email'
        }[this.modal];
    }
    get modalConfirmCls() {
        return ['reject', 'cancel', 'sendback'].includes(this.modal) ? 'mx-btn mx-btn_danger' : 'mx-btn mx-btn_primary';
    }
    get qrLink() {
        return this.qrInvitation ? this.qrInvitation.link : '';
    }
    get qrCaption() {
        return this.qrInvitation ? this.qrInvitation.guestName : '';
    }
    get qrFileName() {
        return this.qrInvitation ? `Invitation - ${this.qrInvitation.guestName}` : 'invitation';
    }

    // ---------------------------------------------------------------- handlers: navigation

    handleTab(event) {
        this.tab = event.currentTarget.dataset.key;
        if (this.tab === 'plan' && !this.suggestions && !this.suggesting) {
            this.loadSuggestions();
        }
    }

    // ---------------------------------------------------------------- handlers: plan assistant

    async loadSuggestions() {
        this.suggesting = true;
        this.suggestError = null;
        try {
            this.suggestions = await suggestPlan({ meetingId: this.currentId });
        } catch (e) {
            this.suggestError = errorMessage(e);
        } finally {
            this.suggesting = false;
        }
    }

    handleRefreshSuggestions() {
        this.loadSuggestions();
    }

    async handleSuggestInvitee(event) {
        const ids = [event.currentTarget.dataset.id];
        await this.addSuggestedInvitees(ids, 'Added to the meeting');
    }

    async handleSuggestTopInvitees() {
        const ids = this.suggestedInvitees.slice(0, 5).map((s) => s.accountId);
        await this.addSuggestedInvitees(ids, `${ids.length} HCPs added`);
    }

    async addSuggestedInvitees(ids, successMessage) {
        await this.run(async () => {
            for (const recordId of ids) {
                // eslint-disable-next-line no-await-in-loop
                await addAttendee({ meetingId: this.currentId, kind: 'hcp', recordId, writeInName: null });
                this.suggestions = {
                    ...this.suggestions,
                    invitees: this.suggestions.invitees.filter((s) => s.accountId !== recordId)
                };
            }
            await this.load();
            return true;
        }, successMessage);
    }

    async handleSuggestService(event) {
        const service = this.suggestedServices.find((s) => s.serviceId === event.currentTarget.dataset.id);
        if (!service) {
            return;
        }
        await this.run(async () => {
            await addServiceItem({
                meetingId: this.currentId,
                serviceId: service.serviceId,
                vendorId: service.vendorId || null,
                description: null,
                quantity: Number(service.quantity || 1),
                unitCost: Number(service.unitCost || 0)
            });
            await this.load();
            await this.loadSuggestions();
            return true;
        }, `${service.serviceName} added`);
    }

    handleBack() {
        if (this.embedded) {
            this.dispatchEvent(new CustomEvent('close'));
            return;
        }
        this[NavigationMixin.Navigate]({ type: 'standard__navItemPage', attributes: { apiName: 'Meetings_Home' } });
    }

    handleRefresh() {
        this.load();
    }

    // ---------------------------------------------------------------- handlers: edit

    startCreate() {
        let start = this.defaultStart ? new Date(this.defaultStart) : null;
        if (!start || Number.isNaN(start.getTime())) {
            start = new Date();
            start.setDate(start.getDate() + 7);
            start.setHours(18, 0, 0, 0);
        }
        const requestedEnd = this.defaultEnd ? new Date(this.defaultEnd) : null;
        const end =
            requestedEnd && requestedEnd > start ? requestedEnd : new Date(start.getTime() + 3 * 3600000);
        this.form = {
            title: '',
            department: '',
            activityType: '',
            start: toLocalInput(start),
            end: toLocalInput(end),
            venue: '',
            brandId: '',
            agenda: '',
            estimatedParticipants: ''
        };
        this.editing = true;
    }

    handleEdit() {
        const m = this.m;
        this.form = {
            title: this.ws.objectives || m.title,
            department: m.department || '',
            activityType: m.activityType || '',
            start: toLocalInput(m.startDateTime),
            end: toLocalInput(m.endDateTime),
            venue: m.venue || '',
            brandId: this.ws.brandId || '',
            agenda: this.ws.agenda || '',
            estimatedParticipants: this.ws.estimatedParticipants || ''
        };
        this.editing = true;
    }

    handleFormInput(event) {
        const field = event.target.dataset.field;
        this.form = { ...this.form, [field]: event.target.value };
        if (field === 'activityType') {
            const allowed = this.departmentOptions.map((o) => o.value);
            if (!allowed.includes(this.form.department)) {
                this.form = { ...this.form, department: allowed.length === 1 ? allowed[0] : '' };
            }
        }
    }

    handleCancelEdit() {
        if (this.isCreate) {
            this.dispatchEvent(new CustomEvent('close'));
            return;
        }
        this.editing = false;
    }

    async handleSave() {
        const f = this.form;
        if (!f.title || !f.department || !f.activityType || !f.start || !f.end) {
            this.toast('Missing details', 'Add the title, department, activity type, start, and end.', 'warning');
            return;
        }
        const payload = {
            id: this.currentId || null,
            title: f.title,
            department: f.department,
            activityType: f.activityType,
            startDateTime: fromLocalInput(f.start),
            endDateTime: fromLocalInput(f.end),
            venue: f.venue,
            brandId: f.brandId || null,
            agenda: f.agenda,
            estimatedParticipants: f.estimatedParticipants ? Number(f.estimatedParticipants) : null
        };
        await this.run(async () => {
            const id = await saveMeeting({ payload: JSON.stringify(payload) });
            if (this.isCreate) {
                this._meetingId = id;
                this.tab = 'people';
                this.dispatchEvent(new CustomEvent('created', { detail: { meetingId: id } }));
            }
            this.editing = false;
            await this.load();
            return true;
        }, 'Meeting saved');
    }

    // ---------------------------------------------------------------- handlers: people

    handlePersonKind(event) {
        this.personKind = event.currentTarget.dataset.value;
        this.personResults = [];
        this.personTerm = '';
    }

    handlePersonSearch(event) {
        this.personTerm = event.target.value;
        clearTimeout(this._searchTimer);
        if (!this.personTerm || this.personTerm.length < 2) {
            this.personResults = [];
            return;
        }
        // eslint-disable-next-line @lwc/lwc/no-async-operation
        this._searchTimer = setTimeout(() => this.runPersonSearch(), 300);
    }

    async runPersonSearch() {
        this.searching = true;
        try {
            const rows = await searchPeople({ meetingId: this.currentId, kind: this.personKind, term: this.personTerm });
            const existing = new Set(((this.ws && this.ws.members) || []).map((p) => p.recordId));
            this.personResults = (rows || []).filter((r) => !existing.has(r.id)).map((r) => ({ ...r, key: r.id, initials: initials(r.name) }));
        } catch (e) {
            this.personResults = [];
            this.toast('Search failed', errorMessage(e), 'error');
        } finally {
            this.searching = false;
        }
    }

    async handleAddPerson(event) {
        const recordId = event.currentTarget.dataset.id;
        await this.run(async () => {
            await addAttendee({ meetingId: this.currentId, kind: this.personKind, recordId, writeInName: null });
            this.personResults = this.personResults.filter((r) => r.id !== recordId);
            await this.load();
            return true;
        }, 'Added to the meeting');
    }

    handleGuestName(event) {
        this.guestName = event.target.value;
    }

    async handleAddGuest() {
        if (!this.guestName) {
            return;
        }
        await this.run(async () => {
            await addAttendee({ meetingId: this.currentId, kind: 'guest', recordId: null, writeInName: this.guestName });
            this.guestName = '';
            await this.load();
            return true;
        }, 'Guest added');
    }

    async handleRemovePerson(event) {
        const memberId = event.currentTarget.dataset.id;
        await this.run(async () => {
            await removeAttendee({ memberId });
            await this.load();
            return true;
        }, 'Removed');
    }

    async handleAttendance(event) {
        const memberId = event.currentTarget.dataset.id;
        const attendance = event.currentTarget.dataset.value;
        await this.run(async () => {
            const result = await setAttendance({ memberId, attendance });
            if (isQueued(result)) {
                this.patchMember(memberId, { attendance });
                return 'queued';
            }
            await this.load();
            return true;
        }, attendance === 'Attended' ? 'Marked as attended' : 'Marked as absent');
    }

    patchMember(memberId, patch) {
        const members = (this.ws.members || []).map((p) => (p.id === memberId ? { ...p, ...patch } : p));
        this.ws = { ...this.ws, members };
    }

    // ---------------------------------------------------------------- handlers: services

    handleServiceInput(event) {
        const field = event.target.dataset.field;
        const next = { ...this.serviceForm, [field]: event.target.value };
        if (field === 'serviceId') {
            const option = ((this.options && this.options.services) || []).find((o) => o.value === event.target.value);
            next.unitCost = option && option.amount !== null && option.amount !== undefined ? option.amount : '';
        }
        this.serviceForm = next;
    }

    async handleAddService() {
        const s = this.serviceForm;
        if (!s.serviceId || s.unitCost === undefined || s.unitCost === '') {
            this.toast('Missing details', 'Choose a service and enter the unit cost.', 'warning');
            return;
        }
        await this.run(async () => {
            await addServiceItem({
                meetingId: this.currentId,
                serviceId: s.serviceId,
                vendorId: s.vendorId || null,
                description: s.description || null,
                quantity: Number(s.quantity || 1),
                unitCost: Number(s.unitCost)
            });
            this.resetServiceForm();
            await this.load();
            return true;
        }, 'Service added');
    }

    resetServiceForm() {
        this.serviceForm = { ...EMPTY_SERVICE };
        this.template.querySelectorAll('.service-form [data-field]').forEach((el) => {
            el.value = EMPTY_SERVICE[el.dataset.field];
        });
    }

    async handleRemoveService(event) {
        const itemId = event.currentTarget.dataset.id;
        await this.run(async () => {
            await removeServiceItem({ itemId });
            await this.load();
            return true;
        }, 'Service removed');
    }

    async handleInvoiceUpload(event) {
        const file = event.target.files && event.target.files[0];
        event.target.value = '';
        if (!file) {
            return;
        }
        await this.run(async () => {
            const encoded = await readFileAsBase64(file);
            this.ws = await uploadInvoice({ meetingId: this.currentId, fileName: encoded.fileName, base64Data: encoded.base64 });
            return true;
        }, 'Invoice uploaded');
    }

    // ---------------------------------------------------------------- handlers: invitations

    async handleInviteAll() {
        await this.run(async () => {
            this.ws = await inviteAttendees({ meetingId: this.currentId });
            return true;
        }, 'Invitations ready');
    }

    handleInviteInput(event) {
        this[event.target.dataset.field] = event.target.value;
    }

    async handleAddInvite() {
        if (!this.inviteName) {
            this.toast('Missing name', 'Enter the guest name.', 'warning');
            return;
        }
        await this.run(async () => {
            this.ws = await addGuestInvitation({
                meetingId: this.currentId,
                guestName: this.inviteName,
                phone: this.invitePhone,
                email: this.inviteEmail
            });
            this.inviteName = '';
            this.invitePhone = '';
            this.inviteEmail = '';
            return true;
        }, 'Invitation added');
    }

    async handleWhatsApp(event) {
        const invitationId = event.currentTarget.dataset.id;
        const invitation = (this.ws.invitations || []).find((i) => i.id === invitationId);
        if (!invitation) {
            return;
        }
        let url = invitation.whatsappUrl;
        try {
            const row = await markInvitationSent({ invitationId, phone: null });
            if (row && row.whatsappUrl) {
                url = row.whatsappUrl;
                const invitations = this.ws.invitations.map((i) => (i.id === invitationId ? row : i));
                this.ws = { ...this.ws, invitations };
            }
        } catch (e) {
            // The link still works when the status update cannot be saved.
        }
        if (url) {
            window.open(url, '_blank');
        }
    }

    async handleCopyLink(event) {
        const link = event.currentTarget.dataset.link;
        try {
            await navigator.clipboard.writeText(link);
            this.toast('Link copied', '', 'success');
        } catch (e) {
            this.toast('Copy failed', link, 'warning');
        }
    }

    handleShowQr(event) {
        const invitationId = event.currentTarget.dataset.id;
        this.qrInvitation = (this.ws.invitations || []).find((i) => i.id === invitationId);
        this.modal = 'qr';
    }

    handleEmailInvite(event) {
        const invitationId = event.currentTarget.dataset.id;
        this.emailInvitation = (this.ws.invitations || []).find((i) => i.id === invitationId);
        this.emailAddress = (this.emailInvitation && this.emailInvitation.email) || '';
        this.modal = 'email';
    }

    handleEmailAddress(event) {
        this.emailAddress = event.target.value;
    }

    async sendEmailInvite() {
        const email = (this.emailAddress || '').trim();
        if (!/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email)) {
            this.toast('Check the email', 'Enter a valid email address.', 'warning');
            return;
        }
        const invitationId = this.emailInvitation.id;
        const ok = await this.run(async () => {
            const row = await sendInvitationEmail({ invitationId, email });
            const invitations = this.ws.invitations.map((i) => (i.id === invitationId ? row : i));
            this.ws = { ...this.ws, invitations };
            return true;
        }, `Invitation emailed to ${email}`);
        if (ok) {
            this.closeModal();
        }
    }

    handleOpenScanner() {
        this.showScanner = true;
    }

    async handleScannerClose(event) {
        this.showScanner = false;
        if (event.detail && event.detail.changed) {
            await this.load();
            this.dispatchEvent(new CustomEvent('changed', { detail: { meetingId: this.currentId } }));
        }
    }

    async handleToggleInvite(event) {
        const invitationId = event.currentTarget.dataset.id;
        const invitation = (this.ws.invitations || []).find((i) => i.id === invitationId);
        await this.run(async () => {
            this.ws = await setInvitationActive({ invitationId, active: invitation.active === false });
            return true;
        }, invitation.active === false ? 'Invitation turned on' : 'Invitation turned off');
    }

    // ---------------------------------------------------------------- handlers: lifecycle

    async handleSubmit() {
        await this.lifecycle(() => submitMeeting({ meetingId: this.currentId }), 'Submitted for approval');
    }

    async handleExecute() {
        await this.lifecycle(() => markExecuted({ meetingId: this.currentId }), 'Marked as held');
    }

    async handleClose() {
        await this.lifecycle(() => closeMeeting({ meetingId: this.currentId }), 'Meeting closed');
    }

    openModal(event) {
        this.modal = event.currentTarget.dataset.modal;
        this.modalText = '';
        this.moneyFile = null;
        const m = this.m;
        if (this.modal === 'pay') {
            this.moneyForm = { amount: m.remainingAmount || '', paidOn: new Date().toISOString().slice(0, 10), reference: '' };
        } else if (this.modal === 'actual') {
            this.moneyForm = { amount: m.actualCost || '' };
        } else {
            this.moneyForm = { amount: '' };
        }
    }

    closeModal() {
        this.modal = null;
        this.qrInvitation = null;
        this.emailInvitation = null;
    }

    stop(event) {
        event.stopPropagation();
    }

    handleModalText(event) {
        this.modalText = event.target.value;
    }

    handleMoneyInput(event) {
        this.moneyForm = { ...this.moneyForm, [event.target.dataset.field]: event.target.value };
    }

    async handleMoneyFile(event) {
        const file = event.target.files && event.target.files[0];
        if (!file) {
            this.moneyFile = null;
            return;
        }
        try {
            this.moneyFile = await readFileAsBase64(file);
        } catch (e) {
            event.target.value = '';
            this.moneyFile = null;
            this.toast('File too large', errorMessage(e), 'warning');
        }
    }

    async handleModalConfirm() {
        if (this.modal === 'email') {
            await this.sendEmailInvite();
            return;
        }
        const id = this.currentId;
        const text = this.modalText;
        const amount = this.moneyForm.amount === '' ? null : Number(this.moneyForm.amount);
        const file = this.moneyFile || {};
        const calls = {
            approve: [() => approveMeeting({ meetingId: id, comments: text }), 'Approved'],
            reject: [() => rejectMeeting({ meetingId: id, reason: text }), 'Rejected'],
            cancel: [() => cancelMeeting({ meetingId: id, reason: text }), 'Meeting cancelled'],
            sendback: [() => sendBackToBusiness({ meetingId: id, notes: text }), 'Sent back to the requester'],
            deposit: [
                () => submitDeposit({ meetingId: id, amount, fileName: file.fileName || null, base64Data: file.base64 || null }),
                'Deposit sent to accounting'
            ],
            actual: [
                () => submitActualCost({ meetingId: id, amount, fileName: file.fileName || null, base64Data: file.base64 || null }),
                'Actual cost submitted'
            ],
            pay: [
                () =>
                    recordPayment({
                        meetingId: id,
                        amount,
                        paidOn: this.moneyForm.paidOn || null,
                        reference: this.moneyForm.reference || null
                    }),
                'Payment recorded'
            ]
        };
        const entry = calls[this.modal];
        if (!entry) {
            return;
        }
        if (['reject', 'cancel', 'sendback'].includes(this.modal) && !text) {
            this.toast('Reason needed', this.modalTextLabel, 'warning');
            return;
        }
        if (this.isMoneyModal && (amount === null || Number.isNaN(amount))) {
            this.toast('Amount needed', 'Enter the amount.', 'warning');
            return;
        }
        const ok = await this.lifecycle(entry[0], entry[1]);
        if (ok) {
            this.closeModal();
        }
    }

    async lifecycle(call, successMessage) {
        return this.run(async () => {
            const result = await call();
            if (isQueued(result)) {
                return 'queued';
            }
            if (result && result.meeting) {
                this.ws = result;
            } else {
                await this.load();
            }
            if (this._recordId) {
                notifyRecordUpdateAvailable([{ recordId: this._recordId }]).catch(() => {});
            }
            return true;
        }, successMessage);
    }

    async run(work, successMessage) {
        if (this.busy) {
            return false;
        }
        this.busy = true;
        try {
            const outcome = await work();
            if (outcome === 'queued') {
                this.toast('Saved on this device', 'It will be sent to Salesforce when you are back online.', 'info');
            } else if (successMessage) {
                this.toast(successMessage, '', 'success');
            }
            this.dispatchEvent(new CustomEvent('changed', { detail: { meetingId: this.currentId } }));
            return true;
        } catch (e) {
            this.toast('Could not complete', errorMessage(e), 'error');
            return false;
        } finally {
            this.busy = false;
        }
    }

    toast(title, message, variant) {
        this.dispatchEvent(new ShowToastEvent({ title, message, variant }));
    }
}

function arrivalLabel(arrivedAt, meetingStart) {
    return meetingStart && dateLabel(arrivedAt) === dateLabel(meetingStart) ? timeLabel(arrivedAt) : dateTimeLabel(arrivedAt);
}