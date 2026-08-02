/** Shared helpers for iframe-engine Custom Element ports. */

export function escapeHtml(s: string): string {
  return s.replace(/[&<>"']/g, (c) =>
    ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' })[c]!
  );
}

export const CARD_CSS = `
  :host { display:block; font-family: system-ui, -apple-system, sans-serif; color:#181818; }
  article {
    background:#fff; border:1px solid #e5e5e5; border-radius:4px;
    box-shadow:0 1px 2px rgba(0,0,0,.05); overflow:hidden;
  }
  header {
    display:flex; align-items:center; gap:.5rem;
    padding:.75rem 1rem; border-bottom:1px solid #e5e5e5;
  }
  h2 { margin:0; font-size:.9375rem; color:#032d60; }
  .pill { margin-left:auto; font-size:.6rem; color:#2e844a; font-weight:700; letter-spacing:.02em; }
  .body { padding:.5rem 0; }
  .empty, .loading { color:#706e6b; font-size:.8125rem; padding:1rem; text-align:center; }
  .row {
    display:flex; gap:.75rem; align-items:flex-start;
    padding:.65rem 1rem; border-bottom:1px solid #f3f3f3; cursor:pointer;
  }
  .row:last-child { border-bottom:0; }
  .row:hover { background:#f3f3f3; }
  .row strong { display:block; font-size:.8125rem; color:#032d60; }
  .row .meta { font-size:.7rem; color:#706e6b; margin-top:.15rem; }
  .badge {
    display:inline-block; font-size:.65rem; font-weight:700;
    padding:.1rem .35rem; border-radius:.25rem; background:#ecebea; color:#2e2e2e;
  }
  .actions { display:flex; gap:.35rem; margin-top:.35rem; }
  button {
    font:inherit; font-size:.7rem; padding:.25rem .55rem; border-radius:.25rem;
    border:1px solid #747474; background:#fff; color:#0176d3; cursor:pointer;
  }
  button.brand { background:#0176d3; border-color:#0176d3; color:#fff; }
  .metric-grid { display:grid; grid-template-columns:repeat(2,minmax(0,1fr)); gap:.5rem; padding:.75rem 1rem; }
  .metric {
    background:#f3f3f3; border-radius:.25rem; padding:.65rem .75rem;
  }
  .metric .v { font-size:1.25rem; font-weight:700; color:#032d60; }
  .metric .l { font-size:.7rem; color:#706e6b; }
`;

export function unwrapList(payload: unknown): unknown[] {
  if (Array.isArray(payload)) return payload;
  if (payload && typeof payload === 'object') {
    const o = payload as Record<string, unknown>;
    for (const k of ['visits', 'accounts', 'messages', 'rows', 'records', 'items']) {
      if (Array.isArray(o[k])) return o[k] as unknown[];
    }
  }
  return [];
}
