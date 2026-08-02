import { html, type TemplateResult } from 'lit';

export function sldsButton(
  label: string,
  opts: {
    variant?: 'brand' | 'neutral' | 'base' | 'destructive-text';
    disabled?: boolean;
    className?: string;
    onClick?: (e: Event) => void;
    title?: string;
  } = {}
): TemplateResult {
  const v = opts.variant ?? 'neutral';
  const cls = [
    'slds-button',
    v === 'brand' ? 'slds-button_brand' : '',
    v === 'neutral' ? 'slds-button_neutral' : '',
    v === 'base' ? 'slds-button_base' : '',
    v === 'destructive-text' ? 'slds-button_destructive-text' : '',
    opts.className ?? ''
  ]
    .filter(Boolean)
    .join(' ');
  return html`
    <button
      type="button"
      class=${cls}
      ?disabled=${opts.disabled}
      title=${opts.title ?? label}
      @click=${opts.onClick}
    >
      ${label}
    </button>
  `;
}

export function sldsBadge(label: string, className = ''): TemplateResult {
  return html`<span class="slds-badge ${className}">${label}</span>`;
}

export function sldsEmpty(message: string, action?: TemplateResult): TemplateResult {
  return html`
    <div class="slds-text-align_center slds-p-around_medium slds-text-color_weak empty-state">
      <div>${message}</div>
      ${action ?? ''}
    </div>
  `;
}

export function sldsCard(body: TemplateResult, className = ''): TemplateResult {
  return html`<article class="slds-card osr-lwc-mirror ${className}">${body}</article>`;
}
