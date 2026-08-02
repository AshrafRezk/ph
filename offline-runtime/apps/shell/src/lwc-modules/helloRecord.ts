/**
 * Spike: @wire-style getRecord via platform bridge (SQLite offline / live online).
 */
import { getRecord } from '@osr/platform';

export default class HelloRecord extends HTMLElement {
  recordId = '';
  objectApi = 'Account';
  label = '…';
  error = '';
  source = '';

  static get observedAttributes() {
    return ['record-id', 'object-api'];
  }

  attributeChangedCallback(name: string, _o: string, v: string) {
    if (name === 'record-id') this.recordId = v;
    if (name === 'object-api') this.objectApi = v;
    void this.refresh();
  }

  connectedCallback() {
    this.attachShadow({ mode: 'open' });
    this.recordId = this.getAttribute('record-id') || this.recordId;
    this.objectApi = this.getAttribute('object-api') || this.objectApi;
    void this.refresh();
  }

  async refresh() {
    this.render('Loading…');
    if (!this.recordId) {
      this.render('Pass recordId to load a record from SQLite.');
      return;
    }
    try {
      const data = (await getRecord({
        recordId: this.recordId,
        objectApiName: this.objectApi
      })) as Record<string, unknown> | null;
      this.label = String(data?.Name ?? data?.Id ?? 'Record');
      this.error = '';
      this.render(null);
    } catch (e) {
      this.error = e instanceof Error ? e.message : String(e);
      this.render(null);
    }
  }

  render(loading: string | null) {
    if (!this.shadowRoot) return;
    this.shadowRoot.innerHTML = `
      <style>
        :host { display:block; font-family:system-ui,sans-serif; }
        div { padding:1rem; border:1px solid #e5e5e5; border-radius:4px; background:#fff; }
        h1 { margin:0 0 .35rem; font-size:1rem; color:#032d60; }
        .err { color:#ba0517; font-size:.8rem; }
        .meta { color:#706e6b; font-size:.75rem; }
      </style>
      <div>
        <h1>${loading ?? this.label}</h1>
        ${this.error ? `<p class="err">${this.error}</p>` : ''}
        <p class="meta">${this.objectApi} · ${this.recordId || '—'} · offline-capable getRecord</p>
      </div>
    `;
  }
}
