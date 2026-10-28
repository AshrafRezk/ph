import { LightningElement, api, track, wire } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import LightningConfirm from 'lightning/confirm';
import { MessageContext } from 'lightning/messageService';
import LEAFLET from '@salesforce/resourceUrl/leaflet';
import fetchPlannerData from '@salesforce/apex/FieldPlannerController.fetchPlannerData';
import getMapAccounts from '@salesforce/apex/FieldPlannerController.getMapAccounts';
import getPlannerAccountRecordTypes from '@salesforce/apex/FieldPlannerController.getPlannerAccountRecordTypes';
import getPlannerAccountFilterOptions from '@salesforce/apex/FieldPlannerController.getPlannerAccountFilterOptions';
import getPlannerViewerContext from '@salesforce/apex/FieldPlannerController.getPlannerViewerContext';
import getWizardCreateOptions from '@salesforce/apex/AccountsTabController.getWizardCreateOptions';
import {
    getVisitStatusOptions,
    validateVisitStatusChange,
    isNonWorkingDay,
    setWorkingDays,
    canSubmitForApproval,
    isLockedVisitStatus,
    isPendingApprovalStatus,
    isPlannedVisitType,
    VISIT_STATUS_DRAFT,
    VISIT_STATUS_SUBMITTED,
    VISIT_STATUS_SCHEDULED,
    VISIT_STATUS_COMPLETED,
    VISIT_STATUS_CANCELLED
} from 'c/visitStatusUtils';
import submitVisit from '@salesforce/apex/FieldPlannerController.submitVisit';
import submitWeekPlans from '@salesforce/apex/FieldPlannerController.submitWeekPlans';
import approvePlanVisit from '@salesforce/apex/FieldPlannerController.approvePlanVisit';
import rejectPlanVisit from '@salesforce/apex/VisitValidationController.rejectPlanVisit';
import approveTotRequest from '@salesforce/apex/TimeOffRequestController.approveRequest';
import rejectTotRequest from '@salesforce/apex/TimeOffRequestController.rejectRequest';
import approveMeetingPlan from '@salesforce/apex/MeetingPlannerController.approveMeetingPlan';
import rejectMeetingPlan from '@salesforce/apex/MeetingPlannerController.rejectMeetingPlan';
import getAccountVisitTargets from '@salesforce/apex/FieldPlannerController.getAccountVisitTargets';
import getWeeklyPlanRecommendations from '@salesforce/apex/FieldPlannerAssistController.getWeeklyPlanRecommendations';
import copyDayVisits from '@salesforce/apex/FieldPlannerAssistController.copyDayVisits';
import copyWeekVisits from '@salesforce/apex/FieldPlannerAssistController.copyWeekVisits';
import askPlannerQuestion from '@salesforce/apex/PlannerAskService.askPlannerQuestion';
import searchAccountsPage from '@salesforce/apex/FieldPlannerController.searchAccountsPage';
import upsertVisit from '@salesforce/apex/FieldPlannerController.upsertVisit';
import rescheduleVisits from '@salesforce/apex/FieldPlannerController.rescheduleVisits';
import deleteVisit from '@salesforce/apex/FieldPlannerController.deleteVisit';
import createTimeOff from '@salesforce/apex/FieldPlannerController.createTimeOff';
import updateTimeOff from '@salesforce/apex/FieldPlannerAssistController.updateTimeOff';
import getPromotionalProjects from '@salesforce/apex/FieldPlannerController.getPromotionalProjects';
import fetchMeetings from '@salesforce/apex/MeetingPlannerController.fetchMeetings';
import {
    getCurrentPosition,
    fetchOsrmRoute,
    haversineKm,
    parseOptimizedVisitOrder,
    buildSwapHints
} from 'c/plannerMapUtils';
import { detectRouteOutliers, formatDistantStopsSummary, normalizeSalesforceId } from 'c/plannerRouteUtils';
import {
    addOsmTileLayer,
    createVisitPinIcon,
    ensureLeaflet,
    prefetchMapAreaTiles,
    resolveAccountPinKind,
    resolveAccountTypeLabel,
    resolveAccountListKind
} from 'c/plannerMapPins';
import { accountTypeIconUrl, resolveAccountThemeKind } from 'c/accountTypeTheme';
import {
    loadAccountCollections,
    saveAccountCollections
} from 'c/plannerAccountCollections';
import {
    subscribeTerritoryContext,
    unsubscribeTerritoryContext
} from 'c/territoryContextClient';
import { isFieldFeatureEnabled, loadFieldFeatures } from 'c/fieldFeatureFlags';
import Id from '@salesforce/user/Id';
import {
    getMapAccountsCache,
    getPlannerCache,
    getUserMapAccountsKey,
    getUserPlannerCacheKey,
    newClientKey,
    putCachedAccounts,
    putCachedMapLocation,
    getCachedMapLocation,
    putMapAccountsCache,
    putPlannerCache,
    searchCachedAccounts
} from 'c/clmOfflineStore';
import { isOfflineMode, queueOfflineAction, markOnline, markOffline } from 'c/clmOfflineSync';

const DAY_START_HOUR = 6;
const DAY_END_HOUR = 24;
const SLOT_MINUTES = 30;
const PX_PER_MINUTE = 1;
const CALENDAR_HEADER_HEIGHT = 32;
const CALENDAR_DAY_END_MARKER_HEIGHT = 1;
const DEFAULT_VISIT_MINUTES = 60;
const ACCOUNT_PAGE_SIZE = 40;
const ACCOUNT_LIST_VISIBLE_COUNT = 10;
const ACCOUNT_AUTO_FILL_MAX_PAGES = 1;
const SEARCH_DEBOUNCE_MS = 350;
const ROUTE_PREVIEW_DEBOUNCE_MS = 400;
const FILTER_ALL = 'All';
const ON_TIME_BUFFER_MIN = 10;
const EARLY_THRESHOLD_MIN = 10;
const FUEL_COST_PER_KM = 0.12;
const DETOUR_ON_WAY_MAX_MIN = 5;
const DRAG_TYPE_ACCOUNT = 'account';
const DRAG_TYPE_TOT = 'tot';
const DRAG_TYPE_EVENT = 'event';
const DRAG_TYPE_PROMO = 'promo';
const DRAG_TYPE_MEETING = 'meeting';
const DEFAULT_PROMO_MINUTES = 120;
const DEFAULT_MEETING_MINUTES = 120;
const TOT_STAGE_SUBMITTED = 'Submitted for Approval';
const MEETING_PENDING_STATUSES = new Set([
    'PendingApproval',
    'Pending GPM Approval',
    'Pending NLM Approval'
]);
const PLAN_SLOT_DAY_FORMAT = { weekday: 'long', day: 'numeric', month: 'long' };
const PLAN_SLOT_TIME_FORMAT = { hour: 'numeric', minute: '2-digit' };
const OSRM_BASE = 'https://router.project-osrm.org';
const LIST_MODE_ALL = 'all';
const LIST_MODE_COLLECTION = 'collection';
const COLLECTION_FETCH_PAGE_SIZE = 200;

function totStageKind(stage) {
    const raw = String(stage || 'Draft').trim();
    if (raw === 'Approved' || raw === 'Scheduled') return 'scheduled';
    if (raw === 'Rejected') return 'rejected';
    if (raw === 'Submitted for Approval' || raw === 'Submitted') return 'submitted';
    return 'draft';
}

function meetingStatusKind(status) {
    const raw = String(status || 'Draft').trim();
    const lower = raw.toLowerCase();
    if (raw === 'Rejected' || raw === 'Cancelled') return 'rejected';
    if (
        raw === 'Approved' ||
        raw === 'Scheduled' ||
        raw === 'Closed' ||
        raw === 'Concluded'
    ) {
        return 'scheduled';
    }
    if (
        raw === 'PendingApproval' ||
        raw === 'Pending Approval' ||
        raw === 'Pending GPM Approval' ||
        raw === 'Pending NLM Approval' ||
        raw === 'Submitted' ||
        lower.includes('pending') ||
        lower.includes('gpm') ||
        lower.includes('nlm')
    ) {
        return 'submitted';
    }
    return 'draft';
}

function plannerStatusTitlePrefix(kind) {
    if (kind === 'scheduled') return 'Scheduled — ';
    if (kind === 'rejected') return 'Rejected — ';
    if (kind === 'submitted') return 'Submitted — ';
    return 'Draft — ';
}

// Keep in sync with timeOffSubmission TYPE_OPTIONS (types only; spans unchanged here).
const TOT_TYPES = [
    { label: 'Annual Leave', value: 'Annual Leave' },
    { label: 'Business Trip', value: 'Business Trip' },
    { label: 'Sick', value: 'Sick' },
    { label: 'Training', value: 'Training' },
    { label: 'Casual/Emergency', value: 'Casual/Emergency' },
    { label: 'Health Day', value: 'Health Day' },
    { label: 'Maternity/Paternity', value: 'Maternity/Paternity' },
    { label: 'Office Work', value: 'Office Work' },
    { label: 'Marriage', value: 'Marriage' },
    { label: 'Cycle Meeting', value: 'Cycle Meeting' },
    { label: 'Unpaid', value: 'Unpaid' },
    { label: 'Sales Meeting', value: 'Sales Meeting' },
    { label: 'Military', value: 'Military' },
    { label: 'Prospection', value: 'Prospection' },
    { label: 'Handover', value: 'Handover' },
    { label: 'Sales Day', value: 'Sales Day' },
    { label: 'Delegation', value: 'Delegation' },
    { label: 'RTD', value: 'RTD' },
    { label: 'Speaker', value: 'Speaker' }
];

const TOT_SPANS = [
    { label: 'Full Day', value: 'Full_Day' },
    { label: 'Partial (Hours)', value: 'Hours' }
];

const TOT_QUICK_PRESETS = [
    { id: 'training-2h', label: 'Training · 2h', typeValue: 'Training', spanType: 'Hours', durationHours: '2' },
    { id: 'sick-4h', label: 'Sick · 4h', typeValue: 'Sick', spanType: 'Hours', durationHours: '4' },
    {
        id: 'annual-leave-full',
        label: 'Annual Leave · Full day',
        typeValue: 'Annual Leave',
        spanType: 'Full_Day',
        durationHours: null
    },
    { id: 'health-3h', label: 'Health Day · 3h', typeValue: 'Health Day', spanType: 'Hours', durationHours: '3' }
];

function startOfWeek(date) {
    const d = new Date(date);
    // Saturday-start calendar week; working days come from Planner Rules.
    const daysFromSaturday = (d.getDay() + 1) % 7;
    d.setDate(d.getDate() - daysFromSaturday);
    d.setHours(0, 0, 0, 0);
    return d;
}

function addDays(date, days) {
    const d = new Date(date);
    d.setDate(d.getDate() + days);
    return d;
}

function toDateKey(date) {
    const pad = (n) => String(n).padStart(2, '0');
    return `${date.getFullYear()}-${pad(date.getMonth() + 1)}-${pad(date.getDate())}`;
}

function formatTime(date) {
    return date.toLocaleTimeString([], { hour: '2-digit', minute: '2-digit' });
}

function formatDateLabel(date) {
    return date.toLocaleDateString([], { month: 'short', day: 'numeric' });
}

function parseSalesforceDateTime(value) {
    if (!value) {
        return null;
    }
    return new Date(value);
}

function sameSalesforceId(left, right) {
    if (!left || !right) {
        return left === right;
    }
    return String(left).substring(0, 15) === String(right).substring(0, 15);
}

function isViewerOwnTerritory(option, defaultUserId, assignedTerritoryIds) {
    const userId = option?.userId || option?.value;
    if (defaultUserId && userId && sameSalesforceId(userId, defaultUserId)) {
        return true;
    }
    if (option?.assigned === true) {
        return true;
    }
    const territoryId = option?.territoryId;
    if (!territoryId || !Array.isArray(assignedTerritoryIds)) {
        return false;
    }
    return assignedTerritoryIds.some((id) => sameSalesforceId(id, territoryId));
}

function toSalesforceDateTimeLocal(date) {
    const pad = (n) => String(n).padStart(2, '0');
    return `${date.getFullYear()}-${pad(date.getMonth() + 1)}-${pad(date.getDate())}T${pad(date.getHours())}:${pad(date.getMinutes())}`;
}

function toApexDate(date) {
    const pad = (n) => String(n).padStart(2, '0');
    return `${date.getFullYear()}-${pad(date.getMonth() + 1)}-${pad(date.getDate())}`;
}

function toApexDateTime(value) {
    const date = value instanceof Date ? value : new Date(value);
    if (Number.isNaN(date.getTime())) {
        return null;
    }
    return date.toISOString();
}

function normalizeLocalDateTimeString(value) {
    if (!value) {
        return null;
    }
    const normalized = value.length === 16 ? `${value}:00` : value;
    return toApexDateTime(new Date(normalized));
}

// geolocation + OSRM helpers moved to plannerMapUtils/plannerMapUtils.js

function coerceGeoCoordinate(value) {
    if (value == null || value === '') {
        return null;
    }
    const num = Number(value);
    return Number.isFinite(num) ? num : null;
}

function buildGeoStopsFromVisits(visits, dayKey) {
    return (visits || [])
        .filter((visit) => {
            const start = parseSalesforceDateTime(visit.startDateTime);
            return start && toDateKey(start) === dayKey && visit.accountId;
        })
        .map((visit) => {
            const latitude = coerceGeoCoordinate(visit.accountLatitude);
            const longitude = coerceGeoCoordinate(visit.accountLongitude);
            if (latitude == null || longitude == null) {
                return null;
            }
            return {
                id: visit.id,
                accountName: visit.accountName || visit.name || 'Visit',
                latitude,
                longitude
            };
        })
        .filter(Boolean);
}

function buildOutlierIdsByDayKey(visits, dayKeys) {
    const result = {};
    (dayKeys || []).forEach((dayKey) => {
        const outliers = detectRouteOutliers(buildGeoStopsFromVisits(visits, dayKey));
        result[dayKey] = new Set(outliers.map((item) => normalizeSalesforceId(item.visitId)));
    });
    return result;
}

function buildCoordPath(points) {
    return points.map((point) => `${point.longitude},${point.latitude}`).join(';');
}

// fetchOsrmRoute moved to plannerMapUtils/plannerMapUtils.js

function buildRouteAlternatives(routes) {
    if (!routes?.length) {
        return [];
    }
    const fastest = routes.reduce((a, b) => (a.duration <= b.duration ? a : b));
    const shortest = routes.reduce((a, b) => (a.distance <= b.distance ? a : b));
    const lowestCost = routes.reduce((a, b) =>
        a.distance * FUEL_COST_PER_KM <= b.distance * FUEL_COST_PER_KM ? a : b
    );
    const unique = new Map();
    const add = (id, label, route) => {
        if (!unique.has(id)) {
            unique.set(id, {
                id,
                label,
                distanceKm: (route.distance / 1000).toFixed(1),
                durationMin: Math.round(route.duration / 60),
                estCost: (route.distance / 1000 * FUEL_COST_PER_KM).toFixed(2),
                geometry: route.geometry,
                legs: route.legs,
                duration: route.duration,
                distance: route.distance
            });
        }
    };
    add('fastest', 'Fastest', fastest);
    if (shortest !== fastest) {
        add('shortest', 'Shortest', shortest);
    }
    if (lowestCost !== fastest && lowestCost !== shortest) {
        add('lowestCost', 'Lowest est. cost', lowestCost);
    }
    return [...unique.values()];
}

function computeArrivalStatuses(orderedStops, legs, departureTime = new Date()) {
    if (!orderedStops?.length) {
        return [];
    }
    let cursor = new Date(departureTime.getTime());
    return orderedStops.map((stop, index) => {
        const driveMs = (legs[index]?.duration || 0) * 1000;
        cursor = new Date(cursor.getTime() + driveMs);
        const scheduledStart = parseSalesforceDateTime(stop.startDateTime);
        const eta = new Date(cursor.getTime());
        let status = 'on_time';
        let statusLabel = 'On time';
        let statusClass = 'arrival-on-time';
        let diffMin = 0;
        if (scheduledStart) {
            diffMin = Math.round((eta.getTime() - scheduledStart.getTime()) / 60000);
            if (diffMin < -EARLY_THRESHOLD_MIN) {
                status = 'early';
                statusLabel = `Early · ETA ${formatTime(eta)} (${Math.abs(diffMin)} min early)`;
                statusClass = 'arrival-early';
            } else if (diffMin > ON_TIME_BUFFER_MIN) {
                status = 'late';
                statusLabel = `Won't make it · ETA ${formatTime(eta)} (${diffMin} min late)`;
                statusClass = 'arrival-late';
            } else {
                statusLabel = `On time · ETA ${formatTime(eta)}`;
            }
        } else {
            statusLabel = `ETA ${formatTime(eta)}`;
        }
        const durationMs = stop.durationMs || DEFAULT_VISIT_MINUTES * 60000;
        cursor = new Date(eta.getTime() + durationMs);
        return { ...stop, eta, diffMin, status, statusLabel, statusClass };
    });
}

// haversineKm moved to plannerMapUtils/plannerMapUtils.js

function accountMatchesFilters(account, filters) {
    const term = (filters.searchTerm || '').trim().toLowerCase();
    if (filters.recordType && filters.recordType !== FILTER_ALL) {
        if (account.recordTypeDeveloperName !== filters.recordType) {
            return false;
        }
    }
    if (filters.specialty && filters.specialty !== FILTER_ALL) {
        const specialtyValue = account.specialtyApiValue || account.specialty;
        if (specialtyValue !== filters.specialty) {
            return false;
        }
    }
    if (filters.classification && filters.classification !== FILTER_ALL) {
        if (account.classification !== filters.classification) {
            return false;
        }
    }
    if (!accountMatchesBrickFilters(account, filters)) {
        return false;
    }
    if (term) {
        const haystack = [
            account.name,
            account.specialty,
            account.city,
            account.classification,
            account.brickName,
            account.brick148Name,
            account.brick702Name
        ]
            .filter(Boolean)
            .join(' ')
            .toLowerCase();
        if (!haystack.includes(term)) {
            return false;
        }
    }
    return true;
}

function accountMatchesBrickFilters(account, filters) {
    const brick702Id = filters.brick702Id && filters.brick702Id !== FILTER_ALL ? String(filters.brick702Id) : '';
    const brick148Id = filters.brick148Id && filters.brick148Id !== FILTER_ALL ? String(filters.brick148Id) : '';
    const legacyBrickId = filters.brickId && filters.brickId !== FILTER_ALL ? String(filters.brickId) : '';
    if (brick702Id) {
        const ids = [account.brick702Id, account.brickId].filter(Boolean).map((value) => String(value));
        if (!ids.includes(brick702Id)) {
            return false;
        }
    }
    if (brick148Id) {
        const ids = [account.brick148Id, account.brickId].filter(Boolean).map((value) => String(value));
        if (!ids.includes(brick148Id)) {
            const childMatch = (filters.brick702Options || []).some(
                (option) =>
                    String(option?.parentValue || '') === brick148Id &&
                    ids.includes(String(option.value))
            );
            if (!childMatch) {
                return false;
            }
        }
    }
    if (!brick702Id && !brick148Id && legacyBrickId) {
        const ids = [account.brickId, account.brick148Id, account.brick702Id]
            .filter(Boolean)
            .map((value) => String(value));
        if (!ids.includes(legacyBrickId)) {
            return false;
        }
    }
    return true;
}

async function fetchOsrmTrip(coordPath) {
    const url = `${OSRM_BASE}/trip/v1/driving/${coordPath}?source=first&roundtrip=false&geometries=geojson`;
    const response = await fetch(url);
    const data = await response.json();
    if (data.code !== 'Ok' || !data.trips?.length) {
        throw new Error('Unable to optimize route.');
    }
    return data;
}

// parseOptimizedVisitOrder moved to plannerMapUtils/plannerMapUtils.js

// buildSwapHints moved to plannerMapUtils/plannerMapUtils.js

function computeScheduleFromRoute(orderedStops, legs) {
    const schedules = [];
    if (!orderedStops.length) {
        return schedules;
    }
    let cursor = parseSalesforceDateTime(orderedStops[0].startDateTime);
    for (let index = 0; index < orderedStops.length; index++) {
        if (index > 0) {
            const driveMs = (legs[index]?.duration || 0) * 1000;
            cursor = new Date(cursor.getTime() + driveMs);
        }
        const durationMs = orderedStops[index].durationMs || DEFAULT_VISIT_MINUTES * 60000;
        const start = new Date(cursor.getTime());
        const end = new Date(start.getTime() + durationMs);
        schedules.push({ visitId: orderedStops[index].id, start, end });
        cursor = end;
    }
    return schedules;
}

export default class FieldRepPlanner extends NavigationMixin(LightningElement) {
    @track weekStart = startOfWeek(new Date());
    @track viewMode = 'calendar';
    @track mobileSubView = 'calendar';
    @track mapDayKey = toDateKey(new Date());
    @track accounts = [];
    @track visits = [];
    @track timeOffBlocks = [];
    @track meetings = [];
    @track publicHolidayDates = [];
    // Planner Rules for the planner owner (from the server); null until the week loads.
    @track plannerWorkingDays = null;
    @track plannerPolicies = {};
    @track accountSearch = '';
    @track accountRecordType = 'All';
    @track accountSpecialty = 'All';
    @track accountClassification = 'All';
    @track accountBrick = 'All';
    @track accountBrick148 = 'All';
    @track accountBrick702 = 'All';
    @track visitCoverage = 'all';
    @track specialtyOptions = [{ label: 'All Specialties', value: 'All' }];
    @track classificationOptions = [{ label: 'All Classifications', value: 'All' }];
    @track brickOptions = [{ label: 'All Bricks', value: 'All' }];
    @track brick148Options = [{ label: 'All 148 bricks', value: 'All' }];
    @track brick702Options = [{ label: 'All 702 bricks', value: 'All' }];
    @track recordTypeOptions = [];
    @track accountOffset = 0;
    @track hasMoreAccounts = false;
    @track totalAccountCount = 0;
    @track isLoadingAccounts = false;
    @track isLoading = false;
    @track isSaving = false;
    @track errorMessage;
    @track modalClosing = false;
    @track showTotModal = false;
    @track totTypeValue = '';
    @track totSpanType = '';
    @track totDurationHours = '';
    @track totStartDateTime = '';
    @track totStartDate = '';
    @track totComments = '';
    @track routeSummary;
    @track currentLocation;
    @track mapAccounts = [];
    @track isLoadingMapAccounts = false;
    @track isBuildingRoute = false;
    @track isOptimizingRoute = false;
    @track isUpdatingRoute = false;
    @track routeVisitOrder = [];
    @track routeOrderDirty = false;
    @track routeOptimization;
    @track routeAlternatives = [];
    @track selectedRouteId = 'fastest';
    @track arrivalStatuses = [];
    @track visitSuggestions = [];
    @track accountVisitTargets = [];
    @track weekRecommendations = [];
    @track weekForecast;
    @track isLoadingRecommendations = false;
    @track copyTargetDayKey = '';
    @track isCopyingDay = false;
    @track showCopyPlanMenu = false;
    @track showViewerMenu = false;
    @track isCopyingWeek = false;
    @track showPlannerInsights = false;
    @track plannerInsightLines = [];
    @track plannerChatMessages = [];
    @track plannerChatQuestion = '';
    @track isAskingPlanner = false;
    agentforceFabX = null;
    agentforceFabY = null;
    _agentforceDrag = null;
    _agentforceMoved = false;
    resizingEventType;
    @track proposedStops = [];
    @track selectedStopId;
    @track isRefreshingRoutePreview = false;
    @track plannerViewerContext;
    @track selectedContextUserId;
    @track selectedTerritoryId;
    @track viewerContextLabel = '';
    @track showPlanChoiceModal = false;
    @track showVisitModal = false;
    @track showVisitDetailModal = false;
    @track showVisitMoreMenu = false;
    @track showVisitPickerModal = false;
    @track visitPickerOptions = [];
    @track visitAccountId = '';
    @track visitAccountName = '';
    @track visitAccountIconName = '';
    @track visitAccountRecordTypeLabel = '';
    @track visitAccountInvalid = false;
    @track visitDetailId = '';
    @track visitDetailAccountName = '';
    @track visitDetailStatus = VISIT_STATUS_DRAFT;
    @track visitDetailOriginalStatus = '';
    @track visitDetailCancellationReason = '';
    @track visitDetailStartDateTime = '';
    @track visitDetailEndDateTime = '';
    @track pendingSlotStart = null;
    @track touchDragState;
    @track showPromoModal = false;
    @track promoProjectId = '';
    @track promoTitle = '';
    @track promoProjectOptions = [];
    @track showMeetingPanel = false;
    meetingPanelId = null;
    meetingPanelStart = null;
    meetingPanelEnd = null;
    @track showPlanApprovalModal = false;
    @track planApprovalKind = '';
    @track planApprovalRecordId = '';
    @track planApprovalTitle = '';
    @track planApprovalRejectionReason = '';
    @track managerPlanRejectionReason = '';
    @track totQuickPresets = TOT_QUICK_PRESETS;
    @track showAccountFilterPanel = false;
    @track showPlanningPalettePanel = false;
    @track showLegendPanel = false;
    @track accountCollections = [];
    @track selectedCollectionId = null;
    @track listViewMode = LIST_MODE_ALL;
    @track showSaveCollectionModal = false;
    @track saveCollectionName = '';
    @api hideEmbeddedAgentforce = false;
    meetingExpensesEnabled = true;
    mapRouteEnabled = true;
    copyPreviousEnabled = true;
    addMeetingEnabled = true;
    timeOffEnabled = true;
    fieldAiEnabled = true;
    @track showMeetingExpenseModal = false;
    @track meetingExpenseId;
    @track meetingExpenseTitle = '';
    @track isSavingCollection = false;
    @track showRenameCollectionModal = false;
    @track renameCollectionName = '';
    pendingTotStart = null;

    leafletReady = false;
    mapInstance;
    mapMarkers = [];
    visitPinIcons = {};
    routeLayer;
    altRouteLayers = [];
    flyAnimationToken = 0;
    routePreviewTimer;
    dragPayload;
    isDragActive = false;
    resizingEventId;
    resizeStartY;
    resizeOriginalEnd;
    searchDebounceTimer;
    suppressVisitClick = false;
    touchDragGhostEl;
    touchDropHighlightEl;
    touchDropHighlightClass;
    _handleDocumentTouchMove;
    _handleDocumentTouchEnd;
    _messageContext;
    territoryContextSubscription;

    @wire(MessageContext)
    wiredMessageContext(value) {
        this._messageContext = value;
        this.subscribeTerritoryContext();
    }

    connectedCallback() {
        this._handleDocumentTouchMove = this.handleDocumentTouchMove.bind(this);
        this._handleDocumentTouchEnd = this.handleDocumentTouchEnd.bind(this);
        this._onPlannerWeekUpdated = (event) => this.handlePlannerWeekUpdated(event);
        this._onPlanAccount = () => this.consumePendingPlanAccount();
        if (typeof window !== 'undefined') {
            window.addEventListener('zeta-planner-week-updated', this._onPlannerWeekUpdated);
            window.addEventListener('zeta-plan-account', this._onPlanAccount);
        }
        this.subscribeTerritoryContext();
        void this.bootstrapWithFeatures();
        this.bindPlannerViewport();
    }

    async bootstrapWithFeatures() {
        await loadFieldFeatures();
        this.mapRouteEnabled = isFieldFeatureEnabled('planner.mapRoute');
        this.copyPreviousEnabled = isFieldFeatureEnabled('planner.copyPrevious');
        this.addMeetingEnabled = isFieldFeatureEnabled('planner.addMeeting');
        this.timeOffEnabled = isFieldFeatureEnabled('planner.timeOff');
        this.meetingExpensesEnabled = isFieldFeatureEnabled('meetingExpenses');
        this.fieldAiEnabled = isFieldFeatureEnabled('agentforce');
        if (!this.mapRouteEnabled && this.viewMode === 'map') {
            this.viewMode = 'calendar';
        }
        this.bootstrapPlanner();
    }

    bindPlannerViewport() {
        if (this._onPlannerViewportResize || typeof window === 'undefined') {
            return;
        }
        this._onPlannerViewportResize = () => this.pinPlannerToViewport();
        window.addEventListener('resize', this._onPlannerViewportResize);
        if (window.visualViewport) {
            window.visualViewport.addEventListener('resize', this._onPlannerViewportResize);
        }
    }

    pinPlannerToViewport() {
        const host = this.template?.host;
        if (!host || typeof window === 'undefined') {
            return;
        }
        if (this.hideEmbeddedAgentforce === true) {
            host.classList.add('planner-embedded');
            host.style.height = '';
            host.style.maxHeight = '';
            this._pinnedHostHeight = undefined;
            return;
        }
        host.classList.remove('planner-embedded');
        const top = Math.max(0, host.getBoundingClientRect().top);
        const next = Math.max(280, Math.round(window.innerHeight - top - 8));
        if (Math.abs((this._pinnedHostHeight || 0) - next) < 4) {
            return;
        }
        this._pinnedHostHeight = next;
        host.style.height = `${next}px`;
        host.style.maxHeight = `${next}px`;
    }

    async bootstrapPlanner() {
        if (this._bootstrapInFlight) {
            this._bootstrapQueued = true;
            return;
        }
        this._bootstrapInFlight = true;
        console.log('[PlannerDbg] bootstrapPlanner start', {
            offlineMode: isOfflineMode(),
            navigatorOnLine: typeof navigator !== 'undefined' ? navigator.onLine : 'n/a'
        });
        try {
            await this.loadViewerContext();
            await Promise.all([
                this.loadRecordTypes(),
                this.loadFilterOptions(),
                this.loadWeek(),
                this.loadAccountsPage(true)
            ]);
            console.log('[PlannerDbg] bootstrapPlanner done', {
                accounts: this.accounts?.length,
                totalAccountCount: this.totalAccountCount,
                isCollectionView: this.isCollectionView
            });
            this.consumePendingPlanAccount();
            void this.warmMapCache();
        } finally {
            this._bootstrapInFlight = false;
            if (this._bootstrapQueued) {
                this._bootstrapQueued = false;
                void this.bootstrapPlanner();
            }
        }
    }

    handlePlannerWeekUpdated(event) {
        const weekStart = event?.detail?.weekStart;
        const payload = event?.detail?.payload;
        if (!payload || weekStart !== toApexDate(this.weekStart)) {
            return;
        }
        this.visits = payload.visits || [];
        this.timeOffBlocks = payload.timeOffBlocks || payload.timeOff || [];
        if (Array.isArray(payload.meetings) && (payload.meetings.length || !(this.meetings || []).length)) {
            this.meetings = payload.meetings;
        }
        if (this.isMapView) {
            this.initializeRouteVisitOrder();
            void this.renderMap();
        }
    }

    consumePendingPlanAccount() {
        if (this.isReadOnlyPlannerView) {
            return;
        }
        let accountId = '';
        try {
            accountId = sessionStorage.getItem('zeta.pwa.planAccountId') || '';
            if (accountId) {
                sessionStorage.removeItem('zeta.pwa.planAccountId');
            }
        } catch (_storageError) {
            accountId = '';
        }
        if (!accountId) {
            return;
        }
        this.primeVisitAccount(accountId);
        this.pendingSlotStart = new Date();
        this.pendingSlotStart.setMinutes(0, 0, 0);
        this.showVisitModal = true;
        this.showToast('Plan visit', 'Pick a date and time for this account, then save the draft.', 'info');
    }

    async loadRecordTypes() {
        try {
            const data = await getPlannerAccountRecordTypes();
            if (data && data.length) {
                this.recordTypeOptions = data;
                if (!this.accountRecordType) {
                    this.accountRecordType = 'All';
                }
            } else {
                this.recordTypeOptions = [{ label: 'All Record Types', value: 'All' }];
            }
        } catch (_error) {
            this.recordTypeOptions = [{ label: 'All Record Types', value: 'All' }];
        }
    }

    renderedCallback() {
        this.pinPlannerToViewport();
        const list = this.template.querySelector('.account-list');
        if (list && list !== this._accountListEl) {
            this.unbindAccountListScroll();
            this._accountListEl = list;
            this._onAccountListScroll = (event) => this.handleAccountListScroll(event);
            list.addEventListener('scroll', this._onAccountListScroll, { passive: true });
        }
        if (this._pendingAccountListFill) {
            this._pendingAccountListFill = false;
            this.fillAccountListIfNeeded();
        }
    }

    unbindAccountListScroll() {
        if (this._accountListEl && this._onAccountListScroll) {
            this._accountListEl.removeEventListener('scroll', this._onAccountListScroll);
        }
        this._accountListEl = undefined;
        this._onAccountListScroll = undefined;
    }

    disconnectedCallback() {
        this.unbindAccountListScroll();
        this.teardownTouchDragListeners();
        this.destroyMap();
        window.clearTimeout(this.searchDebounceTimer);
        window.clearTimeout(this.routePreviewTimer);
        window.clearTimeout(this._modalCloseTimer);
        window.removeEventListener('mousemove', this.handleResizeMove);
        window.removeEventListener('mouseup', this.handleResizeEnd);
        if (this._onPlannerWeekUpdated && typeof window !== 'undefined') {
            window.removeEventListener('zeta-planner-week-updated', this._onPlannerWeekUpdated);
        }
        if (this._onPlanAccount && typeof window !== 'undefined') {
            window.removeEventListener('zeta-plan-account', this._onPlanAccount);
        }
        if (this._onPlannerViewportResize && typeof window !== 'undefined') {
            window.removeEventListener('resize', this._onPlannerViewportResize);
            if (window.visualViewport) {
                window.visualViewport.removeEventListener('resize', this._onPlannerViewportResize);
            }
            this._onPlannerViewportResize = undefined;
        }
        if (this._onCopyPlanOutside && typeof window !== 'undefined') {
            window.removeEventListener('click', this._onCopyPlanOutside, true);
            this._onCopyPlanOutside = undefined;
        }
        this.unbindViewerMenuOutside();
        unsubscribeTerritoryContext(this.territoryContextSubscription);
        this.territoryContextSubscription = undefined;
    }

    subscribeTerritoryContext() {
        if (this.territoryContextSubscription || !this._messageContext) {
            return;
        }
        this.territoryContextSubscription = subscribeTerritoryContext(this._messageContext, (message) => {
            const nextKey = `${message?.territoryId || ''}|${message?.usingAllAssigned === true}`;
            if (this._territoryContextKey === undefined) {
                this._territoryContextKey = nextKey;
                return;
            }
            if (nextKey === this._territoryContextKey) {
                return;
            }
            this._territoryContextKey = nextKey;
            this.destroyMap();
            void this.bootstrapPlanner();
        });
    }

    get plannerModalClass() {
        return this.modalClosing
            ? 'slds-modal slds-fade-in-open planner-modal-exit'
            : 'slds-modal slds-fade-in-open';
    }

    get plannerBackdropClass() {
        return this.modalClosing
            ? 'slds-backdrop slds-backdrop_open planner-backdrop-exit'
            : 'slds-backdrop slds-backdrop_open';
    }

    stopPlannerModalContentClick(event) {
        event.stopPropagation();
    }

    handlePlannerModalShellClick(event) {
        if (event.target !== event.currentTarget) {
            return;
        }
        this.dismissPlannerModal(event.currentTarget.dataset.modal);
    }

    closePlannerModal(applyClose) {
        if (typeof applyClose !== 'function' || this.modalClosing) {
            return;
        }
        const reduceMotion =
            typeof window !== 'undefined' &&
            window.matchMedia &&
            window.matchMedia('(prefers-reduced-motion: reduce)').matches;
        if (reduceMotion) {
            applyClose();
            return;
        }
        this.modalClosing = true;
        window.clearTimeout(this._modalCloseTimer);
        this._modalCloseTimer = window.setTimeout(() => {
            this.modalClosing = false;
            this._modalCloseTimer = undefined;
            applyClose();
        }, 240);
    }

    dismissPlannerModal(name) {
        switch (name) {
            case 'visitDetail':
                this.handleVisitDetailCancel();
                return;
            case 'planChoice':
                this.handlePlanChoiceCancel();
                return;
            case 'visit':
                this.handleVisitCancel();
                return;
            case 'visitPicker':
                this.handleVisitPickerCancel();
                return;
            case 'tot':
                this.handleTotCancel();
                return;
            case 'planApproval':
                this.handlePlanApprovalCancel();
                return;
            case 'renameCollection':
                this.handleRenameCollectionCancel();
                return;
            case 'saveCollection':
                this.handleSaveCollectionCancel();
                return;
            case 'promo':
                this.handlePromoCancel();
                return;
            case 'meeting':
                this.handleMeetingPanelClose();
                return;
            case 'meetingExpense':
                this.handleMeetingExpenseClose();
                return;
            default:
                return;
        }
    }

    get isManagerSubTerritoryView() {
        return (
            this.plannerViewerContext?.viewerMode === 'manager' &&
            this.plannerViewerContext?.canApproveTeamPlans !== true
        );
    }

    get viewerPickerLabel() {
        return this.isManagerSubTerritoryView ? 'Sub-territory' : 'View planner for';
    }

    get viewerPickerPlaceholder() {
        return 'My territory';
    }

    get renderAgentforceFab() {
        return this.hideEmbeddedAgentforce !== true && this.fieldAiEnabled === true;
    }

    get showMapRouteSwitch() {
        return this.mapRouteEnabled === true;
    }

    get showCopyPreviousPlan() {
        return this.copyPreviousEnabled === true;
    }

    get showPlanningPlus() {
        return this.addMeetingEnabled === true || this.timeOffEnabled === true;
    }

    get showPlannerMeetingSection() {
        return this.addMeetingEnabled === true;
    }

    get showPlannerTimeOffSection() {
        return this.timeOffEnabled === true;
    }

    handleMeetingExpenseClose() {
        this.showMeetingExpenseModal = false;
        this.meetingExpenseId = null;
        this.meetingExpenseTitle = '';
    }

    handleOpenMeetingRecord() {
        if (this.meetingExpenseId) {
            this.navigateToRecord(this.meetingExpenseId, 'Meeting__c');
        }
        this.handleMeetingExpenseClose();
    }

    get isViewingSelf() {
        const defaultUserId = this.plannerViewerContext?.defaultUserId;
        return (
            !this.selectedContextUserId ||
            !defaultUserId ||
            sameSalesforceId(this.selectedContextUserId, defaultUserId)
        );
    }

    get contextUserId() {
        if (this.isViewingSelf) {
            return this.plannerViewerContext?.defaultUserId || null;
        }
        return this.selectedContextUserId || null;
    }

    get isReadOnlyPlannerView() {
        return this.canSwitchPlannerView && !this.isViewingSelf;
    }

    get canManageTeamPlans() {
        if (this.plannerViewerContext?.canApproveTeamPlans !== true || this.isViewingSelf) {
            return false;
        }
        return this.selectedViewerOption?.canApprove !== false;
    }

    get selectedViewerOption() {
        const options = this.plannerViewerContext?.options || [];
        if (this.selectedTerritoryId) {
            const byTerritory = options.find(
                (option) =>
                    option.territoryId &&
                    sameSalesforceId(option.territoryId, this.selectedTerritoryId) &&
                    (!this.selectedContextUserId ||
                        sameSalesforceId(option.userId, this.selectedContextUserId))
            );
            if (byTerritory) {
                return byTerritory;
            }
        }
        return options.find(
            (option) => option.userId && sameSalesforceId(option.userId, this.selectedContextUserId)
        );
    }

    get showTeamPlannerBanner() {
        return this.canManageTeamPlans;
    }

    get teamPlannerBannerLabel() {
        const repLabel = this.selectedViewerOption?.label || 'this rep';
        return `Review ${repLabel}'s weekly plan. Approve or reject submitted visits, TOTs, and meetings.`;
    }

    get canSwitchPlannerView() {
        return this.plannerViewerContext?.canSwitchView === true;
    }

    get plannerViewerOptions() {
        const defaultUserId = this.plannerViewerContext?.defaultUserId;
        const assignedTerritoryIds = this.plannerViewerContext?.assignedTerritoryIds;
        const options = [
            {
                label: 'My territory',
                value: defaultUserId,
                territoryId: '',
                assigned: true,
                pendingApprovalCount: 0
            }
        ];
        const seen = new Set();
        (this.plannerViewerContext?.options || []).forEach((option) => {
            const val = option.userId || option.value;
            if (!val || isViewerOwnTerritory(option, defaultUserId, assignedTerritoryIds)) {
                return;
            }
            const territoryId = option.territoryId || '';
            const key = `${String(territoryId).substring(0, 15)}:${String(val).substring(0, 15)}`;
            if (seen.has(key)) {
                return;
            }
            seen.add(key);
            const territoryName = option.territoryName || '';
            const person = option.userName || '';
            options.push({
                label: option.label || [territoryName, person].filter(Boolean).join(' — '),
                value: val,
                territoryId,
                assigned: false,
                pendingApprovalCount: Number(option.pendingApprovalCount) || 0
            });
        });
        return options;
    }

    get plannerViewerMenuItems() {
        return this.plannerViewerOptions.map((option, index) => {
            let selected = false;
            if (option.assigned) {
                selected = this.isViewingSelf;
            } else if (option.territoryId && this.selectedTerritoryId) {
                selected = sameSalesforceId(option.territoryId, this.selectedTerritoryId);
            } else {
                selected = Boolean(option.value) && sameSalesforceId(option.value, this.selectedContextUserId);
            }
            const pending = option.assigned ? 0 : option.pendingApprovalCount;
            return {
                key: `${option.territoryId || 'mine'}-${option.value || 'self'}-${index}`,
                value: option.value || '',
                territoryId: option.territoryId || '',
                label: option.label,
                hasPending: pending > 0,
                pendingLabel: pending > 99 ? '99+' : String(pending),
                pendingTitle: `${pending} item${pending === 1 ? '' : 's'} to approve`,
                ariaSelected: selected ? 'true' : 'false',
                className: `planner-viewer-option${selected ? ' is-selected' : ''}`
            };
        });
    }

    get selectedViewerLabel() {
        if (this.isViewingSelf) {
            return this.viewerPickerPlaceholder;
        }
        return this.selectedViewerOption?.label || this.viewerPickerPlaceholder;
    }

    get viewerPendingTotal() {
        const seen = new Set();
        return this.plannerViewerOptions.reduce((sum, option) => {
            if (option.assigned) {
                return sum;
            }
            const key = option.value ? String(option.value).substring(0, 15) : '';
            if (!key || seen.has(key)) {
                return sum;
            }
            seen.add(key);
            return sum + (Number(option.pendingApprovalCount) || 0);
        }, 0);
    }

    get hasViewerPendingTotal() {
        return this.viewerPendingTotal > 0;
    }

    get viewerPendingTotalLabel() {
        const total = this.viewerPendingTotal;
        return total > 99 ? '99+' : String(total);
    }

    get viewerPendingTotalTitle() {
        const total = this.viewerPendingTotal;
        return `${total} item${total === 1 ? '' : 's'} pending your approval`;
    }

    get viewerMenuTriggerClass() {
        return `planner-viewer-trigger${this.showViewerMenu ? ' is-open' : ''}`;
    }

    get viewerMenuExpanded() {
        return this.showViewerMenu ? 'true' : 'false';
    }

    handleToggleViewerMenu(event) {
        event.stopPropagation();
        if (this.showViewerMenu) {
            this.closeViewerMenu();
            return;
        }
        this.showViewerMenu = true;
        this.unbindViewerMenuOutside();
        this._onViewerMenuOutside = (outsideEvent) => {
            const wrap = this.template.querySelector('.planner-viewer-picker');
            const path = typeof outsideEvent.composedPath === 'function' ? outsideEvent.composedPath() : [];
            if (wrap && (wrap.contains(outsideEvent.target) || path.includes(wrap))) {
                return;
            }
            this.closeViewerMenu();
        };
        window.setTimeout(() => {
            if (this._onViewerMenuOutside) {
                window.addEventListener('click', this._onViewerMenuOutside, true);
            }
        }, 0);
    }

    handleViewerMenuKeydown(event) {
        if (event.key === 'Escape' && this.showViewerMenu) {
            event.stopPropagation();
            this.closeViewerMenu();
        }
    }

    handleViewerOptionKeydown(event) {
        if (event.key === 'Enter' || event.key === ' ') {
            event.preventDefault();
            this.handleViewerMenuSelect(event);
        }
    }

    unbindViewerMenuOutside() {
        if (this._onViewerMenuOutside && typeof window !== 'undefined') {
            window.removeEventListener('click', this._onViewerMenuOutside, true);
        }
        this._onViewerMenuOutside = undefined;
    }

    closeViewerMenu() {
        this.showViewerMenu = false;
        this.unbindViewerMenuOutside();
    }

    async handleViewerMenuSelect(event) {
        const value = event.currentTarget.dataset.value;
        const territoryId = event.currentTarget.dataset.territoryId || '';
        this.closeViewerMenu();
        if (!value) {
            return;
        }
        const sameUser = this.isViewingSelf
            ? sameSalesforceId(value, this.plannerViewerContext?.defaultUserId)
            : sameSalesforceId(value, this.selectedContextUserId);
        const sameTerritory = !territoryId || sameSalesforceId(territoryId, this.selectedTerritoryId);
        if (sameUser && (this.isViewingSelf || sameTerritory)) {
            return;
        }
        await this.handleContextUserChange({ detail: { value, territoryId } });
    }

    adjustSelectedViewerPendingCount(delta) {
        const context = this.plannerViewerContext;
        if (!context?.options || this.isViewingSelf) {
            return;
        }
        this.plannerViewerContext = {
            ...context,
            options: context.options.map((option) =>
                option.userId && sameSalesforceId(option.userId, this.selectedContextUserId)
                    ? {
                          ...option,
                          pendingApprovalCount: Math.max(0, (Number(option.pendingApprovalCount) || 0) + delta)
                      }
                    : option
            )
        };
    }

    get showViewerBadge() {
        return this.plannerViewerContext?.viewerMode === 'admin' && this.plannerViewerContext?.topTerritoryName;
    }

    get viewerBadgeLabel() {
        return this.plannerViewerContext?.topTerritoryName || '';
    }

    get showSpecialtyFilter() {
        return (this.specialtyOptions || []).length > 1;
    }

    get showClassificationFilter() {
        return (this.classificationOptions || []).length > 1;
    }

    get specialtyFilterDisabled() {
        return !this.showSpecialtyFilter;
    }

    get classificationFilterDisabled() {
        return !this.showClassificationFilter;
    }

    get showBrickFilter() {
        return (this.brick148FilterOptions || []).length > 1 || (this.brick702FilterOptions || []).length > 1;
    }

    get brick148FilterOptions() {
        const rows = (this.brick148Options || []).filter((item) => item?.value && item.value !== FILTER_ALL);
        return [{ label: 'All 148 bricks', value: FILTER_ALL }, ...rows];
    }

    get brick702FilterOptions() {
        const rows = (this.brick702Options || []).filter((item) => item?.value && item.value !== FILTER_ALL);
        const selected148 = this.accountBrick148;
        const source =
            selected148 && selected148 !== FILTER_ALL
                ? rows.filter((item) => String(item.parentValue || '') === String(selected148))
                : rows;
        return [{ label: 'All 702 bricks', value: FILTER_ALL }, ...source];
    }

    get brick148FilterDisabled() {
        return (this.brick148FilterOptions || []).length <= 1;
    }

    get brick702FilterDisabled() {
        return (this.brick702FilterOptions || []).length <= 1;
    }

    get brickFilterDisabled() {
        return this.brick148FilterDisabled && this.brick702FilterDisabled;
    }

    get hasActiveAccountFilters() {
        return (
            this.activeDropdownFilterCount > 0 ||
            (this.accountSearch || '').trim().length > 0
        );
    }

    get activeDropdownFilterCount() {
        let count = 0;
        if (this.accountRecordType !== 'All') {
            count += 1;
        }
        if (this.accountSpecialty !== 'All') {
            count += 1;
        }
        if (this.accountClassification !== 'All') {
            count += 1;
        }
        if (this.accountBrick148 !== 'All') {
            count += 1;
        }
        if (this.accountBrick702 !== 'All') {
            count += 1;
        }
        if (this.accountBrick !== 'All' && this.accountBrick148 === 'All' && this.accountBrick702 === 'All') {
            count += 1;
        }
        if (this.visitCoverage && this.visitCoverage !== 'all') {
            count += 1;
        }
        return count;
    }

    get filterFunnelButtonClass() {
        return `filter-funnel-btn${this.showAccountFilterPanel ? ' is-open' : ''}${
            this.activeDropdownFilterCount > 0 ? ' has-active-filters' : ''
        }`;
    }

    get planningPlusButtonClass() {
        return `planning-plus-btn${this.showPlanningPalettePanel ? ' is-open' : ''}`;
    }

    get legendButtonClass() {
        return `planner-legend-btn${this.showLegendPanel ? ' is-open' : ''}`;
    }

    get collectionsStorageUserId() {
        return this.plannerViewerContext?.defaultUserId || this.selectedContextUserId || 'anonymous';
    }

    get selectedCollection() {
        return (this.accountCollections || []).find((item) => item.id === this.selectedCollectionId) || null;
    }

    get selectedCollectionName() {
        return this.selectedCollection?.name || '';
    }

    get isCollectionView() {
        return this.listViewMode === LIST_MODE_COLLECTION && Boolean(this.selectedCollection);
    }

    get collectionChips() {
        return (this.accountCollections || []).map((collection) => ({
            id: collection.id,
            label: `${collection.name} (${(collection.accounts || []).length})`,
            title: collection.name,
            chipClass: `collection-chip${
                this.selectedCollectionId === collection.id ? ' collection-chip-active' : ''
            }`
        }));
    }

    get allAccountsChipClass() {
        return `collection-chip collection-chip-all${
            this.listViewMode === LIST_MODE_ALL ? ' collection-chip-active' : ''
        }`;
    }

    get showCollectionDropZone() {
        return this.isCollectionView && !this.isReadOnlyPlannerView;
    }

    get canSaveFilterAsCollection() {
        return (
            !this.isReadOnlyPlannerView &&
            this.listViewMode === LIST_MODE_ALL &&
            this.hasActiveAccountFilters &&
            this.totalAccountCount > 0
        );
    }

    get saveCollectionAccountCountLabel() {
        return this.totalAccountCount === 1 ? '1 account' : `${this.totalAccountCount} accounts`;
    }

    get isMobileCalendarTab() {
        return this.mobileSubView === 'calendar';
    }

    get isMobileAccountsTab() {
        return this.mobileSubView === 'accounts';
    }

    get mobileCalendarBtnClass() {
        return `mobile-nav-btn${this.isMobileCalendarTab ? ' is-active' : ''}`;
    }

    get mobileAccountsBtnClass() {
        return `mobile-nav-btn${this.isMobileAccountsTab ? ' is-active' : ''}`;
    }

    handleSelectMobileCalendar() {
        this.mobileSubView = 'calendar';
    }

    handleSelectMobileAccounts() {
        this.mobileSubView = 'accounts';
    }

    get isSaveCollectionDisabled() {
        return this.isSavingCollection || !(this.saveCollectionName || '').trim();
    }

    get isRenameCollectionDisabled() {
        return !(this.renameCollectionName || '').trim();
    }

    get accountSearchPlaceholder() {
        return this.isCollectionView
            ? 'Switch to All accounts to search'
            : 'Search by name, specialty, or 148/702 brick…';
    }

    get showCompactFilterSummary() {
        return this.hasActiveAccountFilters && !this.showAccountFilterPanel;
    }

    get activeFilterChips() {
        const chips = [];
        if ((this.accountSearch || '').trim()) {
            chips.push({ key: 'search', label: `Search: ${this.accountSearch.trim()}` });
        }
        if (this.accountRecordType !== 'All') {
            const option = (this.recordTypeOptions || []).find((item) => item.value === this.accountRecordType);
            chips.push({ key: 'type', label: option?.label || 'Type filter' });
        }
        if (this.accountSpecialty !== 'All') {
            const option = (this.specialtyOptions || []).find((item) => item.value === this.accountSpecialty);
            chips.push({ key: 'specialty', label: option?.label || 'Specialty filter' });
        }
        if (this.accountClassification !== 'All') {
            const option = (this.classificationOptions || []).find(
                (item) => item.value === this.accountClassification
            );
            chips.push({ key: 'classification', label: option?.label || 'Class filter' });
        }
        if (this.accountBrick148 !== 'All') {
            const option = (this.brick148FilterOptions || []).find((item) => item.value === this.accountBrick148);
            chips.push({ key: 'brick148', label: option?.label || '148 brick' });
        }
        if (this.accountBrick702 !== 'All') {
            const option = (this.brick702FilterOptions || []).find((item) => item.value === this.accountBrick702);
            chips.push({ key: 'brick702', label: option?.label || '702 brick' });
        }
        if (this.accountBrick !== 'All' && this.accountBrick148 === 'All' && this.accountBrick702 === 'All') {
            const option = (this.brickOptions || []).find((item) => item.value === this.accountBrick);
            chips.push({ key: 'brick', label: option?.label || 'Brick filter' });
        }
        if (this.visitCoverage && this.visitCoverage !== 'all') {
            const option = (this.visitCoverageOptions || []).find((item) => item.value === this.visitCoverage);
            chips.push({ key: 'coverage', label: option?.label || 'Visit status' });
        }
        return chips;
    }

    get promoEndLabel() {
        if (!this.pendingSlotStart) {
            return '';
        }
        const end = new Date(this.pendingSlotStart.getTime() + DEFAULT_PROMO_MINUTES * 60000);
        return formatTime(end);
    }

    get isPromoSaveDisabled() {
        return this.isSaving || !this.promoProjectId || !(this.promoTitle || '').trim();
    }

    get totSubmitDisabled() {
        return this.isSaving || Boolean(this.validateTotFormState());
    }

    get displayAccounts() {
        const sourceAccounts = this.isCollectionView
            ? this.selectedCollection?.accounts || []
            : this.accounts || [];
        const coverageFilter = this.visitCoverage || 'all';
        const brickFilters = this.getAccountFilters();
        return sourceAccounts
            .map((account) => {
                const decorated = this.decorateAccountForDisplay(account);
                const coverage = this.getAccountVisitCoverage(decorated.id);
                const coverageLabel = this.visitCoverageLabel(coverage);
                return {
                    ...decorated,
                    visitCoverage: coverage,
                    coverageLabel,
                    coverageBadgeClass: `account-coverage-badge account-coverage-${coverage}`,
                    chipClass: `account-chip account-chip-${coverage}${
                        this.touchDragState?.accountId === decorated.id && this.touchDragState?.active
                            ? ' is-touch-dragging'
                            : ''
                    }`,
                    chipTitle:
                        coverage === 'none'
                            ? 'No visit this week — drag onto the calendar'
                            : coverage === 'draft'
                              ? 'Has a draft visit — open to submit'
                              : 'Open scheduled visit'
                };
            })
            .filter(
                (account) =>
                    this.accountMatchesVisitCoverage(account.visitCoverage, coverageFilter) &&
                    accountMatchesBrickFilters(account, brickFilters)
            )
            .sort((a, b) => {
                const rank = (coverage) => {
                    if (coverage === 'none') return 0;
                    if (coverage === 'draft') return 1;
                    if (coverage === 'submitted') return 2;
                    return 3;
                };
                const byCoverage = rank(a.visitCoverage) - rank(b.visitCoverage);
                if (byCoverage !== 0) {
                    return byCoverage;
                }
                return String(a.name || '').localeCompare(String(b.name || ''));
            });
    }

    get visitCoverageOptions() {
        return [
            { label: 'All accounts', value: 'all' },
            { label: 'No visit this week', value: 'none' },
            { label: 'Draft', value: 'draft' },
            { label: 'Scheduled / submitted', value: 'scheduled' }
        ];
    }

    get draftSubmitBannerLabel() {
        const count = this.draftPlannedVisits.length;
        const ready =
            count === 1 ? '1 draft visit is ready to send for approval.' : `${count} draft visits are ready to send for approval.`;
        if (!this.showWeeklyTargetGap) {
            return ready;
        }
        return `${ready} ${this.weeklyTargetGapLabel}`;
    }

    getAccountVisitCoverage(accountId) {
        const visits = this.findVisitsForAccount(accountId);
        if (!visits.length) {
            return 'none';
        }
        if (visits.some((visit) => visit.status === VISIT_STATUS_DRAFT)) {
            return 'draft';
        }
        if (visits.some((visit) => visit.status === VISIT_STATUS_SUBMITTED)) {
            return 'submitted';
        }
        return 'scheduled';
    }

    visitCoverageLabel(coverage) {
        if (coverage === 'none') {
            return 'No visit';
        }
        if (coverage === 'draft') {
            return 'Draft';
        }
        if (coverage === 'submitted') {
            return 'Submitted';
        }
        if (coverage === 'scheduled') {
            return 'Scheduled';
        }
        return '';
    }

    accountMatchesVisitCoverage(coverage, filter) {
        if (!filter || filter === 'all') {
            return true;
        }
        if (filter === 'none') {
            return coverage === 'none';
        }
        if (filter === 'draft') {
            return coverage === 'draft';
        }
        if (filter === 'scheduled') {
            return coverage === 'scheduled' || coverage === 'submitted';
        }
        return true;
    }

    get hasRouteAlternatives() {
        return (this.routeAlternatives || []).length > 1;
    }

    get hasVisitSuggestions() {
        return (this.visitSuggestions || []).length > 0;
    }

    get arrivalSummaryLabel() {
        const statuses = this.arrivalStatuses || [];
        const early = statuses.filter((s) => s.status === 'early').length;
        const onTime = statuses.filter((s) => s.status === 'on_time').length;
        const late = statuses.filter((s) => s.status === 'late').length;
        return `${onTime} on time · ${early} early · ${late} late`;
    }

    get routeAlternativeRadioOptions() {
        return (this.routeAlternatives || []).map((alt) => ({
            label: `${alt.label} · ${alt.durationMin} min · ${alt.distanceKm} km`,
            value: alt.id
        }));
    }

    get accountChipDraggable() {
        if (this.isReadOnlyPlannerView) {
            return 'false';
        }
        // On touch / coarse-pointer devices the native HTML5 draggable attribute
        // hijacks the gesture (starts a native drag, swallows touchmove), so the
        // custom touch-drag never activates. Disable it there and let the touch
        // handlers drive; keep native drag for mouse (fine-pointer) devices.
        if (this.isCoarsePointer) {
            return 'false';
        }
        return 'true';
    }

    get isCoarsePointer() {
        return (
            typeof window !== 'undefined' &&
            typeof window.matchMedia === 'function' &&
            window.matchMedia('(pointer: coarse)').matches
        );
    }

    get hasRouteEstCost() {
        return Boolean(this.routeSummary?.estCost);
    }

    async loadViewerContext() {
        try {
            this.plannerViewerContext = await getPlannerViewerContext();
            this.selectedContextUserId = this.plannerViewerContext?.defaultUserId;
            this.selectedTerritoryId = null;
            console.log('[PlannerDbg] loadViewerContext', {
                viewerMode: this.plannerViewerContext?.viewerMode,
                defaultUserId: this.plannerViewerContext?.defaultUserId,
                selectedContextUserId: this.selectedContextUserId,
                contextUserId: this.contextUserId,
                options: this.plannerViewerContext?.options?.length
            });
            this.updateViewerContextLabel();
            this.loadCollectionsFromStorage();
        } catch (error) {
            console.error('[PlannerDbg] loadViewerContext ERROR', error);
            this.showToast('Planner context failed', this.reduceError(error), 'error');
        }
    }

    async loadFilterOptions() {
        try {
            const options = await getPlannerAccountFilterOptions({ contextUserId: this.contextUserId });
            this.specialtyOptions = options?.specialtyOptions || [{ label: 'All Specialties', value: 'All' }];
            this.classificationOptions =
                options?.classificationOptions || [{ label: 'All Classifications', value: 'All' }];
            this.brickOptions = options?.brickOptions || [{ label: 'All Bricks', value: 'All' }];
            this.brick148Options = options?.brick148Options || [{ label: 'All 148 bricks', value: 'All' }];
            this.brick702Options = options?.brick702Options || [{ label: 'All 702 bricks', value: 'All' }];
            await this.ensureBrickLevelOptions();
            this.syncBrickFilterSelection();
        } catch (error) {
            this.specialtyOptions = [{ label: 'All Specialties', value: 'All' }];
            this.classificationOptions = [{ label: 'All Classifications', value: 'All' }];
            this.brickOptions = [{ label: 'All Bricks', value: 'All' }];
            this.brick148Options = [{ label: 'All 148 bricks', value: 'All' }];
            this.brick702Options = [{ label: 'All 702 bricks', value: 'All' }];
            await this.ensureBrickLevelOptions();
        }
    }

    async ensureBrickLevelOptions() {
        const has148 = (this.brick148Options || []).some((item) => item?.value && item.value !== FILTER_ALL);
        const has702 = (this.brick702Options || []).some((item) => item?.value && item.value !== FILTER_ALL);
        if (has148 && has702) {
            return;
        }
        try {
            const wizard = await getWizardCreateOptions();
            if (!has148) {
                this.brick148Options = [
                    { label: 'All 148 bricks', value: FILTER_ALL },
                    ...(wizard?.bricks148 || []).map((brick) => ({
                        label: brick.label,
                        value: brick.brickId,
                        parentValue: brick.parentBrickId || brick.zoneBrickId || ''
                    }))
                ];
            }
            if (!has702) {
                this.brick702Options = [
                    { label: 'All 702 bricks', value: FILTER_ALL },
                    ...(wizard?.bricks702 || []).map((brick) => ({
                        label: brick.label,
                        value: brick.brickId,
                        parentValue: brick.parentBrickId || ''
                    }))
                ];
            }
        } catch (_error) {
            /* planner filter options remain as returned */
        }
    }

    async loadPromoProjectOptions() {
        try {
            const projects = await getPromotionalProjects({ contextUserId: this.contextUserId });
            this.promoProjectOptions = (projects || []).map((project) => ({
                label: project.label,
                value: project.value
            }));
        } catch (error) {
            this.promoProjectOptions = [];
        }
    }

    updateViewerContextLabel() {
        if (!this.isReadOnlyPlannerView) {
            this.viewerContextLabel = '';
            return;
        }
        const option = this.selectedViewerOption;
        this.viewerContextLabel = option
            ? `Viewing ${option.label}'s planner (read-only)`
            : "Viewing another rep's planner (read-only)";
    }

    async handleContextUserChange(event) {
        this.selectedContextUserId = event.detail.value;
        if (Object.prototype.hasOwnProperty.call(event.detail || {}, 'territoryId')) {
            this.selectedTerritoryId = event.detail.territoryId || null;
        }
        this.updateViewerContextLabel();
        this.resetRouteState();
        await this.loadFilterOptions();
        await this.loadWeek();
        await this.loadAccountsPage(true);
        if (this.isMapView) {
            await this.hydrateMapFromCache();
            await this.renderMap();
            void this.refreshMapCacheInBackground();
        }
    }

    normalizeClassificationCode(raw) {
        if (raw == null || raw === '') {
            return null;
        }
        const key = String(raw).trim().toUpperCase();
        return /^[ABC][123]$/.test(key) ? key : null;
    }

    buildAccountMetaLine(account) {
        const classification = this.normalizeClassificationCode(account.classification);
        return [
            account.recordTypeName,
            account.specialty,
            classification,
            account.brick702Name || account.brick148Name || account.brickName || account.city
        ]
            .filter(Boolean)
            .join(' · ');
    }

    buildAccountFootnote(account) {
        const planned = Math.round(Number(account?.plannedVisits) || 0);
        const completed = Math.round(Number(account?.actualVisits) || 0);
        const target = Math.round(Number(account?.targetVisits) || 0);
        const parts = [];
        const classification = this.normalizeClassificationCode(account?.classification);
        if (classification) {
            parts.push(classification);
        }
        // Always show planned / completed / target so SFE can read the gap at a glance.
        parts.push(`Planned ${planned}`);
        parts.push(`Completed ${completed}`);
        parts.push(`Target ${target}`);
        const pace = (account?.paceStatusLabel || '').trim();
        if (pace && pace !== 'N/A') {
            parts.push(pace);
        } else {
            const status = (account?.frequencyStatus || '').trim();
            if (status) {
                parts.push(status);
            }
        }
        return parts.join(' · ');
    }

    enrichAccountVisitMetrics(account) {
        if (!account?.id) {
            return account;
        }
        const live = (this.accounts || []).find((item) => item.id === account.id);
        if (!live) {
            return account;
        }
        return {
            ...account,
            frequencyStatus: live.frequencyStatus ?? account.frequencyStatus,
            actualVisits: live.actualVisits ?? account.actualVisits,
            targetVisits: live.targetVisits ?? account.targetVisits,
            plannedVisits: live.plannedVisits ?? account.plannedVisits,
            paceStatus: live.paceStatus ?? account.paceStatus,
            paceStatusLabel: live.paceStatusLabel ?? account.paceStatusLabel,
            classification: live.classification ?? account.classification
        };
    }

    decorateAccountForDisplay(account) {
        const enriched = this.enrichAccountVisitMetrics(account);
        const listKind =
            typeof resolveAccountListKind === 'function'
                ? resolveAccountListKind(
                      enriched.recordTypeDeveloperName,
                      enriched.recordTypeName
                  )
                : {
                      kind: 'account',
                      iconName: 'standard:account',
                      label: enriched.recordTypeName || 'Account'
                  };
        return {
            ...enriched,
            metaLine: enriched.metaLine || this.buildAccountMetaLine(enriched),
            footnoteLine: enriched.footnoteLine || this.buildAccountFootnote(enriched),
            typeIconName: listKind.iconName,
            typeIconUrl: accountTypeIconUrl(listKind.kind),
            typeIconClass: `account-type-icon account-type-icon-${listKind.kind}`,
            typeIconLabel: listKind.label
        };
    }

    getAccountFilters() {
        return {
            searchTerm: this.accountSearch,
            recordType: this.accountRecordType,
            specialty: this.accountSpecialty,
            classification: this.accountClassification,
            brickId: this.resolvedBrickFilterId(),
            brick148Id: this.accountBrick148,
            brick702Id: this.accountBrick702,
            brick702Options: this.brick702Options,
            visitCoverage: this.visitCoverage
        };
    }

    resolvedBrickFilterId() {
        if (this.accountBrick702 && this.accountBrick702 !== FILTER_ALL) {
            return this.accountBrick702;
        }
        if (this.accountBrick148 && this.accountBrick148 !== FILTER_ALL) {
            return this.accountBrick148;
        }
        if (this.accountBrick && this.accountBrick !== FILTER_ALL) {
            return this.accountBrick;
        }
        return null;
    }

    accountSearchParams(offset, pageSize) {
        return {
            searchTerm: this.accountSearch || null,
            recordTypeDeveloperName: this.accountRecordType,
            specialty: this.accountSpecialty === 'All' ? null : this.accountSpecialty,
            classification: this.accountClassification === 'All' ? null : this.accountClassification,
            brickId: this.resolvedBrickFilterId(),
            brick148Id: this.accountBrick148 === 'All' ? null : this.accountBrick148,
            brick702Id: this.accountBrick702 === 'All' ? null : this.accountBrick702,
            offset,
            pageSize,
            contextUserId: this.contextUserId
        };
    }

    toApexAccountSearchParams(offset, pageSize) {
        const params = this.accountSearchParams(offset, pageSize);
        return {
            searchTerm: params.searchTerm,
            recordTypeDeveloperName: params.recordTypeDeveloperName,
            specialty: params.specialty,
            classification: params.classification,
            brickId: params.brickId,
            offset: params.offset,
            pageSize: params.pageSize,
            contextUserId: params.contextUserId
        };
    }

    syncBrickFilterSelection() {
        const allowed148 = new Set((this.brick148FilterOptions || []).map((item) => String(item.value)));
        if (this.accountBrick148 !== FILTER_ALL && !allowed148.has(String(this.accountBrick148))) {
            this.accountBrick148 = FILTER_ALL;
        }
        const allowed702 = new Set((this.brick702FilterOptions || []).map((item) => String(item.value)));
        if (this.accountBrick702 !== FILTER_ALL && !allowed702.has(String(this.accountBrick702))) {
            this.accountBrick702 = FILTER_ALL;
        }
        this.accountBrick = this.resolvedBrickFilterId() || FILTER_ALL;
    }

    handleClearAccountFilters() {
        this.accountSearch = '';
        this.accountRecordType = 'All';
        this.accountSpecialty = 'All';
        this.accountClassification = 'All';
        this.accountBrick = 'All';
        this.accountBrick148 = 'All';
        this.accountBrick702 = 'All';
        this.visitCoverage = 'all';
        this.loadAccountsPage(true);
        if (this.isMapView) {
            this.focusMapOnFilteredAccounts();
        }
    }

    handleVisitCoverageChange(event) {
        this.visitCoverage = event.detail.value || 'all';
        if (this.isMapView) {
            this.focusMapOnFilteredAccounts();
        }
    }

    handleToggleAccountFilters() {
        this.showAccountFilterPanel = !this.showAccountFilterPanel;
        if (this.showAccountFilterPanel) {
            this.showPlanningPalettePanel = false;
            this.showLegendPanel = false;
        }
    }

    handleCloseAccountFilters() {
        this.showAccountFilterPanel = false;
    }

    handleTogglePlanningPalette() {
        if (this.isReadOnlyPlannerView) {
            return;
        }
        this.showPlanningPalettePanel = !this.showPlanningPalettePanel;
        if (this.showPlanningPalettePanel) {
            this.showAccountFilterPanel = false;
            this.showLegendPanel = false;
        }
    }

    handleClosePlanningPalette() {
        this.showPlanningPalettePanel = false;
    }

    handleToggleLegend() {
        this.showLegendPanel = !this.showLegendPanel;
        if (this.showLegendPanel) {
            this.showAccountFilterPanel = false;
            this.showPlanningPalettePanel = false;
        }
    }

    handleCloseLegend() {
        this.showLegendPanel = false;
    }

    stopLegendPanelClick(event) {
        event.stopPropagation();
    }

    getCollectionsStorageKey() {
        return this.collectionsStorageUserId;
    }

    loadCollectionsFromStorage() {
        this.accountCollections = loadAccountCollections(this.collectionsStorageUserId);
        if (
            this.selectedCollectionId &&
            !this.accountCollections.some((item) => item.id === this.selectedCollectionId)
        ) {
            this.selectedCollectionId = null;
            this.listViewMode = LIST_MODE_ALL;
        }
    }

    saveCollectionsToStorage() {
        const saved = saveAccountCollections(this.collectionsStorageUserId, this.accountCollections);
        if (!saved) {
            this.showToast('Save failed', 'Could not save account lists on this device.', 'error');
        }
    }

    snapshotAccountForCollection(account) {
        if (!account?.id) {
            return null;
        }
        return {
            id: account.id,
            name: account.name,
            metaLine: account.metaLine || this.buildAccountMetaLine(account),
            footnoteLine: account.footnoteLine || this.buildAccountFootnote(account),
            frequencyStatus: account.frequencyStatus,
            actualVisits: account.actualVisits,
            targetVisits: account.targetVisits,
            plannedVisits: account.plannedVisits,
            paceStatus: account.paceStatus,
            paceStatusLabel: account.paceStatusLabel,
            recordTypeDeveloperName: account.recordTypeDeveloperName,
            recordTypeName: account.recordTypeName,
            specialty: account.specialty,
            classification: account.classification,
            brickId: account.brickId,
            brickName: account.brickName,
            brick148Id: account.brick148Id,
            brick148Name: account.brick148Name,
            brick702Id: account.brick702Id,
            brick702Name: account.brick702Name,
            city: account.city
        };
    }

    resolveAccountById(accountId, fallbackAccount) {
        if (fallbackAccount?.id === accountId) {
            return fallbackAccount;
        }
        return (
            (this.accounts || []).find((item) => item.id === accountId) ||
            (this.accountCollections || [])
                .flatMap((collection) => collection.accounts || [])
                .find((item) => item.id === accountId) ||
            (this.mapAccounts || []).find((item) => item.id === accountId) ||
            null
        );
    }

    handleShowAllAccounts() {
        this.listViewMode = LIST_MODE_ALL;
        this.selectedCollectionId = null;
        if (!this.accounts.length && !this.isLoadingAccounts) {
            this.loadAccountsPage(true);
        }
    }

    handleSelectCollection(event) {
        const collectionId = event.currentTarget.dataset.collectionId;
        const collection = (this.accountCollections || []).find((item) => item.id === collectionId);
        if (!collection) {
            return;
        }
        this.selectedCollectionId = collectionId;
        this.listViewMode = LIST_MODE_COLLECTION;
    }

    handleCreateEmptyCollection() {
        if (this.isReadOnlyPlannerView) {
            return;
        }
        const collection = {
            id: `col-${Date.now()}`,
            name: `List ${this.accountCollections.length + 1}`,
            accounts: [],
            filterSnapshot: null,
            createdAt: new Date().toISOString()
        };
        this.accountCollections = [...this.accountCollections, collection];
        this.selectedCollectionId = collection.id;
        this.listViewMode = LIST_MODE_COLLECTION;
        this.saveCollectionsToStorage();
    }

    addAccountToCollection(collectionId, account) {
        const snapshot = this.snapshotAccountForCollection(account);
        if (!snapshot) {
            return;
        }
        let collectionName = '';
        let added = false;
        this.accountCollections = (this.accountCollections || []).map((collection) => {
            if (collection.id !== collectionId) {
                return collection;
            }
            collectionName = collection.name;
            const exists = (collection.accounts || []).some((item) => item.id === snapshot.id);
            if (exists) {
                return collection;
            }
            added = true;
            return {
                ...collection,
                accounts: [...(collection.accounts || []), snapshot]
            };
        });
        if (!added) {
            this.showToast('Already in list', `${snapshot.name} is already in ${collectionName}.`, 'info');
            return;
        }
        this.saveCollectionsToStorage();
        this.showToast('Added to list', `${snapshot.name} added to ${collectionName}.`, 'success');
    }

    handleCollectionDropZoneDragOver(event) {
        if (this.dragPayload?.kind === DRAG_TYPE_ACCOUNT) {
            event.preventDefault();
            event.dataTransfer.dropEffect = 'copy';
            event.currentTarget.classList.add('collection-drop-zone-active');
        }
    }

    handleCollectionDropZoneDrop(event) {
        event.preventDefault();
        event.stopPropagation();
        event.currentTarget.classList.remove('collection-drop-zone-active');
        const payload = this.parseDragPayload(event) || this.dragPayload;
        if (payload?.kind !== DRAG_TYPE_ACCOUNT || !this.selectedCollectionId) {
            return;
        }
        const accountId = payload.accountId || payload.account?.id;
        const account = this.resolveAccountById(accountId, payload.account);
        if (!account) {
            return;
        }
        this.addAccountToCollection(this.selectedCollectionId, account);
        this.dragPayload = undefined;
        this.isDragActive = false;
    }

    handleCollectionChipDragOver(event) {
        if (this.dragPayload?.kind === DRAG_TYPE_ACCOUNT) {
            event.preventDefault();
            event.stopPropagation();
            event.dataTransfer.dropEffect = 'copy';
            event.currentTarget.classList.add('collection-chip-drop-target');
        }
    }

    handleCollectionChipDrop(event) {
        event.preventDefault();
        event.stopPropagation();
        event.currentTarget.classList.remove('collection-chip-drop-target');
        const collectionId = event.currentTarget.dataset.collectionId;
        const payload = this.parseDragPayload(event) || this.dragPayload;
        if (payload?.kind !== DRAG_TYPE_ACCOUNT || !collectionId) {
            return;
        }
        const accountId = payload.accountId || payload.account?.id;
        const account = this.resolveAccountById(accountId, payload.account);
        if (!account) {
            return;
        }
        const previousSelection = this.selectedCollectionId;
        this.addAccountToCollection(collectionId, account);
        if (previousSelection === collectionId) {
            this.selectedCollectionId = collectionId;
            this.listViewMode = LIST_MODE_COLLECTION;
        }
        this.dragPayload = undefined;
        this.isDragActive = false;
    }

    handleDeleteSelectedCollection() {
        if (!this.selectedCollectionId || this.isReadOnlyPlannerView) {
            return;
        }
        this.accountCollections = (this.accountCollections || []).filter(
            (item) => item.id !== this.selectedCollectionId
        );
        this.selectedCollectionId = null;
        this.listViewMode = LIST_MODE_ALL;
        this.saveCollectionsToStorage();
        if (!this.accounts.length && !this.isLoadingAccounts) {
            this.loadAccountsPage(true);
        }
    }

    handleOpenRenameCollectionModal() {
        if (!this.selectedCollectionId || this.isReadOnlyPlannerView) {
            return;
        }
        this.renameCollectionName = this.selectedCollectionName;
        this.showRenameCollectionModal = true;
    }

    handleRenameCollectionNameChange(event) {
        this.renameCollectionName = event.detail.value;
    }

    handleRenameCollectionCancel() {
        this.closePlannerModal(() => {
            this.showRenameCollectionModal = false;
            this.renameCollectionName = '';
        });
    }

    handleRenameCollectionConfirm() {
        const name = (this.renameCollectionName || '').trim();
        if (!name || !this.selectedCollectionId || this.isReadOnlyPlannerView) {
            return;
        }
        const collectionId = this.selectedCollectionId;
        this.accountCollections = (this.accountCollections || []).map((collection) =>
            collection.id === collectionId ? { ...collection, name } : collection
        );
        this.saveCollectionsToStorage();
        this.showRenameCollectionModal = false;
        this.renameCollectionName = '';
        this.showToast('List renamed', `"${name}" is updated.`, 'success');
    }

    handleOpenSaveCollectionModal() {
        this.saveCollectionName = '';
        this.showSaveCollectionModal = true;
    }

    handleSaveCollectionNameChange(event) {
        this.saveCollectionName = event.detail.value;
    }

    handleSaveCollectionCancel() {
        this.closePlannerModal(() => {
            this.showSaveCollectionModal = false;
            this.saveCollectionName = '';
            this.isSavingCollection = false;
        });
    }

    async fetchAllFilteredAccounts() {
        const allAccounts = [];
        let offset = 0;
        let hasMore = true;

        while (hasMore) {
            const result = await searchAccountsPage(this.toApexAccountSearchParams(offset, COLLECTION_FETCH_PAGE_SIZE));
            const pageAccounts = (result?.accounts || []).map((account) =>
                this.snapshotAccountForCollection(this.decorateAccountForDisplay(account))
            );
            await putCachedAccounts(result?.accounts || []);
            allAccounts.push(...pageAccounts.filter(Boolean));
            hasMore = result?.hasMore === true;
            offset += pageAccounts.length;
            if (pageAccounts.length === 0) {
                break;
            }
        }
        return allAccounts;
    }

    async handleSaveCollectionConfirm() {
        const name = (this.saveCollectionName || '').trim();
        if (!name || this.isSavingCollection) {
            return;
        }
        this.isSavingCollection = true;
        try {
            const accounts = await this.fetchAllFilteredAccounts();
            const collection = {
                id: `col-${Date.now()}`,
                name,
                accounts,
                filterSnapshot: this.getAccountFilters(),
                createdAt: new Date().toISOString()
            };
            this.accountCollections = [...this.accountCollections, collection];
            this.selectedCollectionId = collection.id;
            this.listViewMode = LIST_MODE_COLLECTION;
            this.saveCollectionsToStorage();
            this.showSaveCollectionModal = false;
            this.saveCollectionName = '';
            this.showToast(
                'List saved',
                `"${name}" saved with ${accounts.length} account${accounts.length === 1 ? '' : 's'}.`,
                'success'
            );
        } catch (error) {
            this.showToast('Save failed', this.reduceError(error), 'error');
        } finally {
            this.isSavingCollection = false;
        }
    }

    handleFilterPanelClick(event) {
        event.stopPropagation();
    }

    waitForMapMoveEnd(map, timeoutMs = 2500) {
        return new Promise((resolve) => {
            let done = false;
            const finish = () => {
                if (!done) {
                    done = true;
                    map.off('moveend', finish);
                    resolve();
                }
            };
            map.once('moveend', finish);
            window.setTimeout(finish, timeoutMs);
        });
    }

    async ensureCurrentLocation() {
        if (this.currentLocation) {
            return;
        }
        try {
            const cached = await getCachedMapLocation();
            if (cached?.latitude != null && cached?.longitude != null) {
                this.currentLocation = cached;
            }
        } catch (_error) {
            // Cached GPS is optional; the map can still open on account pins.
        }
    }

    async refreshCurrentLocation() {
        try {
            const position = await getCurrentPosition();
            this.currentLocation = position;
            await putCachedMapLocation(position);
        } catch (_error) {
            // Location permission is optional for map display.
        }
    }

    async hydrateMapFromCache() {
        await this.ensureCurrentLocation();
        if ((this.mapAccounts || []).length) {
            return;
        }
        try {
            const cached = await getMapAccountsCache(getUserMapAccountsKey(this.contextUserId || Id));
            if (cached?.length) {
                this.mapAccounts = cached;
            }
        } catch (_error) {
            // First visit has no map cache yet.
        }
    }

    collectMapPrefetchPoints() {
        const points = [];
        if (this.currentLocation) {
            points.push(this.currentLocation);
        }
        (this.orderedRouteStops || []).forEach((stop) => {
            if (stop.latitude != null && stop.longitude != null) {
                points.push(stop);
            }
        });
        const origin = this.currentLocation;
        let accounts = (this.mapAccounts || []).filter(
            (account) => account.latitude != null && account.longitude != null
        );
        if (origin && accounts.length) {
            accounts = accounts.filter(
                (account) =>
                    haversineKm(
                        origin.latitude,
                        origin.longitude,
                        Number(account.latitude),
                        Number(account.longitude)
                    ) <= 18
            );
        }
        accounts.slice(0, 80).forEach((account) => points.push(account));
        return points;
    }

    async prefetchVisibleMapTiles() {
        try {
            await prefetchMapAreaTiles(this.collectMapPrefetchPoints());
        } catch (_error) {
            // Tile prefetch is best-effort; live OSM still works.
        }
    }

    async refreshMapCacheInBackground() {
        await Promise.all([this.refreshCurrentLocation(), this.loadMapAccounts()]);
        if (this.isMapView && this.mapInstance) {
            this.plotStopsOnMap(
                this.orderedRouteStops,
                Boolean(this.currentLocation),
                this.unplannedMapAccounts
            );
        }
        void this.prefetchVisibleMapTiles();
    }

    async warmMapCache() {
        try {
            await this.hydrateMapFromCache();
            await this.ensureLeaflet();
            await this.prefetchVisibleMapTiles();
            void this.refreshMapCacheInBackground();
        } catch (_error) {
            // Warming must never block planner.
        }
    }

    getRouteViewportPoints() {
        const points = [];
        if (this.currentLocation) {
            points.push([this.currentLocation.latitude, this.currentLocation.longitude]);
        }
        this.orderedRouteStops.forEach((stop) => {
            if (stop.latitude != null && stop.longitude != null) {
                points.push([stop.latitude, stop.longitude]);
            }
        });
        return points;
    }

    applyInitialMapViewport() {
        if (!this.mapInstance) {
            return;
        }
        const points = this.getRouteViewportPoints();
        if (!points.length) {
            this.mapInstance.setView([30.0444, 31.2357], 6);
            return;
        }
        if (points.length === 1) {
            this.mapInstance.setView(points[0], 15);
            return;
        }
        const bounds = window.L.latLngBounds(points);
        this.mapInstance.fitBounds(bounds.pad(0.2), { maxZoom: 14 });
    }

    async flyToLocation(lat, lng, zoom = 15) {
        if (!this.mapInstance || lat == null || lng == null) {
            return;
        }
        const token = ++this.flyAnimationToken;
        const map = this.mapInstance;
        const currentZoom = map.getZoom();
        const center = map.getCenter();
        map.flyTo(center, Math.max(currentZoom - 2, 9), { duration: 0.9 });
        await this.waitForMapMoveEnd(map);
        if (token !== this.flyAnimationToken) {
            return;
        }
        map.flyTo([lat, lng], zoom, { duration: 1.1 });
        await this.waitForMapMoveEnd(map);
    }

    async focusMapOnFilteredAccounts() {
        if (!this.isMapView || !this.mapInstance || this.isDragActive) {
            return;
        }
        const filters = this.getAccountFilters();
        const matches = (this.mapAccounts || []).filter(
            (account) =>
                account.latitude != null &&
                account.longitude != null &&
                accountMatchesFilters(account, filters)
        );
        this.plotStopsOnMap(
            this.orderedRouteStops,
            Boolean(this.currentLocation),
            this.unplannedMapAccounts
        );
        if (matches.length === 0) {
            this.showToast('No matches', 'No geocoded accounts match your filters.', 'info');
            return;
        }
        if (matches.length === 1) {
            await this.flyToLocation(matches[0].latitude, matches[0].longitude);
            return;
        }
        const bounds = window.L.latLngBounds(matches.map((a) => [a.latitude, a.longitude]));
        const map = this.mapInstance;
        map.flyTo(bounds.getCenter(), Math.max(map.getZoom() - 2, 9), { duration: 0.9 });
        await this.waitForMapMoveEnd(map);
        map.fitBounds(bounds.pad(0.15), { maxZoom: 14, animate: true, duration: 1.0 });
    }

    handleSpecialtyChange(event) {
        this.accountSpecialty = event.detail.value;
        this.loadAccountsPage(true);
        if (this.isMapView) {
            this.focusMapOnFilteredAccounts();
        }
    }

    handleClassificationChange(event) {
        this.accountClassification = event.detail.value;
        this.loadAccountsPage(true);
        if (this.isMapView) {
            this.focusMapOnFilteredAccounts();
        }
    }

    handleBrickChange(event) {
        this.accountBrick = event.detail.value;
        this.loadAccountsPage(true);
        if (this.isMapView) {
            this.focusMapOnFilteredAccounts();
        }
    }

    handleBrick148Change(event) {
        this.accountBrick148 = event.detail.value || FILTER_ALL;
        this.syncBrickFilterSelection();
        this.loadAccountsPage(true);
        if (this.isMapView) {
            this.focusMapOnFilteredAccounts();
        }
    }

    handleBrick702Change(event) {
        this.accountBrick702 = event.detail.value || FILTER_ALL;
        if (this.accountBrick702 !== FILTER_ALL) {
            const selected = (this.brick702Options || []).find(
                (item) => String(item.value) === String(this.accountBrick702)
            );
            if (selected?.parentValue && this.accountBrick148 === FILTER_ALL) {
                this.accountBrick148 = selected.parentValue;
            }
        }
        this.syncBrickFilterSelection();
        this.loadAccountsPage(true);
        if (this.isMapView) {
            this.focusMapOnFilteredAccounts();
        }
    }

    getPlannerContextDateKeys() {
        if (this.isMapView) {
            return new Set([this.mapDayKey]);
        }
        const keys = new Set();
        for (let i = 0; i < 7; i += 1) {
            keys.add(toDateKey(addDays(this.weekStart, i)));
        }
        return keys;
    }

    findVisitsForAccount(accountId) {
        if (!accountId) {
            return [];
        }
        const contextKeys = this.getPlannerContextDateKeys();
        return (this.visits || [])
            .filter((visit) => {
                if (visit.accountId !== accountId || visit.status === 'Cancelled') {
                    return false;
                }
                const start = parseSalesforceDateTime(visit.startDateTime);
                return start && contextKeys.has(toDateKey(start));
            })
            .sort((a, b) => {
                const startA = parseSalesforceDateTime(a.startDateTime)?.getTime() || 0;
                const startB = parseSalesforceDateTime(b.startDateTime)?.getTime() || 0;
                return startA - startB;
            });
    }

    openVisitPickerModal(matches) {
        this.visitPickerOptions = matches.map((visit) => {
            const start = parseSalesforceDateTime(visit.startDateTime);
            const end = parseSalesforceDateTime(visit.endDateTime);
            const timeLabel =
                start && end
                    ? `${formatDateLabel(start)} ${formatTime(start)} – ${formatTime(end)}`
                    : visit.accountName || visit.name;
            return {
                id: visit.id,
                label: timeLabel,
                status: visit.status
            };
        });
        this.showVisitPickerModal = true;
    }

    handleAccountChipClick(event) {
        if (this.suppressVisitClick || this.isDragActive) {
            return;
        }
        const accountId = event.currentTarget.dataset.accountId;
        const matches = this.findVisitsForAccount(accountId);

        if (matches.length === 0) {
            this.showToast(
                'No visit scheduled',
                'Drag this account onto the calendar to schedule a visit first.',
                'info'
            );
            if (this.isMapView) {
                const account =
                    this.mapAccounts.find((item) => item.id === accountId) ||
                    this.resolveAccountById(accountId);
                if (account?.latitude != null && account?.longitude != null) {
                    this.flyToLocation(account.latitude, account.longitude);
                }
            }
            return;
        }

        if (matches.length === 1) {
            const visit = matches[0];
            if (
                visit.status === VISIT_STATUS_DRAFT ||
                visit.status === VISIT_STATUS_SUBMITTED ||
                canSubmitForApproval(visit.visitType, visit.status)
            ) {
                this.openVisitDetailModal(visit);
                return;
            }
            this.navigateToRecord(matches[0].id, 'Visit__c');
            return;
        }

        this.openVisitPickerModal(matches);
    }

    handleVisitPickerSelect(event) {
        const visitId = event.currentTarget.dataset.visitId;
        this.showVisitPickerModal = false;
        this.visitPickerOptions = [];
        if (visitId) {
            this.navigateToRecord(visitId, 'Visit__c');
        }
    }

    handleVisitPickerCancel() {
        this.closePlannerModal(() => {
            this.showVisitPickerModal = false;
            this.visitPickerOptions = [];
        });
    }

    handleRouteStopClick(event) {
        const stopId = event.currentTarget.dataset.stopId;
        if (!stopId || stopId === 'current-location') {
            return;
        }
        this.selectedStopId = stopId;
        const stop = this.orderedRouteStops.find((item) => item.id === stopId);
        if (stop?.id) {
            this.navigateToRecord(stop.id, 'Visit__c');
            return;
        }
        if (stop?.latitude != null && stop?.longitude != null) {
            this.flyToLocation(stop.latitude, stop.longitude);
        }
    }

    scheduleRoutePreviewRefresh() {
        window.clearTimeout(this.routePreviewTimer);
        this.routePreviewTimer = window.setTimeout(() => {
            this.refreshRoutePreview();
        }, ROUTE_PREVIEW_DEBOUNCE_MS);
    }

    async refreshRoutePreview() {
        if (!this.currentLocation || !this.mapInstance || this.isReadOnlyPlannerView) {
            return;
        }
        const visitStops = this.orderedRouteStops;
        if (!visitStops.length) {
            return;
        }
        this.isRefreshingRoutePreview = true;
        try {
            const routes = await fetchOsrmRoute(
                buildCoordPath(this.getRouteCoordinatePoints(visitStops)),
                true
            );
            this.applyRouteResult(routes, visitStops);
            this.routeOrderDirty = true;
        } catch (error) {
            // Keep existing route on preview failure.
        } finally {
            this.isRefreshingRoutePreview = false;
        }
    }

    clearAltRouteLayers() {
        (this.altRouteLayers || []).forEach((layer) => {
            if (this.mapInstance && layer) {
                this.mapInstance.removeLayer(layer);
            }
        });
        this.altRouteLayers = [];
    }

    applyRouteResult(routes, visitStops) {
        const alternatives = buildRouteAlternatives(routes);
        this.routeAlternatives = alternatives;
        if (!alternatives.length) {
            return;
        }
        const selected =
            alternatives.find((item) => item.id === this.selectedRouteId) || alternatives[0];
        this.selectedRouteId = selected.id;
        this.drawSelectedRoute(selected, visitStops);
        this.arrivalStatuses = computeArrivalStatuses(visitStops, selected.legs || []);
        this.computeVisitSuggestions(visitStops, selected);
    }

    drawSelectedRoute(selectedRoute, visitStops) {
        if (!this.mapInstance || !selectedRoute?.geometry) {
            return;
        }
        const coords = selectedRoute.geometry.coordinates.map(([lng, lat]) => [lat, lng]);
        this.clearAltRouteLayers();
        if (this.routeLayer) {
            this.mapInstance.removeLayer(this.routeLayer);
        }
        this.plotStopsOnMap(visitStops, Boolean(this.currentLocation), this.unplannedMapAccounts);
        (this.routeAlternatives || []).forEach((alt) => {
            if (alt.id === selectedRoute.id || !alt.geometry) {
                return;
            }
            const altCoords = alt.geometry.coordinates.map(([lng, lat]) => [lat, lng]);
            const layer = window.L.polyline(altCoords, {
                color: '#5c6bc0',
                weight: 3,
                opacity: 0.45,
                dashArray: '8 6'
            }).addTo(this.mapInstance);
            this.altRouteLayers.push(layer);
        });
        this.routeLayer = window.L.polyline(coords, { color: '#2e7d32', weight: 5, opacity: 0.85 }).addTo(
            this.mapInstance
        );
        this.mapInstance.fitBounds(this.routeLayer.getBounds().pad(0.15));
        this.routeSummary = {
            distanceKm: selectedRoute.distanceKm,
            durationMin: selectedRoute.durationMin,
            estCost: selectedRoute.estCost
        };
    }

    handleRouteAlternativeChange(event) {
        this.selectedRouteId = event.detail.value;
        const selected = (this.routeAlternatives || []).find((item) => item.id === this.selectedRouteId);
        if (selected) {
            this.drawSelectedRoute(selected, this.orderedRouteStops);
            this.arrivalStatuses = computeArrivalStatuses(this.orderedRouteStops, selected.legs || []);
        }
    }

    async computeVisitSuggestions(visitStops, selectedRoute) {
        if (this.isReadOnlyPlannerView) {
            this.visitSuggestions = [];
            return;
        }
        try {
            if (!this.accountVisitTargets?.length) {
                this.accountVisitTargets = await getAccountVisitTargets({ contextUserId: this.contextUserId });
            }
            const plannedIds = new Set(visitStops.map((s) => s.accountId));
            const candidates = (this.accountVisitTargets || []).filter((t) => !plannedIds.has(t.accountId));
            if (!candidates.length || !visitStops.length) {
                this.visitSuggestions = [];
                return;
            }
            const routePoints = this.getRouteCoordinatePoints(visitStops);
            const scored = candidates
                .map((target) => {
                    let minDist = Infinity;
                    for (let i = 0; i < routePoints.length - 1; i++) {
                        const a = routePoints[i];
                        const b = routePoints[i + 1];
                        const d1 = haversineKm(target.latitude, target.longitude, a.latitude, a.longitude);
                        const d2 = haversineKm(target.latitude, target.longitude, b.latitude, b.longitude);
                        const seg = haversineKm(a.latitude, a.longitude, b.latitude, b.longitude);
                        minDist = Math.min(minDist, d1 + d2 - seg);
                    }
                    return { target, minDist };
                })
                .sort((a, b) => a.minDist - b.minDist)
                .slice(0, 5);
            this.visitSuggestions = scored.map(({ target, minDist }, index) => {
                const detourMin = Math.max(1, Math.round((minDist / 40) * 60));
                const insertIndex = index % Math.max(visitStops.length, 1);
                let placementLabel = 'On the way';
                if (insertIndex === 0) {
                    placementLabel = 'Visit before your first stop';
                } else if (insertIndex >= visitStops.length - 1) {
                    placementLabel = 'Visit after your last stop';
                } else if (detourMin > DETOUR_ON_WAY_MAX_MIN) {
                    placementLabel = `Between stops ${insertIndex}–${insertIndex + 1}`;
                }
                return {
                    id: target.accountId,
                    accountId: target.accountId,
                    accountName: target.accountName,
                    placementLabel,
                    detourMin,
                    insertIndex,
                    visitGapLabel: `${target.actualVisits || 0}/${target.targetVisitFrequency || 0} visits this cycle`,
                    frequencyStatus: target.frequencyStatus
                };
            });
        } catch (error) {
            this.visitSuggestions = [];
        }
    }

    handleAddSuggestionToRoute(event) {
        if (this.isReadOnlyPlannerView) {
            return;
        }
        const accountId = event.currentTarget.dataset.accountId;
        const suggestion = this.visitSuggestions.find((item) => item.accountId === accountId);
        if (!suggestion) {
            return;
        }
        this.showToast('Suggestion added', `${suggestion.accountName} noted for your route.`, 'success');
    }

    handlePlanSuggestionVisit(event) {
        if (this.isReadOnlyPlannerView) {
            return;
        }
        const accountId = event.currentTarget.dataset.accountId;
        const suggestion = (this.visitSuggestions || []).find((item) => item.accountId === accountId);
        this.primeVisitAccount(accountId, suggestion);
        this.pendingSlotStart = new Date();
        this.pendingSlotStart.setMinutes(0, 0, 0);
        this.showVisitModal = true;
    }

    getSelectedRoute() {
        return (
            (this.routeAlternatives || []).find((item) => item.id === this.selectedRouteId) ||
            this.routeAlternatives[0]
        );
    }

    get isCalendarView() {
        return this.viewMode === 'calendar';
    }

    get isMapView() {
        return this.viewMode === 'map';
    }

    get calendarSwitchClass() {
        return `view-mode-switch__btn${this.isCalendarView ? ' is-active' : ''}`;
    }

    get mapSwitchClass() {
        return `view-mode-switch__btn${this.isMapView ? ' is-active' : ''}`;
    }

    get weekEnd() {
        return addDays(this.weekStart, 6);
    }

    get weekLabel() {
        const end = this.weekEnd;
        return `${formatDateLabel(this.weekStart)} – ${formatDateLabel(end)}`;
    }

    get draftPlannedVisits() {
        const seen = new Set();
        return (this.visits || []).filter((visit) => {
            if (!visit?.id || seen.has(visit.id)) {
                return false;
            }
            if (visit.status !== VISIT_STATUS_DRAFT) {
                return false;
            }
            if (visit.visitType && !isPlannedVisitType(visit.visitType)) {
                return false;
            }
            seen.add(visit.id);
            return true;
        });
    }

    get plannedCallCount() {
        const seen = new Set();
        let count = 0;
        (this.visits || []).forEach((visit) => {
            if (!visit?.accountId || visit.status === VISIT_STATUS_CANCELLED) {
                return;
            }
            if (visit.id && seen.has(visit.id)) {
                return;
            }
            if (visit.id) {
                seen.add(visit.id);
            }
            count += 1;
        });
        return count;
    }

    get weeklyTargetCount() {
        return Number(this.weekForecast?.weeklyTarget) || 0;
    }

    get additionalCallsNeeded() {
        if (!this.weeklyTargetCount) {
            return 0;
        }
        return Math.max(0, this.weeklyTargetCount - this.plannedCallCount);
    }

    get showWeeklyTargetGap() {
        return !this.isReadOnlyPlannerView && this.additionalCallsNeeded > 0;
    }

    get weeklyTargetGapLabel() {
        const needed = this.additionalCallsNeeded;
        if (!needed) {
            return '';
        }
        const target = this.weeklyTargetCount;
        const planned = this.plannedCallCount;
        return `Weekly target ${target}: ${planned} planned, ${needed} more call${needed === 1 ? '' : 's'} needed. You can still submit.`;
    }

    get canSubmitWeek() {
        return !this.isReadOnlyPlannerView && this.draftPlannedVisits.length > 0;
    }

    get isSubmitWeekDisabled() {
        return !this.canSubmitWeek || this.isSaving;
    }

    get submitWeekLabel() {
        const count = this.draftPlannedVisits.length;
        return count > 0 ? `Submit week (${count})` : 'Submit week';
    }

    holidayKeySet() {
        return new Set((this.publicHolidayDates || []).map((value) => String(value).slice(0, 10)));
    }

    isPublicHolidayDate(date) {
        return this.holidayKeySet().has(toDateKey(date));
    }

    isBlockedPlannerDay(date) {
        return this.isPlannerNonWorkingDay(date) || this.isPublicHolidayDate(date);
    }

    /** Working days come from Planner Rules (org, line, title or user level) so the calendar matches the server. */
    isPlannerNonWorkingDay(date) {
        if (!date) {
            return false;
        }
        const days = this.plannerWorkingDays;
        if (Array.isArray(days) && days.length) {
            const day = date instanceof Date ? date.getDay() : new Date(date).getDay();
            return !days.includes(day);
        }
        return isNonWorkingDay(date);
    }

    applyPlannerRules(source) {
        const days = Array.isArray(source?.workingDayNumbers)
            ? source.workingDayNumbers.map(Number).filter((d) => d >= 0 && d <= 6)
            : [];
        if (days.length) {
            this.plannerWorkingDays = days;
            setWorkingDays(days);
        }
        this.plannerPolicies = {
            weekend: source?.weekendPolicy || this.plannerPolicies?.weekend || 'Block',
            visitHoliday: source?.visitHolidayPolicy || this.plannerPolicies?.visitHoliday || 'Block',
            meetingHoliday: source?.meetingHolidayPolicy || this.plannerPolicies?.meetingHoliday || 'Warn'
        };
    }

    get workingDaysLabel() {
        const names = ['Sunday', 'Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday'];
        const order = [6, 0, 1, 2, 3, 4, 5];
        const active = order.filter((d) => !this.isPlannerNonWorkingDay(new Date(2026, 0, 3 + order.indexOf(d))));
        if (!active.length) {
            return 'on working days';
        }
        const first = order.indexOf(active[0]);
        const contiguous = active.every((d, i) => order.indexOf(d) === first + i);
        if (contiguous && active.length > 1) {
            return `${names[active[0]]} through ${names[active[active.length - 1]]}`;
        }
        return active.map((d) => names[d]).join(', ');
    }

    /**
     * Day check before planning on the calendar. Block refuses here; Warn asks (meetings) or lets
     * the server ask (visits); Allow carries on. Returns false when planning should stop.
     */
    async confirmPlannerDay(start, kind) {
        const policies = this.plannerPolicies || {};
        const isMeeting = kind === DRAG_TYPE_MEETING;
        if (this.isPlannerNonWorkingDay(start)) {
            const policy = policies.weekend || 'Block';
            if (policy === 'Block') {
                this.showToast(
                    'Non-working day',
                    `${isMeeting ? 'Meetings' : 'Visits'} can only be planned ${this.workingDaysLabel}.`,
                    'error'
                );
                return false;
            }
            if (policy === 'Warn' && isMeeting) {
                const ok = await LightningConfirm.open({
                    label: 'Non-working day',
                    message: 'This day is a weekend for your team. Plan the meeting anyway?',
                    theme: 'warning'
                });
                if (!ok) {
                    return false;
                }
            }
        }
        if (this.isPublicHolidayDate(start)) {
            const policy = isMeeting ? policies.meetingHoliday || 'Warn' : policies.visitHoliday || 'Block';
            if (policy === 'Block') {
                this.showToast(
                    'Public holiday',
                    isMeeting
                        ? 'Meetings cannot be planned on a public holiday.'
                        : 'Visits cannot be scheduled on a public holiday.',
                    'error'
                );
                return false;
            }
            if (policy === 'Warn' && isMeeting) {
                const ok = await LightningConfirm.open({
                    label: 'Public holiday',
                    message: 'This day is a public holiday. Plan the meeting anyway?',
                    theme: 'warning'
                });
                if (!ok) {
                    return false;
                }
            }
        }
        return true;
    }

    get weekDays() {
        const todayKey = toDateKey(new Date());
        const holidays = this.holidayKeySet();
        return Array.from({ length: 7 }, (_, index) => {
            const date = addDays(this.weekStart, index);
            const key = toDateKey(date);
            const isToday = key === todayKey;
            const isWeekend = this.isPlannerNonWorkingDay(date);
            const isHoliday = holidays.has(key);
            const isBlocked = isWeekend || isHoliday;
            return {
                key,
                label: date.toLocaleDateString([], { weekday: 'short' }),
                dateLabel: formatDateLabel(date),
                holidayLabel: isHoliday ? 'Public holiday' : '',
                headerClass: `calendar-header-cell${isToday ? ' is-today' : ''}${isHoliday ? ' is-holiday' : ''}${isWeekend ? ' is-weekend' : ''}`,
                isWeekend,
                isHoliday,
                isBlocked
            };
        });
    }

    get mapDayOptions() {
        return this.weekDays.map((day) => ({
            label: `${day.label} ${day.dateLabel}`,
            value: day.key
        }));
    }

    get totalMinutes() {
        return (DAY_END_HOUR - DAY_START_HOUR) * 60;
    }

    get gridStyle() {
        const heightPx =
            CALENDAR_HEADER_HEIGHT +
            this.totalMinutes * PX_PER_MINUTE +
            CALENDAR_DAY_END_MARKER_HEIGHT;
        return `height:${heightPx}px`;
    }

    get timeRows() {
        const rows = [];
        for (let hour = DAY_START_HOUR; hour < DAY_END_HOUR; hour++) {
            for (let slot = 0; slot < 60; slot += SLOT_MINUTES) {
                const minutes = (hour - DAY_START_HOUR) * 60 + slot;
                const label =
                    slot === 0
                        ? new Date(2000, 0, 1, hour, 0).toLocaleTimeString([], {
                              hour: 'numeric',
                              minute: '2-digit'
                          })
                        : '';
                rows.push({
                    key: `${hour}-${slot}`,
                    label,
                    gutterClass: 'time-gutter',
                    isDayEnd: false,
                    style: `height:${SLOT_MINUTES * PX_PER_MINUTE}px`,
                    dayCells: this.weekDays.map((day) => ({
                        key: `${day.key}-${hour}-${slot}`,
                        dayKey: day.key,
                        minutes,
                        columnClass: `day-column${day.key === toDateKey(new Date()) ? ' is-today' : ''}${
                            day.isWeekend ? ' is-weekend' : ''
                        }${day.isHoliday ? ' is-holiday' : ''}`,
                        style: `height:${SLOT_MINUTES * PX_PER_MINUTE}px`
                    }))
                });
            }
        }

        const endLabel = new Date(2000, 0, 1, DAY_END_HOUR % 24, 0).toLocaleTimeString([], {
            hour: 'numeric',
            minute: '2-digit'
        });
        rows.push({
            key: 'day-end',
            label: endLabel,
            gutterClass: 'time-gutter day-end-gutter',
            isDayEnd: true,
            style: `height:${CALENDAR_DAY_END_MARKER_HEIGHT}px`,
            dayCells: this.weekDays.map((day) => ({
                key: `${day.key}-day-end`,
                dayKey: day.key,
                minutes: this.totalMinutes,
                columnClass: `day-column day-end-marker${day.key === toDateKey(new Date()) ? ' is-today' : ''}${
                    day.isWeekend ? ' is-weekend' : ''
                }${day.isHoliday ? ' is-holiday' : ''}`,
                style: `height:${CALENDAR_DAY_END_MARKER_HEIGHT}px`
            }))
        });
        return rows;
    }

    get hasAccounts() {
        return this.displayAccounts.length > 0;
    }

    get emptyAccountsHint() {
        if (this.isLoadingAccounts) {
            return '';
        }
        if (this.totalAccountCount > 0 && this.hasActiveAccountFilters) {
            return 'No accounts match the current filters. Clear filters to see your territory list.';
        }
        if (this.totalAccountCount > 0) {
            return 'Accounts loaded but hidden by view filters. Try clearing filters.';
        }
        return 'No accounts in your territory yet. Check territory alignment or open Accounts tab.';
    }

    get showAccountLoadMore() {
        return !this.isCollectionView && this.hasMoreAccounts && !this.isLoadingAccounts;
    }

    get accountCountLabel() {
        if (this.isCollectionView) {
            const count = this.selectedCollection?.accounts?.length || 0;
            return count === 1 ? '1 account in list' : `${count} accounts in list`;
        }
        const visible = this.displayAccounts.length;
        if (this.totalAccountCount === 0) {
            return '0 accounts';
        }
        if (this.hasActiveAccountFilters && visible !== this.totalAccountCount) {
            return visible === 1
                ? `1 visible of ${this.totalAccountCount}`
                : `${visible} visible of ${this.totalAccountCount}`;
        }
        const shown = this.accounts.length;
        if (shown < this.totalAccountCount) {
            return `Showing 1–${shown} of ${this.totalAccountCount}`;
        }
        return `${this.totalAccountCount} accounts`;
    }

    get accountListStyle() {
        return `--account-list-visible-count:${ACCOUNT_LIST_VISIBLE_COUNT}`;
    }

    get accountSearchDisabled() {
        return this.isCollectionView;
    }

    get accountFiltersDisabled() {
        return this.isCollectionView;
    }

    get calendarEvents() {
        const events = [];
        const outlierIdsByDay = this.calendarOutlierIdsByDayKey;
        (this.visits || []).forEach((visit) => {
            const isPromo = !visit.accountId && visit.zetaProjectId;
            const isLocked = visit.status === 'Completed' || visit.status === 'Cancelled';
            const visitStart = parseSalesforceDateTime(visit.startDateTime);
            const visitDayKey = visitStart ? toDateKey(visitStart) : null;
            const dayOutlierIds = visitDayKey ? outlierIdsByDay[visitDayKey] : null;
            const isRouteOutlier =
                Boolean(visit.accountId) &&
                dayOutlierIds?.has(normalizeSalesforceId(visit.id));
            const statusClass =
                visit.status === VISIT_STATUS_DRAFT
                    ? 'visit draft'
                    : visit.status === VISIT_STATUS_SUBMITTED
                      ? 'visit submitted'
                      : visit.status === VISIT_STATUS_SCHEDULED
                        ? 'visit scheduled'
                        : visit.status === VISIT_STATUS_CANCELLED
                          ? 'visit cancelled'
                          : visit.status === VISIT_STATUS_COMPLETED
                            ? 'visit completed'
                            : 'visit';
            const titlePrefix =
                visit.status === VISIT_STATUS_DRAFT
                    ? 'Draft — '
                    : visit.status === VISIT_STATUS_SUBMITTED
                      ? 'Submitted — '
                      : '';
            const promoTitle = visit.visitObjective || visit.zetaProjectName || 'Promotional Event';
            const event = this.buildPositionedEvent({
                id: visit.id,
                type: 'visit',
                title: isPromo
                    ? `${titlePrefix}Promo — ${promoTitle}`
                    : `${titlePrefix}${visit.accountName || visit.name}`,
                start: visitStart,
                end: parseSalesforceDateTime(visit.endDateTime),
                draggable: !isLocked && !isPromo,
                resizable:
                    !isLocked &&
                    !isPromo &&
                    (visit.status === 'Draft' ||
                        visit.status === 'Submitted' ||
                        visit.status === 'Scheduled'),
                extraClass: isPromo
                    ? 'visit promo'
                    : `${statusClass} theme-${resolveAccountThemeKind(visit.accountRecordTypeDeveloperName, visit.accountRecordTypeName)}${isRouteOutlier ? ' visit-outlier' : ''}`
            });
            if (event) {
                events.push({
                    ...event,
                    isVisit: true,
                    showOutlierWarning: isRouteOutlier
                });
            }
        });

        (this.timeOffBlocks || []).forEach((tot) => {
            const label = tot.typeLabel || tot.typeValue || tot.type || tot.name || tot.Type__c || 'Time Off';
            const startRaw = tot.startDateTime || tot.Start_Date_Time__c || tot.startDate;
            const endRaw = tot.endDateTime || tot.End_Date_Time__c || tot.endDate;

            let startDate = parseSalesforceDateTime(startRaw);
            let endDate = parseSalesforceDateTime(endRaw);

            const isFullDay = tot.isFullDay || tot.spanType === 'Full_Day' || tot.Span_Type__c === 'Full_Day';

            if (isFullDay && startDate) {
                const d = new Date(startDate);
                d.setHours(DAY_START_HOUR, 0, 0, 0);
                startDate = d;
                const e = new Date(startDate);
                e.setHours(DAY_END_HOUR, 0, 0, 0);
                endDate = e;
            } else if (startDate && (!endDate || endDate.getTime() <= startDate.getTime())) {
                const hours = Number(tot.durationHours || 2);
                endDate = new Date(startDate.getTime() + hours * 3600 * 1000);
            }

            const customTimeLabel = isFullDay
                ? 'Full Day'
                : startDate && endDate
                  ? `${formatTime(startDate)} – ${formatTime(endDate)}`
                  : '';
            const stageKind = totStageKind(tot.stage);
            const stagePrefix = plannerStatusTitlePrefix(stageKind);
            const canResizeTot =
                !isFullDay &&
                (stageKind === 'draft' || stageKind === 'submitted') &&
                !this.isReadOnlyPlannerView;

            const event = this.buildPositionedEvent({
                id: tot.id,
                type: 'tot',
                title: `${stagePrefix}TOT — ${label}`,
                start: startDate,
                end: endDate,
                customTimeLabel,
                draggable: false,
                resizable: canResizeTot,
                extraClass: `tot tot-${stageKind}`
            });
            if (event) {
                events.push(event);
            }
        });

        (this.meetings || []).forEach((meeting) => {
            const statusKind = meetingStatusKind(meeting.status);
            const titlePrefix = plannerStatusTitlePrefix(statusKind);
            const typeLabel = meeting.recordTypeLabel || 'Meeting';
            const meetingTitle = meeting.title || meeting.name || typeLabel;
            const event = this.buildPositionedEvent({
                id: meeting.id,
                type: 'meeting',
                title: `${titlePrefix}${typeLabel} — ${meetingTitle}`,
                start: parseSalesforceDateTime(meeting.startDateTime),
                end: parseSalesforceDateTime(meeting.endDateTime),
                draggable: false,
                resizable: false,
                extraClass: `meeting meeting-${statusKind}`
            });
            if (event) {
                events.push(event);
            }
        });

        return events;
    }

    get mapStops() {
        const dayVisits = (this.visits || [])
            .filter((visit) => {
                const start = parseSalesforceDateTime(visit.startDateTime);
                return start && toDateKey(start) === this.mapDayKey;
            })
            .sort((a, b) => new Date(a.startDateTime) - new Date(b.startDateTime));

        return dayVisits.map((visit, index) => {
            const start = parseSalesforceDateTime(visit.startDateTime);
            const end = parseSalesforceDateTime(visit.endDateTime);
            const latitude = coerceGeoCoordinate(visit.accountLatitude);
            const longitude = coerceGeoCoordinate(visit.accountLongitude);
            const hasLocation = latitude != null && longitude != null;
            const pinKind = resolveAccountThemeKind(
                visit.accountRecordTypeDeveloperName,
                visit.accountRecordTypeName
            );
            const metrics = this.resolveAccountById(visit.accountId) || {};
            return {
                id: visit.id,
                accountId: visit.accountId,
                order: index + 1,
                accountName: visit.accountName,
                accountTypeLabel: resolveAccountTypeLabel(pinKind, visit.accountRecordTypeName),
                pinKind,
                status: visit.status,
                visitType: visit.visitType,
                startDateTime: visit.startDateTime,
                endDateTime: visit.endDateTime,
                durationMs: end - start,
                timeLabel: `${formatTime(start)} – ${formatTime(end)}`,
                classification: metrics.classification,
                plannedVisits: metrics.plannedVisits,
                actualVisits: metrics.actualVisits,
                targetVisits: metrics.targetVisits,
                paceStatusLabel: metrics.paceStatusLabel,
                latitude,
                longitude,
                hasLocation
            };
        });
    }

    get visitStopsWithLocation() {
        return this.mapStops.filter((stop) => stop.hasLocation);
    }

    get routableVisitStops() {
        return this.visitStopsWithLocation.filter(
            (stop) => stop.status !== 'Completed' && stop.status !== 'Cancelled'
        );
    }

    get orderedRouteStops() {
        const stopsById = new Map(this.routableVisitStops.map((stop) => [stop.id, stop]));
        const orderIds =
            this.routeVisitOrder?.length > 0
                ? this.routeVisitOrder
                : this.routableVisitStops.map((stop) => stop.id);
        return orderIds.map((id) => stopsById.get(id)).filter(Boolean);
    }

    initializeRouteVisitOrder() {
        this.routeVisitOrder = this.routableVisitStops.map((stop) => stop.id);
    }

    resetRouteState() {
        this.routeVisitOrder = [];
        this.routeOrderDirty = false;
        this.routeOptimization = undefined;
        this.routeSummary = undefined;
        this.currentLocation = undefined;
        this.routeAlternatives = [];
        this.selectedRouteId = 'fastest';
        this.arrivalStatuses = [];
        this.visitSuggestions = [];
        this.proposedStops = [];
        this.clearAltRouteLayers();
    }

    get plannedAccountIdsForMapDay() {
        return new Set(
            (this.visits || [])
                .filter((visit) => {
                    const start = parseSalesforceDateTime(visit.startDateTime);
                    return start && toDateKey(start) === this.mapDayKey && visit.accountId;
                })
                .map((visit) => visit.accountId)
        );
    }

    get unplannedMapAccounts() {
        const plannedIds = this.plannedAccountIdsForMapDay;
        return (this.mapAccounts || [])
            .filter((account) => account.latitude != null && account.longitude != null)
            .filter((account) => !plannedIds.has(account.id))
            .map((account) => {
                const pinKind = resolveAccountThemeKind(
                    account.recordTypeDeveloperName,
                    account.recordTypeName
                );
                return {
                    id: account.id,
                    accountId: account.id,
                    accountName: account.name,
                    accountTypeLabel: resolveAccountTypeLabel(pinKind, account.recordTypeName),
                    pinKind: 'unplanned',
                    latitude: account.latitude,
                    longitude: account.longitude,
                    specialty: account.specialty,
                    specialtyApiValue: account.specialtyApiValue,
                    classification: account.classification,
                    recordTypeDeveloperName: account.recordTypeDeveloperName,
                    recordTypeName: account.recordTypeName,
                    city: account.city,
                    plannedVisits: account.plannedVisits,
                    actualVisits: account.actualVisits,
                    targetVisits: account.targetVisits,
                    paceStatusLabel: account.paceStatusLabel,
                    hasLocation: true,
                    isPlanned: false
                };
            });
    }

    get mapAccountCountLabel() {
        const planned = this.orderedRouteStops.length;
        const total = (this.mapAccounts || []).filter(
            (account) => account.latitude != null && account.longitude != null
        ).length;
        const unplanned = this.unplannedMapAccounts.length;
        if (total === 0) {
            return 'No geocoded accounts in your territory.';
        }
        return `${total} accounts on map · ${planned} planned · ${unplanned} unplanned`;
    }

    get geoAccountStopsForMapDay() {
        return buildGeoStopsFromVisits(this.visits, this.mapDayKey);
    }

    get calendarOutlierIdsByDayKey() {
        const dayKeys = (this.weekDays || []).map((day) => day.key);
        return buildOutlierIdsByDayKey(this.visits, dayKeys);
    }

    get routeOutliers() {
        return detectRouteOutliers(this.geoAccountStopsForMapDay);
    }

    get routeOutlierIds() {
        return new Set(this.routeOutliers.map((item) => normalizeSalesforceId(item.visitId)));
    }

    get hasRouteOutliers() {
        return this.routeOutliers.length > 0;
    }

    get distantStopsSummary() {
        return formatDistantStopsSummary(this.routeOutliers);
    }

    get decoratedRouteOutliers() {
        const canAct = !this.isReadOnlyPlannerView;
        return this.routeOutliers.map((outlier) => ({
            ...outlier,
            canAct
        }));
    }

    get optimizationIdeas() {
        const ideas = [];
        if (this.hasRouteOptimization) {
            ideas.push({
                id: 'route-order-hint',
                type: 'info',
                text: `Reordering stops could save about ${this.routeOptimization.savingsMin} minutes (${this.routeOptimization.savingsKm} km). Apply the suggested order below.`,
                isOutlier: false,
                isInfo: true,
                canAct: false,
                itemClass: 'ideas-item',
                iconName: 'utility:light_bulb',
                iconClass: 'ideas-icon'
            });
        }
        return ideas;
    }

    get hasOptimizationIdeas() {
        return this.optimizationIdeas.length > 0;
    }

    get sidebarRouteStops() {
        const stops = [];
        if (this.currentLocation) {
            stops.push({
                id: 'current-location',
                accountName: 'Current location',
                timeLabel: 'Starting point',
                hasLocation: true,
                isCurrentLocation: true,
                canReorder: false,
                orderLabel: 'You',
                orderClass: 'route-stop-order is-current-location',
                stopClass: 'route-stop is-current-location'
            });
        }
        const visitStops = this.orderedRouteStops;
        const arrivalById = new Map((this.arrivalStatuses || []).map((item) => [item.id, item]));
        const outlierIds = this.routeOutlierIds;
        visitStops.forEach((stop, index) => {
            const arrival = arrivalById.get(stop.id);
            const isSelected = this.selectedStopId === stop.id;
            const stopIdKey = normalizeSalesforceId(stop.id);
            const isOutlier = [...outlierIds].some(
                (id) => normalizeSalesforceId(id) === stopIdKey
            );
            stops.push({
                ...stop,
                isCurrentLocation: false,
                isOutlier,
                canReorder: visitStops.length > 1 && !this.isReadOnlyPlannerView,
                canMutate:
                    !this.isReadOnlyPlannerView && stop.status !== 'Completed' && !isOutlier,
                canMoveUp: index > 0,
                canMoveDown: index < visitStops.length - 1,
                orderLabel: String(this.currentLocation ? index + 1 : index + 1),
                orderClass: `route-stop-order route-stop-order-${stop.pinKind}${
                    isOutlier ? ' route-stop-order-outlier' : ''
                }`,
                stopClass: `route-stop${this.routeOrderDirty ? ' route-stop-dirty' : ''}${
                    isSelected ? ' route-stop-selected' : ''
                }${arrival?.status === 'late' ? ' route-stop-late' : ''}${
                    isOutlier ? ' route-stop-outlier' : ''
                }`,
                arrivalStatusLabel: arrival?.statusLabel,
                arrivalStatusClass: arrival?.statusClass
            });
        });
        return stops;
    }

    get hasMapStops() {
        return this.orderedRouteStops.length > 0;
    }

    get isRouteDisabled() {
        return (
            this.isReadOnlyPlannerView ||
            this.orderedRouteStops.length < 1 ||
            this.isBuildingRoute ||
            this.isUpdatingRoute
        );
    }

    get canOptimizeRoute() {
        return this.orderedRouteStops.length > 1 && !this.isOptimizingRoute && !this.isUpdatingRoute;
    }

    get canUpdateRouteAndCalendar() {
        return (
            this.currentLocation &&
            this.orderedRouteStops.length > 0 &&
            (this.routeOrderDirty || this.routeOptimization) &&
            !this.isUpdatingRoute &&
            !this.isBuildingRoute
        );
    }

    get hasRouteOptimization() {
        return Boolean(this.routeOptimization?.suggestedOrder?.length);
    }

    get optimizeRouteLabel() {
        return this.isOptimizingRoute ? 'Optimizing…' : 'Optimize route';
    }

    get isOptimizeDisabled() {
        return this.isReadOnlyPlannerView || !this.canOptimizeRoute || !this.currentLocation;
    }

    get isUpdateRouteDisabled() {
        return !this.canUpdateRouteAndCalendar;
    }

    get buildRouteLabel() {
        if (this.isBuildingRoute) {
            return 'Locating…';
        }
        if (this.isUpdatingRoute) {
            return 'Updating…';
        }
        return 'Build Route';
    }

    get totTypeOptions() {
        return TOT_TYPES;
    }

    get totSpanOptions() {
        return TOT_SPANS;
    }

    get totDurationOptions() {
        return Array.from({ length: 8 }, (_, index) => {
            const value = String(index + 1);
            return { label: `${value} hour${index === 0 ? '' : 's'}`, value };
        });
    }

    get visitStatusOptions() {
        const visit = (this.visits || []).find((item) => item.id === this.visitDetailId);
        return getVisitStatusOptions(
            visit?.startDateTime,
            visit?.visitType,
            this.visitDetailOriginalStatus || visit?.status
        );
    }

    get visitShowCancellationReason() {
        return this.visitDetailStatus === 'Cancelled';
    }

    get visitDetailReadOnly() {
        return (
            this.isReadOnlyPlannerView ||
            isLockedVisitStatus(this.visitDetailOriginalStatus) ||
            isPendingApprovalStatus(this.visitDetailOriginalStatus)
        );
    }

    get visitDetailCanSubmit() {
        const visit = (this.visits || []).find((item) => item.id === this.visitDetailId);
        return (
            !this.visitDetailReadOnly &&
            canSubmitForApproval(visit?.visitType, this.visitDetailOriginalStatus)
        );
    }

    get visitDetailCanMutate() {
        return !this.visitDetailReadOnly && Boolean(this.visitDetailId);
    }

    get visitDetailCanCoach() {
        return this.isReadOnlyPlannerView && Boolean(this.visitDetailId);
    }

    get visitDetailCanManagerApprove() {
        if (!this.canManageTeamPlans || !this.visitDetailId) {
            return false;
        }
        const visit = (this.visits || []).find((item) => item.id === this.visitDetailId);
        return (
            this.visitDetailOriginalStatus === VISIT_STATUS_SUBMITTED &&
            isPlannedVisitType(visit?.visitType)
        );
    }

    get totIsHoursSpan() {
        return this.totSpanType === 'Hours';
    }

    get totIsFullDaySpan() {
        return this.totSpanType === 'Full_Day';
    }

    get pendingSlotLabel() {
        if (!this.pendingSlotStart) {
            return '';
        }
        return `${formatDateLabel(this.pendingSlotStart)} at ${formatTime(this.pendingSlotStart)}`;
    }

    get visitEndLabel() {
        if (!this.pendingSlotStart) {
            return '';
        }
        const end = new Date(this.pendingSlotStart.getTime() + DEFAULT_VISIT_MINUTES * 60000);
        return formatTime(end);
    }

    resolveSlotFromCoordinates(clientX, clientY) {
        if (clientX == null || clientY == null) {
            return null;
        }
        const canvas = this.template.querySelector('.calendar-canvas');
        if (!canvas) {
            return null;
        }
        const rect = canvas.getBoundingClientRect();
        const TIME_GUTTER_PX = 56;
        const xRel = clientX - rect.left - TIME_GUTTER_PX;
        const totalGridWidth = rect.width - TIME_GUTTER_PX;
        const days = this.weekDays || [];
        if (days.length === 0 || totalGridWidth <= 0 || xRel < 0) {
            return null;
        }
        const dayWidth = totalGridWidth / days.length;
        const dayIndex = Math.min(Math.max(0, Math.floor(xRel / dayWidth)), days.length - 1);
        const day = days[dayIndex];
        if (!day?.key) {
            return null;
        }

        const yRel = clientY - rect.top - CALENDAR_HEADER_HEIGHT;
        const rawMinutes = Math.max(0, yRel / PX_PER_MINUTE);
        const slotMinutes = Math.min(
            Math.floor(rawMinutes / SLOT_MINUTES) * SLOT_MINUTES,
            this.totalMinutes - SLOT_MINUTES
        );
        if (Number.isNaN(slotMinutes)) {
            return null;
        }
        return this.minutesToDate(day.key, slotMinutes);
    }

    resolveSlotFromEvent(event) {
        const slot = event.target?.closest?.('[data-day-key][data-minutes]');
        if (slot) {
            const dayKey = slot.dataset.dayKey;
            const minutes = Number(slot.dataset.minutes);
            if (dayKey && !Number.isNaN(minutes)) {
                return this.minutesToDate(dayKey, minutes);
            }
        }
        const clientX = event.clientX;
        const clientY = event.clientY;
        if (clientX != null && clientY != null) {
            const pointSlot = this.findCalendarSlotAtPoint(clientX, clientY);
            if (pointSlot) {
                const dayKey = pointSlot.dataset.dayKey;
                const minutes = Number(pointSlot.dataset.minutes);
                if (dayKey && !Number.isNaN(minutes)) {
                    return this.minutesToDate(dayKey, minutes);
                }
            }
            return this.resolveSlotFromCoordinates(clientX, clientY);
        }
        return null;
    }

    parseDragPayload(event) {
        if (this.dragPayload) {
            return this.dragPayload;
        }
        try {
            const raw = event.dataTransfer?.getData('application/json');
            if (raw) {
                return JSON.parse(raw);
            }
        } catch (error) {
            // Fall through to text payload parsing.
        }
        const text = event.dataTransfer?.getData('text/plain');
        if (!text) {
            return null;
        }
        if (text === DRAG_TYPE_TOT) {
            return { kind: DRAG_TYPE_TOT };
        }
        if (text === DRAG_TYPE_PROMO) {
            return { kind: DRAG_TYPE_PROMO };
        }
        if (text === DRAG_TYPE_MEETING) {
            return { kind: DRAG_TYPE_MEETING };
        }
        const account = this.resolveAccountById(text);
        if (account) {
            return { kind: DRAG_TYPE_ACCOUNT, accountId: account.id, account };
        }
        const visit = this.visits.find((item) => item.id === text);
        if (visit) {
            return {
                kind: DRAG_TYPE_EVENT,
                visit,
                durationMs:
                    parseSalesforceDateTime(visit.endDateTime) -
                    parseSalesforceDateTime(visit.startDateTime)
            };
        }
        return null;
    }

    buildPositionedEvent(config) {
        const { start, end } = config;
        if (!start || !end) {
            return null;
        }
        const dayKey = toDateKey(start);
        const dayIndex = this.weekDays.findIndex((day) => day.key === dayKey);
        if (dayIndex < 0) {
            return null;
        }

        const dayStart = new Date(start);
        dayStart.setHours(DAY_START_HOUR, 0, 0, 0);
        const rawTopMinutes = (start - dayStart) / 60000;
        const rawDurationMinutes = Math.max((end - start) / 60000, SLOT_MINUTES / 2);
        const rawEndMinutes = rawTopMinutes + rawDurationMinutes;

        if (rawEndMinutes <= 0 || rawTopMinutes >= this.totalMinutes) {
            return null;
        }

        const topMinutes = Math.max(0, rawTopMinutes);
        const visibleEndMinutes = Math.min(rawEndMinutes, this.totalMinutes);
        const durationMinutes = Math.max(visibleEndMinutes - topMinutes, SLOT_MINUTES / 2);

        const columnLeft = `calc(3.5rem + ((100% - 3.5rem) / 7) * ${dayIndex} + 0.25rem)`;
        const columnWidth = `calc(((100% - 3.5rem) / 7) - 0.5rem)`;
        const heightPx = durationMinutes * PX_PER_MINUTE;
        const timeLabel = config.customTimeLabel || `${formatTime(start)} – ${formatTime(end)}`;

        return {
            key: `${config.type}-${config.id}`,
            id: config.id,
            type: config.type,
            title: config.title,
            clickHint: `${config.title} · ${timeLabel}`,
            timeLabel,
            compact: heightPx < 45,
            draggable: config.draggable ? 'true' : 'false',
            resizable: config.resizable,
            blockClass: `event-block ${config.extraClass}`,
            style: `top:${CALENDAR_HEADER_HEIGHT + topMinutes * PX_PER_MINUTE}px;left:${columnLeft};width:${columnWidth};height:${heightPx}px`
        };
    }

    async loadWeek() {
        this.isLoading = true;
        this.errorMessage = undefined;
        const cacheKey = `${getUserPlannerCacheKey(Id)}_${toDateKey(this.weekStart)}`;
        try {
            // Always go through the PWA stub: online it hits Salesforce then merges
            // queued visits; offline it reads IndexedDB and never calls Salesforce.
            const payload = await fetchPlannerData({
                weekStart: toApexDate(this.weekStart),
                weekEnd: toApexDate(this.weekEnd),
                contextUserId: this.contextUserId
            });
            // payload can be null if Apex fails mid-migration (e.g. Meeting__c access);
            // never read .visits off a null payload — that blanked the calendar.
            this.visits = payload?.visits || [];
            this.timeOffBlocks = payload?.timeOffBlocks || payload?.timeOff || [];
            this.publicHolidayDates = payload?.publicHolidayDates || [];
            this.applyPlannerRules(payload);
            const weekMeetings = payload?.meetings || [];
            if (isOfflineMode()) {
                this.meetings = weekMeetings;
            } else {
                try {
                    const fetched = await fetchMeetings({
                        weekStart: toApexDate(this.weekStart),
                        weekEnd: toApexDate(this.weekEnd),
                        contextUserId: this.contextUserId,
                        fresh: true
                    });
                    const listed = Array.isArray(fetched) ? fetched : [];
                    this.meetings = listed.length ? listed : weekMeetings;
                } catch (meetingError) {
                    this.meetings = weekMeetings.length ? weekMeetings : this.meetings || [];
                }
            }
            await putPlannerCache(cacheKey, {
                visits: this.visits,
                timeOffBlocks: this.timeOffBlocks,
                meetings: this.meetings,
                publicHolidayDates: this.publicHolidayDates,
                workingDayNumbers: this.plannerWorkingDays,
                weekendPolicy: this.plannerPolicies?.weekend,
                visitHolidayPolicy: this.plannerPolicies?.visitHoliday,
                meetingHolidayPolicy: this.plannerPolicies?.meetingHoliday
            });
            if (this.isMapView) {
                this.resetRouteState();
                this.initializeRouteVisitOrder();
                await this.renderMap();
            }
            if (this.isCalendarView && this.isCurrentWeekDisplayed()) {
                this.scheduleScrollCalendarToNow();
            }
            void this.loadWeekRecommendations();
            void this.refreshPlannerInsights();
        } catch (error) {
            const cached = await getPlannerCache(cacheKey);
            if (cached) {
                this.visits = cached.visits || [];
                this.timeOffBlocks = cached.timeOffBlocks || [];
                this.meetings = cached.meetings || [];
                this.publicHolidayDates = cached.publicHolidayDates || [];
                this.applyPlannerRules(cached);
                this.errorMessage = undefined;
            } else {
                this.errorMessage = this.reduceError(error);
            }
        } finally {
            this.isLoading = false;
        }
    }

    async loadWeekRecommendations() {
        this.isLoadingRecommendations = true;
        try {
            const payload = await getWeeklyPlanRecommendations({
                weekStart: toApexDate(this.weekStart),
                weekEnd: toApexDate(this.weekEnd),
                contextUserId: this.contextUserId
            });
            this.weekForecast = payload?.forecast || null;
            this.weekRecommendations = (payload?.recommendations || []).map((row) => ({
                ...row,
                key: row.accountId,
                gapLabel:
                    row.visitGap != null
                        ? `${row.actualVisits || 0}/${row.targetVisitFrequency || 0} · gap ${row.visitGap}`
                        : row.frequencyStatus || ''
            }));
        } catch (_error) {
            this.weekRecommendations = [];
            this.weekForecast = null;
        } finally {
            this.isLoadingRecommendations = false;
        }
    }

    async refreshPlannerInsights() {
        const lines = [];
        const visits = this.visits || [];
        const byStatus = {};
        visits.forEach((visit) => {
            const status = visit.status || 'Draft';
            byStatus[status] = (byStatus[status] || 0) + 1;
        });
        lines.push(
            `${visits.length} visit(s) this week` +
                (Object.keys(byStatus).length
                    ? ` — ${Object.entries(byStatus)
                          .map(([k, v]) => `${v} ${k}`)
                          .join(', ')}`
                    : '')
        );
        const totCount = (this.timeOffBlocks || []).length;
        if (totCount) {
            lines.push(`${totCount} time-off block(s) on the calendar.`);
        }
        if (this.weekForecast) {
            lines.push(
                `Pace: ${this.weekForecast.paceLabel || '—'} · ${this.weekForecast.dailyFrequency || 0} visits/day over ${
                    this.weekForecast.remainingWorkingDays || 0
                } remaining working days.`
            );
        }
        const uncovered = (this.weekRecommendations || []).filter((row) => !row.plannedThisWeek).slice(0, 3);
        if (uncovered.length) {
            lines.push(
                `Priority to plan: ${uncovered.map((row) => row.accountName).join(', ')}.`
            );
        }
        this.plannerInsightLines = lines.map((text, index) => ({ key: `insight-${index}`, text }));
    }

    get hasWeekRecommendations() {
        return (this.weekRecommendations || []).length > 0;
    }

    get weekForecastLabel() {
        if (!this.weekForecast) {
            return '';
        }
        return `${this.weekForecast.plannedVisitCount || 0} planned · ${
            this.weekForecast.dailyFrequency || 0
        }/day · ${this.weekForecast.paceLabel || ''}`;
    }

    get copyTargetDayOptions() {
        return (this.mapDayOptions || []).filter((opt) => opt.value !== this.mapDayKey);
    }

    get isCopyDayDisabled() {
        return (
            this.isReadOnlyPlannerView ||
            this.isCopyingDay ||
            !this.copyTargetDayKey ||
            this.copyTargetDayKey === this.mapDayKey
        );
    }

    get isCopyPlanDisabled() {
        return this.isReadOnlyPlannerView || this.isSaving || this.isCopyingWeek;
    }

    get copyPlanButtonClass() {
        return `copy-plan-btn${this.showCopyPlanMenu ? ' is-open' : ''}`;
    }

    handleToggleCopyPlanMenu(event) {
        event.stopPropagation();
        if (this.isCopyPlanDisabled) {
            return;
        }
        this.showCopyPlanMenu = !this.showCopyPlanMenu;
        if (this.showCopyPlanMenu) {
            this.bindCopyPlanOutside();
        } else {
            this.unbindCopyPlanOutside();
        }
    }

    bindCopyPlanOutside() {
        this.unbindCopyPlanOutside();
        this._onCopyPlanOutside = (event) => {
            const wrap = this.template.querySelector('.copy-plan-wrap');
            const path = typeof event.composedPath === 'function' ? event.composedPath() : [];
            if (wrap && (wrap.contains(event.target) || path.includes(wrap))) {
                return;
            }
            this.showCopyPlanMenu = false;
            this.unbindCopyPlanOutside();
        };
        window.setTimeout(() => {
            if (this._onCopyPlanOutside) {
                window.addEventListener('click', this._onCopyPlanOutside, true);
            }
        }, 0);
    }

    unbindCopyPlanOutside() {
        if (this._onCopyPlanOutside && typeof window !== 'undefined') {
            window.removeEventListener('click', this._onCopyPlanOutside, true);
        }
        this._onCopyPlanOutside = undefined;
    }

    closeCopyPlanMenu() {
        this.showCopyPlanMenu = false;
        this.unbindCopyPlanOutside();
    }

    async handleCopyPreviousPlan(event) {
        const weekCount = Number(event.currentTarget.dataset.weekCount);
        this.closeCopyPlanMenu();
        if (this.isCopyPlanDisabled || (weekCount !== 1 && weekCount !== 2)) {
            return;
        }
        const confirmed = await LightningConfirm.open({
            message:
                weekCount === 2
                    ? 'Copy the previous 2 weeks of visits (scheduled and completed) into this week and next week as drafts? Cancelled visits and days that already have a visit for the same account are skipped.'
                    : "Copy last week's visits (scheduled and completed) into this week as drafts? Cancelled visits and days that already have a visit for the same account are skipped.",
            label: weekCount === 2 ? 'Copy 2 weeks' : 'Copy 1 week',
            theme: 'info'
        });
        if (!confirmed) {
            return;
        }
        this.isCopyingWeek = true;
        try {
            const result = await copyWeekVisits({
                targetWeekStart: toApexDate(this.weekStart),
                weekCount,
                contextUserId: this.contextUserId
            });
            const created = result?.createdCount || 0;
            const skipped = result?.skippedCount || 0;
            const errors = (result?.issues || []).filter((issue) => issue?.isError);
            this.showToast(
                created ? 'Plan copied' : 'Nothing copied',
                created
                    ? `${created} draft visit${created === 1 ? '' : 's'} added${skipped ? ` · ${skipped} skipped` : ''}.`
                    : skipped
                      ? `No new visits copied (${skipped} skipped).`
                      : 'No visits found in the previous period.',
                created ? 'success' : 'info'
            );
            if (errors.length) {
                const lines = errors
                    .slice(0, 5)
                    .map((issue) => `${issue.accountName || 'Visit'} (${issue.sourceDate}): ${issue.message}`);
                if (errors.length > 5) {
                    lines.push(`…and ${errors.length - 5} more.`);
                }
                this.showToast(
                    `${errors.length} visit${errors.length === 1 ? '' : 's'} could not be copied`,
                    lines.join(' · '),
                    'warning'
                );
            }
            await this.loadWeek();
        } catch (error) {
            this.showToast('Copy failed', this.reduceError(error), 'error');
        } finally {
            this.isCopyingWeek = false;
        }
    }

    handleCloseAgentforcePopup() {
        this.showPlannerInsights = false;
    }

    handleAgentforceFabClick = (event) => {
        if (this._agentforceMoved) {
            event.preventDefault();
            event.stopPropagation();
            this._agentforceMoved = false;
            return;
        }
        const opening = !this.showPlannerInsights;
        this.showPlannerInsights = opening;
        if (opening) {
            void this.loadWeekRecommendations().then(() => this.refreshPlannerInsights());
        }
    };

    get agentforceFabStyle() {
        if (this.agentforceFabX == null || this.agentforceFabY == null) {
            return '';
        }
        return `left:${this.agentforceFabX}px;top:${this.agentforceFabY}px;right:auto;bottom:auto;`;
    }

    handleAgentforceFabPointerDown = (event) => {
        if (event.button != null && event.button !== 0) {
            return;
        }
        const root = this.template.querySelector('.agentforce-fab-root');
        if (!root) {
            return;
        }
        const rect = root.getBoundingClientRect();
        this._agentforceMoved = false;
        this._agentforceDrag = {
            startX: event.clientX,
            startY: event.clientY,
            originLeft: rect.left,
            originTop: rect.top
        };
        try {
            event.currentTarget.setPointerCapture(event.pointerId);
        } catch (_err) {
            // Some hosts reject setPointerCapture.
        }
        window.addEventListener('pointermove', this.handleAgentforceFabPointerMove);
        window.addEventListener('pointerup', this.handleAgentforceFabPointerUp);
        window.addEventListener('pointercancel', this.handleAgentforceFabPointerUp);
    };

    handleAgentforceFabPointerMove = (event) => {
        if (!this._agentforceDrag) {
            return;
        }
        const dx = event.clientX - this._agentforceDrag.startX;
        const dy = event.clientY - this._agentforceDrag.startY;
        if (Math.abs(dx) > 6 || Math.abs(dy) > 6) {
            this._agentforceMoved = true;
        }
        if (!this._agentforceMoved) {
            return;
        }
        event.preventDefault();
        const fabWidth = 118;
        const fabHeight = 56;
        const maxX = Math.max(8, window.innerWidth - fabWidth - 8);
        const maxY = Math.max(8, window.innerHeight - fabHeight - 8);
        this.agentforceFabX = Math.min(maxX, Math.max(8, this._agentforceDrag.originLeft + dx));
        this.agentforceFabY = Math.min(maxY, Math.max(8, this._agentforceDrag.originTop + dy));
    };

    handleAgentforceFabPointerUp = () => {
        window.removeEventListener('pointermove', this.handleAgentforceFabPointerMove);
        window.removeEventListener('pointerup', this.handleAgentforceFabPointerUp);
        window.removeEventListener('pointercancel', this.handleAgentforceFabPointerUp);
        this._agentforceDrag = null;
    };

    handleCopyTargetDayChange(event) {
        this.copyTargetDayKey = event.detail.value;
    }

    async handleCopyDay() {
        if (this.isCopyDayDisabled) {
            return;
        }
        this.isCopyingDay = true;
        try {
            const created = await copyDayVisits({
                sourceDate: this.mapDayKey,
                targetDate: this.copyTargetDayKey,
                contextUserId: this.contextUserId
            });
            const count = Array.isArray(created) ? created.length : 0;
            this.showToast(
                'Day copied',
                count
                    ? `${count} draft visit${count === 1 ? '' : 's'} added. Adjust times on the calendar as needed.`
                    : 'No visits to copy (already planned, completed, or cancelled).',
                count ? 'success' : 'info'
            );
            await this.loadWeek();
        } catch (error) {
            this.showToast('Copy failed', this.reduceError(error), 'error');
        } finally {
            this.isCopyingDay = false;
        }
    }

    handlePlanRecommendation(event) {
        if (this.isReadOnlyPlannerView) {
            return;
        }
        const accountId = event.currentTarget.dataset.accountId;
        if (!accountId) {
            return;
        }
        this.primeVisitAccount(accountId);
        this.pendingSlotStart = new Date();
        this.pendingSlotStart.setMinutes(0, 0, 0);
        this.showVisitModal = true;
    }

    handlePlannerChatQuestionChange(event) {
        this.plannerChatQuestion = event.detail.value;
    }

    async handleAskPlannerQuestion() {
        const question = (this.plannerChatQuestion || '').trim();
        if (!question || this.isAskingPlanner) {
            return;
        }
        this.isAskingPlanner = true;
        const history = [...(this.plannerChatMessages || [])];
        history.push({
            key: `q-${Date.now()}`,
            role: 'user',
            cssClass: 'planner-chat-user',
            text: question
        });
        this.plannerChatMessages = history;
        this.plannerChatQuestion = '';
        try {
            const result = await askPlannerQuestion({
                question,
                weekStart: toApexDate(this.weekStart),
                contextUserId: this.contextUserId
            });
            this.plannerChatMessages = [
                ...history,
                {
                    key: `a-${Date.now()}`,
                    role: 'assistant',
                    cssClass: 'planner-chat-bot',
                    text: result?.answer || 'No answer returned.'
                }
            ];
        } catch (error) {
            this.plannerChatMessages = [
                ...history,
                {
                    key: `a-${Date.now()}`,
                    role: 'assistant',
                    cssClass: 'planner-chat-bot',
                    text: this.reduceError(error)
                }
            ];
        } finally {
            this.isAskingPlanner = false;
        }
    }

    isCurrentWeekDisplayed() {
        const todayKey = toDateKey(new Date());
        return (this.weekDays || []).some((day) => day.key === todayKey);
    }

    scheduleScrollCalendarToNow() {
        window.requestAnimationFrame(() => {
            window.requestAnimationFrame(() => this.scrollCalendarToNow());
        });
    }

    scrollCalendarToNow() {
        if (!this.isCalendarView) {
            return;
        }
        const scrollEl = this.template.querySelector('.calendar-scroll');
        if (!scrollEl) {
            return;
        }
        const now = new Date();
        const minutesFromStart = (now.getHours() - DAY_START_HOUR) * 60 + now.getMinutes();
        const clampedMinutes = Math.max(0, Math.min(minutesFromStart, this.totalMinutes));
        const targetTop =
            CALENDAR_HEADER_HEIGHT + clampedMinutes * PX_PER_MINUTE - scrollEl.clientHeight * 0.25;
        scrollEl.scrollTop = Math.max(0, targetTop);
    }

    async handleToday() {
        this.weekStart = startOfWeek(new Date());
        this.mapDayKey = toDateKey(new Date());
        await this.loadWeek();
        this.scheduleScrollCalendarToNow();
    }

    async handleThisWeek() {
        this.weekStart = startOfWeek(new Date());
        this.syncMapDayToVisibleWeek();
        await this.loadWeek();
    }

    async handleJumpNextWeek() {
        this.weekStart = addDays(startOfWeek(new Date()), 7);
        this.syncMapDayToVisibleWeek();
        await this.loadWeek();
    }

    handlePrevWeek() {
        this.weekStart = addDays(this.weekStart, -7);
        this.syncMapDayToVisibleWeek();
        this.loadWeek();
    }

    handleNextWeek() {
        this.weekStart = addDays(this.weekStart, 7);
        this.syncMapDayToVisibleWeek();
        this.loadWeek();
    }

    syncMapDayToVisibleWeek() {
        const todayKey = toDateKey(new Date());
        const days = this.weekDays || [];
        if (days.some((day) => day.key === todayKey)) {
            this.mapDayKey = todayKey;
            return;
        }
        const firstWorking = days.find((day) => !day.isWeekend);
        this.mapDayKey = firstWorking?.key || days[0]?.key || todayKey;
    }

    handleShowCalendar() {
        this.closeCopyPlanMenu();
        this.viewMode = 'calendar';
        this.resetRouteState();
        this.destroyMap();
    }

    async handleShowMap() {
        this.closeCopyPlanMenu();
        this.viewMode = 'map';
        this.initializeRouteVisitOrder();
        await this.hydrateMapFromCache();
        await this.renderMap();
        void this.refreshMapCacheInBackground();
    }

    handleMapDayChange(event) {
        this.mapDayKey = event.detail.value;
        this.resetRouteState();
        this.initializeRouteVisitOrder();
        this.renderMap();
    }

    async loadMapAccounts() {
        const cacheUserKey = getUserMapAccountsKey(this.contextUserId || Id);
        try {
            const cached = await getMapAccountsCache(cacheUserKey);
            if (cached?.length && !(this.mapAccounts || []).length) {
                this.mapAccounts = cached;
            }
            if (isOfflineMode()) {
                if (cached?.length) {
                    this.mapAccounts = cached;
                }
                return;
            }
            this.isLoadingMapAccounts = true;
            this.mapAccounts = await getMapAccounts({ contextUserId: this.contextUserId });
            await putCachedAccounts(this.mapAccounts);
            await putMapAccountsCache(cacheUserKey, this.mapAccounts);
        } catch (error) {
            const cached = await getMapAccountsCache(cacheUserKey);
            if (cached && cached.length) {
                this.mapAccounts = cached;
            } else if (!(this.mapAccounts || []).length) {
                this.showToast('Map accounts failed', this.reduceError(error), 'error');
                this.mapAccounts = [];
            }
        } finally {
            this.isLoadingMapAccounts = false;
        }
    }

    // Wraps the IndexedDB-backed cache read so a store error (blocked/absent IDB,
    // as seen in some Lightning webviews) can never reject into the caller.
    async safeSearchCachedAccounts(searchParams) {
        try {
            return await searchCachedAccounts(searchParams);
        } catch (error) {
            console.warn('[PlannerDbg] searchCachedAccounts failed', error);
            return { accounts: [], totalCount: 0, hasMore: false };
        }
    }

    async loadAccountsPage(reset) {
        if (this.isLoadingAccounts) {
            return;
        }
        if (reset) {
            this.accountOffset = 0;
            this.accounts = [];
            this.hasMoreAccounts = false;
            this.totalAccountCount = 0;
            this._accountAutoFillPages = 0;
            this._accountFillBlocked = false;
            this._failedAccountOffset = undefined;
        } else if (this._failedAccountOffset === this.accountOffset) {
            return;
        }

        this.isLoadingAccounts = true;
        let addedAccounts = 0;
        const searchParams = this.accountSearchParams(this.accountOffset, ACCOUNT_PAGE_SIZE);
        const apexSearchParams = this.toApexAccountSearchParams(this.accountOffset, ACCOUNT_PAGE_SIZE);
        console.log('[PlannerDbg] loadAccountsPage', {
            reset,
            offlineMode: isOfflineMode(),
            searchParams: JSON.parse(JSON.stringify(searchParams))
        });

        try {
            if (isOfflineMode()) {
                const cachedResult = await this.safeSearchCachedAccounts(searchParams);
                console.log('[PlannerDbg] loadAccountsPage OFFLINE branch', {
                    cachedAccounts: cachedResult?.accounts?.length,
                    totalCount: cachedResult?.totalCount
                });
                if (cachedResult?.accounts?.length) {
                    addedAccounts = this.applyAccountPage(cachedResult, reset);
                    return;
                }
                // Empty cache while flagged offline — don't show a blank list; try
                // the server anyway. If we really are offline the Apex call fails
                // and the catch handles it.
                console.log('[PlannerDbg] OFFLINE cache empty -> falling through to Apex');
            }

            const result = await searchAccountsPage(apexSearchParams);
            markOnline();
            console.log('[PlannerDbg] loadAccountsPage ONLINE result', {
                rawAccounts: result?.accounts?.length,
                totalCount: result?.totalCount,
                hasMore: result?.hasMore
            });
            const rawAccounts = result?.accounts || [];
            if (rawAccounts.length) {
                await putCachedAccounts(rawAccounts);
            }
            addedAccounts = this.applyAccountPage(result, reset);
            console.log('[PlannerDbg] loadAccountsPage AFTER decorate', {
                decorated: addedAccounts,
                accountsInState: this.accounts.length,
                totalAccountCount: this.totalAccountCount,
                isCollectionView: this.isCollectionView
            });
        } catch (error) {
            const message = this.reduceError(error);
            console.error('[PlannerDbg] loadAccountsPage CATCH', message, error);
            this._accountFillBlocked = true;
            this._failedAccountOffset = this.accountOffset;
            if (/could not reach|network|offline|failed to fetch|timeout|session expired/i.test(message)) {
                markOffline();
            }
            const cachedResult = await this.safeSearchCachedAccounts(searchParams);
            if (cachedResult?.accounts?.length) {
                addedAccounts = this.applyAccountPage(cachedResult, reset);
                console.log('[PlannerDbg] loadAccountsPage CATCH used cache', {
                    cachedAccounts: cachedResult.accounts.length
                });
            } else {
                console.warn('[PlannerDbg] loadAccountsPage CATCH no cache -> toast');
                this.showToast('Account load failed', this.reduceError(error), 'error');
            }
        } finally {
            this.isLoadingAccounts = false;
            this._pendingAccountListFill =
                !this._accountFillBlocked && addedAccounts > 0 && this.hasMoreAccounts === true;
        }
    }

    applyAccountPage(result, reset) {
        const rawAccounts = result?.accounts || [];
        const pageAccounts = rawAccounts.map((account) => this.decorateAccountForDisplay(account));
        this.accounts = reset ? pageAccounts : [...this.accounts, ...pageAccounts];
        this.accountOffset = this.accounts.length;
        this.totalAccountCount = result?.totalCount || this.totalAccountCount || 0;
        const reachedEnd =
            !rawAccounts.length ||
            rawAccounts.length < ACCOUNT_PAGE_SIZE ||
            this.accounts.length >= this.totalAccountCount;
        this.hasMoreAccounts = reachedEnd
            ? false
            : result?.hasMore === true || this.accounts.length < this.totalAccountCount;
        return pageAccounts.length;
    }

    fillAccountListIfNeeded() {
        if (
            this.isCollectionView ||
            this.isLoadingAccounts ||
            !this.hasMoreAccounts ||
            this._accountFillBlocked
        ) {
            return;
        }
        const autoFillPages = this._accountAutoFillPages || 0;
        if (autoFillPages >= ACCOUNT_AUTO_FILL_MAX_PAGES) {
            return;
        }
        window.requestAnimationFrame(() => {
            if (
                this.isCollectionView ||
                this.isLoadingAccounts ||
                !this.hasMoreAccounts ||
                this._accountFillBlocked
            ) {
                return;
            }
            const list = this.template.querySelector('.account-list');
            if (!list || list.clientHeight < 24) {
                return;
            }
            if (list.scrollHeight <= list.clientHeight + 8) {
                this._accountAutoFillPages = autoFillPages + 1;
                this.loadAccountsPage(false);
            }
        });
    }

    handleRecordTypeChange(event) {
        this.accountRecordType = event.detail.value;
        this.loadAccountsPage(true);
        if (this.isMapView) {
            this.focusMapOnFilteredAccounts();
        }
    }

    handleAccountSearch(event) {
        this.accountSearch = event.detail.value;
        window.clearTimeout(this.searchDebounceTimer);
        this.searchDebounceTimer = window.setTimeout(() => {
            this.loadAccountsPage(true);
            if (this.isMapView) {
                this.focusMapOnFilteredAccounts();
            }
        }, SEARCH_DEBOUNCE_MS);
    }

    handleAccountListScroll(event) {
        if (this.isCollectionView) {
            return;
        }
        const list = event.target;
        const nearBottom = list.scrollTop + list.clientHeight >= list.scrollHeight - 64;
        if (nearBottom && this.hasMoreAccounts && !this.isLoadingAccounts) {
            this.loadAccountsPage(false);
        }
    }

    handleLoadMoreAccounts() {
        if (this.isCollectionView) {
            return;
        }
        this._accountFillBlocked = false;
        this._failedAccountOffset = undefined;
        if (this.hasMoreAccounts && !this.isLoadingAccounts) {
            this.loadAccountsPage(false);
        }
    }

    setDragActiveState(active) {
        this.isDragActive = Boolean(active);
        const root = this.template.querySelector('.planner-root');
        if (root) {
            if (active) {
                root.classList.add('is-drag-active');
            } else {
                root.classList.remove('is-drag-active');
            }
        }
    }

    handleAccountDragStart(event) {
        if (this.isReadOnlyPlannerView) {
            event.preventDefault();
            return;
        }
        const accountId = event.currentTarget.dataset.accountId;
        const account = this.resolveAccountById(accountId);
        this.setDragActiveState(true);
        this.dragPayload = { kind: DRAG_TYPE_ACCOUNT, accountId, account };
        event.dataTransfer.setData('application/json', JSON.stringify(this.dragPayload));
        event.dataTransfer.setData('text/plain', accountId || '');
        event.dataTransfer.effectAllowed = 'copyMove';
    }

    handleSidebarDragEnd() {
        this.dragPayload = undefined;
        this.template.querySelectorAll('.collection-chip-drop-target').forEach((el) => {
            el.classList.remove('collection-chip-drop-target');
        });
        this.template.querySelectorAll('.collection-drop-zone-active').forEach((el) => {
            el.classList.remove('collection-drop-zone-active');
        });
        window.setTimeout(() => {
            this.setDragActiveState(false);
        }, 0);
    }

    teardownTouchDragListeners() {
        document.removeEventListener('touchmove', this._handleDocumentTouchMove);
        document.removeEventListener('touchend', this._handleDocumentTouchEnd);
        document.removeEventListener('touchcancel', this._handleDocumentTouchEnd);
        this.removeTouchDragGhost();
        this.clearTouchDropHighlight();
        this.touchDragState = undefined;
        this.setDragActiveState(false);
    }

    beginTouchDragTracking(state) {
        this.touchDragState = state;
        document.addEventListener('touchmove', this._handleDocumentTouchMove, { passive: false });
        document.addEventListener('touchend', this._handleDocumentTouchEnd);
        document.addEventListener('touchcancel', this._handleDocumentTouchEnd);
    }

    handleAccountTouchStart(event) {
        if (this.isReadOnlyPlannerView) {
            return;
        }
        const touch = event.touches?.[0];
        if (!touch) {
            return;
        }
        const accountId = event.currentTarget.dataset.accountId;
        const account = this.accounts.find((item) => item.id === accountId);
        if (!account) {
            return;
        }
        this.beginTouchDragTracking({
            kind: DRAG_TYPE_ACCOUNT,
            accountId,
            account,
            label: account.name,
            startX: touch.clientX,
            startY: touch.clientY,
            active: false
        });
    }

    handleQuickTotTouchStart(event) {
        if (this.isReadOnlyPlannerView) {
            return;
        }
        const touch = event.touches?.[0];
        if (!touch) {
            return;
        }
        const presetId = event.currentTarget.dataset.presetId;
        const preset = TOT_QUICK_PRESETS.find((item) => item.id === presetId);
        this.beginTouchDragTracking({
            kind: DRAG_TYPE_TOT,
            totPreset: preset,
            label: preset ? preset.label : 'Time Off',
            startX: touch.clientX,
            startY: touch.clientY,
            active: false
        });
    }

    handleTotTouchStart(event) {
        if (this.isReadOnlyPlannerView) {
            return;
        }
        const touch = event.touches?.[0];
        if (!touch) {
            return;
        }
        this.beginTouchDragTracking({
            kind: DRAG_TYPE_TOT,
            label: 'Time Off',
            startX: touch.clientX,
            startY: touch.clientY,
            active: false
        });
    }

    handleDocumentTouchMove(event) {
        if (!this.touchDragState) {
            return;
        }
        const touch = event.touches?.[0];
        if (!touch) {
            return;
        }
        const dx = touch.clientX - this.touchDragState.startX;
        const dy = touch.clientY - this.touchDragState.startY;
        if (!this.touchDragState.active) {
            if (Math.hypot(dx, dy) < 12) {
                return;
            }
            if (
                this.touchDragState.kind === DRAG_TYPE_ACCOUNT &&
                Math.abs(dy) > Math.abs(dx)
            ) {
                this.teardownTouchDragListeners();
                return;
            }
            this.touchDragState = { ...this.touchDragState, active: true };
            this.setDragActiveState(true);
            this.dragPayload = this.buildTouchDragPayload(this.touchDragState);
            this.showTouchDragGhost(this.touchDragState.label, touch.clientX, touch.clientY);
        }
        event.preventDefault();
        this.moveTouchDragGhost(touch.clientX, touch.clientY);
        this.highlightTouchDropTarget(touch.clientX, touch.clientY);
    }

    async handleDocumentTouchEnd(event) {
        if (!this.touchDragState) {
            return;
        }
        const touch = event.changedTouches?.[0];
        const wasActive = this.touchDragState.active;
        try {
            if (wasActive && touch) {
                // Account → list (collection) drop. Native ondrop never fires on
                // touch, so resolve the collection target here before the calendar.
                if (this.dragPayload?.kind === DRAG_TYPE_ACCOUNT) {
                    const collectionId = this.findCollectionTargetIdAtPoint(
                        touch.clientX,
                        touch.clientY
                    );
                    if (collectionId) {
                        const payload = this.dragPayload;
                        const accountId = payload.accountId || payload.account?.id;
                        const account = this.resolveAccountById(accountId, payload.account);
                        if (account) {
                            this.addAccountToCollection(collectionId, account);
                        }
                        return;
                    }
                }
                let start = null;
                const slot = this.findCalendarSlotAtPoint(touch.clientX, touch.clientY);
                if (slot) {
                    start = this.resolveSlotFromElement(slot);
                }
                if (!start) {
                    start = this.resolveSlotFromCoordinates(touch.clientX, touch.clientY);
                }
                if (start && this.dragPayload) {
                    await this.processCalendarDrop(start, this.dragPayload);
                }
            }
        } finally {
            this.teardownTouchDragListeners();
            this.dragPayload = undefined;
            this.setDragActiveState(false);
            if (wasActive) {
                this.suppressVisitClick = true;
                window.setTimeout(() => {
                    this.suppressVisitClick = false;
                }, 250);
            }
        }
    }

    handleCalendarTouchMove(event) {
        if (!this.touchDragState?.active) {
            return;
        }
        event.preventDefault();
    }

    buildTouchDragPayload(state) {
        if (state.kind === DRAG_TYPE_ACCOUNT) {
            return { kind: DRAG_TYPE_ACCOUNT, accountId: state.accountId, account: state.account };
        }
        if (state.kind === DRAG_TYPE_TOT) {
            return { kind: DRAG_TYPE_TOT, totPreset: state.totPreset };
        }
        if (state.kind === DRAG_TYPE_PROMO) {
            return { kind: DRAG_TYPE_PROMO };
        }
        return null;
    }

    showTouchDragGhost(label, x, y) {
        this.removeTouchDragGhost();
        const ghost = document.createElement('div');
        ghost.className = 'touch-drag-ghost';
        ghost.textContent = label || 'Dragging';
        ghost.style.left = `${x}px`;
        ghost.style.top = `${y}px`;
        document.body.appendChild(ghost);
        this.touchDragGhostEl = ghost;
    }

    moveTouchDragGhost(x, y) {
        if (!this.touchDragGhostEl) {
            return;
        }
        this.touchDragGhostEl.style.left = `${x}px`;
        this.touchDragGhostEl.style.top = `${y}px`;
    }

    removeTouchDragGhost() {
        if (this.touchDragGhostEl) {
            this.touchDragGhostEl.remove();
            this.touchDragGhostEl = undefined;
        }
    }

    findCalendarSlotAtPoint(x, y) {
        if (this.touchDragGhostEl) {
            this.touchDragGhostEl.style.display = 'none';
        }
        let element = null;
        if (this.template?.elementFromPoint) {
            element = this.template.elementFromPoint(x, y);
        }
        if (!element) {
            element = document.elementFromPoint(x, y);
        }
        if (this.touchDragGhostEl) {
            this.touchDragGhostEl.style.display = '';
        }
        return element?.closest?.('[data-day-key][data-minutes]') || null;
    }

    elementAtPoint(x, y) {
        if (this.touchDragGhostEl) {
            this.touchDragGhostEl.style.display = 'none';
        }
        let element = null;
        if (this.template?.elementFromPoint) {
            element = this.template.elementFromPoint(x, y);
        }
        if (!element) {
            element = document.elementFromPoint(x, y);
        }
        if (this.touchDragGhostEl) {
            this.touchDragGhostEl.style.display = '';
        }
        return element;
    }

    findCollectionTargetElementAtPoint(x, y) {
        // 1. Try the precise point hit-test first.
        const element = this.elementAtPoint(x, y);
        if (element?.closest) {
            const chip = element.closest('.collection-chip[data-collection-id]');
            if (chip) {
                return chip;
            }
            const zone = element.closest('.collection-drop-zone');
            if (zone && this.selectedCollectionId) {
                return zone;
            }
        }
        // 2. Geometric fallback — robust to shadow DOM boundaries and the drag
        //    ghost overlapping the point. Small tolerance makes small chips easy
        //    to hit on touch.
        const TOL = 10;
        const hits = (el) => {
            if (!el) {
                return false;
            }
            const r = el.getBoundingClientRect();
            if (!r.width && !r.height) {
                return false;
            }
            return (
                x >= r.left - TOL &&
                x <= r.right + TOL &&
                y >= r.top - TOL &&
                y <= r.bottom + TOL
            );
        };
        const chips = this.template.querySelectorAll('.collection-chip[data-collection-id]');
        for (const chip of chips) {
            if (hits(chip)) {
                return chip;
            }
        }
        if (this.selectedCollectionId) {
            const zone = this.template.querySelector('.collection-drop-zone');
            if (hits(zone)) {
                return zone;
            }
        }
        return null;
    }

    findCollectionTargetIdAtPoint(x, y) {
        const el = this.findCollectionTargetElementAtPoint(x, y);
        if (!el) {
            return null;
        }
        return el.dataset?.collectionId || this.selectedCollectionId || null;
    }

    highlightTouchDropTarget(x, y) {
        this.clearTouchDropHighlight();
        const slot = this.findCalendarSlotAtPoint(x, y);
        if (slot) {
            slot.classList.add('calendar-drop-target');
            this.touchDropHighlightEl = slot;
            this.touchDropHighlightClass = 'calendar-drop-target';
            return;
        }
        if (this.dragPayload?.kind === DRAG_TYPE_ACCOUNT) {
            const target = this.findCollectionTargetElementAtPoint(x, y);
            if (target) {
                const cls = target.classList.contains('collection-drop-zone')
                    ? 'collection-drop-zone-active'
                    : 'collection-chip-drop-target';
                target.classList.add(cls);
                this.touchDropHighlightEl = target;
                this.touchDropHighlightClass = cls;
            }
        }
    }

    clearTouchDropHighlight() {
        if (this.touchDropHighlightEl) {
            this.touchDropHighlightEl.classList.remove(
                this.touchDropHighlightClass || 'calendar-drop-target'
            );
            this.touchDropHighlightEl = undefined;
            this.touchDropHighlightClass = undefined;
        }
    }

    resolveSlotFromElement(slot) {
        if (!slot) {
            return null;
        }
        const dayKey = slot.dataset.dayKey;
        const minutes = Number(slot.dataset.minutes);
        if (!dayKey || Number.isNaN(minutes)) {
            return null;
        }
        return this.minutesToDate(dayKey, minutes);
    }

    handleTotDragStart(event) {
        if (this.isReadOnlyPlannerView) {
            event.preventDefault();
            return;
        }
        this.setDragActiveState(true);
        this.dragPayload = { kind: DRAG_TYPE_TOT };
        event.dataTransfer.setData('application/json', JSON.stringify(this.dragPayload));
        event.dataTransfer.setData('text/plain', DRAG_TYPE_TOT);
        event.dataTransfer.effectAllowed = 'copy';
    }

    handleMeetingDragStart(event) {
        if (this.isReadOnlyPlannerView) {
            event.preventDefault();
            return;
        }
        this.setDragActiveState(true);
        this.dragPayload = { kind: DRAG_TYPE_MEETING };
        event.dataTransfer.setData('application/json', JSON.stringify(this.dragPayload));
        event.dataTransfer.setData('text/plain', DRAG_TYPE_MEETING);
        event.dataTransfer.effectAllowed = 'copy';
    }

    handleNewMeetingClick() {
        if (this.isReadOnlyPlannerView) {
            return;
        }
        this.showPlanningPalettePanel = false;
        this.openMeetingPanel({});
    }

    handleEventDragStart(event) {
        const eventId = event.currentTarget.dataset.eventId;
        const eventType = event.currentTarget.dataset.eventType;
        if (eventType !== 'visit') {
            event.preventDefault();
            return;
        }
        const visit = this.visits.find((item) => item.id === eventId);
        if (!visit || visit.status === 'Completed' || visit.status === 'Cancelled') {
            event.preventDefault();
            return;
        }
        this.dragPayload = {
            kind: DRAG_TYPE_EVENT,
            visit,
            durationMs:
                parseSalesforceDateTime(visit.endDateTime) - parseSalesforceDateTime(visit.startDateTime)
        };
        this.setDragActiveState(true);
        event.currentTarget.classList.add('is-dragging');
        event.dataTransfer.setData('application/json', JSON.stringify(this.dragPayload));
        event.dataTransfer.setData('text/plain', eventId);
        event.dataTransfer.effectAllowed = 'move';
    }

    handleEventDragEnd(event) {
        event.currentTarget.classList.remove('is-dragging');
        this.dragPayload = undefined;
        this.suppressVisitClick = true;
        window.setTimeout(() => {
            this.setDragActiveState(false);
            this.suppressVisitClick = false;
        }, 250);
    }

    handleDragOver(event) {
        event.preventDefault();
        event.dataTransfer.dropEffect = this.dragPayload?.kind === DRAG_TYPE_EVENT ? 'move' : 'copy';
    }

    async handleCalendarDrop(event) {
        event.preventDefault();
        event.stopPropagation();
        const start = this.resolveSlotFromEvent(event);
        const payload = this.parseDragPayload(event);
        await this.processCalendarDrop(start, payload);
    }

    async processCalendarDrop(start, payload) {
        if (!start || !payload) {
            return;
        }
        // Drop can hit both the planning-palette backdrop and the calendar
        // scroll container in one gesture; only process the first drop.
        if (this._calendarDropInFlight) {
            return;
        }
        this._calendarDropInFlight = true;
        if (this.showPlanningPalettePanel) {
            this.showPlanningPalettePanel = false;
        }
        if (this.isBlockedPlannerDay(start) && !(await this.confirmPlannerDay(start, payload.kind))) {
            this.dragPayload = undefined;
            this.setDragActiveState(false);
            this._calendarDropInFlight = false;
            return;
        }
        try {
            if (payload.kind === DRAG_TYPE_ACCOUNT) {
                const accountId = payload.accountId || payload.account?.id;
                if (!accountId) {
                    this.showToast('Save failed', 'Select an account for the visit.', 'error');
                    return;
                }
                const end = new Date(start.getTime() + DEFAULT_VISIT_MINUTES * 60000);
                await this.persistVisit({
                    accountId,
                    startDateTime: start,
                    endDateTime: end,
                    status: VISIT_STATUS_DRAFT
                });
            } else if (payload.kind === DRAG_TYPE_EVENT) {
                const end = new Date(start.getTime() + payload.durationMs);
                await this.persistVisit({
                    id: payload.visit.id,
                    accountId: payload.visit.accountId,
                    startDateTime: start,
                    endDateTime: end,
                    status: payload.visit.status
                });
            } else if (payload.kind === DRAG_TYPE_TOT) {
                if (payload.totPreset) {
                    await this.submitQuickTotAt(start, payload.totPreset);
                } else {
                    this.openTotModal(start);
                }
            } else if (payload.kind === DRAG_TYPE_PROMO) {
                this.pendingSlotStart = start;
                await this.openPromoModal();
            } else if (payload.kind === DRAG_TYPE_MEETING) {
                this.showPlanningPalettePanel = false;
                this.openMeetingPanel({ start });
            }
        } finally {
            this.dragPayload = undefined;
            this.setDragActiveState(false);
            this._calendarDropInFlight = false;
        }
    }

    handleSlotClick(event) {
        if (this.isDragActive) {
            return;
        }
        const start = this.resolveSlotFromEvent(event);
        if (!start) {
            return;
        }
        this.pendingSlotStart = start;
        this.showPlanChoiceModal = true;
    }

    handlePlanChoiceCancel() {
        this.closePlannerModal(() => {
            this.showPlanChoiceModal = false;
            this.pendingSlotStart = null;
        });
    }

    async handlePlanVisitChoice() {
        this.showPlanChoiceModal = false;
        this.clearVisitAccountSelection();
        this.showVisitModal = true;
    }

    handlePlanTotChoice() {
        this.showPlanChoiceModal = false;
        const start = this.pendingSlotStart;
        this.pendingSlotStart = null;
        if (start) {
            this.openTotModal(start);
        }
    }

    async handlePlanPromoChoice() {
        this.showPlanChoiceModal = false;
        await this.openPromoModal();
    }

    async handlePlanMeetingChoice() {
        const start = this.pendingSlotStart;
        this.showPlanChoiceModal = false;
        this.pendingSlotStart = null;
        if (start && this.isBlockedPlannerDay(start) && !(await this.confirmPlannerDay(start, DRAG_TYPE_MEETING))) {
            return;
        }
        this.openMeetingPanel({ start });
    }

    get pendingSlotDayLabel() {
        return this.pendingSlotStart ? this.pendingSlotStart.toLocaleDateString(undefined, PLAN_SLOT_DAY_FORMAT) : '';
    }

    get pendingSlotTimeLabel() {
        return this.pendingSlotStart ? this.pendingSlotStart.toLocaleTimeString(undefined, PLAN_SLOT_TIME_FORMAT) : '';
    }

    openMeetingPanel({ meetingId = null, start = null }) {
        if (meetingId) {
            this.meetingPanelId = meetingId;
            this.meetingPanelStart = null;
            this.meetingPanelEnd = null;
        } else {
            const begin = start ? new Date(start) : this.nextMeetingSlot();
            this.meetingPanelId = null;
            this.meetingPanelStart = begin.toISOString();
            this.meetingPanelEnd = new Date(begin.getTime() + DEFAULT_MEETING_MINUTES * 60000).toISOString();
        }
        this.showMeetingPanel = true;
    }

    nextMeetingSlot() {
        const slot = new Date();
        slot.setDate(slot.getDate() + 1);
        slot.setHours(18, 0, 0, 0);
        return slot;
    }

    handleMeetingPanelShellClick(event) {
        if (event.target === event.currentTarget) {
            this.handleMeetingPanelClose();
        }
    }

    handleMeetingPanelClose() {
        this.showMeetingPanel = false;
        this.meetingPanelId = null;
        this.meetingPanelStart = null;
        this.meetingPanelEnd = null;
        void this.refreshPlannerMeetings();
    }

    handleMeetingPanelCreated(event) {
        this.meetingPanelId = event.detail && event.detail.meetingId;
        void this.refreshPlannerMeetings();
    }

    handleMeetingPanelChanged() {
        void this.refreshPlannerMeetings();
    }

    async refreshPlannerMeetings() {
        if (isOfflineMode()) {
            return;
        }
        try {
            this.meetings =
                (await fetchMeetings({
                    weekStart: toApexDate(this.weekStart),
                    weekEnd: toApexDate(this.weekEnd),
                    contextUserId: this.contextUserId
                })) || [];
        } catch (error) {
            // Keep the meetings already on the calendar.
        }
    }

    async openPromoModal() {
        await this.loadPromoProjectOptions();
        const defaultProject = this.promoProjectOptions[0];
        this.promoProjectId = defaultProject?.value || '';
        this.promoTitle = defaultProject?.label || '';
        this.showPromoModal = true;
    }

    handlePromoProjectChange(event) {
        this.promoProjectId = event.detail.value;
        const selected = (this.promoProjectOptions || []).find((option) => option.value === this.promoProjectId);
        if (selected && !(this.promoTitle || '').trim()) {
            this.promoTitle = selected.label;
        }
    }

    handlePromoTitleChange(event) {
        this.promoTitle = event.detail.value;
    }

    handlePromoCancel() {
        this.closePlannerModal(() => {
            this.showPromoModal = false;
            this.promoProjectId = '';
            this.promoTitle = '';
            this.pendingSlotStart = null;
        });
    }

    async handlePromoSave() {
        if (!this.promoProjectId) {
            this.showToast('Validation', 'Select a promotional project.', 'error');
            return;
        }
        if (!(this.promoTitle || '').trim()) {
            this.showToast('Validation', 'Enter an event title.', 'error');
            return;
        }
        if (!this.pendingSlotStart) {
            this.showToast('Validation', 'Select a calendar time slot.', 'error');
            return;
        }
        const end = new Date(this.pendingSlotStart.getTime() + DEFAULT_PROMO_MINUTES * 60000);
        await this.persistVisit({
            accountId: null,
            zetaProjectId: this.promoProjectId,
            visitObjective: this.promoTitle.trim(),
            startDateTime: this.pendingSlotStart,
            endDateTime: end,
            status: VISIT_STATUS_DRAFT
        });
        this.showPromoModal = false;
        this.promoProjectId = '';
        this.promoTitle = '';
        this.pendingSlotStart = null;
    }

    get visitAccountSuggestions() {
        return (this.accounts || []).slice(0, 8).map((account) => ({
            accountId: account.id,
            accountName: account.name,
            recordTypeLabel: account.recordTypeName || '',
            iconName: this.iconForVisitAccount(account)
        }));
    }

    iconForVisitAccount(account) {
        const key = account?.recordTypeDeveloperName || '';
        if (
            key === 'PersonAccount' ||
            key === 'SDO_PersonAccounts' ||
            key === 'Medical_Professional_HCP'
        ) {
            return 'standard:person_account';
        }
        if (key === 'Pharmacy') {
            return 'standard:household';
        }
        if (key === 'Business_Contact') {
            return 'standard:contact';
        }
        return 'standard:account';
    }

    clearVisitAccountSelection() {
        this.visitAccountId = '';
        this.visitAccountName = '';
        this.visitAccountIconName = '';
        this.visitAccountRecordTypeLabel = '';
        this.visitAccountInvalid = false;
    }

    primeVisitAccount(accountId, hint) {
        const account = this.resolveAccountById(accountId, hint) || hint || null;
        this.visitAccountId = accountId || '';
        this.visitAccountName =
            account?.name || account?.accountName || hint?.accountName || '';
        this.visitAccountRecordTypeLabel =
            account?.recordTypeName || account?.recordTypeLabel || hint?.recordTypeLabel || '';
        this.visitAccountIconName = this.iconForVisitAccount(account || hint);
        this.visitAccountInvalid = false;
    }

    handleVisitAccountLookupChange(event) {
        const detail = event.detail || {};
        this.visitAccountId = detail.accountId || '';
        this.visitAccountName = detail.accountName || '';
        this.visitAccountIconName = detail.iconName || '';
        this.visitAccountRecordTypeLabel = detail.recordTypeLabel || '';
        if (this.visitAccountId) {
            this.visitAccountInvalid = false;
        }
    }

    handleVisitCancel() {
        this.closePlannerModal(() => {
            this.showVisitModal = false;
            this.clearVisitAccountSelection();
            this.pendingSlotStart = null;
        });
    }

    async handleVisitSave() {
        if (!this.visitAccountId) {
            this.visitAccountInvalid = true;
            this.showToast('Validation', 'Select an HCP or HCO for the visit.', 'error');
            this.template.querySelector('c-field-account-lookup')?.focus();
            return;
        }
        if (!this.pendingSlotStart) {
            this.showToast('Validation', 'Select a calendar time slot.', 'error');
            return;
        }
        const end = new Date(this.pendingSlotStart.getTime() + DEFAULT_VISIT_MINUTES * 60000);
        await this.persistVisit({
            accountId: this.visitAccountId,
            startDateTime: this.pendingSlotStart,
            endDateTime: end,
            status: VISIT_STATUS_DRAFT
        });
        this.showVisitModal = false;
        this.clearVisitAccountSelection();
        this.pendingSlotStart = null;
    }

    openTotModal(startDate) {
        this.pendingTotStart = startDate;
        const isFullDay = startDate.getHours() === 0 && startDate.getMinutes() === 0;
        this.totTypeValue = 'Training';
        this.totSpanType = isFullDay ? 'Full_Day' : 'Hours';
        this.totDurationHours = '2';
        if (isFullDay) {
            this.totStartDate = toApexDate(startDate);
            this.totStartDateTime = '';
        } else {
            this.totStartDate = '';
            this.totStartDateTime = toSalesforceDateTimeLocal(startDate);
        }
        this.totComments = '';
        this.showTotModal = true;
    }

    applyTotPreset(preset) {
        if (!preset) {
            return;
        }
        this.totTypeValue = preset.typeValue;
        this.totSpanType = preset.spanType;
        this.totDurationHours = preset.durationHours || '';
        const startDate = this.pendingTotStart || this.pendingSlotStart || new Date();
        if (preset.spanType === 'Full_Day') {
            this.totStartDate = toApexDate(startDate);
            this.totStartDateTime = '';
        } else {
            this.totStartDate = '';
            this.totStartDateTime = toSalesforceDateTimeLocal(startDate);
            if (!this.totDurationHours) {
                this.totDurationHours = '2';
            }
        }
    }

    handleTotPresetClick(event) {
        const presetId = event.currentTarget.dataset.presetId;
        const preset = TOT_QUICK_PRESETS.find((item) => item.id === presetId);
        if (preset) {
            this.showPlanningPalettePanel = false;
            this.applyTotPreset(preset);
            this.showTotModal = true;
        }
    }

    handleCustomTotClick() {
        this.showPlanningPalettePanel = false;
        this.openTotModal(new Date());
    }

    handleQuickTotDragStart(event) {
        if (this.isReadOnlyPlannerView) {
            event.preventDefault();
            return;
        }
        const presetId = event.currentTarget.dataset.presetId;
        const preset = TOT_QUICK_PRESETS.find((item) => item.id === presetId);
        this.setDragActiveState(true);
        this.dragPayload = { kind: DRAG_TYPE_TOT, totPreset: preset };
        event.dataTransfer.setData('application/json', JSON.stringify(this.dragPayload));
        event.dataTransfer.setData('text/plain', DRAG_TYPE_TOT);
        event.dataTransfer.effectAllowed = 'copy';
    }

    handlePromoDragStart(event) {
        if (this.isReadOnlyPlannerView) {
            event.preventDefault();
            return;
        }
        this.setDragActiveState(true);
        this.dragPayload = { kind: DRAG_TYPE_PROMO };
        event.dataTransfer.setData('application/json', JSON.stringify(this.dragPayload));
        event.dataTransfer.setData('text/plain', DRAG_TYPE_PROMO);
        event.dataTransfer.effectAllowed = 'copy';
    }

    async submitQuickTotAt(startDate, preset) {
        if (!preset || this.isReadOnlyPlannerView) {
            return;
        }
        this.pendingTotStart = startDate;
        this.applyTotPreset(preset);
        await this.saveTot('Submitted for Approval');
        this.pendingTotStart = null;
    }

    handleTotTypeChange(event) {
        this.totTypeValue = event.detail.value;
    }

    handleTotSpanChange(event) {
        this.totSpanType = event.detail.value;
        if (this.totSpanType !== 'Hours') {
            this.totDurationHours = '';
            this.totStartDateTime = '';
        } else if (!this.totDurationHours) {
            this.totDurationHours = '2';
            this.totStartDate = '';
        } else {
            this.totStartDate = '';
        }
    }

    handleTotStartDateChange(event) {
        this.totStartDate = event.detail.value;
    }

    handleTotDurationChange(event) {
        this.totDurationHours = event.detail.value;
    }

    handleTotStartChange(event) {
        this.totStartDateTime = event.detail.value;
    }

    handleTotCommentsChange(event) {
        this.totComments = event.detail.value;
    }

    handleTotCancel() {
        this.closePlannerModal(() => {
            this.showTotModal = false;
            this.pendingTotStart = null;
            this.resetTotForm();
        });
    }

    resetTotForm() {
        this.totTypeValue = '';
        this.totSpanType = '';
        this.totDurationHours = '';
        this.totStartDateTime = '';
        this.totStartDate = '';
        this.totComments = '';
    }

    buildTotStartDateTime(form) {
        const startDate = this.pendingTotStart;
        if (form.spanType === 'Full_Day') {
            const dateValue = form.startDate || form.startDateTime?.slice(0, 10);
            if (!dateValue) {
                return null;
            }
            return normalizeLocalDateTimeString(`${dateValue}T09:00:00`);
        }
        const normalizedStart = normalizeLocalDateTimeString(form.startDateTime);
        if (normalizedStart) {
            return normalizedStart;
        }
        if (startDate) {
            return toApexDateTime(startDate);
        }
        return null;
    }

    validateTotFormState() {
        if (!this.totTypeValue) {
            return 'Select a time off type.';
        }
        if (!this.totSpanType) {
            return 'Select full day or partial hours.';
        }
        if (this.totSpanType === 'Hours' && !this.totDurationHours) {
            return 'Select duration for partial time off.';
        }
        if (this.totSpanType === 'Hours' && !this.totStartDateTime) {
            return 'Start date and time is required for partial time off.';
        }
        if (this.totSpanType === 'Full_Day' && !this.totStartDate) {
            return 'Select the date for your full day off.';
        }

        return null;
    }

    validateTotForm() {
        const typeValue = this.totTypeValue || this.template.querySelector('[data-tot-field="type"]')?.value;
        const spanType = this.totSpanType || this.template.querySelector('[data-tot-field="span"]')?.value;
        const durationHours =
            this.totDurationHours || this.template.querySelector('[data-tot-field="duration"]')?.value;
        const startDateTime =
            this.totStartDateTime || this.template.querySelector('[data-tot-field="start-datetime"]')?.value;
        const startDate = this.totStartDate || this.template.querySelector('[data-tot-field="start-date"]')?.value;

        if (!typeValue) {
            return 'Select a time off type.';
        }
        if (!spanType) {
            return 'Select full day or partial hours.';
        }
        if (spanType === 'Hours' && !durationHours) {
            return 'Select duration for partial time off.';
        }
        if (spanType === 'Hours' && !startDateTime) {
            return 'Start date and time is required for partial time off.';
        }
        if (spanType === 'Full_Day' && !startDate) {
            return 'Select the date for your full day off.';
        }

        return null;
    }

    mergeCreatedTot(created) {
        if (!created?.id) {
            return;
        }
        const alreadyShown = (this.timeOffBlocks || []).some((block) => block.id === created.id);
        if (alreadyShown) {
            return;
        }
        this.timeOffBlocks = [...(this.timeOffBlocks || []), created];
    }

    readTotFormValues() {
        return {
            typeValue: this.totTypeValue || this.template.querySelector('[data-tot-field="type"]')?.value,
            spanType: this.totSpanType || this.template.querySelector('[data-tot-field="span"]')?.value,
            durationHours:
                this.totDurationHours || this.template.querySelector('[data-tot-field="duration"]')?.value,
            startDateTime:
                this.totStartDateTime || this.template.querySelector('[data-tot-field="start-datetime"]')?.value,
            startDate: this.totStartDate || this.template.querySelector('[data-tot-field="start-date"]')?.value,
            comments: this.totComments
        };
    }

    async handleTotSaveDraft() {
        await this.saveTot('Draft');
    }

    async handleTotSubmit() {
        await this.saveTot('Submitted for Approval');
    }

    totWindowFromForm(form, startDateTime) {
        const startDateObj = new Date(startDateTime);
        let endDateObj;
        if (form.spanType === 'Full_Day') {
            startDateObj.setHours(9, 0, 0, 0);
            endDateObj = new Date(startDateObj);
            endDateObj.setHours(17, 0, 0, 0);
        } else {
            const hours = Number(form.durationHours || 2);
            endDateObj = new Date(startDateObj.getTime() + hours * 3600 * 1000);
        }
        return { startDateObj, endDateObj };
    }

    shouldQueueTot(error) {
        const status = Number(error?.status || error?.statusCode || 0);
        const msg = String(error?.body?.message || error?.message || error || '');
        return (
            status === 0 ||
            status === 404 ||
            status >= 500 ||
            /LimitException|Aura context|failed to fetch|networkerror|load failed|offline|HTTP 5|Unknown POST path|not found/i.test(
                msg
            )
        );
    }

    async queueCreateTimeOff(form, startDateTime, stage) {
        const { startDateObj, endDateObj } = this.totWindowFromForm(form, startDateTime);
        const isoStart = startDateObj.toISOString();
        const isoEnd = endDateObj.toISOString();
        const newKey = newClientKey('tot');
        await queueOfflineAction({
            actionType: 'CREATE_TIME_OFF',
            clientActionKey: newKey,
            payloadJson: JSON.stringify({
                typeValue: form.typeValue,
                spanType: form.spanType,
                durationHours: form.spanType === 'Hours' ? form.durationHours : null,
                startDateTime: isoStart,
                comments: form.comments,
                stage
            })
        });
        return {
            id: newKey,
            name: form.typeValue,
            typeLabel: form.typeValue,
            typeValue: form.typeValue,
            startDateTime: isoStart,
            endDateTime: isoEnd,
            spanType: form.spanType,
            stage
        };
    }

    async saveTot(stage) {
        if (this.isReadOnlyPlannerView) {
            this.showToast('Read-only', 'You cannot edit another rep\'s planner.', 'error');
            return;
        }
        const validationMessage = this.validateTotForm();
        if (validationMessage) {
            this.showToast('TOT failed', validationMessage, 'error');
            return;
        }

        const form = this.readTotFormValues();
        const startDateTime = this.buildTotStartDateTime(form);
        if (!startDateTime) {
            this.showToast('TOT failed', 'Start date/time is required.', 'error');
            return;
        }

        this.isSaving = true;
        try {
            let created;
            let queued = false;
            if (isOfflineMode()) {
                created = await this.queueCreateTimeOff(form, startDateTime, stage);
                queued = true;
            } else {
                try {
                    created = await createTimeOff({
                        typeValue: form.typeValue,
                        spanType: form.spanType,
                        durationHours: form.spanType === 'Hours' ? form.durationHours : null,
                        startDateTime,
                        comments: form.comments,
                        stage
                    });
                } catch (networkError) {
                    if (!this.shouldQueueTot(networkError)) {
                        throw networkError;
                    }
                    created = await this.queueCreateTimeOff(form, startDateTime, stage);
                    queued = true;
                }
            }
            if (created && !created.endDateTime) {
                const s = parseSalesforceDateTime(created.startDateTime || startDateTime);
                if (s) {
                    const hours = Number(form.durationHours || (form.spanType === 'Full_Day' ? 8 : 2));
                    const e = new Date(s.getTime() + hours * 3600 * 1000);
                    created.endDateTime = e.toISOString();
                }
            }
            this.showTotModal = false;
            this.pendingTotStart = null;
            this.resetTotForm();
            this.mergeCreatedTot(created);
            await this.cacheCurrentWeek();
            this.showToast(
                queued || isOfflineMode()
                    ? 'Queued offline'
                    : stage === 'Draft'
                      ? 'TOT saved'
                      : 'TOT submitted',
                queued || isOfflineMode()
                    ? `${created.typeLabel} will sync when you reconnect.`
                    : `${created.typeLabel} request created.`,
                'success'
            );
            void this.loadWeek();
        } catch (error) {
            const message = this.reduceError(error);
            const isOverlap =
                /overlap/i.test(message) ||
                /overlaps with another/i.test(message);
            if (isOverlap) {
                void this.loadWeek();
            }
            this.showToast(
                'TOT failed',
                isOverlap
                    ? `${message} Check your calendar — an existing TOT may already cover this time.`
                    : message,
                'error'
            );
        } finally {
            this.isSaving = false;
        }
    }

    handleResizeStart = (event) => {
        event.stopPropagation();
        event.preventDefault();
        const eventId = event.currentTarget.dataset.eventId;
        const eventType = event.currentTarget.dataset.eventType || 'visit';
        if (eventType === 'tot') {
            const tot = (this.timeOffBlocks || []).find((item) => String(item.id) === String(eventId));
            if (!tot) {
                return;
            }
            this.resizingEventId = eventId;
            this.resizingEventType = 'tot';
            this.resizeStartY = event.clientY;
            this.resizeOriginalEnd = parseSalesforceDateTime(
                tot.endDateTime || tot.End_Date_Time__c || tot.endDate
            );
        } else {
            const visit = this.visits.find((item) => item.id === eventId);
            if (!visit) {
                return;
            }
            this.resizingEventId = eventId;
            this.resizingEventType = 'visit';
            this.resizeStartY = event.clientY;
            this.resizeOriginalEnd = parseSalesforceDateTime(visit.endDateTime);
        }
        try {
            event.currentTarget.setPointerCapture(event.pointerId);
        } catch (_err) {
            // ignore
        }
        window.addEventListener('pointermove', this.handleResizeMove);
        window.addEventListener('pointerup', this.handleResizeEnd);
        window.addEventListener('pointercancel', this.handleResizeEnd);
    };

    handleResizeMove = (event) => {
        if (!this.resizingEventId) {
            return;
        }
        event.preventDefault();
        const deltaMinutes =
            Math.round((event.clientY - this.resizeStartY) / PX_PER_MINUTE / SLOT_MINUTES) *
            SLOT_MINUTES;
        if (this.resizingEventType === 'tot') {
            const tot = (this.timeOffBlocks || []).find(
                (item) => String(item.id) === String(this.resizingEventId)
            );
            if (!tot) {
                return;
            }
            const start = parseSalesforceDateTime(
                tot.startDateTime || tot.Start_Date_Time__c || tot.startDate
            );
            const newEnd = new Date(this.resizeOriginalEnd.getTime() + deltaMinutes * 60000);
            const minEnd = new Date(start.getTime() + SLOT_MINUTES * 60000);
            if (newEnd < minEnd) {
                return;
            }
            tot.endDateTime = toApexDateTime(newEnd);
            this.timeOffBlocks = [...this.timeOffBlocks];
            return;
        }
        const visit = this.visits.find((item) => item.id === this.resizingEventId);
        if (!visit) {
            return;
        }
        const start = parseSalesforceDateTime(visit.startDateTime);
        const newEnd = new Date(this.resizeOriginalEnd.getTime() + deltaMinutes * 60000);
        const minEnd = new Date(start.getTime() + SLOT_MINUTES * 60000);
        if (newEnd < minEnd) {
            return;
        }
        visit.endDateTime = toApexDateTime(newEnd);
        this.visits = [...this.visits];
    };

    handleResizeEnd = async () => {
        window.removeEventListener('pointermove', this.handleResizeMove);
        window.removeEventListener('pointerup', this.handleResizeEnd);
        window.removeEventListener('pointercancel', this.handleResizeEnd);
        if (!this.resizingEventId) {
            return;
        }
        const eventId = this.resizingEventId;
        const eventType = this.resizingEventType;
        this.resizingEventId = undefined;
        this.resizingEventType = undefined;
        if (eventType === 'tot') {
            const tot = (this.timeOffBlocks || []).find((item) => String(item.id) === String(eventId));
            if (!tot) {
                return;
            }
            const start = parseSalesforceDateTime(
                tot.startDateTime || tot.Start_Date_Time__c || tot.startDate
            );
            const end = parseSalesforceDateTime(tot.endDateTime || tot.End_Date_Time__c);
            try {
                await updateTimeOff({
                    timeOffId: tot.id,
                    endDateTime: end
                });
                const hours = Math.max(0.25, (end - start) / 3600000);
                tot.durationHours = String(Math.round(hours * 4) / 4);
                this.showToast('TOT updated', 'Duration saved.', 'success');
            } catch (error) {
                this.showToast('TOT resize failed', this.reduceError(error), 'error');
                void this.loadWeek();
            }
            return;
        }
        const visit = this.visits.find((item) => item.id === eventId);
        if (!visit) {
            return;
        }
        await this.persistVisit({
            id: visit.id,
            accountId: visit.accountId,
            startDateTime: parseSalesforceDateTime(visit.startDateTime),
            endDateTime: parseSalesforceDateTime(visit.endDateTime),
            status: visit.status
        });
    };

    handleEventClick(event) {
        event.stopPropagation();
        if (this.suppressVisitClick || this.isDragActive) {
            return;
        }
        const eventType = event.currentTarget.dataset.eventType;
        const recordId = event.currentTarget.dataset.eventId;
        if (eventType === 'visit') {
            const visit = (this.visits || []).find((item) => item.id === recordId);
            if (visit) {
                this.openVisitDetailModal(visit);
            }
        } else if (eventType === 'tot') {
            const tot = (this.timeOffBlocks || []).find((item) => String(item.id) === String(recordId));
            const label = tot?.typeLabel || tot?.typeValue || tot?.name || 'Time Off';
            const stage = tot?.stage || '';
            if (this.canManageTeamPlans && stage === TOT_STAGE_SUBMITTED) {
                this.openPlanApprovalModal('tot', recordId, `TOT — ${label}`);
                return;
            }
            this.showToast('Time Off (TOT)', `${label} (${stage || 'Submitted'})`, 'info');
            this.navigateToRecord(recordId, 'Time_Off_Request__c');
        } else if (eventType === 'meeting') {
            const meeting = (this.meetings || []).find((item) => String(item.id) === String(recordId));
            if (meeting && meeting.department) {
                this.openMeetingPanel({ meetingId: recordId });
                return;
            }
            if (this.canManageTeamPlans && meeting && MEETING_PENDING_STATUSES.has(meeting.status)) {
                const typeLabel = meeting.recordTypeLabel || 'Meeting';
                const meetingTitle = meeting.title || meeting.name || typeLabel;
                this.openPlanApprovalModal('meeting', recordId, `${typeLabel} — ${meetingTitle}`);
                return;
            }
            if (this.meetingExpensesEnabled && meeting) {
                this.meetingExpenseId = recordId;
                this.meetingExpenseTitle = meeting.title || meeting.name || 'Meeting';
                this.showMeetingExpenseModal = true;
                return;
            }
            this.openMeetingPanel({ meetingId: recordId });
        }
    }

    openPlanApprovalModal(kind, recordId, title) {
        this.planApprovalKind = kind;
        this.planApprovalRecordId = recordId;
        this.planApprovalTitle = title;
        this.planApprovalRejectionReason = '';
        this.showPlanApprovalModal = true;
    }

    handlePlanApprovalRejectionChange(event) {
        this.planApprovalRejectionReason = event.detail.value;
    }

    handleManagerPlanRejectionChange(event) {
        this.managerPlanRejectionReason = event.detail.value;
    }

    handlePlanApprovalCancel() {
        this.closePlannerModal(() => {
            this.showPlanApprovalModal = false;
            this.planApprovalKind = '';
            this.planApprovalRecordId = '';
            this.planApprovalTitle = '';
            this.planApprovalRejectionReason = '';
        });
    }

    async handlePlanApprovalApprove() {
        if (!this.planApprovalRecordId) {
            return;
        }
        this.isSaving = true;
        try {
            if (this.planApprovalKind === 'tot') {
                await approveTotRequest({ requestId: this.planApprovalRecordId });
                this.showToast('Approved', 'Time off request approved.', 'success');
            } else if (this.planApprovalKind === 'meeting') {
                await approveMeetingPlan({ meetingId: this.planApprovalRecordId });
                this.showToast('Approved', 'Meeting approved.', 'success');
            }
            this.adjustSelectedViewerPendingCount(-1);
            this.showPlanApprovalModal = false;
            await this.loadWeek();
        } catch (error) {
            this.showToast('Approve failed', this.reduceError(error), 'error');
        } finally {
            this.isSaving = false;
        }
    }

    async handlePlanApprovalReject() {
        const rejectionReason = (this.planApprovalRejectionReason || '').trim();
        if (!rejectionReason) {
            this.showToast('Rejection reason required', 'Enter a reason before rejecting.', 'error');
            return;
        }
        if (!this.planApprovalRecordId) {
            return;
        }
        this.isSaving = true;
        try {
            if (this.planApprovalKind === 'tot') {
                await rejectTotRequest({
                    requestId: this.planApprovalRecordId,
                    rejectionReason
                });
                this.showToast('Rejected', 'Time off returned to the rep.', 'success');
            } else if (this.planApprovalKind === 'meeting') {
                await rejectMeetingPlan({
                    meetingId: this.planApprovalRecordId,
                    rejectionReason
                });
                this.showToast('Rejected', 'Meeting rejected.', 'success');
            }
            this.adjustSelectedViewerPendingCount(-1);
            this.showPlanApprovalModal = false;
            await this.loadWeek();
        } catch (error) {
            this.showToast('Reject failed', this.reduceError(error), 'error');
        } finally {
            this.isSaving = false;
        }
    }

    async handleManagerApproveVisit() {
        const visitId = this.visitDetailId;
        if (!visitId) {
            return;
        }
        this.isSaving = true;
        try {
            const saved = await approvePlanVisit({ visitId });
            this.replaceVisit(saved);
            this.adjustSelectedViewerPendingCount(-1);
            await this.loadWeek();
            this.showToast('Approved', 'Visit is now scheduled.', 'success');
            this.showVisitDetailModal = false;
            this.visitDetailId = '';
            this.managerPlanRejectionReason = '';
        } catch (error) {
            this.showToast('Approve failed', this.reduceError(error), 'error');
        } finally {
            this.isSaving = false;
        }
    }

    async handleManagerRejectVisit() {
        const visitId = this.visitDetailId;
        const rejectionReason = (this.managerPlanRejectionReason || '').trim();
        if (!rejectionReason) {
            this.showToast('Rejection reason required', 'Enter a reason before rejecting.', 'error');
            return;
        }
        if (!visitId) {
            return;
        }
        this.isSaving = true;
        try {
            await rejectPlanVisit({ visitId, rejectionReason });
            this.adjustSelectedViewerPendingCount(-1);
            await this.loadWeek();
            this.showToast('Rejected', 'Visit returned to Draft for the rep.', 'success');
            this.showVisitDetailModal = false;
            this.visitDetailId = '';
            this.managerPlanRejectionReason = '';
        } catch (error) {
            this.showToast('Reject failed', this.reduceError(error), 'error');
        } finally {
            this.isSaving = false;
        }
    }

    findVisitById(visitId) {
        if (!visitId) {
            return null;
        }
        const key = normalizeSalesforceId(visitId);
        return (this.visits || []).find((item) => normalizeSalesforceId(item.id) === key) || null;
    }

    resolveVisitIdFromEvent(event) {
        const candidates = [event?.currentTarget, event?.target, event?.target?.closest?.('[data-visit-id]')];
        for (const element of candidates) {
            const visitId = element?.dataset?.visitId;
            if (visitId) {
                return visitId;
            }
        }
        return null;
    }

    async handleVisitDetailRemove() {
        this.showVisitMoreMenu = false;
        const visit = this.visits.find((item) => item.id === this.visitDetailId);
        if (!visit) {
            return;
        }
        const removed = await this.removeVisitById(
            visit.id,
            visit.accountName || visit.name,
            { closeModal: true }
        );
        if (removed) {
            this.showVisitDetailModal = false;
            this.visitDetailId = '';
        }
    }

    async handleVisitDetailPostpone() {
        this.showVisitMoreMenu = false;
        const visit = this.visits.find((item) => item.id === this.visitDetailId);
        if (!visit) {
            return;
        }
        const moved = await this.postponeVisitById(
            visit.id,
            visit.accountName || visit.name,
            { closeModal: true }
        );
        if (moved) {
            this.showVisitDetailModal = false;
            this.visitDetailId = '';
        }
    }

    async handleRouteStopPostpone(event) {
        event?.stopPropagation?.();
        const visitId = this.resolveVisitIdFromEvent(event);
        const visit = this.findVisitById(visitId);
        if (!visit) {
            this.showToast('Postpone failed', 'Visit not found in your plan.', 'error');
            return;
        }
        await this.postponeVisitById(visit.id, visit.accountName);
    }

    async handleRouteStopRemove(event) {
        event?.stopPropagation?.();
        const visitId = this.resolveVisitIdFromEvent(event);
        const visit = this.findVisitById(visitId);
        if (!visit) {
            this.showToast('Remove failed', 'Visit not found in your plan.', 'error');
            return;
        }
        await this.removeVisitById(visit.id, visit.accountName);
    }

    async removeVisitById(visitId, accountName, options = {}) {
        if (this.isReadOnlyPlannerView) {
            this.showToast('Read-only', 'You cannot edit another rep\'s planner.', 'error');
            return false;
        }
        const visit = this.findVisitById(visitId);
        if (!visit) {
            return false;
        }
        if (visit.status === 'Completed') {
            this.showToast('Cannot remove', 'Completed visits cannot be deleted.', 'error');
            return false;
        }
        const label = accountName || visit.accountName || visit.name || 'this visit';
        const confirmed = await LightningConfirm.open({
            message: `Remove ${label} from your plan? This cannot be undone.`,
            variant: 'headerless',
            label: 'Remove visit?'
        });
        if (!confirmed) {
            return false;
        }

        this.isSaving = true;
        try {
            await deleteVisit({ visitId: visit.id });
            await this.loadWeek();
            this.showToast('Visit removed', label, 'success');
            return true;
        } catch (error) {
            this.showToast('Remove failed', this.reduceError(error), 'error');
            return false;
        } finally {
            this.isSaving = false;
        }
    }

    async postponeVisitById(visitId, accountName, options = {}) {
        if (this.isReadOnlyPlannerView) {
            this.showToast('Read-only', 'You cannot edit another rep\'s planner.', 'error');
            return false;
        }
        const visit = this.findVisitById(visitId);
        if (!visit) {
            return false;
        }
        const start = parseSalesforceDateTime(visit.startDateTime);
        const end = parseSalesforceDateTime(visit.endDateTime);
        if (!start || !end) {
            this.showToast('Postpone failed', 'Visit times are missing.', 'error');
            return false;
        }
        const label = accountName || visit.accountName || visit.name || 'this visit';
        const confirmed = await LightningConfirm.open({
            message: `Postpone ${label} to tomorrow at the same time?`,
            variant: 'headerless',
            label: 'Postpone visit?'
        });
        if (!confirmed) {
            return false;
        }

        const tomorrowStart = new Date(start);
        tomorrowStart.setDate(tomorrowStart.getDate() + 1);
        const tomorrowEnd = new Date(end);
        tomorrowEnd.setDate(tomorrowEnd.getDate() + 1);

        this.isSaving = true;
        try {
            const updated = isOfflineMode()
                ? await this.queueRescheduleVisits(
                      [visit.id],
                      [tomorrowStart],
                      [tomorrowEnd]
                  )
                : await rescheduleVisits({
                      visitIds: [visit.id],
                      startDateTimes: [toApexDateTime(tomorrowStart)],
                      endDateTimes: [toApexDateTime(tomorrowEnd)]
                  });
            const saved = updated[0];
            if (saved) {
                const others = this.visits.filter((item) => item.id !== saved.id);
                this.visits = [...others, saved].sort(
                    (a, b) => new Date(a.startDateTime) - new Date(b.startDateTime)
                );
                await this.cacheCurrentWeek();
            }
            if (this.isMapView) {
                await this.renderMap();
            }
            this.showToast(
                isOfflineMode() ? 'Queued offline' : 'Visit postponed',
                isOfflineMode()
                    ? `${label} will move to tomorrow when you sync.`
                    : `${label} moved to tomorrow.`,
                'success'
            );
            return true;
        } catch (error) {
            this.showToast('Postpone failed', this.reduceError(error), 'error');
            return false;
        } finally {
            this.isSaving = false;
        }
    }

    openVisitDetailModal(visit) {
        const start = parseSalesforceDateTime(visit.startDateTime);
        const end = parseSalesforceDateTime(visit.endDateTime);
        this.visitDetailId = visit.id;
        this.visitDetailAccountName = visit.accountName || visit.name;
        this.visitDetailStatus = visit.status || VISIT_STATUS_DRAFT;
        this.visitDetailOriginalStatus = visit.status || VISIT_STATUS_DRAFT;
        this.visitDetailCancellationReason = visit.cancellationReason || '';
        this.visitDetailStartDateTime = start ? toSalesforceDateTimeLocal(start) : '';
        this.visitDetailEndDateTime = end ? toSalesforceDateTimeLocal(end) : '';
        this.managerPlanRejectionReason = '';
        this.showVisitMoreMenu = false;
        this.showVisitDetailModal = true;
    }

    parseVisitDetailSchedule() {
        const startIso = normalizeLocalDateTimeString(this.visitDetailStartDateTime);
        const endIso = normalizeLocalDateTimeString(this.visitDetailEndDateTime);
        if (!startIso || !endIso) {
            return { error: 'Visit start and end date/time are required.' };
        }
        const start = new Date(startIso);
        const end = new Date(endIso);
        if (Number.isNaN(start.getTime()) || Number.isNaN(end.getTime())) {
            return { error: 'Enter valid start and end date/time values.' };
        }
        if (end <= start) {
            return { error: 'End time must be after start time.' };
        }
        return { start, end, startIso };
    }

    handleVisitDetailStartChange(event) {
        this.visitDetailStartDateTime = event.detail.value;
    }

    handleVisitDetailEndChange(event) {
        this.visitDetailEndDateTime = event.detail.value;
    }

    handleVisitDetailStatusChange(event) {
        this.visitDetailStatus = event.detail.value;
        if (this.visitDetailStatus !== 'Cancelled') {
            this.visitDetailCancellationReason = '';
        }
    }

    handleVisitDetailCancellationChange(event) {
        this.visitDetailCancellationReason = event.detail.value;
    }

    handleVisitDetailCancel() {
        this.closePlannerModal(() => {
            this.showVisitMoreMenu = false;
            this.showVisitDetailModal = false;
            this.visitDetailId = '';
        });
    }

    handleToggleVisitMoreMenu(event) {
        event?.stopPropagation?.();
        this.showVisitMoreMenu = !this.showVisitMoreMenu;
    }

    handleStartCoaching() {
        const visitId = this.visitDetailId;
        if (visitId) {
            try {
                sessionStorage.setItem('zeta.pwa.openVisitCoaching', visitId);
            } catch (_error) {
                /* ignore */
            }
        }
        this.handleViewVisit();
    }

    handleViewVisit() {
        const visitId = this.visitDetailId;
        this.showVisitMoreMenu = false;
        this.showVisitDetailModal = false;
        this.visitDetailId = '';
        if (!visitId) {
            return;
        }
        this.navigateToRecord(visitId, 'Visit__c');
    }

    async handleVisitDetailSave() {
        const visit = this.visits.find((item) => item.id === this.visitDetailId);
        if (!visit) {
            return;
        }
        const schedule = this.parseVisitDetailSchedule();
        if (schedule.error) {
            this.showToast('Validation', schedule.error, 'error');
            return;
        }
        const validationMessage = validateVisitStatusChange(
            this.visitDetailStatus,
            schedule.startIso,
            this.visitDetailCancellationReason
        );
        if (validationMessage) {
            this.showToast('Validation', validationMessage, 'error');
            return;
        }
        const { start, end } = schedule;
        await this.persistVisit({
            id: visit.id,
            accountId: visit.accountId,
            startDateTime: start,
            endDateTime: end,
            status: this.visitDetailStatus,
            cancellationReason: this.visitDetailCancellationReason
        });
        this.showVisitDetailModal = false;
        this.visitDetailId = '';
    }

    async handleSubmitVisitForApproval() {
        const visitId = this.visitDetailId;
        if (!visitId) {
            return;
        }
        this.isSaving = true;
        try {
            if (isOfflineMode()) {
                const saved = await this.queueSubmitVisit(visitId);
                this.replaceVisit(saved);
                await this.cacheCurrentWeek();
                this.showToast('Queued offline', 'Visit submit will send when you reconnect.', 'success');
            } else {
                const saved = await submitVisit({ visitId });
                this.replaceVisit(saved);
                await this.cacheCurrentWeek();
                this.showToast('Submitted', 'Visit plan sent to your manager for approval.', 'success');
                this.notifyVisitSubmitted();
            }
            this.showVisitDetailModal = false;
            this.visitDetailId = '';
        } catch (error) {
            this.showToast('Submit failed', this.reduceError(error), 'error');
        } finally {
            this.isSaving = false;
        }
    }

    notifyVisitSubmitted() {
        try {
            window.dispatchEvent(new CustomEvent('zeta-visit-submitted'));
        } catch (_err) {
            /* ignore */
        }
    }

    replaceVisit(saved) {
        if (!saved?.id) {
            return;
        }
        const others = this.visits.filter((visit) => visit.id !== saved.id);
        this.visits = [...others, saved].sort(
            (a, b) => new Date(a.startDateTime) - new Date(b.startDateTime)
        );
    }

    async handleSubmitWeek() {
        if (!this.canSubmitWeek) {
            return;
        }
        const drafts = this.draftPlannedVisits;
        let message = `Submit ${drafts.length} draft visit${drafts.length === 1 ? '' : 's'} for manager approval?`;
        if (this.showWeeklyTargetGap) {
            message += `\n\n${this.weeklyTargetGapLabel}`;
        }
        const confirmed = await LightningConfirm.open({
            message,
            label: 'Submit week',
            theme: this.showWeeklyTargetGap ? 'warning' : 'info'
        });
        if (!confirmed) {
            return;
        }
        this.isSaving = true;
        try {
            if (isOfflineMode()) {
                for (const visit of drafts) {
                    const saved = await this.queueSubmitVisit(visit.id);
                    this.replaceVisit(saved);
                }
                await this.cacheCurrentWeek();
                this.showToast(
                    'Queued offline',
                    `${drafts.length} visit${drafts.length === 1 ? '' : 's'} will submit when you reconnect.`,
                    'success'
                );
                return;
            }
            const result = await submitWeekPlans({
                weekStart: toApexDate(this.weekStart),
                weekEnd: toApexDate(this.weekEnd)
            });
            await this.loadWeek();
            const submitted = result?.submittedCount || 0;
            const failed = result?.failedCount || 0;
            if (failed > 0 && submitted > 0) {
                this.showToast(
                    'Week partly submitted',
                    `${submitted} sent for approval. ${failed} could not be submitted.`,
                    'warning'
                );
            } else if (failed > 0) {
                this.showToast(
                    'Submit failed',
                    (result.errors || []).join(' ') || 'No visits could be submitted.',
                    'error'
                );
            } else {
                this.showToast(
                    'Submitted',
                    `${submitted} visit${submitted === 1 ? '' : 's'} sent to your manager for approval.`,
                    'success'
                );
                this.notifyVisitSubmitted();
            }
        } catch (error) {
            this.showToast('Submit failed', this.reduceError(error), 'error');
        } finally {
            this.isSaving = false;
        }
    }

    async persistVisit({
        id,
        accountId,
        zetaProjectId,
        visitObjective,
        startDateTime,
        endDateTime,
        status,
        cancellationReason
    }) {
        if (this.isReadOnlyPlannerView) {
            this.showToast('Read-only', 'You cannot edit another rep\'s planner.', 'error');
            return;
        }
        this.isSaving = true;
        try {
            let saved;
            if (isOfflineMode()) {
                saved = await this.queueUpsertVisit({
                    id,
                    accountId,
                    zetaProjectId,
                    visitObjective,
                    startDateTime,
                    endDateTime,
                    status,
                    cancellationReason
                });
            } else {
                saved = await this.upsertVisitWithWarnAck({
                    visitId: id || null,
                    accountId: accountId || null,
                    startDateTime: toApexDateTime(startDateTime),
                    endDateTime: toApexDateTime(endDateTime),
                    status: status || VISIT_STATUS_DRAFT,
                    visitType: 'Planned (Automatically)',
                    cancellationReason: cancellationReason || null,
                    zetaProjectId: zetaProjectId || null,
                    visitObjective: visitObjective || null
                });
            }
            if (!saved) {
                return;
            }
            const others = this.visits.filter((visit) => visit.id !== saved.id);
            this.visits = [...others, saved].sort(
                (a, b) => new Date(a.startDateTime) - new Date(b.startDateTime)
            );
            await this.cacheCurrentWeek();
            const isPromo = !saved.accountId && saved.zetaProjectId;
            const toastTitle = isOfflineMode()
                ? 'Queued offline'
                : saved.status === VISIT_STATUS_DRAFT
                  ? 'Draft visit saved'
                  : 'Visit updated';
            const toastBody = isPromo
                ? saved.visitObjective || saved.zetaProjectName || 'Promotional event'
                : saved.accountName || saved.name;
            this.showToast(toastTitle, toastBody, 'success');
            if (this.isMapView) {
                await this.renderMap();
            }
        } catch (error) {
            this.showToast('Save failed', this.reduceError(error), 'error');
            await this.loadWeek();
        } finally {
            this.isSaving = false;
        }
    }

    async cacheCurrentWeek() {
        const cacheKey = `${getUserPlannerCacheKey(Id)}_${toDateKey(this.weekStart)}`;
        await putPlannerCache(cacheKey, {
            visits: this.visits,
            timeOffBlocks: this.timeOffBlocks
        });
    }

    async queueUpsertVisit({
        id,
        accountId,
        zetaProjectId,
        visitObjective,
        startDateTime,
        endDateTime,
        status,
        cancellationReason
    }) {
        const clientVisitKey = id && String(id).startsWith('local_') ? id : id || newClientKey('visit');
        const localId = id || clientVisitKey;
        console.log('[Planner] [Offline Visit Creation] Preparing local visit payload...', {
            localId,
            clientVisitKey,
            accountId,
            startDateTime,
            endDateTime,
            status
        });
        await queueOfflineAction({
            actionType: 'UPSERT_VISIT',
            clientVisitKey,
            clientActionKey: newClientKey('upsert'),
            visitId: id && !String(id).startsWith('local_') ? id : null,
            payloadJson: JSON.stringify({
                visitId: id && !String(id).startsWith('local_') ? id : null,
                accountId: accountId || null,
                startDateTime: startDateTime?.toISOString?.() || startDateTime,
                endDateTime: endDateTime?.toISOString?.() || endDateTime,
                status: status || VISIT_STATUS_DRAFT,
                visitType: 'Planned (Automatically)',
                cancellationReason: cancellationReason || null,
                zetaProjectId: zetaProjectId || null,
                visitObjective: visitObjective || null
            })
        });
        const existing = this.findVisitById(localId) || {};
        console.log('[Planner] [Offline Visit Creation] Optimistically added visit to local calendar view.');
        return {
            ...existing,
            id: localId,
            accountId: accountId || existing.accountId,
            zetaProjectId: zetaProjectId || existing.zetaProjectId,
            visitObjective: visitObjective || existing.visitObjective,
            startDateTime: startDateTime?.toISOString?.() || startDateTime,
            endDateTime: endDateTime?.toISOString?.() || endDateTime,
            status: status || VISIT_STATUS_DRAFT || existing.status,
            cancellationReason: cancellationReason || null,
            accountName: existing.accountName || 'Offline visit',
            name: existing.name || 'Offline visit',
            clientVisitKey
        };
    }

    async queueSubmitVisit(visitId) {
        const existing = this.findVisitById(visitId) || { id: visitId };
        const isLocal = visitId && String(visitId).startsWith('local_');
        await queueOfflineAction({
            actionType: 'SUBMIT_VISIT',
            visitId: isLocal ? null : visitId,
            clientVisitKey: existing.clientVisitKey || visitId,
            clientActionKey: newClientKey('submit'),
            payloadJson: JSON.stringify({
                visitId: isLocal ? null : visitId
            })
        });
        return {
            ...existing,
            id: visitId,
            status: VISIT_STATUS_SUBMITTED
        };
    }

    async queueRescheduleVisits(visitIds, starts, ends) {
        await queueOfflineAction({
            actionType: 'RESCHEDULE_VISITS',
            clientActionKey: newClientKey('reschedule'),
            payloadJson: JSON.stringify({
                visitIds,
                startDateTimes: starts.map((d) => d.toISOString()),
                endDateTimes: ends.map((d) => d.toISOString())
            })
        });
        return visitIds.map((visitId, index) => {
            const existing = this.findVisitById(visitId) || { id: visitId };
            return {
                ...existing,
                startDateTime: starts[index].toISOString(),
                endDateTime: ends[index].toISOString()
            };
        });
    }

    minutesToDate(dayKey, minutesFromStart) {
        const [year, month, day] = dayKey.split('-').map(Number);
        const date = new Date(year, month - 1, day, DAY_START_HOUR, 0, 0, 0);
        date.setMinutes(date.getMinutes() + minutesFromStart);
        return date;
    }

    async ensureLeaflet() {
        if (this.leafletReady && window.L) {
            return window.L;
        }
        await ensureLeaflet(this, LEAFLET);
        this.leafletReady = true;
        return window.L;
    }

    clearMapMarkers() {
        this.mapMarkers.forEach((marker) => marker.remove());
        this.mapMarkers = [];
    }

    getVisitPinIcon(pinKind, isOutlier = false) {
        const cacheKey = `${pinKind}${isOutlier ? '-outlier' : ''}`;
        if (!this.visitPinIcons[cacheKey]) {
            this.visitPinIcons[cacheKey] = createVisitPinIcon(pinKind, window.L, isOutlier);
        }
        return this.visitPinIcons[cacheKey];
    }

    addMapMarker(stop, options = {}) {
        const { isCurrentLocation = false, popupHtml, dimmed = false, onClick, isOutlier = false } =
            options;
        let marker;
        if (isCurrentLocation) {
            marker = window.L.circleMarker([stop.latitude, stop.longitude], {
                radius: 10,
                color: '#0176d3',
                fillColor: '#0176d3',
                fillOpacity: 0.95,
                weight: 2
            });
        } else {
            const pinKind = stop.pinKind || 'hcp';
            marker = window.L.marker([stop.latitude, stop.longitude], {
                icon: this.getVisitPinIcon(pinKind, isOutlier),
                opacity: dimmed ? 0.35 : 1
            });
        }
        marker.addTo(this.mapInstance);
        marker.bindPopup(popupHtml || `<strong>${stop.accountName}</strong>`);
        if (onClick) {
            marker.on('click', onClick);
        }
        this.mapMarkers.push(marker);
        return marker;
    }

    buildVisitPopupHtml(stop, order) {
        const typeLabel = stop.accountTypeLabel || resolveAccountTypeLabel(stop.pinKind);
        const metrics = this.buildAccountFootnote(stop);
        const metricsLine = metrics ? `<br/>${metrics}` : '';
        return `<strong>${order}. ${stop.accountName}</strong><br/><span>${typeLabel}</span>${metricsLine}<br/>${stop.timeLabel || ''}`;
    }

    plotStopsOnMap(visitStops, includeCurrentLocation = false, unplannedAccounts = []) {
        this.clearMapMarkers();
        const filters = this.getAccountFilters();
        const unplannedMarkerClick = (stop) => () => {
            if (stop.latitude != null && stop.longitude != null) {
                this.flyToLocation(stop.latitude, stop.longitude);
            }
        };
        const visitMarkerClick = (stop) => () => {
            if (stop.id) {
                this.navigateToRecord(stop.id, 'Visit__c');
                return;
            }
            if (stop.latitude != null && stop.longitude != null) {
                this.flyToLocation(stop.latitude, stop.longitude);
            }
        };
        if (includeCurrentLocation && this.currentLocation) {
            this.addMapMarker(
                {
                    latitude: this.currentLocation.latitude,
                    longitude: this.currentLocation.longitude,
                    accountName: 'Current location'
                },
                {
                    isCurrentLocation: true,
                    popupHtml: '<strong>Current location</strong><br/>Route starting point'
                }
            );
        }
        unplannedAccounts.forEach((account) => {
            const dimmed = !accountMatchesFilters(account, filters);
            this.addMapMarker(account, {
                popupHtml: `<strong>${account.accountName}</strong><br/><span>${account.accountTypeLabel}</span><br/>${this.buildAccountFootnote(account) || 'No visit planned today'}`,
                dimmed,
                onClick: unplannedMarkerClick(account)
            });
        });
        const outlierIds = this.routeOutlierIds;
        visitStops.forEach((stop, index) => {
            const order = includeCurrentLocation ? index + 1 : stop.order;
            const isOutlier = outlierIds.has(normalizeSalesforceId(stop.id));
            const popupSuffix = isOutlier ? '<br/><em>Route outlier — far from other stops</em>' : '';
            this.addMapMarker(stop, {
                isOutlier,
                popupHtml: `${this.buildVisitPopupHtml(stop, order)}${popupSuffix}`,
                onClick: visitMarkerClick(stop)
            });
        });
    }

    async renderMap() {
        await this.ensureLeaflet();
        await this.ensureCurrentLocation();
        const container = this.template.querySelector('.map-container');
        if (!container) {
            return;
        }
        container.innerHTML = '';
        const mapDiv = document.createElement('div');
        mapDiv.style.height = '100%';
        mapDiv.style.width = '100%';
        container.appendChild(mapDiv);

        const visitStops = this.orderedRouteStops;
        const unplannedAccounts = this.unplannedMapAccounts;
        const viewportPoints = this.getRouteViewportPoints();
        const defaultCenter = viewportPoints.length ? viewportPoints[0] : [30.0444, 31.2357];
        const defaultZoom = viewportPoints.length === 1 ? 15 : 12;

        this.mapInstance = window.L.map(mapDiv).setView(defaultCenter, defaultZoom);
        addOsmTileLayer(this.mapInstance, window.L);

        this.plotStopsOnMap(visitStops, Boolean(this.currentLocation), unplannedAccounts);
        this.applyInitialMapViewport();

        if (this.routeLayer) {
            this.mapInstance.removeLayer(this.routeLayer);
            this.routeLayer = undefined;
        }

        window.setTimeout(() => {
            this.mapInstance?.invalidateSize?.();
            this.applyInitialMapViewport();
        }, 100);
    }

    destroyMap() {
        if (this.mapInstance) {
            this.mapInstance.remove();
            this.mapInstance = undefined;
        }
        this.mapMarkers = [];
        this.routeLayer = undefined;
        this.clearAltRouteLayers();
    }

    drawRouteOnMap(route, visitStops) {
        this.applyRouteResult([route], visitStops);
    }

    getRouteCoordinatePoints(visitStops) {
        const points = [];
        if (this.currentLocation) {
            points.push({
                latitude: this.currentLocation.latitude,
                longitude: this.currentLocation.longitude
            });
        }
        visitStops.forEach((stop) => {
            points.push({ latitude: stop.latitude, longitude: stop.longitude });
        });
        return points;
    }

    async handleBuildRoute() {
        if (this.isReadOnlyPlannerView) {
            return;
        }
        const visitStops = this.orderedRouteStops;
        if (visitStops.length < 1) {
            return;
        }

        this.isBuildingRoute = true;
        try {
            if (!this.routeVisitOrder?.length) {
                this.initializeRouteVisitOrder();
            }
            this.currentLocation = await getCurrentPosition();
            await putCachedMapLocation(this.currentLocation);
            const routes = await fetchOsrmRoute(
                buildCoordPath(this.getRouteCoordinatePoints(visitStops)),
                true
            );
            this.applyRouteResult(routes, visitStops);
            this.routeOrderDirty = false;
            this.routeOptimization = undefined;
            this.accountVisitTargets = await getAccountVisitTargets({ contextUserId: this.contextUserId });
        } catch (error) {
            this.showToast('Route failed', error.message || 'Unable to build route.', 'error');
        } finally {
            this.isBuildingRoute = false;
        }
    }

    handleMoveRouteStop(event) {
        event.stopPropagation();
        if (this.isReadOnlyPlannerView) {
            return;
        }
        const visitId = event.currentTarget.dataset.visitId;
        const direction = event.currentTarget.dataset.direction;
        if (!visitId || !direction) {
            return;
        }
        if (!this.routeVisitOrder?.length) {
            this.initializeRouteVisitOrder();
        }
        const order = [...this.routeVisitOrder];
        const index = order.indexOf(visitId);
        if (index < 0) {
            return;
        }
        const swapIndex = direction === 'up' ? index - 1 : index + 1;
        if (swapIndex < 0 || swapIndex >= order.length) {
            return;
        }
        [order[index], order[swapIndex]] = [order[swapIndex], order[index]];
        this.routeVisitOrder = order;
        this.routeOrderDirty = true;
        this.routeOptimization = undefined;
        if (this.mapInstance) {
            this.plotStopsOnMap(
                this.orderedRouteStops,
                Boolean(this.currentLocation),
                this.unplannedMapAccounts
            );
        }
        if (this.currentLocation) {
            this.scheduleRoutePreviewRefresh();
        }
    }

    async handleOptimizeRoute() {
        if (this.isReadOnlyPlannerView) {
            return;
        }
        if (!this.currentLocation) {
            this.showToast('Optimize route', 'Build route first to set your starting location.', 'error');
            return;
        }
        const visitStops = this.orderedRouteStops;
        if (visitStops.length < 2) {
            return;
        }

        this.isOptimizingRoute = true;
        try {
            const visitIds = visitStops.map((stop) => stop.id);
            const coordPath = buildCoordPath(this.getRouteCoordinatePoints(visitStops));
            const [currentRoute, tripData] = await Promise.all([
                fetchOsrmRoute(coordPath),
                fetchOsrmTrip(coordPath)
            ]);
            const suggestedOrder = parseOptimizedVisitOrder(tripData, visitIds);
            const sameOrder =
                suggestedOrder.length === visitIds.length &&
                suggestedOrder.every((visitId, index) => visitId === visitIds[index]);
            if (sameOrder) {
                this.routeOptimization = undefined;
                this.showToast('Route optimized', 'This stop order is already optimal.', 'success');
                return;
            }

            const stopsById = new Map(visitStops.map((stop) => [stop.id, stop]));
            const suggestedPoints = [
                {
                    latitude: this.currentLocation.latitude,
                    longitude: this.currentLocation.longitude
                },
                ...suggestedOrder.map((visitId) => stopsById.get(visitId)).filter(Boolean)
            ];
            const suggestedRoute = await fetchOsrmRoute(buildCoordPath(suggestedPoints));
            const savingsMin = Math.max(
                0,
                Math.round((currentRoute.duration - suggestedRoute.duration) / 60)
            );
            const savingsKm = Math.max(
                0,
                Number(((currentRoute.distance - suggestedRoute.distance) / 1000).toFixed(1))
            );

            this.routeOptimization = {
                suggestedOrder,
                savingsMin,
                savingsKm,
                swapHints: buildSwapHints(visitIds, suggestedOrder, stopsById)
            };
        } catch (error) {
            this.showToast('Optimize failed', this.reduceError(error), 'error');
        } finally {
            this.isOptimizingRoute = false;
        }
    }

    async handleApplySuggestedOrder() {
        if (!this.routeOptimization?.suggestedOrder?.length) {
            return;
        }
        this.routeVisitOrder = [...this.routeOptimization.suggestedOrder];
        this.routeOrderDirty = true;
        await this.handleUpdateRouteAndCalendar();
    }

    async handleUpdateRouteAndCalendar() {
        if (this.isReadOnlyPlannerView) {
            return;
        }
        if (!this.currentLocation) {
            this.showToast('Update route', 'Build route first to set your starting location.', 'error');
            return;
        }
        const visitStops = this.orderedRouteStops;
        if (!visitStops.length) {
            return;
        }

        this.isUpdatingRoute = true;
        try {
            const selectedRoute = this.getSelectedRoute();
            const route =
                selectedRoute ||
                (await fetchOsrmRoute(buildCoordPath(this.getRouteCoordinatePoints(visitStops))));
            const legs = selectedRoute?.legs || route.legs;
            const schedules = computeScheduleFromRoute(visitStops, legs);
            const updated = isOfflineMode()
                ? await this.queueRescheduleVisits(
                      schedules.map((item) => item.visitId),
                      schedules.map((item) => item.start),
                      schedules.map((item) => item.end)
                  )
                : await rescheduleVisits({
                      visitIds: schedules.map((item) => item.visitId),
                      startDateTimes: schedules.map((item) => toApexDateTime(item.start)),
                      endDateTimes: schedules.map((item) => toApexDateTime(item.end))
                  });
            const byId = new Map(updated.map((visit) => [visit.id, visit]));
            this.visits = this.visits.map((visit) => byId.get(visit.id) || visit);
            await this.cacheCurrentWeek();
            this.routeVisitOrder = visitStops.map((stop) => stop.id);
            this.applyRouteResult(selectedRoute ? [selectedRoute] : [route], this.orderedRouteStops);
            this.routeOrderDirty = false;
            this.routeOptimization = undefined;
            this.showToast(
                isOfflineMode() ? 'Queued offline' : 'Route updated',
                isOfflineMode()
                    ? 'Visit times will sync when you are back online.'
                    : 'Visit times were rescheduled to match your route.',
                'success'
            );
        } catch (error) {
            this.showToast('Update failed', this.reduceError(error), 'error');
        } finally {
            this.isUpdatingRoute = false;
        }
    }

    navigateToRecord(recordId, objectApiName) {
        this[NavigationMixin.Navigate]({
            type: 'standard__recordPage',
            attributes: { recordId, objectApiName, actionName: 'view' }
        });
    }

    async upsertVisitWithWarnAck(payload, acknowledgeWarnings = false) {
        try {
            return await upsertVisit({
                ...payload,
                acknowledgeWarnings
            });
        } catch (error) {
            const message = this.reduceError(error);
            if (!acknowledgeWarnings && /^WARN:\s*/i.test(message)) {
                const confirmed = window.confirm(
                    `${message.replace(/^WARN:\s*/i, '')}\n\nSave anyway?`
                );
                if (confirmed) {
                    return this.upsertVisitWithWarnAck(payload, true);
                }
                return null;
            }
            throw error;
        }
    }

    showToast(title, message, variant) {
        this.dispatchEvent(new ShowToastEvent({ title, message, variant }));
    }

    reduceError(error) {
        let raw = '';
        if (Array.isArray(error?.body)) {
            raw = error.body.map((item) => item.message).join(', ');
        } else if (error?.body?.output?.errors?.length) {
            raw = error.body.output.errors.map((item) => item.message).join(', ');
        } else if (error?.body?.pageErrors?.length) {
            raw = error.body.pageErrors.map((item) => item.message).join(', ');
        } else {
            raw = error?.body?.message || error?.message || '';
        }
        return this.sanitizePlannerMessage(raw);
    }

    sanitizePlannerMessage(raw) {
        let message = String(raw || '').trim();
        if (!message) {
            return 'Something went wrong. Please try again.';
        }
        if (/script-thrown exception/i.test(message)) {
            return 'Something went wrong. Please try again.';
        }
        if (/failed to fetch|networkerror|cors|network error|load failed|aborterror|timed out|timeout/i.test(message)) {
            return 'Could not reach Salesforce. Check your connection and try again.';
        }
        if (/offline/i.test(message) && /cache|cached/i.test(message)) {
            return 'Planner data is not available offline yet. Open the planner while online first.';
        }
        if (/session expired|unauthorized|401|invalid.?session/i.test(message)) {
            return 'Your session expired. Sign in again to continue.';
        }
        message = message
            .replace(/^Network error\s*-\s*possible CORS issue:\s*/i, '')
            .replace(/FIELD_CUSTOM_VALIDATION_EXCEPTION[,:]\s*/gi, '')
            .replace(/REQUIRED_FIELD_MISSING[,:]\s*/gi, '')
            .replace(/DUPLICATE_VALUE[,:]\s*/gi, '')
            .replace(/^HTTP\s+\d+\s*-?\s*/i, '')
            .trim();
        if (message.endsWith(': []') || message.endsWith(':[]')) {
            message = message.slice(0, message.lastIndexOf(':')).trim();
        }
        if (!message || /script-thrown exception/i.test(message)) {
            return 'Something went wrong. Please try again.';
        }
        return message.length > 280 ? `${message.slice(0, 277)}...` : message;
    }
}