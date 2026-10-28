import { LightningElement, track, wire } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import LightningConfirm from 'lightning/confirm';
import { MessageContext } from 'lightning/messageService';
import FORM_FACTOR from '@salesforce/client/formFactor';
import USER_ID from '@salesforce/user/Id';
import LEAFLET from '@salesforce/resourceUrl/leaflet';
import getAccountsTabPage from '@salesforce/apex/AccountsTabController.getAccountsTabPage';
import getBookMode from '@salesforce/apex/FieldBookAccess.getBookMode';
import getAccountsTabMapPoints from '@salesforce/apex/AccountsTabController.getAccountsTabMapPoints';
import getAccountsTabRecordTypeOptions from '@salesforce/apex/AccountsTabController.getAccountsTabRecordTypeOptions';
import getCreateableAccountRecordTypes from '@salesforce/apex/AccountsTabController.getCreateableAccountRecordTypes';
import searchMasterListWithFilters from '@salesforce/apex/AccountsTabController.searchMasterListWithFilters';
import searchMapPlaces from '@salesforce/apex/AccountsTabController.searchMapPlaces';
import searchVezeetaDoctors from '@salesforce/apex/VezeetaDoctorService.searchVezeetaDoctors';
import getVezeetaDoctor from '@salesforce/apex/VezeetaDoctorService.getVezeetaDoctor';
import saveVezeetaProfileUrl from '@salesforce/apex/VezeetaDoctorService.saveVezeetaProfileUrl';
import createAccountFromWizard from '@salesforce/apex/AccountsTabController.createAccountFromWizard';
import getWizardCreateOptions from '@salesforce/apex/AccountsTabController.getWizardCreateOptions';
import setAccountKol from '@salesforce/apex/AccountsTabController.setAccountKol';
import exportAccountsCsvChunk from '@salesforce/apex/AccountsTabController.exportAccountsCsvChunk';
import approveAccountSubmissionApex from '@salesforce/apex/AccountsTabController.approveAccountSubmission';
import getAccountNurtureSummary from '@salesforce/apex/AccountsTabController.getAccountNurtureSummary';
import isAccountApprovalManager from '@salesforce/apex/AccountsTabController.isAccountApprovalManager';
import rejectAccountSubmissionApex from '@salesforce/apex/AccountsTabController.rejectAccountSubmission';
import getPlannerAccountFilterOptions from '@salesforce/apex/FieldPlannerController.getPlannerAccountFilterOptions';
import { getCurrentPosition } from 'c/plannerMapUtils';
import {
    addOsmTileLayer,
    ensureLeaflet
} from 'c/plannerMapPins';
import { accountTypeIconUrl, resolveAccountThemeKind } from 'c/accountTypeTheme';
import {
    loadAccountCollections,
    getCollectionAccountIds
} from 'c/plannerAccountCollections';
import {
    subscribeTerritoryContext,
    unsubscribeTerritoryContext
} from 'c/territoryContextClient';

// Matches AccountsTabController.DUPLICATE_WARNING_PREFIX.
const DUPLICATE_WARNING_PREFIX = 'Possible duplicate: ';

const FILTER_ALL = 'All';
const SCOPE_BOTH = 'both';
const SCOPE_IN = 'in';
const SCOPE_OUT = 'out';
const LIST_MODE_ALL = 'all';
const LIST_MODE_COLLECTION = 'collection';
const LIST_MODE_NURTURING = 'nurturing';
const APPROVAL_SCOPE_NURTURING = 'nurturing';
const NURTURE_LANE_ALL = 'all';
const SORT_AGENTFORCE = 'agentforceScore';
const SORT_CLASSIFICATION = 'classification';
const SORT_NAME = 'name';
const SORT_HEALTH = 'health';
const SORT_GAP = 'gap';
const SORT_VISITS = 'visits';
const SORT_LAST_VISIT = 'lastVisit';
const PAGE_SIZE = 10;
const NURTURE_ACTION_PAGE_SIZE = 50;
const MAP_PAGE_SIZE = 50;
const ACCOUNTS_MAP_CHROME_CSS = `
.acct-map-pin{background:transparent!important;border:none!important;}
.leaflet-popup-content-wrapper{border-radius:14px;box-shadow:0 12px 32px rgba(3,45,96,.18);padding:0;}
.leaflet-popup-content{margin:0.75rem 0.85rem;min-width:11.5rem;}
.leaflet-popup-tip{box-shadow:none;}
.acct-popup-name{font-weight:700;font-size:0.9rem;color:#181818;line-height:1.3;}
.acct-popup-place{margin-top:0.15rem;color:#706e6b;font-size:0.75rem;}
.acct-popup-row{display:flex;gap:0.4rem;align-items:center;margin-top:0.45rem;flex-wrap:wrap;}
.acct-popup-chip{background:#eef4ff;color:#014486;border-radius:999px;padding:0.05rem 0.45rem;font-size:0.65rem;font-weight:700;}
.acct-popup-risk{font-size:0.65rem;font-weight:700;}
.acct-popup-meta{margin-top:0.4rem;font-size:0.75rem;color:#444;line-height:1.45;}
.acct-popup-open{margin-top:0.6rem;border:0;background:#0176d3;color:#fff;border-radius:0.45rem;padding:0.32rem 0.65rem;font-size:0.75rem;font-weight:700;cursor:pointer;}
.acct-popup-open:hover{background:#014486;}
`;
const SEARCH_DEBOUNCE_MS = 350;
const COMPACT_BREAKPOINT_PX = 1200;

const SCOPE_OPTIONS = [
    { label: 'All Accounts', value: SCOPE_BOTH },
    { label: 'In Plan Cycle', value: SCOPE_IN },
    { label: 'Out of Plan Cycle', value: SCOPE_OUT }
];

const SORT_OPTIONS = [
    { label: 'Agentforce Score', value: SORT_AGENTFORCE },
    { label: 'Classification', value: SORT_CLASSIFICATION },
    { label: 'Name', value: SORT_NAME },
    { label: 'Connection Health', value: SORT_HEALTH },
    { label: 'Visit Gap', value: SORT_GAP },
    { label: 'Actual Visits', value: SORT_VISITS }
];

const RISK_PIN_COLORS = {
    High: '#ba0517',
    Med: '#fe9339',
    Low: '#2e844a'
};

const RISK_DOT_CLASS = {
    High: 'map-list-risk-high',
    Med: 'map-list-risk-med',
    Low: 'map-list-risk-low'
};

const MAP_INTELLIGENCE_LABEL = 'Cloudastick Map Intelligence';
const PLACE_KIND_META = {
  doctor: { label: 'Doctor', iconName: 'utility:user', color: '#3f7de5', themeKind: 'hcp' },
  pharmacy: { label: 'Pharmacy', iconName: 'utility:store', color: '#176935', themeKind: 'pharmacy' },
  hco: { label: 'HCO', iconName: 'utility:home', color: '#fdbf29', themeKind: 'hco' },
  company: { label: 'Company', iconName: 'utility:company', color: '#032d60' },
  unknown: { label: 'Unknown', iconName: 'utility:help', color: '#706e6b' }
};
const COMPANY_PIN_SVG =
  '<svg viewBox="0 0 24 24" aria-hidden="true"><path fill="#fff" d="M4 20V8h6V4h10v16H4zm2-2h4v-4H6v4zm0-6h4V10H6v2zm6 6h6v-2h-6v2zm0-4h6v-2h-6v2zm0-4h6V8h-6v2zM12 6v2h6V6h-6z"/></svg>';
const UNKNOWN_PIN_SVG =
  '<svg viewBox="0 0 24 24" aria-hidden="true"><path fill="#fff" d="M11 18h2v2h-2v-2zm1-16C9.2 2 7 4.2 7 7h2c0-1.7 1.3-3 3-3s3 1.3 3 3c0 1.5-.8 2.2-2.1 3.5L12 11.3c-1.2 1.2-1.9 2.2-1.9 3.7h2c0-.9.4-1.6 1.3-2.5l.9-.9C15.9 10.1 17 8.9 17 7c0-2.8-2.2-5-5-5z"/></svg>';
const EGYPT_MAP_CENTER = [26.8, 30.8];
const PHONE_LOOKUP_DEBOUNCE_MS = 650;
const ADDRESS_LOOKUP_DEBOUNCE_MS = 550;
const ADDRESS_LOOKUP_MIN_STREET_LEN = 4;
const QUALITY_BASELINE = 45;
const HCP_CREATE_TYPES = new Set([
  'PersonAccount',
  'SDO_PersonAccounts',
  'Medical_Professional_HCP',
  'Business_Contact'
]);

function escapeMapHtml(value) {
  return String(value ?? '')
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;')
    .replace(/"/g, '&quot;');
}

function phoneDigits(raw) {
  if (!raw) {
    return '';
  }
  let digits = String(raw).replace(/[^0-9]/g, '');
  if (digits.startsWith('00')) {
    digits = digits.slice(2);
  }
  if (digits.startsWith('20') && digits.length >= 11) {
    digits = digits.slice(2);
  }
  if (digits.startsWith('0') && digits.length >= 9) {
    digits = digits.slice(1);
  }
  return digits;
}

function looksLikePhone(raw) {
  return phoneDigits(raw).length >= 8 && /^[\s().+\-0-9]+$/.test(String(raw || '').trim());
}

function unwrapMapPlaces(result) {
  if (Array.isArray(result)) {
    return result;
  }
  if (Array.isArray(result?.places)) {
    return result.places;
  }
  return [];
}

function unwrapMapBias(result) {
  if (!result || Array.isArray(result)) {
    return null;
  }
  if (result.centerLat == null || result.centerLng == null) {
    return null;
  }
  return {
    centerLat: Number(result.centerLat),
    centerLng: Number(result.centerLng),
    radiusMeters: result.radiusMeters == null ? null : Number(result.radiusMeters)
  };
}

function uniquePhoneCount(form) {
  const seen = new Set();
  [form?.whatsappNumber, form?.phone, form?.clinicPhone].forEach((value) => {
    const digits = phoneDigits(value);
    if (digits) {
      seen.add(digits);
    }
  });
  return seen.size;
}

function filledPhoneCount(form) {
  return [form?.whatsappNumber, form?.phone, form?.clinicPhone].filter((value) => phoneDigits(value)).length;
}

function evaluateCreateQuality(form, recordType) {
  const missing = [];
  const extras = [];
  const isPerson = recordType?.isPersonAccount === true;
  const developerName = recordType?.developerName || '';
  const isHcp = HCP_CREATE_TYPES.has(developerName);
  const isPharmacy = developerName === 'Pharmacy';
  const isHco = developerName === 'Institution_HCO';
  if (isPerson) {
    if (!form?.lastName) {
      missing.push('Last name');
    }
  } else if (!form?.name) {
    missing.push('Name');
  }
  if (isHcp && !form?.specialty1) {
    missing.push('Specialty 1');
  } else if (isPharmacy && !form?.pharmacyType) {
    missing.push('Pharmacy type');
  } else if (isHco && !form?.institutionType) {
    missing.push('Institution type');
  } else if (!isHcp && !isPharmacy && !isHco && !form?.specialty1 && !form?.pharmacyType && !form?.institutionType) {
    missing.push('Specialty or type');
  }
  if (!form?.brick148Id) {
    missing.push('148 brick');
  }
  if (!form?.brick702Id) {
    missing.push('702 brick');
  }
  if (!form?.street) {
    missing.push('Detailed address');
  }
  if (form?.latitude == null || form?.longitude == null) {
    missing.push('Map pin');
  }
  if (!form?.building) {
    missing.push('Building');
  }
  if (!form?.governorate) {
    missing.push('Governorate');
  }
  if (!form?.landmark) {
    missing.push('علامة مميزة');
  }
  if (!form?.pinConfirmed) {
    missing.push('Confirm address and pin');
  }
  const uniquePhones = uniquePhoneCount(form);
  const filledPhones = filledPhoneCount(form);
  if (uniquePhones < 1) {
    missing.push('At least one contact number');
  }
  const duplicatePhones = filledPhones > uniquePhones;
  const canSave = missing.length === 0;
  let score = 0;
  if (canSave) {
    score = QUALITY_BASELINE;
    if (uniquePhones >= 2) {
      score += 12;
    } else {
      extras.push('Add a second unique phone channel (+12)');
    }
    if (uniquePhones >= 3) {
      score += 10;
    } else if (uniquePhones >= 2) {
      extras.push('Add a third unique phone channel (+10)');
    }
    if (isHcp) {
      if (form?.specialty2) {
        score += 12;
      } else {
        extras.push('Add a second specialty (+12)');
      }
      if (form?.specialty3) {
        score += 10;
      } else {
        extras.push('Add a third specialty (+10)');
      }
    }
    if (form?.email) {
      score += 11;
    } else {
      extras.push('Add an email (+11)');
    }
    score = Math.min(100, score);
  } else {
    score = Math.max(0, Math.round(((10 - missing.length) * QUALITY_BASELINE) / 10));
  }
  let label = 'Fair';
  if (score >= 75) {
    label = 'Excellent';
  } else if (score >= 50) {
    label = 'Good';
  }
  return { score, label, canSave, missing, extras, duplicatePhones, uniquePhones };
}

export default class AccountsTab extends NavigationMixin(LightningElement) {
  @track rows = [];
  @track mapRows = [];
  @track summary = {
    totalCount: 0,
    inPlanCount: 0,
    outPlanCount: 0,
    behindPaceCount: 0,
    monthLabel: ''
  };
  @track recordTypeCounts = [];

  isLoading = true;
  isExporting = false;
  errorMessage;
  viewMode = 'list';
  scope = SCOPE_BOTH;
  searchTerm = '';
  recordType = FILTER_ALL;
  classification = FILTER_ALL;
  brickId = FILTER_ALL;
  specialtyFilter = FILTER_ALL;
  sortBy = SORT_AGENTFORCE;
  sortDirection = 'desc';
  currentPage = 1;
  mapCurrentPage = 1;
  mapEligibleCount = 0;
  isNarrowViewport = false;
  sidebarOpen = true;
  sidebarPanel = 'lists';
  _viewportReady = false;
  listViewMode = LIST_MODE_ALL;
  selectedCollectionId = null;
  isAccountManager = false;
  nurtureNeedsYou = 0;
  nurtureWithManager = 0;
  nurtureWithSfe = 0;
  nurtureLane = NURTURE_LANE_ALL;
  approvalSelectedById = {};
  showMassRejectModal = false;
  massRejectMissing = false;
  isSavingApproval = false;
  rejectionReasonByAccountId = {};
  accountCollections = [];
  showNewAccountModal = false;
  selectedCreateRecordTypeId;
  createRecordTypeOptions = [];
  newAccountStep = 'recordType';
  masterSearchTerm = '';
  masterBrick148Id = FILTER_ALL;
  masterBrick702Id = FILTER_ALL;
  masterSpecialtyFilter = '';
  masterSpecialtyQuery = '';
  showMasterSpecialtyMenu = false;
  @track masterSearchResults = [];
  @track cognitiveResults = [];
  isMasterSearching = false;
  masterSearchRan = false;
  selectedMasterAccountId;
  mapSearchTerm = '';
  mapZoneId = '';
  mapBrick148Id = '';
  mapBrick702Id = '';
  mapArea = '';
  @track mapSearchResults = [];
  mapSearchBias = null;
  isMapSearching = false;
  mapSearchRan = false;
  selectedMapPlaceId;
  lookupSource = 'maps';
  vezeetaSearchTerm = '';
  @track vezeetaResults = [];
  vezeetaSearchRan = false;
  isVezeetaSearching = false;
  isVezeetaLoading = false;
  selectedVezeetaUrl;
  vezeetaSearchDebounce;
  @track createForm = {};
  isGettingCurrentLocation = false;
  currentLocationError = null;
  isSavingAccount = false;
  createError;
  masterSearchDebounce;
  mapSearchDebounce;
  phoneLookupDebounce;
  wizardCreateOptions = {};
  @track phoneMapSuggestion;
  isPhoneMapLookingUp = false;
  mapPrefillPhoneDigits = '';
  lastPhoneLookupDigits = '';
  createPinMarker;
  wizardCreateMapMode = false;
  isCreateAddressLookingUp = false;
  createAddressLookupDebounce;
  createAddressLookupToken = 0;
  lastCreateAddressLookupKey = '';
  createPinRippleLayer;
  createPinRippleRaf;
  _wizardPinLatLngKey = '';

  recordTypeOptions = [{ label: 'All Record Types', value: FILTER_ALL }];
  specialtyOptions = [{ label: 'All Specialties', value: FILTER_ALL }];
  brickOptions = [{ label: 'All Bricks', value: FILTER_ALL }];
  classificationOptions = [{ label: 'All Classifications', value: FILTER_ALL }];
  scopeOptions = SCOPE_OPTIONS;
  sortOptions = SORT_OPTIONS;

  mapInstance;
  mapMarkers = [];
  markersByAccountId = {};
  mapRenderToken = 0;
  loadRequestToken = 0;
  selectedAccountId;
  wizardMapInstance;
  wizardMapMarkers = [];
  wizardMapMarkersByPlaceId = {};
  wizardMapShouldFit = false;
  wizardMapSyncing = false;
  wizardMapPending = false;
  wizardMapDrawnKey;

  searchDebounce;
  _messageContext;
  territoryContextSubscription;

  @wire(MessageContext)
  wiredMessageContext(value) {
    this._messageContext = value;
    this.subscribeTerritoryContext();
  }

  fullBookOpen = false;
  canOpenFullBook = false;

  connectedCallback() {
    this.updateViewportMode();
    if (typeof window !== 'undefined') {
      window.addEventListener('resize', this.handleResize);
      window.addEventListener('keydown', this.handleDrawerKeydown);
    }
    this.subscribeTerritoryContext();
    this.loadPlannerCollections();
    this.loadFilterOptions();
    void this.loadApprovalContext();
    void this.loadBookMode();
    this.reloadData(true);
  }

  async loadBookMode() {
    try {
      const mode = await getBookMode();
      // SFE already gets the whole book from Apex; label it so and drop the toggle.
      if (mode?.fullBookByDefault === true) {
        this.fullBookOpen = true;
        this.canOpenFullBook = false;
        return;
      }
      this.canOpenFullBook = mode?.canOpenFullBook === true;
    } catch (e) {
      this.canOpenFullBook = false;
    }
  }

  handleToggleFullBook() {
    this.fullBookOpen = !this.fullBookOpen;
    this.reloadData(true);
  }

  get bookToggleLabel() {
    return this.fullBookOpen ? 'Show my book only' : 'Open full book';
  }

  get bookScopeLabel() {
    return this.fullBookOpen
      ? 'Full book is open.'
      : 'Showing this user’s territory book only.';
  }

  async loadApprovalContext() {
    try {
      this.isAccountManager = (await isAccountApprovalManager()) === true;
      if (this.isAccountManager) {
        const summary = await getAccountNurtureSummary();
        this.nurtureNeedsYou = summary?.needsYou || 0;
        this.nurtureWithManager = summary?.withManager || 0;
        this.nurtureWithSfe = summary?.withSfe || 0;
      } else {
        this.nurtureNeedsYou = 0;
        this.nurtureWithManager = 0;
        this.nurtureWithSfe = 0;
      }
    } catch (e) {
      this.isAccountManager = false;
      this.nurtureNeedsYou = 0;
      this.nurtureWithManager = 0;
      this.nurtureWithSfe = 0;
    }
  }

  subscribeTerritoryContext() {
    if (this.territoryContextSubscription) {
      return;
    }
    // Subscribe even when LMS MessageContext is missing (PWA stub / LWS); window + BroadcastChannel still fire.
    this.territoryContextSubscription = subscribeTerritoryContext(this._messageContext, () => {
      this.reloadData(true);
    });
  }

  renderedCallback() {
    if (this._scrollMapAccountId && this.isMapView) {
      const accountId = this._scrollMapAccountId;
      this._scrollMapAccountId = null;
      const listItem = this.template.querySelector(
        `.map-account-item[data-account-id="${accountId}"]`
      );
      listItem?.scrollIntoView({ block: 'nearest' });
    }
    if (!this.showNewAccountModal) {
      if (this.wizardMapInstance) {
        this.destroyWizardMap();
      }
      this._wizardMapStep = null;
      return;
    }
    if (this._wizardMapStep && this._wizardMapStep !== this.newAccountStep && this.wizardMapInstance) {
      this.destroyWizardMap();
    }
    this._wizardMapStep = this.newAccountStep;
    if (this.isMapSearchStep && this.isMapLookup) {
      this.ensureWizardSearchMap();
    } else if (this.isCreateFormStep) {
      this.ensureWizardCreateMap();
    }
  }

  disconnectedCallback() {
    this.destroyMap();
    this.destroyWizardMap();
    if (this.searchDebounce) {
      clearTimeout(this.searchDebounce);
    }
    if (typeof window !== 'undefined') {
      window.removeEventListener('resize', this.handleResize);
      window.removeEventListener('keydown', this.handleDrawerKeydown);
    }
    if (this.territoryContextSubscription) {
      unsubscribeTerritoryContext(this.territoryContextSubscription);
      this.territoryContextSubscription = undefined;
    }
  }

  handleResize = () => {
    this.updateViewportMode();
    if (this.isMapView && this.mapInstance) {
      setTimeout(() => this.mapInstance?.invalidateSize(), 100);
    }
  };

  updateViewportMode() {
    if (typeof window === 'undefined') {
      return;
    }
    const wasCompact = this.isCompactView;
    this.isNarrowViewport = window.innerWidth <= COMPACT_BREAKPOINT_PX;
    const nowCompact = this.isCompactView;
    if (!this._viewportReady) {
      this.sidebarOpen = !nowCompact;
      this._viewportReady = true;
      return;
    }
    if (nowCompact && !wasCompact) {
      this.sidebarOpen = false;
    } else if (!nowCompact && wasCompact) {
      this.sidebarOpen = true;
    }
  }

  handleDrawerKeydown = (event) => {
    if (event.key === 'Escape' && this.sidebarOpen && this.isCompactView) {
      this.sidebarOpen = false;
    }
  };

  closeOverlayDrawer() {
    if (this.isCompactView) {
      this.sidebarOpen = false;
    }
  }

  get isCompactView() {
    return (
      FORM_FACTOR === 'Small' ||
      FORM_FACTOR === 'Medium' ||
      this.isNarrowViewport
    );
  }

  get isListView() {
    return this.viewMode === 'list';
  }

  get isMapView() {
    return this.viewMode === 'map';
  }

  get listVariant() {
    return this.isListView ? 'brand' : 'neutral';
  }

  get mapVariant() {
    return this.isMapView ? 'brand' : 'neutral';
  }

  get listViewLabel() {
    return this.isCompactView ? 'List' : 'List View';
  }

  get mapViewLabel() {
    return this.isCompactView ? 'Map' : 'Map View';
  }

  get shellClass() {
    return `accounts-shell${this.isCompactView ? ' accounts-shell-compact' : ''}`;
  }

  get toolbarClass() {
    return `accounts-toolbar${this.isCompactView ? ' accounts-toolbar-compact' : ''}`;
  }

  get filterButtonClass() {
    return this.isCompactView && this.sidebarOpen ? 'toolbar-funnel toolbar-funnel-open' : 'toolbar-funnel';
  }

  get oceShellClass() {
    return `oce-shell${this.isCompactView ? ' oce-shell-overlay' : ''}`;
  }

  get sidebarClass() {
    const classes = ['oce-sidebar'];
    if (this.sidebarOpen) {
      classes.push('oce-sidebar-open');
    }
    if (this.isCompactView) {
      classes.push('oce-sidebar-overlay');
    }
    return classes.join(' ');
  }

  get showSidebarBackdrop() {
    return this.isCompactView && this.sidebarOpen && this.isListView;
  }

  get sidebarRole() {
    return this.isCompactView ? 'dialog' : 'complementary';
  }

  get sidebarAriaModal() {
    return this.isCompactView && this.sidebarOpen ? 'true' : 'false';
  }

  get sidebarAriaHidden() {
    return this.isCompactView && !this.sidebarOpen ? 'true' : 'false';
  }

  get isListsPanel() {
    return this.sidebarPanel === 'lists';
  }

  get isFiltersPanel() {
    return this.sidebarPanel === 'filters';
  }

  get listsSegmentClass() {
    return `oce-segment-btn${this.isListsPanel ? ' oce-segment-btn-active' : ''}`;
  }

  get filtersSegmentClass() {
    return `oce-segment-btn${this.isFiltersPanel ? ' oce-segment-btn-active' : ''}`;
  }

  get listNavItems() {
    return [
      {
        value: SCOPE_BOTH,
        label: `All (${this.summary.totalCount || 0})`,
        buttonClass: this.navButtonClass(
          this.listViewMode === LIST_MODE_ALL && this.scope === SCOPE_BOTH
        )
      },
      {
        value: SCOPE_IN,
        label: `In Plan Cycle (${this.summary.inPlanCount || 0})`,
        buttonClass: this.navButtonClass(
          this.listViewMode === LIST_MODE_ALL && this.scope === SCOPE_IN
        )
      },
      {
        value: SCOPE_OUT,
        label: `Out of Plan Cycle (${this.summary.outPlanCount || 0})`,
        buttonClass: this.navButtonClass(
          this.listViewMode === LIST_MODE_ALL && this.scope === SCOPE_OUT
        )
      }
    ];
  }

  get showApprovalsSidebar() {
    return this.isAccountManager === true;
  }

  get isNurturingList() {
    return this.listViewMode === LIST_MODE_NURTURING;
  }

  get nurtureTotal() {
    return (this.nurtureNeedsYou || 0) + (this.nurtureWithManager || 0) + (this.nurtureWithSfe || 0);
  }

  get pendingApprovalNavClass() {
    const classes = [this.navButtonClass(this.isNurturingList)];
    if ((this.nurtureNeedsYou || 0) > 0) {
      classes.push('oce-nav-btn-alert');
    }
    return classes.join(' ');
  }

  get pendingApprovalNavLabel() {
    const needsYou = this.nurtureNeedsYou || 0;
    if (needsYou === 1) {
      return '1 needs you';
    }
    if (needsYou > 1) {
      return `${needsYou} need you`;
    }
    const waiting = (this.nurtureWithManager || 0) + (this.nurtureWithSfe || 0);
    if (waiting === 1) {
      return '1 waiting';
    }
    if (waiting > 1) {
      return `${waiting} waiting`;
    }
    return 'None in progress';
  }

  get nurtureNavTitle() {
    return `${this.nurtureNeedsYou || 0} need your approval · ${this.nurtureWithManager || 0} with your manager · ${this.nurtureWithSfe || 0} with SFE`;
  }

  get nurtureHelp() {
    return 'Accounts still moving through approval, grouped by who has to act next.';
  }

  get nurtureChips() {
    const lane = this.nurtureLane || NURTURE_LANE_ALL;
    const chips = [
      { value: NURTURE_LANE_ALL, label: `All (${this.nurtureTotal})` },
      {
        value: 'needsYou',
        label: `Needs you (${this.nurtureNeedsYou || 0})`,
        alert: (this.nurtureNeedsYou || 0) > 0
      },
      { value: 'withManager', label: `With your manager (${this.nurtureWithManager || 0})` },
      { value: 'withSfe', label: `With SFE (${this.nurtureWithSfe || 0})` }
    ];
    return chips.map((chip) => {
      const classes = ['nurture-chip'];
      const selected = lane === chip.value;
      if (selected) {
        classes.push('nurture-chip-active');
      }
      if (chip.alert && !selected) {
        classes.push('nurture-chip-alert');
      }
      return {
        ...chip,
        className: classes.join(' '),
        ariaSelected: selected ? 'true' : 'false'
      };
    });
  }

  get actionableRows() {
    return (this.rows || []).filter((row) => row.showApprovalActions);
  }

  get selectedActionableIds() {
    return this.actionableRows
      .filter((row) => this.approvalSelectedById[row.accountId])
      .map((row) => row.accountId);
  }

  get showMassApproval() {
    return this.isNurturingList && this.actionableRows.length > 0;
  }

  get massSelectionLabel() {
    const selected = this.selectedActionableIds.length;
    const total = this.actionableRows.length;
    if (!selected) {
      return total === 1 ? '1 account needs you' : `${total} accounts need you`;
    }
    return selected === 1 ? '1 selected' : `${selected} selected`;
  }

  get massDisabled() {
    return this.isSavingApproval || this.selectedActionableIds.length === 0;
  }

  get massApproveLabel() {
    const count = this.selectedActionableIds.length;
    return count ? `Approve selected (${count})` : 'Approve selected';
  }

  get massRejectLabel() {
    const count = this.selectedActionableIds.length;
    return count ? `Reject selected (${count})` : 'Reject selected';
  }

  get massRejectHelp() {
    const count = this.selectedActionableIds.length;
    return count === 1
      ? 'This reason is saved on the selected account.'
      : `This reason is saved on ${count} selected accounts that do not already have one.`;
  }

  get emptyStateMessage() {
    if (!this.isNurturingList) {
      return 'No accounts match the current filters.';
    }
    if ((this.nurtureLane || NURTURE_LANE_ALL) === NURTURE_LANE_ALL) {
      return 'No accounts are moving through approval.';
    }
    return 'No accounts in this status.';
  }

  get hasPlannerCollections() {
    return (this.accountCollections || []).length > 0;
  }

  get collectionChips() {
    return (this.accountCollections || []).map((collection) => ({
      id: collection.id,
      label: `${collection.name} (${getCollectionAccountIds(collection).length})`,
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

  get selectedCollectionAccountIds() {
    if (this.listViewMode !== LIST_MODE_COLLECTION || !this.selectedCollectionId) {
      return [];
    }
    const collection = (this.accountCollections || []).find(
      (item) => item.id === this.selectedCollectionId
    );
    return getCollectionAccountIds(collection);
  }

  get countLabel() {
    if (this.listViewMode === LIST_MODE_NURTURING) {
      const total = this.summary.totalCount || 0;
      return `${total} in Account nurturing`;
    }
    if (this.listViewMode === LIST_MODE_COLLECTION) {
      const collection = (this.accountCollections || []).find(
        (item) => item.id === this.selectedCollectionId
      );
      const listCount = this.summary.totalCount || 0;
      const collectionSize = getCollectionAccountIds(collection).length;
      if (collectionSize > listCount) {
        return `${listCount} of ${collectionSize} in “${collection?.name || 'list'}”`;
      }
      return `${listCount} in “${collection?.name || 'list'}”`;
    }
    const total = this.summary.totalCount || 0;
    const scopeLabel =
      this.scope === SCOPE_IN
        ? 'in plan cycle'
        : this.scope === SCOPE_OUT
          ? 'out of plan cycle'
          : 'accounts';
    return `${total} ${scopeLabel}`;
  }

  get typeNavItems() {
    return (this.recordTypeCounts || []).map((item) => ({
      value: item.value,
      label: `${item.label} (${item.count || 0})`,
      buttonClass: this.navButtonClass(this.recordType === item.value)
    }));
  }

  get mapListItems() {
    return (this.mapRows || []).map((row) => {
      const themeKind = resolveAccountThemeKind(
        row.recordTypeDeveloperName,
        row.recordTypeName
      );
      const pinKind = themeKind === 'account' ? 'hcp' : themeKind;
      const typeLabels = { pharmacy: 'Pharmacy', hco: 'HCO', hcp: 'HCP' };
      const isSelected = row.accountId === this.selectedAccountId;
      const risk = row.agentforceRisk || 'Low';
      const riskKey = String(risk).toLowerCase();
      return {
        ...row,
        pinKind,
        selected: isSelected,
        typeIconUrl: accountTypeIconUrl(pinKind),
        typeLabel: typeLabels[pinKind] || 'HCP',
        classification: row.classification || '—',
        riskLabel: `${risk} pace`,
        riskChipClass: `map-risk-chip map-risk-chip-${riskKey}`,
        riskDotClass: RISK_DOT_CLASS[risk] || RISK_DOT_CLASS.Low,
        avatarClass: `map-account-avatar map-account-avatar-${pinKind}${isSelected ? ' is-selected' : ''}`,
        visitsLabel: row.targetVisits != null ? `Visits ${row.callPlanLabel}` : 'No visit target',
        itemClass: `map-account-item${isSelected ? ' map-account-item-selected' : ''}`,
        subtitle: [row.accountSubtype || row.recordTypeName, row.city].filter(Boolean).join(' · ') || '—'
      };
    });
  }

  get mapListBodyClass() {
    return `map-list-body${this.isLoading && this.hasMapListItems ? ' is-loading' : ''}`;
  }

  get showMapListSpinner() {
    return this.isLoading && !this.hasMapListItems;
  }

  get showMapEmptyOverlay() {
    return !this.isLoading && !this.hasMapListItems;
  }

  get mapListCountLabel() {
    const geocoded = this.mapEligibleCount || 0;
    const matched = this.summary.totalCount || 0;
    if (geocoded === 0) {
      return matched > 0 ? `None of ${matched} located` : 'None located';
    }
    if (geocoded <= MAP_PAGE_SIZE) {
      return `${geocoded} located`;
    }
    const start = (this.mapCurrentPage - 1) * MAP_PAGE_SIZE + 1;
    const end = Math.min(this.mapCurrentPage * MAP_PAGE_SIZE, geocoded);
    return `${start}–${end} of ${geocoded}`;
  }

  get showMapPagination() {
    return (this.mapEligibleCount || 0) > MAP_PAGE_SIZE;
  }

  get mapTotalPages() {
    return Math.max(1, Math.ceil((this.mapEligibleCount || 0) / MAP_PAGE_SIZE));
  }

  get mapHasPreviousPage() {
    return this.mapCurrentPage > 1;
  }

  get mapHasNextPage() {
    return this.mapCurrentPage < this.mapTotalPages;
  }

  get isMapPrevDisabled() {
    return !this.mapHasPreviousPage || this.isLoading;
  }

  get isMapNextDisabled() {
    return !this.mapHasNextPage || this.isLoading;
  }

  get mapPageLabel() {
    return `Page ${this.mapCurrentPage} of ${this.mapTotalPages}`;
  }

  get hasMapListItems() {
    return (this.mapRows || []).length > 0;
  }

  navButtonClass(isActive) {
    return `oce-nav-btn${isActive ? ' oce-nav-btn-active' : ''}`;
  }

  get listPageSize() {
    return this.isNurturingList && this.nurtureLane === 'needsYou' ? NURTURE_ACTION_PAGE_SIZE : PAGE_SIZE;
  }

  get showPagination() {
    return this.isListView && (this.summary.totalCount || 0) > this.listPageSize;
  }

  get totalPages() {
    return Math.max(1, Math.ceil((this.summary.totalCount || 0) / this.listPageSize));
  }

  get hasPreviousPage() {
    return this.currentPage > 1;
  }

  get hasNextPage() {
    return this.currentPage < this.totalPages;
  }

  get isPrevDisabled() {
    return !this.hasPreviousPage || this.isLoading;
  }

  get isNextDisabled() {
    return !this.hasNextPage || this.isLoading;
  }

  get rangeLabel() {
    const total = this.summary.totalCount || 0;
    if (total === 0) {
      return '';
    }
    const start = (this.currentPage - 1) * this.listPageSize + 1;
    const end = Math.min(this.currentPage * this.listPageSize, total);
    return `Showing ${start}–${end} of ${total}`;
  }

  get pageLabel() {
    return `Page ${this.currentPage} of ${this.totalPages}`;
  }

  get showEmptyState() {
    return !this.isLoading && !this.errorMessage && (this.rows || []).length === 0;
  }

  get createRecordTypeCards() {
    const selectedId = this.selectedCreateRecordTypeId ? String(this.selectedCreateRecordTypeId) : '';
    return (this.createRecordTypeOptions || []).map((option) => {
      const recordTypeId = option.recordTypeId ? String(option.recordTypeId) : '';
      const selected = recordTypeId !== '' && recordTypeId === selectedId;
      return {
        ...option,
        recordTypeId,
        selected,
        cardClass: selected ? 'record-type-card record-type-card-selected' : 'record-type-card'
      };
    });
  }

  get isCreateContinueDisabled() {
    if (this.newAccountStep === 'recordType') {
      return !this.selectedCreateRecordTypeId;
    }
    if (this.newAccountStep === 'masterSearch') {
      return !this.selectedMasterAccountId;
    }
    if (this.newAccountStep === 'mapSearch') {
      if (this.isVezeetaLookup) {
        return !this.selectedVezeetaUrl || this.isVezeetaLoading;
      }
      return !this.selectedMapPlaceId;
    }
    return this.isSavingAccount || this.isCreateFormInvalid;
  }

  get isCreateFormInvalid() {
    return !this.createQuality.canSave;
  }

  get createQuality() {
    return evaluateCreateQuality(this.createForm, this.selectedCreateRecordType);
  }

  get dataQualityScore() {
    return this.createQuality.score;
  }

  get dataQualityLabel() {
    return this.createQuality.label;
  }

  get dataQualityRingVariant() {
    if (this.dataQualityScore >= 75) {
      return 'base-autocomplete';
    }
    if (this.dataQualityScore >= 50) {
      return 'warning';
    }
    return 'expired';
  }

  get dataQualityMissing() {
    return this.createQuality.missing || [];
  }

  get dataQualityExtras() {
    return this.createQuality.canSave ? this.createQuality.extras || [] : [];
  }

  get hasQualityMissing() {
    return (this.createQuality.missing || []).length > 0;
  }

  get hasQualityExtras() {
    return (this.dataQualityExtras || []).length > 0;
  }

  get duplicatePhoneWarning() {
    return this.createQuality.duplicatePhones
      ? 'The same number is in more than one field. Duplicates do not raise the data quality score.'
      : '';
  }

  get qualityBaseline() {
    return QUALITY_BASELINE;
  }

  get showSpecialtyFields() {
    return HCP_CREATE_TYPES.has(this.selectedCreateRecordType?.developerName);
  }

  get showPharmacyTypeField() {
    return this.selectedCreateRecordType?.developerName === 'Pharmacy';
  }

  get showInstitutionTypeField() {
    return this.selectedCreateRecordType?.developerName === 'Institution_HCO';
  }

  get specialtyCreateOptions() {
    return this.wizardCreateOptions?.specialtyOptions || [];
  }

  get pharmacyTypeOptions() {
    return this.wizardCreateOptions?.pharmacyTypeOptions || [];
  }

  get institutionTypeOptions() {
    return this.wizardCreateOptions?.institutionTypeOptions || [];
  }

  get governorateOptions() {
    return this.wizardCreateOptions?.governorateOptions || [];
  }

  get brick148Options() {
    return (this.wizardCreateOptions?.bricks148 || []).map((brick) => ({
      label: brick.label,
      value: brick.brickId
    }));
  }

  get brick702Options() {
    const selected148 = this.createForm?.brick148Id;
    const rows = this.wizardCreateOptions?.bricks702 || [];
    const filtered = selected148
      ? rows.filter((brick) => String(brick.parentBrickId || '') === String(selected148))
      : rows;
    const source = filtered.length ? filtered : rows;
    return source.map((brick) => ({
      label: brick.label,
      value: brick.brickId
    }));
  }

  get mapZoneOptions() {
    return [
      { label: 'All zones', value: '' },
      ...(this.wizardCreateOptions?.bricks70 || []).map((brick) => ({
        label: brick.label,
        value: brick.brickId
      }))
    ];
  }

  get mapFilterBrick148Options() {
    const zoneId = this.mapZoneId;
    const rows = this.wizardCreateOptions?.bricks148 || [];
    const source = zoneId
      ? rows.filter((brick) => String(brick.zoneBrickId || brick.parentBrickId || '') === String(zoneId))
      : rows;
    return [
      { label: 'All 148 bricks', value: '' },
      ...source.map((brick) => ({
        label: brick.label,
        value: brick.brickId
      }))
    ];
  }

  get mapFilterBrick702Options() {
    const brick148Id = this.mapBrick148Id;
    const zoneId = this.mapZoneId;
    const rows = this.wizardCreateOptions?.bricks702 || [];
    let source = rows;
    if (brick148Id) {
      source = rows.filter((brick) => String(brick.parentBrickId || '') === String(brick148Id));
    } else if (zoneId) {
      source = rows.filter((brick) => String(brick.zoneBrickId || '') === String(zoneId));
    }
    return [
      { label: 'All 702 bricks', value: '' },
      ...source.map((brick) => ({
        label: brick.label,
        value: brick.brickId
      }))
    ];
  }

  get mapAreaOptions() {
    const empty = { label: 'All areas', value: '' };
    const govs = (this.wizardCreateOptions?.areaOptions || this.wizardCreateOptions?.governorateOptions || []).map(
      (opt) => ({
        label: opt.label,
        value: opt.value
      })
    );
    const brick148Id = this.mapBrick148Id;
    const zoneId = this.mapZoneId;
    let neighborhoods = this.wizardCreateOptions?.bricks702 || [];
    if (brick148Id) {
      neighborhoods = neighborhoods.filter((brick) => String(brick.parentBrickId || '') === String(brick148Id));
    } else if (zoneId) {
      neighborhoods = neighborhoods.filter((brick) => String(brick.zoneBrickId || '') === String(zoneId));
    } else {
      neighborhoods = [];
    }
    const seen = new Set(govs.map((opt) => String(opt.value || '').toLowerCase()));
    const extras = [];
    neighborhoods.forEach((brick) => {
      const name = (brick.city || brick.label || '').replace(/^\d+\s*[—-]\s*/, '').trim();
      const value = brick.city || brick.label?.split(' — ').pop() || brick.label;
      const key = String(value || '').toLowerCase();
      if (!value || seen.has(key)) {
        return;
      }
      seen.add(key);
      extras.push({ label: name || value, value });
    });
    return [empty, ...govs, ...extras];
  }

  get masterBrick148FilterOptions() {
    return [{ label: 'Any 148 brick', value: FILTER_ALL }, ...this.brick148Options];
  }

  get masterBrick702FilterOptions() {
    const selected148 =
      this.masterBrick148Id && this.masterBrick148Id !== FILTER_ALL ? this.masterBrick148Id : null;
    const rows = this.wizardCreateOptions?.bricks702 || [];
    const source = selected148
      ? rows.filter((brick) => String(brick.parentBrickId || '') === String(selected148))
      : rows;
    return [
      { label: 'Any 702 brick', value: FILTER_ALL },
      ...source.map((brick) => ({
        label: brick.label,
        value: brick.brickId
      }))
    ];
  }

  get filteredMasterSpecialtyOptions() {
    const any = { label: 'Any specialty', value: '', optionKey: 'any-specialty' };
    const rows = (this.specialtyCreateOptions || []).map((opt) => ({
      ...opt,
      optionKey: opt.value || opt.label
    }));
    const query = (this.masterSpecialtyQuery || '').trim().toLowerCase();
    const selected = rows.find((opt) => opt.value === this.masterSpecialtyFilter);
    const selectedLabel = (selected?.label || '').toLowerCase();
    let filtered = rows;
    if (query && query !== selectedLabel) {
      filtered = rows.filter(
        (opt) =>
          (opt.label || '').toLowerCase().includes(query) ||
          (opt.value || '').toLowerCase().replace(/_/g, ' ').includes(query)
      );
    }
    return [any, ...filtered].slice(0, 50);
  }

  get hasCreateRecordTypes() {
    return (this.createRecordTypeOptions || []).length > 0;
  }

  get selectedCreateRecordType() {
    const selectedId = this.selectedCreateRecordTypeId ? String(this.selectedCreateRecordTypeId) : '';
    return (this.createRecordTypeOptions || []).find(
      (option) => String(option.recordTypeId) === selectedId
    );
  }

  get isPersonCreateType() {
    return this.selectedCreateRecordType?.isPersonAccount === true;
  }

  get newAccountModalClass() {
    if (this.newAccountStep === 'recordType') {
      return 'slds-modal slds-fade-in-open slds-modal_small';
    }
    if (this.newAccountStep === 'mapSearch' || this.newAccountStep === 'createForm') {
      return 'slds-modal slds-fade-in-open slds-modal_large';
    }
    return 'slds-modal slds-fade-in-open slds-modal_medium';
  }

  get isRecordTypeStep() {
    return this.newAccountStep === 'recordType';
  }

  get isMasterSearchStep() {
    return this.newAccountStep === 'masterSearch';
  }

  get isMapSearchStep() {
    return this.newAccountStep === 'mapSearch';
  }

  get isVezeetaLookup() {
    return this.isPersonCreateType && this.lookupSource === 'vezeeta';
  }

  get isMapLookup() {
    return !this.isVezeetaLookup;
  }

  get showVezeetaSourceToggle() {
    return this.isPersonCreateType;
  }

  get mapSourceClass() {
    return this.isVezeetaLookup ? 'wizard-source-btn' : 'wizard-source-btn wizard-source-btn-active';
  }

  get vezeetaSourceClass() {
    return this.isVezeetaLookup ? 'wizard-source-btn wizard-source-btn-active' : 'wizard-source-btn';
  }

  get notFoundSearchLabel() {
    return this.isPersonCreateType ? 'Not found — search maps or Google Search' : 'Not found — search maps';
  }

  get hasVezeetaResults() {
    return (this.vezeetaResults || []).length > 0;
  }

  get showVezeetaEmpty() {
    return this.vezeetaSearchRan && !this.isVezeetaSearching && !this.hasVezeetaResults;
  }

  get showVezeetaHint() {
    return !this.vezeetaSearchRan && !this.isVezeetaSearching && !this.hasVezeetaResults;
  }

  get vezeetaResultCards() {
    return this.decorateWizardResults(this.vezeetaResults, this.selectedVezeetaUrl, 'urlName').map((row) => {
      const bits = [row.specialty, row.area, row.city].filter(Boolean);
      return {
        ...row,
        locationLine: [row.address, bits.join(' · ')].filter(Boolean).join(' — '),
        metaLine: row.clinicName || '',
        sourceLabel: 'Google Search',
        sourceClass: 'wizard-source-pill wizard-source-pill-vezeeta'
      };
    });
  }

  get isCreateFormStep() {
    return this.newAccountStep === 'createForm';
  }

  get newAccountSubtitle() {
    if (this.isRecordTypeStep) {
      return 'Select a record type to continue.';
    }
    if (this.isMasterSearchStep) {
      return 'Search by name, number, phone, specialty, city, or brick. Filter by 148/702 brick and specialty. Results show brick and location.';
    }
    if (this.isMapSearchStep) {
      if (this.isVezeetaLookup) {
        return 'Search Google by doctor name, or by a specialty such as جلدية. Choosing a doctor fills the profile, clinic, and map pin.';
      }
      return 'Search companies, doctors, or HCOs by name or phone. Icons show the place type; stars show KOLness and map rating.';
    }
    return 'Complete required fields, confirm the pin, and watch the data quality score.';
  }

  get newAccountStepLabel() {
    if (this.isRecordTypeStep) {
      return 'Step 1 of 4';
    }
    if (this.isMasterSearchStep) {
      return 'Step 2 of 4 — Search Master List';
    }
    if (this.isMapSearchStep) {
      return this.isVezeetaLookup ? 'Step 3 of 4 — Google Search' : 'Step 3 of 4 — Search maps';
    }
    return 'Step 4 of 4 — Review and save';
  }

  get primaryWizardLabel() {
    if (this.isRecordTypeStep) {
      return 'Continue';
    }
    if (this.isMasterSearchStep) {
      return 'Use selected account';
    }
    if (this.isMapSearchStep) {
      if (this.isVezeetaLookup) {
        return this.isVezeetaLoading ? 'Loading profile…' : 'Use Google Search doctor';
      }
      return 'Use map place';
    }
    return this.isSavingAccount ? 'Saving…' : 'Save account';
  }

  get showMapEmpty() {
    return this.mapSearchRan && !this.isMapSearching && (this.mapSearchResults || []).length === 0;
  }

  get hasMapResults() {
    return (this.mapSearchResults || []).length > 0;
  }

  get showMapSearchHint() {
    return !this.mapSearchRan && !this.isMapSearching && !this.hasMapResults;
  }

  get showMasterEmptyPrompt() {
    return (
      this.masterSearchRan &&
      !this.isMasterSearching &&
      (this.masterSearchResults || []).length === 0 &&
      (this.cognitiveResults || []).length === 0
    );
  }

  get showCognitiveSection() {
    return !this.isMasterSearching && (this.cognitiveResults || []).length > 0;
  }

  get showWizardBack() {
    return this.newAccountStep !== 'recordType';
  }

  get showMapEmptyPrompt() {
    return (
      this.mapSearchRan &&
      !this.isMapSearching &&
      (this.mapSearchResults || []).length === 0
    );
  }

  get hasMasterResults() {
    return (this.masterSearchResults || []).length > 0;
  }

  get createBrickOptions() {
    return [
      { label: 'No brick', value: '' },
      ...(this.brickOptions || []).filter((option) => option.value && option.value !== FILTER_ALL)
    ];
  }

  get masterResultCards() {
    return this.withSource(
      this.decorateWizardResults(this.masterSearchResults, this.selectedMasterAccountId, 'accountId'),
      'Master list',
      'master'
    );
  }

  get cognitiveResultCards() {
    return this.withSource(
      this.decorateWizardResults(this.cognitiveResults, this.selectedMasterAccountId, 'accountId'),
      'Master list',
      'master'
    );
  }

  get mapResultCards() {
    return this.decorateWizardResults(this.mapSearchResults, this.selectedMapPlaceId, 'placeId').map(
      (row) => {
        const placeKind = this.normalizePlaceKind(row.placeKind);
        const isKol = row.isKol === true;
        const starCount = isKol ? 5 : this.normalizeStarCount(row.starCount);
        const kindMeta = PLACE_KIND_META[placeKind] || PLACE_KIND_META.unknown;
        return {
          ...row,
          placeKind,
          placeKindLabel: row.placeKindLabel || kindMeta.label,
          kindIcon: kindMeta.iconName,
          kindIconUrl: accountTypeIconUrl(kindMeta.themeKind),
          kindClass: `wizard-kind-chip wizard-kind-${placeKind}`,
          isKol,
          starCount,
          stars: this.buildMapStars(starCount, isKol),
          starTitle: isKol
            ? 'KOL — 5 map stars'
            : starCount
              ? `${starCount} of 5 map stars`
              : 'No map rating yet',
          provider: MAP_INTELLIGENCE_LABEL,
          sourceLabel: 'Maps',
          sourceClass: 'wizard-source-pill wizard-source-pill-maps',
          cardClass: [row.cardClass || 'wizard-result-card', isKol ? 'wizard-result-card-kol' : '']
            .filter(Boolean)
            .join(' ')
        };
      }
    );
  }

  normalizePlaceKind(kind) {
    const value = String(kind || '').toLowerCase();
    return PLACE_KIND_META[value] ? value : 'unknown';
  }

  normalizeStarCount(value) {
    const stars = Number(value);
    if (!Number.isFinite(stars) || stars <= 0) {
      return 0;
    }
    return Math.min(5, Math.round(stars));
  }

  buildMapStars(starCount, isKol) {
    const filled = this.normalizeStarCount(starCount);
    const stars = [];
    for (let i = 1; i <= 5; i += 1) {
      const on = i <= filled;
      stars.push({
        key: String(i),
        iconName: 'utility:favorite',
        cssClass: on
          ? isKol
            ? 'wizard-star wizard-star-on wizard-star-kol'
            : 'wizard-star wizard-star-on'
          : 'wizard-star wizard-star-off'
      });
    }
    return stars;
  }

  withSource(rows, label, kind) {
    const sourceClass = `wizard-source-pill wizard-source-pill-${kind}`;
    return (rows || []).map((row) => ({
      ...row,
      sourceLabel: label,
      sourceClass
    }));
  }

  decorateWizardResults(rows, selectedId, idField) {
    const selected = selectedId ? String(selectedId) : '';
    return (rows || []).map((row, index) => {
      const id = row[idField] ? String(row[idField]) : `row-${index}`;
      const selectedRow = selected !== '' && id === selected;
      return {
        ...row,
        rowId: id,
        selected: selectedRow,
        cardClass: selectedRow ? 'wizard-result-card wizard-result-card-selected' : 'wizard-result-card'
      };
    });
  }

  async loadFilterOptions() {
    try {
      const [recordTypes, plannerOpts, createTypes, wizardOpts] = await Promise.all([
        getAccountsTabRecordTypeOptions(),
        getPlannerAccountFilterOptions({ contextUserId: null }),
        getCreateableAccountRecordTypes(),
        getWizardCreateOptions()
      ]);
      this.recordTypeOptions = this.normalizeComboboxOptions(recordTypes, this.recordTypeOptions);
      this.createRecordTypeOptions = Array.isArray(createTypes) ? createTypes : [];
      this.classificationOptions = [
        { label: 'All Classifications', value: FILTER_ALL },
        { label: 'A1', value: 'A1' },
        { label: 'A2', value: 'A2' },
        { label: 'A3', value: 'A3' },
        { label: 'B1', value: 'B1' },
        { label: 'B2', value: 'B2' },
        { label: 'B3', value: 'B3' },
        { label: 'C1', value: 'C1' },
        { label: 'C2', value: 'C2' },
        { label: 'C3', value: 'C3' }
      ];
      // The planner lists already start with their own "All" entry; keep only ours.
      const withoutAll = (options) => (options || []).filter((option) => option.value !== FILTER_ALL);
      this.specialtyOptions = [
        { label: 'All Specialties', value: FILTER_ALL },
        ...withoutAll(plannerOpts?.specialtyOptions)
      ];
      this.brickOptions = [
        { label: 'All Bricks', value: FILTER_ALL },
        ...withoutAll(plannerOpts?.brickOptions)
      ];
      this.wizardCreateOptions = wizardOpts || {};
    } catch (error) {
      this.specialtyOptions = [{ label: 'All Specialties', value: FILTER_ALL }];
      this.brickOptions = [{ label: 'All Bricks', value: FILTER_ALL }];
      this.createRecordTypeOptions = [];
      this.wizardCreateOptions = {};
    }
  }

  loadPlannerCollections() {
    this.accountCollections = loadAccountCollections(USER_ID);
    if (
      this.selectedCollectionId &&
      !this.accountCollections.some((item) => item.id === this.selectedCollectionId)
    ) {
      this.selectedCollectionId = null;
      this.listViewMode = LIST_MODE_ALL;
    }
  }

  normalizeComboboxOptions(options, fallback = []) {
    const source = Array.isArray(options) && options.length ? options : fallback;
    return source
      .map((option) => ({
        label: option?.label,
        value: option?.value
      }))
      .filter((option) => option.label && option.value);
  }

  readInputValue(event) {
    if (event?.detail?.value != null) {
      return event.detail.value;
    }
    if (event?.target?.value != null) {
      return event.target.value;
    }
    return '';
  }

  buildApexParams(mapMode = false) {
    const accountIds = this.selectedCollectionAccountIds;
    const trimmedSearch = (this.searchTerm || '').trim();
    const pageSize = mapMode ? MAP_PAGE_SIZE : this.listPageSize;
    const page = mapMode ? this.mapCurrentPage : this.currentPage;
    return {
      scope: this.scope,
      searchTerm: trimmedSearch || null,
      recordTypeDeveloperName: this.recordType,
      classification:
        this.classification === FILTER_ALL ? null : this.classification,
      sortBy: this.sortBy,
      sortDirection: this.sortDirection,
      offset: (page - 1) * pageSize,
      pageSize,
      monthStart: null,
      contextUserId: null,
      accountIds: accountIds.length ? accountIds : null,
      brickId: this.brickId === FILTER_ALL ? null : this.brickId,
      specialtyFilter: this.specialtyFilter === FILTER_ALL ? null : this.specialtyFilter,
      approvalScope: this.listViewMode === LIST_MODE_NURTURING ? APPROVAL_SCOPE_NURTURING : null,
      nurtureLane:
        this.listViewMode === LIST_MODE_NURTURING && this.nurtureLane && this.nurtureLane !== NURTURE_LANE_ALL
          ? this.nurtureLane
          : null,
      repBookOnly: this.fullBookOpen ? false : true
    };
  }

  async handleExportCsv() {
    if (this.isExporting) {
      return;
    }
    this.isExporting = true;
    this.errorMessage = null;
    try {
      // The full book comes back in chunks; a territory book comes back in one.
      const parts = [];
      let afterId = null;
      for (;;) {
        // eslint-disable-next-line no-await-in-loop
        const chunk = await exportAccountsCsvChunk({
          scope: this.scope,
          searchTerm: (this.searchTerm || '').trim() || null,
          recordTypeDeveloperName: this.recordType,
          classification: this.classification === FILTER_ALL ? null : this.classification,
          contextUserId: null,
          brickId: this.brickId === FILTER_ALL ? null : this.brickId,
          specialtyFilter: this.specialtyFilter === FILTER_ALL ? null : this.specialtyFilter,
          fullBook: this.fullBookOpen,
          afterId
        });
        if (chunk?.csv) {
          parts.push(chunk.csv);
        }
        if (!chunk || chunk.done !== false || !chunk.nextAfterId) {
          break;
        }
        afterId = chunk.nextAfterId;
      }
      const csv = parts.join('\n');
      if (!csv || csv === 'null' || String(csv).trim() === '') {
        this.errorMessage = 'Nothing to export for the current territory.';
        return;
      }
      // Lightning Web Security rejects text/csv and MIME parameters, so the file goes out as
      // text/plain with a .csv name; the BOM keeps Arabic names readable in Excel.
      const blob = new Blob(['\uFEFF' + csv], { type: 'text/plain' });
      const url = URL.createObjectURL(blob);
      const link = document.createElement('a');
      link.href = url;
      link.download = 'accounts_export.csv';
      link.style.display = 'none';
      document.body.appendChild(link);
      link.click();
      link.remove();
      // eslint-disable-next-line @lwc/lwc/no-async-operation
      setTimeout(() => URL.revokeObjectURL(url), 60000);
    } catch (error) {
      this.errorMessage = this.reduceError(error);
    } finally {
      this.isExporting = false;
    }
  }

  handleColumnSort(event) {
    const sortField = event.detail?.sortField;
    if (!sortField) {
      return;
    }
    const requestedDirection = event.detail?.sortDirection;
    if (requestedDirection === 'asc' || requestedDirection === 'desc') {
      this.sortBy = sortField;
      this.sortDirection = requestedDirection;
    } else if (this.sortBy === sortField) {
      this.sortDirection = this.sortDirection === 'asc' ? 'desc' : 'asc';
    } else {
      this.sortBy = sortField;
      this.sortDirection =
        sortField === SORT_NAME || sortField === SORT_CLASSIFICATION ? 'asc' : 'desc';
    }
    // Oce list sorts the current page client-side — avoid a full Apex round-trip.
  }

  handleBrickChange(event) {
    this.brickId = this.readInputValue(event);
    this.reloadData(true);
  }

  handleSpecialtyChange(event) {
    this.specialtyFilter = this.readInputValue(event);
    this.reloadData(true);
  }

  applyPageSummary(result) {
    this.summary = {
      totalCount: result?.totalCount || 0,
      inPlanCount: result?.inPlanCount || 0,
      outPlanCount: result?.outPlanCount || 0,
      behindPaceCount: result?.behindPaceCount || 0,
      monthLabel: result?.monthLabel || ''
    };
    this.recordTypeCounts = result?.recordTypeCounts || [];
    this.mapEligibleCount = result?.mapEligibleCount ?? this.mapEligibleCount;
    if (this.listViewMode === LIST_MODE_NURTURING && result) {
      this.nurtureNeedsYou = result.nurtureNeedsYouCount || 0;
      this.nurtureWithManager = result.nurtureWithManagerCount || 0;
      this.nurtureWithSfe = result.nurtureWithSfeCount || 0;
    }
    const maxPage = Math.max(
      1,
      Math.ceil((this.summary.totalCount || 0) / this.listPageSize)
    );
    if (this.currentPage > maxPage) {
      this.currentPage = maxPage;
    }
    const maxMapPage = Math.max(
      1,
      Math.ceil((this.mapEligibleCount || 0) / MAP_PAGE_SIZE)
    );
    if (this.mapCurrentPage > maxMapPage) {
      this.mapCurrentPage = maxMapPage;
    }
  }

  reloadData(reset) {
    if (reset) {
      this.currentPage = 1;
      this.mapCurrentPage = 1;
    }
    if (this.isMapView) {
      return this.refreshMapView();
    }
    return this.loadPage();
  }

  async loadPage() {
    const token = ++this.loadRequestToken;
    this.isLoading = true;
    this.errorMessage = null;
    try {
      const result = await getAccountsTabPage(this.buildApexParams(false));
      if (token !== this.loadRequestToken) {
        return;
      }
      this.rows = (result?.rows || []).map((row) => this.mapRow(row));
      this.applyPageSummary(result);
    } catch (error) {
      if (token === this.loadRequestToken) {
        this.errorMessage = this.reduceError(error);
      }
    } finally {
      if (token === this.loadRequestToken) {
        this.isLoading = false;
      }
      void this.loadApprovalContext();
    }
  }

  async refreshMapView() {
    const token = ++this.mapRenderToken;
    this.isLoading = true;
    this.errorMessage = null;
    this.selectedAccountId = null;
    try {
      const summaryParams = {
        ...this.buildApexParams(false),
        offset: 0,
        pageSize: 1
      };
      const mapParams = this.buildApexParams(true);
      const [pageResult, mapPage] = await Promise.all([
        getAccountsTabPage(summaryParams),
        getAccountsTabMapPoints(mapParams)
      ]);
      if (token !== this.mapRenderToken) {
        return;
      }
      this.applyPageSummary(pageResult);
      this.mapEligibleCount = mapPage?.mapEligibleCount || 0;
      this.mapRows = (mapPage?.rows || []).map((row) => this.mapRow(row));
      await this.drawMapMarkers(this.mapRows, token);
    } catch (error) {
      if (token === this.mapRenderToken) {
        this.errorMessage = this.reduceError(error);
      }
    } finally {
      if (token === this.mapRenderToken) {
        this.isLoading = false;
      }
    }
  }

  mapRow(row) {
    const target = row.targetVisits;
    const actual = row.actualVisits || 0;
    const planned = row.plannedVisits || 0;
    const hasTarget = target != null;
    return {
      ...row,
      reachPercentDisplay:
        row.reachPercent != null ? `${Math.round(Number(row.reachPercent))}%` : '—',
      projectedPercentDisplay:
        row.projectedPercent != null
          ? `${Math.round(Number(row.projectedPercent))}%`
          : '—',
      agentforceScoreDisplay:
        row.agentforceScore != null ? Number(row.agentforceScore).toFixed(1) : '—',
      isKolLabel: row.isKol ? 'Yes' : 'No',
      targetLabel: row.inPlanCycle ? 'Yes' : 'No',
      callPlanLabel: hasTarget ? `${actual}/${target}` : '—',
      plannedPlanLabel: hasTarget ? `Planned ${planned}/${target}` : '—',
      targetVisits: hasTarget ? target : null,
      visitGap: hasTarget ? row.visitGap : null
    };
  }

  handleShowList() {
    this.viewMode = 'list';
    this.destroyMap();
    if (!this.rows.length) {
      this.reloadData(true);
    }
  }

  async handleShowMap() {
    this.viewMode = 'map';
    await this.refreshMapView();
  }

  handleScopeChange(event) {
    this.listViewMode = LIST_MODE_ALL;
    this.selectedCollectionId = null;
    this.scope = this.readInputValue(event);
    this.reloadData(true);
  }

  handleRecordTypeChange(event) {
    this.recordType = this.readInputValue(event);
    this.reloadData(true);
  }

  handleClassificationChange(event) {
    this.classification = this.readInputValue(event);
    this.reloadData(true);
  }

  handleSortChange(event) {
    this.sortBy = this.readInputValue(event);
    this.sortDirection =
      this.sortBy === SORT_NAME || this.sortBy === SORT_CLASSIFICATION ? 'asc' : 'desc';
    this.reloadData(true);
  }

  handleOceSortToggle() {
    if (this.sortBy !== SORT_NAME) {
      this.sortBy = SORT_NAME;
      this.sortDirection = 'asc';
    } else {
      this.sortDirection = this.sortDirection === 'asc' ? 'desc' : 'asc';
    }
    this.reloadData(true);
  }

  handleSearchChange(event) {
    this.scheduleSearch(this.readInputValue(event));
  }

  handleSearchKeyUp(event) {
    this.scheduleSearch(this.readInputValue(event));
  }

  applySearch(value) {
    this.searchTerm = value ?? '';
    if (this.searchDebounce) {
      clearTimeout(this.searchDebounce);
      this.searchDebounce = null;
    }
    this.reloadData(true);
  }

  scheduleSearch(value) {
    this.searchTerm = value ?? '';
    if (this.searchDebounce) {
      clearTimeout(this.searchDebounce);
    }
    this.searchDebounce = setTimeout(() => {
      this.searchDebounce = null;
      this.reloadData(true);
    }, SEARCH_DEBOUNCE_MS);
  }

  handleRefresh() {
    this.loadPlannerCollections();
    this.reloadData(true);
  }

  handleNewAccount() {
    const options = this.createRecordTypeOptions || [];
    if (options.length === 0) {
      this.navigateToNewAccount(null);
      return;
    }
    this.resetNewAccountWizard();
    this.selectedCreateRecordTypeId = options[0].recordTypeId;
    this.showNewAccountModal = true;
  }

  handleSelectCreateRecordType(event) {
    this.selectedCreateRecordTypeId = event.currentTarget.dataset.recordTypeId;
  }

  handleCloseNewAccountModal() {
    this.showNewAccountModal = false;
    this.resetNewAccountWizard();
  }

  handleWizardBack() {
    if (this.newAccountStep === 'masterSearch') {
      this.newAccountStep = 'recordType';
      return;
    }
    if (this.newAccountStep === 'mapSearch') {
      this.newAccountStep = 'masterSearch';
      return;
    }
    if (this.newAccountStep === 'createForm') {
      this.newAccountStep = 'mapSearch';
      this.wizardMapShouldFit = true;
    }
  }

  handleConfirmNewAccount() {
    if (this.newAccountStep === 'recordType') {
      this.newAccountStep = 'masterSearch';
      return;
    }
    if (this.newAccountStep === 'masterSearch') {
      this.openSelectedMasterAccount();
      return;
    }
    if (this.newAccountStep === 'mapSearch') {
      if (this.isVezeetaLookup) {
        this.applySelectedVezeetaDoctor();
        return;
      }
      this.applySelectedMapPlace();
      return;
    }
    this.saveWizardAccount();
  }

  handleMasterSearchChange(event) {
    this.masterSearchTerm = this.readInputValue(event);
    this.scheduleMasterSearch();
  }

  handleMasterSearchKeyUp(event) {
    this.masterSearchTerm = this.readInputValue(event);
    this.scheduleMasterSearch();
  }

  handleMasterBrick148FilterChange(event) {
    this.masterBrick148Id = this.readInputValue(event);
    const allowed = new Set(
      (this.masterBrick702FilterOptions || []).map((option) => String(option.value || ''))
    );
    if (
      this.masterBrick702Id &&
      this.masterBrick702Id !== FILTER_ALL &&
      !allowed.has(String(this.masterBrick702Id))
    ) {
      this.masterBrick702Id = FILTER_ALL;
    }
    this.scheduleMasterSearch();
  }

  handleMasterBrick702FilterChange(event) {
    this.masterBrick702Id = this.readInputValue(event);
    this.scheduleMasterSearch();
  }

  handleMasterSpecialtyFocus() {
    this.showMasterSpecialtyMenu = true;
  }

  handleMasterSpecialtyQueryInput(event) {
    this.masterSpecialtyQuery = this.readInputValue(event);
    this.showMasterSpecialtyMenu = true;
    const query = (this.masterSpecialtyQuery || '').trim();
    if (!query) {
      this.masterSpecialtyFilter = '';
    }
    this.scheduleMasterSearch();
  }

  handleMasterSpecialtyPick(event) {
    const value = event.currentTarget.dataset.value || '';
    const label = event.currentTarget.dataset.label || '';
    this.masterSpecialtyFilter = value;
    this.masterSpecialtyQuery = value ? label : '';
    this.showMasterSpecialtyMenu = false;
    this.scheduleMasterSearch();
  }

  scheduleMasterSearch() {
    if (this.masterSearchDebounce) {
      clearTimeout(this.masterSearchDebounce);
    }
    this.masterSearchDebounce = setTimeout(() => {
      this.masterSearchDebounce = null;
      this.runMasterSearch();
    }, SEARCH_DEBOUNCE_MS);
  }

  hasMasterSearchCriteria() {
    const term = (this.masterSearchTerm || '').trim();
    return (
      term.length >= 2 ||
      this.hasMasterBrick148Filter() ||
      this.hasMasterBrick702Filter() ||
      Boolean(this.masterSpecialtyFilter)
    );
  }

  hasMasterBrick148Filter() {
    return Boolean(this.masterBrick148Id) && this.masterBrick148Id !== FILTER_ALL;
  }

  hasMasterBrick702Filter() {
    return Boolean(this.masterBrick702Id) && this.masterBrick702Id !== FILTER_ALL;
  }

  async runMasterSearch() {
    this.selectedMasterAccountId = null;
    if (!this.hasMasterSearchCriteria() || !this.selectedCreateRecordTypeId) {
      this.masterSearchResults = [];
      this.cognitiveResults = [];
      this.masterSearchRan = false;
      return;
    }
    const term = (this.masterSearchTerm || '').trim();
    this.isMasterSearching = true;
    this.masterSearchRan = true;
    const filters = {
      searchTerm: term,
      recordTypeId: this.selectedCreateRecordTypeId,
      brick148Id: this.hasMasterBrick148Filter() ? this.masterBrick148Id : null,
      brick702Id: this.hasMasterBrick702Filter() ? this.masterBrick702Id : null,
      specialtyFilter: this.masterSpecialtyFilter || null
    };
    try {
      const rows = await searchMasterListWithFilters({
        ...filters,
        cognitive: false
      });
      this.masterSearchResults = Array.isArray(rows) ? rows : [];
      if (this.masterSearchResults.length === 0 && term.length >= 2) {
        const cognitive = await searchMasterListWithFilters({
          ...filters,
          cognitive: true
        });
        this.cognitiveResults = Array.isArray(cognitive) ? cognitive : [];
      } else {
        this.cognitiveResults = [];
      }
    } catch (error) {
      this.masterSearchResults = [];
      this.cognitiveResults = [];
      this.toast('Master search failed', this.errorMessageFrom(error), 'error');
    } finally {
      this.isMasterSearching = false;
    }
  }

  handleSelectMasterAccount(event) {
    this.selectedMasterAccountId = event.currentTarget.dataset.accountId;
  }

  openSelectedMasterAccount() {
    if (!this.selectedMasterAccountId) {
      return;
    }
    const accountId = this.selectedMasterAccountId;
    this.handleCloseNewAccountModal();
    this.toast('Master account found', 'Opened the existing account instead of creating a duplicate.', 'success');
    this.navigateToAccount(accountId);
  }

  handleGoToMapSearch() {
    this.newAccountStep = 'mapSearch';
    if ((this.mapSearchTerm || '').trim().length < 2 && (this.masterSearchTerm || '').trim().length >= 2) {
      this.mapSearchTerm = this.masterSearchTerm;
    }
    if ((this.mapSearchTerm || '').trim().length >= 2) {
      this.runMapSearch();
    }
  }

  handleMapSearchChange(event) {
    this.mapSearchTerm = this.readInputValue(event);
    this.scheduleMapSearch();
  }

  handleMapZoneChange(event) {
    this.mapZoneId = this.readInputValue(event);
    const allowed148 = new Set(
      (this.mapFilterBrick148Options || []).map((option) => String(option.value || ''))
    );
    if (this.mapBrick148Id && !allowed148.has(String(this.mapBrick148Id))) {
      this.mapBrick148Id = '';
    }
    const allowed702 = new Set(
      (this.mapFilterBrick702Options || []).map((option) => String(option.value || ''))
    );
    if (this.mapBrick702Id && !allowed702.has(String(this.mapBrick702Id))) {
      this.mapBrick702Id = '';
    }
    this.scheduleMapSearch();
  }

  handleMapBrick148Change(event) {
    this.mapBrick148Id = this.readInputValue(event);
    const allowed702 = new Set(
      (this.mapFilterBrick702Options || []).map((option) => String(option.value || ''))
    );
    if (this.mapBrick702Id && !allowed702.has(String(this.mapBrick702Id))) {
      this.mapBrick702Id = '';
    }
    if (this.mapBrick148Id && !this.mapZoneId) {
      const brick148 = (this.wizardCreateOptions?.bricks148 || []).find(
        (brick) => String(brick.brickId) === String(this.mapBrick148Id)
      );
      if (brick148?.zoneBrickId) {
        this.mapZoneId = brick148.zoneBrickId;
      }
    }
    this.scheduleMapSearch();
  }

  handleMapBrick702Change(event) {
    this.mapBrick702Id = this.readInputValue(event);
    if (this.mapBrick702Id) {
      const brick702 = (this.wizardCreateOptions?.bricks702 || []).find(
        (brick) => String(brick.brickId) === String(this.mapBrick702Id)
      );
      if (brick702?.parentBrickId && !this.mapBrick148Id) {
        this.mapBrick148Id = brick702.parentBrickId;
      }
      if (brick702?.zoneBrickId && !this.mapZoneId) {
        this.mapZoneId = brick702.zoneBrickId;
      }
    }
    this.scheduleMapSearch();
  }

  handleMapAreaChange(event) {
    this.mapArea = this.readInputValue(event);
    this.scheduleMapSearch();
  }

  buildMapGeoFilter() {
    const zoneBrickId = this.mapZoneId || null;
    const brick148Id = this.mapBrick148Id || null;
    const brick702Id = this.mapBrick702Id || null;
    const area = this.mapArea || null;
    if (!zoneBrickId && !brick148Id && !brick702Id && !area) {
      return null;
    }
    return { zoneBrickId, brick148Id, brick702Id, area };
  }

  scheduleMapSearch() {
    if (this.mapSearchDebounce) {
      clearTimeout(this.mapSearchDebounce);
    }
    this.mapSearchDebounce = setTimeout(() => {
      this.mapSearchDebounce = null;
      this.runMapSearch();
    }, SEARCH_DEBOUNCE_MS);
  }

  async runMapSearch() {
    const term = (this.mapSearchTerm || '').trim();
    const geoFilter = this.buildMapGeoFilter();
    this.selectedMapPlaceId = null;
    if (term.length < 2) {
      this.mapSearchResults = [];
      this.mapSearchRan = false;
      this.wizardMapShouldFit = true;
      if (geoFilter) {
        try {
          const result = await searchMapPlaces({
            searchTerm: term,
            recordTypeDeveloperName: this.selectedCreateRecordType?.developerName,
            geoFilter
          });
          this.mapSearchBias = unwrapMapBias(result);
        } catch (error) {
          this.mapSearchBias = null;
        }
      } else {
        this.mapSearchBias = null;
      }
      return;
    }
    this.isMapSearching = true;
    this.mapSearchRan = true;
    try {
      const result = await searchMapPlaces({
        searchTerm: term,
        recordTypeDeveloperName: this.selectedCreateRecordType?.developerName,
        geoFilter
      });
      this.mapSearchResults = unwrapMapPlaces(result);
      this.mapSearchBias = unwrapMapBias(result);
      this.wizardMapShouldFit = true;
    } catch (error) {
      this.mapSearchResults = [];
      this.mapSearchBias = null;
      this.toast('Map search failed', this.errorMessageFrom(error), 'error');
    } finally {
      this.isMapSearching = false;
    }
  }

  handleSelectMapPlace(event) {
    this.selectWizardMapPlace(event.currentTarget.dataset.placeId, true);
  }

  applySelectedMapPlace() {
    const place = (this.mapSearchResults || []).find(
      (row) => String(row.placeId) === String(this.selectedMapPlaceId)
    );
    this.prefillCreateForm(place || null);
    this.newAccountStep = 'createForm';
  }

  handleLookupSourceChange(event) {
    const source = event.currentTarget?.dataset?.source;
    if (source !== 'maps' && source !== 'vezeeta') {
      return;
    }
    if (source === this.lookupSource) {
      return;
    }
    this.lookupSource = source;
    if (source === 'vezeeta') {
      this.destroyWizardMap();
      if (!(this.vezeetaSearchTerm || '').trim() && (this.mapSearchTerm || '').trim()) {
        this.vezeetaSearchTerm = this.mapSearchTerm;
      }
      if ((this.vezeetaSearchTerm || '').trim().length >= 2) {
        this.runVezeetaSearch();
      }
      return;
    }
    if ((this.mapSearchTerm || '').trim().length >= 2) {
      this.runMapSearch();
    }
  }

  handleVezeetaSearchChange(event) {
    this.vezeetaSearchTerm = this.readInputValue(event);
    this.scheduleVezeetaSearch();
  }

  scheduleVezeetaSearch() {
    if (this.vezeetaSearchDebounce) {
      clearTimeout(this.vezeetaSearchDebounce);
    }
    this.vezeetaSearchDebounce = setTimeout(() => {
      this.vezeetaSearchDebounce = null;
      this.runVezeetaSearch();
    }, SEARCH_DEBOUNCE_MS);
  }

  async runVezeetaSearch() {
    const term = (this.vezeetaSearchTerm || '').trim();
    this.selectedVezeetaUrl = null;
    if (term.length < 2) {
      this.vezeetaResults = [];
      this.vezeetaSearchRan = false;
      return;
    }
    this.isVezeetaSearching = true;
    this.vezeetaSearchRan = true;
    try {
      const rows = await searchVezeetaDoctors({ searchTerm: term });
      this.vezeetaResults = Array.isArray(rows) ? rows : [];
    } catch (error) {
      this.vezeetaResults = [];
      this.toast('Google Search failed', this.errorMessageFrom(error), 'error');
    } finally {
      this.isVezeetaSearching = false;
    }
  }

  handleSelectVezeetaDoctor(event) {
    this.selectedVezeetaUrl = event.currentTarget.dataset.urlName;
  }

  async applySelectedVezeetaDoctor() {
    const hit = (this.vezeetaResults || []).find(
      (row) => String(row.urlName) === String(this.selectedVezeetaUrl)
    );
    if (!hit?.urlName || this.isVezeetaLoading) {
      return;
    }
    this.isVezeetaLoading = true;
    try {
      const doctor = await getVezeetaDoctor({ profileUrl: hit.urlName });
      const name = hit.name || doctor?.name || '';
      this.prefillCreateForm({
        name,
        address: doctor?.street || hit.address || '',
        city: doctor?.city || hit.city || '',
        governorate: doctor?.governorate || '',
        landmark: doctor?.landmark || doctor?.clinicName || hit.clinicName || '',
        phone: '',
        latitude: doctor?.latitude ?? null,
        longitude: doctor?.longitude ?? null,
        brickId: doctor?.brick702Id || doctor?.brickId || null,
        brick148Id: doctor?.brick148Id || null,
        brick702Id: doctor?.brick702Id || null,
        brickName: doctor?.brickName || '',
        placeId: null,
        specialty1: doctor?.specialty1 || '',
        specialty2: doctor?.specialty2 || '',
        specialty3: doctor?.specialty3 || ''
      });
      this.createForm = {
        ...this.createForm,
        pinConfirmed: false
      };
      this.newAccountStep = 'createForm';
    } catch (error) {
      this.toast('Google Search profile failed', this.errorMessageFrom(error), 'error');
    } finally {
      this.isVezeetaLoading = false;
    }
  }

  handleCreateBlankAccount() {
    this.prefillCreateForm({
      name: this.masterSearchTerm || this.vezeetaSearchTerm || this.mapSearchTerm || '',
      address: '',
      phone: '',
      latitude: null,
      longitude: null,
      brickId: null,
      brickName: '',
      placeId: null
    });
    this.newAccountStep = 'createForm';
  }

  prefillCreateForm(place) {
    const name = place?.name || this.masterSearchTerm || '';
    const address = place?.address || '';
    const city = place?.city || this.cityFromAddress(address);
    const phone = place?.phone || '';
    const form = {
      name,
      firstName: '',
      lastName: '',
      phone,
      whatsappNumber: '',
      clinicPhone: '',
      email: '',
      specialty1: place?.specialty1 || '',
      specialty2: place?.specialty2 || '',
      specialty3: place?.specialty3 || '',
      pharmacyType: '',
      institutionType: '',
      street: address,
      city,
      country: 'Egypt',
      building: '',
      governorate: place?.governorate || this.governorateFromAddress(address),
      landmark: place?.landmark || '',
      website: place?.profileUrl || '',
      vezeetaFee: place?.fees || '',
      latitude: place?.latitude ?? null,
      longitude: place?.longitude ?? null,
      brickId: place?.brickId || '',
      brick148Id: place?.brick148Id || '',
      brick702Id: place?.brick702Id || place?.brickId || '',
      brickName: place?.brickName || '',
      placeId: place?.placeId || '',
      placeKind: place?.placeKind || '',
      isKol: place?.isKol === true,
      pinConfirmed: !!(place?.latitude && place?.longitude && address)
    };
    if (form.brick702Id && !form.brick148Id) {
      const brick702 = (this.wizardCreateOptions?.bricks702 || []).find(
        (brick) => String(brick.brickId) === String(form.brick702Id)
      );
      if (brick702?.parentBrickId) {
        form.brick148Id = brick702.parentBrickId;
      }
    }
    if (this.isPersonCreateType && name) {
      const parts = name.trim().split(/\s+/);
      form.firstName = parts[0] || '';
      form.lastName = parts.slice(1).join(' ') || parts[0] || '';
    }
    this.createForm = form;
    this.createError = null;
    this.phoneMapSuggestion = null;
    this.mapPrefillPhoneDigits = phoneDigits(phone);
    this.lastPhoneLookupDigits = this.mapPrefillPhoneDigits;
  }

  governorateFromAddress(address) {
    if (!address) {
      return '';
    }
    const haystack = String(address).toLowerCase();
    const match = (this.wizardCreateOptions?.governorateOptions || []).find((option) =>
      haystack.includes(String(option.value || '').toLowerCase())
    );
    return match?.value || '';
  }

  cityFromAddress(address) {
    if (!address) {
      return '';
    }
    const parts = String(address)
      .split(',')
      .map((part) => part.trim())
      .filter(Boolean);
    if (parts.length >= 2) {
      return parts[parts.length - 2];
    }
    return parts[0] || '';
  }

  handleCreateFieldChange(event) {
    const field = event.target.dataset.field;
    if (!field) {
      return;
    }

    const value = this.readInputValue(event);
    const next = {
      ...this.createForm,
      [field]: value
    };

    // If the user edits the address details, the existing pin confirmation is no longer reliable.
    if (['street', 'building', 'governorate', 'landmark'].includes(field)) {
      next.pinConfirmed = false;
      if (field === 'street') {
        next.city = this.cityFromAddress(value) || next.city;
      }
      this.scheduleCreateAddressMapLookup();
    }

    this.createForm = next;
  }

  handlePinConfirmedChange(event) {
    this.createForm = {
      ...this.createForm,
      pinConfirmed: event.target.checked === true || event.detail?.checked === true
    };
  }

  scheduleCreateAddressMapLookup() {
    if (this.createAddressLookupDebounce) {
      clearTimeout(this.createAddressLookupDebounce);
    }
    this.createAddressLookupDebounce = setTimeout(() => {
      this.createAddressLookupDebounce = null;
      this.runCreateAddressMapLookup();
    }, ADDRESS_LOOKUP_DEBOUNCE_MS);
  }

  buildCreateFormGeoFilter() {
    const brick148Id = this.createForm?.brick148Id || null;
    const brick702Id = this.createForm?.brick702Id || null;
    if (!brick148Id && !brick702Id) {
      return null;
    }
    return { brick148Id, brick702Id };
  }

  buildCreateFormAddressSearchTerm() {
    const street = (this.createForm?.street || '').trim();
    const building = (this.createForm?.building || '').trim();
    const landmark = (this.createForm?.landmark || '').trim();
    const city = (this.createForm?.city || '').trim();
    const governorate = (this.createForm?.governorate || '').trim();
    return [street, building, landmark, city, governorate].filter(Boolean).join(', ');
  }

  pickBestPlaceCandidate(places) {
    if (!Array.isArray(places) || places.length === 0) {
      return null;
    }
    return places
      .filter((p) => p?.latitude != null && p?.longitude != null)
      .sort((a, b) => {
        const ra = Number(a?.rating || a?.starCount || 0);
        const rb = Number(b?.rating || b?.starCount || 0);
        // Higher confidence is preferred; tie-breaker by provider ratingCount.
        const d = rb - ra;
        if (d !== 0) return d;
        return Number(b?.ratingCount || 0) - Number(a?.ratingCount || 0);
      })[0];
  }

  animateCreatePinRipple(leaflet, map, latLng) {
    if (!leaflet || !map || !latLng) {
      return;
    }
    if (this.createPinRippleRaf) {
      cancelAnimationFrame(this.createPinRippleRaf);
      this.createPinRippleRaf = null;
    }
    if (this.createPinRippleLayer) {
      try {
        map.removeLayer(this.createPinRippleLayer);
      } catch (e) {
        // ignore
      }
      this.createPinRippleLayer = null;
    }

    const start = typeof performance !== 'undefined' ? performance.now() : Date.now();
    const durationMs = 900;
    const circle = leaflet.circleMarker(latLng, {
      radius: 10,
      color: '#0176d3',
      weight: 2,
      opacity: 0.6,
      fillOpacity: 0
    });
    this.createPinRippleLayer = circle.addTo(map);

    const tick = (now) => {
      const t = Math.min(1, (now - start) / durationMs);
      const radius = 10 + t * 45;
      const opacity = 0.65 * (1 - t);
      circle.setRadius(radius);
      circle.setStyle({ opacity });
      if (t >= 1) {
        try {
          map.removeLayer(circle);
        } catch (e) {
          // ignore
        }
        if (this.createPinRippleLayer === circle) {
          this.createPinRippleLayer = null;
        }
        return;
      }
      this.createPinRippleRaf = requestAnimationFrame(tick);
    };

    this.createPinRippleRaf = requestAnimationFrame(tick);
  }

  async runCreateAddressMapLookup() {
    if (!this.isCreateFormStep || this.isSavingAccount || this.isGettingCurrentLocation) {
      return;
    }
    const street = (this.createForm?.street || '').trim();
    if (street.length < ADDRESS_LOOKUP_MIN_STREET_LEN) {
      return;
    }

    const requestToken = (this.createAddressLookupToken || 0) + 1;
    this.createAddressLookupToken = requestToken;
    const term = this.buildCreateFormAddressSearchTerm();
    const geoFilter = this.buildCreateFormGeoFilter();
    const recordTypeDeveloperName = this.selectedCreateRecordType?.developerName;
    if (!term || term.trim().length < 2) {
      return;
    }
    if (term === this.lastCreateAddressLookupKey) {
      return;
    }
    this.lastCreateAddressLookupKey = term;

    this.isCreateAddressLookingUp = true;
    try {
      await this.ensureWizardCreateMap();
      const result = await searchMapPlaces({
        searchTerm: term,
        recordTypeDeveloperName,
        geoFilter
      });
      // Ignore stale lookups (user kept typing).
      if (this.createAddressLookupToken !== requestToken) {
        return;
      }
      const places = unwrapMapPlaces(result);
      const best = this.pickBestPlaceCandidate(places);
      if (!best) {
        return;
      }

      const next = {
        ...this.createForm,
        street: this.createForm.street,
        pinConfirmed: false,
        latitude:
          best.latitude == null ? this.createForm.latitude : Number(Number(best.latitude).toFixed(6)),
        longitude:
          best.longitude == null ? this.createForm.longitude : Number(Number(best.longitude).toFixed(6)),
        placeId: best.placeId || this.createForm.placeId,
        placeKind: best.placeKind || this.createForm.placeKind,
        isKol: best.isKol === true,
        governorate: this.createForm.governorate
      };
      // Brick context can be inferred from the place match; keep user-chosen brick if missing.
      if (best.brick148Id) next.brick148Id = best.brick148Id;
      if (best.brick702Id) next.brick702Id = best.brick702Id;
      if (best.brickId && !next.brick148Id) next.brick148Id = best.brickId;
      if (best.brickId && !next.brick702Id) next.brick702Id = best.brickId;
      if (best.brickId && !next.brickId) next.brickId = best.brickId;

      // If we found a canonical address, keep the user-typed street as-is,
      // but try to update city (helps map biasing + dropdown consistency).
      if (best.address) {
        next.city = this.cityFromAddress(best.address) || next.city;
      }

      this.createForm = next;
    } catch (e) {
      // Silent failure: address typing should not block the wizard.
    } finally {
      if (this.createAddressLookupToken === requestToken) {
        this.isCreateAddressLookingUp = false;
      }
    }
  }

  get useMyLocationDisabled() {
    if (this.isSavingAccount || this.isGettingCurrentLocation) {
      return true;
    }
    return !(typeof navigator !== 'undefined' && navigator.geolocation);
  }

  async handleUseMyLocation() {
    if (this.useMyLocationDisabled) {
      return;
    }
    this.currentLocationError = null;
    this.isGettingCurrentLocation = true;
    try {
      const pos = await getCurrentPosition();
      const latitude = Number(pos.latitude.toFixed(6));
      const longitude = Number(pos.longitude.toFixed(6));

      // Moving the pin invalidates the user's confirmation.
      // User must confirm the detailed address + pin after they review/edit fields.
      this.createForm = {
        ...this.createForm,
        latitude,
        longitude,
        pinConfirmed: false,
        pinSource: 'gps'
      };

      // Ensure the map is mounted so the marker can be moved immediately.
      await this.ensureWizardCreateMap();
    } catch (error) {
      this.currentLocationError = this.errorMessageFrom(error);
      this.toast('Unable to get your location', this.currentLocationError, 'error');
    } finally {
      this.isGettingCurrentLocation = false;
    }
  }

  handleCreatePhoneChange(event) {
    this.handleCreateFieldChange(event);
    this.schedulePhoneMapLookup();
  }

  handleBrick148Change(event) {
    const brick148Id = this.readInputValue(event);
    const brick148 = (this.wizardCreateOptions?.bricks148 || []).find(
      (brick) => String(brick.brickId) === String(brick148Id)
    );
    const next = {
      ...this.createForm,
      brick148Id
    };
    if (brick148?.governorate && !this.createForm.governorate) {
      next.governorate = brick148.governorate;
    }
    const current702 = (this.wizardCreateOptions?.bricks702 || []).find(
      (brick) => String(brick.brickId) === String(this.createForm.brick702Id)
    );
    if (current702 && String(current702.parentBrickId || '') !== String(brick148Id)) {
      next.brick702Id = '';
      next.brickId = '';
    }
    this.createForm = next;
  }

  handleBrick702Change(event) {
    const brick702Id = this.readInputValue(event);
    const brick702 = (this.wizardCreateOptions?.bricks702 || []).find(
      (brick) => String(brick.brickId) === String(brick702Id)
    );
    const next = {
      ...this.createForm,
      brick702Id,
      brickId: brick702Id
    };
    if (brick702?.parentBrickId && !this.createForm.brick148Id) {
      next.brick148Id = brick702.parentBrickId;
    }
    if (brick702?.governorate && !this.createForm.governorate) {
      next.governorate = brick702.governorate;
    }
    this.createForm = next;
  }

  schedulePhoneMapLookup() {
    if (this.phoneLookupDebounce) {
      clearTimeout(this.phoneLookupDebounce);
    }
    this.phoneLookupDebounce = setTimeout(() => {
      this.phoneLookupDebounce = null;
      this.runPhoneMapLookup();
    }, PHONE_LOOKUP_DEBOUNCE_MS);
  }

  async runPhoneMapLookup() {
    const candidates = [
      this.createForm?.whatsappNumber,
      this.createForm?.phone,
      this.createForm?.clinicPhone
    ].filter((value) => looksLikePhone(value));
    const raw = candidates[candidates.length - 1];
    const digits = phoneDigits(raw);
    if (!digits || digits === this.lastPhoneLookupDigits || digits === this.mapPrefillPhoneDigits) {
      return;
    }
    this.lastPhoneLookupDigits = digits;
    this.isPhoneMapLookingUp = true;
    try {
      const result = await searchMapPlaces({
        searchTerm: raw,
        recordTypeDeveloperName: this.selectedCreateRecordType?.developerName,
        geoFilter: null
      });
      const match = unwrapMapPlaces(result).find((row) => row?.name);
      this.phoneMapSuggestion = match || null;
    } catch (error) {
      this.phoneMapSuggestion = null;
    } finally {
      this.isPhoneMapLookingUp = false;
    }
  }

  handleUsePhoneMapMatch() {
    const place = this.phoneMapSuggestion;
    if (!place) {
      return;
    }
    const next = { ...this.createForm };
    const mapName = (place.name || '').trim();
    if (mapName) {
      if (this.isPersonCreateType) {
        const parts = mapName.split(/\s+/);
        next.firstName = parts[0] || next.firstName;
        next.lastName = parts.slice(1).join(' ') || next.lastName || parts[0];
      } else {
        next.name = mapName;
      }
    }
    if (place.address) {
      next.street = place.address;
      next.city = this.cityFromAddress(place.address) || next.city;
      next.governorate = this.governorateFromAddress(place.address) || next.governorate;
    }
    if (place.latitude != null && place.longitude != null) {
      next.latitude = place.latitude;
      next.longitude = place.longitude;
    }
    if (place.brick148Id) {
      next.brick148Id = place.brick148Id;
    }
    if (place.brick702Id || place.brickId) {
      next.brick702Id = place.brick702Id || place.brickId;
      next.brickId = next.brick702Id;
    }
    if (place.placeId) {
      next.placeId = place.placeId;
    }
    if (place.phone && !next.phone) {
      next.phone = place.phone;
    }
    next.pinConfirmed = !!(next.street && next.latitude != null);
    next.pinSource = null;
    this.createForm = next;
    this.phoneMapSuggestion = null;
    this.mapPrefillPhoneDigits = phoneDigits(next.phone || next.whatsappNumber || next.clinicPhone);
    this.syncCreatePinMarker();
  }

  async saveWizardAccount(allowDuplicate = false) {
    if (this.isCreateFormInvalid || this.isSavingAccount) {
      return;
    }
    this.isSavingAccount = true;
    this.createError = null;
    let retryAsDuplicate = false;
    try {
      const vezeetaProfileUrl = this.createForm.website;
      const result = await createAccountFromWizard({
        input: {
          recordTypeId: this.selectedCreateRecordTypeId,
          name: this.createForm.name,
          firstName: this.createForm.firstName,
          lastName: this.createForm.lastName,
          phone: this.createForm.phone,
          whatsappNumber: this.createForm.whatsappNumber,
          clinicPhone: this.createForm.clinicPhone,
          email: this.createForm.email,
          specialty1: this.createForm.specialty1,
          specialty2: this.createForm.specialty2,
          specialty3: this.createForm.specialty3,
          pharmacyType: this.createForm.pharmacyType,
          institutionType: this.createForm.institutionType,
          street: this.createForm.street,
          city: this.createForm.city,
          country: this.createForm.country,
          building: this.createForm.building,
          governorate: this.createForm.governorate,
          landmark: this.createForm.landmark,
          latitude: this.createForm.latitude,
          longitude: this.createForm.longitude,
          brickId: this.createForm.brick702Id || this.createForm.brickId || null,
          brick148Id: this.createForm.brick148Id || null,
          brick702Id: this.createForm.brick702Id || null,
          placeId: this.createForm.placeId,
          website: this.createForm.website,
          allowDuplicate: allowDuplicate === true
        }
      });
      const accountId = result?.accountId;
      if (accountId && vezeetaProfileUrl) {
        try {
          await saveVezeetaProfileUrl({ accountId, profileUrl: vezeetaProfileUrl });
        } catch (stampError) {
          // The account is already saved. The profile link is also sent on the create input.
        }
      }
      this.handleCloseNewAccountModal();
      this.toast(
        'Submitted for approval',
        result?.message || 'Account submitted for manager approval.',
        'success'
      );
      if (accountId) {
        this.navigateToAccount(accountId);
      }
      this.reloadData(true);
    } catch (error) {
      const message = this.errorMessageFrom(error);
      if (allowDuplicate !== true && String(message || '').startsWith(DUPLICATE_WARNING_PREFIX)) {
        retryAsDuplicate = await LightningConfirm.open({
          label: 'Possible duplicate account',
          message,
          theme: 'warning'
        });
        if (!retryAsDuplicate) {
          this.createError = message;
        }
      } else {
        this.createError = message;
      }
    } finally {
      this.isSavingAccount = false;
    }
    if (retryAsDuplicate) {
      await this.saveWizardAccount(true);
    }
  }

  resetNewAccountWizard() {
    this.newAccountStep = 'recordType';
    this.selectedCreateRecordTypeId = null;
    this.masterSearchTerm = '';
    this.masterBrick148Id = FILTER_ALL;
    this.masterBrick702Id = FILTER_ALL;
    this.masterSpecialtyFilter = '';
    this.masterSpecialtyQuery = '';
    this.showMasterSpecialtyMenu = false;
    this.masterSearchResults = [];
    this.cognitiveResults = [];
    this.isMasterSearching = false;
    this.masterSearchRan = false;
    this.selectedMasterAccountId = null;
    this.mapSearchTerm = '';
    this.mapZoneId = '';
    this.mapBrick148Id = '';
    this.mapBrick702Id = '';
    this.mapArea = '';
    this.mapSearchResults = [];
    this.mapSearchBias = null;
    this.isMapSearching = false;
    this.mapSearchRan = false;
    this.selectedMapPlaceId = null;
    this.lookupSource = 'maps';
    this.vezeetaSearchTerm = '';
    this.vezeetaResults = [];
    this.vezeetaSearchRan = false;
    this.isVezeetaSearching = false;
    this.isVezeetaLoading = false;
    this.selectedVezeetaUrl = null;
    if (this.vezeetaSearchDebounce) {
      clearTimeout(this.vezeetaSearchDebounce);
      this.vezeetaSearchDebounce = null;
    }
    this.destroyWizardMap();

    if (this.createAddressLookupDebounce) {
      clearTimeout(this.createAddressLookupDebounce);
      this.createAddressLookupDebounce = null;
    }
    this.createAddressLookupToken = 0;
    this.lastCreateAddressLookupKey = '';
    this.isCreateAddressLookingUp = false;
    this.createPinRippleLayer = null;
    this._wizardPinLatLngKey = '';
    this.createForm = {};
    this.isSavingAccount = false;
    this.createError = null;
    this.phoneMapSuggestion = null;
    this.isPhoneMapLookingUp = false;
    this.mapPrefillPhoneDigits = '';
    this.lastPhoneLookupDigits = '';
    if (this.phoneLookupDebounce) {
      clearTimeout(this.phoneLookupDebounce);
      this.phoneLookupDebounce = null;
    }
  }

  errorMessageFrom(error) {
    return (
      error?.body?.message ||
      error?.message ||
      (Array.isArray(error?.body) ? error.body[0]?.message : null) ||
      'Something went wrong.'
    );
  }

  toast(title, message, variant) {
    this.dispatchEvent(new ShowToastEvent({ title, message, variant }));
  }

  navigateToNewAccount(recordTypeId) {
    const pageRef = {
      type: 'standard__objectPage',
      attributes: {
        objectApiName: 'Account',
        actionName: 'new'
      },
      state: {
        nooverride: '1',
        useRecordTypeCheck: '1'
      }
    };
    if (recordTypeId) {
      pageRef.state.recordTypeId = recordTypeId;
    }
    this[NavigationMixin.Navigate](pageRef);
  }

  handleShowAllAccounts() {
    this.loadPlannerCollections();
    this.listViewMode = LIST_MODE_ALL;
    this.selectedCollectionId = null;
    this.reloadData(true);
    this.closeOverlayDrawer();
  }

  handleSelectCollection(event) {
    this.loadPlannerCollections();
    const collectionId = event.currentTarget.dataset.collectionId;
    const collection = (this.accountCollections || []).find((item) => item.id === collectionId);
    if (!collection) {
      return;
    }
    this.selectedCollectionId = collectionId;
    this.listViewMode = LIST_MODE_COLLECTION;
    this.reloadData(true);
    this.closeOverlayDrawer();
  }

  handlePreviousPage() {
    if (!this.hasPreviousPage || this.isLoading) {
      return;
    }
    this.currentPage -= 1;
    this.loadPage();
  }

  handleNextPage() {
    if (!this.hasNextPage || this.isLoading) {
      return;
    }
    this.currentPage += 1;
    this.loadPage();
  }

  handleMapPreviousPage() {
    if (!this.mapHasPreviousPage || this.isLoading) {
      return;
    }
    this.mapCurrentPage -= 1;
    this.refreshMapView();
  }

  handleMapNextPage() {
    if (!this.mapHasNextPage || this.isLoading) {
      return;
    }
    this.mapCurrentPage += 1;
    this.refreshMapView();
  }

  handleToggleFilters() {
    if (!this.isListView) {
      this.viewMode = 'list';
      this.sidebarOpen = true;
      return;
    }
    if (this.isCompactView) {
      this.sidebarOpen = !this.sidebarOpen;
      return;
    }
    this.sidebarPanel = this.sidebarPanel === 'filters' ? 'lists' : 'filters';
    this.sidebarOpen = true;
  }

  handleToggleLists() {
    if (!this.isListView) {
      this.viewMode = 'list';
      this.loadPlannerCollections();
      this.sidebarPanel = 'lists';
      this.sidebarOpen = true;
      return;
    }
    if (this.isCompactView && this.sidebarOpen && this.sidebarPanel === 'lists') {
      this.sidebarOpen = false;
      return;
    }
    this.loadPlannerCollections();
    this.sidebarPanel = 'lists';
    this.sidebarOpen = true;
  }

  handleToggleSidebar() {
    this.sidebarOpen = !this.sidebarOpen;
  }

  handleCloseSidebar() {
    this.sidebarOpen = false;
  }

  handleShowListsPanel() {
    this.loadPlannerCollections();
    this.sidebarPanel = 'lists';
    this.sidebarOpen = true;
  }

  handleShowFiltersPanel() {
    this.sidebarPanel = 'filters';
    this.sidebarOpen = true;
  }

  handleListNavSelect(event) {
    this.listViewMode = LIST_MODE_ALL;
    this.selectedCollectionId = null;
    this.scope = event.currentTarget.dataset.value;
    this.reloadData(true);
    this.closeOverlayDrawer();
  }

  handlePendingApprovalNav() {
    this.listViewMode = LIST_MODE_NURTURING;
    this.nurtureLane = NURTURE_LANE_ALL;
    this.approvalSelectedById = {};
    this.selectedCollectionId = null;
    this.scope = SCOPE_BOTH;
    this.reloadData(true);
    this.closeOverlayDrawer();
  }

  handleNurtureLane(event) {
    const lane = event.currentTarget?.dataset?.lane;
    if (!lane || lane === this.nurtureLane) {
      return;
    }
    this.nurtureLane = lane;
    this.approvalSelectedById = {};
    this.reloadData(true);
  }

  handleApprovalSelectionChange(event) {
    const detail = event.detail || {};
    if (detail.all) {
      const next = {};
      if (detail.selected) {
        this.actionableRows.forEach((row) => {
          next[row.accountId] = true;
        });
      }
      this.approvalSelectedById = next;
      return;
    }
    const accountId = detail.accountId;
    if (!accountId) {
      return;
    }
    const next = { ...this.approvalSelectedById };
    if (detail.selected) {
      next[accountId] = true;
    } else {
      delete next[accountId];
    }
    this.approvalSelectedById = next;
  }

  handleMassApprove() {
    void this.commitMassApprove(this.selectedActionableIds);
  }

  handleMassReject() {
    const accountIds = this.selectedActionableIds;
    if (!accountIds.length || this.isSavingApproval) {
      return;
    }
    const missing = accountIds.filter((accountId) => !(this.rejectionReasonByAccountId[accountId] || '').trim());
    if (!missing.length) {
      void this.commitMassReject(
        accountIds.map((accountId) => ({
          accountId,
          rejectionReason: this.rejectionReasonByAccountId[accountId].trim()
        }))
      );
      return;
    }
    this.massRejectMissing = false;
    this.showMassRejectModal = true;
  }

  handleMassRejectInput() {
    if (this.massRejectMissing) {
      this.massRejectMissing = false;
    }
  }

  handleCloseMassReject() {
    if (this.isSavingApproval) {
      return;
    }
    this.showMassRejectModal = false;
    this.massRejectMissing = false;
  }

  stopMassRejectClick(event) {
    event.stopPropagation();
  }

  handleConfirmMassReject() {
    const field = this.template.querySelector('[data-mass-reject-reason]');
    const reason = (field?.value || '').trim();
    const accountIds = this.selectedActionableIds;
    const jobs = accountIds.map((accountId) => ({
      accountId,
      rejectionReason: (this.rejectionReasonByAccountId[accountId] || '').trim() || reason
    }));
    if (jobs.some((job) => !job.rejectionReason)) {
      this.massRejectMissing = true;
      field?.focus();
      return;
    }
    void this.commitMassReject(jobs);
  }

  async commitMassApprove(accountIds) {
    const ids = [...accountIds];
    if (!ids.length || this.isSavingApproval) {
      return;
    }
    this.isSavingApproval = true;
    let done = 0;
    try {
      for (const accountId of ids) {
        // eslint-disable-next-line no-await-in-loop
        await approveAccountSubmissionApex({ accountId });
        done += 1;
        this.clearApprovalSelection(accountId);
      }
      this.toast(
        'Sent to SFE',
        done === 1
          ? 'You approved this account. It is waiting on SFE.'
          : `${done} accounts are waiting on SFE.`,
        'success'
      );
      this.reloadData(false);
    } catch (error) {
      this.toast('Approve failed', this.errorMessageFrom(error), 'error');
      if (done) {
        this.reloadData(false);
      }
    } finally {
      this.isSavingApproval = false;
    }
  }

  async commitMassReject(jobs) {
    const queue = [...jobs];
    if (!queue.length || this.isSavingApproval) {
      return;
    }
    this.isSavingApproval = true;
    let done = 0;
    try {
      for (const job of queue) {
        // eslint-disable-next-line no-await-in-loop
        await rejectAccountSubmissionApex({
          accountId: job.accountId,
          rejectionReason: job.rejectionReason
        });
        done += 1;
        this.clearApprovalSelection(job.accountId);
      }
      this.showMassRejectModal = false;
      this.massRejectMissing = false;
      this.toast(
        'Rejected',
        done === 1
          ? 'Account returned to Draft for the rep.'
          : `${done} accounts returned to Draft for the rep.`,
        'success'
      );
      this.reloadData(false);
    } catch (error) {
      this.toast('Reject failed', this.errorMessageFrom(error), 'error');
      if (done) {
        this.reloadData(false);
      }
    } finally {
      this.isSavingApproval = false;
    }
  }

  clearApprovalSelection(accountId) {
    if (!this.approvalSelectedById[accountId]) {
      return;
    }
    const next = { ...this.approvalSelectedById };
    delete next[accountId];
    this.approvalSelectedById = next;
    if (this.rejectionReasonByAccountId[accountId]) {
      const reasons = { ...this.rejectionReasonByAccountId };
      delete reasons[accountId];
      this.rejectionReasonByAccountId = reasons;
    }
  }

  handleApprovalRejectionChange(event) {
    const accountId = event.detail?.accountId || event.target?.dataset?.accountId;
    const value = event.detail?.value ?? event.detail?.value;
    if (!accountId) {
      return;
    }
    this.rejectionReasonByAccountId = {
      ...this.rejectionReasonByAccountId,
      [accountId]: value
    };
  }

  handleTypeNavSelect(event) {
    this.recordType = event.currentTarget.dataset.value;
    this.reloadData(true);
    this.closeOverlayDrawer();
  }

  handleMapListSelect(event) {
    const accountId = event.currentTarget.dataset.accountId;
    if (!accountId) {
      return;
    }
    this.selectedAccountId = accountId;
    this.applyPinSelection();
    const row = (this.mapRows || []).find((item) => item.accountId === accountId);
    if (row?.latitude != null && row?.longitude != null) {
      this.flyToAccount(row.latitude, row.longitude, accountId);
    }
    this.scrollMapListItemIntoView(accountId);
  }

  handleMapListViewAccount(event) {
    event.stopPropagation();
    const accountId = event.currentTarget.dataset.accountId;
    if (accountId) {
      this.navigateToAccount(accountId);
    }
  }

  handleDuplicateChange() {
    this.reloadData(true);
  }

  handleOceRowAction(event) {
    const { accountId, action } = event.detail;
    if (action === 'plan' || action === 'rtd') {
      this.navigateToPlanner(accountId);
      if (action === 'rtd') {
        this.dispatchEvent(
          new ShowToastEvent({
            title: 'Schedule RTD meeting',
            message: 'Use + in the planner to add an RTD or speaker meeting for this account.',
            variant: 'info'
          })
        );
      }
      return;
    }
    if (action === 'kol') {
      this.toggleKol(accountId);
      return;
    }
    if (action === 'approve') {
      if (this.isSavingApproval) {
        return;
      }
      void this.handleApproveAccountRow(accountId);
      return;
    }
    if (action === 'reject') {
      if (this.isSavingApproval) {
        return;
      }
      void this.handleRejectAccountRow(accountId);
      return;
    }
    if (accountId) {
      this.navigateToAccount(accountId);
    }
  }

  async handleApproveAccountRow(accountId) {
    if (!accountId) {
      return;
    }
    try {
      await approveAccountSubmissionApex({ accountId });
      this.toast('Sent to SFE', 'You approved this account. It is waiting on SFE.', 'success');
      this.reloadData(true);
    } catch (error) {
      this.toast('Approve failed', this.errorMessageFrom(error), 'error');
    }
  }

  async handleRejectAccountRow(accountId) {
    if (!accountId) {
      return;
    }
    const rejectionReason = (this.rejectionReasonByAccountId[accountId] || '').trim();
    if (!rejectionReason) {
      this.toast('Rejection reason required', 'Enter a reason before rejecting.', 'error');
      return;
    }
    try {
      await rejectAccountSubmissionApex({ accountId, rejectionReason });
      this.toast('Rejected', 'Account returned to Draft for the rep.', 'success');
      this.reloadData(true);
    } catch (error) {
      this.toast('Reject failed', this.errorMessageFrom(error), 'error');
    }
  }

  async toggleKol(accountId) {
    if (!accountId) {
      return;
    }
    const row = (this.rows || []).find((item) => item.accountId === accountId);
    if (row?.kolBusy) {
      return;
    }
    const previousIsKol = row?.isKol === true;
    const nextIsKol = !previousIsKol;
    this.rows = (this.rows || []).map((item) =>
      item.accountId === accountId
        ? {
            ...item,
            isKol: nextIsKol,
            isKolLabel: nextIsKol ? 'Yes' : 'No',
            kolBusy: true
          }
        : item
    );
    try {
      const result = await setAccountKol({
        accountId,
        isKol: nextIsKol
      });
      const isKol = result?.isKol === true;
      this.rows = (this.rows || []).map((item) =>
        item.accountId === accountId
          ? { ...item, isKol, isKolLabel: isKol ? 'Yes' : 'No', kolBusy: false }
          : item
      );
    } catch (error) {
      this.rows = (this.rows || []).map((item) =>
        item.accountId === accountId
          ? {
              ...item,
              isKol: previousIsKol,
              isKolLabel: previousIsKol ? 'Yes' : 'No',
              kolBusy: false
            }
          : item
      );
      this.dispatchEvent(
        new ShowToastEvent({
          title: 'Unable to update KOL',
          message: this.reduceError(error) || 'Could not update KOL for this territory.',
          variant: 'error'
        })
      );
    }
  }

  async waitForMapContainer() {
    for (let attempt = 0; attempt < 30; attempt += 1) {
      const container = this.template.querySelector('.accounts-map');
      if (container) {
        return container;
      }
      await new Promise((resolve) => requestAnimationFrame(resolve));
    }
    return null;
  }

  async ensureMapReady(leaflet, token) {
    const container = await this.waitForMapContainer();
    if (!container || token !== this.mapRenderToken) {
      return null;
    }
    this._leaflet = leaflet;
    const live = this.mapInstance?.getContainer?.();
    if (live && container.contains(live)) {
      this.injectAccountsMapChrome(this.mapInstance);
      return this.mapInstance;
    }
    if (this.mapInstance) {
      this.destroyMap();
    }
    container.innerHTML = '';
    const mapDiv = document.createElement('div');
    mapDiv.style.height = '100%';
    mapDiv.style.width = '100%';
    container.appendChild(mapDiv);
    const map = leaflet.map(mapDiv, { zoomControl: true, scrollWheelZoom: true });
    addOsmTileLayer(map, leaflet);
    this.mapInstance = map;
    this.injectAccountsMapChrome(map);
    this.observeAccountsMap(map);
    return map;
  }

  observeAccountsMap(map) {
    const pane = map?.getContainer?.();
    if (!pane || typeof ResizeObserver === 'undefined') {
      return;
    }
    if (!this._mapResizeObserver) {
      this._mapResizeObserver = new ResizeObserver(() => {
        this.mapInstance?.invalidateSize();
      });
    }
    this._mapResizeObserver.observe(pane);
  }

  injectAccountsMapChrome(map) {
    const pane = map?.getContainer?.();
    if (!pane || pane.querySelector('style[data-accounts-map-chrome]')) {
      return;
    }
    const style = document.createElement('style');
    style.setAttribute('data-accounts-map-chrome', 'true');
    style.textContent = ACCOUNTS_MAP_CHROME_CSS;
    pane.appendChild(style);
  }

  buildRiskPinIcon(leaflet, row) {
    const themeKind = resolveAccountThemeKind(
      row.recordTypeDeveloperName,
      row.recordTypeName
    );
    const pinKind = themeKind === 'account' ? 'hcp' : themeKind;
    const themeColors = { pharmacy: '#176935', hco: '#e0a800', hcp: '#3f7de5' };
    const border = themeColors[pinKind] || themeColors.hcp;
    const glyph = accountTypeIconUrl(pinKind);
    const risk = RISK_PIN_COLORS[row.agentforceRisk] || RISK_PIN_COLORS.Low;
    const selected = row.accountId === this.selectedAccountId;
    const safeName = escapeMapHtml(row.accountName || '');
    const mark = glyph
      ? `<img src="${glyph}" alt="" style="width:16px;height:16px;object-fit:contain;display:block;" />`
      : '';
    const halo = selected
      ? `0 0 0 4px ${border}33, 0 6px 14px rgba(3,45,96,0.35)`
      : '0 2px 6px rgba(3,45,96,0.28)';
    const scale = selected ? 'transform:scale(1.12);' : '';
    return leaflet.divIcon({
      className: 'acct-map-pin',
      html:
        `<div style="position:relative;width:34px;height:34px;border-radius:50%;background:#fff;border:2.5px solid ${border};box-shadow:${halo};display:flex;align-items:center;justify-content:center;${scale}" title="${safeName}">` +
        mark +
        `<span style="position:absolute;right:-2px;bottom:-2px;width:11px;height:11px;border-radius:50%;background:${risk};border:2px solid #fff;box-sizing:border-box;"></span>` +
        '</div>',
      iconSize: [34, 34],
      iconAnchor: [17, 17],
      popupAnchor: [0, -18]
    });
  }

  async drawMapMarkers(points, token) {
    const leaflet = await ensureLeaflet(this, LEAFLET);
    if (token !== this.mapRenderToken) {
      return;
    }
    const map = await this.ensureMapReady(leaflet, token);
    if (!map) {
      return;
    }
    this.clearMarkers();
    const bounds = [];
    this.markersByAccountId = {};
    (points || []).forEach((row) => {
      if (row.latitude == null || row.longitude == null) {
        return;
      }
      const latLng = [Number(row.latitude), Number(row.longitude)];
      bounds.push(latLng);
      const icon = this.buildRiskPinIcon(leaflet, row);
      const marker = leaflet
        .marker(latLng, { icon, riseOnHover: true })
        .addTo(map)
        .bindPopup(this.buildPopupHtml(row), { closeButton: true, autoPanPadding: [24, 24] });
      marker.on('click', () => {
        this.selectedAccountId = row.accountId;
        this.applyPinSelection();
        this.scrollMapListItemIntoView(row.accountId);
      });
      marker.on('popupopen', (event) => {
        const button = event.popup?.getElement()?.querySelector('.acct-popup-open');
        if (!button || button.dataset.bound === '1') {
          return;
        }
        button.dataset.bound = '1';
        button.addEventListener('click', () => this.navigateToAccount(row.accountId));
      });
      this.mapMarkers.push(marker);
      this.markersByAccountId[row.accountId] = marker;
    });
    if (bounds.length === 1) {
      map.setView(bounds[0], 14);
    } else if (bounds.length) {
      map.fitBounds(bounds, { padding: [48, 48], maxZoom: 14 });
    } else {
      map.setView([30.0444, 31.2357], 6);
    }
    setTimeout(() => map.invalidateSize(), 80);
  }

  applyPinSelection() {
    const leaflet = this._leaflet;
    if (!leaflet || !this.markersByAccountId) {
      return;
    }
    Object.keys(this.markersByAccountId).forEach((accountId) => {
      const row = (this.mapRows || []).find((item) => item.accountId === accountId);
      const marker = this.markersByAccountId[accountId];
      if (row && marker) {
        marker.setIcon(this.buildRiskPinIcon(leaflet, row));
      }
    });
  }

  flyToAccount(latitude, longitude, accountId) {
    if (!this.mapInstance) {
      return;
    }
    const lat = Number(latitude);
    const lng = Number(longitude);
    this.mapInstance.flyTo([lat, lng], 15, { duration: 0.8 });
    const marker = this.markersByAccountId[accountId];
    if (marker) {
      setTimeout(() => marker.openPopup(), 400);
    }
  }

  scrollMapListItemIntoView(accountId) {
    this._scrollMapAccountId = accountId;
    const listItem = this.template.querySelector(
      `.map-account-item[data-account-id="${accountId}"]`
    );
    if (listItem) {
      listItem.scrollIntoView({ block: 'nearest', behavior: 'smooth' });
    }
  }

  buildPopupHtml(row) {
    const hasTarget = row.targetVisits != null;
    const visits = hasTarget
      ? `${row.actualVisits || 0}/${row.targetVisits}`
      : `${row.actualVisits || 0} (no target)`;
    const place = [row.accountSubtype || row.recordTypeName, row.city].filter(Boolean).join(' · ');
    const plan =
      row.planCycleLabel === 'In' ? 'In plan' : row.planCycleLabel === 'Out' ? 'Out of plan' : '';
    const risk = row.agentforceRisk || 'Low';
    const riskColor = RISK_PIN_COLORS[risk] || RISK_PIN_COLORS.Low;
    const score =
      row.agentforceScore != null ? Number(row.agentforceScore).toFixed(1) : '—';
    return `<div class="acct-popup">
      <div class="acct-popup-name">${escapeMapHtml(row.accountName || 'Account')}</div>
      <div class="acct-popup-place">${escapeMapHtml(place || '—')}</div>
      <div class="acct-popup-row">
        <span class="acct-popup-chip">${escapeMapHtml(row.classification || '—')}</span>
        <span class="acct-popup-risk" style="color:${riskColor}">${escapeMapHtml(risk)} pace</span>
      </div>
      <div class="acct-popup-meta">${escapeMapHtml(plan)}<br/>Visits ${escapeMapHtml(visits)} · ${escapeMapHtml(row.paceStatusLabel || '—')}<br/>Score ${escapeMapHtml(score)}</div>
      <button type="button" class="acct-popup-open">Open account</button>
    </div>`;
  }

  navigateToAccount(accountId) {
    this[NavigationMixin.Navigate]({
      type: 'standard__recordPage',
      attributes: {
        recordId: accountId,
        objectApiName: 'Account',
        actionName: 'view'
      }
    });
  }

  navigateToPlanner(accountId) {
    const state = accountId ? { c__accountId: accountId, accountId } : undefined;
    this[NavigationMixin.Navigate]({
      type: 'standard__navItemPage',
      attributes: {
        apiName: 'Field_Rep_Planner'
      },
      state
    });
    // Offline PWA: NavigationMixin may no-op for nav items — also broadcast.
    if (typeof window !== 'undefined') {
      window.dispatchEvent(
        new CustomEvent('zeta-navigate-tab', {
          detail: {
            apiName: 'Field_Rep_Planner',
            accountId: accountId || null
          }
        })
      );
    }
  }

  get displayRowsWithMatch() {
    const term = (this.searchTerm || '').trim().toLowerCase();
    return (this.rows || []).map((row) => {
      const approvalSelected = this.approvalSelectedById[row.accountId] === true;
      if (!term) {
        return { ...row, matchReason: row.matchReason || '', approvalSelected };
      }
      const reasons = [];
      if ((row.accountName || '').toLowerCase().includes(term)) reasons.push('Name');
      if ((row.specialtyDisplay || row.specialty || '').toLowerCase().includes(term)) {
        reasons.push('Specialty');
      }
      if ((row.brickName || '').toLowerCase().includes(term)) reasons.push('Brick');
      if ((row.city || '').toLowerCase().includes(term)) reasons.push('City');
      if ((row.classification || '').toLowerCase().includes(term)) reasons.push('Class');
      return {
        ...row,
        approvalSelected,
        matchReason: reasons.length ? `Matched: ${reasons.join(' · ')}` : row.matchReason || ''
      };
    });
  }

  clearMarkers() {
    if (!this.mapMarkers?.length || !this.mapInstance) {
      this.mapMarkers = [];
      this.markersByAccountId = {};
      return;
    }
    this.mapMarkers.forEach((marker) => this.mapInstance.removeLayer(marker));
    this.mapMarkers = [];
    this.markersByAccountId = {};
  }

  destroyMap() {
    this.clearMarkers();
    if (this._mapResizeObserver) {
      this._mapResizeObserver.disconnect();
    }
    if (this.mapInstance) {
      this.mapInstance.remove();
      this.mapInstance = null;
    }
  }

  selectWizardMapPlace(placeId, flyTo) {
    if (!placeId) {
      return;
    }
    this.selectedMapPlaceId = String(placeId);
    if (flyTo) {
      this.flyWizardMapToSelection();
    }
    this.scrollWizardPlaceIntoView(this.selectedMapPlaceId);
  }

  flyWizardMapToSelection() {
    const marker = this.wizardMapMarkersByPlaceId[String(this.selectedMapPlaceId || '')];
    if (!marker || !this.wizardMapInstance) {
      return;
    }
    this.wizardMapInstance.flyTo(marker.getLatLng(), 15, { duration: 0.45 });
  }

  scrollWizardPlaceIntoView(placeId) {
    const card = this.template.querySelector(`[data-place-id="${placeId}"]`);
    if (card) {
      card.scrollIntoView({ block: 'nearest', behavior: 'smooth' });
    }
  }

  async ensureWizardSearchMap() {
    if (this.wizardMapSyncing) {
      this.wizardMapPending = true;
      return;
    }
    this.wizardMapSyncing = true;
    try {
      const leaflet = await ensureLeaflet(this, LEAFLET);
      if (!this.showNewAccountModal || !this.isMapSearchStep) {
        return;
      }
      const map = await this.ensureWizardMapReady(leaflet, '.wizard-search-map');
      if (!map) {
        return;
      }
      this.drawWizardSearchMarkers(leaflet, map);
    } finally {
      this.wizardMapSyncing = false;
      if (this.wizardMapPending) {
        this.wizardMapPending = false;
        this.ensureWizardSearchMap();
      }
    }
  }

  async ensureWizardCreateMap() {
    if (this.wizardMapSyncing) {
      this.wizardMapPending = true;
      return;
    }
    this.wizardMapSyncing = true;
    try {
      const leaflet = await ensureLeaflet(this, LEAFLET);
      if (!this.showNewAccountModal || !this.isCreateFormStep) {
        return;
      }
      const map = await this.ensureWizardMapReady(leaflet, '.wizard-create-map');
      if (!map) {
        return;
      }
      this.syncCreatePinMarker(leaflet, map);
    } finally {
      this.wizardMapSyncing = false;
      if (this.wizardMapPending && this.isCreateFormStep) {
        this.wizardMapPending = false;
        this.ensureWizardCreateMap();
      } else {
        this.wizardMapPending = false;
      }
    }
  }

  async ensureWizardMapReady(leaflet, selector) {
    const container = this.template.querySelector(selector);
    if (!container) {
      return null;
    }
    if (this.wizardMapInstance) {
      setTimeout(() => this.wizardMapInstance?.invalidateSize(), 80);
      return this.wizardMapInstance;
    }
    container.innerHTML = '';
    const mapDiv = document.createElement('div');
    mapDiv.style.height = '100%';
    mapDiv.style.width = '100%';
    container.appendChild(mapDiv);
    const map = leaflet.map(mapDiv, { zoomControl: true, scrollWheelZoom: true });
    addOsmTileLayer(map, leaflet);
    map.setView(EGYPT_MAP_CENTER, 6);
    this.wizardMapInstance = map;
    this.wizardMapDrawnKey = null;
    map.on('click', (event) => {
      if (!this.isCreateFormStep || !event?.latlng) {
        return;
      }
      this.setCreatePin(event.latlng.lat, event.latlng.lng, true);
    });
    setTimeout(() => map.invalidateSize(), 120);
    return map;
  }

  syncCreatePinMarker(leaflet, map) {
    const target = map || this.wizardMapInstance;
    if (!target) {
      return;
    }
    const lat = this.createForm?.latitude;
    const lng = this.createForm?.longitude;
    if (lat == null || lng == null) {
      if (this.createPinMarker) {
        target.removeLayer(this.createPinMarker);
        this.createPinMarker = null;
      }
      if (this.createPinRippleLayer) {
        try {
          target.removeLayer(this.createPinRippleLayer);
        } catch (e) {
          // ignore
        }
        this.createPinRippleLayer = null;
      }
      if (this.createPinRippleRaf) {
        cancelAnimationFrame(this.createPinRippleRaf);
        this.createPinRippleRaf = null;
      }
      this._wizardPinLatLngKey = '';
      return;
    }

    const latNum = Number(lat);
    const lngNum = Number(lng);
    const latLng = [latNum, lngNum];
    const pinKey = `${latNum.toFixed(6)},${lngNum.toFixed(6)}`;
    const zoom = Math.max(target.getZoom() || 6, 14);
    const pinChanged = pinKey !== this._wizardPinLatLngKey;
    this._wizardPinLatLngKey = pinKey;

    const isGpsPin = this.createForm?.pinSource === 'gps';
    const icon = leaflet
      ? isGpsPin
        ? this.buildGpsPinIcon(leaflet)
        : this.buildWizardPlaceIcon(
            leaflet,
            true,
            this.createForm?.placeKind,
            this.createForm?.isKol === true
          )
      : null;

    if (this.createPinMarker) {
      this.createPinMarker.setLatLng(latLng);
      if (icon) {
        this.createPinMarker.setIcon(icon);
      }
    } else if (leaflet) {
      this.createPinMarker = leaflet
        .marker(latLng, {
          draggable: true,
          icon
        })
        .addTo(target);
      this.createPinMarker.on('dragend', (event) => {
        const pos = event.target.getLatLng();
        this.setCreatePin(pos.lat, pos.lng, false);
      });
    } else {
      this.ensureWizardCreateMap();
      return;
    }

    // Only animate when the pin actually changes.
    if (pinChanged) {
      if (typeof target.flyTo === 'function') {
        target.flyTo(latLng, zoom, { duration: 0.7 });
      } else {
        target.setView(latLng, zoom);
      }
      this.animateCreatePinRipple(leaflet, target, latLng);
    }
    setTimeout(() => target.invalidateSize(), 80);
  }

  setCreatePin(lat, lng, confirm) {
    this.createForm = {
      ...this.createForm,
      latitude: Number(lat.toFixed(6)),
      longitude: Number(lng.toFixed(6)),
      pinSource: null,
      // Pin moved => confirmation should be re-checked by the user.
      pinConfirmed: confirm ? true : false
    };
  }

  drawWizardSearchMarkers(leaflet, map) {
    const results = this.mapSearchResults || [];
    const selected = this.selectedMapPlaceId ? String(this.selectedMapPlaceId) : '';
    const biasKey = this.mapSearchBias
      ? `${this.mapSearchBias.centerLat},${this.mapSearchBias.centerLng},${this.mapSearchBias.radiusMeters}`
      : 'nobias';
    const markerKey = `${selected}|${results
      .map((row) => `${row.placeId}:${row.placeKind || ''}:${row.isKol ? 'kol' : ''}`)
      .join(',')}|${this.wizardMapShouldFit ? 'fit' : 'keep'}|${biasKey}`;
    if (markerKey === this.wizardMapDrawnKey) {
      return;
    }
    this.clearWizardMapMarkers();
    const bounds = [];
    results.forEach((row) => {
      if (row.latitude == null || row.longitude == null || !row.placeId) {
        return;
      }
      const id = String(row.placeId);
      const latLng = [Number(row.latitude), Number(row.longitude)];
      bounds.push(latLng);
      const isSelected = id === selected;
      const marker = leaflet
        .marker(latLng, {
          icon: this.buildWizardPlaceIcon(leaflet, isSelected, row.placeKind, row.isKol === true),
          zIndexOffset: isSelected ? 1000 : 0
        })
        .addTo(map);
      marker.on('click', () => {
        this.selectWizardMapPlace(id, false);
      });
      this.wizardMapMarkers.push(marker);
      this.wizardMapMarkersByPlaceId[id] = marker;
    });
    if (this.wizardMapShouldFit && bounds.length) {
      map.fitBounds(bounds, { padding: [28, 28], maxZoom: 14 });
      this.wizardMapShouldFit = false;
    } else if (this.wizardMapShouldFit && this.mapSearchBias?.centerLat != null) {
      const radius = this.mapSearchBias.radiusMeters || 40000;
      const lat = this.mapSearchBias.centerLat;
      const lng = this.mapSearchBias.centerLng;
      const dLat = radius / 111320;
      const cosLat = Math.cos((lat * Math.PI) / 180);
      const dLng = cosLat === 0 ? dLat : radius / (111320 * Math.abs(cosLat));
      map.fitBounds(
        [
          [lat - dLat, lng - dLng],
          [lat + dLat, lng + dLng]
        ],
        { padding: [28, 28], maxZoom: 12 }
      );
      this.wizardMapShouldFit = false;
    } else if (!bounds.length) {
      map.setView(EGYPT_MAP_CENTER, 6);
    }
    this.wizardMapDrawnKey = `${selected}|${results.map((row) => row.placeId).join(',')}|keep`;
    setTimeout(() => map.invalidateSize(), 80);
  }

  buildGpsPinIcon(leaflet) {
    // Crosshair-style icon to visually indicate “GPS current location”.
    return leaflet.divIcon({
      className: 'map-pin-icon-shell map-gps-icon-shell',
      html:
        '<div style="' +
        'width:34px;height:34px;border-radius:50%;' +
        'background:#0176d3;border:2px solid #fff;' +
        'box-shadow:0 2px 6px rgba(0,0,0,0.35);' +
        'display:flex;align-items:center;justify-content:center;' +
        'position:relative;' +
        '">' +
        '<span style="font-size:18px;line-height:1;color:#fff;font-weight:800;">+</span>' +
        '</div>',
      iconSize: [34, 34],
      iconAnchor: [17, 17],
      popupAnchor: [0, -16]
    });
  }

  buildWizardPlaceIcon(leaflet, selected, placeKind, isKol) {
    const kind = this.normalizePlaceKind(placeKind);
    const meta = PLACE_KIND_META[kind] || PLACE_KIND_META.unknown;
    const size = selected ? 36 : 28;
    const color = meta.color;
    const glyphUrl = accountTypeIconUrl(meta.themeKind);
    const ring = selected
      ? `0 0 0 3px ${color}55, 0 2px 6px rgba(0,0,0,0.35)`
      : '0 2px 6px rgba(0,0,0,0.35)';
    const star = isKol
      ? '<span style="position:absolute;right:-2px;top:-4px;font-size:11px;line-height:1;color:#ffd76e;text-shadow:0 0 2px #5c4300">★</span>'
      : '';
    const inner = glyphUrl
      ? `<img src="${glyphUrl}" alt="" style="width:70%;height:70%;object-fit:contain;" />`
      : `<span style="display:block;width:70%;height:70%;line-height:0;">${String(
          kind === 'company' ? COMPANY_PIN_SVG : UNKNOWN_PIN_SVG
        ).replace('<svg ', '<svg width="100%" height="100%" ')}</span>`;
    const background = glyphUrl ? '#fff' : color;
    const border = glyphUrl ? `2px solid ${color}` : '2px solid #fff';
    return leaflet.divIcon({
      className: 'map-pin-icon-shell',
      html:
        `<div title="${meta.label}${isKol ? ' · KOL' : ''}" style="position:relative;width:${size}px;height:${size}px;border-radius:50%;background:${background};border:${border};box-shadow:${ring};display:flex;align-items:center;justify-content:center;padding:4px;box-sizing:border-box;">` +
        inner +
        star +
        '</div>',
      iconSize: [size, size],
      iconAnchor: [size / 2, size / 2]
    });
  }

  clearWizardMapMarkers() {
    if (this.wizardMapInstance && this.wizardMapMarkers?.length) {
      this.wizardMapMarkers.forEach((marker) => this.wizardMapInstance.removeLayer(marker));
    }
    this.wizardMapMarkers = [];
    this.wizardMapMarkersByPlaceId = {};
  }

  destroyWizardMap() {
    if (this.createAddressLookupDebounce) {
      clearTimeout(this.createAddressLookupDebounce);
      this.createAddressLookupDebounce = null;
    }
    this.isCreateAddressLookingUp = false;
    this.clearWizardMapMarkers();
    if (this.createPinMarker && this.wizardMapInstance) {
      this.wizardMapInstance.removeLayer(this.createPinMarker);
    }
    this.createPinMarker = null;
    if (this.createPinRippleLayer && this.wizardMapInstance) {
      try {
        this.wizardMapInstance.removeLayer(this.createPinRippleLayer);
      } catch (e) {
        // ignore
      }
    }
    this.createPinRippleLayer = null;
    if (this.createPinRippleRaf) {
      cancelAnimationFrame(this.createPinRippleRaf);
      this.createPinRippleRaf = null;
    }
    this._wizardPinLatLngKey = '';
    if (this.wizardMapInstance) {
      this.wizardMapInstance.remove();
      this.wizardMapInstance = null;
    }
    this.wizardMapDrawnKey = null;
    this.wizardMapPending = false;
  }

  reduceError(error) {
    if (Array.isArray(error?.body)) {
      return error.body.map((e) => e.message).join(', ');
    }
    return error?.body?.message || error?.message || 'Unable to load accounts.';
  }
}