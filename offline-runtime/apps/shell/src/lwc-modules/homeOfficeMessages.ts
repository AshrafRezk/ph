/**
 * Engine-ready Home Office Messages — uses platform Apex shim (SQLite cache / live).
 * Mounted in the local LWC iframe instead of the Lit fidelity port.
 */
import { createApexInvoker } from '@osr/platform';

const getActiveMessages = createApexInvoker('HomeOfficeMessageController.getActiveMessages');
const ROTATE_MS = 6000;

type OfficeMessage = {
  publishedLabel?: string;
  publishedOn?: string;
  isHighPriority?: boolean;
  audienceLabel?: string;
  subject?: string;
  authorName?: string;
  body?: string;
};

export default class HomeOfficeMessages extends HTMLElement {
  messages: OfficeMessage[] = [];
  isLoading = true;
  activeIndex = 0;
  _timer: ReturnType<typeof setInterval> | null = null;

  connectedCallback() {
    this.attachShadow({ mode: 'open' });
    void this.load();
  }

  disconnectedCallback() {
    this.stop();
  }

  async load() {
    this.isLoading = true;
    this.render();
    try {
      const rows = await getActiveMessages({ limitSize: 6 });
      this.messages = Array.isArray(rows) ? rows : [];
      this.activeIndex = 0;
      if (this.messages.length > 1) this.start();
    } catch {
      this.messages = [];
    } finally {
      this.isLoading = false;
      this.render();
    }
  }

  start() {
    this.stop();
    this._timer = setInterval(() => {
      if (this.messages.length <= 1) return;
      this.activeIndex = (this.activeIndex + 1) % this.messages.length;
      this.render();
    }, ROTATE_MS);
  }

  stop() {
    if (this._timer) clearInterval(this._timer);
    this._timer = null;
  }

  render() {
    if (!this.shadowRoot) return;
    const m = this.messages[this.activeIndex];
    this.shadowRoot.innerHTML = `
      <style>
        :host { display:block; font-family: system-ui, sans-serif; }
        article { background:#fff; border:1px solid #e5e5e5; border-radius:4px; overflow:hidden; box-shadow:0 1px 2px rgba(0,0,0,.05); }
        header { display:flex; gap:.5rem; align-items:flex-start; padding:.75rem 1rem; border-bottom:1px solid #e5e5e5; }
        h2 { margin:0; font-size:.9375rem; color:#032d60; }
        .sub { margin:.1rem 0 0; font-size:.6875rem; color:#706e6b; }
        .body { padding:1rem; min-height:5rem; }
        .empty, .loading { color:#706e6b; font-size:.8125rem; padding:1rem; text-align:center; }
        .badge { display:inline-block; background:#fe9339; color:#fff; font-size:.65rem; font-weight:700; padding:.1rem .35rem; border-radius:.25rem; margin-right:.35rem; }
        .aud { color:#0176d3; font-size:.7rem; font-weight:600; }
        .date { float:right; color:#706e6b; font-size:.7rem; }
        .subj { margin:.5rem 0 .25rem; font-size:.9rem; color:#032d60; }
        .author { margin:0; font-size:.75rem; color:#706e6b; }
        .msg { margin:.5rem 0 0; font-size:.8125rem; color:#181818; line-height:1.4; }
        .dots { display:flex; gap:.35rem; justify-content:center; padding:0 0 .75rem; }
        .dot { width:.5rem; height:.5rem; border-radius:50%; border:0; background:#dddbda; cursor:pointer; }
        .dot.on { background:#0176d3; }
        .engine-pill { font-size:.6rem; color:#2e844a; font-weight:700; margin-left:auto; }
      </style>
      <article>
        <header>
          <div>
            <h2>Home Office Messages</h2>
            <p class="sub">Corporate updates from Head Office</p>
          </div>
          <span class="engine-pill">IFRAME ENGINE</span>
        </header>
        <div class="body">
          ${
            this.isLoading
              ? `<div class="loading">Loading messages…</div>`
              : !m
                ? `<div class="empty">No messages from Head Office right now.</div>`
                : `
              <div>
                <span class="date">${m.publishedLabel || m.publishedOn || ''}</span>
                ${m.isHighPriority ? `<span class="badge">HIGH PRIORITY</span>` : ''}
                <span class="aud">${m.audienceLabel || ''}</span>
                <h3 class="subj">${escapeHtml(m.subject || '')}</h3>
                <p class="author">${escapeHtml(m.authorName || '')}</p>
                <p class="msg">${escapeHtml(m.body || '')}</p>
              </div>
              ${
                this.messages.length > 1
                  ? `<div class="dots">${this.messages
                      .map(
                        (_, i) =>
                          `<button type="button" class="dot ${i === this.activeIndex ? 'on' : ''}" data-i="${i}"></button>`
                      )
                      .join('')}</div>`
                  : ''
              }
            `
          }
        </div>
      </article>
    `;
    this.shadowRoot.querySelectorAll('.dot').forEach((btn) => {
      btn.addEventListener('click', () => {
        this.activeIndex = Number((btn as HTMLElement).dataset.i || 0);
        this.start();
        this.render();
      });
    });
  }
}

function escapeHtml(s: string): string {
  return s.replace(/[&<>"']/g, (c) =>
    ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' })[c]!
  );
}
