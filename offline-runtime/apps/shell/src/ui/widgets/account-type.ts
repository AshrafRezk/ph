import { html, svg, type TemplateResult } from 'lit';

export type AccountKind = 'hcp' | 'hco' | 'pharmacy';

export type AccountKindSource = {
  recordTypeName?: string | null;
  recordTypeDeveloperName?: string | null;
  name?: string | null;
  Type?: string | null;
  accountRecordTypeName?: string | null;
  accountRecordTypeDeveloperName?: string | null;
  accountName?: string | null;
};

const KIND_LABEL: Record<AccountKind, string> = {
  hcp: 'HCP',
  hco: 'HCO',
  pharmacy: 'Pharmacy'
};

const KIND_TITLE: Record<AccountKind, string> = {
  hcp: 'Healthcare Provider',
  hco: 'Healthcare Organization',
  pharmacy: 'Pharmacy'
};

function typeBlob(source: AccountKindSource | Record<string, unknown> | null | undefined): string {
  if (!source) return '';
  const s = source as AccountKindSource & Record<string, unknown>;
  return [
    s.recordTypeDeveloperName,
    s.recordTypeName,
    s.accountRecordTypeDeveloperName,
    s.accountRecordTypeName,
    s.Type,
    s.name,
    s.accountName
  ]
    .filter(Boolean)
    .join(' ')
    .toLowerCase();
}

export function resolveAccountKind(
  source: AccountKindSource | Record<string, unknown> | null | undefined
): AccountKind {
  const blob = typeBlob(source);
  if (blob.includes('pharm')) return 'pharmacy';
  if (
    blob.includes('hco') ||
    blob.includes('hospital') ||
    blob.includes('institution') ||
    blob.includes('clinic') ||
    blob.includes('organization')
  ) {
    return 'hco';
  }
  return 'hcp';
}

export function accountKindLabel(kind: AccountKind): string {
  return KIND_LABEL[kind];
}

export function accountKindTitle(kind: AccountKind): string {
  return KIND_TITLE[kind];
}

/** Compact inline SVG glyph for HTML badges (16×16 viewBox). */
export function accountKindGlyph(kind: AccountKind, fill = 'currentColor'): TemplateResult {
  if (kind === 'hcp') {
    return html`<svg class="acct-kind-glyph" viewBox="0 0 24 24" aria-hidden="true" focusable="false">
      <path
        fill=${fill}
        d="M12 12a4 4 0 1 0-4-4 4 4 0 0 0 4 4zm0 2c-3.3 0-10 1.7-10 5v1h20v-1c0-3.3-6.7-5-10-5zm7-9h-2V3h-2v2h-2v2h2v2h2V7h2z"
      />
    </svg>`;
  }
  if (kind === 'pharmacy') {
    return html`<svg class="acct-kind-glyph" viewBox="0 0 24 24" aria-hidden="true" focusable="false">
      <path
        fill=${fill}
        d="M7 3h10l1 4H6l1-4zm-1 6h12v2H6V9zm1 4h10l1.2 8.4A1 1 0 0 1 17.2 23H6.8a1 1 0 0 1-1-1.1L7 13zm4 2v5h2v-5h-2z"
      />
    </svg>`;
  }
  return html`<svg class="acct-kind-glyph" viewBox="0 0 24 24" aria-hidden="true" focusable="false">
    <path
      fill=${fill}
      d="M4 21V7l8-4 8 4v14h-5v-6H9v6H4zm7-14h2v2h-2V7zm0 4h2v2h-2v-2zm4-4h2v2h-2V7zm0 4h2v2h-2v-2zM7 7h2v2H7V7zm0 4h2v2H7v-2z"
    />
  </svg>`;
}

/** SVG glyph paths for affiliation network nodes (centered in a circle). */
export function accountKindSvgIcon(
  kind: AccountKind | 'root',
  cx: number,
  cy: number,
  fill: string,
  size = 22
): TemplateResult {
  const s = size / 24;
  const tx = cx - (size / 2);
  const ty = cy - (size / 2) - (kind === 'root' ? 0 : 0);
  if (kind === 'root') {
    return svg`<g transform=${`translate(${tx} ${ty}) scale(${s})`}>
      <path fill=${fill} d="M12 4a4 4 0 1 1 0 8 4 4 0 0 1 0-8zm0 10c-4 0-8 2-8 4v2h16v-2c0-2-4-4-8-4z"/>
    </g>`;
  }
  if (kind === 'hcp') {
    return svg`<g transform=${`translate(${tx} ${ty}) scale(${s})`}>
      <path fill=${fill} d="M12 11a3.5 3.5 0 1 0-3.5-3.5A3.5 3.5 0 0 0 12 11zm0 1.5c-3 0-9 1.5-9 4.5V19h18v-2c0-3-6-4.5-9-4.5zm6.5-8.5h-1.5V2.5h-2v1.5H13v2h2v1.5h2V6.5h1.5z"/>
    </g>`;
  }
  if (kind === 'pharmacy') {
    return svg`<g transform=${`translate(${tx} ${ty}) scale(${s})`}>
      <path fill=${fill} d="M7.5 3h9l.8 3.5H6.7L7.5 3zM6 8h12v1.8H6V8zm1 3.5h10l1 7.2a.9.9 0 0 1-.9 1.1H6.9a.9.9 0 0 1-.9-1.1l1-7.2zM11 14v4h2v-4h-2z"/>
    </g>`;
  }
  return svg`<g transform=${`translate(${tx} ${ty}) scale(${s})`}>
    <path fill=${fill} d="M4 20V8l8-4 8 4v12h-5v-5H9v5H4zm6.5-12h3v2h-3V8zm0 3.5h3v2h-3v-2zm4 0h3v2h-3v-2zm0-3.5h3v2h-3V8zM7 8h3v2H7V8zm0 3.5h3v2H7v-2z"/>
  </g>`;
}

export function renderAccountKindBadge(
  source: AccountKindSource | Record<string, unknown> | null | undefined,
  opts?: { label?: string | null; compact?: boolean; className?: string }
): TemplateResult {
  const kind = resolveAccountKind(source);
  const label = opts?.label?.trim() || (opts?.compact ? KIND_LABEL[kind] : KIND_TITLE[kind]);
  const extra = opts?.className ? ` ${opts.className}` : '';
  return html`
    <span class="acct-kind-badge acct-kind-${kind}${extra}" title=${KIND_TITLE[kind]}>
      ${accountKindGlyph(kind)}
      <span class="acct-kind-label">${label}</span>
    </span>
  `;
}

export function renderAccountKindIconOnly(
  source: AccountKindSource | Record<string, unknown> | null | undefined,
  opts?: { className?: string }
): TemplateResult {
  const kind = resolveAccountKind(source);
  const extra = opts?.className ? ` ${opts.className}` : '';
  return html`
    <span class="account-type-icon ${kind}${extra}" title=${KIND_TITLE[kind]} aria-label=${KIND_LABEL[kind]}>
      ${accountKindGlyph(kind)}
    </span>
  `;
}
