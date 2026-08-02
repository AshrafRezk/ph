/**
 * Planner iframe-engine port (list week view). Full Leaflet calendar stays as Lit fallback path
 * for map mode; this CE covers offline Apex-driven week visits via the bridge.
 */
import { createApexInvoker, navigate } from '@osr/platform';
import { CARD_CSS, escapeHtml, unwrapList } from './shared';

const getPlanner = createApexInvoker('FieldPlannerController.fetchPlannerData');

type Visit = {
  id?: string;
  name?: string;
  accountName?: string;
  status?: string;
  startDateTime?: string;
};

export default class FieldRepPlanner extends HTMLElement {
  visits: Visit[] = [];
  loading = true;

  connectedCallback() {
    this.attachShadow({ mode: 'open' });
    void this.load();
  }

  async load() {
    this.loading = true;
    this.render();
    try {
      const raw = await getPlanner({});
      this.visits = unwrapList(raw) as Visit[];
      if (!this.visits.length && raw && typeof raw === 'object') {
        this.visits = unwrapList((raw as { visits?: unknown }).visits ? raw : {}) as Visit[];
        if (Array.isArray((raw as { visits?: Visit[] }).visits)) {
          this.visits = (raw as { visits: Visit[] }).visits;
        }
      }
    } catch {
      this.visits = [];
    }
    this.loading = false;
    this.render();
  }

  dayLabel(iso?: string) {
    if (!iso) return '';
    const d = new Date(iso);
    if (Number.isNaN(d.getTime())) return '';
    return d.toLocaleString(undefined, {
      weekday: 'short',
      month: 'short',
      day: 'numeric',
      hour: 'numeric',
      minute: '2-digit'
    });
  }

  render() {
    if (!this.shadowRoot) return;
    this.shadowRoot.innerHTML = `
      <style>${CARD_CSS}
        .note { font-size:.7rem; color:#706e6b; padding:0 1rem .5rem; }
      </style>
      <article>
        <header>
          <h2>Field Planner</h2>
          <span class="pill">IFRAME ENGINE</span>
        </header>
        <p class="note">Week visits from Apex cache (map/calendar chrome available via shell when needed).</p>
        <div class="body">
          ${
            this.loading
              ? `<div class="loading">Loading week…</div>`
              : !this.visits.length
                ? `<div class="empty">No visits in this week.</div>`
                : this.visits
                    .map(
                      (v) => `
              <div class="row" data-id="${escapeHtml(v.id || '')}">
                <div style="flex:1">
                  <strong>${escapeHtml(v.accountName || v.name || 'Visit')}</strong>
                  <div class="meta">${escapeHtml(this.dayLabel(v.startDateTime))} · ${escapeHtml(v.status || '')}</div>
                </div>
              </div>`
                    )
                    .join('')
          }
        </div>
      </article>
    `;
    this.shadowRoot.querySelectorAll('.row').forEach((el) => {
      el.addEventListener('click', () => {
        const id = (el as HTMLElement).dataset.id;
        if (!id) return;
        void navigate({
          type: 'standard__recordPage',
          attributes: { recordId: id, objectApiName: 'Visit__c', actionName: 'view' }
        });
      });
    });
  }
}
