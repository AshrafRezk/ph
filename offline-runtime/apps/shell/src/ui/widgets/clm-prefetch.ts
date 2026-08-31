import { html, nothing, type TemplateResult } from 'lit';

/** Compact status pill — matches fieldRepHomeClmPrefetch, not a Home card. */
export function renderFidelityClmPrefetch(opts: {
  label: string;
  presentations?: unknown[] | null;
  cached?: boolean;
  syncing?: boolean;
  onBrowse?: () => void;
  onPrefetch?: () => void;
}): TemplateResult {
  const n = opts.presentations?.length ?? 0;
  const label = opts.syncing
    ? 'Caching CLM slides…'
    : n > 0
      ? `${n} CLM deck(s) · tap to open`
      : 'No CLM content cached yet';
  return html`
    <div
      class="osr-lwc-mirror prefetch-status"
      role="status"
      aria-live="polite"
      @click=${() => opts.onBrowse?.()}
      style="cursor:${opts.onBrowse ? 'pointer' : 'default'}"
      title="Open CLM presentations"
    >
      <span class="prefetch-icon" aria-hidden="true">⬇</span>
      <span>${label}</span>
      ${opts.cached && !opts.syncing ? html`<span class="osr-cache-pill">Cached</span>` : nothing}
    </div>
  `;
}
