import { LightningElement, track, wire } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import FORM_FACTOR from '@salesforce/client/formFactor';
import getFilterOptions from '@salesforce/apex/PharmacySalesAnalyticsController.getFilterOptions';
import getDashboardPage from '@salesforce/apex/PharmacySalesAnalyticsController.getDashboardPage';

const FILTER_DEBOUNCE_MS = 300;
const PRESET_MONTHS = [
    { id: '3', label: 'Last 3 months', months: 3 },
    { id: '6', label: 'Last 6 months', months: 6 },
    { id: '12', label: 'Last 12 months', months: 12 }
];

function monthInputValue(dateObj) {
    if (!dateObj) {
        return '';
    }
    const year = dateObj.getFullYear();
    const month = String(dateObj.getMonth() + 1).padStart(2, '0');
    return `${year}-${month}`;
}

function parseMonthInput(value) {
    if (!value) {
        return null;
    }
    const [year, month] = value.split('-').map((part) => parseInt(part, 10));
    return new Date(year, month - 1, 1);
}

function formatNumber(value) {
    const num = Number(value || 0);
    if (num >= 1000000) {
        return `${(num / 1000000).toFixed(1)}M`;
    }
    if (num >= 1000) {
        return `${(num / 1000).toFixed(1)}K`;
    }
    return num.toLocaleString(undefined, { maximumFractionDigits: 0 });
}

function formatCount(value) {
    return Number(value || 0).toLocaleString();
}

function formatCurrency(value) {
    const num = Number(value || 0);
    return num.toLocaleString(undefined, { style: 'currency', currency: 'EGP', maximumFractionDigits: 0 });
}

function formatRoiPercent(value) {
    if (value === null || value === undefined || value === '') {
        return '—';
    }
    const num = Number(value);
    if (!Number.isFinite(num)) {
        return '—';
    }
    const sign = num > 0 ? '+' : '';
    return `${sign}${num.toFixed(1)}%`;
}

function buildRoiBreakdown(row) {
    const visits = row.visitCountWithDetailing || 0;
    const commute = formatCurrency(row.commuteCostEstimate);
    if (row.canViewSalary) {
        const salary = formatCurrency(row.repSalaryAllocated);
        return `${visits} visits with detailing · ${salary} salary · ${commute} commute`;
    }
    return `${visits} visits with detailing · ${commute} commute`;
}

function roiToneClass(roiPercent) {
    const num = Number(roiPercent);
    if (!Number.isFinite(num)) {
        return 'roi-neutral';
    }
    if (num >= 0) {
        return 'roi-positive';
    }
    return 'roi-negative';
}

export default class PharmacySalesDashboard extends LightningElement {
    @track isLoading = true;
    @track filterOptions;
    @track dashboardData;
    @track expandedFamilies = new Set();
    @track filtersExpanded = FORM_FACTOR === 'Small';

    startMonthValue;
    endMonthValue;
    dataSource = 'All';
    // Blank until the user picks one: the server then applies the Sales Policy default.
    tenderMode = '';
    therapyArea = 'All';
    productFamily = 'All';
    brickId = 'All';
    pharmacyId = 'All';
    activePreset = '6';

    debounceTimer;
    requestSeq = 0;
    loadProgress = '';

    detailColumns = [
        { label: 'Month', fieldName: 'monthLabel', type: 'text' },
        { label: 'Pharmacy', fieldName: 'pharmacyName', type: 'text' },
        { label: 'Brick', fieldName: 'brickName', type: 'text' },
        { label: 'Product', fieldName: 'productName', type: 'text' },
        { label: 'Family', fieldName: 'productFamily', type: 'text' },
        { label: 'Therapy Area', fieldName: 'therapyArea', type: 'text' },
        { label: 'Source', fieldName: 'dataSource', type: 'text' },
        { label: 'Tender', fieldName: 'tenderLabel', type: 'text', initialWidth: 90 },
        { label: 'Qty', fieldName: 'quantity', type: 'number', cellAttributes: { alignment: 'right' } },
        { label: 'Unit Price', fieldName: 'unitPrice', type: 'currency', typeAttributes: { currencyCode: 'EGP' } },
        { label: 'Revenue', fieldName: 'revenue', type: 'currency', typeAttributes: { currencyCode: 'EGP' } }
    ];

    connectedCallback() {
        this.applyPreset(6);
        this.refreshDashboard();
    }

    @wire(getFilterOptions)
    wiredFilterOptions({ data, error }) {
        if (data) {
            this.filterOptions = data;
        } else if (error) {
            this.toast('Filter options error', this.reduceError(error), 'error');
        }
    }

    get isMobile() {
        return FORM_FACTOR === 'Small';
    }

    get filtersPanelClass() {
        return `filters${this.filtersExpanded ? ' filters--open' : ''}`;
    }

    get filtersToggleLabel() {
        return this.filtersExpanded ? 'Hide filters' : 'Show filters';
    }

    get presetButtons() {
        return PRESET_MONTHS.map((preset) => ({
            ...preset,
            className: `preset-chip${this.activePreset === preset.id ? ' preset-chip--active' : ''}`
        }));
    }

    get therapyAreaOptions() {
        return this.filterOptions?.therapyAreas || [{ label: 'All', value: 'All' }];
    }

    get productFamilyOptions() {
        return this.filterOptions?.productFamilies || [{ label: 'All', value: 'All' }];
    }

    get brickOptions() {
        return this.filterOptions?.bricks || [{ label: 'All', value: 'All' }];
    }

    get pharmacyOptions() {
        return this.filterOptions?.pharmacies || [{ label: 'All', value: 'All' }];
    }

    get tenderModeOptions() {
        return this.filterOptions?.tenderModes || [
            { label: 'Exclude tender sales', value: 'Exclude' },
            { label: 'Tender sales only', value: 'Only' },
            { label: 'All sales (incl. tender)', value: 'All' }
        ];
    }

    get tenderModeValue() {
        return this.tenderMode || this.filterOptions?.defaultTenderMode || 'Exclude';
    }

    get dataSourceOptions() {
        return this.filterOptions?.dataSources || [
            { label: 'All', value: 'All' },
            { label: 'IbnSina', value: 'IbnSina' },
            { label: 'Pharmaoverseas', value: 'Pharmaoverseas' }
        ];
    }

    get filterStateForInsights() {
        const startDate = parseMonthInput(this.startMonthValue);
        const endDate = parseMonthInput(this.endMonthValue);
        return {
            startMonth: startDate ? this.toApexDate(startDate) : null,
            endMonth: endDate ? this.toApexDate(endDate) : null,
            dataSource: this.dataSource,
            tenderMode: this.tenderMode || null,
            therapyArea: this.therapyArea,
            productFamily: this.productFamily,
            brickId: this.brickId,
            pharmacyId: this.pharmacyId
        };
    }

    get kpiCards() {
        const kpis = this.dashboardData?.kpis;
        if (!kpis) {
            return [];
        }
        return [
            { id: 'revenue', label: 'Total Revenue', value: formatCurrency(kpis.totalRevenue), hint: 'EGP across filters' },
            { id: 'qty', label: 'Units Withdrawn', value: formatNumber(kpis.totalQuantity), hint: 'Total quantity' },
            { id: 'pharmacies', label: 'Pharmacies', value: String(kpis.pharmacyCount || 0), hint: 'Active in range' },
            { id: 'products', label: 'Products', value: String(kpis.productCount || 0), hint: 'Distinct SKUs' }
        ];
    }

    get familyCards() {
        return (this.dashboardData?.familyBreakdown || []).map((family) => {
            const expanded = this.expandedFamilies.has(family.family);
            return {
                ...family,
                key: family.family,
                isExpanded: expanded,
                quantityDisplay: formatNumber(family.quantity),
                revenueDisplay: formatCurrency(family.revenue),
                therapyBadge: family.therapyArea || '—',
                chevronClass: `family-chevron${expanded ? ' family-chevron--open' : ''}`,
                roiDisplay: formatRoiPercent(family.roiPercent),
                roiToneClass: roiToneClass(family.roiPercent),
                fieldSpendDisplay: formatCurrency(family.totalFieldSpend),
                roiBreakdown: buildRoiBreakdown(family),
                products: (family.products || []).map((product) => ({
                    ...product,
                    key: product.productId,
                    quantityDisplay: formatNumber(product.quantity),
                    revenueDisplay: formatCurrency(product.revenue),
                    percentDisplay: `${product.percentOfFamily || 0}%`,
                    hasImage: Boolean(product.imageUrl),
                    roiDisplay: formatRoiPercent(product.roiPercent),
                    roiToneClass: roiToneClass(product.roiPercent),
                    roiBreakdown: buildRoiBreakdown(product)
                }))
            };
        });
    }

    get matrixMonthLabels() {
        return (this.dashboardData?.matrixMonthKeys || []).map((key) => ({
            key,
            label: this.formatMonthKeyLabel(key)
        }));
    }

    get matrixRows() {
        return (this.dashboardData?.brickMonthMatrix || []).map((row) => ({
            ...row,
            key: row.brickId,
            rowTotalDisplay: formatCurrency(row.rowTotal),
            cells: (row.cells || []).map((cell) => ({
                ...cell,
                key: `${row.brickId}-${cell.monthKey}`,
                revenueDisplay: formatCurrency(cell.revenue),
                cellClass: 'matrix-cell',
                isZero: !cell.revenue
            }))
        }));
    }

    get detailRows() {
        return (this.dashboardData?.detailRows || []).map((row) => ({
            ...row,
            key: row.recordId,
            quantityDisplay: formatNumber(row.quantity),
            unitPriceDisplay: formatCurrency(row.unitPrice),
            revenueDisplay: formatCurrency(row.revenue)
        }));
    }

    get hasFamilies() {
        return this.familyCards.length > 0;
    }

    get hasMatrix() {
        return this.matrixRows.length > 0;
    }

    get hasDetailRows() {
        return this.detailRows.length > 0;
    }

    get detailCapNote() {
        const total = this.dashboardData?.detailTotal || 0;
        const shown = this.dashboardData?.detailRows?.length || 0;
        if (total <= shown) {
            return '';
        }
        return `Showing the first ${formatCount(shown)} of ${formatCount(total)} lines. Click a brick and month in the table above to see its lines.`;
    }

    handleFiltersToggle() {
        this.filtersExpanded = !this.filtersExpanded;
    }

    handlePresetClick(event) {
        const months = parseInt(event.currentTarget.dataset.months, 10);
        const presetId = event.currentTarget.dataset.presetId;
        this.activePreset = presetId;
        this.applyPreset(months);
        this.scheduleRefresh();
    }

    handleStartMonthChange(event) {
        this.startMonthValue = event.target.value;
        this.activePreset = '';
        this.scheduleRefresh();
    }

    handleEndMonthChange(event) {
        this.endMonthValue = event.target.value;
        this.activePreset = '';
        this.scheduleRefresh();
    }

    handleFilterChange(event) {
        const field = event.target.dataset.field;
        const value = event.detail.value;
        if (field === 'dataSource') {
            this.dataSource = value;
        } else if (field === 'tenderMode') {
            this.tenderMode = value;
        } else if (field === 'therapyArea') {
            this.therapyArea = value;
        } else if (field === 'productFamily') {
            this.productFamily = value;
        } else if (field === 'brickId') {
            this.brickId = value;
        } else if (field === 'pharmacyId') {
            this.pharmacyId = value;
        }
        this.scheduleRefresh();
    }

    handleFamilyToggle(event) {
        const family = event.currentTarget.dataset.family;
        const next = new Set(this.expandedFamilies);
        if (next.has(family)) {
            next.delete(family);
        } else {
            next.add(family);
        }
        this.expandedFamilies = next;
    }

    handleMatrixCellClick(event) {
        const brickId = event.currentTarget.dataset.brickId;
        const monthKey = event.currentTarget.dataset.monthKey;
        if (!brickId || !monthKey) {
            return;
        }
        this.brickId = brickId;
        const monthDate = parseMonthInput(monthKey.length === 7 ? monthKey : monthKey);
        if (monthDate) {
            this.startMonthValue = monthInputValue(monthDate);
            this.endMonthValue = monthInputValue(monthDate);
        }
        this.activePreset = '';
        this.filtersExpanded = true;
        this.refreshDashboard({
            matrixBrickId: brickId,
            matrixMonthKey: monthKey
        });
    }

    applyPreset(months) {
        const end = new Date();
        end.setDate(1);
        const start = new Date(end);
        start.setMonth(start.getMonth() - (months - 1));
        this.startMonthValue = monthInputValue(start);
        this.endMonthValue = monthInputValue(end);
    }

    scheduleRefresh() {
        clearTimeout(this.debounceTimer);
        this.debounceTimer = setTimeout(() => this.refreshDashboard(), FILTER_DEBOUNCE_MS);
    }

    async refreshDashboard(extraFilters = {}) {
        this.isLoading = true;
        this.loadProgress = '';
        const requestId = ++this.requestSeq;
        try {
            const startDate = parseMonthInput(this.startMonthValue);
            const endDate = parseMonthInput(this.endMonthValue);
            const filters = {
                startMonth: startDate ? this.toApexDate(startDate) : null,
                endMonth: endDate ? this.toApexDate(endDate) : null,
                dataSource: this.dataSource,
                tenderMode: this.tenderMode || null,
                therapyArea: this.therapyArea,
                productFamily: this.productFamily,
                brickId: this.brickId !== 'All' ? this.brickId : null,
                pharmacyIds: this.pharmacyId !== 'All' ? [this.pharmacyId] : null,
                matrixBrickId: extraFilters.matrixBrickId || null,
                matrixMonthKey: extraFilters.matrixMonthKey || null
            };
            // A month of distributor files is 100k+ lines, more than one server call may read,
            // so the totals are built page by page and the last page carries the dashboard.
            let cursor = null;
            let state = null;
            let page;
            do {
                // eslint-disable-next-line no-await-in-loop
                page = await getDashboardPage({ filters, cursor, state });
                if (requestId !== this.requestSeq) {
                    return;
                }
                cursor = page?.nextCursor || null;
                state = page?.state || null;
                if (!page?.done && page?.rowsTotal) {
                    this.loadProgress = `Reading sales lines… ${formatCount(page.rowsRead)} of ${formatCount(page.rowsTotal)}`;
                }
            } while (page && !page.done && cursor);
            this.dashboardData = page?.payload || null;
            if (this.expandedFamilies.size === 0 && this.dashboardData?.familyBreakdown?.length) {
                this.expandedFamilies = new Set([this.dashboardData.familyBreakdown[0].family]);
            }
            this.refs.agentInsights?.refreshFromParent?.(this.filterStateForInsights);
        } catch (error) {
            if (requestId !== this.requestSeq) {
                return;
            }
            this.dashboardData = null;
            this.toast('Dashboard error', this.reduceError(error), 'error');
        } finally {
            if (requestId === this.requestSeq) {
                this.isLoading = false;
                this.loadProgress = '';
            }
        }
    }

    toApexDate(dateObj) {
        const year = dateObj.getFullYear();
        const month = String(dateObj.getMonth() + 1).padStart(2, '0');
        const day = String(dateObj.getDate()).padStart(2, '0');
        return `${year}-${month}-${day}`;
    }

    formatMonthKeyLabel(monthKey) {
        const date = parseMonthInput(monthKey);
        if (!date) {
            return monthKey;
        }
        return date.toLocaleDateString(undefined, { month: 'short', year: 'numeric' });
    }

    toast(title, message, variant) {
        this.dispatchEvent(new ShowToastEvent({ title, message, variant }));
    }

    reduceError(error) {
        return error?.body?.message || error?.message || 'Unknown error';
    }
}