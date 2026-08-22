import { LitElement, html, nothing, type TemplateResult } from 'lit';
import { customElement, property, state } from 'lit/decorators.js';
import type {
  PharmacySalesCachePayload,
  PharmacySalesDetailRowDto,
  PharmacySalesFilterOptionsDto,
  PharmacySalesInsightsPayloadDto,
  PharmacySalesOptionDto
} from '../apex-cache';
import './pharmacy-sales-agent-insights';
import type { PharmacySalesFilterState } from './pharmacy-sales-agent-insights';

const PRESET_MONTHS = [
  { id: '3', label: 'Last 3 months', months: 3 },
  { id: '6', label: 'Last 6 months', months: 6 },
  { id: '12', label: 'Last 12 months', months: 12 }
];

const MAX_DETAIL_ROWS = 500;

function monthInputValue(dateObj: Date): string {
  const year = dateObj.getFullYear();
  const month = String(dateObj.getMonth() + 1).padStart(2, '0');
  return `${year}-${month}`;
}

function parseMonthInput(value: string): Date | null {
  if (!value) return null;
  const [year, month] = value.split('-').map((part) => parseInt(part, 10));
  return new Date(year, month - 1, 1);
}

function formatNumber(value: number): string {
  const num = Number(value || 0);
  if (num >= 1000000) return `${(num / 1000000).toFixed(1)}M`;
  if (num >= 1000) return `${(num / 1000).toFixed(1)}K`;
  return num.toLocaleString(undefined, { maximumFractionDigits: 0 });
}

function formatCurrency(value: number): string {
  const num = Number(value || 0);
  return num.toLocaleString(undefined, { style: 'currency', currency: 'EGP', maximumFractionDigits: 0 });
}

function formatRoiPercent(value: number | null | undefined): string {
  if (value === null || value === undefined) return '—';
  const num = Number(value);
  if (!Number.isFinite(num)) return '—';
  const sign = num > 0 ? '+' : '';
  return `${sign}${num.toFixed(1)}%`;
}

function roiToneClass(roiPercent: number | null | undefined): string {
  const num = Number(roiPercent);
  if (!Number.isFinite(num)) return 'roi-neutral';
  if (num >= 0) return 'roi-positive';
  return 'roi-negative';
}

function buildRoiBreakdown(visits: number, commute: number): string {
  return `${visits} visits with detailing · ${formatCurrency(commute)} commute`;
}

function optionsOrDefault(
  list: PharmacySalesOptionDto[] | undefined,
  fallback: PharmacySalesOptionDto[]
): PharmacySalesOptionDto[] {
  return list?.length ? list : fallback;
}

function rowInRange(row: PharmacySalesDetailRowDto, start: string, end: string): boolean {
  const key = row.monthKey ?? '';
  if (!key) return true;
  if (start && key < start) return false;
  if (end && key > end) return false;
  return true;
}

function matchesFilter(value: string | undefined, selected: string): boolean {
  return selected === 'All' || !selected || value === selected;
}

interface ProductAgg {
  productId: string;
  productName: string;
  quantity: number;
  revenue: number;
  visitCountWithDetailing: number;
  commuteCostEstimate: number;
  roiPercent: number;
  percentOfFamily?: number;
}

interface FamilyAgg {
  family: string;
  therapyArea: string;
  quantity: number;
  revenue: number;
  visitCountWithDetailing: number;
  commuteCostEstimate: number;
  roiPercent: number;
  products: ProductAgg[];
}

interface DashboardView {
  kpis: {
    totalRevenue: number;
    totalQuantity: number;
    pharmacyCount: number;
    productCount: number;
  };
  familyBreakdown: FamilyAgg[];
  matrixMonthKeys: string[];
  brickMonthMatrix: {
    brickId: string;
    brickName: string;
    cells: { monthKey: string; revenue: number }[];
    rowTotal: number;
  }[];
  detailRows: PharmacySalesDetailRowDto[];
}

function computeDashboard(
  rows: PharmacySalesDetailRowDto[],
  filters: {
    startMonth: string;
    endMonth: string;
    dataSource: string;
    therapyArea: string;
    productFamily: string;
    brickId: string;
    pharmacyId: string;
  }
): DashboardView {
  const filtered = rows.filter((row) => {
    if (!rowInRange(row, filters.startMonth, filters.endMonth)) return false;
    if (!matchesFilter(row.dataSource, filters.dataSource)) return false;
    if (!matchesFilter(row.therapyArea, filters.therapyArea)) return false;
    if (!matchesFilter(row.productFamily, filters.productFamily)) return false;
    if (!matchesFilter(row.brickId, filters.brickId)) return false;
    if (!matchesFilter(row.pharmacyId, filters.pharmacyId)) return false;
    return true;
  });

  const pharmacyIds = new Set<string>();
  const productIds = new Set<string>();
  let totalRevenue = 0;
  let totalQuantity = 0;

  const familyMap = new Map<string, FamilyAgg>();
  const matrix = new Map<string, Map<string, number>>();
  const brickNames = new Map<string, string>();
  const monthKeys = new Set<string>();

  for (const row of filtered) {
    totalRevenue += Number(row.revenue ?? 0);
    totalQuantity += Number(row.quantity ?? 0);
    if (row.pharmacyId) pharmacyIds.add(row.pharmacyId);
    if (row.productId) productIds.add(row.productId);
    if (row.monthKey) monthKeys.add(row.monthKey);
    if (row.brickId) {
      brickNames.set(row.brickId, row.brickName ?? row.brickId);
      if (!matrix.has(row.brickId)) matrix.set(row.brickId, new Map());
      const cells = matrix.get(row.brickId)!;
      const mk = row.monthKey ?? '';
      cells.set(mk, (cells.get(mk) ?? 0) + Number(row.revenue ?? 0));
    }

    const familyKey = row.productFamily ?? 'Unknown';
    let family = familyMap.get(familyKey);
    if (!family) {
      family = {
        family: familyKey,
        therapyArea: row.therapyArea ?? '—',
        quantity: 0,
        revenue: 0,
        visitCountWithDetailing: 0,
        commuteCostEstimate: 0,
        roiPercent: 0,
        products: []
      };
      familyMap.set(familyKey, family);
    }
    family.quantity += Number(row.quantity ?? 0);
    family.revenue += Number(row.revenue ?? 0);
    family.visitCountWithDetailing += Number(row.visitCountWithDetailing ?? 0);
    family.commuteCostEstimate += Number(row.commuteCostEstimate ?? 0);

    const pid = row.productId ?? row.productName ?? 'unknown';
    let product = family.products.find((p) => p.productId === pid);
    if (!product) {
      product = {
        productId: pid,
        productName: row.productName ?? pid,
        quantity: 0,
        revenue: 0,
        visitCountWithDetailing: 0,
        commuteCostEstimate: 0,
        roiPercent: 0
      };
      family.products.push(product);
    }
    product.quantity += Number(row.quantity ?? 0);
    product.revenue += Number(row.revenue ?? 0);
    product.visitCountWithDetailing += Number(row.visitCountWithDetailing ?? 0);
    product.commuteCostEstimate += Number(row.commuteCostEstimate ?? 0);
    product.roiPercent = Number(row.roiPercent ?? product.roiPercent);
  }

  const familyBreakdown = [...familyMap.values()]
    .map((family) => {
      family.products.sort((a, b) => b.revenue - a.revenue);
      for (const product of family.products) {
        product.roiPercent =
          product.revenue > 0
            ? ((product.revenue - product.commuteCostEstimate) / product.revenue) * 100 - 15
            : 0;
        product.roiPercent = Math.round(product.roiPercent * 10) / 10;
      }
      const familyRevenue = family.revenue || 1;
      for (const product of family.products) {
        product.percentOfFamily = Math.round((product.revenue / familyRevenue) * 100);
      }
      family.roiPercent =
        family.revenue > 0
          ? ((family.revenue - family.commuteCostEstimate) / family.revenue) * 100 - 12
          : 0;
      family.roiPercent = Math.round(family.roiPercent * 10) / 10;
      return family;
    })
    .sort((a, b) => b.revenue - a.revenue);

  const sortedMonthKeys = [...monthKeys].sort();
  const brickMonthMatrix = [...matrix.entries()]
    .map(([brickId, cells]) => {
      let rowTotal = 0;
      const cellList = sortedMonthKeys.map((monthKey) => {
        const revenue = cells.get(monthKey) ?? 0;
        rowTotal += revenue;
        return { monthKey, revenue };
      });
      return {
        brickId,
        brickName: brickNames.get(brickId) ?? brickId,
        cells: cellList,
        rowTotal
      };
    })
    .sort((a, b) => b.rowTotal - a.rowTotal);

  return {
    kpis: {
      totalRevenue,
      totalQuantity,
      pharmacyCount: pharmacyIds.size,
      productCount: productIds.size
    },
    familyBreakdown,
    matrixMonthKeys: sortedMonthKeys,
    brickMonthMatrix,
    detailRows: filtered.slice(0, MAX_DETAIL_ROWS)
  };
}

@customElement('osr-pharmacy-sales-dashboard')
export class OsrPharmacySalesDashboard extends LitElement {
  createRenderRoot() {
    return this;
  }

  @property({ type: Object }) data: PharmacySalesCachePayload | null = null;
  @property({ type: Object }) insights: PharmacySalesInsightsPayloadDto | null = null;
  @property({ type: Boolean }) cached = false;
  @property({ type: Boolean }) online = false;

  @state() private startMonthValue = '';
  @state() private endMonthValue = '';
  @state() private dataSource = 'All';
  @state() private therapyArea = 'All';
  @state() private productFamily = 'All';
  @state() private brickId = 'All';
  @state() private pharmacyId = 'All';
  @state() private activePreset = '6';
  @state() private filtersExpanded = false;
  @state() private expandedFamilies = new Set<string>();

  connectedCallback() {
    super.connectedCallback();
    this.applyPreset(6);
    if (typeof window !== 'undefined' && window.matchMedia('(max-width: 47.99rem)').matches) {
      this.filtersExpanded = true;
    }
  }

  private applyPreset(months: number) {
    const end = new Date();
    end.setDate(1);
    const start = new Date(end);
    start.setMonth(start.getMonth() - (months - 1));
    this.startMonthValue = monthInputValue(start);
    this.endMonthValue = monthInputValue(end);
  }

  private get currentFilterState(): PharmacySalesFilterState {
    return {
      startMonth: this.startMonthValue || null,
      endMonth: this.endMonthValue || null,
      dataSource: this.dataSource,
      therapyArea: this.therapyArea,
      productFamily: this.productFamily,
      brickId: this.brickId,
      pharmacyId: this.pharmacyId
    };
  }

  private get filterOptions(): PharmacySalesFilterOptionsDto {
    return (
      this.data?.filterOptions ?? {
        therapyAreas: [{ value: 'All', label: 'All' }],
        productFamilies: [{ value: 'All', label: 'All' }],
        bricks: [{ value: 'All', label: 'All' }],
        pharmacies: [{ value: 'All', label: 'All' }],
        dataSources: [
          { value: 'All', label: 'All' },
          { value: 'IbnSina', label: 'IbnSina' },
          { value: 'Pharmaoverseas', label: 'Pharmaoverseas' }
        ]
      }
    );
  }

  private get dashboard(): DashboardView {
    const rows = this.data?.detailRows ?? [];
    return computeDashboard(rows, {
      startMonth: this.startMonthValue,
      endMonth: this.endMonthValue,
      dataSource: this.dataSource,
      therapyArea: this.therapyArea,
      productFamily: this.productFamily,
      brickId: this.brickId,
      pharmacyId: this.pharmacyId
    });
  }

  private renderSelect(
    label: string,
    field: string,
    value: string,
    options: PharmacySalesOptionDto[]
  ) {
    return html`
      <div class="filter-field">
        <label for=${field}>${label}</label>
        <select id=${field} data-field=${field} .value=${value} @change=${this.handleSelectChange}>
          ${options.map(
            (opt) => html`
              <option value=${opt.value ?? 'All'}>${opt.label ?? opt.value}</option>
            `
          )}
        </select>
      </div>
    `;
  }

  private handleFiltersToggle() {
    this.filtersExpanded = !this.filtersExpanded;
  }

  private handlePresetClick(e: Event) {
    const btn = e.currentTarget as HTMLButtonElement;
    const months = parseInt(btn.dataset.months ?? '6', 10);
    this.activePreset = btn.dataset.presetId ?? '';
    this.applyPreset(months);
  }

  private handleMonthChange(e: Event) {
    const input = e.target as HTMLInputElement;
    if (input.id === 'ps-start-month') this.startMonthValue = input.value;
    else this.endMonthValue = input.value;
    this.activePreset = '';
  }

  private handleSelectChange(e: Event) {
    const select = e.target as HTMLSelectElement;
    const field = select.dataset.field;
    const value = select.value;
    if (field === 'dataSource') this.dataSource = value;
    else if (field === 'therapyArea') this.therapyArea = value;
    else if (field === 'productFamily') this.productFamily = value;
    else if (field === 'brickId') this.brickId = value;
    else if (field === 'pharmacyId') this.pharmacyId = value;
  }

  private handleFamilyToggle(e: Event) {
    const family = (e.currentTarget as HTMLButtonElement).dataset.family;
    if (!family) return;
    const next = new Set(this.expandedFamilies);
    if (next.has(family)) next.delete(family);
    else next.add(family);
    this.expandedFamilies = next;
  }

  private handleMatrixCellClick(e: Event) {
    const btn = e.currentTarget as HTMLButtonElement;
    const brick = btn.dataset.brickId;
    const monthKey = btn.dataset.monthKey;
    if (!brick || !monthKey || btn.disabled) return;
    this.brickId = brick;
    this.startMonthValue = monthKey;
    this.endMonthValue = monthKey;
    this.activePreset = '';
    this.filtersExpanded = true;
  }

  private formatMonthKeyLabel(monthKey: string): string {
    const date = parseMonthInput(monthKey.length === 7 ? monthKey : monthKey.slice(0, 7));
    if (!date) return monthKey;
    return date.toLocaleDateString(undefined, { month: 'short', year: 'numeric' });
  }

  render() {
    const dash = this.dashboard;
    const opts = this.filterOptions;
    const hasData = (this.data?.detailRows?.length ?? 0) > 0;
    const filtersClass = `filters${this.filtersExpanded ? ' filters--open' : ''}`;

    if (!hasData) {
      return html`
        <article class="osr-lwc-mirror pharmacy-sales-dashboard sales-card">
          <header class="sales-header">
            <h2 class="sales-title">Pharmacy Sales Analytics</h2>
            <p class="sales-subtitle">Withdrawals and revenue by product, brick, and data source</p>
            ${this.cached ? html`<span class="cached-pill">Offline cache</span>` : nothing}
          </header>
          <section class="panel">
            <p class="empty-copy">
              No pharmacy sell-out data synced yet. Connect online to pull sales withdrawals, or use
              demo mode.
            </p>
          </section>
        </article>
      `;
    }

    const kpiCards = [
      {
        id: 'revenue',
        label: 'Total Revenue',
        value: formatCurrency(dash.kpis.totalRevenue),
        hint: 'EGP across filters'
      },
      {
        id: 'qty',
        label: 'Units Withdrawn',
        value: formatNumber(dash.kpis.totalQuantity),
        hint: 'Total quantity'
      },
      {
        id: 'pharmacies',
        label: 'Pharmacies',
        value: String(dash.kpis.pharmacyCount),
        hint: 'Active in range'
      },
      {
        id: 'products',
        label: 'Products',
        value: String(dash.kpis.productCount),
        hint: 'Distinct SKUs'
      }
    ];

    return html`
      <article class="osr-lwc-mirror pharmacy-sales-dashboard sales-card">
        <header class="sales-header">
          <h2 class="sales-title">Pharmacy Sales Analytics</h2>
          <p class="sales-subtitle">Withdrawals and revenue by product, brick, and data source</p>
          ${this.cached ? html`<span class="cached-pill">Offline cache</span>` : nothing}
        </header>

        <section class=${filtersClass}>
          <button type="button" class="filters-toggle" @click=${this.handleFiltersToggle}>
            ${this.filtersExpanded ? 'Hide filters' : 'Show filters'}
          </button>
          <div class="filters-body">
            <div class="filters-row filters-row--dates">
              <div class="filter-field">
                <label for="ps-start-month">From</label>
                <input
                  id="ps-start-month"
                  type="month"
                  .value=${this.startMonthValue}
                  @change=${this.handleMonthChange}
                />
              </div>
              <div class="filter-field">
                <label for="ps-end-month">To</label>
                <input
                  id="ps-end-month"
                  type="month"
                  .value=${this.endMonthValue}
                  @change=${this.handleMonthChange}
                />
              </div>
            </div>
            <div class="preset-group">
              <span class="preset-label">Quick range</span>
              <div class="preset-chips">
                ${PRESET_MONTHS.map(
                  (preset) => html`
                    <button
                      type="button"
                      class="preset-chip${this.activePreset === preset.id ? ' preset-chip--active' : ''}"
                      data-preset-id=${preset.id}
                      data-months=${String(preset.months)}
                      @click=${this.handlePresetClick}
                    >
                      ${preset.label}
                    </button>
                  `
                )}
              </div>
            </div>
            <div class="filters-row filters-row--compact">
              ${this.renderSelect(
                'Data Source',
                'dataSource',
                this.dataSource,
                optionsOrDefault(opts.dataSources, [
                  { value: 'All', label: 'All' },
                  { value: 'IbnSina', label: 'IbnSina' },
                  { value: 'Pharmaoverseas', label: 'Pharmaoverseas' }
                ])
              )}
              ${this.renderSelect(
                'Therapy Area',
                'therapyArea',
                this.therapyArea,
                optionsOrDefault(opts.therapyAreas, [{ value: 'All', label: 'All' }])
              )}
              ${this.renderSelect(
                'Product Family',
                'productFamily',
                this.productFamily,
                optionsOrDefault(opts.productFamilies, [{ value: 'All', label: 'All' }])
              )}
              ${this.renderSelect(
                'Brick',
                'brickId',
                this.brickId,
                optionsOrDefault(opts.bricks, [{ value: 'All', label: 'All' }])
              )}
              ${this.renderSelect(
                'Pharmacy',
                'pharmacyId',
                this.pharmacyId,
                optionsOrDefault(opts.pharmacies, [{ value: 'All', label: 'All' }])
              )}
            </div>
          </div>
        </section>

        <osr-pharmacy-sales-agent-insights
          .insights=${this.insights}
          .filterState=${this.currentFilterState}
          .cached=${this.cached}
          .online=${this.online}
        ></osr-pharmacy-sales-agent-insights>

        <section class="kpi-strip">
          ${kpiCards.map(
            (kpi) => html`
              <div class="kpi-tile">
                <span class="kpi-tile-label">${kpi.label}</span>
                <span class="kpi-tile-value">${kpi.value}</span>
                <span class="kpi-tile-hint">${kpi.hint}</span>
              </div>
            `
          )}
        </section>

        <section class="panel">
          <h3 class="panel-title">Product Family Breakdown</h3>
          ${dash.familyBreakdown.length
            ? dash.familyBreakdown.map((family) => {
                const expanded = this.expandedFamilies.has(family.family);
                return html`
                  <article class="family-card">
                    <button
                      type="button"
                      class="family-header"
                      data-family=${family.family}
                      @click=${this.handleFamilyToggle}
                    >
                      <span class="family-chevron${expanded ? ' family-chevron--open' : ''}">›</span>
                      <span class="family-name">${family.family}</span>
                      <span class="family-badge">${family.therapyArea}</span>
                      <span class="family-metrics">
                        <span>${formatNumber(family.quantity)} units</span>
                        <span>${formatCurrency(family.revenue)}</span>
                        <span class=${roiToneClass(family.roiPercent)}
                          >ROI ${formatRoiPercent(family.roiPercent)}</span
                        >
                      </span>
                      <span class="family-roi-breakdown"
                        >${buildRoiBreakdown(
                          family.visitCountWithDetailing,
                          family.commuteCostEstimate
                        )}</span
                      >
                    </button>
                    ${expanded
                      ? html`
                          <div class="family-products">
                            ${family.products.map(
                              (product) => html`
                                <div class="product-row">
                                  <div class="product-image--placeholder" aria-hidden="true">💊</div>
                                  <div class="product-meta">
                                    <span class="product-name">${product.productName}</span>
                                    <span class="product-stats">
                                      ${formatNumber(product.quantity)} units ·
                                      ${formatCurrency(product.revenue)} ·
                                      ${product.percentOfFamily ?? 0}%
                                    </span>
                                    <span class="product-roi">
                                      <span class=${roiToneClass(product.roiPercent)}
                                        >ROI ${formatRoiPercent(product.roiPercent)}</span
                                      >
                                      <span class="product-roi-detail"
                                        >${buildRoiBreakdown(
                                          product.visitCountWithDetailing,
                                          product.commuteCostEstimate
                                        )}</span
                                      >
                                    </span>
                                  </div>
                                </div>
                              `
                            )}
                          </div>
                        `
                      : nothing}
                  </article>
                `;
              })
            : html`<p class="empty-copy">No product sales match the current filters.</p>`}
        </section>

        <section class="panel">
          <h3 class="panel-title">Revenue by Brick and Month</h3>
          ${dash.brickMonthMatrix.length
            ? html`
                <div class="matrix-wrap">
                  <table class="matrix-table">
                    <thead>
                      <tr>
                        <th>Brick</th>
                        ${dash.matrixMonthKeys.map(
                          (key) => html`<th>${this.formatMonthKeyLabel(key)}</th>`
                        )}
                        <th>Total</th>
                      </tr>
                    </thead>
                    <tbody>
                      ${dash.brickMonthMatrix.map(
                        (row) => html`
                          <tr>
                            <td class="matrix-brick">${row.brickName}</td>
                            ${row.cells.map(
                              (cell) => html`
                                <td>
                                  <button
                                    type="button"
                                    class="matrix-cell"
                                    data-brick-id=${row.brickId}
                                    data-month-key=${cell.monthKey}
                                    ?disabled=${!cell.revenue}
                                    @click=${this.handleMatrixCellClick}
                                  >
                                    ${formatCurrency(cell.revenue)}
                                  </button>
                                </td>
                              `
                            )}
                            <td class="matrix-total">${formatCurrency(row.rowTotal)}</td>
                          </tr>
                        `
                      )}
                    </tbody>
                  </table>
                </div>
              `
            : html`<p class="empty-copy">No brick revenue data for the selected period.</p>`}
        </section>

        <section class="panel">
          <h3 class="panel-title">Detail</h3>
          ${dash.detailRows.length
            ? html`
                <div class="detail-table-wrap">
                  <table class="detail-table">
                    <thead>
                      <tr>
                        <th>Month</th>
                        <th>Pharmacy</th>
                        <th>Brick</th>
                        <th>Product</th>
                        <th>Family</th>
                        <th>Therapy</th>
                        <th>Source</th>
                        <th class="num">Qty</th>
                        <th class="num">Unit Price</th>
                        <th class="num">Revenue</th>
                      </tr>
                    </thead>
                    <tbody>
                      ${dash.detailRows.map(
                        (row) => html`
                          <tr>
                            <td>${row.monthLabel}</td>
                            <td>${row.pharmacyName}</td>
                            <td>${row.brickName}</td>
                            <td>${row.productName}</td>
                            <td>${row.productFamily}</td>
                            <td>${row.therapyArea}</td>
                            <td>${row.dataSource}</td>
                            <td class="num">${formatNumber(Number(row.quantity ?? 0))}</td>
                            <td class="num">${formatCurrency(Number(row.unitPrice ?? 0))}</td>
                            <td class="num">${formatCurrency(Number(row.revenue ?? 0))}</td>
                          </tr>
                        `
                      )}
                    </tbody>
                  </table>
                </div>
                <div class="detail-cards">
                  ${dash.detailRows.map(
                    (row) => html`
                      <article class="detail-card">
                        <div class="detail-card-head">
                          <span class="detail-card-month">${row.monthLabel}</span>
                          <span class="detail-card-revenue"
                            >${formatCurrency(Number(row.revenue ?? 0))}</span
                          >
                        </div>
                        <p class="detail-card-product">${row.productName}</p>
                        <p class="detail-card-meta">${row.pharmacyName} · ${row.brickName}</p>
                        <p class="detail-card-meta">${row.productFamily} · ${row.therapyArea}</p>
                        <p class="detail-card-stats">
                          ${formatNumber(Number(row.quantity ?? 0))} units ·
                          ${formatCurrency(Number(row.unitPrice ?? 0))} · ${row.dataSource}
                        </p>
                      </article>
                    `
                  )}
                </div>
              `
            : html`<p class="empty-copy">No detail rows for the selected filters.</p>`}
        </section>
      </article>
    `;
  }
}

declare global {
  interface HTMLElementTagNameMap {
    'osr-pharmacy-sales-dashboard': OsrPharmacySalesDashboard;
  }
}

export function renderPharmacySalesDashboard(opts: {
  label: string;
  data: PharmacySalesCachePayload | null;
  insights?: PharmacySalesInsightsPayloadDto | null;
  cached?: boolean;
  online?: boolean;
}): TemplateResult {
  return html`
    <osr-pharmacy-sales-dashboard
      .data=${opts.data}
      .insights=${opts.insights ?? null}
      .cached=${!!opts.cached}
      .online=${!!opts.online}
    ></osr-pharmacy-sales-dashboard>
  `;
}
