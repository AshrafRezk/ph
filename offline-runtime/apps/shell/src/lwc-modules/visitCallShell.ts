import { createApexInvoker, getRecord, navigate, showToast } from '@osr/platform';
import { CARD_CSS, escapeHtml, unwrapList } from './shared';

const getTodayPlan = createApexInvoker('FieldRepHomeController.getTodayPlan');

type Visit = {
  id?: string;
  name?: string;
  accountName?: string;
  status?: string;
  startDateTime?: string;
};

export default class VisitCallShell extends HTMLElement {
  visits: Visit[] = [];
  recordLabel = '';
  loading = true;
  recordId = '';

  static get observedAttributes() {
    return ['record-id'];
  }

  attributeChangedCallback(name: string, _o: string, v: string) {
    if (name === 'record-id') {
      this.recordId = v;
      void this.load();
    }
  }

  connectedCallback() {
    this.attachShadow({ mode: 'open' });
    this.recordId = this.getAttribute('record-id') || this.recordId;
    void this.load();
  }

  async load() {
    this.loading = true;
    this.render();
    try {
      if (this.recordId) {
        const rec = (await getRecord({
          recordId: this.recordId,
          objectApiName: 'Visit__c'
        })) as Record<string, unknown> | null;
        this.recordLabel = String(rec?.Name ?? this.recordId);
        this.visits = [
          {
            id: this.recordId,
            name: this.recordLabel,
            accountName: String(rec?.Account_Name__c ?? rec?.Account__c ?? ''),
            status: String(rec?.Status__c ?? '')
          }
        ];
      } else {
        const raw = await getTodayPlan({});
        this.visits = unwrapList(raw) as Visit[];
        if (!this.visits.length && raw && typeof raw === 'object' && Array.isArray((raw as { visits?: Visit[] }).visits)) {
          this.visits = (raw as { visits: Visit[] }).visits;
        }
      }
    } catch (e) {
      this.visits = [];
      void showToast({
        title: 'Visit Call',
        message: e instanceof Error ? e.message : String(e),
        variant: 'error'
      });
    }
    this.loading = false;
    this.render();
  }

  render() {
    if (!this.shadowRoot) return;
    this.shadowRoot.innerHTML = `
      <style>${CARD_CSS}</style>
      <article>
        <header>
          <h2>${escapeHtml(this.recordId ? `Visit · ${this.recordLabel}` : 'Visit Call')}</h2>
          <span class="pill">IFRAME ENGINE</span>
        </header>
        <div class="body">
          ${
            this.loading
              ? `<div class="loading">Loading…</div>`
              : !this.visits.length
                ? `<div class="empty">No visit context. Open a visit from Today's Plan.</div>`
                : this.visits
                    .map(
                      (v) => `
              <div class="row" data-id="${escapeHtml(v.id || '')}">
                <div style="flex:1">
                  <strong>${escapeHtml(v.accountName || v.name || 'Visit')}</strong>
                  <div class="meta">${escapeHtml(v.status || '')}</div>
                  <div class="actions">
                    <button type="button" class="brand" data-open="${escapeHtml(v.id || '')}">Open record</button>
                  </div>
                </div>
              </div>`
                    )
                    .join('')
          }
        </div>
      </article>
    `;
    this.shadowRoot.querySelectorAll('[data-open]').forEach((btn) => {
      btn.addEventListener('click', (ev) => {
        ev.stopPropagation();
        const id = (btn as HTMLElement).dataset.open;
        if (!id) return;
        void navigate({
          type: 'standard__recordPage',
          attributes: { recordId: id, objectApiName: 'Visit__c', actionName: 'view' }
        });
      });
    });
  }
}
