import approveExpense from '@salesforce/apex/ExpenseSubmissionController.approveExpense';
import deleteMyExpense from '@salesforce/apex/ExpenseSubmissionController.deleteMyExpense';
import getExpenseDetail from '@salesforce/apex/ExpenseSubmissionController.getExpenseDetail';
import getExpenseTypeOptions from '@salesforce/apex/ExpenseSubmissionController.getExpenseTypeOptions';
import getMyExpenses from '@salesforce/apex/ExpenseSubmissionController.getMyExpenses';
import getTeamExpenses from '@salesforce/apex/ExpenseSubmissionController.getTeamExpenses';
import rejectExpense from '@salesforce/apex/ExpenseSubmissionController.rejectExpense';
import submitExpense from '@salesforce/apex/ExpenseSubmissionController.submitExpense';
import updateMyExpense from '@salesforce/apex/ExpenseSubmissionController.updateMyExpense';
import { LightningElement, wire } from 'lwc';
import LightningConfirm from 'lightning/confirm';
import { NavigationMixin } from 'lightning/navigation';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import {
    CATEGORIES,
    KINDS,
    buildPayload,
    displayFromDescription,
    fieldsFor,
    initialValues,
    invoiceMode,
    parsePacked,
    policyNote,
    primaryDate,
    showsDestinations,
    showsEmployees,
    showsRoute,
    validateExpense,
    valuesFromExpense
} from './expenseFormCatalog';
import getExpenseFormContext from '@salesforce/apex/ExpenseSubmissionController.getExpenseFormContext';
import LEAFLET from '@salesforce/resourceUrl/leaflet';
import { addOsmTileLayer, ensureLeaflet } from 'c/plannerMapPins';
import { fetchOsrmRoute, haversineKm } from 'c/plannerMapUtils';

const FUEL_EGP_PER_LITER = 21.5;
const FUEL_LITERS_PER_100KM = 8.5;
const EGYPT_TOLL_BOOTHS = [
    { name: 'بوابه طريق اسكندريه (بوابه القاهره)', latitude: 30.070708, longitude: 31.0130791 },
    { name: 'Alexandria toll', latitude: 30.9694171, longitude: 29.8278376 },
    { name: 'Toll booth', latitude: 30.7188696, longitude: 30.9776976 },
    { name: 'Toll booth', latitude: 30.0868101, longitude: 30.9738417 },
    { name: 'Toll booth', latitude: 30.1097325, longitude: 31.3860352 },
    { name: 'Toll booth', latitude: 30.1248101, longitude: 31.3999727 },
    { name: 'Toll booth', latitude: 29.8103145, longitude: 31.0534842 },
    { name: 'Toll booth', latitude: 31.1794943, longitude: 29.8775548 }
];

const TYPE_ICONS = {
    Meal: 'utility:retail_execution',
    Transportation: 'utility:travel_and_places',
    Transport: 'utility:travel_and_places',
    Accommodation: 'utility:home',
    Fuel: 'utility:travel_and_places',
    Parking: 'utility:travel_and_places',
    Toll: 'utility:travel_and_places',
    'Client Entertainment': 'utility:groups',
    Conference_Event: 'utility:event',
    Training: 'utility:education',
    'Sample Expense': 'utility:product',
    Communication: 'utility:call',
    Others: 'utility:record'
};

const STATUS_BADGE_CLASS = {
    Approved: 'status-badge status-approved',
    Pending: 'status-badge status-pending',
    Submitted: 'status-badge status-pending',
    Rejected: 'status-badge status-rejected'
};

const STATUS_HELP = {
    Pending: 'Waiting for your manager to approve or reject.',
    Submitted: 'Submitted to your manager and awaiting approval.',
    Approved: 'Approved by your manager. This request can no longer be changed.',
    Rejected: 'Rejected by your manager. Edit it to send it back for approval.'
};

const LOCKED_STATUS = 'Approved';

const MAX_INVOICE_BYTES = 4 * 1024 * 1024;
const MAX_INVOICES = 3;

export default class ExpenseSubmission extends NavigationMixin(LightningElement) {
    isSaving = false;
    isLoadingList = false;
    isLoadingTeam = false;
    showingAllExpenses = false;
    activeTab = 'mine';
    editingId = null;
    modalOpen = false;
    modalStep = 'pick';
    draftKindId = '';
    draft = {};
    fieldErrors = {};
    formError = '';
    invoiceFiles = [];
    employeeDraft = '';
    attendees = [];
    attendeeStatus = '';
    routeStops = [];
    routeStatus = '';
    routeDate = '';
    placeResults = [];
    activePlaceKey = '';
    placeMapOpen = false;
    placeSearchToken = 0;
    placeMenuStyle = '';
    openSelectKey = '';
    selectMenuStyle = '';
    tripDistanceKm = null;
    tripFuelLiters = '';
    tripFuelCost = '';
    tripStatus = '';
    tripTolls = [];
    tripGeometry = [];
    tripQuoteKey = '';
    destinationDraft = { from: '', to: '', km: '' };
    destinationError = '';
    historyExpenses = [];
    historyLoaded = false;

    typeOptions = [];
    myExpenses = [];
    teamExpenses = [];
    expensesError;
    teamError;
    selectedDetail = null;
    selectedDetailId = null;
    rejectionReasonByExpenseId = {};

    connectedCallback() {
        this.loadExpenses(10);
        this.loadTeamExpenses();
    }

    disconnectedCallback() {
        this.destroyMaps();
        this.lowerModalLayer();
    }

    renderedCallback() {
        if (!this.modalOpen) {
            return;
        }
        if (this.placeMapOpen && this.activePlaceKey && this._drawnPlace !== this.activePlaceKey) {
            this._drawnPlace = this.activePlaceKey;
            this.drawPlaceMap();
        }
        const routeToken = this.routeMapToken;
        if (this.showRoute && routeToken && this._drawnRoute !== routeToken) {
            this._drawnRoute = routeToken;
            this.drawRouteMap();
        }
        const tripToken = this.tripMapToken;
        if (tripToken && this._drawnTrip !== tripToken) {
            this._drawnTrip = tripToken;
            this.drawTripMap();
        }
        this.repositionFloatingMenus();
    }

    @wire(getExpenseTypeOptions)
    wiredTypeOptions({ data, error }) {
        if (data?.length) {
            this.typeOptions = data;
        } else if (error) {
            this.typeOptions = [];
        }
    }

    get isMyTab() {
        return this.activeTab === 'mine';
    }

    get isTeamTab() {
        return this.activeTab === 'team';
    }

    get myTabClass() {
        return this.isMyTab ? 'tab is-active' : 'tab';
    }

    get teamTabClass() {
        return this.isTeamTab ? 'tab is-active' : 'tab';
    }

    get isEditing() {
        return Boolean(this.editingId);
    }

    get headerSubtitle() {
        return this.isTeamTab
            ? 'Review requests from your team.'
            : 'Choose a category, then enter the details for that expense.';
    }

    get categoryGroups() {
        return CATEGORIES.map((category) => ({
            ...category,
            cards: category.kinds.map((kindId) => {
                const card = KINDS[kindId];
                return {
                    ...card,
                    railClass: this.draftKindId === card.id ? 'rail-item is-selected' : 'rail-item'
                };
            })
        }));
    }

    get isPickerStep() {
        return this.modalStep === 'pick';
    }

    get isFormStep() {
        return this.modalStep === 'form';
    }

    get modalTitle() {
        return this.hasDraftKind ? KINDS[this.draftKindId]?.label || 'Expense' : this.isEditing ? 'Edit expense' : 'New expense';
    }

    get modalHint() {
        if (this.isPickerStep) {
            return 'Pick the expense that matches the receipt or allowance.';
        }
        return this.isEditing
            ? 'Update the details and save. A rejected request goes back to your manager.'
            : KINDS[this.draftKindId]?.blurb || '';
    }

    get hasDraftKind() {
        return Boolean(this.draftKindId);
    }

    get showRoute() {
        return showsRoute(this.draftKindId, this.draft);
    }

    get hasRouteStops() {
        return this.routeStops.length > 0;
    }

    get hasRouteCoords() {
        return this.routeStops.some((stop) => stop.latitude && stop.longitude);
    }

    get selectMenuOpen() {
        return Boolean(this.openSelectKey);
    }

    get placeMenuOpen() {
        return Boolean(this.activePlaceKey) && this.placeResults.length > 0;
    }

    get floatingMenuOpen() {
        return this.selectMenuOpen || this.placeMenuOpen;
    }

    get selectMenuOptions() {
        const field = fieldsFor(this.draftKindId, this.draft).find((entry) => entry.key === this.openSelectKey);
        if (!field) {
            return [];
        }
        const current = this.draft[field.key] ?? '';
        return (field.options || [])
            .filter((option) => option.value)
            .map((option) => ({
                ...option,
                className: option.value === current ? 'menu-option is-selected' : 'menu-option'
            }));
    }

    get showTripQuote() {
        return this.tripDistanceKm != null;
    }

    get hasTolls() {
        return this.tripTolls.length > 0;
    }

    get tripDistanceLabel() {
        return `${Number(this.tripDistanceKm).toFixed(1)} km`;
    }

    get tripFuelRateLabel() {
        return FUEL_EGP_PER_LITER.toFixed(2);
    }

    get tripMapToken() {
        if (!this.tripGeometry.length) {
            return '';
        }
        return `${this.tripQuoteKey}:${this.tripTolls.length}`;
    }

    get hasTripMap() {
        return this.tripGeometry.length > 1;
    }

    get fuelUseLabel() {
        return String(FUEL_LITERS_PER_100KM);
    }

    get placeMenuResults() {
        return this.placeResults.map((hit, index) => ({
            ...hit,
            index,
            key: `${hit.lat}-${hit.lng}-${index}`
        }));
    }

    get routeMapToken() {
        return this.routeStops.map((stop) => stop.id).join('|');
    }

    get hasAttendeeMatches() {
        return this.attendeeMatches.length > 0;
    }

    get attendeeMatches() {
        const query = (this.employeeDraft || '').trim().toLowerCase();
        const chosen = new Set((this.draft.employees || []).map((name) => name.toLowerCase()));
        return this.attendees
            .filter((person) => {
                if (chosen.has(String(person.name || '').toLowerCase())) {
                    return false;
                }
                if (!query) {
                    return true;
                }
                return `${person.name} ${person.detail || ''}`.toLowerCase().includes(query);
            })
            .slice(0, 8);
    }

    get policyText() {
        return policyNote(this.draftKindId, this.draft);
    }

    get hasPolicy() {
        return Boolean(this.policyText);
    }

    get formFields() {
        if (!this.draftKindId) {
            return [];
        }
        return fieldsFor(this.draftKindId, this.draft).map((field) => {
            const error = this.fieldErrors[field.key] || '';
            return {
                ...field,
                value: this.draft[field.key] ?? '',
                error,
                hasError: Boolean(error),
                hasHint: Boolean(field.hint),
                isText: field.kind === 'text',
                isMoney: field.kind === 'money',
                isNumber: field.kind === 'number',
                isDate: field.kind === 'date',
                isSelect: field.kind === 'select',
                displayValue:
                    (field.options || []).find((option) => option.value && option.value === (this.draft[field.key] ?? ''))
                        ?.label || 'Select an option',
                placeholderSelect: !(field.options || []).some(
                    (option) => option.value && option.value === (this.draft[field.key] ?? '')
                ),
                valueClass: !(field.options || []).some(
                    (option) => option.value && option.value === (this.draft[field.key] ?? '')
                )
                    ? 'is-placeholder'
                    : '',
                isTextarea: field.kind === 'textarea',
                isPlace: field.kind === 'place',
                restaurants: field.restaurants ? 'true' : 'false',
                showResults: field.kind === 'place' && this.activePlaceKey === field.key && this.placeResults.length > 0,
                showMap: field.kind === 'place' && this.placeMapOpen && this.activePlaceKey === field.key,
                results:
                    this.activePlaceKey === field.key
                        ? this.placeResults.map((hit, index) => ({
                              ...hit,
                              index,
                              key: `${hit.lat}-${hit.lng}-${index}`
                          }))
                        : [],
                wrapClass: `${field.full ? 'modal-field modal-field-full' : 'modal-field'}${
                    this.openSelectKey === field.key || (this.activePlaceKey === field.key && this.placeResults.length)
                        ? ' is-raised'
                        : ''
                }`,
                controlClass: error ? 'modal-control is-invalid' : 'modal-control',
                options: (field.options || []).map((option) => ({
                    ...option,
                    selected: option.value === (this.draft[field.key] ?? '')
                }))
            };
        });
    }

    get showEmployees() {
        return showsEmployees(this.draftKindId, this.draft);
    }

    get employeeChips() {
        return (this.draft.employees || []).map((name) => ({ name }));
    }

    get employeeError() {
        return this.fieldErrors.employees || '';
    }

    get hasEmployeeError() {
        return Boolean(this.employeeError);
    }

    get showDestinations() {
        return showsDestinations(this.draftKindId, this.draft);
    }

    get destinationRows() {
        return (this.draft.destinations || []).map((row) => ({
            ...row,
            routeLabel: `${row.from} → ${row.to}`,
            kmLabel: `${row.km} km`
        }));
    }

    get hasDestinationError() {
        return Boolean(this.fieldErrors.destinations || this.destinationError);
    }

    get destinationErrorText() {
        return this.fieldErrors.destinations || this.destinationError;
    }

    get showInvoice() {
        return invoiceMode(this.draftKindId, this.draft) !== 'hidden';
    }

    get invoiceRequired() {
        const mode = invoiceMode(this.draftKindId, this.draft);
        return mode === 'required' || (mode === 'choice' && this.draft.uploadInvoice === 'YES');
    }

    get invoiceHint() {
        if (invoiceMode(this.draftKindId, this.draft) === 'optional') {
            return 'Optional for this allowance. PDF or image, up to 3 files.';
        }
        return 'PDF or image, up to 3 files, 4 MB each.';
    }

    get invoiceError() {
        return this.fieldErrors.invoiceFiles || '';
    }

    get hasInvoiceError() {
        return Boolean(this.invoiceError);
    }

    get hasInvoices() {
        return this.invoiceFiles.length > 0;
    }

    get savedInvoiceNote() {
        const saved = this.draft.invoiceFiles;
        if (!saved || this.invoiceFiles.length) {
            return '';
        }
        return `Already attached: ${saved}`;
    }

    get hasSavedInvoiceNote() {
        return Boolean(this.savedInvoiceNote);
    }

    get viewAllLabel() {
        return this.showingAllExpenses ? 'Show recent' : 'View all';
    }

    get hasExpenses() {
        return this.myExpenses.length > 0;
    }

    get hasTeamExpenses() {
        return this.teamExpenses.length > 0;
    }

    get showEmpty() {
        return !this.isLoadingList && !this.hasExpenses && !this.expensesError;
    }

    get showTeamEmpty() {
        return !this.isLoadingTeam && !this.hasTeamExpenses && !this.teamError;
    }

    get showListLoading() {
        return this.isLoadingList && !this.hasExpenses;
    }

    get showTeamLoading() {
        return this.isLoadingTeam && !this.hasTeamExpenses;
    }

    get showViewAll() {
        return this.hasExpenses || this.showingAllExpenses;
    }

    get hasSelectedDetail() {
        return this.selectedDetail != null;
    }

    get activeRows() {
        return this.isTeamTab ? this.teamExpenses : this.myExpenses;
    }

    get expenseCount() {
        return this.activeRows.length;
    }

    get pendingCount() {
        return this.activeRows.filter((row) => this.isAwaiting(row.status)).length;
    }

    get teamAwaitingCount() {
        return this.teamExpenses.filter((row) => row.canAct).length;
    }

    get pendingStatClass() {
        return this.pendingCount > 0 ? 'stat stat-awaiting' : 'stat';
    }

    get totalAmountLabel() {
        const total = this.activeRows.reduce((sum, row) => sum + (Number(row.amount) || 0), 0);
        return this.formatAmount(total);
    }

    get submitLabel() {
        if (this.isSaving) {
            return this.isEditing ? 'Saving…' : 'Sending…';
        }
        return this.isEditing ? 'Save changes' : 'Submit';
    }

    get ledgerTitle() {
        return this.showingAllExpenses ? 'All my expenses' : 'My expenses';
    }

    get ledgerHint() {
        if (!this.hasExpenses) {
            return 'Requests you create appear here.';
        }
        return this.showingAllExpenses
            ? `${this.expenseCount} requests. Open one to see its status.`
            : `Latest ${this.expenseCount}. Edit or delete until it is approved.`;
    }

    get displayExpenses() {
        const selected = this.normalizeId(this.selectedDetailId);
        const editing = this.normalizeId(this.editingId);
        return this.myExpenses.map((row) => ({
            ...row,
            cardClass: this.cardClass(row, selected, editing)
        }));
    }

    get displayTeamExpenses() {
        return this.teamExpenses.map((row) => ({
            ...row,
            rejectionDraft: this.rejectionReasonByExpenseId[row.expenseId] || '',
            cardClass: `expense-card ${row.toneClass}`
        }));
    }

    cardClass(row, selected, editing) {
        const id = this.normalizeId(row.id);
        const marked = id === selected || id === editing ? ' is-selected' : '';
        return `expense-card ${row.toneClass}${marked}`;
    }

    handleShowMine() {
        this.activeTab = 'mine';
    }

    handleShowTeam() {
        this.activeTab = 'team';
        if (!this.teamExpenses.length && !this.isLoadingTeam) {
            this.loadTeamExpenses();
        }
    }

    async handleOpenCreate() {
        this.editingId = null;
        this.modalStep = 'pick';
        this.draftKindId = '';
        this.draft = {};
        this.fieldErrors = {};
        this.formError = '';
        this.invoiceFiles = [];
        this.employeeDraft = '';
        this.resetDestinationDraft();
        this.modalOpen = true;
        this.raiseModalLayer();
        await this.ensureHistory();
        this.loadAttendees();
    }

    handlePickKind(event) {
        const kindId = event.currentTarget.dataset.kind;
        if (!KINDS[kindId]) {
            return;
        }
        this.draftKindId = kindId;
        this.draft = initialValues(kindId);
        this.fieldErrors = {};
        this.formError = '';
        this.invoiceFiles = [];
        this.employeeDraft = '';
        this.resetDestinationDraft();
        this.placeResults = [];
        this.placeMapOpen = false;
        this.activePlaceKey = '';
        this.openSelectKey = '';
        this.clearTripQuote();
        this.routeStops = [];
        this.routeStatus = '';
        this.routeDate = '';
        this.modalStep = 'form';
        this.loadRoute();
        this.loadAttendees();
    }

    handleBackToTypes() {
        this.draftKindId = '';
        this.modalStep = 'pick';
        this.formError = '';
        this.fieldErrors = {};
        this.routeStops = [];
        this.routeStatus = '';
    }

    handleCloseModal() {
        if (this.isSaving) {
            return;
        }
        this.modalOpen = false;
        this.editingId = null;
        this.formError = '';
        this.fieldErrors = {};
        this.placeMapOpen = false;
        this.destroyMaps();
        this.lowerModalLayer();
    }

    stopModalClick(event) {
        event.stopPropagation();
    }

    raiseModalLayer() {
        this.lowerModalLayer();
        const host = this.template.host;
        const raised = [];
        let node = host;
        while (node && node !== document.body && node !== document.documentElement) {
            const parent = node.parentElement;
            const style = window.getComputedStyle(node);
            raised.push({ node, zIndex: node.style.zIndex, position: node.style.position });
            if (style.position === 'static') {
                node.style.position = 'relative';
            }
            node.style.zIndex = '40000';
            if (!parent || this.parentOverlapsModal(parent, node)) {
                break;
            }
            node = parent;
        }
        this._raisedLayers = raised;
    }

    parentOverlapsModal(parent, node) {
        const selector = 'c-field-rep-home-today-plan, .leaflet-container, .today-plan-card';
        return [...parent.querySelectorAll(selector)].some((element) => !node.contains(element));
    }

    lowerModalLayer() {
        (this._raisedLayers || []).forEach((entry) => {
            entry.node.style.zIndex = entry.zIndex;
            entry.node.style.position = entry.position;
        });
        this._raisedLayers = [];
    }

    schedulePlaceSearch(query, restaurants) {
        window.clearTimeout(this._placeTimer);
        this._placeTimer = window.setTimeout(() => {
            this.searchPlaces(query, restaurants);
        }, 350);
    }

    async searchPlaces(query, restaurants) {
        const text = String(query || '').trim();
        if (text.length < 2) {
            this.placeResults = [];
            return;
        }
        const token = this.placeSearchToken + 1;
        this.placeSearchToken = token;
        const params = new URLSearchParams({
            format: 'jsonv2',
            countrycodes: 'eg',
            limit: '8',
            addressdetails: '1',
            q: restaurants ? `${text} restaurant` : text
        });
        try {
            const response = await fetch(`https://nominatim.openstreetmap.org/search?${params.toString()}`, {
                headers: { Accept: 'application/json' }
            });
            if (!response.ok || token !== this.placeSearchToken) {
                return;
            }
            const rows = await response.json();
            if (token !== this.placeSearchToken) {
                return;
            }
            this.placeResults = (Array.isArray(rows) ? rows : []).map((row) => ({
                label: String(row.display_name || '').split(',').slice(0, 2).join(',').trim(),
                detail: row.display_name || '',
                lat: Number(row.lat),
                lng: Number(row.lon)
            }));
        } catch (_error) {
            if (token === this.placeSearchToken) {
                this.placeResults = [];
            }
        }
    }

    async loadAttendees() {
        if (this.attendees.length) {
            return;
        }
        try {
            const context = await getExpenseFormContext({ expenseDate: null });
            this.attendees = context?.attendees || [];
            this.attendeeStatus = this.attendees.length ? '' : 'No territory users were found. Type a name to add them.';
        } catch (_error) {
            this.attendeeStatus = '';
        }
    }

    async loadRoute() {
        if (!showsRoute(this.draftKindId, this.draft)) {
            this.routeStops = [];
            this.routeStatus = '';
            return;
        }
        const day = primaryDate(this.draftKindId, this.draft);
        if (!day) {
            this.routeStatus = 'Choose the date to load that day’s visits.';
            return;
        }
        if (day === this.routeDate && this.routeStops.length) {
            return;
        }
        this.routeDate = day;
        this.routeStatus = 'Loading visits and time off…';
        this._drawnRoute = '';
        try {
            const context = await getExpenseFormContext({ expenseDate: day });
            this.routeStops = context?.stops || [];
            if (context?.attendees?.length && !this.attendees.length) {
                this.attendees = context.attendees;
            }
            this.syncRouteOntoDraft();
            this.routeStatus = this.routeStops.length ? '' : 'No visits or time off on this date.';
        } catch (_error) {
            this.routeStops = [];
            this.routeStatus = 'The day route could not be loaded.';
        }
    }

    syncRouteOntoDraft() {
        const summary = this.routeStops
            .slice(0, 4)
            .map((stop) => stop.title)
            .filter(Boolean)
            .join(' → ')
            .slice(0, 90);
        this.draft = { ...this.draft, dayRoute: summary };
        return this.draft;
    }

    async drawRouteMap() {
        const points = this.routeStops.filter((stop) => stop.latitude && stop.longitude);
        const container = this.template.querySelector('.route-map');
        if (!container || !points.length) {
            return;
        }
        const leaflet = await ensureLeaflet(this, LEAFLET);
        if (this.routeMap) {
            this.routeMap.remove();
            this.routeMap = null;
        }
        const map = leaflet.map(container).setView([Number(points[0].latitude), Number(points[0].longitude)], 12);
        addOsmTileLayer(map, leaflet);
        const latlngs = points.map((stop) => [Number(stop.latitude), Number(stop.longitude)]);
        latlngs.forEach((latlng, index) => {
            leaflet
                .circleMarker(latlng, {
                    radius: 7,
                    color: '#0176d3',
                    fillColor: '#0176d3',
                    fillOpacity: 1,
                    weight: 2
                })
                .addTo(map)
                .bindTooltip(`${index + 1}. ${points[index].title}`);
        });
        if (latlngs.length > 1) {
            leaflet.polyline(latlngs, { color: '#0176d3', weight: 3 }).addTo(map);
            map.fitBounds(latlngs, { padding: [16, 16] });
        }
        this.routeMap = map;
        window.setTimeout(() => map.invalidateSize(), 50);
    }

    async drawPlaceMap() {
        const key = this.activePlaceKey;
        const container = this.template.querySelector(`.place-map[data-map="${key}"]`);
        if (!container || !key) {
            return;
        }
        const leaflet = await ensureLeaflet(this, LEAFLET);
        if (this.placeMap) {
            this.placeMap.remove();
            this.placeMap = null;
        }
        const lat = Number(this.draft[`${key}Lat`]) || 30.0444;
        const lng = Number(this.draft[`${key}Lng`]) || 31.2357;
        const map = leaflet.map(container).setView([lat, lng], this.draft[`${key}Lat`] ? 14 : 6);
        addOsmTileLayer(map, leaflet);
        let marker = null;
        const drop = async (latlng) => {
            if (marker) {
                marker.setLatLng(latlng);
            } else {
                marker = leaflet.marker(latlng).addTo(map);
            }
            let label = this.draft[key] || 'Pinned location';
            try {
                const response = await fetch(
                    `https://nominatim.openstreetmap.org/reverse?format=jsonv2&lat=${latlng.lat}&lon=${latlng.lng}`
                );
                const row = await response.json();
                if (row?.display_name) {
                    label = String(row.display_name).split(',').slice(0, 2).join(',').trim();
                }
            } catch (_error) {
                label = `${latlng.lat.toFixed(5)}, ${latlng.lng.toFixed(5)}`;
            }
        this.draft = {
            ...this.draft,
            [key]: label,
            [`${key}Lat`]: Number(latlng.lat).toFixed(5),
            [`${key}Lng`]: Number(latlng.lng).toFixed(5)
        };
        this.loadTripQuote();
        };
        if (this.draft[`${key}Lat`]) {
            marker = leaflet.marker([lat, lng]).addTo(map);
        }
        map.on('click', (event) => drop(event.latlng));
        this.placeMap = map;
        window.setTimeout(() => map.invalidateSize(), 50);
    }

    async drawTripMap() {
        const container = this.template.querySelector('.trip-map');
        const line = this.tripGeometry.map((pair) => [Number(pair[1]), Number(pair[0])]).filter((pair) => pair[0] && pair[1]);
        if (!container || line.length < 2) {
            return;
        }
        const leaflet = await ensureLeaflet(this, LEAFLET);
        if (this.tripMap) {
            this.tripMap.remove();
            this.tripMap = null;
        }
        const map = leaflet.map(container, { zoomControl: true }).setView(line[0], 8);
        addOsmTileLayer(map, leaflet);
        leaflet.polyline(line, { color: '#0176d3', weight: 4 }).addTo(map);
        leaflet.circleMarker(line[0], { radius: 6, color: '#fff', weight: 2, fillColor: '#0176d3', fillOpacity: 1 }).addTo(map);
        leaflet
            .circleMarker(line[line.length - 1], { radius: 6, color: '#fff', weight: 2, fillColor: '#032d60', fillOpacity: 1 })
            .addTo(map);
        this.tripTolls.forEach((toll) => {
            if (!toll.latitude || !toll.longitude) {
                return;
            }
            leaflet
                .circleMarker([Number(toll.latitude), Number(toll.longitude)], {
                    radius: 7,
                    color: '#8a5a00',
                    weight: 2,
                    fillColor: '#f9e3b1',
                    fillOpacity: 1
                })
                .addTo(map)
                .bindTooltip(toll.name);
        });
        map.fitBounds(line, { padding: [18, 18] });
        this.tripMap = map;
        window.setTimeout(() => map.invalidateSize(), 50);
    }

    destroyMaps() {
        if (this.routeMap) {
            this.routeMap.remove();
            this.routeMap = null;
        }
        if (this.placeMap) {
            this.placeMap.remove();
            this.placeMap = null;
        }
        if (this.tripMap) {
            this.tripMap.remove();
            this.tripMap = null;
        }
        this._drawnRoute = '';
        this._drawnPlace = '';
        this._drawnTrip = '';
    }

    handleFieldInput(event) {
        const key = event.target.dataset.key;
        let next = { ...this.draft, [key]: event.target.value };
        if (key === 'accommodationType') {
            next = { ...next, mealType: '' };
        }
        this.draft = next;
        this.clearFieldError(key);
        if (key === 'invoiceDate' || key === 'date' || key === 'travelType' || key === 'cityType' || key === 'transportationType' || key === 'cateringType') {
            this.routeDate = '';
            this.loadRoute();
        }
    }

    handleToggleSelect(event) {
        event.stopPropagation();
        const key = event.currentTarget.dataset.key;
        this.placeResults = [];
        if (this.openSelectKey === key) {
            this.openSelectKey = '';
            return;
        }
        this.openSelectKey = key;
        this.selectMenuStyle = this.menuStyleFor(event.currentTarget);
    }

    handlePickOption(event) {
        event.stopPropagation();
        const key = event.currentTarget.dataset.key;
        const value = event.currentTarget.dataset.value;
        this.openSelectKey = '';
        this.handleFieldInput({ target: { dataset: { key }, value } });
    }

    handleDismissMenus() {
        this.openSelectKey = '';
        this.placeResults = [];
    }

    menuStyleFor(anchor) {
        if (!anchor) {
            return '';
        }
        const rect = anchor.getBoundingClientRect();
        return `top:${Math.round(rect.bottom + 4)}px;left:${Math.round(rect.left)}px;width:${Math.round(rect.width)}px`;
    }

    repositionFloatingMenus() {
        if (this.selectMenuOpen) {
            const button = this.template.querySelector(`button.modal-control[data-key="${this.openSelectKey}"]`);
            const next = this.menuStyleFor(button);
            if (next && next !== this.selectMenuStyle) {
                this.selectMenuStyle = next;
            }
        }
        if (this.placeMenuOpen) {
            const input = this.template.querySelector(`input[data-key="${this.activePlaceKey}"]`);
            const next = this.menuStyleFor(input);
            if (next && next !== this.placeMenuStyle) {
                this.placeMenuStyle = next;
            }
        }
    }

    handleUseFuelAmount() {
        if (!this.tripFuelCost) {
            return;
        }
        this.draft = { ...this.draft, value: this.tripFuelCost };
        this.clearFieldError('value');
    }

    handleStartTollExpense() {
        const previous = this.draft;
        const day = primaryDate(this.draftKindId, previous);
        const tollNames = this.tripTolls
            .map((toll) => toll.name)
            .filter(Boolean)
            .slice(0, 3)
            .join(', ');
        this.draftKindId = 'bus-transit';
        this.draft = {
            ...initialValues('bus-transit'),
            transportationType: 'Travel',
            travelType: 'Road Toll Ticket',
            from: previous.from || '',
            to: previous.to || '',
            fromLat: previous.fromLat || '',
            fromLng: previous.fromLng || '',
            toLat: previous.toLat || '',
            toLng: previous.toLng || '',
            date: day || previous.date || previous.invoiceDate,
            description: tollNames ? `Tolls: ${tollNames}` : ''
        };
        this.openSelectKey = '';
        this.fieldErrors = {};
        this.formError = '';
        this.tripQuoteKey = '';
        this.loadTripQuote();
    }

    clearTripQuote() {
        this.tripDistanceKm = null;
        this.tripFuelLiters = '';
        this.tripFuelCost = '';
        this.tripStatus = '';
        this.tripTolls = [];
        this.tripGeometry = [];
        this.tripQuoteKey = '';
        this._drawnTrip = '';
        if (this.tripMap) {
            this.tripMap.remove();
            this.tripMap = null;
        }
    }

    async loadTripQuote() {
        const fromLat = Number(this.draft.fromLat);
        const fromLng = Number(this.draft.fromLng);
        const toLat = Number(this.draft.toLat);
        const toLng = Number(this.draft.toLng);
        if (![fromLat, fromLng, toLat, toLng].every((value) => Number.isFinite(value) && value !== 0)) {
            this.clearTripQuote();
            return;
        }
        const key = [fromLat, fromLng, toLat, toLng].join(',');
        if (key === this.tripQuoteKey && this.tripDistanceKm != null) {
            return;
        }
        this.tripQuoteKey = key;
        this.tripStatus = 'Calculating the driving route…';
        try {
            const route = await fetchOsrmRoute(`${fromLng},${fromLat};${toLng},${toLat}`);
            if (this.tripQuoteKey !== key) {
                return;
            }
            const geometry = route.geometry?.coordinates || [];
            this.applyTripNumbers(route.distance / 1000, 'Driving distance between the two places.');
            this.tripGeometry = geometry;
            this.tripTolls = await this.findTolls(geometry);
            this._drawnTrip = '';
            if (this.tripQuoteKey === key) {
                this.rememberTripOnDraft();
            }
        } catch (_error) {
            if (this.tripQuoteKey !== key) {
                return;
            }
            const km = haversineKm(fromLat, fromLng, toLat, toLng);
            this.applyTripNumbers(km, 'Straight-line distance. The road route could not be loaded.');
            this.tripGeometry = [
                [fromLng, fromLat],
                [toLng, toLat]
            ];
            this.tripTolls = [];
            this._drawnTrip = '';
            this.rememberTripOnDraft();
        }
    }

    applyTripNumbers(km, status) {
        const liters = (km * FUEL_LITERS_PER_100KM) / 100;
        const cost = Math.round(liters * FUEL_EGP_PER_LITER);
        this.tripDistanceKm = km;
        this.tripFuelLiters = liters.toFixed(1);
        this.tripFuelCost = String(cost);
        this.tripStatus = status;
    }

    rememberTripOnDraft() {
        const tollNames = this.tripTolls
            .map((toll) => toll.name)
            .filter(Boolean)
            .slice(0, 3)
            .join(', ');
        const next = {
            ...this.draft,
            tripDistanceKm: Number(this.tripDistanceKm).toFixed(1),
            tripFuelCost: this.tripFuelCost,
            tripTollNames: tollNames
        };
        if (fieldsFor(this.draftKindId, next).some((field) => field.key === 'distanceKm')) {
            next.distanceKm = String(Math.max(1, Math.round(this.tripDistanceKm)));
        }
        this.draft = next;
    }

    async findTolls(geometry) {
        if (!geometry.length) {
            return [];
        }
        const local = EGYPT_TOLL_BOOTHS.filter(
            (toll) => this.nearestKm(toll.latitude, toll.longitude, geometry) <= 2.5
        ).map((toll, index) => ({ ...toll, id: `local-${index}` }));
        let live = [];
        try {
            live = await this.queryTollBooths(geometry);
        } catch (_error) {
            live = [];
        }
        return this.clusterTolls([...local, ...live]);
    }

    async queryTollBooths(geometry) {
        const lats = geometry.map((pair) => Number(pair[1]));
        const lngs = geometry.map((pair) => Number(pair[0]));
        const south = Math.min(...lats) - 0.05;
        const north = Math.max(...lats) + 0.05;
        const west = Math.min(...lngs) - 0.05;
        const east = Math.max(...lngs) + 0.05;
        const query =
            `[out:json][timeout:12];(` +
            `node["barrier"="toll_booth"](${south},${west},${north},${east});` +
            `node["highway"="toll_gantry"](${south},${west},${north},${east});` +
            `);out body 40;`;
        const response = await fetch('https://overpass-api.de/api/interpreter', {
            method: 'POST',
            headers: { 'Content-Type': 'text/plain;charset=UTF-8', Accept: 'application/json' },
            body: query
        });
        if (!response.ok) {
            return [];
        }
        const payload = await response.json();
        return (payload.elements || [])
            .map((element) => ({
                id: String(element.id),
                name: element.tags?.name || element.tags?.ref || 'Toll booth',
                latitude: element.lat,
                longitude: element.lon
            }))
            .filter((toll) => this.nearestKm(toll.latitude, toll.longitude, geometry) <= 2.5);
    }

    nearestKm(lat, lng, geometry) {
        let best = Number.POSITIVE_INFINITY;
        const step = Math.max(1, Math.ceil(geometry.length / 160));
        for (let index = 0; index < geometry.length; index += step) {
            const pair = geometry[index];
            best = Math.min(best, haversineKm(lat, lng, Number(pair[1]), Number(pair[0])));
        }
        return best;
    }

    clusterTolls(rows) {
        const clusters = [];
        rows.forEach((toll) => {
            const existing = clusters.find(
                (cluster) => haversineKm(cluster.latitude, cluster.longitude, toll.latitude, toll.longitude) < 3
            );
            if (!existing) {
                clusters.push({ ...toll });
                return;
            }
            if (existing.name === 'Toll booth' && toll.name !== 'Toll booth') {
                existing.name = toll.name;
            }
        });
        return clusters.slice(0, 4);
    }

    handlePlaceFocus(event) {
        this.activePlaceKey = event.target.dataset.key;
    }

    handlePlaceInput(event) {
        const key = event.target.dataset.key;
        const restaurants = event.target.dataset.restaurants === 'true';
        this.activePlaceKey = key;
        this.draft = { ...this.draft, [key]: event.target.value, [`${key}Lat`]: '', [`${key}Lng`]: '' };
        this.clearFieldError(key);
        if (key === 'from' || key === 'to') {
            this.clearTripQuote();
        }
        this.schedulePlaceSearch(event.target.value, restaurants);
    }

    handlePickPlace(event) {
        const key = event.currentTarget.dataset.key;
        const hit = this.placeResults[Number(event.currentTarget.dataset.index)];
        if (!hit) {
            return;
        }
        this.draft = {
            ...this.draft,
            [key]: hit.label,
            [`${key}Lat`]: Number(hit.lat).toFixed(5),
            [`${key}Lng`]: Number(hit.lng).toFixed(5)
        };
        this.placeResults = [];
        this.placeMapOpen = true;
        this._drawnPlace = '';
        this.clearFieldError(key);
        this.loadTripQuote();
    }

    handlePinPlace(event) {
        this.activePlaceKey = event.currentTarget.dataset.key;
        this.placeMapOpen = true;
        this._drawnPlace = '';
    }

    handlePickAttendee(event) {
        this.addEmployeeName(event.currentTarget.dataset.name);
    }

    handleEmployeeDraft(event) {
        this.employeeDraft = event.target.value;
    }

    handleAddEmployee() {
        this.addEmployeeName(this.employeeDraft);
    }

    addEmployeeName(value) {
        const name = String(value || '').trim();
        if (!name) {
            this.fieldErrors = { ...this.fieldErrors, employees: 'Choose someone from your territory.' };
            return;
        }
        const current = this.draft.employees || [];
        if (current.some((entry) => entry.toLowerCase() === name.toLowerCase())) {
            this.fieldErrors = { ...this.fieldErrors, employees: 'That employee is already on the request.' };
            return;
        }
        this.draft = { ...this.draft, employees: [...current, name] };
        this.employeeDraft = '';
        this.clearFieldError('employees');
    }

    handleRemoveEmployee(event) {
        const name = event.currentTarget.dataset.name;
        this.draft = {
            ...this.draft,
            employees: (this.draft.employees || []).filter((entry) => entry !== name)
        };
    }

    handleDestinationInput(event) {
        const key = event.target.dataset.key;
        this.destinationDraft = { ...this.destinationDraft, [key]: event.target.value };
        this.destinationError = '';
    }

    handleAddDestination() {
        const from = (this.destinationDraft.from || '').trim();
        const to = (this.destinationDraft.to || '').trim();
        const km = Number(this.destinationDraft.km);
        if (!from || !to) {
            this.destinationError = 'Enter both From and To.';
            return;
        }
        if (from.toLowerCase() === to.toLowerCase()) {
            this.destinationError = 'From and To must be different places.';
            return;
        }
        if (!Number.isFinite(km) || km <= 0) {
            this.destinationError = 'Enter the total kilometers for this leg.';
            return;
        }
        const row = { id: `${Date.now()}`, from, to, km: String(km) };
        this.draft = { ...this.draft, destinations: [...(this.draft.destinations || []), row] };
        this.resetDestinationDraft();
        this.clearFieldError('destinations');
    }

    handleRemoveDestination(event) {
        const id = event.currentTarget.dataset.id;
        this.draft = {
            ...this.draft,
            destinations: (this.draft.destinations || []).filter((row) => row.id !== id)
        };
    }

    handleInvoicePick(event) {
        const selected = Array.from(event.target.files || []);
        const next = [...this.invoiceFiles];
        let error = '';
        selected.forEach((file) => {
            const allowed = /\.(pdf|png|jpe?g)$/i.test(file.name);
            if (!allowed) {
                error = `${file.name} must be a PDF or image.`;
                return;
            }
            if (file.size > MAX_INVOICE_BYTES) {
                error = `${file.name} is larger than 4 MB.`;
                return;
            }
            next.push({
                id: `${Date.now()}-${file.name}-${next.length}`,
                name: file.name,
                sizeLabel: this.formatFileSize(file.size),
                file
            });
        });
        event.target.value = '';
        if (next.length > MAX_INVOICES) {
            this.fieldErrors = { ...this.fieldErrors, invoiceFiles: 'You can attach up to 3 invoices.' };
            return;
        }
        this.invoiceFiles = next;
        if (error) {
            this.fieldErrors = { ...this.fieldErrors, invoiceFiles: error };
            return;
        }
        this.clearFieldError('invoiceFiles');
    }

    handleRemoveInvoice(event) {
        const id = event.currentTarget.dataset.id;
        this.invoiceFiles = this.invoiceFiles.filter((file) => file.id !== id);
    }

    handleRejectionChange(event) {
        const expenseId = event.target.dataset.expenseId;
        this.rejectionReasonByExpenseId = {
            ...this.rejectionReasonByExpenseId,
            [expenseId]: event.detail.value
        };
    }

    async handleSubmit() {
        await this.ensureHistory();
        const savedNames = String(this.draft.invoiceFiles || '')
            .split(',')
            .map((name) => name.trim())
            .filter(Boolean);
        const invoiceNames = this.invoiceFiles.length ? this.invoiceFiles.map((file) => file.name) : savedNames;
        const result = validateExpense(this.draftKindId, this.syncRouteOntoDraft(), {
            expenses: this.historyExpenses.length ? this.historyExpenses : this.myExpenses,
            excludeId: this.editingId,
            invoiceCount: this.invoiceFiles.length || savedNames.length,
            invoiceNames
        });
        this.fieldErrors = result.fields;
        this.formError = result.message;
        if (result.message) {
            return;
        }

        const payload = buildPayload(this.draftKindId, this.draft, invoiceNames);
        if (!payload.description || !payload.expenseDate || !payload.typeValue) {
            this.formError = 'Amount, date, and expense type are required.';
            return;
        }
        if (this.typeOptions.length && !this.typeOptions.some((option) => option.value === payload.typeValue)) {
            this.formError = 'This expense type is not available on your account.';
            return;
        }

        this.isSaving = true;
        try {
            const invoicePayload = this.invoiceFiles.length ? await this.readInvoiceFiles() : undefined;
            const request = { ...payload, invoiceFiles: invoicePayload };
            let saved;
            if (this.editingId) {
                saved = await this.saveExpense(() => updateMyExpense({ expenseId: this.editingId, ...request }), request);
                this.showToast('Expense updated', 'Your changes were saved.', 'success');
            } else {
                saved = await this.saveExpense(() => submitExpense(request), request);
                this.showToast('Sent to manager', 'Your expense is pending manager approval.', 'success');
            }
            if (saved?.invoiceUploadFailed) {
                this.showToast('Invoice not attached', 'The request was saved, but the invoice file could not be uploaded.', 'warning');
            }
            this.modalOpen = false;
            this.editingId = null;
            this.historyLoaded = false;
            this.showingAllExpenses = false;
            await this.loadExpenses(10);
        } catch (error) {
            this.formError = this.reduceError(error);
        } finally {
            this.isSaving = false;
        }
    }

    async saveExpense(run, request) {
        try {
            return await run();
        } catch (error) {
            const message = this.reduceError(error);
            if (request.invoiceFiles && /unknown|no such column|parameter/i.test(message)) {
                const { invoiceFiles, ...rest } = request;
                if (this.editingId) {
                    return updateMyExpense({ expenseId: this.editingId, ...rest });
                }
                return submitExpense(rest);
            }
            throw error;
        }
    }

    handleEdit(event) {
        const recordId = this.normalizeId(event.currentTarget.dataset.id);
        const row = this.myExpenses.find((item) => this.normalizeId(item.id) === recordId);
        if (!row || !row.canModify) {
            return;
        }
        const restored = valuesFromExpense(row);
        this.activeTab = 'mine';
        this.editingId = recordId;
        this.draftKindId = restored.kindId;
        this.draft = restored.values;
        this.fieldErrors = {};
        this.formError = '';
        this.invoiceFiles = [];
        this.employeeDraft = '';
        this.resetDestinationDraft();
        this.modalStep = 'form';
        this.modalOpen = true;
        this.raiseModalLayer();
        this.ensureHistory();
        this.loadRoute();
        this.loadAttendees();
    }

    async handleDelete(event) {
        const recordId = this.normalizeId(event.currentTarget.dataset.id);
        const row = this.myExpenses.find((item) => this.normalizeId(item.id) === recordId);
        if (!row || !row.canModify) {
            return;
        }
        const confirmed = await LightningConfirm.open({
            label: 'Delete expense',
            message: `Delete this ${row.typeLabel || 'expense'} request for ${row.amountLabel} EGP?`,
            variant: 'header'
        });
        if (!confirmed) {
            return;
        }
        try {
            await deleteMyExpense({ expenseId: recordId });
            if (this.normalizeId(this.editingId) === recordId) {
                this.modalOpen = false;
                this.editingId = null;
            }
            if (this.normalizeId(this.selectedDetailId) === recordId) {
                this.handleCloseDetail();
            }
            await this.loadExpenses(this.showingAllExpenses ? 200 : 10);
            this.showToast('Deleted', 'The expense request was deleted.', 'success');
        } catch (error) {
            this.showToast('Delete failed', this.reduceError(error), 'error');
        }
    }

    async handleViewDetails(event) {
        const recordId = this.normalizeId(event.currentTarget.dataset.id);
        await this.showExpenseDetails(recordId);
    }

    async showExpenseDetails(recordId) {
        if (!recordId) {
            return;
        }
        this.selectedDetailId = recordId;
        try {
            const detail = await getExpenseDetail({ expenseId: recordId });
            this.selectedDetail = this.mapExpenseRow(detail);
            setTimeout(() => {
                this.template.querySelector('.expense-detail-panel')?.scrollIntoView({
                    behavior: 'smooth',
                    block: 'nearest'
                });
            }, 0);
        } catch (error) {
            this.selectedDetail = null;
            this.showToast('Unable to load details', this.reduceError(error), 'error');
        }
    }

    handleCloseDetail() {
        this.selectedDetail = null;
        this.selectedDetailId = null;
    }

    handleOpenDetailRecord() {
        if (this.selectedDetail?.id) {
            this.navigateToExpense(this.selectedDetail.id);
        }
    }

    navigateToExpense(recordId) {
        if (!recordId) {
            return;
        }
        this[NavigationMixin.Navigate]({
            type: 'standard__recordPage',
            attributes: {
                recordId,
                objectApiName: 'Employee_Expense__c',
                actionName: 'view'
            }
        });
    }

    async handleViewAllExpenses() {
        if (this.showingAllExpenses) {
            this.showingAllExpenses = false;
            await this.loadExpenses(10);
        } else {
            this.showingAllExpenses = true;
            await this.loadExpenses(200);
        }
    }

    async handleApprove(event) {
        const expenseId = event.currentTarget.dataset.expenseId;
        try {
            await approveExpense({ expenseId });
            this.showToast('Approved', 'Expense request approved.', 'success');
            await this.loadTeamExpenses();
        } catch (error) {
            this.showToast('Approve failed', this.reduceError(error), 'error');
        }
    }

    async handleReject(event) {
        const expenseId = event.currentTarget.dataset.expenseId;
        const rejectionReason = (this.rejectionReasonByExpenseId[expenseId] || '').trim();
        if (!rejectionReason) {
            this.showToast('Rejection reason required', 'Enter a reason before rejecting.', 'error');
            return;
        }
        try {
            await rejectExpense({ expenseId, rejectionReason });
            this.rejectionReasonByExpenseId = {
                ...this.rejectionReasonByExpenseId,
                [expenseId]: ''
            };
            this.showToast('Rejected', 'Expense request rejected.', 'success');
            await this.loadTeamExpenses();
        } catch (error) {
            this.showToast('Reject failed', this.reduceError(error), 'error');
        }
    }

    async loadExpenses(limitSize) {
        this.isLoadingList = true;
        try {
            const data = await getMyExpenses({ limitSize });
            this.myExpenses = (data || []).map((expense) => this.mapExpenseRow(expense));
            this.expensesError = undefined;
            if (this.selectedDetailId) {
                const stillVisible = this.myExpenses.some(
                    (row) => this.normalizeId(row.id) === this.normalizeId(this.selectedDetailId)
                );
                if (stillVisible) {
                    await this.showExpenseDetails(this.selectedDetailId);
                } else {
                    this.handleCloseDetail();
                }
            }
        } catch (error) {
            this.myExpenses = [];
            this.expensesError = this.reduceError(error);
        } finally {
            this.isLoadingList = false;
        }
    }

    async loadTeamExpenses() {
        this.isLoadingTeam = true;
        try {
            const data = await getTeamExpenses();
            this.teamExpenses = (data || []).map((expense) => this.mapTeamRow(expense));
            this.teamError = undefined;
        } catch (error) {
            this.teamExpenses = [];
            this.teamError = this.reduceError(error);
        } finally {
            this.isLoadingTeam = false;
        }
    }

    normalizeId(value) {
        return value == null ? null : String(value);
    }

    isAwaiting(status) {
        return status === 'Pending' || status === 'Submitted';
    }

    async ensureHistory() {
        if (this.historyLoaded) {
            return;
        }
        try {
            const data = await getMyExpenses({ limitSize: 200 });
            this.historyExpenses = (data || []).map((expense) => this.mapExpenseRow(expense));
            this.historyLoaded = true;
        } catch (_error) {
            this.historyExpenses = this.myExpenses;
        }
    }

    clearFieldError(key) {
        if (!this.fieldErrors[key] && !this.formError) {
            return;
        }
        const next = { ...this.fieldErrors };
        delete next[key];
        this.fieldErrors = next;
        this.formError = '';
    }

    resetDestinationDraft() {
        this.destinationDraft = { from: '', to: '', km: '' };
        this.destinationError = '';
    }

    readInvoiceFiles() {
        return Promise.all(this.invoiceFiles.map((item) => this.readInvoiceFile(item)));
    }

    readInvoiceFile(item) {
        return new Promise((resolve, reject) => {
            const reader = new FileReader();
            reader.onload = () => {
                const result = String(reader.result || '');
                const base64 = result.includes(',') ? result.split(',')[1] : result;
                resolve({ name: item.name, base64 });
            };
            reader.onerror = () => reject(reader.error);
            reader.readAsDataURL(item.file);
        });
    }

    formatFileSize(size) {
        if (size < 1024) {
            return `${size} B`;
        }
        if (size < 1024 * 1024) {
            return `${Math.round(size / 1024)} KB`;
        }
        return `${(size / (1024 * 1024)).toFixed(1)} MB`;
    }

    toInputDate(value) {
        if (!value) {
            return '';
        }
        const text = String(value);
        if (/^\d{4}-\d{2}-\d{2}/.test(text)) {
            return text.slice(0, 10);
        }
        const parsed = new Date(text);
        if (Number.isNaN(parsed.getTime())) {
            return '';
        }
        return parsed.toISOString().slice(0, 10);
    }

    mapExpenseRow(expense) {
        const statusKey = expense.status || 'Pending';
        const typeKey = this.resolveTypeKey(expense.typeLabel);
        const display = displayFromDescription(expense.description, expense.typeLabel);
        const parsed = parsePacked(expense.description);
        const kind = parsed.kindId ? KINDS[parsed.kindId] : null;
        return {
            ...expense,
            id: this.normalizeId(expense.id),
            typeValue: expense.typeValue || typeKey,
            expenseDateLabel: this.formatDisplayDate(expense.expenseDate),
            amountLabel: this.formatAmount(expense.amount),
            typeLabel: display.typeLabel,
            descriptionLabel: display.descriptionLabel,
            hasDescription: display.hasDescription,
            detailLines: display.detailLines,
            hasDetailLines: display.detailLines.length > 0,
            managerName: expense.managerName || '—',
            statusHelp: STATUS_HELP[statusKey] || 'Expense request status.',
            statusBadgeClass: STATUS_BADGE_CLASS[statusKey] || STATUS_BADGE_CLASS.Pending,
            toneClass: this.toneClass(statusKey),
            typeIcon: kind?.icon || TYPE_ICONS[typeKey] || TYPE_ICONS.Others,
            canModify: statusKey !== LOCKED_STATUS,
            showRejectionReason: statusKey === 'Rejected' && Boolean(expense.rejectionReason)
        };
    }

    mapTeamRow(expense) {
        const statusKey = expense.status || 'Pending';
        const typeKey = this.resolveTypeKey(expense.typeLabel);
        const display = displayFromDescription(expense.description, expense.typeLabel);
        const parsed = parsePacked(expense.description);
        const kind = parsed.kindId ? KINDS[parsed.kindId] : null;
        return {
            ...expense,
            expenseId: this.normalizeId(expense.expenseId),
            amount: expense.amount,
            repName: expense.repName || 'Team member',
            expenseDateLabel: this.formatDisplayDate(expense.expenseDate),
            amountLabel: this.formatAmount(expense.amount),
            typeLabel: display.typeLabel,
            descriptionLabel: display.descriptionLabel,
            hasDescription: display.hasDescription,
            statusBadgeClass: STATUS_BADGE_CLASS[statusKey] || STATUS_BADGE_CLASS.Pending,
            toneClass: this.toneClass(statusKey),
            typeIcon: kind?.icon || TYPE_ICONS[typeKey] || TYPE_ICONS.Others,
            canAct: expense.canAct === true && this.isAwaiting(statusKey),
            showRejectionReason: statusKey === 'Rejected' && Boolean(expense.rejectionReason)
        };
    }

    toneClass(statusKey) {
        if (statusKey === 'Approved') {
            return 'tone-approved';
        }
        if (statusKey === 'Rejected') {
            return 'tone-rejected';
        }
        return 'tone-pending';
    }

    resolveTypeKey(typeLabel) {
        if (typeLabel === 'Conference / Event') {
            return 'Conference_Event';
        }
        return typeLabel;
    }

    formatDisplayDate(value) {
        if (!value) {
            return '—';
        }
        const text = String(value);
        const parsed = /^\d{4}-\d{2}-\d{2}$/.test(text) ? new Date(`${text}T00:00:00`) : new Date(text);
        if (Number.isNaN(parsed.getTime())) {
            return text;
        }
        return parsed.toLocaleDateString('en-GB', {
            day: '2-digit',
            month: 'short',
            year: 'numeric'
        });
    }

    formatAmount(value) {
        if (value === null || value === undefined || value === '') {
            return '—';
        }
        return Number(value).toLocaleString('en-EG', {
            minimumFractionDigits: 0,
            maximumFractionDigits: 2
        });
    }

    showToast(title, message, variant) {
        this.dispatchEvent(new ShowToastEvent({ title, message, variant }));
    }

    reduceError(error) {
        if (Array.isArray(error?.body)) {
            return error.body.map((item) => item.message).join(', ');
        }
        if (error?.body?.output?.errors?.length) {
            return error.body.output.errors.map((item) => item.message).join(', ');
        }
        if (error?.body?.output?.fieldErrors) {
            return Object.values(error.body.output.fieldErrors)
                .flat()
                .map((item) => item.message)
                .join(', ');
        }
        return error?.body?.message || error?.message || 'An unexpected error occurred.';
    }
}