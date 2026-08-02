import { html, nothing, type TemplateResult } from 'lit';

/** Digits only, keep leading + for intl formatting when present. */
export function normalizePhoneDigits(raw: string): string {
  const trimmed = String(raw || '').trim();
  if (!trimmed) return '';
  const hasPlus = trimmed.startsWith('+');
  const digits = trimmed.replace(/\D/g, '');
  if (!digits) return '';
  return hasPlus ? `+${digits}` : digits;
}

export function telHref(raw: string): string | null {
  const n = normalizePhoneDigits(raw);
  if (!n) return null;
  return `tel:${n}`;
}

/** WhatsApp wa.me expects country code digits without + or leading zeros quirks. */
export function whatsappHref(raw: string): string | null {
  const n = normalizePhoneDigits(raw);
  if (!n) return null;
  const digits = n.replace(/\D/g, '');
  if (digits.length < 8) return null;
  return `https://wa.me/${digits}`;
}

export function openPhoneLink(href: string, e?: Event) {
  e?.preventDefault();
  e?.stopPropagation();
  if (href.startsWith('tel:')) {
    window.location.href = href;
    return;
  }
  try {
    window.open(href, '_blank', 'noopener,noreferrer');
  } catch {
    window.location.href = href;
  }
}

export function renderPhoneActions(
  raw: string | null | undefined,
  opts?: { className?: string; showNumber?: boolean }
): TemplateResult | typeof nothing {
  const phone = String(raw || '').trim();
  if (!phone) return nothing;
  const call = telHref(phone);
  const wa = whatsappHref(phone);
  if (!call && !wa) {
    return html`<p class="account-hub-meta phone-static">☎ ${phone}</p>`;
  }
  const extra = opts?.className ? ` ${opts.className}` : '';
  return html`
    <div class="phone-actions${extra}">
      ${opts?.showNumber === false
        ? nothing
        : html`<span class="phone-actions-number" title=${phone}>${phone}</span>`}
      <div class="phone-actions-btns">
        ${call
          ? html`<a
              class="phone-action-btn phone-action-call"
              href=${call}
              @click=${(e: Event) => openPhoneLink(call, e)}
              aria-label=${`Call ${phone}`}
            >
              <svg viewBox="0 0 24 24" aria-hidden="true" focusable="false">
                <path
                  fill="currentColor"
                  d="M6.6 10.8a15.1 15.1 0 006.6 6.6l2.2-2.2a1 1 0 011-.25 11.4 11.4 0 003.6.57 1 1 0 011 1V20a1 1 0 01-1 1A17 17 0 013 4a1 1 0 011-1h3.5a1 1 0 011 1 11.4 11.4 0 00.57 3.6 1 1 0 01-.25 1L6.6 10.8z"
                />
              </svg>
              Call
            </a>`
          : nothing}
        ${wa
          ? html`<a
              class="phone-action-btn phone-action-wa"
              href=${wa}
              target="_blank"
              rel="noopener noreferrer"
              @click=${(e: Event) => openPhoneLink(wa, e)}
              aria-label=${`WhatsApp ${phone}`}
            >
              <svg viewBox="0 0 24 24" aria-hidden="true" focusable="false">
                <path
                  fill="currentColor"
                  d="M12 2a10 10 0 00-8.7 15L2 22l5.2-1.3A10 10 0 1012 2zm0 18a8 8 0 01-4.1-1.1l-.3-.2-3 .8.8-2.9-.2-.3A8 8 0 1112 20zm4.4-5.9c-.2-.1-1.4-.7-1.6-.8s-.4-.1-.5.1-.6.8-.7.9-.3.2-.5.1a6.5 6.5 0 01-1.9-1.2 7.2 7.2 0 01-1.3-1.6c-.1-.3 0-.4.1-.5l.4-.5.2-.3.1-.3-.1-.5c0-.1-.5-1.3-.7-1.7s-.4-.4-.5-.4h-.5c-.2 0-.4.1-.6.3a2 2 0 00-.6 1.5 3.5 3.5 0 00.7 1.8 8 8 0 003.4 3.1 11 11 0 002 .8 2.4 2.4 0 001.6.1 2.8 2.8 0 001.8-1.3 2.3 2.3 0 00.2-1.3c-.1-.1-.2-.2-.4-.3z"
                />
              </svg>
              WhatsApp
            </a>`
          : nothing}
      </div>
    </div>
  `;
}
