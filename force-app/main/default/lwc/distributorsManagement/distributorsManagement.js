import { LightningElement, api, track } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { loadScript, loadStyle } from 'lightning/platformResourceLoader';
import SHEETJS from '@salesforce/resourceUrl/sheetjs';
import LEAFLET from '@salesforce/resourceUrl/leaflet';
import DISTRIBUTOR_LOGOS from '@salesforce/resourceUrl/DistributorLogos';
import { ensureLeaflet, addOsmTileLayer } from 'c/plannerMapPins';
import { EGYPT_BOUNDS, fitBoundsFor, popupHtml } from './distributorMapUtils';
import {
    DISTRIBUTOR_OPTIONS,
    REPORT_CADENCE_OPTIONS,
    detectDistributor,
    parseDistributorWorkbook,
    isValidReportMonth
} from 'c/distributorAdapters';
import listDistributors from '@salesforce/apex/SalesDistributorRegistry.listDistributors';
import ensureDistributorDefaults from '@salesforce/apex/SalesDistributorRegistry.ensureDefaults';
import upsertDistributor from '@salesforce/apex/SalesDistributorRegistry.upsertDistributor';
import getProductAliases from '@salesforce/apex/DistributorsManagementController.getProductAliases';
import getProductMappingNav from '@salesforce/apex/DistributorsManagementController.getProductMappingNav';
import saveProductAliasDrafts from '@salesforce/apex/DistributorsManagementController.saveProductAliasDrafts';
import bulkConfirmProductAliases from '@salesforce/apex/DistributorsManagementController.bulkConfirmProductAliases';
import getSelloutAliases from '@salesforce/apex/DistributorsManagementController.getSelloutAliases';
import getSelloutAliasesPage from '@salesforce/apex/DistributorsManagementController.getSelloutAliasesPage';
import updateSelloutAlias from '@salesforce/apex/DistributorsManagementController.updateSelloutAlias';
import mergeSelloutAliases from '@salesforce/apex/DistributorsManagementController.mergeSelloutAliases';
import rematchSellouts from '@salesforce/apex/DistributorSelloutRematchService.rematch';
import searchPharmacies from '@salesforce/apex/DistributorsManagementController.searchPharmacies';
import ingestNormalizedRows from '@salesforce/apex/DistributorsManagementController.ingestNormalizedRows';
import previewMappingCoverage from '@salesforce/apex/DistributorsManagementController.previewMappingCoverage';
import getImportBatches from '@salesforce/apex/DistributorsManagementController.getImportBatches';
import markImportBatchFailed from '@salesforce/apex/DistributorsManagementController.markImportBatchFailed';
import resumeImportBatch from '@salesforce/apex/DistributorsManagementController.resumeImportBatch';
import requeueImportBatch from '@salesforce/apex/DistributorsManagementController.requeueImportBatch';
import getGeocodeConfigStatus from '@salesforce/apex/DistributorsManagementController.getGeocodeConfigStatus';
import saveGeocodeApiKey from '@salesforce/apex/DistributorsManagementController.saveGeocodeApiKey';
import getMappingAccuracy from '@salesforce/apex/DistributorsManagementController.getMappingAccuracy';
import getLoadReview from '@salesforce/apex/DistributorLoadReviewService.getLoadReview';
import searchRatedDoctors from '@salesforce/apex/PharmacyProximityShareService.searchRatedDoctors';
import getDoctorShareReview from '@salesforce/apex/PharmacyProximityShareService.getDoctorShareReview';
import refreshNearbyShares from '@salesforce/apex/PharmacyProximityShareService.refreshNearbyShares';
import saveOrderShares from '@salesforce/apex/PharmacyProximityShareService.saveOrderShares';

const LOGO_FILE_BY_CODE = {
    EPDA: 'epda.png',
    Ebda: 'epda.png',
    EBDA: 'epda.png',
    'EPDA Cust': 'epda.png',
    'Ebda Cust': 'epda.png',
    'EBDA Cust': 'epda.png',
    Egydrug: 'egydrug.png',
    Elezaby: 'elezaby.png',
    IBNSINA: 'ibnsina.png',
    POS: 'pos.png',
    Sofico: 'sofico.png'
};

/** Correct UI spelling; imports still accept Ebda as a typo. */
function displayDistributorLabel(code) {
    if (!code) return code;
    const upper = String(code).trim().toUpperCase();
    if (upper === 'EBDA' || upper === 'EPDA') return 'EPDA';
    if (upper === 'EBDA CUST' || upper === 'EPDA CUST') return 'EPDA Cust';
    return code;
}

function logoFileFor(code) {
    if (!code) return null;
    const raw = String(code).trim();
    if (LOGO_FILE_BY_CODE[raw]) return LOGO_FILE_BY_CODE[raw];
    const labeled = displayDistributorLabel(raw);
    if (LOGO_FILE_BY_CODE[labeled]) return LOGO_FILE_BY_CODE[labeled];
    const upper = raw.toUpperCase();
    if (upper === 'EBDA' || upper === 'EPDA') return 'epda.png';
    if (upper === 'EBDA CUST' || upper === 'EPDA CUST') return 'epda.png';
    return null;
}

const PRODUCT_PAGE_SIZE_OPTIONS = [
    { label: '25', value: '25' },
    { label: '50', value: '50' },
    { label: '100', value: '100' }
];

const TABS = [
    { id: 'import', label: 'Import' },
    { id: 'registry', label: 'Registry' },
    { id: 'products', label: 'Product mapping' },
    { id: 'sellouts', label: 'Sellout mapping' },
    { id: 'nearby', label: 'Nearby share' },
    { id: 'batches', label: 'Batches' }
];

const CHUNK_SIZE = 1500;

const STATUS_COLORS = {
    Confirmed: '#2e844a',
    Suggested: '#dd7a01',
    Unmatched: '#ba0517',
    Rejected: '#706e6b',
    Pending: '#0176d3'
};

export default class DistributorsManagement extends LightningElement {
    @track activeTab = 'import';
    @track distributorCode = '';
    @track fileName = '';
    @track reportMonth = '';
    /** Month found in the file's dates. Only a suggestion: it never replaces a month the user picked. */
    @track detectedMonth = '';
    reportMonthUserSet = false;
    distributorUserSet = false;
    @track parsedRows = [];
    @track parseWarnings = [];
    @track sheetUsed = '';
    @track coverage;
    @track isParsing = false;
    @track isImporting = false;
    @track importMessage = '';
    @track reportCadence = '';
    @track detectedFrom = '';
    @track importMaxRows = 0;
    @track preferAddressedRows = false;
    @track geocodeStatus;
    @track googleApiKeyInput = '';
    @track isSavingGeocode = false;

    @track productRows = [];
    @track productStatusFilter = '';
    @track productUnmappedOnly = false;
    @track productDrafts = [];
    @track isSavingProducts = false;
    @track productGroupMode = 'distributor';
    @track productLineFilter = '';
    @track productSearch = '';
    @track productNavKey = '';
    @track productNav = { distributors: [], productLines: [] };
    @track productPage = 1;
    @track productPageSize = 50;
    productSearchTimer;
    productPageSizeOptions = PRODUCT_PAGE_SIZE_OPTIONS;

    @track selloutRows = [];
    @track selloutStatusFilter = '';
    @track selloutNeedsReview = true;
    @track selectedSelloutId;
    @track pharmacyOptions = [];
    @track selectedPharmacyId;
    @track pharmacySearch = '';

    @track batchRows = [];
    loadReview;
    isLoadingReview = false;
    @track accuracy;
    @track doctorSearch = '';
    @track doctorOptions = [];
    @track shareReview;
    @track shareDrafts = [];
    @track isSavingShares = false;
    @track registryRows = [];
    @track registryDraft = {
        code: '',
        name: '',
        adapterKey: '',
        isDirect: false,
        isActive: true
    };
    @track isSavingRegistry = false;

    @api initialDoctorSearch = '';

    sheetjsReady = false;
    leafletReady = false;
    map;
    markersLayer;

    distributorOptions = DISTRIBUTOR_OPTIONS;
    selloutOffset = 0;
    selloutPageSize = 500;
    reportCadenceOptions = REPORT_CADENCE_OPTIONS;

    productColumns = [
        { label: 'Distributor', fieldName: 'distributorCode', type: 'text', initialWidth: 110 },
        { label: 'Product line', fieldName: 'productFamily', type: 'text', initialWidth: 120 },
        { label: 'Item code', fieldName: 'itemCode', type: 'text', initialWidth: 100 },
        {
            label: 'Item name',
            fieldName: 'itemName',
            type: 'text',
            editable: true,
            wrapText: true
        },
        {
            label: 'Zeta product',
            fieldName: 'productUrl',
            type: 'url',
            typeAttributes: {
                label: { fieldName: 'productName' },
                target: '_blank',
                tooltip: 'Open Salesforce Product'
            }
        },
        {
            label: 'Zeta code',
            fieldName: 'zetaCode',
            type: 'text',
            editable: true,
            initialWidth: 110
        },
        {
            label: 'Confidence %',
            fieldName: 'confidence',
            type: 'number',
            editable: true,
            initialWidth: 110,
            cellAttributes: { alignment: 'left' }
        },
        { label: 'Method', fieldName: 'matchMethod', type: 'text', initialWidth: 90 },
        {
            label: 'Status',
            fieldName: 'status',
            type: 'text',
            editable: true,
            initialWidth: 110
        }
    ];

    selloutColumns = [
        {
            label: 'Alias',
            fieldName: 'recordUrl',
            type: 'url',
            typeAttributes: { label: { fieldName: 'clientName' }, target: '_blank' },
            initialWidth: 160
        },
        { label: 'Distributor', fieldName: 'distributorCode', type: 'text', initialWidth: 90 },
        { label: 'Client code', fieldName: 'clientCode', type: 'text', initialWidth: 90 },
        { label: 'Address', fieldName: 'address', type: 'text' },
        {
            label: 'Pharmacy Account',
            fieldName: 'pharmacyUrl',
            type: 'url',
            typeAttributes: { label: { fieldName: 'pharmacyName' }, target: '_blank' },
            initialWidth: 160
        },
        { label: 'Confidence %', fieldName: 'confidence', type: 'number', initialWidth: 100 },
        { label: 'Geo', fieldName: 'geocodeStatus', type: 'text', initialWidth: 90 },
        {
            label: 'Geo reason',
            fieldName: 'geocodeMessage',
            type: 'text',
            wrapText: true,
            initialWidth: 220
        },
        { label: 'Status', fieldName: 'status', type: 'text', initialWidth: 100 }
    ];

    batchColumns = [
        { label: 'Batch', fieldName: 'batchName', type: 'text', initialWidth: 110 },
        { label: 'File', fieldName: 'fileName', type: 'text', wrapText: true },
        { label: 'Distributor', fieldName: 'distributorCode', type: 'text' },
        { label: 'Status', fieldName: 'status', type: 'text', initialWidth: 100 },
        { label: 'Chunks', fieldName: 'chunkLabel', type: 'text', initialWidth: 90 },
        { label: 'Inserted', fieldName: 'rowsInserted', type: 'number' },
        { label: 'Updated', fieldName: 'rowsUpdated', type: 'number' },
        { label: 'Failed', fieldName: 'rowsFailed', type: 'number' },
        { label: 'Aliases', fieldName: 'aliasesCreated', type: 'number' },
        { label: 'Needs review', fieldName: 'needsReview', type: 'number' },
        { label: 'Last log', fieldName: 'logTail', type: 'text', wrapText: true },
        { type: 'action', typeAttributes: { rowActions: this.getBatchRowActions.bind(this) } }
    ];

    statusFilterOptions = [
        { label: 'All statuses', value: '' },
        { label: 'Suggested', value: 'Suggested' },
        { label: 'Confirmed', value: 'Confirmed' },
        { label: 'Rejected', value: 'Rejected' },
        { label: 'Unmatched', value: 'Unmatched' }
    ];

    groupModeOptions = [
        { label: 'Distributor', value: 'distributor' },
        { label: 'Product line', value: 'productLine' },
        { label: 'Flat list', value: 'flat' }
    ];

    get tabs() {
        return TABS.map((tab) => ({
            ...tab,
            className: `tab-btn${this.activeTab === tab.id ? ' tab-btn--active' : ''}`
        }));
    }

    get distributorFilterOptions() {
        return [{ label: 'All distributors', value: '' }, ...DISTRIBUTOR_OPTIONS];
    }

    get isImportTab() {
        return this.activeTab === 'import';
    }
    get isRegistryTab() {
        return this.activeTab === 'registry';
    }
    get isProductsTab() {
        return this.activeTab === 'products';
    }
    get isSelloutsTab() {
        return this.activeTab === 'sellouts';
    }
    get isBatchesTab() {
        return this.activeTab === 'batches';
    }
    get isNearbyTab() {
        return this.activeTab === 'nearby';
    }

    get pharmacyAccuracyLabel() {
        return this.accuracy ? `${this.accuracy.pharmacyAccuracy}%` : '';
    }
    get productAccuracyLabel() {
        return this.accuracy ? `${this.accuracy.productAccuracy}%` : '';
    }
    get accuracyDetail() {
        if (!this.accuracy) return '';
        const a = this.accuracy;
        return `Pharmacies ${a.selloutsMapped}/${a.sellouts} · Products confirmed ${a.productsConfirmed}/${a.productAliases} · Code ${a.matchedByCode} · Name ${a.matchedByName} · Map ${a.matchedByMap} · SFE ${a.matchedBySfe} · Needs review ${a.needsReview}`;
    }
    get hasDoctorOptions() {
        return this.doctorOptions.length > 0;
    }
    get hasShareRows() {
        return this.shareDrafts.length > 0;
    }
    get shareTotalLabel() {
        const total = this.shareDrafts.reduce(
            (sum, row) => sum + (Number(row.orderSharePercent) || 0),
            0
        );
        return `${total.toFixed(2)}%`;
    }
    get shareTotalClass() {
        const total = this.shareDrafts.reduce(
            (sum, row) => sum + (Number(row.orderSharePercent) || 0),
            0
        );
        return Math.abs(total - 100) <= 0.1 ? 'share-total share-total--ok' : 'share-total share-total--bad';
    }

    get hasParsedRows() {
        return this.parsedRows.length > 0;
    }

    get parseSummary() {
        if (!this.hasParsedRows) return '';
        const products = new Set(this.parsedRows.map((r) => r.itemCode)).size;
        const sellouts = new Set(this.parsedRows.map((r) => r.clientCode)).size;
        let cover = '';
        if (this.coverage) {
            cover = ` | Products mapped ${this.coverage.productsMapped}/${this.coverage.distinctProducts} | Sellouts mapped ${this.coverage.selloutsMapped}/${this.coverage.distinctSellouts}`;
        }
        const cadence = this.reportCadence ? ` | ${this.reportCadence}` : '';
        const dist = this.distributorCode ? ` | ${this.distributorCode}` : '';
        return `${this.parsedRows.length} rows${dist}${cadence} | ${products} products | ${sellouts} sellouts | sheet ${this.sheetUsed || '-'}${cover}`;
    }

    get selectedSellout() {
        return this.selloutRows.find((r) => r.recordId === this.selectedSelloutId);
    }

    get linkedDistributorsLabel() {
        const s = this.selectedSellout;
        if (!s?.linkedDistributors?.length) return '';
        return `Also mapped from: ${s.linkedDistributors.join(', ')}`;
    }

    get selectedSelloutHasPharmacy() {
        return !!this.selectedSellout?.pharmacyUrl;
    }

    get selectedSelloutGeoStatus() {
        return this.selectedSellout?.geocodeStatus || '';
    }

    get selectedSelloutNeedsGeoHelp() {
        const status = this.selectedSelloutGeoStatus;
        return status === 'Failed' || status === 'Skipped' || status === 'Pending';
    }

    get selectedSelloutGeoReason() {
        return this.selectedSellout?.geocodeMessage || '';
    }

    get selectedSelloutGeoRecommendation() {
        return this.selectedSellout?.geocodeRecommendation || '';
    }

    get selectedSelloutRecordUrl() {
        return this.selectedSellout?.recordUrl || null;
    }

    get selectedSelloutPharmacyUrl() {
        return this.selectedSellout?.pharmacyUrl || null;
    }

    get selectedSelloutPharmacyLabel() {
        const s = this.selectedSellout;
        if (!s?.pharmacyName) return '';
        return s.pharmacyName;
    }

    get hasProductDrafts() {
        return (this.productDrafts || []).length > 0;
    }

    get pharmacyComboboxOptions() {
        return (this.pharmacyOptions || []).map((o) => ({ label: o.label, value: o.value }));
    }

    get showProductNav() {
        return this.productGroupMode !== 'flat';
    }

    get productLayoutClass() {
        return this.showProductNav ? 'product-layout product-layout--split' : 'product-layout';
    }

    get productNavSource() {
        if (this.productGroupMode === 'productLine') {
            return this.productNav?.productLines || [];
        }
        return this.productNav?.distributors || [];
    }

    get productNavItems() {
        return this.productNavSource.map((item) => {
            const label = displayDistributorLabel(item.label || item.key);
            const logoUrl = this.logoUrlFor(item.key) || this.logoUrlFor(label);
            return {
                ...item,
                label,
                logoUrl,
                hasLogo: !!logoUrl && this.productGroupMode === 'distributor',
                className: `nav-item${this.productNavKey === item.key ? ' nav-item--active' : ''}`
            };
        });
    }

    get allNavClass() {
        return `nav-item${this.productNavKey === '' ? ' nav-item--active' : ''}`;
    }

    get productTotalCount() {
        return this.productNavSource.reduce((sum, item) => sum + (item.count || 0), 0);
    }

    get productLineFilterOptions() {
        const lines = (this.productNav?.productLines || []).map((g) => ({
            label: `${g.label} (${g.count})`,
            value: g.key
        }));
        return [{ label: 'All product lines', value: '' }, ...lines];
    }

    get productFilterSummary() {
        const parts = [];
        if (this.distributorCode) parts.push(this.distributorCode);
        if (this.productNavKey) {
            const hit = this.productNavSource.find((g) => g.key === this.productNavKey);
            parts.push(hit?.label || this.productNavKey);
        } else if (this.productLineFilter) {
            const hit = (this.productNav?.productLines || []).find((g) => g.key === this.productLineFilter);
            parts.push(hit?.label || this.productLineFilter);
        }
        if (this.productSearch) parts.push(`"${this.productSearch}"`);
        const scope = parts.length ? parts.join(' | ') : 'All mappings';
        return `${scope} | ${this.productRows.length} row(s)`;
    }

    get productTotalPages() {
        return Math.max(1, Math.ceil((this.productRows || []).length / this.productPageSize));
    }

    get pagedProductRows() {
        const start = (this.productPage - 1) * this.productPageSize;
        return (this.productRows || []).slice(start, start + this.productPageSize);
    }

    get productPageLabel() {
        if (!this.productRows?.length) {
            return 'No rows';
        }
        const start = (this.productPage - 1) * this.productPageSize + 1;
        const end = Math.min(this.productPage * this.productPageSize, this.productRows.length);
        return `Showing ${start}-${end} of ${this.productRows.length}`;
    }

    get isProductPrevDisabled() {
        return this.productPage <= 1;
    }

    get isProductNextDisabled() {
        return this.productPage >= this.productTotalPages;
    }

    get productPageSizeValue() {
        return String(this.productPageSize);
    }

    logoUrlFor(code) {
        const file = logoFileFor(code);
        return file ? `${DISTRIBUTOR_LOGOS}/${file}` : null;
    }

    get allDistributorsLogoUrl() {
        return `${DISTRIBUTOR_LOGOS}/all.png`;
    }

    resetProductPage() {
        this.productPage = 1;
    }

    get geocodeProviderLabel() {
        return this.geocodeStatus?.providerLabel || 'Checking geocoder...';
    }

    get geocodeReadyMessage() {
        if (!this.geocodeStatus) return '';
        if (this.geocodeStatus.hasGoogleKey) {
            return `Using Google Geocoding for street addresses, then Google Places when the address misses but the pharmacy name is known. Proximity ${this.geocodeStatus.proximityMeters}m / auto-confirm ${this.geocodeStatus.autoConfirmThreshold}%.`;
        }
        return `No Google API key set — using OpenStreetMap Nominatim. Proximity ${this.geocodeStatus.proximityMeters}m.`;
    }

    connectedCallback() {
        if (this.initialDoctorSearch) {
            this.doctorSearch = this.initialDoctorSearch;
        }
        this.loadDistributorRegistry();
        this.loadProductRows();
        this.loadBatchRows();
        this.loadGeocodeStatus();
        this.loadAccuracy();
    }

    async loadDistributorRegistry() {
        try {
            await ensureDistributorDefaults();
            const rows = await listDistributors({ activeOnly: false });
            this.registryRows = (rows || []).map((row) => ({
                ...row,
                key: row.id || row.code,
                kindLabel: row.isDirect ? 'Direct' : 'Distributor',
                activeLabel: row.isActive === false ? 'Inactive' : 'Active'
            }));
            const active = (rows || []).filter((row) => row.isActive !== false);
            if (active.length) {
                this.distributorOptions = active.map((row) => ({
                    label: row.isDirect ? `${row.name} (Direct)` : row.name,
                    value: row.code
                }));
            }
        } catch (e) {
            // Fall back to static DISTRIBUTOR_OPTIONS (includes Zeta Direct).
        }
    }

    handleRegistryField(event) {
        const field = event.target.dataset.field;
        if (!field) return;
        let value;
        if (event.target.type === 'checkbox' || event.target.type === 'toggle') {
            value = event.target.checked;
        } else if (event.detail && event.detail.value !== undefined) {
            value = event.detail.value;
        } else {
            value = event.target.value;
        }
        this.registryDraft = { ...this.registryDraft, [field]: value };
    }

    handleRegistryEdit(event) {
        const code = event.currentTarget.dataset.code;
        const row = (this.registryRows || []).find((r) => r.code === code);
        if (!row) return;
        this.registryDraft = {
            code: row.code,
            name: row.name,
            adapterKey: row.adapterKey || row.code,
            isDirect: row.isDirect === true,
            isActive: row.isActive !== false
        };
    }

    async handleRegistrySave() {
        this.isSavingRegistry = true;
        try {
            await upsertDistributor({
                code: this.registryDraft.code,
                name: this.registryDraft.name,
                isDirect: this.registryDraft.isDirect === true,
                adapterKey: this.registryDraft.adapterKey || this.registryDraft.code,
                isActive: this.registryDraft.isActive !== false
            });
            this.dispatchEvent(
                new ShowToastEvent({
                    title: 'Distributor saved',
                    message: `${this.registryDraft.name} is in the registry.`,
                    variant: 'success'
                })
            );
            this.registryDraft = {
                code: '',
                name: '',
                adapterKey: '',
                isDirect: false,
                isActive: true
            };
            await this.loadDistributorRegistry();
        } catch (e) {
            this.dispatchEvent(
                new ShowToastEvent({
                    title: 'Save failed',
                    message: e?.body?.message || e?.message || 'Unknown error',
                    variant: 'error'
                })
            );
        } finally {
            this.isSavingRegistry = false;
        }
    }

    async loadGeocodeStatus() {
        try {
            this.geocodeStatus = await getGeocodeConfigStatus();
        } catch (e) {
            // non-blocking
        }
    }

    renderedCallback() {
        if (this.isSelloutsTab && this.leafletReady && this.selloutRows.length) {
            // map refresh handled after load
        }
    }

    handleTabClick(event) {
        this.activeTab = event.currentTarget.dataset.tabId;
        if (this.activeTab === 'products') {
            this.loadProductRows();
        } else if (this.activeTab === 'sellouts') {
            this.loadSelloutRows().then(() => this.initMap());
        } else if (this.activeTab === 'batches') {
            this.loadBatchRows();
        } else if (this.activeTab === 'nearby' && this.doctorSearch && !this.shareReview) {
            this.handleDoctorSearch();
        }
    }

    handleDistributorChange(event) {
        this.distributorCode = event.detail.value || '';
        this.distributorUserSet = !!this.distributorCode;
        this.productNavKey = '';
        this.loadAccuracy();
        if (this.activeTab === 'products') {
            this.loadProductRows();
        } else if (this.activeTab === 'sellouts') {
            this.loadSelloutRows();
        } else if (this.activeTab === 'batches') {
            this.loadBatchRows();
        }
    }

    handleReportMonthChange(event) {
        this.reportMonth = (event.target.value || '').trim();
        // A typed month is the user's choice and is never replaced by what the file dates suggest.
        this.reportMonthUserSet = this.reportMonth !== '';
        if (!this.reportMonthUserSet && this.detectedMonth) {
            this.reportMonth = this.detectedMonth;
        }
    }

    get monthNotice() {
        if (!this.hasParsedRows) return '';
        if (!isValidReportMonth(this.reportMonth)) {
            return 'Enter the report month as YYYY-MM before importing.';
        }
        if (this.detectedMonth && this.detectedMonth !== this.reportMonth) {
            return `File dates look like ${this.detectedMonth}, but this import will use ${this.reportMonth}, the month you chose.`;
        }
        return '';
    }

    get hasMonthNotice() {
        return !!this.monthNotice;
    }

    async ensureSheetJs() {
        if (this.sheetjsReady) return;
        await loadScript(this, SHEETJS);
        this.sheetjsReady = true;
    }

    async handleFileChange(event) {
        const file = event.target.files?.[0];
        if (!file) return;
        this.fileName = file.name;
        this.isParsing = true;
        this.parseWarnings = [];
        this.parsedRows = [];
        this.coverage = null;
        this.reportCadence = '';
        this.detectedFrom = '';
        this.detectedMonth = '';
        try {
            await this.ensureSheetJs();
            const buffer = await file.arrayBuffer();
            const workbook = globalThis.XLSX.read(buffer, { type: 'array' });
            // Keep a distributor the user picked; otherwise detect from file name then workbook layout
            const preferred = (this.distributorUserSet && this.distributorCode) || detectDistributor(file.name);
            const parsed = parseDistributorWorkbook(workbook, preferred, file.name);
            this.distributorCode = parsed.distributorCode || this.distributorCode || '';
            let rows = parsed.rows || [];
            if (this.preferAddressedRows) {
                const addressed = rows.filter((r) => (r.address || '').trim());
                if (addressed.length) {
                    rows = addressed;
                    this.parseWarnings = [
                        ...(parsed.warnings || []),
                        `Prefer addressed rows: using ${addressed.length} of ${(parsed.rows || []).length} with an address (better for geocoding).`
                    ];
                } else {
                    this.parseWarnings = parsed.warnings || [];
                }
            } else {
                this.parseWarnings = parsed.warnings || [];
            }
            const maxRows = Number(this.importMaxRows) > 0 ? Number(this.importMaxRows) : 0;
            if (maxRows && rows.length > maxRows) {
                rows = rows.slice(0, maxRows);
                this.parseWarnings = [
                    ...this.parseWarnings,
                    `Import capped at ${maxRows} rows for a safe pilot (change Max rows to import more).`
                ];
            }
            this.parsedRows = rows;
            this.sheetUsed = parsed.sheetUsed || '';
            this.reportCadence = parsed.reportCadence || '';
            this.detectedFrom = parsed.detectedFrom || '';
            // Month: the detected month only fills an empty / auto-filled field, never a user-picked month.
            this.detectedMonth = parsed.detectedMonth || '';
            if (!this.reportMonthUserSet) {
                this.reportMonth = this.detectedMonth;
            }
            if (this.parsedRows.length) {
                const sample = this.parsedRows.slice(0, 800);
                this.coverage = await previewMappingCoverage({
                    distributorCode: this.distributorCode,
                    rowsJson: JSON.stringify(sample)
                });
                this.toast('Parsed', this.parseSummary, 'success');
            } else {
                const detail =
                    (this.parseWarnings && this.parseWarnings[0]) ||
                    'No rows. Select the distributor if auto-detect failed.';
                this.toast('Parsed', detail, 'warning');
            }
        } catch (e) {
            this.toast('Parse error', this.reduceError(e), 'error');
        } finally {
            this.isParsing = false;
        }
    }

    async handleImport() {
        if (!this.parsedRows.length) {
            this.toast('Import', 'Parse a distributor Excel file first.', 'warning');
            return;
        }
        if (!this.distributorCode) {
            this.toast('Import', 'Select a distributor.', 'warning');
            return;
        }
        if (!isValidReportMonth(this.reportMonth)) {
            this.toast('Import', 'Enter the report month as YYYY-MM (for example 2026-06).', 'warning');
            return;
        }
        this.isImporting = true;
        this.importMessage = '';
        let batchId = null;
        try {
            const total = this.parsedRows.length;
            const totalChunks = Math.ceil(total / CHUNK_SIZE);
            for (let c = 0; c < totalChunks; c++) {
                const start = c * CHUNK_SIZE;
                const chunk = this.parsedRows.slice(start, start + CHUNK_SIZE);
                const isLast = c === totalChunks - 1;
                // Chunks must go up in order: the server stages one file per chunk and counts them.
                // eslint-disable-next-line no-await-in-loop
                const result = await ingestNormalizedRows({
                    distributorCode: this.distributorCode,
                    fileName: this.fileName,
                    reportMonth: this.reportMonth,
                    rowsJson: JSON.stringify(chunk),
                    existingBatchId: batchId,
                    finalize: isLast,
                    chunkIndex: c,
                    totalChunks
                });
                batchId = result.batchId;
                this.importMessage = `Processed ${Math.min(start + CHUNK_SIZE, total)} / ${total}. ${result.message}`;
                if (isLast && result.status === 'Failed') {
                    throw new Error(result.message);
                }
            }
            this.toast('Import queued', this.importMessage, 'success');
            this.loadBatchRows();
            this.loadProductRows();
            this.activeTab = 'batches';
        } catch (e) {
            const reason = this.reduceError(e);
            if (batchId) {
                // Never leave a half-uploaded batch in "Uploading".
                try {
                    await markImportBatchFailed({ batchId, reason: `Upload failed in the browser: ${reason}` });
                } catch (markError) { // eslint-disable-line no-unused-vars
                    // the sweeper will fail it if this call also cannot reach Salesforce
                }
                this.loadBatchRows();
            }
            this.toast('Import failed', reason, 'error');
        } finally {
            this.isImporting = false;
        }
    }

    handleImportMaxRowsChange(event) {
        this.importMaxRows = Number(event.target.value) || 0;
    }

    handlePreferAddressedToggle(event) {
        this.preferAddressedRows = event.target.checked;
    }

    handleGoogleApiKeyChange(event) {
        this.googleApiKeyInput = event.target.value;
    }

    async handleSaveGeocodeKey() {
        this.isSavingGeocode = true;
        try {
            this.geocodeStatus = await saveGeocodeApiKey({ apiKey: this.googleApiKeyInput });
            this.googleApiKeyInput = '';
            this.toast('Geocode config', this.geocodeReadyMessage, 'success');
        } catch (e) {
            this.toast('Geocode config', this.reduceError(e), 'error');
        } finally {
            this.isSavingGeocode = false;
        }
    }

    resolveProductQueryFilters() {
        let distributorCode = this.distributorCode || null;
        let productLineFilter = this.productLineFilter || null;

        if (this.productGroupMode === 'distributor' && this.productNavKey) {
            distributorCode = this.productNavKey;
        }
        if (this.productGroupMode === 'productLine' && this.productNavKey) {
            productLineFilter = this.productNavKey;
        }

        return { distributorCode, productLineFilter };
    }

    async loadProductRows() {
        try {
            const { distributorCode, productLineFilter } = this.resolveProductQueryFilters();
            const [rows, nav] = await Promise.all([
                getProductAliases({
                    distributorCode,
                    statusFilter: this.productStatusFilter || null,
                    unmappedOnly: this.productUnmappedOnly,
                    limitSize: 1000,
                    productLineFilter,
                    searchTerm: this.productSearch || null
                }),
                getProductMappingNav({
                    distributorCode: this.distributorCode || null,
                    statusFilter: this.productStatusFilter || null,
                    unmappedOnly: this.productUnmappedOnly
                })
            ]);
            this.productNav = nav || { distributors: [], productLines: [] };
            this.productRows = (rows || []).map((row) => ({
                ...row,
                productFamily: row.productFamily || 'Unassigned',
                productUrl: row.productUrl || (row.productId ? `/${row.productId}` : null),
                productName: row.productName || (row.productId ? 'Open product' : '')
            }));
            this.productDrafts = [];
            this.resetProductPage();
        } catch (e) {
            this.toast('Product aliases', this.reduceError(e), 'error');
        }
    }

    handleProductGroupModeChange(event) {
        this.productGroupMode = event.detail.value;
        this.productNavKey = '';
        this.resetProductPage();
        this.loadProductRows();
    }

    handleProductNavClick(event) {
        this.productNavKey = event.currentTarget.dataset.key || '';
        this.resetProductPage();
        this.loadProductRows();
    }

    handleProductLineFilterChange(event) {
        this.productLineFilter = event.detail.value || '';
        if (this.productGroupMode === 'productLine') {
            this.productNavKey = this.productLineFilter;
        }
        this.resetProductPage();
        this.loadProductRows();
    }

    handleProductFilterChange(event) {
        this.productStatusFilter = event.detail.value;
        this.resetProductPage();
        this.loadProductRows();
    }

    handleProductUnmappedToggle(event) {
        this.productUnmappedOnly = event.target.checked;
        this.resetProductPage();
        this.loadProductRows();
    }

    handleProductSearchChange(event) {
        this.productSearch = event.target.value || '';
        // eslint-disable-next-line @lwc/lwc/no-async-operation
        window.clearTimeout(this.productSearchTimer);
        // eslint-disable-next-line @lwc/lwc/no-async-operation
        this.productSearchTimer = window.setTimeout(() => {
            this.resetProductPage();
            this.loadProductRows();
        }, 300);
    }

    handleProductPageSizeChange(event) {
        this.productPageSize = Number(event.detail.value) || 50;
        this.resetProductPage();
    }

    handleProductPrevPage() {
        if (this.productPage > 1) {
            this.productPage -= 1;
        }
    }

    handleProductNextPage() {
        if (this.productPage < this.productTotalPages) {
            this.productPage += 1;
        }
    }

    handleProductCellChange(event) {
        this.productDrafts = event.detail.draftValues || [];
    }

    handleCancelProductDrafts() {
        this.productDrafts = [];
        const table = this.template.querySelector('lightning-datatable');
        if (table) {
            table.draftValues = [];
        }
    }

    async handleSaveProductDrafts(event) {
        const drafts = event?.detail?.draftValues || this.productDrafts || [];
        if (!drafts.length) {
            return;
        }
        this.isSavingProducts = true;
        try {
            const n = await saveProductAliasDrafts({ draftsJson: JSON.stringify(drafts) });
            this.toast('Saved', `Updated ${n} product mapping(s).`, 'success');
            this.productDrafts = [];
            const table = this.template.querySelector('lightning-datatable');
            if (table) {
                table.draftValues = [];
            }
            await this.loadProductRows();
        } catch (e) {
            this.toast('Save failed', this.reduceError(e), 'error');
        } finally {
            this.isSavingProducts = false;
        }
    }

    async handleBulkConfirmProducts() {
        try {
            const { distributorCode } = this.resolveProductQueryFilters();
            const n = await bulkConfirmProductAliases({
                minConfidence: 90,
                distributorCode
            });
            this.toast('Bulk confirm', `Confirmed ${n} aliases with 90%+ confidence.`, 'success');
            this.loadProductRows();
        } catch (e) {
            this.toast('Bulk confirm failed', this.reduceError(e), 'error');
        }
    }

    async loadSelloutRows() {
        try {
            this.selloutOffset = 0;
            this.selloutRows = await getSelloutAliases({
                distributorCode: this.distributorCode || null,
                statusFilter: this.selloutStatusFilter || null,
                needsReviewOnly: this.selloutNeedsReview,
                limitSize: this.selloutPageSize
            });
            this.renderMarkers();
        } catch (e) {
            this.toast('Sellout aliases', this.reduceError(e), 'error');
        }
    }

    async handleLoadMoreSellouts() {
        try {
            this.selloutOffset += this.selloutPageSize;
            const more = await getSelloutAliasesPage({
                distributorCode: this.distributorCode || null,
                statusFilter: this.selloutStatusFilter || null,
                needsReviewOnly: this.selloutNeedsReview,
                limitSize: this.selloutPageSize,
                offsetSize: this.selloutOffset
            });
            this.selloutRows = [...(this.selloutRows || []), ...(more || [])];
            this.renderMarkers();
        } catch (e) {
            this.toast('Sellout page', this.reduceError(e), 'error');
        }
    }

    handleSelloutFilterChange(event) {
        this.selloutStatusFilter = event.detail.value;
        this.loadSelloutRows();
    }

    handleSelloutReviewToggle(event) {
        this.selloutNeedsReview = event.target.checked;
        this.loadSelloutRows();
    }

    handleSelloutRowSelection(event) {
        const selected = event.detail.selectedRows?.[0];
        this.selectedSelloutId = selected?.recordId;
        this.focusMarker(selected);
    }

    handleOpenSelectedAlias() {
        const url = this.selectedSelloutRecordUrl;
        if (url) {
            window.open(url, '_blank');
        }
    }

    handleOpenSelectedPharmacy() {
        const url = this.selectedSelloutPharmacyUrl;
        if (url) {
            window.open(url, '_blank');
        }
    }

    async handlePharmacySearch(event) {
        this.pharmacySearch = event.target.value;
        if ((this.pharmacySearch || '').length < 2) {
            this.pharmacyOptions = [];
            return;
        }
        this.pharmacyOptions = await searchPharmacies({ searchTerm: this.pharmacySearch });
    }

    handlePharmacyOptionChange(event) {
        this.selectedPharmacyId = event.detail.value;
    }

    async handleLinkPharmacy() {
        if (!this.selectedSelloutId) {
            this.toast('Sellout', 'Select a sellout row.', 'warning');
            return;
        }
        if (!this.selectedPharmacyId) {
            this.toast('Sellout', 'Pick the pharmacy to link this sellout point to first.', 'warning');
            return;
        }
        try {
            await updateSelloutAlias({
                aliasId: this.selectedSelloutId,
                pharmacyId: this.selectedPharmacyId,
                status: 'Confirmed',
                confidence: 100,
                createPharmacy: false
            });
            this.toast('Linked', 'Sellout linked to pharmacy.', 'success');
            this.loadSelloutRows();
        } catch (e) {
            this.toast('Link failed', this.reduceError(e), 'error');
        }
    }

    async handleCreatePharmacy() {
        if (!this.selectedSelloutId) return;
        try {
            await updateSelloutAlias({
                aliasId: this.selectedSelloutId,
                pharmacyId: null,
                status: 'Confirmed',
                confidence: 100,
                createPharmacy: true
            });
            this.toast('Created', 'Pharmacy account created and linked.', 'success');
            this.loadSelloutRows();
        } catch (e) {
            this.toast('Create failed', this.reduceError(e), 'error');
        }
    }

    async handleRejectSellout() {
        if (!this.selectedSelloutId) return;
        try {
            await updateSelloutAlias({
                aliasId: this.selectedSelloutId,
                pharmacyId: null,
                status: 'Rejected',
                confidence: 0,
                createPharmacy: false
            });
            this.toast('Rejected', 'Sellout alias rejected.', 'success');
            this.loadSelloutRows();
        } catch (e) {
            this.toast('Reject failed', this.reduceError(e), 'error');
        }
    }

    async handleRematchSellouts() {
        const code = (this.selectedSellout && this.selectedSellout.distributorCode) || this.distributorCode || 'IBNSINA';
        try {
            const res = await rematchSellouts({ distributorCode: code, limitSize: 200 });
            const variant = res.errors ? 'warning' : res.confirmed || res.suggested ? 'success' : 'info';
            this.toast(`Re-match ${code}`, res.message, variant);
            await this.loadSelloutRows();
        } catch (e) {
            this.toast('Re-match failed', this.reduceError(e), 'error');
        }
    }

    async handleMergeSellout() {
        if (!this.selectedSelloutId || !this.selectedPharmacyId) {
            this.toast('Merge', 'Select a sellout row and a target pharmacy.', 'warning');
            return;
        }
        try {
            await mergeSelloutAliases({
                sourceAliasId: this.selectedSelloutId,
                targetPharmacyId: this.selectedPharmacyId
            });
            this.toast('Merged', 'Alias mapped onto target pharmacy.', 'success');
            this.loadSelloutRows();
        } catch (e) {
            this.toast('Merge failed', this.reduceError(e), 'error');
        }
    }

    async initMap() {
        const container = this.template.querySelector('.sellout-map');
        if (!container) return;
        try {
            const leaflet = await ensureLeaflet(this, LEAFLET);
            await loadStyle(this, `${LEAFLET}/leaflet.css`);
            this.leafletReady = true;
            if (this.map) {
                this.map.remove();
                this.map = null;
            }
            this.map = leaflet.map(container).fitBounds(EGYPT_BOUNDS);
            addOsmTileLayer(this.map, leaflet);
            this.markersLayer = leaflet.layerGroup().addTo(this.map);
            this.renderMarkers();
            // eslint-disable-next-line @lwc/lwc/no-async-operation
            setTimeout(() => this.map.invalidateSize(), 100);
        } catch (e) {
            this.toast('Map', this.reduceError(e), 'error');
        }
    }

    renderMarkers() {
        if (!this.map || !this.markersLayer || !globalThis.L) return;
        const leaflet = globalThis.L;
        this.markersLayer.clearLayers();
        const bounds = [];
        for (const row of this.selloutRows) {
            if (row.latitude == null || row.longitude == null) continue;
            const color = STATUS_COLORS[row.status] || '#0176d3';
            const marker = leaflet.circleMarker([row.latitude, row.longitude], {
                radius: 7,
                color,
                fillColor: color,
                fillOpacity: 0.85
            });
            marker.bindPopup(popupHtml(row));
            marker.on('click', () => {
                this.selectedSelloutId = row.recordId;
            });
            marker.addTo(this.markersLayer);
            bounds.push([row.latitude, row.longitude]);
        }
        // Fit to the markers inside Egypt; a stray geocode elsewhere must not zoom the map out to the world.
        this.map.fitBounds(fitBoundsFor(bounds), { padding: [24, 24], maxZoom: 14 });
    }

    focusMarker(row) {
        if (!this.map || !row || row.latitude == null) return;
        this.map.setView([row.latitude, row.longitude], 15);
    }

    async loadBatchRows() {
        try {
            const rows = await getImportBatches({ limitSize: 50 });
            this.batchRows = (rows || []).map((row) => ({
                ...row,
                chunkLabel:
                    row.chunksExpected != null
                        ? `${row.chunksProcessed || 0} / ${row.chunksExpected}`
                        : row.chunksProcessed
                          ? String(row.chunksProcessed)
                          : '',
                logTail: this.lastLogLine(row.errorLog)
            }));
        } catch (e) {
            this.toast('Batches', this.reduceError(e), 'error');
        }
    }

    async openLoad(batchId) {
        this.isLoadingReview = true;
        this.loadReview = undefined;
        try {
            const r = await getLoadReview({ batchId });
            const fmt = (n) => new Intl.NumberFormat('en-US', { maximumFractionDigits: 2 }).format(Number(n || 0));
            this.loadReview = {
                ...r,
                title: `${r.batchName} · ${r.distributorCode || ''} · ${r.fileName || ''}`,
                summary:
                    `${fmt(r.rowsScanned)} rows read: ${fmt(r.rowsMatched)} matched, ${fmt(r.rowsUnmatched)} unmatched` +
                    (r.rowsRejectedAtUpload ? `, ${fmt(r.rowsRejectedAtUpload)} rejected at upload (no item or client code)` : '') +
                    `. ${fmt(r.matchedLineCount)} sales lines written.`,
                matchedLines: (r.matchedLines || []).map((l) => ({ ...l, tenderLabel: l.isTender ? 'Tender' : '' })),
                unmatchedGroups: r.unmatchedGroups || [],
                hasMatched: Boolean(r.matchedLines && r.matchedLines.length),
                hasUnmatched: Boolean(r.unmatchedGroups && r.unmatchedGroups.length),
                matchedMore: r.matchedLineCount > (r.matchedLines || []).length,
                fallbackNote: r.stagedRowsMissing
                    ? "This load's staged rows are no longer stored, so the list shows its unmatched clients and the distributor's unconfirmed products (no row counts)."
                    : ''
            };
        } catch (e) {
            this.toast('Open load', this.reduceError(e), 'error');
        } finally {
            this.isLoadingReview = false;
        }
    }

    handleCloseLoadReview() {
        this.loadReview = undefined;
    }

    matchedLineColumns = [
        { label: 'Pharmacy', fieldName: 'pharmacy', type: 'text', wrapText: true },
        { label: 'Brick', fieldName: 'brick', type: 'text' },
        { label: 'Product', fieldName: 'product', type: 'text', wrapText: true },
        { label: 'Qty', fieldName: 'quantity', type: 'number', initialWidth: 90 },
        { label: 'Revenue', fieldName: 'revenue', type: 'currency', typeAttributes: { currencyCode: 'EGP' } },
        { label: 'Tender', fieldName: 'tenderLabel', type: 'text', initialWidth: 80 }
    ];

    unmatchedColumns = [
        { label: 'Reason', fieldName: 'reason', type: 'text', wrapText: true },
        { label: 'Code', fieldName: 'code', type: 'text', initialWidth: 120 },
        { label: 'Name in file', fieldName: 'name', type: 'text', wrapText: true },
        { label: 'Rows', fieldName: 'rows', type: 'number', initialWidth: 80 },
        { label: 'Qty', fieldName: 'quantity', type: 'number', initialWidth: 90 },
        { label: 'How to fix', fieldName: 'fix', type: 'text', wrapText: true }
    ];

    lastLogLine(log) {
        if (!log) return '';
        const lines = String(log)
            .split('\n')
            .map((l) => l.trim())
            .filter(Boolean);
        return (lines[lines.length - 1] || '').slice(0, 160);
    }

    getBatchRowActions(row, doneCallback) {
        const actions = [{ label: 'Open load', name: 'open' }];
        if (row.canResume) {
            actions.push({ label: 'Resume', name: 'resume' });
            actions.push({ label: 'Re-queue', name: 'requeue' });
        }
        if (row.canFail) {
            actions.push({ label: 'Mark failed', name: 'markFailed' });
        }
        doneCallback(actions);
    }

    async handleBatchRowAction(event) {
        const action = event.detail.action.name;
        const row = event.detail.row;
        if (!row || action === 'none') return;
        if (action === 'open') {
            await this.openLoad(row.batchId);
            return;
        }
        try {
            let result;
            if (action === 'resume') {
                result = await resumeImportBatch({ batchId: row.batchId });
            } else if (action === 'requeue') {
                result = await requeueImportBatch({ batchId: row.batchId });
            } else if (action === 'markFailed') {
                result = await markImportBatchFailed({ batchId: row.batchId, reason: 'Marked failed by an admin.' });
            } else {
                return;
            }
            this.toast(row.batchName || 'Batch', result?.message || 'Done.', 'success');
        } catch (e) {
            this.toast('Batch action failed', this.reduceError(e), 'error');
        }
        await this.loadBatchRows();
    }

    async loadAccuracy() {
        try {
            this.accuracy = await getMappingAccuracy({
                distributorCode: this.distributorCode || null
            });
        } catch (e) {
            this.accuracy = null;
        }
    }

    handleDoctorSearchChange(event) {
        this.doctorSearch = event.target.value;
    }

    async handleDoctorSearch() {
        try {
            this.doctorOptions = (await searchRatedDoctors({ searchTerm: this.doctorSearch })) || [];
            if (this.doctorOptions.length === 1) {
                await this.loadShareReview(this.doctorOptions[0].doctorId);
            }
        } catch (e) {
            this.toast('Doctor search', this.reduceError(e), 'error');
        }
    }

    async handlePickDoctor(event) {
        await this.loadShareReview(event.currentTarget.dataset.doctorId);
    }

    async loadShareReview(doctorId) {
        try {
            this.shareReview = await getDoctorShareReview({ doctorId });
            this.shareDrafts = (this.shareReview?.pharmacies || []).map((row) => ({ ...row }));
        } catch (e) {
            this.toast('Nearby share', this.reduceError(e), 'error');
        }
    }

    async handleRefreshShares() {
        if (!this.shareReview?.doctorId) return;
        this.isSavingShares = true;
        try {
            this.shareReview = await refreshNearbyShares({ doctorId: this.shareReview.doctorId });
            this.shareDrafts = (this.shareReview?.pharmacies || []).map((row) => ({ ...row }));
            this.toast('Nearby pharmacies', this.shareReview.message, 'success');
        } catch (e) {
            this.toast('Nearby pharmacies', this.reduceError(e), 'error');
        } finally {
            this.isSavingShares = false;
        }
    }

    handleShareChange(event) {
        const affiliationId = event.target.dataset.affiliationId;
        const value = event.target.value;
        this.shareDrafts = this.shareDrafts.map((row) =>
            row.affiliationId === affiliationId ? { ...row, orderSharePercent: value } : row
        );
    }

    async handleSaveShares() {
        if (!this.shareReview?.doctorId) return;
        this.isSavingShares = true;
        try {
            const sharesJson = JSON.stringify(
                this.shareDrafts.map((row) => ({
                    affiliationId: row.affiliationId,
                    orderSharePercent: Number(row.orderSharePercent)
                }))
            );
            this.shareReview = await saveOrderShares({
                doctorId: this.shareReview.doctorId,
                sharesJson
            });
            this.shareDrafts = (this.shareReview?.pharmacies || []).map((row) => ({ ...row }));
            this.toast('Order share', 'Shares saved. They add up to 100%.', 'success');
        } catch (e) {
            this.toast('Order share', this.reduceError(e), 'error');
        } finally {
            this.isSavingShares = false;
        }
    }

    toast(title, message, variant) {
        this.dispatchEvent(new ShowToastEvent({ title, message, variant }));
    }

    reduceError(error) {
        if (!error) return 'Unknown error';
        if (Array.isArray(error.body)) {
            return error.body.map((e) => e.message).join(', ');
        }
        return error.body?.message || error.message || String(error);
    }
}