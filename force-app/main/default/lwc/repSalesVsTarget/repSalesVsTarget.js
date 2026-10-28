import { LightningElement, wire } from 'lwc';
import { MessageContext } from 'lightning/messageService';
import { subscribeTerritoryContext, unsubscribeTerritoryContext } from 'c/territoryContextClient';
import getMySalesVsTarget from '@salesforce/apex/RepSalesTargetController.getMySalesVsTarget';
import getMySalesByBrick from '@salesforce/apex/RepSalesTargetController.getMySalesByBrick';
import LEAFLET from '@salesforce/resourceUrl/leaflet';
import { ensureLeaflet } from 'c/plannerMapPins';
import { isFieldFeatureEnabled, loadFieldFeatures } from 'c/fieldFeatureFlags';

const RANGES = [
    { label: '3 months', value: 3 },
    { label: '6 months', value: 6 }
];

const VIEWS = [
    { label: 'Months', value: 'months' },
    { label: 'Products', value: 'products' },
    { label: 'Map', value: 'map' }
];

// Sequential teal scale, light to dark; bricks with no sales stay grey.
const SCALE = ['#ccfbf1', '#5eead4', '#14b8a6', '#0f766e', '#134e4a'];
const NO_SALES = '#e2e8f0';
const EGYPT_CENTER = [26.8, 30.8];

function formatNumber(value) {
    return new Intl.NumberFormat('en-US', { maximumFractionDigits: 0 }).format(Number(value || 0));
}

function formatCurrency(value) {
    return new Intl.NumberFormat('en-US', { style: 'currency', currency: 'EGP', maximumFractionDigits: 0 }).format(
        Number(value || 0)
    );
}

function hasValue(value) {
    return value !== null && value !== undefined;
}

function percentLabel(value) {
    return hasValue(value) ? `${value}%` : 'No target';
}

function barStyle(value) {
    const width = hasValue(value) ? Math.min(Number(value), 100) : 0;
    return `width: ${width}%`;
}

function barClass(value) {
    if (!hasValue(value)) {
        return 'bar-fill';
    }
    if (value >= 100) {
        return 'bar-fill bar-fill--good';
    }
    return value >= 80 ? 'bar-fill bar-fill--near' : 'bar-fill bar-fill--low';
}

function shareLabel(row) {
    if (!hasValue(row?.shareRevenue)) {
        return '—';
    }
    return hasValue(row.sharePercent) ? `${formatCurrency(row.shareRevenue)} (${row.sharePercent}%)` : formatCurrency(row.shareRevenue);
}

function escapeHtml(value) {
    return String(value ?? '').replace(/[&<>"']/g, (c) => `&#${c.charCodeAt(0)};`);
}

export default class RepSalesVsTarget extends LightningElement {
    featureEnabled = true;
    data;
    detail;
    error;
    detailError;
    isLoading = true;
    isLoadingDetail = false;
    monthsBack = 3;
    view = 'months';
    selectedMonth = '';
    selectedProduct = '';

    map;
    mapLayer;
    mapRenderedFor;

    _messageContext;
    territoryContextSubscription;
    loadSeq = 0;
    detailSeq = 0;

    @wire(MessageContext)
    wiredMessageContext(value) {
        this._messageContext = value;
        this.subscribeTerritoryContext();
    }

    connectedCallback() {
        this.subscribeTerritoryContext();
        loadFieldFeatures().then(() => {
            this.featureEnabled = isFieldFeatureEnabled('home.salesVsTarget');
            if (this.featureEnabled) {
                this.load();
            }
        });
    }

    disconnectedCallback() {
        unsubscribeTerritoryContext(this.territoryContextSubscription);
        this.territoryContextSubscription = undefined;
        this.destroyMap();
    }

    subscribeTerritoryContext() {
        if (this.territoryContextSubscription) {
            return;
        }
        // Subscribe even when LMS MessageContext is missing (PWA stub / LWS); window + BroadcastChannel still fire.
        this.territoryContextSubscription = subscribeTerritoryContext(this._messageContext, () => {
            this.handleTerritoryChange();
        });
    }

    // A new working territory means new bricks and products: drop what is on screen and reload.
    handleTerritoryChange() {
        if (!this.featureEnabled) {
            return;
        }
        this.destroyMap();
        this.data = undefined;
        this.detail = undefined;
        this.error = undefined;
        this.detailError = undefined;
        this.selectedMonth = '';
        this.selectedProduct = '';
        this.load();
        if (!this.isMonthsView) {
            this.loadDetail();
        }
    }

    renderedCallback() {
        if (this.isMapView && this.detail && this.mapRenderedFor !== this.detailKey) {
            this.renderMap();
        }
    }

    // Each load keeps a sequence number so a slow answer for the old territory
    // cannot overwrite the answer for the new one.
    async load() {
        const seq = ++this.loadSeq;
        this.isLoading = true;
        try {
            const data = await getMySalesVsTarget({ monthsBack: this.monthsBack });
            if (seq !== this.loadSeq) {
                return;
            }
            this.data = data;
            this.error = undefined;
        } catch (e) {
            if (seq !== this.loadSeq) {
                return;
            }
            this.error = e?.body?.message || e?.message || 'Could not load sales.';
            this.data = undefined;
        } finally {
            if (seq === this.loadSeq) {
                this.isLoading = false;
            }
        }
    }

    async loadDetail() {
        const seq = ++this.detailSeq;
        this.isLoadingDetail = true;
        try {
            const detail = await getMySalesByBrick({
                monthKey: this.selectedMonth || null,
                productId: this.selectedProduct || null
            });
            if (seq !== this.detailSeq) {
                return;
            }
            this.detail = detail;
            this.detailError = undefined;
            if (this.detail?.monthKey && !this.selectedMonth) {
                this.selectedMonth = this.detail.monthKey;
            }
        } catch (e) {
            if (seq !== this.detailSeq) {
                return;
            }
            this.detailError = e?.body?.message || e?.message || 'Could not load bricks.';
            this.detail = undefined;
        } finally {
            if (seq === this.detailSeq) {
                this.isLoadingDetail = false;
                this.mapRenderedFor = undefined;
            }
        }
    }

    handleRange(event) {
        const months = Number(event.currentTarget.dataset.months);
        if (months && months !== this.monthsBack) {
            this.monthsBack = months;
            this.load();
        }
    }

    handleView(event) {
        const next = event.currentTarget.dataset.view;
        if (!next || next === this.view) {
            return;
        }
        if (this.view === 'map') {
            this.destroyMap();
        }
        this.view = next;
        if (next !== 'months' && !this.detail) {
            this.loadDetail();
        } else {
            this.mapRenderedFor = undefined;
        }
    }

    handleMonthRow(event) {
        this.selectedMonth = event.currentTarget.dataset.month;
        this.selectedProduct = '';
        this.view = 'products';
        this.loadDetail();
    }

    handleMonthChange(event) {
        this.selectedMonth = event.detail.value;
        this.loadDetail();
    }

    handleProductChange(event) {
        this.selectedProduct = event.detail.value;
        this.loadDetail();
    }

    handleProductRow(event) {
        this.selectedProduct = event.currentTarget.dataset.product;
        this.view = 'map';
        this.loadDetail();
    }

    // ----- views

    get isMonthsView() {
        return this.view === 'months';
    }

    get isProductsView() {
        return this.view === 'products';
    }

    get isMapView() {
        return this.view === 'map';
    }

    get viewButtons() {
        return VIEWS.map((v) => ({
            ...v,
            className: `view-chip${v.value === this.view ? ' view-chip--active' : ''}`
        }));
    }

    get rangeButtons() {
        return RANGES.map((r) => ({
            ...r,
            className: `range-chip${r.value === this.monthsBack ? ' range-chip--active' : ''}`
        }));
    }

    get hasMonths() {
        return Boolean(this.data?.months?.length);
    }

    get months() {
        return (this.data?.months || []).map((m) => ({
            ...m,
            qtyLabel: formatNumber(m.quantity),
            revenueLabel: formatCurrency(m.revenue),
            targetLabel: hasValue(m.targetQuantity) ? formatNumber(m.targetQuantity) : '—',
            percent: percentLabel(m.achievementPercent),
            barStyle: barStyle(m.achievementPercent),
            barClass: barClass(m.achievementPercent),
            hasShare: hasValue(m.shareRevenue),
            shareText: hasValue(m.shareRevenue)
                ? `Your share ${formatNumber(m.shareQuantity)} units · ${shareLabel(m)}`
                : ''
        }));
    }

    get monthOptions() {
        const options = (this.data?.months || []).map((m) => ({ label: m.monthLabel, value: m.monthKey }));
        if (this.detail?.monthKey && !options.some((o) => o.value === this.detail.monthKey)) {
            options.push({ label: this.detail.monthLabel, value: this.detail.monthKey });
        }
        return options.reverse();
    }

    get monthValue() {
        return this.selectedMonth || this.detail?.monthKey || '';
    }

    get productOptions() {
        const options = [{ label: 'All products', value: '' }];
        (this.detail?.products || []).forEach((p) => options.push({ label: p.productName, value: p.productId }));
        return options;
    }

    get products() {
        return (this.detail?.products || []).map((p) => ({
            ...p,
            qtyLabel: formatNumber(p.quantity),
            revenueLabel: formatCurrency(p.revenue),
            targetLabel: hasValue(p.targetQuantity) ? formatNumber(p.targetQuantity) : '—',
            percent: percentLabel(p.achievementPercent),
            shareLabel: shareLabel(p),
            rowClass: p.productId === this.selectedProduct ? 'product-row product-row--selected' : 'product-row'
        }));
    }

    get hasProducts() {
        return this.products.length > 0;
    }

    get bricks() {
        return (this.detail?.bricks || []).slice(0, 12).map((b) => ({
            ...b,
            qtyLabel: formatNumber(b.quantity),
            revenueLabel: formatCurrency(b.revenue),
            targetLabel: hasValue(b.targetQuantity) ? formatNumber(b.targetQuantity) : '—',
            percent: percentLabel(b.achievementPercent),
            shareLabel: shareLabel(b),
            visitsLabel: hasValue(b.allVisits) ? `${formatNumber(b.myVisits)} of ${formatNumber(b.allVisits)} visits` : '',
            swatchStyle: `background:${this.colorFor(b.revenue)}`
        }));
    }

    get hasBricks() {
        return Boolean(this.detail?.bricks?.length);
    }

    get moreBricksLabel() {
        const total = this.detail?.bricks?.length || 0;
        return total > 12 ? `Top 12 of ${total} bricks by value` : '';
    }

    get detailSummary() {
        if (!this.detail?.monthLabel) {
            return '';
        }
        const parts = [this.detail.monthLabel];
        parts.push(this.detail.productName || 'all products');
        parts.push(`${formatNumber(this.detail.totalQuantity)} units`);
        parts.push(formatCurrency(this.detail.totalRevenue));
        if (hasValue(this.detail.shareRevenue)) {
            parts.push(`your share ${shareLabel(this.detail)}`);
        }
        return parts.join(' · ');
    }

    get legend() {
        const max = this.maxRevenue;
        if (!max) {
            return [];
        }
        return SCALE.map((color, i) => ({
            key: color,
            style: `background:${color}`,
            label: i === SCALE.length - 1 ? `≥ ${formatCurrency((max * i) / SCALE.length)}` : formatCurrency((max * i) / SCALE.length)
        }));
    }

    get scopeLabel() {
        if (!this.data) {
            return '';
        }
        const visited = this.data.visitedBrickCount || 0;
        const parts = [`${this.data.brickCount || 0} bricks${visited ? ` (${visited} from your visits)` : ''}`];
        parts.push(this.data.productCount ? `${this.data.productCount} line products` : 'all products');
        if (this.data.tenderExcluded) {
            parts.push('tender excluded');
        }
        return parts.join(' · ');
    }

    get showShare() {
        return this.data?.shareAvailable === true;
    }

    get shareSummary() {
        if (!this.showShare || !hasValue(this.data?.shareRevenue)) {
            return '';
        }
        return `Your share over these months: ${formatNumber(this.data.shareQuantity)} units · ${shareLabel(this.data)}`;
    }

    get shareFootnote() {
        return this.showShare
            ? 'Your share: each brick\'s sales of a product are split among the reps whose line carries it, by their completed doctor visits in that brick that month.'
            : 'Your share shows once this month\'s doctor visits are summarised (nightly).';
    }

    get productsTitle() {
        return this.detail?.monthLabel ? `By product, ${this.detail.monthLabel}` : 'By product';
    }

    get detailKey() {
        return `${this.detail?.monthKey}|${this.detail?.productId || ''}|${(this.detail?.bricks || []).length}`;
    }

    get maxRevenue() {
        return Math.max(0, ...(this.detail?.bricks || []).map((b) => Number(b.revenue || 0)));
    }

    colorFor(revenue) {
        const value = Number(revenue || 0);
        const max = this.maxRevenue;
        if (!value || !max) {
            return NO_SALES;
        }
        const index = Math.min(SCALE.length - 1, Math.floor((value / max) * SCALE.length));
        return SCALE[index];
    }

    // ----- map

    async renderMap() {
        const container = this.template.querySelector('.sales-map');
        if (!container) {
            return;
        }
        this.mapRenderedFor = this.detailKey;
        let L;
        try {
            L = await ensureLeaflet(this, LEAFLET);
        } catch {
            this.detailError = 'The map could not load. The brick list below still shows the figures.';
            return;
        }
        if (!this.map) {
            this.map = L.map(container, { zoomControl: true, attributionControl: true });
            L.tileLayer('https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png', {
                maxZoom: 18,
                attribution: '&copy; OpenStreetMap'
            }).addTo(this.map);
        }
        if (this.mapLayer) {
            this.mapLayer.remove();
        }
        const layer = L.featureGroup();
        (this.detail?.bricks || []).forEach((b) => {
            const color = this.colorFor(b.revenue);
            const tooltip =
                `<strong>${escapeHtml(b.name)}</strong><br>` +
                `${formatNumber(b.quantity)} units · ${formatCurrency(b.revenue)}<br>` +
                (hasValue(b.shareRevenue)
                    ? `Your share ${shareLabel(b)} · ${formatNumber(b.myVisits)} of ${formatNumber(b.allVisits)} visits<br>`
                    : '') +
                `Target ${hasValue(b.targetQuantity) ? formatNumber(b.targetQuantity) : '—'} · ${percentLabel(b.achievementPercent)}`;
            let shape;
            if (b.boundaryGeoJson) {
                try {
                    shape = L.geoJSON(JSON.parse(b.boundaryGeoJson), {
                        style: { color: '#0f172a', weight: 1, fillColor: color, fillOpacity: 0.75 }
                    });
                } catch {
                    shape = undefined;
                }
            }
            if (!shape && hasValue(b.latitude) && hasValue(b.longitude)) {
                shape = L.circleMarker([b.latitude, b.longitude], {
                    radius: 9,
                    color: '#0f172a',
                    weight: 1,
                    fillColor: color,
                    fillOpacity: 0.85
                });
            }
            if (shape) {
                shape.bindTooltip(tooltip, { sticky: true });
                layer.addLayer(shape);
            }
        });
        layer.addTo(this.map);
        this.mapLayer = layer;
        const bounds = layer.getBounds();
        if (bounds && bounds.isValid()) {
            this.map.fitBounds(bounds, { padding: [12, 12] });
        } else {
            this.map.setView(EGYPT_CENTER, 5);
        }
        // The card may have been hidden while the map was created.
        // eslint-disable-next-line @lwc/lwc/no-async-operation
        window.requestAnimationFrame(() => this.map && this.map.invalidateSize());
    }

    destroyMap() {
        if (this.map) {
            this.map.remove();
        }
        this.map = undefined;
        this.mapLayer = undefined;
        this.mapRenderedFor = undefined;
    }
}
