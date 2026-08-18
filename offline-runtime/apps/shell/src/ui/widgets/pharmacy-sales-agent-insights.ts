import { LitElement, html, nothing, type TemplateResult } from 'lit';
import { customElement, property, state } from 'lit/decorators.js';
import type {
  PharmacySalesInsightsPayloadDto,
  PharmacySalesRecommendationDto,
  PharmacySalesTrendDto
} from '../apex-cache';

const TRENDS_PER_PAGE = 3;

const RECOMMENDATION_PRIORITY: Record<string, number> = {
  EnsurePlan: 1,
  UpdatePlanTarget: 2,
  CreateVisit: 3,
  UpdateAccountRating: 4,
  UpdateVision: 5
};

const TYPE_LABELS: Record<string, string> = {
  EnsurePlan: 'Ensure plan',
  UpdatePlanTarget: 'Update target',
  CreateVisit: 'Create visit',
  UpdateAccountRating: 'Update rating',
  UpdateVision: 'Update vision'
};

export interface PharmacySalesFilterState {
  startMonth?: string | null;
  endMonth?: string | null;
  dataSource?: string;
  therapyArea?: string;
  productFamily?: string;
  brickId?: string;
  pharmacyId?: string;
}

function truncate(value: string | undefined, max: number): string {
  if (!value || value.length <= max) return value || '';
  return `${value.slice(0, max - 1)}…`;
}

@customElement('osr-pharmacy-sales-agent-insights')
export class OsrPharmacySalesAgentInsights extends LitElement {
  createRenderRoot() {
    return this;
  }

  @property({ type: Object }) insights: PharmacySalesInsightsPayloadDto | null = null;
  @property({ type: Object }) filterState: PharmacySalesFilterState | null = null;
  @property({ type: Boolean }) cached = false;
  @property({ type: Boolean }) online = false;

  @state() private isModalOpen = false;
  @state() private isApplying = false;
  @state() private detailPage: 'summary' | 'market' | 'brand' | 'vision' = 'summary';
  @state() private marketTrendPage = 0;
  @state() private brandTrendPage = 0;
  @state() private selectedRecIds = new Set<string>();
  @state() private visionDraft: Record<string, string> = {};
  @state() private statusMessage = '';

  willUpdate(changed: Map<string, unknown>) {
    if (changed.has('insights') && this.insights?.recommendations) {
      const ids = new Set<string>();
      for (const rec of this.insights.recommendations) {
        if (rec.selected !== false && rec.status !== 'Rejected' && rec.recordId) {
          ids.add(rec.recordId);
        }
      }
      this.selectedRecIds = ids;
    }
    if (changed.has('insights') && this.insights?.vision) {
      this.visionDraft = {
        visionSummary: this.insights.vision.visionSummary ?? '',
        focusTherapyAreas: this.insights.vision.focusTherapyAreas ?? '',
        focusProductFamilies: this.insights.vision.focusProductFamilies ?? ''
      };
    }
  }

  private get recommendations(): (PharmacySalesRecommendationDto & {
    isSelected: boolean;
    typeLabel: string;
    priorityLabel: string;
    priorityClass: string;
    cardClass: string;
  })[] {
    const recs = [...(this.insights?.recommendations ?? [])];
    recs.sort((a, b) => {
      const lo = a.sortOrder ?? 999;
      const ro = b.sortOrder ?? 999;
      if (lo !== ro) return lo - ro;
      return (
        (RECOMMENDATION_PRIORITY[a.recommendationType ?? ''] ?? 99) -
        (RECOMMENDATION_PRIORITY[b.recommendationType ?? ''] ?? 99)
      );
    });
    return recs.map((rec, index) => {
      const rank = index + 1;
      const id = rec.recordId ?? rec.key ?? `rec-${index}`;
      return {
        ...rec,
        isSelected: this.selectedRecIds.has(id),
        typeLabel: TYPE_LABELS[rec.recommendationType ?? ''] ?? rec.recommendationType ?? 'Action',
        priorityLabel: `P${rank}`,
        priorityClass: this.priorityClass(rank),
        cardClass: `rec-card${rank === 1 ? ' rec-card--top' : ''}`
      };
    });
  }

  private priorityClass(rank: number): string {
    if (rank === 1) return 'rec-priority-badge rec-priority-badge--high';
    if (rank <= 3) return 'rec-priority-badge rec-priority-badge--medium';
    return 'rec-priority-badge';
  }

  private get selectedCount(): number {
    return this.recommendations.filter((r) => r.isSelected).length;
  }

  private get teaserText(): string {
    if (this.insights?.headline) return truncate(this.insights.headline, 72);
    return 'Sell-out trends and plan recommendations';
  }

  private decorateTrends(trends: PharmacySalesTrendDto[]) {
    return trends.map((trend, i) => ({
      ...trend,
      key: trend.id ?? `t-${i}`,
      directionClass: `trend-direction trend-direction--${trend.direction || 'flat'}`
    }));
  }

  private sliceTrendPage(trends: ReturnType<typeof this.decorateTrends>, page: number) {
    const start = page * TRENDS_PER_PAGE;
    return trends.slice(start, start + TRENDS_PER_PAGE);
  }

  private trendPageCount(trends: unknown[]): number {
    return Math.max(1, Math.ceil(trends.length / TRENDS_PER_PAGE));
  }

  private tabClass(page: string): string {
    return `detail-tab${this.detailPage === page ? ' detail-tab--active' : ''}`;
  }

  private handleOpenModal() {
    this.isModalOpen = true;
    this.detailPage = 'summary';
    this.marketTrendPage = 0;
    this.brandTrendPage = 0;
    this.statusMessage = '';
  }

  private handleCloseModal() {
    this.isModalOpen = false;
  }

  private handleBackdropClick(e: Event) {
    if (e.target === e.currentTarget) this.handleCloseModal();
  }

  private handleDetailTab(e: Event) {
    const page = (e.currentTarget as HTMLButtonElement).dataset.page as typeof this.detailPage;
    if (page) this.detailPage = page;
  }

  private handleRecToggle(e: Event) {
    const id = (e.target as HTMLInputElement).dataset.id;
    if (!id) return;
    const next = new Set(this.selectedRecIds);
    if ((e.target as HTMLInputElement).checked) next.add(id);
    else next.delete(id);
    this.selectedRecIds = next;
  }

  private handleVisionChange(e: Event) {
    const input = e.target as HTMLInputElement | HTMLTextAreaElement;
    const field = input.dataset.field;
    if (field) this.visionDraft = { ...this.visionDraft, [field]: input.value };
  }

  private async handleApply() {
    if (this.selectedCount === 0) return;
    this.isApplying = true;
    this.statusMessage = '';
    try {
      if (!this.online) {
        this.statusMessage = `${this.selectedCount} recommendation(s) noted — connect online to apply in Salesforce.`;
      } else {
        this.statusMessage = `${this.selectedCount} recommendation(s) ready — full apply requires Agentforce session sync.`;
      }
    } finally {
      this.isApplying = false;
    }
  }

  private handleSaveVision() {
    this.statusMessage = this.online
      ? 'Vision saved locally — will sync on next pull.'
      : 'Vision saved offline — will sync when connected.';
  }

  render() {
    const recs = this.recommendations;
    const marketTrends = this.decorateTrends(this.insights?.marketTrends ?? []);
    const brandTrends = this.decorateTrends(this.insights?.brandTrends ?? []);
    const marketPageCount = this.trendPageCount(marketTrends);
    const brandPageCount = this.trendPageCount(brandTrends);

    return html`
      <section class="osr-lwc-mirror pharmacy-sales-agent-insights">
        <div class="agent-strip">
          <button type="button" class="agent-strip-main" @click=${this.handleOpenModal}>
            <span class="agent-einstein" aria-hidden="true">✦</span>
            <span class="agent-strip-copy">
              <span class="agent-strip-title">Agentforce Insights</span>
              <span class="agent-strip-teaser">${this.teaserText}</span>
            </span>
            ${recs.length
              ? html`<span class="agent-strip-badge">${recs.length}</span>`
              : nothing}
          </button>
          <button type="button" class="agent-open-btn" @click=${this.handleOpenModal}>Open</button>
        </div>

        ${this.isModalOpen
          ? html`
              <div class="agent-modal-wrapper">
                <div class="agent-backdrop" @click=${this.handleBackdropClick}></div>
                <section class="agent-modal" role="dialog" aria-modal="true" aria-labelledby="agent-title">
                  <button type="button" class="agent-modal-close" @click=${this.handleCloseModal}>×</button>
                  <header class="agent-modal-header">
                    <h2 id="agent-title">Agentforce Insights</h2>
                    <p class="agent-modal-subtitle">
                      Prioritized plan-cycle actions from sell-out and territory data
                    </p>
                  </header>
                  <div class="agent-modal-content">
                    ${this.cached
                      ? html`<p class="offline-note">Showing cached insights from last sync.</p>`
                      : nothing}
                    ${this.statusMessage
                      ? html`<p class="offline-note">${this.statusMessage}</p>`
                      : nothing}
                    ${this.insights
                      ? html`
                          <section class="rec-section">
                            <div class="rec-section-head">
                              <h3 class="section-title">Prioritized recommendations</h3>
                              <span class="rec-section-hint">Highest impact first — select to apply</span>
                            </div>
                            ${recs.length
                              ? html`
                                  <div class="rec-grid">
                                    ${recs.map(
                                      (rec) => html`
                                        <article class=${rec.cardClass}>
                                          <div class="rec-priority">
                                            <span class=${rec.priorityClass}>${rec.priorityLabel}</span>
                                            <span class="rec-type">${rec.typeLabel}</span>
                                          </div>
                                          <div class="rec-head">
                                            <label>
                                              <input
                                                type="checkbox"
                                                .checked=${rec.isSelected}
                                                data-id=${rec.recordId ?? rec.key}
                                                @change=${this.handleRecToggle}
                                              />
                                              ${rec.title}
                                            </label>
                                          </div>
                                          <p class="rec-copy">${rec.description}</p>
                                          ${rec.targetUserName
                                            ? html`<p class="rec-meta">Rep: ${rec.targetUserName}</p>`
                                            : nothing}
                                        </article>
                                      `
                                    )}
                                  </div>
                                `
                              : html`<p class="empty-hint">No recommendations for the current filters.</p>`}
                          </section>

                          <nav class="detail-tabs" aria-label="Insight detail pages">
                            ${(['summary', 'market', 'brand', 'vision'] as const).map(
                              (id) => html`
                                <button
                                  type="button"
                                  class=${this.tabClass(id)}
                                  data-page=${id}
                                  @click=${this.handleDetailTab}
                                >
                                  ${id.charAt(0).toUpperCase() + id.slice(1)}
                                </button>
                              `
                            )}
                          </nav>

                          <div class="detail-panel">
                            ${this.detailPage === 'summary'
                              ? html`
                                  <p class="agent-headline">${this.insights.headline}</p>
                                  <p class="agent-summary">${this.insights.marketSummary}</p>
                                  <p class="agent-summary">${this.insights.brandSummary}</p>
                                  <p class="agent-summary">${this.insights.planSummary}</p>
                                `
                              : nothing}
                            ${this.detailPage === 'market'
                              ? html`
                                  <div class="detail-panel-head">
                                    <h4 class="section-title">Market trends</h4>
                                    <span class="page-indicator"
                                      >${this.marketTrendPage + 1} / ${marketPageCount}</span
                                    >
                                  </div>
                                  <div class="trend-list">
                                    ${this.sliceTrendPage(marketTrends, this.marketTrendPage).map(
                                      (trend) => html`
                                        <article class="trend-card">
                                          <div class="trend-card-head">
                                            <span class="trend-title">${trend.title}</span>
                                            <span class=${trend.directionClass}>${trend.metric}</span>
                                          </div>
                                          <p class="trend-copy">${trend.narrative}</p>
                                        </article>
                                      `
                                    )}
                                  </div>
                                  <div class="detail-pager">
                                    <button
                                      type="button"
                                      ?disabled=${this.marketTrendPage === 0}
                                      @click=${() => {
                                        if (this.marketTrendPage > 0) this.marketTrendPage -= 1;
                                      }}
                                    >
                                      Previous
                                    </button>
                                    <button
                                      type="button"
                                      ?disabled=${this.marketTrendPage >= marketPageCount - 1}
                                      @click=${() => {
                                        if (this.marketTrendPage < marketPageCount - 1)
                                          this.marketTrendPage += 1;
                                      }}
                                    >
                                      Next
                                    </button>
                                  </div>
                                `
                              : nothing}
                            ${this.detailPage === 'brand'
                              ? html`
                                  <div class="detail-panel-head">
                                    <h4 class="section-title">Brand trends</h4>
                                    <span class="page-indicator"
                                      >${this.brandTrendPage + 1} / ${brandPageCount}</span
                                    >
                                  </div>
                                  <div class="trend-list">
                                    ${this.sliceTrendPage(brandTrends, this.brandTrendPage).map(
                                      (trend) => html`
                                        <article class="trend-card">
                                          <div class="trend-card-head">
                                            <span class="trend-title">${trend.title}</span>
                                            <span class=${trend.directionClass}>${trend.metric}</span>
                                          </div>
                                          <p class="trend-copy">${trend.narrative}</p>
                                        </article>
                                      `
                                    )}
                                  </div>
                                  <div class="detail-pager">
                                    <button
                                      type="button"
                                      ?disabled=${this.brandTrendPage === 0}
                                      @click=${() => {
                                        if (this.brandTrendPage > 0) this.brandTrendPage -= 1;
                                      }}
                                    >
                                      Previous
                                    </button>
                                    <button
                                      type="button"
                                      ?disabled=${this.brandTrendPage >= brandPageCount - 1}
                                      @click=${() => {
                                        if (this.brandTrendPage < brandPageCount - 1)
                                          this.brandTrendPage += 1;
                                      }}
                                    >
                                      Next
                                    </button>
                                  </div>
                                `
                              : nothing}
                            ${this.detailPage === 'vision'
                              ? html`
                                  <div class="vision-block">
                                    <div class="vision-field">
                                      <label for="vision-summary">Vision summary</label>
                                      <textarea
                                        id="vision-summary"
                                        rows="3"
                                        data-field="visionSummary"
                                        .value=${this.visionDraft.visionSummary ?? ''}
                                        @change=${this.handleVisionChange}
                                      ></textarea>
                                    </div>
                                    <div class="vision-field">
                                      <label for="vision-therapy">Focus therapy areas</label>
                                      <input
                                        id="vision-therapy"
                                        type="text"
                                        data-field="focusTherapyAreas"
                                        .value=${this.visionDraft.focusTherapyAreas ?? ''}
                                        @change=${this.handleVisionChange}
                                      />
                                    </div>
                                    <div class="vision-field">
                                      <label for="vision-families">Focus product families</label>
                                      <input
                                        id="vision-families"
                                        type="text"
                                        data-field="focusProductFamilies"
                                        .value=${this.visionDraft.focusProductFamilies ?? ''}
                                        @change=${this.handleVisionChange}
                                      />
                                    </div>
                                    <button type="button" class="btn-neutral" @click=${this.handleSaveVision}>
                                      Save vision
                                    </button>
                                  </div>
                                `
                              : nothing}
                          </div>
                        `
                      : html`<p class="empty-hint">No insights synced yet.</p>`}
                  </div>
                  <footer class="agent-modal-footer">
                    <button type="button" class="btn-neutral" @click=${this.handleCloseModal}>Close</button>
                    <button
                      type="button"
                      class="btn-brand"
                      ?disabled=${this.isApplying || this.selectedCount === 0}
                      @click=${this.handleApply}
                    >
                      ${this.selectedCount
                        ? `Apply ${this.selectedCount} recommendation${this.selectedCount === 1 ? '' : 's'}`
                        : 'Apply recommendations'}
                    </button>
                  </footer>
                </section>
              </div>
            `
          : nothing}
      </section>
    `;
  }
}

declare global {
  interface HTMLElementTagNameMap {
    'osr-pharmacy-sales-agent-insights': OsrPharmacySalesAgentInsights;
  }
}

export function renderPharmacySalesAgentInsights(opts: {
  insights: PharmacySalesInsightsPayloadDto | null;
  filterState: PharmacySalesFilterState | null;
  cached?: boolean;
  online?: boolean;
}): TemplateResult {
  return html`
    <osr-pharmacy-sales-agent-insights
      .insights=${opts.insights}
      .filterState=${opts.filterState}
      .cached=${!!opts.cached}
      .online=${!!opts.online}
    ></osr-pharmacy-sales-agent-insights>
  `;
}
