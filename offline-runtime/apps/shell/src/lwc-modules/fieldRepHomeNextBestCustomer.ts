import { createApexInvoker, navigate } from '@osr/platform';
import { CARD_CSS, escapeHtml, unwrapList } from './shared';

const getNbc = createApexInvoker('FieldRepHomeController.getNextBestCustomers');

type NbcRow = {
  rank?: number;
  accountId?: string;
  accountName?: string;
  specialty?: string;
  actualVisits?: number;
  targetVisits?: number;
  visitGap?: number;
  planned?: boolean;
};

export default class FieldRepHomeNextBestCustomer extends HTMLElement {
  rows: NbcRow[] = [];
  loading = true;

  connectedCallback() {
    this.attachShadow({ mode: 'open' });
    void this.load();
  }

  async load() {
    this.loading = true;
    this.render();
    try {
      const raw = await getNbc({});
      this.rows = unwrapList(raw) as NbcRow[];
    } catch {
      this.rows = [];
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
          <h2>Next Best Customer</h2>
          <span class="pill">IFRAME ENGINE</span>
        </header>
        <div class="body">
          ${
            this.loading
              ? `<div class="loading">Loading…</div>`
              : !this.rows.length
                ? `<div class="empty">No recommendations right now.</div>`
                : this.rows
                    .slice(0, 8)
                    .map(
                      (r, i) => `
              <div class="row" data-id="${escapeHtml(r.accountId || '')}">
                <span class="badge">#${r.rank ?? i + 1}</span>
                <div style="flex:1">
                  <strong>${escapeHtml(r.accountName || 'Account')}</strong>
                  <div class="meta">${escapeHtml(r.specialty || '')} · ${r.actualVisits ?? 0}/${r.targetVisits ?? 0} visits${
                        r.visitGap != null ? ` · gap ${r.visitGap}` : ''
                      }</div>
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
          attributes: { recordId: id, objectApiName: 'Account', actionName: 'view' }
        });
      });
    });
  }
}
