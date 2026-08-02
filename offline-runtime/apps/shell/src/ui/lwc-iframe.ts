import { html, type TemplateResult } from 'lit';
import { ref } from 'lit/directives/ref.js';

/**
 * Embed the local OSR LWC iframe host for an engine-ready (or compiled) bundle.
 */
export function renderLwcIframe(opts: {
  bundle: string;
  recordId?: string | null;
  objectApi?: string | null;
  height?: number;
  props?: Record<string, string>;
  onFrame?: (iframe: HTMLIFrameElement) => void;
}): TemplateResult {
  const params = new URLSearchParams({ bundle: opts.bundle });
  if (opts.recordId) params.set('recordId', opts.recordId);
  if (opts.objectApi) params.set('objectApi', opts.objectApi);
  for (const [k, v] of Object.entries(opts.props ?? {})) {
    params.set(k, v);
  }
  const src = `/osr-lwc-host.html#${params.toString()}`;
  const h = Math.max(80, opts.height ?? 160);

  return html`
    <iframe
      class="osr-lwc-frame"
      title=${opts.bundle}
      src=${src}
      style="width:100%;border:0;display:block;min-height:${h}px;height:${h}px;background:transparent"
      ${ref((el) => {
        if (el instanceof HTMLIFrameElement) opts.onFrame?.(el);
      })}
    ></iframe>
  `;
}
