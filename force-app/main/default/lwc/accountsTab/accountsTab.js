import { LightningElement, track } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';
import FORM_FACTOR from '@salesforce/client/formFactor';
import USER_ID from '@salesforce/user/Id';
import LEAFLET from '@salesforce/resourceUrl/leaflet';
import getAccountsTabPage from '@salesforce/apex/AccountsTabController.getAccountsTabPage';
import getAccountsTabMapPoints from '@salesforce/apex/AccountsTabController.getAccountsTabMapPoints';
import getAccountsTabRecordTypeOptions from '@salesforce/apex/AccountsTabController.getAccountsTabRecordTypeOptions';
import {
    addOsmTileLayer,
    ensureLeaflet,
    HCO_PIN_SVG,
    HCP_PIN_SVG,
    resolveAccountPinKind
} from 'c/plannerMapPins';
import {
    loadAccountCollections,
    getCollectionAccountIds
} from 'c/plannerAccountCollections';

const FILTER_ALL = 'All';
const SCOPE_BOTH = 'both';
const SCOPE_IN = 'in';
const SCOPE_OUT = 'out';
const LIST_MODE_ALL = 'all';
const LIST_MODE_COLLECTION = 'collection';
const SORT_AGENTFORCE = 'agentforceScore';
const SORT_CLASSIFICATION = 'classification';
const SORT_NAME = 'name';
const PAGE_SIZE = 10;
const MAP_PAGE_SIZE = 5;
const SEARCH_DEBOUNCE_MS = 350;
const COMPACT_BREAKPOINT_PX = 1024;

const SCOPE_OPTIONS = [
    { label: 'All Accounts', value: SCOPE_BOTH },
    { label: 'In Plan Cycle', value: SCOPE_IN },
    { label: 'Out of Plan Cycle', value: SCOPE_OUT }
];

const SORT_OPTIONS = [
    { label: 'Agentforce Score', value: SORT_AGENTFORCE },
    { label: 'Classification', value: SORT_CLASSIFICATION },
    { label: 'Name', value: SORT_NAME }
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
  errorMessage;
  viewMode = 'list';
  scope = SCOPE_BOTH;
  searchTerm = '';
  recordType = FILTER_ALL;
  classification = FILTER_ALL;
  sortBy = SORT_AGENTFORCE;
  sortDirection = 'desc';
  currentPage = 1;
  mapCurrentPage = 1;
  mapEligibleCount = 0;
  isNarrowViewport = false;
  sidebarOpen = true;
  sidebarPanel = 'lists';
  listViewMode = LIST_MODE_ALL;
  selectedCollectionId = null;
  accountCollections = [];
  filterRevision = 0;

  recordTypeOptions = [{ label: 'All Record Types', value: FILTER_ALL }];
  specialtyOptions = [];
  classificationOptions = [{ label: 'All Classifications', value: FILTER_ALL }];
  scopeOptions = SCOPE_OPTIONS;
  sortOptions = SORT_OPTIONS;

  mapInstance;
  mapMarkers = [];
  markersByAccountId = {};
  mapRenderToken = 0;
  loadRequestToken = 0;
  selectedAccountId;

  searchDebounce;

  columns = [
    {
      label: 'Account',
      fieldName: 'accountUrl',
      type: 'url',
      typeAttributes: { label: { fieldName: 'accountName' }, target: '_self' },
      sortable: false
    },
    { label: 'Classification', fieldName: 'classification', type: 'text' },
    { label: 'Matrix', fieldName: 'matrixRating', type: 'text' },
    { label: 'Potential', fieldName: 'potential', type: 'text' },
    { label: 'Penetration', fieldName: 'penetration', type: 'text' },
    { label: 'KOL', fieldName: 'isKolLabel', type: 'text' },
    { label: 'Plan Cycle', fieldName: 'planCycleLabel', type: 'text' },
    {
      label: 'Target',
      fieldName: 'targetVisits',
      type: 'number',
      cellAttributes: { alignment: 'left' }
    },
    {
      label: 'Actual',
      fieldName: 'actualVisits',
      type: 'number',
      cellAttributes: { alignment: 'left' }
    },
    {
      label: 'Gap',
      fieldName: 'visitGap',
      type: 'number',
      cellAttributes: { alignment: 'left' }
    },
    { label: 'Frequency', fieldName: 'frequencyStatus', type: 'text' },
    {
      label: 'Reach %',
      fieldName: 'reachPercentDisplay',
      type: 'text'
    },
    {
      label: 'Projected %',
      fieldName: 'projectedPercentDisplay',
      type: 'text'
    },
    { label: 'Pace', fieldName: 'paceStatusLabel', type: 'text' },
    {
      label: 'Agentforce',
      fieldName: 'agentforceScoreDisplay',
      type: 'text'
    },
    { label: 'Risk', fieldName: 'agentforceRisk', type: 'text' },
    { label: 'Specialty', fieldName: 'specialty', type: 'text' },
    { label: 'City', fieldName: 'city', type: 'text' }
  ];

  connectedCallback() {
    this.updateViewportMode();
    if (typeof window !== 'undefined') {
      window.addEventListener('resize', this.handleResize);
    }
    this.loadPlannerCollections();
    this.loadFilterOptions();
    this.reloadData(true);
  }

  disconnectedCallback() {
    this.destroyMap();
    if (this.searchDebounce) {
      clearTimeout(this.searchDebounce);
    }
    if (typeof window !== 'undefined') {
      window.removeEventListener('resize', this.handleResize);
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
    this.isNarrowViewport = window.innerWidth <= COMPACT_BREAKPOINT_PX;
    if (this.isCompactView && FORM_FACTOR === 'Small') {
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

  get toolbarClass() {
    return `accounts-toolbar${this.isCompactView ? ' accounts-toolbar-compact' : ''}`;
  }

  get summaryCardsClass() {
    return `summary-cards${this.isCompactView ? ' summary-cards-compact' : ''}`;
  }

  get sidebarClass() {
    const classes = ['oce-sidebar'];
    if (this.sidebarOpen) {
      classes.push('oce-sidebar-open');
    }
    return classes.join(' ');
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

  get datatableKey() {
    return `accounts-${this.filterRevision}`;
  }

  get countLabel() {
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
      const pinKind = resolveAccountPinKind(
        row.recordTypeDeveloperName,
        row.recordTypeName
      );
      const isSelected = row.accountId === this.selectedAccountId;
      return {
        ...row,
        pinKind,
        typeLabel: pinKind === 'hco' ? 'HCO' : 'HCP',
        riskDotClass: RISK_DOT_CLASS[row.agentforceRisk] || RISK_DOT_CLASS.Low,
        itemClass: `map-account-item${isSelected ? ' map-account-item-selected' : ''}`,
        subtitle: [row.recordTypeName, row.city].filter(Boolean).join(' · ') || '—'
      };
    });
  }

  get mapListCountLabel() {
    const geocoded = this.mapEligibleCount || 0;
    const matched = this.summary.totalCount || 0;
    if (geocoded === 0) {
      return matched > 0 ? `0 on map (${matched} matched)` : '0 on map';
    }
    const start = (this.mapCurrentPage - 1) * MAP_PAGE_SIZE + 1;
    const end = Math.min(this.mapCurrentPage * MAP_PAGE_SIZE, geocoded);
    let label = `Showing ${start}–${end} of ${geocoded}`;
    if (geocoded < matched) {
      label += ` (${matched} matched)`;
    }
    return label;
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

  get mapRangeLabel() {
    const total = this.mapEligibleCount || 0;
    if (total === 0) {
      return '';
    }
    const start = (this.mapCurrentPage - 1) * MAP_PAGE_SIZE + 1;
    const end = Math.min(this.mapCurrentPage * MAP_PAGE_SIZE, total);
    return `Showing ${start}–${end} of ${total}`;
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

  get showPagination() {
    return this.isListView && (this.summary.totalCount || 0) > PAGE_SIZE;
  }

  get totalPages() {
    return Math.max(1, Math.ceil((this.summary.totalCount || 0) / PAGE_SIZE));
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
    const start = (this.currentPage - 1) * PAGE_SIZE + 1;
    const end = Math.min(this.currentPage * PAGE_SIZE, total);
    return `Showing ${start}–${end} of ${total}`;
  }

  get pageLabel() {
    return `Page ${this.currentPage} of ${this.totalPages}`;
  }

  get showEmptyState() {
    return !this.isLoading && !this.errorMessage && (this.rows || []).length === 0;
  }

  async loadFilterOptions() {
    try {
      const recordTypes = await getAccountsTabRecordTypeOptions();
      this.recordTypeOptions = this.normalizeComboboxOptions(recordTypes, this.recordTypeOptions);
      this.classificationOptions = [
        { label: 'All Classifications', value: FILTER_ALL },
        { label: 'A', value: 'A' },
        { label: 'B', value: 'B' },
        { label: 'C', value: 'C' }
      ];
    } catch (error) {
      // Filters are optional; list still works with defaults.
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
    const pageSize = mapMode ? MAP_PAGE_SIZE : PAGE_SIZE;
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
      accountIds: accountIds.length ? accountIds : null
    };
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
    const maxPage = Math.max(
      1,
      Math.ceil((this.summary.totalCount || 0) / PAGE_SIZE)
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
    this.filterRevision += 1;
    if (this.isMapView) {
      return this.refreshMapView();
    }
    return this.loadPage();
  }

  async loadPage() {
    const token = ++this.loadRequestToken;
    this.isLoading = true;
    this.errorMessage = null;
    this.rows = [];
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
    this.sortDirection = this.sortBy === SORT_NAME ? 'asc' : 'desc';
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
    this.applySearch(this.readInputValue(event));
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

  handleShowAllAccounts() {
    this.loadPlannerCollections();
    this.listViewMode = LIST_MODE_ALL;
    this.selectedCollectionId = null;
    this.reloadData(true);
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
    if (this.sidebarOpen && this.sidebarPanel === 'filters') {
      this.sidebarOpen = false;
      return;
    }
    this.sidebarPanel = 'filters';
    this.sidebarOpen = true;
  }

  handleToggleSidebar() {
    this.sidebarOpen = !this.sidebarOpen;
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
  }

  handleTypeNavSelect(event) {
    this.recordType = event.currentTarget.dataset.value;
    this.reloadData(true);
  }

  handleMapListSelect(event) {
    const accountId = event.currentTarget.dataset.accountId;
    if (!accountId) {
      return;
    }
    this.selectedAccountId = accountId;
    const row = (this.mapRows || []).find((item) => item.accountId === accountId);
    if (row?.latitude != null && row?.longitude != null) {
      this.flyToAccount(row.latitude, row.longitude, accountId);
    }
  }

  handleMapListViewAccount(event) {
    event.stopPropagation();
    const accountId = event.currentTarget.dataset.accountId;
    if (accountId) {
      this.navigateToAccount(accountId);
    }
  }

  handleOceRowAction(event) {
    const { accountId, action } = event.detail;
    if (action === 'plan') {
      this.navigateToPlanner();
      return;
    }
    if (accountId) {
      this.navigateToAccount(accountId);
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
    if (this.mapInstance) {
      this.destroyMap();
    }
    container.innerHTML = '';
    const mapDiv = document.createElement('div');
    mapDiv.style.height = '100%';
    mapDiv.style.width = '100%';
    container.appendChild(mapDiv);
    const map = leaflet.map(mapDiv, { zoomControl: true });
    addOsmTileLayer(map, leaflet);
    this.mapInstance = map;
    return map;
  }

  buildRiskPinIcon(leaflet, row) {
    const pinKind = resolveAccountPinKind(
      row.recordTypeDeveloperName,
      row.recordTypeName
    );
    const svg = (pinKind === 'hco' ? HCO_PIN_SVG : HCP_PIN_SVG).replace(
      '<svg ',
      '<svg style="width:16px;height:16px;" '
    );
    const color = RISK_PIN_COLORS[row.agentforceRisk] || RISK_PIN_COLORS.Low;
    const safeName = String(row.accountName || '')
      .replace(/&/g, '&amp;')
      .replace(/"/g, '&quot;')
      .replace(/</g, '&lt;');
    return leaflet.divIcon({
      className: 'map-pin-icon-shell',
      html: `<div style="width:30px;height:30px;border-radius:50%;background:${color};border:2px solid #fff;box-shadow:0 2px 6px rgba(0,0,0,0.35);display:flex;align-items:center;justify-content:center;" title="${safeName}">${svg}</div>`,
      iconSize: [30, 30],
      iconAnchor: [15, 15],
      popupAnchor: [0, -16]
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
        .marker(latLng, { icon })
        .addTo(map)
        .bindPopup(this.buildPopupHtml(row));
      marker.on('click', () => {
        this.selectedAccountId = row.accountId;
        this.scrollMapListItemIntoView(row.accountId);
        marker.openPopup();
      });
      this.mapMarkers.push(marker);
      this.markersByAccountId[row.accountId] = marker;
    });
    if (bounds.length) {
      map.fitBounds(bounds, { padding: [30, 30], maxZoom: 14 });
    } else {
      map.setView([30.0444, 31.2357], 6);
    }
    setTimeout(() => map.invalidateSize(), 100);
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
    const listItem = this.template.querySelector(
      `[data-account-id="${accountId}"]`
    );
    if (listItem) {
      listItem.scrollIntoView({ block: 'nearest', behavior: 'smooth' });
    }
  }

  buildPopupHtml(row) {
    const projected =
      row.projectedPercent != null ? `${Math.round(Number(row.projectedPercent))}%` : 'N/A';
    const hasTarget = row.targetVisits != null;
    return `<strong>${row.accountName}</strong><br/>
      ${row.classification || '—'} · ${row.planCycleLabel}<br/>
      Visits: ${hasTarget ? `${row.actualVisits || 0}/${row.targetVisits}` : `${row.actualVisits || 0} (no target)`}<br/>
      Pace: ${row.paceStatusLabel || 'N/A'} · Score: ${Number(row.agentforceScore || 0).toFixed(1)}`;
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

  navigateToPlanner() {
    this[NavigationMixin.Navigate]({
      type: 'standard__navItemPage',
      attributes: {
        apiName: 'Field_Rep_Planner'
      }
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
    if (this.mapInstance) {
      this.mapInstance.remove();
      this.mapInstance = null;
    }
  }

  reduceError(error) {
    if (Array.isArray(error?.body)) {
      return error.body.map((e) => e.message).join(', ');
    }
    return error?.body?.message || error?.message || 'Unable to load accounts.';
  }
}
