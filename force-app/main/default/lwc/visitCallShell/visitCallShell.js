import { LightningElement, api, wire } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { refreshApex } from '@salesforce/apex';
import getCallReportPayload from '@salesforce/apex/VisitCallReportController.getCallReportPayload';
import saveCallReportJson from '@salesforce/apex/VisitCallReportController.saveCallReportJson';
import getWhatsAppSurveyContext from '@salesforce/apex/VisitSurveyLinkController.getWhatsAppSurveyContext';
import buildSurveyUrl from '@salesforce/apex/VisitSurveyLinkController.buildSurveyUrl';
import buildWhatsAppMessage from '@salesforce/apex/VisitSurveyLinkController.buildWhatsAppMessage';
import buildMeetingReminderMessage from '@salesforce/apex/VisitSurveyLinkController.buildMeetingReminderMessage';
import getMedicalInquiryCount from '@salesforce/apex/VisitMedicalInquiryController.getMedicalInquiryCount';
import { getVisitStatusOptions, validateVisitStatusChange } from 'c/visitStatusUtils';
import { getVisitPayload, putVisitPayload } from 'c/clmOfflineStore';
import { isOfflineMode, queueOfflineAction } from 'c/clmOfflineSync';
import { accountThemeFor, accountThemeStyle } from 'c/accountTypeTheme';
import { isFieldFeatureEnabled, loadFieldFeatures } from 'c/fieldFeatureFlags';
import getVisitTabs from '@salesforce/apex/VisitCallReportController.getVisitTabs';

const TAB_CATALOG = [
    { id: 'details', label: 'Details' },
    { id: 'affiliations', label: 'Affiliations' },
    { id: 'attendees', label: 'Attendees' },
    { id: 'products', label: 'Products' },
    { id: 'samples', label: 'Dispense' },
    { id: 'storeCheck', label: 'Store Check' },
    { id: 'order', label: 'Make an Order' },
    { id: 'presentations', label: 'Presentations' },
    { id: 'orders', label: 'Orders' },
    { id: 'requests', label: 'Requests' }
];

const STANDARD_TABS = [
    'details',
    'affiliations',
    'attendees',
    'products',
    'samples',
    'presentations',
    'orders',
    'requests'
];

const PHARMACY_TABS = ['details', 'storeCheck', 'order', 'presentations', 'orders', 'requests'];

function defaultVisitTabs(developerName, recordTypeName) {
    const pharmacy =
        developerName === 'Pharmacy' || (recordTypeName || '').toLowerCase() === 'pharmacy';
    return pharmacy ? PHARMACY_TABS : STANDARD_TABS;
}

const HCP_RECORD_TYPES = new Set(['SDO_PersonAccounts', 'Medical_Professional_HCP', 'PersonAccount', 'Business_Contact']);

function formatDateTime(value) {
    if (!value) {
        return '—';
    }
    return new Date(value).toLocaleString([], {
        weekday: 'short',
        month: 'short',
        day: 'numeric',
        hour: '2-digit',
        minute: '2-digit'
    });
}

function formatDate(value) {
    if (!value) {
        return '';
    }
    return new Date(value).toISOString().slice(0, 10);
}

function resolveTimeZone(timeZone) {
    try {
        // Throws RangeError for an unknown zone id.
        new Intl.DateTimeFormat('en-US', { timeZone });
        return timeZone;
    } catch (error) {
        return undefined;
    }
}

// Wall-clock parts of an instant in the visit's time zone (defaults to the device zone).
function zonedParts(value, timeZone) {
    const date = new Date(value);
    if (Number.isNaN(date.getTime())) {
        return null;
    }
    const parts = {};
    new Intl.DateTimeFormat('en-US', {
        timeZone: resolveTimeZone(timeZone),
        hourCycle: 'h23',
        year: 'numeric',
        month: '2-digit',
        day: '2-digit',
        hour: '2-digit',
        minute: '2-digit',
        second: '2-digit'
    })
        .formatToParts(date)
        .forEach((part) => {
            parts[part.type] = part.value;
        });
    return {
        date: `${parts.year}-${parts.month}-${parts.day}`,
        time: `${parts.hour === '24' ? '00' : parts.hour}:${parts.minute}`
    };
}

// Lightning/PWA time inputs return "HH:mm", "HH:mm:ss.SSS" or "HH:mm:ss.SSSZ".
function parseHourMinute(value) {
    const match = /^(\d{1,2}):(\d{2})/.exec(String(value || '').trim());
    if (!match) {
        return null;
    }
    const hours = Number(match[1]);
    const minutes = Number(match[2]);
    if (hours > 23 || minutes > 59) {
        return null;
    }
    return { hours, minutes };
}

// Builds a UTC ISO string from a calendar day plus a wall-clock time in `timeZone`.
function zonedWallTimeToIso(dateString, timeValue, timeZone) {
    const day = /^(\d{4})-(\d{2})-(\d{2})/.exec(String(dateString || ''));
    const clock = parseHourMinute(timeValue);
    if (!day || !clock) {
        return null;
    }
    const zone = resolveTimeZone(timeZone);
    const wallAsUtc = Date.UTC(
        Number(day[1]),
        Number(day[2]) - 1,
        Number(day[3]),
        clock.hours,
        clock.minutes
    );
    let instant = wallAsUtc;
    // Two passes settle the offset around DST changes.
    for (let pass = 0; pass < 2; pass += 1) {
        const shown = zonedParts(instant, zone);
        const shownClock = parseHourMinute(shown.time);
        const shownDay = /^(\d{4})-(\d{2})-(\d{2})/.exec(shown.date);
        const shownAsUtc = Date.UTC(
            Number(shownDay[1]),
            Number(shownDay[2]) - 1,
            Number(shownDay[3]),
            shownClock.hours,
            shownClock.minutes
        );
        instant += wallAsUtc - shownAsUtc;
    }
    return new Date(instant).toISOString();
}

function toTimeInputValue(hourMinute) {
    return hourMinute ? `${hourMinute}:00.000` : '';
}

export default class VisitCallShell extends NavigationMixin(LightningElement) {
    _recordId;

    @api
    get recordId() {
        return this._recordId;
    }
    set recordId(value) {
        const next = value || '';
        if (next === this._recordId) {
            return;
        }
        this._recordId = next;
        this.payload = undefined;
        this.usingCachedPayload = false;
        this.medicalInquiryCount = 0;
        this.serviceRequestCountLoaded = false;
        if (next) {
            this.loadCachedPayload();
        }
    }

    payload;
    wiredPayloadResult;
    isSaving = false;
    usingCachedPayload = false;
    activeSection = 'details';
    tabKeys = [...STANDARD_TABS];
    _tabToken = 0;

    statusValue = 'Draft';
    visitObjective = '';
    visitNotes = '';
    nextVisitDate = '';
    cancellationReason = '';
    didNotMeetHcp = false;
    metInsteadType = '';
    metInsteadName = '';
    attendees = [];
    products = [];
    samples = [];
    isDoubleVisitSelected = false;
    doubleVisitWithId = '';
    teamMembers = [];

    showWhatsAppModal = false;
    showCoachingModal = false;
    coachingEventId;
    medicalInquiryCount = 0;
    fieldRequestCount = 0;
    serviceRequestCountLoaded = false;
    fieldRequestsEnabled = true;
    // Visit day is read-only; only the time of day is editable (HH:mm).
    editStartTime = '';
    editEndTime = '';
    alignedOnRepTerritory = false;
    hasSubordinateTerritories = false;
    whatsappLoading = false;
    whatsappError;
    surveyContext;
    selectedPhoneKey;
    selectedProductName;
    whatsappMessagePreview = '';

    connectedCallback() {
        void loadFieldFeatures().then(() => {
            this.fieldRequestsEnabled = isFieldFeatureEnabled('requests.enabled');
        });
        if (isOfflineMode()) {
            this.loadCachedPayload();
        }
    }

    showReminderModal = false;
    reminderLoading = false;
    reminderError;
    reminderContext;
    selectedReminderPhoneKey;
    reminderMessagePreview = '';

    @wire(getCallReportPayload, { visitId: '$recordId' })
    wiredPayload(result) {
        this.wiredPayloadResult = result;
        if (result.data) {
            this.applyPayload(result.data);
            this.usingCachedPayload = false;
            putVisitPayload(this.recordId, result.data).catch(() => {
                // Best effort cache.
            });
        } else if (result.error || isOfflineMode()) {
            this.loadCachedPayload();
        }
    }

    get offlineHint() {
        return this.usingCachedPayload ? 'Showing cached visit data from device' : '';
    }

    async loadCachedPayload() {
        if (!this.recordId) {
            return;
        }
        try {
            const cached = await getVisitPayload(this.recordId);
            if (cached?.visit) {
                this.applyPayload(cached);
                this.usingCachedPayload = true;
                return;
            }
            if (isOfflineMode()) {
                const payload = await getCallReportPayload({ visitId: this.recordId });
                if (payload?.visit) {
                    this.applyPayload(payload);
                    this.usingCachedPayload = true;
                }
            }
        } catch (error) {
            this.usingCachedPayload = false;
        }
    }

    get isLoading() {
        if (this.usingCachedPayload) {
            return false;
        }
        return !this.wiredPayloadResult || this.wiredPayloadResult.loading;
    }

    get errorMessage() {
        return this.wiredPayloadResult?.error?.body?.message || this.wiredPayloadResult?.error?.message;
    }

    get visit() {
        return this.payload?.visit;
    }

    get visitAccountId() {
        return this.visit?.accountId || null;
    }

    get visitAccountName() {
        return this.visit?.accountName || '';
    }

    get isLocked() {
        return this.visit?.isLocked;
    }

    get statusOptions() {
        return getVisitStatusOptions(
            this.visit?.startDateTime,
            this.visit?.visitType,
            this.visit?.status || this.statusValue
        );
    }

    get showCancellationReason() {
        return this.statusValue === 'Cancelled';
    }

    get showUnplannedCompleteHint() {
        return (
            this.statusValue === 'Completed' &&
            this.visit?.status &&
            this.visit.status !== 'Scheduled' &&
            this.visit.status !== 'Completed'
        );
    }

    get showMetInsteadFields() {
        return this.didNotMeetHcp === true;
    }

    get metInsteadTypeOptions() {
        return [
            { label: 'Assistant', value: 'Assistant' },
            { label: 'Son/Daughter', value: 'Son/Daughter' },
            { label: 'Other', value: 'Other' }
        ];
    }

    get useFieldRequestsModule() {
        return this.fieldRequestsEnabled === true;
    }

    get requestSectionCount() {
        return this.useFieldRequestsModule ? this.fieldRequestCount : this.medicalInquiryCount;
    }

    get canEditSchedule() {
        return this.visit?.canEditSchedule === true && !this.isLocked;
    }

    get navSections() {
        const enabled = new Set(this.tabKeys || []);
        return TAB_CATALOG.filter((section) => enabled.has(section.id)).map((section) => {
            let label = section.label;
            if (section.id === 'requests' && this.requestSectionCount > 0) {
                label = `Requests (${this.requestSectionCount})`;
            }
            return {
                ...section,
                label,
                className:
                    section.id === this.activeSection ? 'nav-item nav-item-active' : 'nav-item'
            };
        });
    }

    hasTab(tabId) {
        return (this.tabKeys || []).includes(tabId);
    }

    get showAffiliationsTab() {
        return this.hasTab('affiliations');
    }

    get showAttendeesTab() {
        return this.hasTab('attendees');
    }

    get showProductsTab() {
        return this.hasTab('products');
    }

    get showSamplesTab() {
        return this.hasTab('samples');
    }

    get showPresentationsTab() {
        return this.hasTab('presentations');
    }

    get showOrdersTab() {
        return this.hasTab('orders');
    }

    get showOrderTab() {
        return this.hasTab('order');
    }

    get showRequestsTab() {
        return this.hasTab('requests');
    }

    get showStoreCheckTab() {
        return this.hasTab('storeCheck');
    }

    get isDetailsSection() {
        return this.activeSection === 'details';
    }

    get isAffiliationsSection() {
        return this.activeSection === 'affiliations';
    }

    get isAttendeesSection() {
        return this.activeSection === 'attendees';
    }

    get isProductsSection() {
        return this.activeSection === 'products';
    }

    get isSamplesSection() {
        return this.activeSection === 'samples';
    }

    get selectedBrandIds() {
        const ids = new Set();
        for (const row of this.products || []) {
            if (row.productType === 'Brand' && row.productId) {
                ids.add(row.productId);
            }
            if (row.parentProductId) {
                ids.add(row.parentProductId);
            }
            if (row.productId) {
                ids.add(row.productId);
            }
        }
        return [...ids];
    }

    get isPresentationsSection() {
        return this.activeSection === 'presentations';
    }

    get detailsPanelClass() {
        return this.activeSection === 'details' ? 'visit-panel' : 'visit-panel visit-section-hidden';
    }

    get affiliationsPanelClass() {
        return this.activeSection === 'affiliations'
            ? 'visit-panel visit-panel-affiliations'
            : 'visit-panel visit-panel-affiliations visit-section-hidden';
    }

    get attendeesPanelClass() {
        return this.activeSection === 'attendees' ? '' : 'visit-section-hidden';
    }

    get productsPanelClass() {
        return this.activeSection === 'products' ? '' : 'visit-section-hidden';
    }

    get samplesPanelClass() {
        return this.activeSection === 'samples' ? '' : 'visit-section-hidden';
    }

    get presentationsPanelClass() {
        return this.activeSection === 'presentations' ? '' : 'visit-section-hidden';
    }

    get ordersPanelClass() {
        return this.activeSection === 'orders' ? '' : 'visit-section-hidden';
    }

    get storeCheckPanelClass() {
        return this.activeSection === 'storeCheck' ? '' : 'visit-section-hidden';
    }

    get orderPanelClass() {
        return this.activeSection === 'order' ? '' : 'visit-section-hidden';
    }

    get isRequestsSection() {
        return this.activeSection === 'requests';
    }

    get requestsPanelClass() {
        return this.activeSection === 'requests' ? '' : 'visit-section-hidden';
    }

    get accountTheme() {
        return accountThemeFor(
            this.visit?.accountRecordTypeDeveloperName,
            this.visit?.accountRecordTypeName
        );
    }

    get themeStyle() {
        return accountThemeStyle(this.accountTheme);
    }

    get shellClass() {
        return `visit-call-shell theme-${this.accountTheme.kind}`;
    }

    get heroClass() {
        return 'visit-hero';
    }

    get accountTypeIconUrl() {
        return this.accountTheme.iconUrl;
    }

    get accountBadgeLabel() {
        return this.accountTheme.kind === 'account'
            ? this.visit?.accountRecordTypeName || 'Account'
            : this.accountTheme.label;
    }

    get accountBadgeClass() {
        return `account-badge account-badge-${this.accountTheme.kind}`;
    }

    get statusBadgeClass() {
        const status = this.visit?.status || 'Draft';
        return `status-badge status-badge-${(status || 'draft').toLowerCase()}`;
    }

    get isDoubleVisit() {
        return this.isDoubleVisitSelected === true;
    }

    get isSingleVisitSelected() {
        return this.isDoubleVisitSelected !== true;
    }

    get singleVisitSwitchClass() {
        return this.isSingleVisitSelected
            ? 'visit-type-switch-btn visit-type-switch-btn-active'
            : 'visit-type-switch-btn';
    }

    get doubleVisitSwitchClass() {
        return this.isDoubleVisitSelected
            ? 'visit-type-switch-btn visit-type-switch-btn-active'
            : 'visit-type-switch-btn';
    }

    get isSingleVisitPressed() {
        return this.isSingleVisitSelected ? 'true' : 'false';
    }

    get isDoubleVisitPressed() {
        return this.isDoubleVisitSelected ? 'true' : 'false';
    }

    get teamMemberOptions() {
        const options = (this.teamMembers || []).map((member) => ({
            label: this.formatTeamMemberLabel(member),
            value: member.userId
        }));
        if (
            this.doubleVisitWithId &&
            !options.some((option) => option.value === this.doubleVisitWithId)
        ) {
            const savedName = this.visit?.doubleVisitWithName;
            options.unshift({
                label: savedName || 'Selected team member',
                value: this.doubleVisitWithId
            });
        }
        return options;
    }

    get selectedTeamMemberName() {
        if (!this.doubleVisitWithId) {
            return this.visit?.doubleVisitWithName || '';
        }
        const selected = (this.teamMembers || []).find(
            (member) => member.userId === this.doubleVisitWithId
        );
        return selected?.name || this.visit?.doubleVisitWithName || '';
    }

    get hasLinkedCoachingEvent() {
        return !!(this.coachingEventId || this.visit?.coachingEventId);
    }

    get showCoachingButton() {
        return (
            this.hasLinkedCoachingEvent ||
            this.hasSubordinateTerritories === true ||
            this.alignedOnRepTerritory !== true
        );
    }

    get showWhatsAppActions() {
        return false;
    }

    get coachingButtonLabel() {
        return this.hasLinkedCoachingEvent ? 'Open Coaching Form' : 'Create Coaching Event';
    }

    get accountMetaLine() {
        return [this.visit?.accountSpecialty, this.visit?.accountCity].filter(Boolean).join(' · ');
    }

    get startLabel() {
        return formatDateTime(this.visit?.startDateTime);
    }

    get endLabel() {
        return formatDateTime(this.visit?.endDateTime);
    }

    handleOpenAccount() {
        if (!this.visit?.accountId) {
            return;
        }
        this[NavigationMixin.Navigate]({
            type: 'standard__recordPage',
            attributes: {
                recordId: this.visit.accountId,
                objectApiName: 'Account',
                actionName: 'view'
            }
        });
    }

    applyPayload(data) {
        this.payload = data;
        const visit = data.visit;
        this.statusValue = visit.status || 'Draft';
        this.visitObjective = visit.visitObjective || '';
        this.visitNotes = visit.visitNotes || '';
        this.nextVisitDate = formatDate(visit.nextVisitDate);
        this.cancellationReason = visit.cancellationReason || '';
        this.didNotMeetHcp = visit.didNotMeetHcp === true;
        this.metInsteadType = visit.metInsteadType || '';
        this.metInsteadName = visit.metInsteadName || '';
        this.attendees = data.attendees || [];
        this.products = data.products || [];
        this.samples = data.samples || [];
        this.teamMembers = data.teamMembers || [];
        this.coachingEventId = visit.coachingEventId;
        this.alignedOnRepTerritory = data.alignedOnRepTerritory === true;
        this.hasSubordinateTerritories = data.hasSubordinateTerritories === true;
        this.editStartTime = zonedParts(visit.startDateTime, visit.userTimeZone)?.time || '';
        this.editEndTime = zonedParts(visit.endDateTime, visit.userTimeZone)?.time || '';
        if (typeof data.medicalInquiryCount === 'number') {
            this.medicalInquiryCount = data.medicalInquiryCount;
            this.serviceRequestCountLoaded = true;
        } else if (visit.canViewServiceRequests === true && !this.serviceRequestCountLoaded) {
            this.serviceRequestCountLoaded = true;
            this.loadServiceRequestCount();
        }
        this.tabKeys =
            Array.isArray(data.tabKeys) && data.tabKeys.length
                ? data.tabKeys
                : defaultVisitTabs(
                      visit.accountRecordTypeDeveloperName,
                      visit.accountRecordTypeName
                  );
        if (!this.tabKeys.includes(this.activeSection)) {
            this.activeSection = 'details';
        }
        void this.loadVisitTabs(visit);
        this.isDoubleVisitSelected = visit.isDoubleVisit === true;
        this.doubleVisitWithId =
            visit.doubleVisitWithId ||
            (this.isDoubleVisitSelected ? visit.defaultDoubleVisitWithId || '' : '');
        this.openRequestedCoaching();
    }

    async loadVisitTabs(visit) {
        const token = (this._tabToken || 0) + 1;
        this._tabToken = token;
        const developerName = visit?.accountRecordTypeDeveloperName || '';
        const recordTypeName = visit?.accountRecordTypeName || '';
        try {
            const keys = await getVisitTabs({ developerName, recordTypeName });
            if (this._tabToken !== token || !Array.isArray(keys) || !keys.length) {
                return;
            }
            this.tabKeys = keys;
            if (!this.tabKeys.includes(this.activeSection)) {
                this.activeSection = 'details';
            }
        } catch (_error) {
            // Defaults already include Orders and Requests for this record type.
        }
    }

    openRequestedCoaching() {
        let pending = '';
        try {
            pending = sessionStorage.getItem('zeta.pwa.openVisitCoaching') || '';
        } catch (_error) {
            return;
        }
        if (!pending || pending !== this.recordId) {
            return;
        }
        try {
            sessionStorage.removeItem('zeta.pwa.openVisitCoaching');
        } catch (_error) {
            /* ignore */
        }
        this.showCoachingModal = true;
    }

    formatTeamMemberLabel(member) {
        if (!member) {
            return '';
        }
        const parts = [member.name];
        if (member.isDefault) {
            parts.push('Territory manager');
        } else if (member.role) {
            parts.push(member.role);
        }
        if (member.territoryName && !member.isDefault) {
            parts.push(member.territoryName);
        }
        return parts.filter(Boolean).join(' · ');
    }

    handleVisitTypeChange(event) {
        const visitType = event.currentTarget?.dataset?.visitType;
        if (this.isLocked || !visitType) {
            return;
        }
        this.isDoubleVisitSelected = visitType === 'double';
        if (this.isDoubleVisitSelected && !this.doubleVisitWithId) {
            this.doubleVisitWithId =
                this.visit?.defaultDoubleVisitWithId ||
                this.teamMembers.find((member) => member.isDefault || member.isManager)?.userId ||
                '';
        }
    }

    handleDoubleVisitWithChange(event) {
        this.doubleVisitWithId = event.detail.value;
    }

    handleCoachingAction() {
        this.showCoachingModal = true;
    }

    handleCloseCoachingModal() {
        this.showCoachingModal = false;
    }

    async handleCoachingCreated() {
        await refreshApex(this.wiredPayloadResult);
    }

    async handleCoachingSubmitted() {
        await refreshApex(this.wiredPayloadResult);
    }

    handleStartTimeChange(event) {
        this.editStartTime = event.detail.value;
    }

    handleEndTimeChange(event) {
        this.editEndTime = event.detail.value;
    }

    get editStartTimeValue() {
        return toTimeInputValue(this.normalizedTime(this.editStartTime));
    }

    get editEndTimeValue() {
        return toTimeInputValue(this.normalizedTime(this.editEndTime));
    }

    normalizedTime(value) {
        const clock = parseHourMinute(value);
        return clock ? `${String(clock.hours).padStart(2, '0')}:${String(clock.minutes).padStart(2, '0')}` : '';
    }

    // Calendar day of the visit in the user's time zone. Locked: never edited here.
    get visitDateKey() {
        return (
            this.visit?.visitDateLocal ||
            zonedParts(this.visit?.startDateTime, this.visit?.userTimeZone)?.date ||
            ''
        );
    }

    get visitDateLabel() {
        const key = this.visitDateKey;
        if (!key) {
            return '—';
        }
        const [year, month, day] = key.split('-').map(Number);
        return new Date(Date.UTC(year, month - 1, day)).toLocaleDateString([], {
            weekday: 'short',
            year: 'numeric',
            month: 'short',
            day: 'numeric',
            timeZone: 'UTC'
        });
    }

    // Start/end instants rebuilt from the locked visit day plus the edited times.
    buildScheduleFromTimes() {
        const day = this.visitDateKey;
        const zone = this.visit?.userTimeZone;
        const build = (editedTime, originalIso) => {
            const original = originalIso ? zonedParts(originalIso, zone) : null;
            // Untouched time keeps the stored instant (seconds included).
            if (original && original.time === this.normalizedTime(editedTime)) {
                return new Date(originalIso).toISOString();
            }
            return zonedWallTimeToIso(day, editedTime, zone);
        };
        return {
            start: build(this.editStartTime, this.visit?.startDateTime),
            end: build(this.editEndTime, this.visit?.endDateTime)
        };
    }

    async loadServiceRequestCount() {
        if (!this.recordId) {
            return;
        }
        try {
            const count = await getMedicalInquiryCount({ visitId: this.recordId });
            this.medicalInquiryCount = count || 0;
        } catch (error) {
            // Count stays at the last known value when the request cannot be loaded.
        }
    }

    handleMedicalInquiryCreated() {
        this.medicalInquiryCount += 1;
    }

    handleFieldRequestCountChange(event) {
        this.fieldRequestCount = event.detail?.count || 0;
    }

    handleNavClick(event) {
        event.preventDefault();
        const fromButton = event.currentTarget?.dataset?.section;
        const fromNested = event.target?.closest?.('[data-section]')?.dataset?.section;
        const section = fromButton || fromNested;
        if (section) {
            this.activeSection = section;
        }
    }

    handleStatusChange(event) {
        this.statusValue = event.detail.value;
        if (this.statusValue !== 'Cancelled') {
            this.cancellationReason = '';
        }
    }

    handleObjectiveChange(event) {
        this.visitObjective = event.detail.value;
    }

    handleNotesChange(event) {
        this.visitNotes = event.detail.value;
    }

    handleNextVisitChange(event) {
        this.nextVisitDate = event.detail.value;
    }

    handleCancellationChange(event) {
        this.cancellationReason = event.detail.value;
    }

    handleDidNotMeetHcpChange(event) {
        this.didNotMeetHcp = event.target.checked === true;
        if (!this.didNotMeetHcp) {
            this.metInsteadType = '';
            this.metInsteadName = '';
        }
    }

    handleMetInsteadTypeChange(event) {
        this.metInsteadType = event.detail.value;
    }

    handleMetInsteadNameChange(event) {
        this.metInsteadName = event.detail.value;
    }

    handleAttendeesChange(event) {
        this.attendees = event.detail.attendees;
    }

    handleProductsChange(event) {
        this.products = event.detail.products;
    }

    handleSamplesChange(event) {
        this.samples = event.detail.samples;
    }

    async handleSave() {
        const validationMessage = validateVisitStatusChange(
            this.statusValue,
            this.visit?.startDateTime,
            this.cancellationReason
        );
        if (validationMessage) {
            this.showToast('Validation', validationMessage, 'error');
            return;
        }
        if (this.didNotMeetHcp && !(this.metInsteadType || '').trim()) {
            this.showToast('Validation', 'Select who you met instead of the doctor.', 'error');
            return;
        }
        if (this.isDoubleVisitSelected && !this.doubleVisitWithId) {
            this.showToast('Validation', 'Select the team member who joined this double visit.', 'error');
            return;
        }
        let schedule = null;
        if (this.canEditSchedule) {
            schedule = this.buildScheduleFromTimes();
            if (!schedule.start || !schedule.end) {
                this.showToast('Validation', 'Start and end times are required.', 'error');
                return;
            }
            if (new Date(schedule.end) <= new Date(schedule.start)) {
                this.showToast('Validation', 'End time must be after start time.', 'error');
                return;
            }
        }
        this.isSaving = true;
        try {
            const saveRequest = {
                visitId: this.recordId || this.payload?.visit?.id,
                status: this.statusValue,
                visitObjective: this.visitObjective,
                visitNotes: this.visitNotes,
                clmPresentation: this.payload?.visit?.clmPresentation || null,
                nextVisitDate: this.nextVisitDate || null,
                cancellationReason: this.cancellationReason || null,
                didNotMeetHcp: this.didNotMeetHcp === true,
                metInsteadType: this.didNotMeetHcp ? this.metInsteadType || null : null,
                metInsteadName: this.didNotMeetHcp ? this.metInsteadName || null : null,
                isDoubleVisit: this.isDoubleVisitSelected === true,
                doubleVisitWithId: this.isDoubleVisitSelected ? this.doubleVisitWithId || null : null,
                attendees: this.attendees,
                products: this.products,
                samples: this.samples,
                clmSessions: []
            };
            if (schedule) {
                saveRequest.startDateTime = schedule.start;
                saveRequest.endDateTime = schedule.end;
            }
            // Offline saves sync later; the server uses this to accept a Completed
            // report captured on the visit day for up to 3 days after.
            saveRequest.capturedAt = new Date().toISOString();

            if (!saveRequest.visitId) {
                this.showToast('Save failed', 'Visit Id is required.', 'error');
                return;
            }

            if (isOfflineMode()) {
                const offlinePayload = {
                    visit: {
                        ...this.payload?.visit,
                        status: this.statusValue,
                        visitObjective: this.visitObjective,
                        visitNotes: this.visitNotes,
                        nextVisitDate: this.nextVisitDate || null,
                        cancellationReason: this.cancellationReason || null,
                        didNotMeetHcp: this.didNotMeetHcp === true,
                        metInsteadType: this.didNotMeetHcp ? this.metInsteadType || null : null,
                        metInsteadName: this.didNotMeetHcp ? this.metInsteadName || null : null,
                        isDoubleVisit: this.isDoubleVisitSelected === true,
                        doubleVisitWithId: this.isDoubleVisitSelected
                            ? this.doubleVisitWithId || null
                            : null,
                        doubleVisitWithName: this.selectedTeamMemberName,
                        defaultDoubleVisitWithId: this.visit?.defaultDoubleVisitWithId || null,
                        ...(schedule
                            ? {
                                  startDateTime: schedule.start,
                                  endDateTime: schedule.end
                              }
                            : {})
                    },
                    attendees: this.attendees,
                    products: this.products,
                    samples: this.samples,
                    teamMembers: this.teamMembers,
                    clmSessions: this.payload?.clmSessions || [],
                    alignedOnRepTerritory: this.alignedOnRepTerritory,
                    medicalInquiryCount: this.medicalInquiryCount
                };
                await putVisitPayload(this.recordId || saveRequest.visitId, offlinePayload);
                await queueOfflineAction({
                    actionType: 'SAVE_CALL_REPORT',
                    visitId: saveRequest.visitId,
                    clientActionKey: `save_call_${saveRequest.visitId}_${Date.now()}`,
                    callReportJson: JSON.stringify(saveRequest)
                });
                this.applyPayload(offlinePayload);
                this.showToast(
                    'Saved offline',
                    'Visit changes will sync when you are back online.',
                    'success'
                );
                return;
            }

            const saved = await saveCallReportJson({ requestJson: JSON.stringify(saveRequest) });
            this.applyPayload(saved);
            await putVisitPayload(saveRequest.visitId, saved);
            await refreshApex(this.wiredPayloadResult);
            this.showToast('Visit saved', saved.visit.accountName, 'success');
        } catch (error) {
            this.showToast('Save failed', this.reduceError(error), 'error');
        } finally {
            this.isSaving = false;
        }
    }

    get reminderPhoneOptions() {
        return (this.reminderContext?.phoneOptions || []).map((row) => ({
            label: row.label,
            value: row.key
        }));
    }

    get reminderSendDisabled() {
        return (
            this.reminderLoading ||
            !!this.reminderError ||
            !this.selectedReminderPhoneKey ||
            !this.reminderMessagePreview
        );
    }

    get phoneOptions() {
        return (this.surveyContext?.phoneOptions || []).map((row) => ({
            label: row.label,
            value: row.key
        }));
    }

    get productOptions() {
        return (this.surveyContext?.products || []).map((row) => ({
            label: row.productName,
            value: row.productName
        }));
    }

    get whatsappSendDisabled() {
        return (
            this.whatsappLoading ||
            !!this.whatsappError ||
            !this.selectedPhoneKey ||
            !this.selectedProductName
        );
    }

    async handleOpenWhatsAppModal() {
        this.showWhatsAppModal = true;
        this.whatsappLoading = true;
        this.whatsappError = undefined;
        try {
            this.surveyContext = await getWhatsAppSurveyContext({ visitId: this.recordId });
            if (!this.surveyContext?.phoneOptions?.length) {
                this.whatsappError = 'No phone numbers found on the account or attendees.';
            } else if (!this.surveyContext?.products?.length) {
                this.whatsappError = 'No territory products available for this visit.';
            } else {
                this.selectedPhoneKey = this.surveyContext.phoneOptions[0].key;
                this.selectedProductName = this.surveyContext.products[0].productName;
                await this.refreshWhatsAppPreview();
            }
        } catch (error) {
            this.whatsappError = this.reduceError(error);
        } finally {
            this.whatsappLoading = false;
        }
    }

    handleCloseWhatsAppModal() {
        this.showWhatsAppModal = false;
    }

    async handlePhoneChange(event) {
        this.selectedPhoneKey = event.detail.value;
        await this.refreshWhatsAppPreview();
    }

    async handleProductChange(event) {
        this.selectedProductName = event.detail.value;
        await this.refreshWhatsAppPreview();
    }

    async refreshWhatsAppPreview() {
        if (!this.selectedPhoneKey || !this.selectedProductName) {
            this.whatsappMessagePreview = '';
            return;
        }
        const phoneRow = (this.surveyContext?.phoneOptions || []).find(
            (row) => row.key === this.selectedPhoneKey
        );
        const surveyUrl = await buildSurveyUrl({
            visitId: this.recordId,
            productName: this.selectedProductName
        });
        this.whatsappMessagePreview = await buildWhatsAppMessage({
            firstName: phoneRow?.firstName,
            productName: this.selectedProductName,
            surveyUrl
        });
    }

    async handleSendWhatsApp() {
        const phoneRow = (this.surveyContext?.phoneOptions || []).find(
            (row) => row.key === this.selectedPhoneKey
        );
        if (!phoneRow?.phone) {
            this.showToast('WhatsApp', 'Select a valid phone number.', 'error');
            return;
        }
        const digits = phoneRow.phone.replace(/[^0-9]/g, '');
        if (!digits) {
            this.showToast('WhatsApp', 'Phone number is not valid for WhatsApp.', 'error');
            return;
        }
        if (!this.whatsappMessagePreview) {
            await this.refreshWhatsAppPreview();
        }
        const url = `https://wa.me/${digits}?text=${encodeURIComponent(this.whatsappMessagePreview)}`;
        window.open(url, '_blank');
        this.handleCloseWhatsAppModal();
        this.showToast('WhatsApp', 'Opening WhatsApp with the survey message.', 'success');
    }

    async handleOpenReminderModal() {
        this.showReminderModal = true;
        this.reminderLoading = true;
        this.reminderError = undefined;
        try {
            this.reminderContext = await getWhatsAppSurveyContext({ visitId: this.recordId });
            if (!this.reminderContext?.phoneOptions?.length) {
                this.reminderError = 'No phone numbers found on the account or attendees.';
            } else {
                this.selectedReminderPhoneKey = this.reminderContext.phoneOptions[0].key;
                await this.refreshReminderPreview();
            }
        } catch (error) {
            this.reminderError = this.reduceError(error);
        } finally {
            this.reminderLoading = false;
        }
    }

    handleCloseReminderModal() {
        this.showReminderModal = false;
    }

    async handleReminderPhoneChange(event) {
        this.selectedReminderPhoneKey = event.detail.value;
        await this.refreshReminderPreview();
    }

    async refreshReminderPreview() {
        if (!this.selectedReminderPhoneKey) {
            this.reminderMessagePreview = '';
            return;
        }
        const phoneRow = (this.reminderContext?.phoneOptions || []).find(
            (row) => row.key === this.selectedReminderPhoneKey
        );
        if (!phoneRow) {
            this.reminderMessagePreview = '';
            return;
        }
        this.reminderMessagePreview = await buildMeetingReminderMessage({
            visitId: this.recordId,
            recipientAccountName: phoneRow.accountName || phoneRow.firstName
        });
    }

    async handleSendReminderWhatsApp() {
        const phoneRow = (this.reminderContext?.phoneOptions || []).find(
            (row) => row.key === this.selectedReminderPhoneKey
        );
        if (!phoneRow?.phone) {
            this.showToast('WhatsApp', 'Select a valid phone number.', 'error');
            return;
        }
        const digits = phoneRow.phone.replace(/[^0-9]/g, '');
        if (!digits) {
            this.showToast('WhatsApp', 'Phone number is not valid for WhatsApp.', 'error');
            return;
        }
        if (!this.reminderMessagePreview) {
            await this.refreshReminderPreview();
        }
        const url = `https://wa.me/${digits}?text=${encodeURIComponent(this.reminderMessagePreview)}`;
        window.open(url, '_blank');
        this.handleCloseReminderModal();
        this.showToast('WhatsApp', 'Opening WhatsApp with the meeting reminder.', 'success');
    }

    showToast(title, message, variant) {
        this.dispatchEvent(new ShowToastEvent({ title, message, variant }));
    }

    reduceError(error) {
        if (Array.isArray(error?.body)) {
            return error.body.map((item) => item.message).join(', ');
        }
        return error?.body?.message || error?.message || 'Unexpected error';
    }
}