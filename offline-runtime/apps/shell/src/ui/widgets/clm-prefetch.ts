import { html, nothing, type TemplateResult } from 'lit';

/** Compact status pill — matches fieldRepHomeClmPrefetch, not a Home card. */
export function renderFidelityClmPrefetch(opts: {
  label: string;
  presentations?: unknown[] | null;
  cached?: boolean;
  syncing?: boolean;
  onBrowse?: () => void;
}): TemplateResult {
  const n = opts.presentations?.length ?? 0;
  const label = opts.syncing
    ? 'Caching CLM content…'
    : n > 0
      ? `${n} CLM(s) ready on device`
      : 'No CLM content cached yet';
  return html`
    <div
      class="osr-lwc-mirror prefetch-status"
      role="status"
      aria-live="polite"
      @click=${() => opts.onBrowse?.()}
      style="cursor:${opts.onBrowse ? 'pointer' : 'default'}"
    >
      <span class="prefetch-icon" aria-hidden="true">⬇</span>
      <span>${label}</span>
      ${opts.cached && !opts.syncing ? html`<span class="osr-cache-pill">Cached</span>` : nothing}
    </div>
  `;
}
