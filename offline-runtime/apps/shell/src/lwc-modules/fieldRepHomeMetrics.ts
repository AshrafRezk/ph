import { createApexInvoker } from '@osr/platform';
import { CARD_CSS, escapeHtml } from './shared';

const getMetrics = createApexInvoker('FieldRepHomeController.getHomeMetrics');

type Metrics = {
  visitCoveragePercent?: number;
  customerCoveragePercent?: number;
  lfPercentTotal?: number;
  rfPercentTotal?: number;
  mfPercentTotal?: number;
};

export default class FieldRepHomeMetrics extends HTMLElement {
  metrics: Metrics | null = null;
  loading = true;

  connectedCallback() {
    this.attachShadow({ mode: 'open' });
    void this.load();
  }

  async load() {
    this.loading = true;
    this.render();
    try {
      const raw = (await getMetrics({})) as Metrics | null;
      this.metrics = raw && typeof raw === 'object' ? raw : null;
    } catch {
      this.metrics = null;
    }
    this.loading = false;
    this.render();
  }

  pct(n?: number) {
    const v = Number(n);
    return Number.isFinite(v) ? `${Math.round(v)}%` : '—';
  }

  render() {
    if (!this.shadowRoot) return;
    const m = this.metrics;
    this.shadowRoot.innerHTML = `
      <style>${CARD_CSS}</style>
      <article>
        <header>
          <h2>Metrics</h2>
          <span class="pill">IFRAME ENGINE</span>
        </header>
        <div class="body">
          ${
            this.loading
              ? `<div class="loading">Loading…</div>`
              : !m
                ? `<div class="empty">No metrics in cache.</div>`
                : `<div class="metric-grid">
              <div class="metric"><div class="v">${escapeHtml(this.pct(m.visitCoveragePercent))}</div><div class="l">Visit coverage</div></div>
              <div class="metric"><div class="v">${escapeHtml(this.pct(m.customerCoveragePercent))}</div><div class="l">Customer coverage</div></div>
              <div class="metric"><div class="v">${escapeHtml(this.pct(m.lfPercentTotal))}</div><div class="l">LF</div></div>
              <div class="metric"><div class="v">${escapeHtml(this.pct(m.rfPercentTotal))}</div><div class="l">RF</div></div>
            </div>`
          }
        </div>
      </article>
    `;
  }
}
