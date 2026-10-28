import { LightningElement, track, wire } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';
import { loadScript, loadStyle } from 'lightning/platformResourceLoader';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import LightningConfirm from 'lightning/confirm';
import Id from '@salesforce/user/Id';
import { MessageContext } from 'lightning/messageService';
import {
    subscribeTerritoryContext,
    unsubscribeTerritoryContext
} from 'c/territoryContextClient';
import { isFieldFeatureEnabled, loadFieldFeatures } from 'c/fieldFeatureFlags';

import LEAFLET from '@salesforce/resourceUrl/leaflet';
import fetchPlannerData from '@salesforce/apex/FieldPlannerController.fetchPlannerData';
import getPlannerViewerContext from '@salesforce/apex/FieldPlannerController.getPlannerViewerContext';
import deleteVisit from '@salesforce/apex/FieldPlannerController.deleteVisit';
import rescheduleVisits from '@salesforce/apex/FieldPlannerController.rescheduleVisits';
import getCallReportPayload from '@salesforce/apex/VisitCallReportController.getCallReportPayload';
import getRatingCaptureContext from '@salesforce/apex/ClmMetricsController.getRatingCaptureContext';
import getCoachingFormContext from '@salesforce/apex/VisitCoachingController.getCoachingFormContext';
import { detectRouteOutliers, formatDistantStopsSummary, normalizeSalesforceId } from 'c/plannerRouteUtils';
import {
    getTodayPlan,
    getUserTodayPlanKey,
    newClientKey,
    putCoachingContext,
    putRatingContext,
    putTodayPlan,
    putVisitPayload
} from 'c/clmOfflineStore';
import { isOfflineMode, queueOfflineAction } from 'c/clmOfflineSync';
import { addOsmTileLayer } from 'c/plannerMapPins';
import { accountThemeFor, accountTypeIconUrl } from 'c/accountTypeTheme';

const OSRM_BASE = 'https://router.project-osrm.org';
const DEFAULT_MAP_CENTER = [30.0444, 31.2357];
const DEFAULT_MAP_ZOOM = 12;
const PLANNER_TAB_API = 'Field_Rep_Planner';
const GOOGLE_MAPS_MAX_STOPS_WITH_ORIGIN = 10;
const GOOGLE_MAPS_MAX_STOPS_WITHOUT_ORIGIN = 11;

function parseSalesforceDateTime(value) {
    if (!value) {
        return null;
    }
    return new Date(value);
}

function toDateKey(date) {
    const pad = (n) => String(n).padStart(2, '0');
    return `${date.getFullYear()}-${pad(date.getMonth() + 1)}-${pad(date.getDate())}`;
}

function toApexDate(date) {
    return toDateKey(date);
}

function toApexDateTime(value) {
    const date = value instanceof Date ? value : new Date(value);
    if (Number.isNaN(date.getTime())) {
        return null;
    }
    return date.toISOString();
}

function toDatetimeLocalValue(date) {
    const pad = (n) => String(n).padStart(2, '0');
    return `${date.getFullYear()}-${pad(date.getMonth() + 1)}-${pad(date.getDate())}T${pad(date.getHours())}:${pad(date.getMinutes())}`;
}

function startOfWeek(date) {
    const d = new Date(date);
    d.setDate(d.getDate() - d.getDay());
    d.setHours(0, 0, 0, 0);
    return d;
}

function addDays(date, days) {
    const d = new Date(date);
    d.setDate(d.getDate() + days);
    return d;
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

function formatTime(date) {
    if (!date) {
        return '';
    }
    return date.toLocaleTimeString([], { hour: '2-digit', minute: '2-digit' });
}

function buildCoordPath(points) {
    return points.map((point) => `${point.longitude},${point.latitude}`).join(';');
}

function resolveAccountPinKind(recordTypeDeveloperName, recordTypeName) {
    const kind = accountThemeFor(recordTypeDeveloperName, recordTypeName).kind;
    return kind === 'account' ? 'hcp' : kind;
}

function resolveAccountTypeLabel(pinKind, recordTypeName) {
    if (recordTypeName) {
        return recordTypeName;
    }
    if (pinKind === 'pharmacy') {
        return 'Pharmacy';
    }
    return pinKind === 'hco' ? 'Healthcare organization' : 'Healthcare professional';
}

function createVisitPinIcon(pinKind) {
    const kind = pinKind === 'pharmacy' || pinKind === 'hco' || pinKind === 'hcp' ? pinKind : 'hcp';
    const colors = { pharmacy: '#176935', hco: '#fdbf29', hcp: '#3f7de5' };
    const titles = { pharmacy: 'Pharmacy', hco: 'HCO', hcp: 'HCP' };
    const glyph = accountTypeIconUrl(kind);
    return window.L.divIcon({
        className: 'map-pin-icon-shell',
        html:
            `<div class="map-pin-marker map-pin-marker-${kind}" title="${titles[kind]}" ` +
            `style="width:30px;height:30px;border-radius:50%;background:#fff;border:2px solid ${colors[kind]};` +
            `box-shadow:0 2px 6px rgba(0,0,0,.35);display:flex;align-items:center;justify-content:center;">` +
            `<img src="${glyph}" alt="" style="width:20px;height:20px;object-fit:contain;" /></div>`,
        iconSize: [30, 30],
        iconAnchor: [15, 15],
        popupAnchor: [0, -16]
    });
}

function resolveStatusMeta(status) {
    if (status === 'Draft') {
        return { label: 'Draft', statusClass: 'status-pill status-draft' };
    }
    if (status === 'Scheduled' || status === 'Rescheduled') {
        return { label: status, statusClass: 'status-pill status-scheduled' };
    }
    if (status === 'Completed') {
        return { label: 'Completed', statusClass: 'status-pill status-completed' };
    }
    if (status === 'Cancelled') {
        return { label: 'Cancelled', statusClass: 'status-pill status-cancelled' };
    }
    return { label: status || 'Visit', statusClass: 'status-pill' };
}

function getCurrentPosition() {
    return new Promise((resolve, reject) => {
        if (!navigator.geolocation) {
            reject(new Error('Geolocation is not supported in this browser.'));
            return;
        }
        navigator.geolocation.getCurrentPosition(
            (position) =>
                resolve({
                    latitude: position.coords.latitude,
                    longitude: position.coords.longitude
                }),
            (error) => {
                const messages = {
                    1: 'Location permission denied.',
                    2: 'Unable to determine your location.',
                    3: 'Location request timed out.'
                };
                reject(new Error(messages[error.code] || 'Unable to get your current location.'));
            },
            { enableHighAccuracy: true, timeout: 15000, maximumAge: 60000 }
        );
    });
}

async function fetchOsrmRoute(coordPath, alternatives = false) {
    const altParam = alternatives ? '&alternatives=true&continue_straight=false' : '';
    const url = `${OSRM_BASE}/route/v1/driving/${coordPath}?overview=full&geometries=geojson${altParam}`;
    const response = await fetch(url);
    const data = await response.json();
    if (data.code !== 'Ok' || !data.routes?.length) {
        throw new Error('No route returned from routing service.');
    }
    if (alternatives) {
        return data.routes;
    }
    return data.routes[0];
}

async function fetchOsrmTrip(coordPath) {
    const url = `${OSRM_BASE}/trip/v1/driving/${coordPath}?source=first&roundtrip=false&geometries=geojson`;
    const response = await fetch(url);
    return response.json();
}

function parseOptimizedVisitOrder(tripResponse, visitIds) {
    const waypoints = tripResponse.waypoints || [];
    const visitIndices = waypoints
        .map((waypoint, inputIndex) => ({ inputIndex, tripIndex: waypoint.waypoint_index }))
        .filter((item) => item.inputIndex > 0)
        .sort((a, b) => a.tripIndex - b.tripIndex)
        .map((item) => item.inputIndex - 1);
    return visitIndices.map((index) => visitIds[index]).filter(Boolean);
}

function waitForDom() {
    return new Promise((resolve) => {
        window.requestAnimationFrame(() => {
            window.setTimeout(resolve, 0);
        });
    });
}

function formatMapCoord(point) {
    return `${point.latitude},${point.longitude}`;
}

function limitStopsForGoogleMaps(stops, hasOrigin) {
    const maxStops = hasOrigin ? GOOGLE_MAPS_MAX_STOPS_WITH_ORIGIN : GOOGLE_MAPS_MAX_STOPS_WITHOUT_ORIGIN;
    if (stops.length <= maxStops) {
        return { stops, truncatedCount: 0 };
    }
    return { stops: stops.slice(0, maxStops), truncatedCount: stops.length - maxStops };
}

function buildGoogleMapsDirectionsUrl(stops, originLocation) {
    if (!stops?.length) {
        return null;
    }

    const params = new URLSearchParams();
    params.set('api', '1');
    params.set('travelmode', 'driving');

    if (stops.length === 1) {
        if (originLocation) {
            params.set('origin', formatMapCoord(originLocation));
        }
        params.set('destination', formatMapCoord(stops[0]));
        return `https://www.google.com/maps/dir/?${params.toString()}`;
    }

    if (originLocation) {
        params.set('origin', formatMapCoord(originLocation));
        params.set('destination', formatMapCoord(stops[stops.length - 1]));
        const intermediates = stops.slice(0, -1);
        if (intermediates.length) {
            params.set('waypoints', intermediates.map(formatMapCoord).join('|'));
        }
    } else {
        params.set('origin', formatMapCoord(stops[0]));
        params.set('destination', formatMapCoord(stops[stops.length - 1]));
        const intermediates = stops.slice(1, -1);
        if (intermediates.length) {
            params.set('waypoints', intermediates.map(formatMapCoord).join('|'));
        }
    }

    return `https://www.google.com/maps/dir/?${params.toString()}`;
}

export default class FieldRepHomeTodayPlan extends NavigationMixin(LightningElement) {
    @track isLoading = true;
    @track upNextVisits = [];
    @track routeSummary;
    @track optimizationIdeas = [];
    @track routeOutliers = [];
    @track outlierVisitIds = [];
    @track unlinkedVisitCount = 0;
    @track plannerViewerContext;
    @track selectedContextUserId;
    @track selectedTerritoryId;
    @track showViewerMenu = false;
    @track isMutatingVisit = false;
    @track showPostponeModal = false;
    postponeVisitId = '';
    postponeAccountLabel = '';
    postponeDateTime = '';
    postponeDurationMs = 0;
    featureEnabled = true;

    leafletReady = false;
    mapInstance;
    mapMarkers = [];
    markersByVisitId = {};
    routeLayer;
    selectedVisitId;
    currentLocation;
    _messageContext;
    territoryContextSubscription;

    @wire(MessageContext)
    wiredMessageContext(value) {
        this._messageContext = value;
        this.subscribeTerritoryContext();
    }

    connectedCallback() {
        this.subscribeTerritoryContext();
        void this.bootstrapWithFeatures();
    }

    async bootstrapWithFeatures() {
        await loadFieldFeatures();
        this.featureEnabled = isFieldFeatureEnabled('home.todayPlan');
        if (this.featureEnabled) {
            this.bootstrap();
        } else {
            this.isLoading = false;
        }
    }

    disconnectedCallback() {
        this.closeViewerMenu();
        this.destroyMap();
        unsubscribeTerritoryContext(this.territoryContextSubscription);
        this.territoryContextSubscription = undefined;
    }

    subscribeTerritoryContext() {
        if (this.territoryContextSubscription || !this._messageContext) {
            return;
        }
        this.territoryContextSubscription = subscribeTerritoryContext(this._messageContext, () => {
            this.destroyMap();
            void this.bootstrap();
        });
    }

    get hasNoVisits() {
        return !this.upNextVisits || this.upNextVisits.length === 0;
    }

    get geoVisits() {
        return (this.upNextVisits || []).filter((v) => v.hasLocation);
    }

    get canSwitchView() {
        return this.plannerViewerContext?.canSwitchView === true;
    }

    get viewerOptions() {
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
            const val = option.userId;
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
                userName: person,
                pendingApprovalCount: Number(option.pendingApprovalCount) || 0
            });
        });
        return options;
    }

    get viewerMenuItems() {
        return this.viewerOptions.map((option, index) => {
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
                className: `today-plan-viewer-option${selected ? ' is-selected' : ''}`
            };
        });
    }

    get selectedViewerLabel() {
        if (this.isViewingSelf) {
            return 'My territory';
        }
        return this.selectedTerritoryOption?.label || 'My territory';
    }

    get selectedTerritoryOption() {
        if (this.selectedTerritoryId) {
            const byTerritory = this.viewerOptions.find(
                (option) =>
                    option.territoryId && sameSalesforceId(option.territoryId, this.selectedTerritoryId)
            );
            if (byTerritory) {
                return byTerritory;
            }
        }
        return this.viewerOptions.find(
            (option) => option.value && sameSalesforceId(option.value, this.selectedContextUserId)
        );
    }

    get viewerPendingTotal() {
        const seen = new Set();
        return this.viewerOptions.reduce((sum, option) => {
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
        return `today-plan-viewer-trigger${this.showViewerMenu ? ' is-open' : ''}`;
    }

    get viewerMenuExpanded() {
        return this.showViewerMenu ? 'true' : 'false';
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

    get selectedRepDisplayName() {
        if (this.isViewingSelf) {
            return null;
        }
        const option = this.selectedTerritoryOption;
        return option?.userName || option?.label || 'Selected rep';
    }

    get viewingOtherBanner() {
        if (this.isViewingSelf) {
            return null;
        }
        return `Viewing ${this.selectedRepDisplayName}'s plan (read-only)`;
    }

    get planSubtitle() {
        const datePart = this.todayLabel;
        const stopsPart = this.stopsLabel;
        if (this.isViewingSelf) {
            return `${datePart} · ${stopsPart}`;
        }
        return `${datePart} · ${this.selectedRepDisplayName} · ${stopsPart}`;
    }

    get hasOptimizationIdeas() {
        return (this.optimizationIdeas || []).length > 0;
    }

    get hasRouteOutliers() {
        return (this.routeOutliers || []).length > 0;
    }

    get distantStopsSummary() {
        return formatDistantStopsSummary(this.routeOutliers);
    }

    get decoratedRouteOutliers() {
        return (this.routeOutliers || []).map((outlier) => ({
            ...outlier,
            canAct: this.canMutatePlan
        }));
    }

    get canMutatePlan() {
        return this.isViewingSelf;
    }

    get todayLabel() {
        return new Date().toLocaleDateString([], {
            weekday: 'long',
            month: 'short',
            day: 'numeric'
        });
    }

    get stopsLabel() {
        const count = this.upNextVisits?.length || 0;
        const geo = this.geoVisits.length;
        if (count === 0) {
            return this.isViewingSelf ? 'No account visits today' : 'No account visits scheduled';
        }
        if (geo === count) {
            return count === 1 ? '1 stop on route' : `${count} stops on route`;
        }
        return `${count} stops · ${geo} on map`;
    }

    get visitCountLabel() {
        return this.stopsLabel;
    }

    get showUnlinkedNote() {
        return this.unlinkedVisitCount > 0;
    }

    get unlinkedNote() {
        const n = this.unlinkedVisitCount;
        return n === 1
            ? '1 visit without an account is hidden. Link it in Planner.'
            : `${n} visits without an account are hidden. Link them in Planner.`;
    }

    get isGoogleNavigateDisabled() {
        return (this.geoVisits?.length || 0) === 0;
    }

    get googleNavigateTitle() {
        const count = this.geoVisits?.length || 0;
        if (count === 0) {
            return 'Add geocoded account visits to navigate';
        }
        if (count === 1) {
            return 'Open route to 1 stop in Google Maps';
        }
        return `Open route with ${count} stops in Google Maps`;
    }

    showToast(title, message, variant) {
        this.dispatchEvent(new ShowToastEvent({ title, message, variant }));
    }

    setOptimizationIdeas(ideas) {
        this.optimizationIdeas = (ideas || []).map((idea, index) => {
            if (typeof idea === 'string') {
                return {
                    id: `idea-${index}`,
                    type: 'info',
                    text: idea,
                    isInfo: true,
                    isOutlier: false,
                    itemClass: 'ideas-item',
                    iconName: 'utility:light_bulb',
                    iconClass: 'ideas-icon'
                };
            }
            const isOutlier = idea.type === 'outlier';
            return {
                ...idea,
                id: idea.id || `idea-${index}`,
                type: idea.type || 'info',
                isInfo: (idea.type || 'info') === 'info',
                isOutlier,
                itemClass: isOutlier ? 'ideas-item ideas-item-outlier' : 'ideas-item',
                iconName: isOutlier ? 'utility:warning' : 'utility:light_bulb',
                iconClass: isOutlier ? 'ideas-icon ideas-icon-warning' : 'ideas-icon'
            };
        });
    }

    updateOutlierState(outliers) {
        this.routeOutliers = outliers || [];
        this.outlierVisitIds = this.routeOutliers.map((item) => item.visitId);
    }

    async bootstrap() {
        if (isOfflineMode()) {
            await this.loadViewerContext();
            await this.loadCachedTodayPlan();
            await waitForDom();
            await this.initializeMapView();
            return;
        }
        await this.loadViewerContext();
        await this.loadTodayPlan();
    }

    async loadViewerContext() {
        try {
            this.plannerViewerContext = await getPlannerViewerContext();
            this.selectedContextUserId = this.plannerViewerContext?.defaultUserId;
            this.selectedTerritoryId = null;
        } catch (e) {
            this.plannerViewerContext = null;
            this.selectedContextUserId = null;
            this.showToast('Error', this.reduceError(e) || 'Unable to load viewer context.', 'error');
        }
    }

    async handleContextUserChange(event) {
        this.selectedContextUserId = event.detail.value;
        if (Object.prototype.hasOwnProperty.call(event.detail || {}, 'territoryId')) {
            this.selectedTerritoryId = event.detail.territoryId || null;
        }
        this.destroyMap();
        await this.loadTodayPlan();
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
            const wrap = this.template.querySelector('.today-plan-rep-picker');
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

    async loadTodayPlan() {
        this.isLoading = true;
        try {
            const today = new Date();
            const todayKey = toDateKey(today);
            const weekStart = startOfWeek(today);
            const weekEnd = addDays(weekStart, 6);
            const payload = await fetchPlannerData({
                weekStart: toApexDate(weekStart),
                weekEnd: toApexDate(weekEnd),
                contextUserId: this.contextUserId
            });
            const sortedVisits = (payload?.visits || [])
                .filter((v) => {
                    const start = parseSalesforceDateTime(v.startDateTime);
                    return start && toDateKey(start) === todayKey;
                })
                .map((v) => this.normalizeVisit(v))
                .sort((a, b) => new Date(a.startDateTime) - new Date(b.startDateTime));

            const accountVisits = sortedVisits.filter((v) => v.accountId);
            this.unlinkedVisitCount = sortedVisits.length - accountVisits.length;
            this.selectedVisitId = accountVisits[0]?.id || null;
            this.upNextVisits = accountVisits.map((v, index) => this.decorateVisit(v, index));
            await putTodayPlan(getUserTodayPlanKey(Id), this.upNextVisits);
            this.prefetchVisitPayloads(accountVisits.map((visit) => visit.id));
        } catch (e) {
            const restored = await this.loadCachedTodayPlan();
            if (!restored) {
                this.setOptimizationIdeas(['Unable to load today’s plan.']);
                this.showToast('Error loading today plan', this.reduceError(e), 'error');
            }
        } finally {
            this.isLoading = false;
        }

        await waitForDom();
        await this.initializeMapView();
    }

    async loadCachedTodayPlan() {
        try {
            const cached = await getTodayPlan(getUserTodayPlanKey(Id));
            if (!cached?.length) {
                this.upNextVisits = [];
                return false;
            }
            this.upNextVisits = cached;
            this.selectedVisitId = cached[0]?.id || null;
            this.setOptimizationIdeas(['Showing cached today plan from device.']);
            return true;
        } catch (error) {
            this.upNextVisits = [];
            return false;
        }
    }

    prefetchVisitPayloads(visitIds) {
        (visitIds || []).forEach((visitId) => {
            if (!visitId) {
                return;
            }
            getCallReportPayload({ visitId })
                .then((payload) => putVisitPayload(visitId, payload))
                .catch(() => {
                    // Best effort cache for offline visits.
                });
            getRatingCaptureContext({ visitId, sessionId: null })
                .then((context) => putRatingContext(visitId, context))
                .catch(() => {
                    // Best effort ratings cache.
                });
            getCoachingFormContext({ visitId })
                .then((context) => putCoachingContext(visitId, context))
                .catch(() => {
                    // Best effort coaching cache.
                });
        });
    }

    normalizeVisit(v) {
        const start = parseSalesforceDateTime(v.startDateTime);
        const end = parseSalesforceDateTime(v.endDateTime);
        const pinKind = resolveAccountPinKind(v.accountRecordTypeDeveloperName, v.accountRecordTypeName);
        const latitude =
            v.accountLatitude != null && v.accountLatitude !== ''
                ? Number(v.accountLatitude)
                : null;
        const longitude =
            v.accountLongitude != null && v.accountLongitude !== ''
                ? Number(v.accountLongitude)
                : null;
        const hasLocation = Number.isFinite(latitude) && Number.isFinite(longitude);

        return {
            id: v.id,
            visitName: v.name,
            accountName: v.accountName,
            accountId: v.accountId,
            status: v.status,
            visitType: v.visitType,
            accountSpecialty: v.accountSpecialty,
            accountRecordTypeDeveloperName: v.accountRecordTypeDeveloperName,
            accountRecordTypeName: v.accountRecordTypeName,
            pinKind,
            typeIconUrl: accountTypeIconUrl(pinKind),
            accountTypeLabel: resolveAccountTypeLabel(pinKind, v.accountRecordTypeName),
            startDateTime: v.startDateTime,
            endDateTime: v.endDateTime,
            latitude,
            longitude,
            hasLocation,
            timeLabel:
                start && end
                    ? `${formatTime(start)} – ${formatTime(end)}`
                    : formatTime(start)
        };
    }

    decorateVisit(visit, index) {
        const isSelected = visit.id === this.selectedVisitId;
        const visitIdKey = normalizeSalesforceId(visit.id);
        const isOutlier = (this.outlierVisitIds || []).some(
            (id) => normalizeSalesforceId(id) === visitIdKey
        );
        const statusMeta = resolveStatusMeta(visit.status);
        const outlierSuffix = isOutlier ? ' route-stop-outlier' : '';
        return {
            ...visit,
            order: index + 1,
            orderLabel: String(index + 1),
            orderClass: `route-stop-order route-stop-order-${visit.pinKind}${isOutlier ? ' route-stop-order-outlier' : ''}`,
            stopClass: `route-stop${isSelected ? ' route-stop-selected' : ''}${outlierSuffix}`,
            statusLabel: statusMeta.label,
            statusClass: statusMeta.statusClass,
            isOutlier,
            canMutate: this.canMutatePlan && visit.status !== 'Completed' && !isOutlier
        };
    }

    refreshVisitSelection() {
        this.upNextVisits = (this.upNextVisits || []).map((v, index) => this.decorateVisit(v, index));
    }

    async initializeMapView() {
        try {
            await this.ensureLeaflet();
            await this.renderMap();
            await this.computeRouteAndOptimization();
        } catch (e) {
            this.setOptimizationIdeas(['Unable to load today’s plan map.']);
        }
    }

    async ensureLeaflet() {
        if (this.leafletReady && window.L) {
            return;
        }
        await loadStyle(this, LEAFLET + '/leaflet.css');
        await loadScript(this, LEAFLET + '/leaflet.js');
        delete window.L.Icon.Default.prototype._getIconUrl;
        window.L.Icon.Default.mergeOptions({
            iconRetinaUrl: LEAFLET + '/marker-icon-2x.png',
            iconUrl: LEAFLET + '/marker-icon.png',
            shadowUrl: LEAFLET + '/marker-shadow.png'
        });
        this.leafletReady = true;
    }

    destroyMap() {
        if (this.mapInstance) {
            this.mapInstance.remove();
            this.mapInstance = undefined;
        }
        this.mapMarkers = [];
        this.markersByVisitId = {};
        this.routeLayer = undefined;
    }

    fitAllVisits() {
        const points = this.geoVisits;
        if (!this.mapInstance || !points.length) {
            return;
        }
        if (points.length === 1) {
            this.mapInstance.setView([points[0].latitude, points[0].longitude], 15);
            return;
        }
        const bounds = window.L.latLngBounds(points.map((p) => [p.latitude, p.longitude]));
        this.mapInstance.fitBounds(bounds.pad(0.15), { maxZoom: 14 });
    }

    flyToVisit(visitId, animate = true) {
        const visit = (this.upNextVisits || []).find((v) => v.id === visitId);
        if (!visit?.latitude || !visit?.longitude || !this.mapInstance) {
            return;
        }
        const latlng = [visit.latitude, visit.longitude];
        if (animate) {
            this.mapInstance.flyTo(latlng, 16, { duration: 0.75 });
        } else {
            this.mapInstance.setView(latlng, 16);
        }
        const marker = this.markersByVisitId[visitId];
        if (marker) {
            window.setTimeout(() => marker.openPopup(), animate ? 400 : 0);
        }
    }

    buildVisitPopupHtml(visit) {
        return `<strong>${visit.order}. ${visit.accountName}</strong><br/><span>${visit.accountTypeLabel}</span><br/>${visit.timeLabel}<br/><span>${visit.statusLabel}</span>`;
    }

    async renderMap() {
        await this.ensureLeaflet();
        const container = this.template.querySelector('.map-container');
        if (!container) {
            return;
        }

        this.destroyMap();
        container.innerHTML = '';
        const mapDiv = document.createElement('div');
        mapDiv.className = 'map-canvas';
        container.appendChild(mapDiv);

        const points = this.geoVisits;
        const defaultCenter = points.length ? [points[0].latitude, points[0].longitude] : DEFAULT_MAP_CENTER;
        const defaultZoom = points.length === 1 ? 15 : DEFAULT_MAP_ZOOM;

        this.mapInstance = window.L.map(mapDiv, { attributionControl: true }).setView(
            defaultCenter,
            defaultZoom
        );
        addOsmTileLayer(this.mapInstance, window.L);

        try {
            if (this.isViewingSelf) {
                this.currentLocation = await getCurrentPosition();
                window.L.circleMarker([this.currentLocation.latitude, this.currentLocation.longitude], {
                    radius: 10,
                    color: '#0176d3',
                    fillColor: '#0176d3',
                    fillOpacity: 0.95,
                    weight: 2
                })
                    .addTo(this.mapInstance)
                    .bindPopup('<strong>Current location</strong><br/>Route starting point');
            } else {
                this.currentLocation = null;
            }
        } catch (e) {
            this.currentLocation = null;
        }

        points.forEach((v) => {
            const marker = window.L.marker([v.latitude, v.longitude], {
                icon: createVisitPinIcon(v.pinKind)
            }).addTo(this.mapInstance);
            marker.bindPopup(this.buildVisitPopupHtml(v));
            marker.on('click', () => {
                this.selectedVisitId = v.id;
                this.refreshVisitSelection();
            });
            this.mapMarkers.push(marker);
            this.markersByVisitId[v.id] = marker;
        });

        window.setTimeout(() => {
            this.mapInstance?.invalidateSize?.();
            if (this.selectedVisitId) {
                this.flyToVisit(this.selectedVisitId, false);
            } else {
                this.fitAllVisits();
            }
        }, 120);
    }

    async computeRouteAndOptimization() {
        this.routeSummary = null;
        this.updateOutlierState([]);
        this.setOptimizationIdeas([]);

        const geoStops = this.geoVisits.map((v) => ({
            id: v.id,
            accountName: v.accountName,
            latitude: v.latitude,
            longitude: v.longitude
        }));
        const outliers = detectRouteOutliers(geoStops);
        this.updateOutlierState(outliers);
        this.refreshVisitSelection();

        const infoIdeas = [];
        const points = geoStops.map((v) => ({ latitude: v.latitude, longitude: v.longitude }));

        if (points.length < 2) {
            this.setOptimizationIdeas([]);
            return;
        }

        const coordPath = buildCoordPath(points);

        try {
            const selectedRoute = await fetchOsrmRoute(coordPath, false);
            const coords = selectedRoute.geometry.coordinates.map(([lng, lat]) => [lat, lng]);
            this.routeLayer = window.L.polyline(coords, { color: '#2e7d32', weight: 5, opacity: 0.85 });
            this.routeLayer.addTo(this.mapInstance);
            this.mapInstance.fitBounds(this.routeLayer.getBounds().pad(0.15));

            this.routeSummary = {
                durationMin: Math.round(selectedRoute.duration / 60),
                distanceKm: (selectedRoute.distance / 1000).toFixed(1)
            };

            const tripResponse = await fetchOsrmTrip(coordPath);
            const trip = tripResponse?.trips?.[0];
            if (trip) {
                const originalVisitIds = this.upNextVisits.map((v) => v.id);
                const optimizedOrder = parseOptimizedVisitOrder(tripResponse, originalVisitIds);
                const isSameOrder =
                    optimizedOrder?.length === originalVisitIds.length &&
                    optimizedOrder.every((id, idx) => id === originalVisitIds[idx]);
                const savingsMin = Math.round((selectedRoute.duration - trip.duration) / 60);

                if (!isSameOrder && savingsMin >= 1) {
                    infoIdeas.push(
                        `Reordering stops could reduce estimated travel time by about ${savingsMin} minutes. Open Planner to apply the suggested stop order.`
                    );
                }
            }
        } catch (e) {
            // Keep the route estimate; skip placeholder ideas when optimization is unavailable.
        }

        this.setOptimizationIdeas(infoIdeas);
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

    findVisitById(visitId) {
        if (!visitId) {
            return null;
        }
        const key = normalizeSalesforceId(visitId);
        return (this.upNextVisits || []).find((visit) => normalizeSalesforceId(visit.id) === key) || null;
    }

    async handlePostponeVisit(event) {
        event?.stopPropagation?.();
        const visitId = this.resolveVisitIdFromEvent(event);
        if (!visitId || !this.canMutatePlan) {
            return;
        }
        const visit = this.findVisitById(visitId);
        if (!visit) {
            this.showToast('Postpone failed', 'Visit not found in today’s plan.', 'error');
            return;
        }
        const start = parseSalesforceDateTime(visit.startDateTime);
        const end = parseSalesforceDateTime(visit.endDateTime);
        if (!start || !end) {
            this.showToast('Postpone failed', 'Visit times are missing.', 'error');
            return;
        }
        const defaultStart = new Date(start);
        defaultStart.setDate(defaultStart.getDate() + 1);
        this.postponeVisitId = visit.id;
        this.postponeAccountLabel = visit.accountName || 'this visit';
        this.postponeDurationMs = Math.max(end.getTime() - start.getTime(), 30 * 60 * 1000);
        this.postponeDateTime = toDatetimeLocalValue(defaultStart);
        this.showPostponeModal = true;
    }

    handlePostponeDateTimeChange(event) {
        this.postponeDateTime = event.detail.value;
    }

    handleClosePostponeModal() {
        this.showPostponeModal = false;
        this.postponeVisitId = '';
        this.postponeAccountLabel = '';
        this.postponeDateTime = '';
        this.postponeDurationMs = 0;
    }

    handlePostponeModalContentClick(event) {
        event.stopPropagation();
    }

    async handleConfirmPostpone() {
        if (!this.postponeVisitId || !this.canMutatePlan) {
            return;
        }
        const newStart = this.postponeDateTime ? new Date(this.postponeDateTime) : null;
        if (!newStart || Number.isNaN(newStart.getTime())) {
            this.showToast('Postpone failed', 'Choose a valid date and time.', 'error');
            return;
        }
        const newEnd = new Date(newStart.getTime() + (this.postponeDurationMs || 30 * 60 * 1000));
        const label = this.postponeAccountLabel || 'this visit';
        const whenLabel = newStart.toLocaleString([], {
            month: 'short',
            day: 'numeric',
            hour: '2-digit',
            minute: '2-digit'
        });

        this.isMutatingVisit = true;
        try {
            if (isOfflineMode()) {
                await queueOfflineAction({
                    actionType: 'RESCHEDULE_VISITS',
                    clientActionKey: newClientKey('reschedule'),
                    payloadJson: JSON.stringify({
                        visitIds: [this.postponeVisitId],
                        startDateTimes: [newStart.toISOString()],
                        endDateTimes: [newEnd.toISOString()]
                    })
                });
                this.upNextVisits = (this.upNextVisits || []).filter((row) => row.id !== this.postponeVisitId);
                await putTodayPlan(getUserTodayPlanKey(Id), this.upNextVisits);
                this.handleClosePostponeModal();
                this.showToast(
                    'Queued offline',
                    `${label} will move to ${whenLabel} when you sync.`,
                    'success'
                );
                return;
            }
            await rescheduleVisits({
                visitIds: [this.postponeVisitId],
                startDateTimes: [toApexDateTime(newStart)],
                endDateTimes: [toApexDateTime(newEnd)]
            });
            this.handleClosePostponeModal();
            this.showToast('Visit postponed', `${label} moved to ${whenLabel}.`, 'success');
            await this.loadTodayPlan();
        } catch (error) {
            this.showToast('Postpone failed', this.reduceError(error), 'error');
        } finally {
            this.isMutatingVisit = false;
        }
    }

    async handleRemoveVisit(event) {
        event?.stopPropagation?.();
        const visitId = this.resolveVisitIdFromEvent(event);
        if (!visitId || !this.canMutatePlan) {
            return;
        }
        const visit = this.findVisitById(visitId);
        if (!visit) {
            this.showToast('Remove failed', 'Visit not found in today’s plan.', 'error');
            return;
        }
        if (visit.status === 'Completed') {
            this.showToast('Cannot remove', 'Completed visits cannot be deleted.', 'error');
            return;
        }
        const label = visit.accountName || 'this visit';
        const confirmed = await LightningConfirm.open({
            message: `Remove ${label} from today’s plan? This cannot be undone.`,
            variant: 'headerless',
            label: 'Remove visit?'
        });
        if (!confirmed) {
            return;
        }

        this.isMutatingVisit = true;
        try {
            await deleteVisit({ visitId: visit.id });
            this.showToast('Visit removed', label, 'success');
            await this.loadTodayPlan();
        } catch (error) {
            this.showToast('Remove failed', this.reduceError(error), 'error');
        } finally {
            this.isMutatingVisit = false;
        }
    }

    handleSelectVisit(event) {
        const visitId = event?.currentTarget?.dataset?.visitId;
        if (!visitId || visitId === this.selectedVisitId) {
            return;
        }
        this.selectedVisitId = visitId;
        this.refreshVisitSelection();
        this.flyToVisit(visitId);
    }

    handleOpenVisit(event) {
        event?.stopPropagation?.();
        const visitId = event?.currentTarget?.dataset?.visitId;
        if (!visitId) {
            return;
        }
        this[NavigationMixin.Navigate]({
            type: 'standard__recordPage',
            attributes: { recordId: visitId, objectApiName: 'Visit__c', actionName: 'view' }
        });
    }

    handleOpenAccount(event) {
        event?.stopPropagation?.();
        const accountId = event?.currentTarget?.dataset?.accountId;
        if (!accountId) {
            return;
        }
        this[NavigationMixin.Navigate]({
            type: 'standard__recordPage',
            attributes: { recordId: accountId, objectApiName: 'Account', actionName: 'view' }
        });
    }

    handleOpenPlanner() {
        this[NavigationMixin.Navigate]({
            type: 'standard__navItemPage',
            attributes: { apiName: PLANNER_TAB_API }
        });
    }

    handleNavigateGoogle() {
        const geoStops = this.geoVisits.map((visit) => ({
            latitude: visit.latitude,
            longitude: visit.longitude
        }));

        if (!geoStops.length) {
            this.showToast(
                'No map stops',
                'Add geocoded account visits in Planner to open a Google Maps route.',
                'warning'
            );
            return;
        }

        const originLocation = this.isViewingSelf ? this.currentLocation : null;
        const { stops, truncatedCount } = limitStopsForGoogleMaps(geoStops, Boolean(originLocation));
        const mapsUrl = buildGoogleMapsDirectionsUrl(stops, originLocation);

        if (!mapsUrl) {
            this.showToast('Unable to open route', 'Could not build a Google Maps route.', 'error');
            return;
        }

        this[NavigationMixin.Navigate]({
            type: 'standard__webPage',
            attributes: { url: mapsUrl }
        });

        const stopCount = stops.length;
        const message =
            truncatedCount > 0
                ? `Opened Google Maps with ${stopCount} stops (${truncatedCount} omitted — Google Maps limit).`
                : stopCount === 1
                  ? 'Opened Google Maps with your next stop.'
                  : `Opened Google Maps with ${stopCount} stops in today’s visit order.`;

        this.showToast('Google Maps', message, 'success');
    }

    reduceError(error) {
        if (!error) {
            return null;
        }
        if (typeof error === 'string') {
            return error;
        }
        return error?.body?.message || error?.message || null;
    }
}