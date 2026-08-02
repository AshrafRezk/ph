import { createApexInvoker, navigate } from '@osr/platform';
import { CARD_CSS, escapeHtml, unwrapList } from './shared';

const getTodayPlan = createApexInvoker('FieldRepHomeController.getTodayPlan');

type Visit = {
  id?: string;
  name?: string;
  accountId?: string;
  accountName?: string;
  status?: string;
  startDateTime?: string;
  endDateTime?: string;
};

export default class FieldRepHomeTodayPlan extends HTMLElement {
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
      const raw = await getTodayPlan({});
      this.visits = unwrapList(raw) as Visit[];
      if (!this.visits.length && raw && typeof raw === 'object' && Array.isArray((raw as { visits?: unknown[] }).visits)) {
        this.visits = (raw as { visits: Visit[] }).visits;
      }
    } catch {
      this.visits = [];
    }
    this.loading = false;
    this.render();
  }

  fmt(iso?: string) {
    if (!iso) return '';
    const d = new Date(iso);
    if (Number.isNaN(d.getTime())) return '';
    return d.toLocaleTimeString(undefined, { hour: 'numeric', minute: '2-digit' });
  }

  render() {
    if (!this.shadowRoot) return;
    this.shadowRoot.innerHTML = `
      <style>${CARD_CSS}
        .toolbar { display:flex; gap:.5rem; padding:.5rem 1rem 0; }
      </style>
      <article>
        <header>
          <h2>Today's Plan</h2>
          <span class="pill">IFRAME ENGINE</span>
        </header>
        <div class="toolbar">
          <button type="button" class="brand" data-act="planner">Open Planner</button>
        </div>
        <div class="body">
          ${
            this.loading
              ? `<div class="loading">Loading…</div>`
              : !this.visits.length
                ? `<div class="empty">No visits planned for today.</div>`
                : this.visits
                    .map(
                      (v) => `
              <div class="row" data-id="${escapeHtml(v.id || '')}">
                <div style="flex:1">
                  <strong>${escapeHtml(v.accountName || v.name || 'Visit')}</strong>
                  <div class="meta">${escapeHtml(this.fmt(v.startDateTime))} · ${escapeHtml(v.status || '')}</div>
                </div>
              </div>`
                    )
                    .join('')
          }
        </div>
      </article>
    `;
    this.shadowRoot.querySelector('[data-act="planner"]')?.addEventListener('click', () => {
      void navigate({
        type: 'standard__navItemPage',
        attributes: { apiName: 'Field_Rep_Planner' }
      });
    });
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
