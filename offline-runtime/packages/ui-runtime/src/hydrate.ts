/**
 * Safe LWC-template binder: {prop}, {a.b}, if:true/false, limited for:each.
 * Does NOT execute org JS / @wire / Lightning components.
 */

export type BinderData = Record<string, unknown>;

function getPath(data: BinderData, path: string): unknown {
  if (!path) return undefined;
  const parts = path.replace(/^\{\s*|\s*\}$/g, '').trim().split('.');
  let cur: unknown = data;
  for (const p of parts) {
    if (cur == null || typeof cur !== 'object') return undefined;
    cur = (cur as Record<string, unknown>)[p];
  }
  return cur;
}

function escapeHtml(s: string): string {
  return s
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;')
    .replace(/"/g, '&quot;');
}

function stringify(v: unknown): string {
  if (v == null) return '';
  if (typeof v === 'object') return escapeHtml(JSON.stringify(v));
  return escapeHtml(String(v));
}

/** Strip LWC directives we can't run; keep structure for binder. */
export function prepareTemplateHtml(html: string): string {
  let out = html
    .replace(/<\/?template\b[^>]*>/gi, '')
    .replace(/<lightning-[a-z0-9-]+\b[^>]*\/>/gi, '')
    .replace(/<lightning-[a-z0-9-]+\b[^>]*>[\s\S]*?<\/lightning-[a-z0-9-]+>/gi, '');
  return out;
}

/**
 * Hydrate a prepared HTML string with data.
 * Supports:
 *  - {foo} / {foo.bar}
 *  - if:true={expr} / if:false={expr} on elements (removes node when false)
 *  - for:each={list} for:item="item" — repeats element's innerHTML per item (item + index in scope)
 */
export function hydrateTemplate(html: string, data: BinderData): string {
  let prepared = prepareTemplateHtml(html);

  // for:each blocks — element with for:each and for:item
  prepared = prepared.replace(
    /<([a-zA-Z0-9-]+)([^>]*?)\sfor:each=\{([^}]+)\}([^>]*?)\sfor:item="([^"]+)"([^>]*)>([\s\S]*?)<\/\1>/gi,
    (_m, tag, pre, listPath, mid, itemName, post, inner) => {
      const list = getPath(data, listPath.trim());
      if (!Array.isArray(list) || list.length === 0) return '';
      return list
        .map((item, index) => {
          const scope = { ...data, [itemName]: item, index };
          const attrs = `${pre}${mid}${post}`.replace(/\sfor:each=\{[^}]+\}/g, '').replace(/\sfor:item="[^"]+"/g, '');
          return `<${tag}${attrs}>${hydrateTemplate(inner, scope)}</${tag}>`;
        })
        .join('');
    }
  );

  // if:true / if:false — drop whole element when condition fails
  prepared = prepared.replace(
    /<([a-zA-Z0-9-]+)([^>]*?)\sif:(true|false)=\{([^}]+)\}([^>]*)>([\s\S]*?)<\/\1>/gi,
    (_m, tag, pre, kind, expr, post, inner) => {
      const val = getPath(data, expr.trim());
      const truthy = Boolean(val);
      const keep = kind === 'true' ? truthy : !truthy;
      if (!keep) return '';
      const attrs = `${pre}${post}`.replace(/\sif:(true|false)=\{[^}]+\}/g, '');
      return `<${tag}${attrs}>${hydrateTemplate(inner, data)}</${tag}>`;
    }
  );

  // Self-closing if:*
  prepared = prepared.replace(
    /<([a-zA-Z0-9-]+)([^>]*?)\sif:(true|false)=\{([^}]+)\}([^>]*)\/>/gi,
    (_m, tag, pre, kind, expr, post) => {
      const val = getPath(data, expr.trim());
      const truthy = Boolean(val);
      const keep = kind === 'true' ? truthy : !truthy;
      if (!keep) return '';
      const attrs = `${pre}${post}`.replace(/\sif:(true|false)=\{[^}]+\}/g, '');
      return `<${tag}${attrs} />`;
    }
  );

  // {expr} interpolations (skip leftover for:/if:)
  prepared = prepared.replace(/\{([a-zA-Z_][a-zA-Z0-9_.]*)\}/g, (_m, path) => {
    return stringify(getPath(data, path));
  });

  return prepared;
}

export function buildHydratedDocument(
  html: string | undefined,
  css: string | undefined,
  data: BinderData,
  opts?: { title?: string; cached?: boolean }
): string {
  const body = html
    ? hydrateTemplate(html, data)
    : `<div class="slds-text-align_center slds-p-around_medium slds-text-color_weak">No items to display</div>`;
  const style = css ? `<style>${css}</style>` : '';
  const badge = opts?.cached
    ? `<span class="osr-cache-pill" style="font-size:10px;font-weight:600;color:#0176d3;background:#eef4ff;border-radius:4px;padding:2px 6px;margin-left:8px">Cached</span>`
    : '';
  const title = opts?.title
    ? `<div class="osr-hydrate-hdr" style="display:flex;align-items:center;justify-content:space-between;padding:8px 12px;font-weight:700">${escapeHtml(opts.title)}${badge}</div>`
    : '';
  return `<div class="osr-lwc-mirror osr-hydrate-root">${style}${title}<div class="osr-hydrate-body">${body}</div></div>`;
}
