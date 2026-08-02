import { html, nothing, type TemplateResult } from 'lit';
import { type OfficeMessageDto } from '../apex-cache';

/** Autoplay timer handles keyed by host element id via module state in shell. */
let autoplayTimer: ReturnType<typeof setInterval> | null = null;

export function renderFidelityMessages(opts: {
  label: string;
  messages: OfficeMessageDto[] | null;
  cached?: boolean;
  index?: number;
  onIndex?: (i: number) => void;
}): TemplateResult {
  const messages = opts.messages ?? [];
  const idx = Math.max(0, Math.min(Math.max(messages.length - 1, 0), opts.index ?? 0));
  const trackStyle = `transform:translateX(-${idx * 100}%);transition:transform .55s ease`;

  if (typeof window !== 'undefined' && messages.length > 1 && opts.onIndex) {
    if (autoplayTimer) clearInterval(autoplayTimer);
    autoplayTimer = setInterval(() => {
      opts.onIndex?.(((opts.index ?? 0) + 1) % messages.length);
    }, 6000);
  }

  return html`
    <article
      class="osr-lwc-mirror slds-card ho-messages-card"
      @mouseenter=${() => {
        if (autoplayTimer) {
          clearInterval(autoplayTimer);
          autoplayTimer = null;
        }
      }}
      @mouseleave=${() => {
        if (messages.length > 1 && opts.onIndex) {
          autoplayTimer = setInterval(() => {
            opts.onIndex?.(((opts.index ?? 0) + 1) % messages.length);
          }, 6000);
        }
      }}
    >
      <div class="ho-header slds-p-around_small">
        <span class="ho-header-icon" aria-hidden="true">${megaphoneSvg()}</span>
        <div>
          <h2 class="ho-title">
            Home Office Messages
            ${opts.cached ? html`<span class="osr-cache-pill">Cached</span>` : nothing}
          </h2>
          <p class="ho-subtitle">Corporate updates from Head Office</p>
        </div>
      </div>

      ${messages.length === 0
        ? html`<div class="home-empty home-empty-compact ho-empty-panel">
            <div class="home-empty-icon" aria-hidden="true">${inboxSvg()}</div>
            <strong class="home-empty-title">You're all caught up</strong>
            <p class="home-empty-copy">No messages from Head Office right now.</p>
          </div>`
        : html`
            <div class="ho-carousel" role="region" aria-label="Home Office Messages carousel">
              <div class="ho-carousel-viewport">
                <div class="ho-carousel-track" style=${trackStyle}>
                  ${messages.map(
                    (msg) => html`
                      <article class="ho-message ${msg.isHighPriority ? 'ho-message-high' : ''}">
                        <div class="ho-message-head">
                          <div class="ho-message-meta">
                            ${msg.isHighPriority
                              ? html`<span class="ho-priority-badge">High Priority</span>`
                              : nothing}
                            ${msg.audienceLabel
                              ? html`<span class="ho-audience">${msg.audienceLabel}</span>`
                              : nothing}
                          </div>
                          <span class="ho-date">${msg.publishedLabel || ''}</span>
                        </div>
                        <h3 class="ho-subject">${msg.subject || 'Update'}</h3>
                        <p class="ho-author">${msg.authorName || ''}</p>
                        <p class="ho-body">${msg.body || ''}</p>
                      </article>
                    `
                  )}
                </div>
              </div>
              ${messages.length > 1
                ? html`
                    <div class="ho-dots" role="tablist">
                      ${messages.map(
                        (_, i) => html`
                          <button
                            type="button"
                            class="ho-dot ${i === idx ? 'ho-dot-active' : ''}"
                            role="tab"
                            aria-selected=${i === idx}
                            @click=${() => opts.onIndex?.(i)}
                          ></button>
                        `
                      )}
                    </div>
                  `
                : nothing}
            </div>
          `}
    </article>
  `;
}

function megaphoneSvg(): TemplateResult {
  return html`<svg width="20" height="20" viewBox="0 0 52 52" fill="none" aria-hidden="true">
    <path
      d="M6 22v8c0 1.1.9 2 2 2h4l10 8V12L12 20H8c-1.1 0-2 .9-2 2z"
      fill="#0176d3"
    />
    <path
      d="M38 16c2.4 2.4 3.8 5.6 3.8 9s-1.4 6.6-3.8 9"
      stroke="#0176d3"
      stroke-width="3"
      stroke-linecap="round"
    />
    <path
      d="M33 20c1.3 1.3 2 3 2 5s-.7 3.7-2 5"
      stroke="#0176d3"
      stroke-width="3"
      stroke-linecap="round"
    />
  </svg>`;
}

function inboxSvg(): TemplateResult {
  return html`<svg width="40" height="40" viewBox="0 0 48 48" fill="none" aria-hidden="true">
    <rect x="8" y="12" width="32" height="24" rx="4" stroke="#c9d7e8" stroke-width="2.5" fill="#f7fbff" />
    <path d="M8 18l16 10L40 18" stroke="#0176d3" stroke-width="2.5" stroke-linecap="round" stroke-linejoin="round" />
  </svg>`;
}
