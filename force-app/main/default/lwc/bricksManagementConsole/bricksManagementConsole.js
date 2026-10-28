import { LightningElement } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import LightningConfirm from 'lightning/confirm';
import BRICK_MAP_HOST from '@salesforce/resourceUrl/brickMapHost';
import LEAFLET from '@salesforce/resourceUrl/leaflet';
import getBrickMap from '@salesforce/apex/BricksManagementController.getBrickMap';
import getSalesPoints from '@salesforce/apex/BricksManagementController.getSalesPoints';
import saveBrickDetails from '@salesforce/apex/BricksManagementController.saveBrickDetails';
import saveBrickRegion from '@salesforce/apex/BricksManagementController.saveBrickRegion';
import locatePoint from '@salesforce/apex/BricksManagementController.locatePoint';
import startSalesPlacement from '@salesforce/apex/BricksManagementController.startSalesPlacement';
import getSalesPlacementStatus from '@salesforce/apex/BricksManagementController.getSalesPlacementStatus';
import getBrickTerritories from '@salesforce/apex/BricksManagementController.getBrickTerritories';
import removeBrickTerritory from '@salesforce/apex/BricksManagementController.removeBrickTerritory';
import assignBrickToTerritory from '@salesforce/apex/BricksManagementController.assignBrickToTerritory';
import getBrickPharmacies from '@salesforce/apex/BricksManagementController.getBrickPharmacies';
import searchPharmacyOptions from '@salesforce/apex/BricksManagementController.searchPharmacyOptions';
import addPharmacyToBrick from '@salesforce/apex/BricksManagementController.addPharmacyToBrick';
import removePharmacyFromBrick from '@salesforce/apex/BricksManagementController.removePharmacyFromBrick';
import deleteBrick from '@salesforce/apex/BricksManagementController.deleteBrick';
import suggestRegionFromName from '@salesforce/apex/BricksManagementController.suggestRegionFromName';
import applyImsOutlines from '@salesforce/apex/BricksManagementController.applyImsOutlines';
import getBrickClients from '@salesforce/apex/BricksManagementController.getBrickClients';
import getTerritoryTree from '@salesforce/apex/TerritoryManagementController.getTerritoryTree';
import getSalesFilters from '@salesforce/apex/BrickSalesMapController.getSalesFilters';
import getSalesChunk from '@salesforce/apex/BrickSalesMapController.getSalesChunk';
import getBrickSales from '@salesforce/apex/BrickSalesMapController.getBrickSales';
import getUnplacedSales from '@salesforce/apex/BrickSalesMapController.getUnplacedSales';
import getDistributorCounts from '@salesforce/apex/BrickSalesMapController.getDistributorCounts';

const MAP_TIMEOUT_MS = 20000;
const JOB_POLL_MS = 5000;
const CLIENT_LIST_LIMIT = 50;
const DATA_SOURCE_OPTIONS = [
    { label: 'IQVIA IMS', value: 'IQVIA IMS' },
    { label: 'IbnSina', value: 'IbnSina' },
    { label: 'Pharmaoverseas', value: 'Pharmaoverseas' }
];
const FILTERS = [
    { value: 'all', label: 'All' },
    { value: 'mapped', label: 'With region' },
    { value: 'unmapped', label: 'No region' },
    { value: 'inactive', label: 'Inactive' }
];
const PLACEMENT_CLASS = {
    'In region': 'bm-pill bm-pill_ok',
    'Nearest region': 'bm-pill bm-pill_near',
    'Approximate location': 'bm-pill bm-pill_warn',
    'Outside regions': 'bm-pill bm-pill_bad',
    'No location': 'bm-pill'
};
const LEVEL_LABELS = { 702: '702 micro brick', 148: '148 brick', 70: '70 area' };
const ALL = 'ALL';
// A month is too many rows for one SUM, so sales are read in chunks of products of about this many lines,
// this many chunks at a time.
const SALES_CHUNK_ROWS = 20000;
const SALES_CONCURRENCY = 4;
const TOP_PRODUCTS = 10;
const SALES_PRODUCT_LIMIT = 15;
const SALES_CLIENT_LIMIT = 20;
const UNPLACED_LIMIT = 100;

export function reduceError(error) {
    if (Array.isArray(error?.body)) {
        return error.body.map((item) => item.message).join(', ');
    }
    return error?.body?.message || error?.message || 'Something went wrong.';
}

export function normalizeText(value) {
    return (value || '').toString().trim().toLowerCase();
}

export function formatMonth(iso) {
    return iso ? new Date(`${iso}T00:00:00`).toLocaleDateString(undefined, { month: 'long', year: 'numeric' }) : '';
}

export function currentMonthIso(today = new Date()) {
    return `${today.getFullYear()}-${String(today.getMonth() + 1).padStart(2, '0')}-01`;
}

/** '2026-08-01' -> '2026-Q3' */
export function quarterOf(iso) {
    return `${iso.slice(0, 4)}-Q${Math.floor((Number(iso.slice(5, 7)) - 1) / 3) + 1}`;
}

/** '2026-Q3' -> ['2026-07-01', '2026-09-01'] */
export function quarterRange(key) {
    const year = key.slice(0, 4);
    const first = (Number(key.slice(-1)) - 1) * 3 + 1;
    const pad = (m) => String(m).padStart(2, '0');
    return [`${year}-${pad(first)}-01`, `${year}-${pad(first + 2)}-01`];
}

export function formatRange(start, end) {
    if (!start) return '';
    if (!end || start === end) return formatMonth(start);
    const short = (iso) => new Date(`${iso}T00:00:00`).toLocaleDateString(undefined, { month: 'short' });
    if (start.slice(0, 4) === end.slice(0, 4)) return `${short(start)} – ${short(end)} ${end.slice(0, 4)}`;
    return `${short(start)} ${start.slice(0, 4)} – ${short(end)} ${end.slice(0, 4)}`;
}

function emptyTotals() {
    return { lines: 0, quantity: 0, revenue: 0 };
}

function addTotals(into, t) {
    into.lines += t.lines || 0;
    into.quantity += Number(t.quantity || 0);
    into.revenue += Number(t.revenue || 0);
    return into;
}

export function compact(value) {
    return Number(value || 0).toLocaleString(undefined, { notation: 'compact', maximumFractionDigits: 1 });
}

function whole(value) {
    return Number(value || 0).toLocaleString(undefined, { maximumFractionDigits: 0 });
}

function plain(value) {
    return value == null ? value : JSON.parse(JSON.stringify(value));
}

function emptyDraft(level, parentId) {
    return {
        recordId: null,
        level,
        name: '',
        code: '',
        parentId: parentId || null,
        governorate: '',
        city: '',
        dataSource: 'IQVIA IMS',
        isActive: true,
        accountSelectable: true
    };
}

export default class BricksManagementConsole extends LightningElement {
    level = '702';
    data;
    points = [];
    loading = true;
    loadError;
    search = '';
    filter = 'all';
    selectedId;
    draft;
    draftDirty = false;
    savingDetails = false;
    job;

    mapSrc = `${BRICK_MAP_HOST}/index.html`;
    frameLoaded = false;
    mapReady = false;
    mapError;
    editingId;
    showPoints = true;

    pharmacies = [];
    brickClients;
    pharmacyTerm = '';
    pharmacyOptions = [];
    selectedPharmacyId;
    territories = [];
    territoryOptions = [];
    selectedTerritoryId;

    showNewModal = false;
    newDraft = emptyDraft('702');
    creating = false;
    showImport = false;
    importText = '';
    applying = false;
    suggesting = false;
    generating = false;

    dataSourceOptions = DATA_SOURCE_OPTIONS;

    view = 'regions';
    salesFilters;
    salesSource = ALL;
    salesStart;
    salesEnd;
    salesNotice = '';
    salesData;
    salesProduct = ALL;
    salesMetric = 'revenue';
    salesTab = 'placed';
    salesProgress;
    salesError;
    brickSales;
    unplacedSales;
    unplacedError;
    unplacedLoading = false;
    _salesSeq = 0;
    _brickSalesSeq = 0;
    _unplacedSeq = 0;
    _salesCache = new Map();
    distributorCounts;
    _countsSeq = 0;
    _countsCache = new Map();

    _boundMessage;
    _mapTimer;
    _jobTimer;
    _pharmacySearchTimer;

    connectedCallback() {
        this._boundMessage = this.handleFrameMessage.bind(this);
        window.addEventListener('message', this._boundMessage);
        this.loadMap({ fit: true });
        this.loadTerritoryOptions();
    }

    disconnectedCallback() {
        window.removeEventListener('message', this._boundMessage);
        clearTimeout(this._mapTimer);
        clearTimeout(this._jobTimer);
        clearTimeout(this._pharmacySearchTimer);
        this.post({ type: 'HOST_DESTROY' });
    }

    // ---------- data ----------

    async loadMap({ fit = false } = {}) {
        this.loading = !this.data;
        try {
            const [data, points] = await Promise.all([getBrickMap({ level: this.level }), getSalesPoints()]);
            this.data = data;
            this.points = points || [];
            this.job = data.job;
            this.loadError = undefined;
            const selected = this.findBrick(this.selectedId);
            if (this.selectedId && !selected) {
                this.clearSelection();
            } else if (selected && !this.draftDirty) {
                this.draft = this.toDraft(selected);
            }
        } catch (error) {
            this.loadError = reduceError(error);
        }
        this.loading = false;
        if (this.mapReady) {
            this.post({ type: 'HOST_UPDATE', ...this.mapPayload(), fit });
        } else {
            this.initMap();
        }
        this.scheduleJobPoll();
    }

    async loadTerritoryOptions() {
        try {
            const roots = await getTerritoryTree();
            const options = [];
            const walk = (nodes, depth) => {
                (nodes || []).forEach((node) => {
                    options.push({ label: `${'— '.repeat(depth)}${node.name}`, value: node.id });
                    walk(node.children, depth + 1);
                });
            };
            walk(roots, 0);
            this.territoryOptions = options;
        } catch {
            this.territoryOptions = [];
        }
    }

    findBrick(id) {
        return id && this.data ? (this.data.bricks || []).find((b) => b.id === id) : undefined;
    }

    get stats() {
        return (this.data && this.data.stats) || {};
    }

    get canEdit() {
        return !!(this.data && this.data.canEdit);
    }

    get cannotEdit() {
        return !this.canEdit;
    }

    // ---------- header ----------

    get levelButtons() {
        return ['702', '148'].map((value) => ({
            value,
            label: value === '702' ? '702 micro bricks' : '148 bricks',
            className: `bm-seg-btn${this.level === value ? ' is-on' : ''}`,
            pressed: this.level === value ? 'true' : 'false'
        }));
    }

    get mapped702Label() {
        return `${this.stats.mapped702 || 0} / ${this.stats.total702 || 0}`;
    }

    get mapped148Label() {
        return `${this.stats.mapped148 || 0} / ${this.stats.total148 || 0}`;
    }

    get clientsLabel() {
        const fmt = (n) => (n || 0).toLocaleString();
        return `${fmt(this.stats.clientsPlaced)} / ${fmt(this.stats.clientsTotal)}`;
    }

    get clientsTitle() {
        const s = this.stats;
        return `Distributor clients: ${s.clientsPlaced || 0} placed in a brick (${s.clientsWithLocation || 0} of all clients have a map point), ${s.clientsApproximate || 0} with only a town or governorate location, ${s.clientsOutside || 0} outside all regions, ${s.clientsNoLocation || 0} with no location — their sales are skipped at import.`;
    }

    get hasApproximate() {
        return (this.stats.clientsApproximate || 0) > 0;
    }

    get jobRunning() {
        return !!(this.job && this.job.running);
    }

    get applyLabel() {
        if (this.jobRunning) {
            const { processed, total } = this.job;
            return total ? `Applying… ${processed || 0} / ${total}` : 'Applying…';
        }
        return 'Apply regions to sales';
    }

    get applyDisabled() {
        return this.cannotEdit || this.applying || this.jobRunning;
    }

    get generateDisabled() {
        return this.cannotEdit || this.generating || this.jobRunning || !!this.editingId;
    }

    get suggestDisabled() {
        return this.regionActionsDisabled || this.suggesting;
    }

    get showApplyBanner() {
        const changed = this.stats.lastRegionChange;
        if (!changed || this.jobRunning) return false;
        if (!this.job || !this.job.createdDate) return true;
        return new Date(changed) > new Date(this.job.createdDate);
    }

    handleLevel(event) {
        const value = event.currentTarget.dataset.value;
        if (value === this.level) return;
        if (this.editingId) {
            this.toast('warning', 'Save or cancel the region you are editing first.');
            return;
        }
        this.level = value;
        this.clearSelection();
        this.post({ type: 'HOST_SELECT', id: null, fly: false });
        this.loadMap({ fit: true });
        if (this.isSalesView) this.refreshSales();
    }

    async handleApply() {
        this.applying = true;
        try {
            this.job = await startSalesPlacement();
            this.toast('success', 'Applying the regions to distributor clients and sales lines in the background.');
            this.scheduleJobPoll();
        } catch (error) {
            this.toast('error', reduceError(error));
        }
        this.applying = false;
    }

    scheduleJobPoll() {
        clearTimeout(this._jobTimer);
        if (!this.jobRunning) return;
        // eslint-disable-next-line @lwc/lwc/no-async-operation
        this._jobTimer = setTimeout(() => this.pollJob(), JOB_POLL_MS);
    }

    async pollJob() {
        try {
            const job = await getSalesPlacementStatus();
            const finished = this.jobRunning && job && !job.running;
            this.job = job;
            if (finished) {
                this.toast(job.status === 'Completed' ? 'success' : 'warning', job.status === 'Completed' ? 'Sales lines now follow the brick regions.' : `The placement job ended as ${job.status}.`);
                this.loadMap();
                return;
            }
        } catch {
            return;
        }
        this.scheduleJobPoll();
    }

    // ---------- list ----------

    get filterChips() {
        return FILTERS.map((f) => ({ ...f, className: `bm-chip-btn${this.filter === f.value ? ' is-on' : ''}` }));
    }

    get listRows() {
        const term = normalizeText(this.search);
        const totals = this.isSalesView ? this.brickTotals : undefined;
        const metric = this.salesMetric;
        const rows = (this.data ? this.data.bricks || [] : [])
            .filter((b) => {
                if (this.filter === 'mapped' && !b.geometry) return false;
                if (this.filter === 'unmapped' && b.geometry) return false;
                if (this.filter === 'inactive' && b.isActive !== false) return false;
                if (!term) return true;
                return [b.name, b.code, b.parentName, b.governorate, b.city].some((v) => normalizeText(v).includes(term));
            })
            .map((b) => ({
                id: b.id,
                name: b.name,
                meta: (totals && this.brickSourceText(b.id)) || [b.code && b.code !== b.name ? b.code : null, b.parentName].filter(Boolean).join(' · '),
                regionLabel: b.geometry ? `${this.formatArea(b.areaKm2)} km²` : 'No region',
                regionClass: b.geometry ? 'bm-tag bm-tag_ok' : 'bm-tag bm-tag_empty',
                clients: totals ? 0 : b.clientCount || 0,
                inactive: b.isActive === false,
                salesValue: totals && totals[b.id] ? Number(totals[b.id][metric] || 0) : 0,
                salesLabel: totals ? this.salesValueLabel(totals[b.id]) : null,
                salesClass: totals && totals[b.id] ? 'bm-tag bm-tag_sales' : 'bm-tag bm-tag_off',
                className: `bm-row${b.id === this.selectedId ? ' is-on' : ''}${b.isActive === false ? ' is-off' : ''}`
            }));
        return totals ? rows.sort((x, y) => y.salesValue - x.salesValue) : rows;
    }

    get hasRows() {
        return this.listRows.length > 0;
    }

    get emptyListMessage() {
        if (!normalizeText(this.search)) {
            if (this.filter === 'unmapped') return 'Every brick at this level has a region.';
            if (this.filter === 'inactive') return 'No inactive bricks at this level.';
            if (this.filter === 'mapped') return 'No brick at this level has a region yet.';
        }
        return 'No bricks match.';
    }

    get listCaption() {
        const total = this.data ? (this.data.bricks || []).length : 0;
        const shown = this.listRows.length;
        return shown === total ? `${total} bricks` : `${shown} of ${total} bricks`;
    }

    handleSearch(event) {
        this.search = event.target.value || '';
    }

    handleFilter(event) {
        this.filter = event.currentTarget.dataset.value;
    }

    handleRowSelect(event) {
        this.selectBrick(event.currentTarget.dataset.id, false);
    }

    // ---------- selection & details ----------

    get selected() {
        return this.findBrick(this.selectedId);
    }

    get hasSelection() {
        return !!this.selected;
    }

    get bodyClass() {
        return `bm-body${this.hasSelection ? ' bm-body_detail' : ''}`;
    }

    selectBrick(id, fromMap) {
        if (id === this.selectedId) {
            if (!fromMap) this.post({ type: 'HOST_SELECT', id, fly: true });
            return;
        }
        if (this.editingId) {
            this.toast('warning', 'Save or cancel the region you are editing first.');
            this.post({ type: 'HOST_SELECT', id: this.selectedId, fly: false });
            return;
        }
        const brick = this.findBrick(id);
        if (!brick) return;
        this.selectedId = id;
        this.draft = this.toDraft(brick);
        this.draftDirty = false;
        this.pharmacies = [];
        this.territories = [];
        this.brickClients = undefined;
        this.selectedPharmacyId = undefined;
        this.selectedTerritoryId = undefined;
        if (!fromMap) this.post({ type: 'HOST_SELECT', id, fly: true });
        this.loadLinks(id);
        this.loadBrickSales(id);
    }

    clearSelection() {
        this.selectedId = undefined;
        this.draft = undefined;
        this.draftDirty = false;
        this.pharmacies = [];
        this.territories = [];
        this.brickClients = undefined;
        this.brickSales = undefined;
    }

    handleCloseDetail() {
        if (this.editingId) {
            this.toast('warning', 'Save or cancel the region you are editing first.');
            return;
        }
        this.clearSelection();
        this.post({ type: 'HOST_SELECT', id: null, fly: false });
    }

    async loadLinks(id) {
        this.loadClients(id);
        try {
            const [pharmacies, territories] = await Promise.all([getBrickPharmacies({ brickId: id }), getBrickTerritories({ brickId: id })]);
            if (id !== this.selectedId) return;
            this.pharmacies = pharmacies || [];
            this.territories = (territories || []).map((t) => ({ ...t, shareLabel: t.share != null ? `${Math.round(Number(t.share) * 100)}%` : '' }));
        } catch (error) {
            if (id === this.selectedId) this.toast('error', reduceError(error));
        }
    }

    async loadClients(id) {
        try {
            const result = await getBrickClients({ brickId: id, level: this.level });
            if (id === this.selectedId) this.brickClients = result || null;
        } catch {
            // The geocoded map points stay as the fallback list.
            if (id === this.selectedId) this.brickClients = null;
        }
    }

    toDraft(brick) {
        return {
            recordId: brick.id,
            level: brick.level,
            name: brick.name || '',
            code: brick.code || '',
            parentId: brick.parentId || null,
            governorate: brick.governorate || '',
            city: brick.city || '',
            dataSource: brick.dataSource || 'IQVIA IMS',
            isActive: brick.isActive !== false,
            accountSelectable: brick.accountSelectable !== false
        };
    }

    get levelLabel() {
        return LEVEL_LABELS[this.level];
    }

    get parentLevelLabel() {
        return this.level === '702' ? '148 brick' : '70 area';
    }

    get parentOptions() {
        return ((this.data && this.data.parents) || []).map((p) => ({ label: p.name, value: p.id }));
    }

    get selectedStatusClass() {
        return this.selected && this.selected.isActive === false ? 'bm-tag bm-tag_off' : 'bm-tag bm-tag_ok';
    }

    get selectedStatusLabel() {
        return this.selected && this.selected.isActive === false ? 'Inactive' : 'Active';
    }

    get selectedHasRegion() {
        return !!(this.selected && this.selected.geometry);
    }

    get regionSummary() {
        const b = this.selected;
        if (!b || !b.geometry) return '';
        const parts = [`${this.formatArea(b.areaKm2)} km²`];
        if (b.regionSource) parts.push(b.regionSource === 'Child bricks' ? 'from its 702 bricks' : b.regionSource.toLowerCase());
        if (b.regionUpdated) parts.push(`updated ${new Date(b.regionUpdated).toLocaleDateString()}`);
        return parts.join(' · ');
    }

    get isEditingSelected() {
        return !!this.editingId && this.editingId === this.selectedId;
    }

    get regionActionsDisabled() {
        return this.cannotEdit || !!this.editingId || !this.mapReady;
    }

    get showChildOutline() {
        return this.level === '148' && this.selected && (this.selected.childMapped || 0) > 0;
    }

    get childSummary() {
        const b = this.selected;
        if (!b || this.level !== '148') return '';
        return `${b.childCount || 0} 702 bricks inside, ${b.childMapped || 0} with a region`;
    }

    get isLevel148() {
        return this.level === '148';
    }

    get saveDetailsDisabled() {
        return this.cannotEdit || this.savingDetails || !this.draftDirty || !(this.draft && this.draft.name.trim());
    }

    handleDraftChange(event) {
        const field = event.target.dataset.field;
        const value = event.target.type === 'toggle' || event.target.type === 'checkbox' ? event.target.checked : event.detail ? event.detail.value : event.target.value;
        this.draft = { ...this.draft, [field]: value };
        this.draftDirty = true;
    }

    handleResetDetails() {
        const brick = this.selected;
        if (brick) this.draft = this.toDraft(brick);
        this.draftDirty = false;
    }

    async handleSaveDetails() {
        this.savingDetails = true;
        try {
            const saved = await saveBrickDetails({ input: { ...this.draft, level: this.level } });
            this.draftDirty = false;
            this.draft = this.toDraft(saved);
            this.toast('success', `${saved.name} saved.`);
            await this.loadMap();
        } catch (error) {
            this.toast('error', reduceError(error));
        }
        this.savingDetails = false;
    }

    // ---------- region editing ----------

    handleDrawRegion() {
        this.beginEdit({ mode: this.selectedHasRegion ? 'edit' : 'draw' });
    }

    handleChildOutline() {
        this.beginEdit({ mode: 'children' });
    }

    async handleSuggestOsm() {
        if (!this.selectedId) return;
        this.suggesting = true;
        try {
            const suggestion = await suggestRegionFromName({ brickId: this.selectedId });
            const geometry = typeof suggestion.geometry === 'string' ? JSON.parse(suggestion.geometry) : suggestion.geometry;
            this.beginEdit({ mode: 'edit', geometry, source: suggestion.source || 'Imported' });
            this.toast('success', suggestion.displayName ? `OSM: ${suggestion.displayName}` : 'OSM outline is on the map. Drag it, then save.');
        } catch (error) {
            this.toast('error', reduceError(error));
        }
        this.suggesting = false;
    }

    async handleGenerateIms() {
        const ok = await LightningConfirm.open({
            label: 'Generate IMS outlines',
            message:
                'Draw every 702 brick that still has no region from the scraped IMS / OpenStreetMap pack. Existing hand-drawn regions stay. 148 bricks become the outline of their 702s. You can still edit any region afterwards.'
        });
        if (!ok) return;
        this.generating = true;
        try {
            const n = await applyImsOutlines({ overwrite: false });
            await this.loadMap({ fit: true });
            this.toast(
                n ? 'success' : 'warning',
                n
                    ? `Drew ${n} IMS brick regions from OpenStreetMap. Edit any one like HAP.`
                    : 'No scraped IMS outlines to apply yet. Use Suggest from OSM on a brick, or wait for the scrape to finish.'
            );
        } catch (error) {
            this.toast('error', reduceError(error));
        }
        this.generating = false;
    }

    handleZoomRegion() {
        this.post({ type: 'HOST_SELECT', id: this.selectedId, fly: true });
    }

    beginEdit(options) {
        if (!this.selectedId || !this.mapReady) return;
        this.editingId = this.selectedId;
        this.post({ type: 'HOST_EDIT', id: this.selectedId, ...options });
    }

    handleOpenImport() {
        this.importText = '';
        this.showImport = true;
    }

    handleCloseImport() {
        this.showImport = false;
    }

    handleImportText(event) {
        this.importText = event.target.value || '';
    }

    get importDisabled() {
        return !this.importText.trim();
    }

    handleApplyImport() {
        let geometry;
        try {
            geometry = JSON.parse(this.importText);
        } catch {
            this.toast('error', 'That text is not valid GeoJSON. Paste a Polygon, MultiPolygon, Feature, or FeatureCollection.');
            return;
        }
        this.showImport = false;
        this.beginEdit({ mode: 'edit', geometry, source: 'Imported' });
    }

    async persistRegion(id, geometry, source) {
        try {
            await saveBrickRegion({ brickId: id, geometry: geometry ? JSON.stringify(geometry) : null, source });
            this.editingId = null;
            await this.loadMap();
            this.post({ type: 'HOST_EDIT_END', id, message: geometry ? 'Region saved.' : 'Region removed.' });
            this.toast('success', geometry ? 'Region saved. Distributor clients inside it were placed again.' : 'Region removed.');
        } catch (error) {
            this.post({ type: 'HOST_EDIT_ERROR', id, message: reduceError(error) });
        }
    }

    // ---------- clients ----------

    // Clients placed from address text have no coordinates, so they are not map points;
    // the detail panel lists every client in the brick from getBrickClients.
    get selectedClients() {
        const id = this.selectedId;
        if (!id) return [];
        if (this.brickClients) return this.brickClients.clients || [];
        const key = this.level === '702' ? 'brick702Id' : 'brick148Id';
        return this.points.filter((p) => p[key] === id);
    }

    get selectedClientTotal() {
        return this.brickClients ? this.brickClients.total || 0 : this.selectedClients.length;
    }

    get clientRows() {
        return this.selectedClients.slice(0, CLIENT_LIST_LIMIT).map((p) => ({
            id: p.id,
            name: p.name || 'Distributor client',
            meta: [p.distributor, p.pharmacyName, p.address].filter(Boolean).join(' · '),
            placement: p.placement || 'Not placed',
            placementClass: PLACEMENT_CLASS[p.placement] || 'bm-pill'
        }));
    }

    get clientCaption() {
        const n = this.selectedClientTotal;
        if (!n) return 'No distributor clients are placed in this brick yet.';
        return n > CLIENT_LIST_LIMIT ? `${n} clients · showing the first ${CLIENT_LIST_LIMIT}` : `${n} client${n === 1 ? '' : 's'}`;
    }

    get salesSummary() {
        const c = this.brickClients;
        if (!c) return '';
        if (!c.salesMonth || !c.salesLines) return 'No sales lines are placed in this brick yet.';
        const month = new Date(`${c.salesMonth}T00:00:00`).toLocaleDateString(undefined, { month: 'long', year: 'numeric' });
        const units = Number(c.salesQuantity || 0).toLocaleString(undefined, { maximumFractionDigits: 0 });
        const revenue = Number(c.salesRevenue || 0).toLocaleString(undefined, { maximumFractionDigits: 0 });
        return `${month} sales: ${Number(c.salesLines).toLocaleString()} lines · ${units} units · EGP ${revenue}`;
    }

    get hasClients() {
        return this.selectedClients.length > 0;
    }

    // ---------- pharmacies ----------

    get hasPharmacies() {
        return this.pharmacies.length > 0;
    }

    get addPharmacyDisabled() {
        return this.cannotEdit || !this.selectedPharmacyId;
    }

    handlePharmacySearch(event) {
        this.pharmacyTerm = event.target.value || '';
        clearTimeout(this._pharmacySearchTimer);
        const term = this.pharmacyTerm.trim();
        if (term.length < 2) {
            this.pharmacyOptions = [];
            return;
        }
        // eslint-disable-next-line @lwc/lwc/no-async-operation
        this._pharmacySearchTimer = setTimeout(async () => {
            try {
                const options = await searchPharmacyOptions({ searchTerm: term });
                if (term === this.pharmacyTerm.trim()) this.pharmacyOptions = (options || []).map((o) => ({ label: o.label, value: o.value }));
            } catch {
                this.pharmacyOptions = [];
            }
        }, 300);
    }

    handlePharmacyPick(event) {
        this.selectedPharmacyId = event.detail.value;
    }

    async handleAddPharmacy() {
        try {
            await addPharmacyToBrick({ brickId: this.selectedId, pharmacyId: this.selectedPharmacyId });
            this.selectedPharmacyId = undefined;
            this.toast('success', 'Pharmacy added to the brick.');
            this.loadLinks(this.selectedId);
        } catch (error) {
            this.toast('error', reduceError(error));
        }
    }

    async handleRemovePharmacy(event) {
        try {
            await removePharmacyFromBrick({ membershipId: event.currentTarget.dataset.id });
            this.toast('success', 'Pharmacy removed from the brick.');
            this.loadLinks(this.selectedId);
        } catch (error) {
            this.toast('error', reduceError(error));
        }
    }

    // ---------- territories ----------

    get hasTerritories() {
        return this.territories.length > 0;
    }

    get alignDisabled() {
        return this.cannotEdit || !this.selectedTerritoryId;
    }

    handleTerritoryPick(event) {
        this.selectedTerritoryId = event.detail.value;
    }

    async handleAlignTerritory() {
        try {
            await assignBrickToTerritory({ brickId: this.selectedId, territory2Id: this.selectedTerritoryId });
            this.selectedTerritoryId = undefined;
            this.toast('success', 'Brick aligned to the territory.');
            this.loadLinks(this.selectedId);
        } catch (error) {
            this.toast('error', reduceError(error));
        }
    }

    async handleRemoveTerritory(event) {
        try {
            await removeBrickTerritory({ alignmentId: event.currentTarget.dataset.id });
            this.toast('success', 'Territory alignment removed.');
            this.loadLinks(this.selectedId);
        } catch (error) {
            this.toast('error', reduceError(error));
        }
    }

    // ---------- create & delete ----------

    handleNewBrick() {
        if (this.editingId) {
            this.toast('warning', 'Save or cancel the region you are editing first.');
            return;
        }
        const parentId = this.selected && this.level === '702' ? this.selected.parentId : null;
        this.newDraft = emptyDraft(this.level, parentId);
        this.showNewModal = true;
    }

    handleCloseNew() {
        this.showNewModal = false;
    }

    handleNewChange(event) {
        const field = event.target.dataset.field;
        const value = event.target.type === 'toggle' || event.target.type === 'checkbox' ? event.target.checked : event.detail ? event.detail.value : event.target.value;
        this.newDraft = { ...this.newDraft, [field]: value };
    }

    get newLevelOptions() {
        return [
            { label: '702 micro brick', value: '702' },
            { label: '148 brick', value: '148' }
        ];
    }

    get newParentLabel() {
        return this.newDraft.level === '702' ? '148 brick it rolls up to' : '70 area it rolls up to';
    }

    get newParentOptions() {
        if (this.newDraft.level === this.level) return this.parentOptions;
        return this._otherParents || [];
    }

    get createDisabled() {
        return this.creating || !this.newDraft.name.trim() || !this.newDraft.parentId;
    }

    async handleNewLevel(event) {
        const level = event.detail.value;
        this.newDraft = { ...this.newDraft, level, parentId: null };
        if (level !== this.level) {
            try {
                const other = await getBrickMap({ level });
                this._otherParents = (other.parents || []).map((p) => ({ label: p.name, value: p.id }));
                this.newDraft = { ...this.newDraft };
            } catch {
                this._otherParents = [];
            }
        }
    }

    async handleCreate() {
        this.creating = true;
        try {
            const created = await saveBrickDetails({ input: { ...this.newDraft, recordId: null } });
            this.showNewModal = false;
            this.toast('success', `${created.name} created. Draw its region on the map.`);
            if (created.level !== this.level) {
                this.level = created.level;
            }
            this.clearSelection();
            await this.loadMap();
            this.selectBrick(created.id, false);
            if (this.canEdit && this.mapReady) this.beginEdit({ mode: 'draw' });
        } catch (error) {
            this.toast('error', reduceError(error));
        }
        this.creating = false;
    }

    async handleDelete() {
        const brick = this.selected;
        if (!brick) return;
        const ok = await LightningConfirm.open({
            label: 'Delete brick',
            message: `Delete ${brick.name}? Its region, pharmacy links and territory alignments go with it.`,
            theme: 'error'
        });
        if (!ok) return;
        try {
            await deleteBrick({ brickId: brick.id });
            this.toast('success', `${brick.name} deleted.`);
            this.clearSelection();
            this.post({ type: 'HOST_SELECT', id: null, fly: false });
            await this.loadMap();
        } catch (error) {
            this.toast('error', reduceError(error));
        }
    }

    // ---------- sales view ----------

    get isSalesView() {
        return this.view === 'sales';
    }

    get viewButtons() {
        return [
            { value: 'regions', label: 'Regions' },
            { value: 'sales', label: 'Sales' }
        ].map((v) => ({ ...v, className: `bm-seg-btn${this.view === v.value ? ' is-on' : ''}`, pressed: this.view === v.value ? 'true' : 'false' }));
    }

    get metricButtons() {
        return [
            { value: 'revenue', label: 'EGP' },
            { value: 'quantity', label: 'Units' }
        ].map((v) => ({ ...v, className: `bm-seg-btn${this.salesMetric === v.value ? ' is-on' : ''}`, pressed: this.salesMetric === v.value ? 'true' : 'false' }));
    }

    get tabButtons() {
        return [
            { value: 'placed', label: 'Placed' },
            { value: 'unplaced', label: 'Not placed' }
        ].map((v) => ({ ...v, className: `bm-seg-btn${this.salesTab === v.value ? ' is-on' : ''}`, pressed: this.salesTab === v.value ? 'true' : 'false' }));
    }

    async handleView(event) {
        const value = event.currentTarget.dataset.value;
        if (value === this.view) return;
        if (this.editingId) {
            this.toast('warning', 'Save or cancel the region you are editing first.');
            return;
        }
        this.view = value;
        if (value === 'sales') {
            if (this.showPoints) this.post({ type: 'HOST_POINTS', on: false });
            await this.ensureSalesFilters();
            this.refreshSales();
        } else {
            this.postHeat();
        }
    }

    async ensureSalesFilters() {
        if (this.salesFilters) return;
        try {
            this.salesFilters = await getSalesFilters();
            this.salesError = undefined;
            this.pickCurrentMonth();
        } catch (error) {
            this.salesError = reduceError(error);
        }
    }

    /** Opens on the current month; sales arrive after a month closes, so before then it opens on the latest month loaded. */
    pickCurrentMonth() {
        const current = currentMonthIso();
        const months = this.dataMonths;
        const month = !months.length || months.includes(current) ? current : months[0];
        this.salesStart = month;
        this.salesEnd = month;
        this.salesNotice = month === current ? '' : `No sales are loaded for ${formatMonth(current)} yet, so this opens on ${formatMonth(month)}, the latest month loaded.`;
    }

    get filterRows() {
        const f = this.salesFilters || {};
        return [...(f.placed || []), ...(f.unplaced || [])];
    }

    matchesSource(row) {
        return this.salesSource === ALL || row.source === this.salesSource;
    }

    inRange(row) {
        return !!row.month && row.month >= this.salesStart && row.month <= this.salesEnd;
    }

    get dataMonths() {
        return [...new Set(this.filterRows.map((r) => r.month).filter(Boolean))].sort().reverse();
    }

    get monthChoices() {
        return [...new Set([currentMonthIso(), ...this.dataMonths])]
            .sort()
            .reverse()
            .map((m) => ({ label: formatMonth(m), value: m }));
    }

    get endOptions() {
        return this.monthChoices.filter((o) => o.value >= this.salesStart);
    }

    get quarterOptions() {
        const keys = [...new Set(this.dataMonths.map(quarterOf))].sort().reverse();
        return keys.map((key) => {
            const [start, end] = quarterRange(key);
            return { label: `${key.replace(/^(\d{4})-(Q\d)$/, '$2 $1')} · ${formatRange(start, end)}`, value: key };
        });
    }

    get salesQuarter() {
        const key = this.salesStart ? quarterOf(this.salesStart) : '';
        const [start, end] = key ? quarterRange(key) : [];
        return start === this.salesStart && end === this.salesEnd ? key : '';
    }

    handleSalesStart(event) {
        this.salesStart = event.detail.value;
        if (this.salesEnd < this.salesStart) this.salesEnd = this.salesStart;
        this.afterRangeChange();
    }

    handleSalesEnd(event) {
        this.salesEnd = event.detail.value;
        if (this.salesStart > this.salesEnd) this.salesStart = this.salesEnd;
        this.afterRangeChange();
    }

    handleSalesQuarter(event) {
        [this.salesStart, this.salesEnd] = quarterRange(event.detail.value);
        this.afterRangeChange();
    }

    handleThisMonth() {
        this.pickCurrentMonth();
        this.keepProductIfAvailable();
        this.refreshSales();
    }

    afterRangeChange() {
        this.salesNotice = '';
        this.keepProductIfAvailable();
        this.refreshSales();
    }

    get sourceOptions() {
        const sources = [...new Set(this.filterRows.filter((r) => this.inRange(r)).map((r) => r.source).filter(Boolean))].sort();
        return [{ label: 'All distributors', value: ALL }, ...sources.map((s) => ({ label: s, value: s }))];
    }

    handleSalesSource(event) {
        this.salesSource = event.detail.value;
        const product = this.salesProduct;
        this.keepProductIfAvailable();
        if (product !== this.salesProduct) {
            this.refreshSales();
            return;
        }
        // Every chunk already holds all distributors, so switching one only reshades.
        this.postHeat();
        this.loadBrickSales(this.selectedId);
        if (this.salesTab === 'unplaced') this.loadUnplaced();
    }

    productLines(list) {
        const byId = new Map();
        (list || [])
            .filter((r) => r.productId && this.inRange(r) && this.matchesSource(r))
            .forEach((r) => {
                const e = byId.get(r.productId) || { id: r.productId, name: r.productName || 'Product', lines: 0 };
                e.lines += r.lines || 0;
                byId.set(r.productId, e);
            });
        return [...byId.values()];
    }

    get productOptions() {
        const f = this.salesFilters || {};
        const merged = new Map();
        [...this.productLines(f.placed), ...this.productLines(f.unplaced)].forEach((p) => merged.set(p.id, p));
        const items = [...merged.values()].sort((a, b) => a.name.localeCompare(b.name));
        return [{ label: 'All products', value: ALL }, ...items.map((p) => ({ label: p.name, value: p.id }))];
    }

    handleSalesProduct(event) {
        this.salesProduct = event.detail.value;
        this.refreshSales();
    }

    keepProductIfAvailable() {
        if (!this.productOptions.some((o) => o.value === this.salesProduct)) this.salesProduct = ALL;
    }

    handleSalesMetric(event) {
        this.salesMetric = event.currentTarget.dataset.value;
        this.postHeat();
    }

    handleSalesTab(event) {
        this.salesTab = event.currentTarget.dataset.value;
        if (this.salesTab === 'unplaced') this.loadUnplaced();
    }

    get salesArgs() {
        return {
            source: this.salesSource === ALL ? null : this.salesSource,
            startMonth: this.salesStart,
            endMonth: this.salesEnd,
            productId: this.salesProduct === ALL ? null : this.salesProduct
        };
    }

    /** One call per month and group of products, packed from the filter line counts to stay under the row limit. */
    planChunks() {
        const byMonth = new Map();
        ((this.salesFilters || {}).placed || []).forEach((r) => {
            if (!r.productId || !this.inRange(r)) return;
            if (this.salesProduct !== ALL && r.productId !== this.salesProduct) return;
            const products = byMonth.get(r.month) || new Map();
            products.set(r.productId, (products.get(r.productId) || 0) + (r.lines || 0));
            byMonth.set(r.month, products);
        });
        const chunks = [];
        byMonth.forEach((products, month) => {
            let ids = [];
            let rows = 0;
            [...products.entries()]
                .sort((a, b) => b[1] - a[1])
                .forEach(([id, n]) => {
                    if (ids.length && rows + n > SALES_CHUNK_ROWS) {
                        chunks.push({ month, productIds: ids });
                        ids = [];
                        rows = 0;
                    }
                    ids.push(id);
                    rows += n;
                });
            if (ids.length) chunks.push({ month, productIds: ids });
        });
        return chunks;
    }

    async refreshSales() {
        if (!this.isSalesView || !this.salesStart) {
            this.postHeat();
            return;
        }
        this.loadBrickSales(this.selectedId);
        this.loadDistributorCounts();
        if (this.salesTab === 'unplaced') this.loadUnplaced();
        const key = [this.level, this.salesStart, this.salesEnd, this.salesProduct].join('|');
        const seq = ++this._salesSeq;
        this.salesError = undefined;
        if (this._salesCache.has(key)) {
            this.salesData = this._salesCache.get(key);
            this.salesProgress = undefined;
            this.postHeat();
            return;
        }
        const queue = this.planChunks();
        const total = queue.length;
        const data = { bricks: {}, products: {} };
        let done = 0;
        this.salesData = undefined;
        this.salesProgress = { done, total };
        this.postHeat();
        const level = this.level;
        const worker = async () => {
            while (queue.length && seq === this._salesSeq) {
                const { month, productIds } = queue.shift();
                // Each worker reads one chunk at a time on purpose; SALES_CONCURRENCY workers run side by side.
                // eslint-disable-next-line no-await-in-loop
                const chunk = await getSalesChunk({ level, month, productIds });
                ((chunk && chunk.bricks) || []).forEach((r) => {
                    const bySource = data.bricks[r.brickId] || (data.bricks[r.brickId] = {});
                    addTotals(bySource[r.source] || (bySource[r.source] = emptyTotals()), r);
                });
                ((chunk && chunk.products) || []).forEach((r) => {
                    const p = data.products[r.productId] || (data.products[r.productId] = { name: r.productName, bySource: {} });
                    addTotals(p.bySource[r.source] || (p.bySource[r.source] = emptyTotals()), r);
                });
                done++;
                if (seq === this._salesSeq) this.salesProgress = { done, total };
            }
        };
        try {
            await Promise.all(Array.from({ length: Math.min(SALES_CONCURRENCY, total) }, worker));
        } catch (error) {
            if (seq === this._salesSeq) {
                this.salesError = reduceError(error);
                this.salesProgress = undefined;
            }
            return;
        }
        if (seq !== this._salesSeq) return;
        this._salesCache.set(key, data);
        this.salesData = data;
        this.salesProgress = undefined;
        this.postHeat();
    }

    /** Totals of the chosen distributor (or all) out of { source: totals }. */
    pickSources(bySource) {
        const t = emptyTotals();
        Object.keys(bySource || {}).forEach((source) => {
            if (this.salesSource === ALL || source === this.salesSource) addTotals(t, bySource[source]);
        });
        return t;
    }

    /** { brickId: totals } for the chosen distributor, bricks without sales left out. */
    get brickTotals() {
        if (!this.isSalesView || !this.salesData) return undefined;
        const out = {};
        Object.keys(this.salesData.bricks).forEach((id) => {
            const t = this.pickSources(this.salesData.bricks[id]);
            if (t.lines) out[id] = t;
        });
        return out;
    }

    heatPayload() {
        if (!this.isSalesView) return null;
        const sources = {};
        Object.keys((this.salesData && this.salesData.bricks) || {}).forEach((id) => {
            sources[id] = this.brickSourceText(id, 6);
        });
        return { metric: this.salesMetric, values: this.brickTotals || {}, pending: !this.salesData, sources };
    }

    postHeat() {
        this.post({ type: 'HOST_HEAT', heat: this.heatPayload() });
    }

    metricLabel(t) {
        return this.salesMetric === 'revenue' ? `EGP ${compact(t.revenue)}` : `${compact(t.quantity)} units`;
    }

    salesValueLabel(t) {
        return t ? this.metricLabel(t) : 'No sales';
    }

    /** Each distributor's sales in one brick, biggest first. */
    brickSources(id) {
        const bySource = (this.salesData && this.salesData.bricks[id]) || {};
        const metric = this.salesMetric;
        return Object.keys(bySource)
            .filter((source) => this.salesSource === ALL || source === this.salesSource)
            .map((source) => ({ source, ...bySource[source] }))
            .sort((a, b) => b[metric] - a[metric]);
    }

    brickSourceText(id, limit = 2) {
        const list = this.brickSources(id);
        if (!list.length) return '';
        const shown = list.slice(0, limit).map((e) => `${e.source} ${this.metricLabel(e)}`);
        if (list.length > limit) shown.push(`+${list.length - limit}`);
        return shown.join(' · ');
    }

    // ---------- sales by distributor and product ----------

    async loadDistributorCounts() {
        const key = [this.level, this.salesStart, this.salesEnd, this.salesProduct].join('|');
        const seq = ++this._countsSeq;
        if (this._countsCache.has(key)) {
            this.distributorCounts = this._countsCache.get(key);
            return;
        }
        this.distributorCounts = undefined;
        try {
            const { startMonth, endMonth, productId } = this.salesArgs;
            const result = await getDistributorCounts({ level: this.level, startMonth, endMonth, productId });
            if (seq !== this._countsSeq) return;
            this._countsCache.set(key, result);
            this.distributorCounts = result;
        } catch (error) {
            if (seq === this._countsSeq) this.salesError = reduceError(error);
        }
    }

    /** { source: totals } over every product read for the range. */
    get salesBySource() {
        const out = {};
        Object.values((this.salesData && this.salesData.products) || {}).forEach((p) => {
            Object.keys(p.bySource).forEach((source) => addTotals(out[source] || (out[source] = emptyTotals()), p.bySource[source]));
        });
        return out;
    }

    get distributorRows() {
        const sales = this.salesBySource;
        const counts = {};
        ((this.distributorCounts && this.distributorCounts.sources) || []).forEach((d) => {
            counts[d.source] = d;
        });
        const sources = [...new Set([...Object.keys(sales), ...Object.keys(counts)])];
        if (!sources.length) return [];
        const totalRevenue = Object.values(sales).reduce((n, t) => n + t.revenue, 0);
        const metric = this.salesMetric;
        const row = (key, name, source, t, c, className) => ({
            key,
            name,
            source,
            revenue: this.salesData ? `EGP ${whole(t.revenue)}` : '…',
            share: this.salesData && totalRevenue ? `${((t.revenue / totalRevenue) * 100).toFixed(1)}%` : '',
            units: this.salesData ? whole(t.quantity) : '…',
            lines: c ? whole(c.lines) : '…',
            address: c ? whole(c.addressLines) : '…',
            point: c ? whole(c.pointLines) : '…',
            bricks: c ? whole(c.bricks) : '…',
            unplaced: c ? whole(c.unplacedRows) : '…',
            className
        });
        const rows = sources
            .map((source) => ({ source, t: sales[source] || emptyTotals() }))
            .sort((a, b) => b.t[metric] - a.t[metric])
            .map(({ source, t }) =>
                row(source, source, source, t, counts[source], `bm-dist-row${this.salesSource === source ? ' is-on' : ''}`)
            );
        if (rows.length > 1) {
            const all = emptyTotals();
            Object.values(sales).forEach((t) => addTotals(all, t));
            const c = this.distributorCounts
                ? Object.values(counts).reduce(
                      (n, d) => ({
                          lines: n.lines + d.lines,
                          addressLines: n.addressLines + d.addressLines,
                          pointLines: n.pointLines + d.pointLines,
                          bricks: Object.keys((this.salesData && this.salesData.bricks) || {}).length || n.bricks + d.bricks,
                          unplacedRows: n.unplacedRows + d.unplacedRows
                      }),
                      { lines: 0, addressLines: 0, pointLines: 0, bricks: 0, unplacedRows: 0 }
                  )
                : null;
            rows.push(row('total', 'All distributors', ALL, all, c, `bm-dist-row bm-dist-total${this.salesSource === ALL ? ' is-on' : ''}`));
        }
        return rows;
    }

    get hasDistributorRows() {
        return this.distributorRows.length > 0;
    }

    get bricksHeader() {
        return this.level === '702' ? '702 bricks' : '148 bricks';
    }

    handleDistributorRow(event) {
        const source = event.currentTarget.dataset.source;
        this.handleSalesSource({ detail: { value: source === this.salesSource ? ALL : source } });
    }

    get topProductRows() {
        const metric = this.salesMetric;
        const list = Object.keys((this.salesData && this.salesData.products) || {})
            .map((id) => ({ id, name: this.salesData.products[id].name, t: this.pickSources(this.salesData.products[id].bySource) }))
            .filter((p) => p.t.lines);
        const total = list.reduce((n, p) => n + p.t[metric], 0);
        return list
            .sort((a, b) => b.t[metric] - a.t[metric])
            .slice(0, TOP_PRODUCTS)
            .map((p, i) => ({
                key: p.id,
                rank: i + 1,
                name: p.name || 'Product',
                meta: `EGP ${whole(p.t.revenue)} · ${whole(p.t.quantity)} units`,
                share: total ? `${((p.t[metric] / total) * 100).toFixed(1)}%` : ''
            }));
    }

    get hasTopProducts() {
        return this.topProductRows.length > 0;
    }

    get topProductsTitle() {
        const who = this.salesSource === ALL ? 'all distributors' : this.salesSource;
        return `Top products · ${who} · by ${this.salesMetric === 'revenue' ? 'EGP' : 'units'}`;
    }

    get selectedSourceRows() {
        return this.brickSources(this.selectedId).map((e) => ({
            key: e.source || 'none',
            name: e.source || 'No distributor',
            value: `EGP ${compact(e.revenue)} · ${whole(e.lines)} lines`
        }));
    }

    get hasSelectedSourceRows() {
        return this.selectedSourceRows.length > 0;
    }

    get salesTotals() {
        const sum = { lines: 0, quantity: 0, revenue: 0, bricks: 0 };
        Object.values(this.brickTotals || {}).forEach((t) => {
            addTotals(sum, t);
            sum.bricks++;
        });
        return sum;
    }

    get salesChips() {
        if (!this.salesData) return [{ key: 'wait', value: '…', label: this.salesProgress ? `adding up ${this.salesProgress.done} / ${this.salesProgress.total}` : 'loading' }];
        const t = this.salesTotals;
        const distributors = Object.keys(this.salesBySource).length;
        return [
            { key: 'egp', value: `EGP ${whole(t.revenue)}`, label: 'sales' },
            { key: 'units', value: whole(t.quantity), label: 'units' },
            { key: 'lines', value: whole(t.lines), label: 'lines in a brick' },
            { key: 'bricks', value: whole(t.bricks), label: `${this.level} bricks with sales` },
            { key: 'dist', value: this.salesSource === ALL ? whole(distributors) : this.salesSource, label: this.salesSource === ALL ? 'distributors' : 'only' }
        ];
    }

    get showApproximateNote() {
        return this.hasApproximate && !this.isSalesView;
    }

    get salesScope() {
        const source = this.salesSource === ALL ? 'All distributors' : this.salesSource;
        const product = this.salesProduct === ALL ? null : (this.productOptions.find((o) => o.value === this.salesProduct) || {}).label;
        return [source, formatRange(this.salesStart, this.salesEnd), product].filter(Boolean).join(' · ');
    }

    get salesHeadline() {
        if (this.salesProgress) return `Adding up sales… ${this.salesProgress.done} / ${this.salesProgress.total}`;
        if (!this.salesStart) return 'No distributor sales are loaded yet.';
        if (!this.salesData) return '';
        const t = this.salesTotals;
        if (!t.lines) return `No sales lines for ${this.salesScope}.`;
        const level = this.level === '702' ? '702 bricks' : '148 bricks';
        return `${this.salesScope}: ${whole(t.lines)} lines placed in ${whole(t.bricks)} ${level} · ${whole(t.quantity)} units · EGP ${whole(t.revenue)}`;
    }

    get unplacedRowCount() {
        return this.productLines((this.salesFilters || {}).unplaced)
            .filter((p) => this.salesProduct === ALL || p.id === this.salesProduct)
            .reduce((n, p) => n + p.lines, 0);
    }

    get unplacedHeadline() {
        const n = this.unplacedRowCount;
        return n ? `Not placed: ${whole(n)} client × product rows kept from the import` : 'Not placed: nothing kept for this period';
    }

    async loadBrickSales(id) {
        this.brickSales = undefined;
        if (!id || !this.isSalesView || !this.salesStart) return;
        const seq = ++this._brickSalesSeq;
        try {
            const result = await getBrickSales({ brickId: id, level: this.level, ...this.salesArgs });
            if (seq === this._brickSalesSeq && id === this.selectedId) this.brickSales = result;
        } catch (error) {
            if (seq === this._brickSalesSeq && id === this.selectedId) this.brickSales = { error: reduceError(error) };
        }
    }

    get showBrickSales() {
        return this.isSalesView && this.hasSelection;
    }

    get brickSalesCaption() {
        const b = this.brickSales;
        if (!b) return 'Loading sales…';
        if (b.error) return b.error;
        if (!b.lines) return `No sales lines in this brick for ${this.salesScope}.`;
        return `${this.salesScope}: ${whole(b.lines)} lines · ${whole(b.quantity)} units · EGP ${whole(b.revenue)} · ${whole(b.clientCount)} clients`;
    }

    toProductRows(list, limit) {
        return (list || []).slice(0, limit).map((p, i) => ({
            key: p.productId || `p${i}`,
            name: p.productName || 'No product',
            meta: `${whole(p.quantity)} units · ${whole(p.lines)} lines`,
            value: `EGP ${compact(p.revenue)}`
        }));
    }

    toClientRows(list, limit) {
        return (list || []).slice(0, limit).map((c, i) => ({
            key: c.clientId || `c${i}`,
            name: c.name || c.code || 'Distributor client',
            meta: [c.distributor, c.code, c.governorate, c.address].filter(Boolean).join(' · '),
            value: `EGP ${compact(c.revenue)} · ${whole(c.quantity)} u`,
            placement: c.placedSince ? 'Placed since' : c.placement || 'No location',
            placementClass: c.placedSince ? 'bm-pill bm-pill_ok' : PLACEMENT_CLASS[c.placement] || 'bm-pill'
        }));
    }

    get brickProductRows() {
        return this.toProductRows(this.brickSales && this.brickSales.products, SALES_PRODUCT_LIMIT);
    }

    get brickClientRows() {
        return this.toClientRows(this.brickSales && this.brickSales.clients, SALES_CLIENT_LIMIT);
    }

    get hasBrickSalesRows() {
        return this.brickProductRows.length > 0;
    }

    get showUnplaced() {
        return this.isSalesView && this.salesTab === 'unplaced';
    }

    async loadUnplaced() {
        if (!this.salesStart) return;
        const seq = ++this._unplacedSeq;
        this.unplacedLoading = true;
        try {
            const result = await getUnplacedSales(this.salesArgs);
            if (seq !== this._unplacedSeq) return;
            this.unplacedSales = result;
            this.unplacedError = undefined;
        } catch (error) {
            if (seq !== this._unplacedSeq) return;
            this.unplacedSales = undefined;
            this.unplacedError = reduceError(error);
        }
        this.unplacedLoading = false;
    }

    get unplacedSummary() {
        const u = this.unplacedSales;
        if (!u) return '';
        if (!u.lines && !u.placedSinceLines) {
            return `Nothing kept as not placed for ${this.salesScope}. Rows are kept from the next load of a month onward, so months loaded before 27 October 2026 show none until they are loaded again.`;
        }
        return `${this.salesScope}: ${whole(u.lines)} rows · ${whole(u.quantity)} units · EGP ${whole(u.revenue)} from ${whole(u.clientCount)} clients with no brick and no CRM pharmacy.`;
    }

    get unplacedSinceNote() {
        const u = this.unplacedSales;
        if (!u || !u.placedSinceLines) return '';
        return `${whole(u.placedSinceLines)} more rows (EGP ${whole(u.placedSinceRevenue)}) belong to clients placed since the import. Load the month again to turn them into sales lines.`;
    }

    get unplacedProductRows() {
        return this.toProductRows(this.unplacedSales && this.unplacedSales.products, UNPLACED_LIMIT);
    }

    get unplacedClientRows() {
        return this.toClientRows(this.unplacedSales && this.unplacedSales.clients, UNPLACED_LIMIT);
    }

    get hasUnplacedRows() {
        return this.unplacedClientRows.length > 0;
    }

    get mainClass() {
        return `bm-map${this.showUnplaced ? ' bm-map_covered' : ''}`;
    }

    // ---------- map frame ----------

    get frame() {
        return this.template.querySelector('iframe.bm-frame');
    }

    get mapVeil() {
        return !this.mapReady && !this.mapError;
    }

    post(message) {
        const frame = this.frame;
        if (frame && frame.contentWindow) {
            frame.contentWindow.postMessage(plain(message), window.location.origin);
        }
    }

    mapPayload() {
        const data = this.data || {};
        return {
            level: this.level,
            bricks: data.bricks || [],
            parents: data.parents || [],
            children: data.children || [],
            points: this.points,
            selectedId: this.selectedId || null,
            canEdit: this.canEdit,
            showPoints: this.showPoints,
            heat: this.heatPayload()
        };
    }

    handleFrameLoad() {
        this.frameLoaded = true;
        this.initMap();
    }

    initMap() {
        if (!this.frameLoaded || !this.data || this.mapReady) return;
        clearTimeout(this._mapTimer);
        // eslint-disable-next-line @lwc/lwc/no-async-operation
        this._mapTimer = setTimeout(() => {
            if (!this.mapReady) this.mapError = 'The map took too long to load. Check your connection and try again.';
        }, MAP_TIMEOUT_MS);
        this.post({ type: 'HOST_INIT', leafletBase: LEAFLET, ...this.mapPayload() });
    }

    handleRetryMap() {
        this.mapError = undefined;
        this.mapReady = false;
        this.frameLoaded = false;
        this.editingId = null;
        this.mapSrc = `${BRICK_MAP_HOST}/index.html?r=${Date.now()}`;
    }

    handleFrameMessage(event) {
        const frame = this.frame;
        if (!frame || event.source !== frame.contentWindow || event.origin !== window.location.origin) return;
        const data = event.data || {};
        switch (data.type) {
            case 'HOST_READY':
                this.mapReady = true;
                this.mapError = undefined;
                clearTimeout(this._mapTimer);
                break;
            case 'HOST_ERROR':
                this.mapError = data.message || 'The map could not start.';
                break;
            case 'HOST_BRICK_SELECT':
                this.selectBrick(data.id, true);
                break;
            case 'HOST_REGION_SAVE':
                this.persistRegion(data.id, data.geometry, data.source);
                break;
            case 'HOST_EDIT_CANCEL':
                this.editingId = null;
                break;
            case 'HOST_LOCATE_POINT':
                this.locate(data);
                break;
            case 'HOST_POINTS_TOGGLED':
                this.showPoints = !!data.on;
                break;
            default:
        }
    }

    async locate({ seq, lat, lng }) {
        try {
            const result = await locatePoint({ latitude: lat, longitude: lng });
            this.post({ type: 'HOST_LOCATE_RESULT', seq, ...result });
        } catch (error) {
            this.post({ type: 'HOST_LOCATE_RESULT', seq, message: reduceError(error) });
        }
    }

    // ---------- helpers ----------

    formatArea(value) {
        const km2 = Number(value || 0);
        if (km2 >= 100) return Math.round(km2).toLocaleString();
        return km2 >= 10 ? km2.toFixed(1) : km2.toFixed(2);
    }

    toast(variant, message) {
        this.dispatchEvent(new ShowToastEvent({ title: message, variant }));
    }
}
