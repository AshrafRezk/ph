/**
 * Curated lightning-* base component stubs for the offline LWC iframe.
 * Registered as custom elements so compiled templates that reference them render.
 */

function el(tag: string, html: string, css = '') {
  if (customElements.get(tag)) return;
  class Stub extends HTMLElement {
    connectedCallback() {
      const shadow = this.attachShadow({ mode: 'open' });
      shadow.innerHTML = `${css ? `<style>${css}</style>` : ''}${html}`;
      // Reflect light-DOM slotted content
      const slot = document.createElement('slot');
      shadow.appendChild(slot);
    }
  }
  customElements.define(tag, Stub);
}

const btnCss = `
  :host { display: inline-block; }
  button {
    font: inherit;
    padding: 0.35rem 0.85rem;
    border-radius: 0.25rem;
    border: 1px solid #747474;
    background: #fff;
    color: #0176d3;
    cursor: pointer;
  }
  :host([variant="brand"]) button, button.brand {
    background: #0176d3;
    border-color: #0176d3;
    color: #fff;
  }
  :host([disabled]) button { opacity: 0.45; pointer-events: none; }
`;

export function registerLightningStubs(): void {
  el(
    'lightning-button',
    `<button type="button" part="button"><slot></slot></button>`,
    btnCss
  );
  // Sync label attribute onto button text if no slot content
  const btnProto = customElements.get('lightning-button');
  if (btnProto) {
    // already defined — enhance via observed pattern on next define skip
  }

  el(
    'lightning-input',
    `<label part="label"><span class="l"></span><input part="input" /></label>`,
    `
    :host { display: block; margin: 0.25rem 0; font: inherit; }
    label { display: flex; flex-direction: column; gap: 0.25rem; font-size: 0.75rem; }
    input { padding: 0.4rem 0.5rem; border: 1px solid #c9c9c9; border-radius: 0.25rem; font: inherit; }
    `
  );

  el(
    'lightning-textarea',
    `<label><span class="l"></span><textarea part="textarea" rows="3"></textarea></label>`,
    `
    :host { display: block; margin: 0.25rem 0; font: inherit; }
    textarea { width: 100%; padding: 0.4rem 0.5rem; border: 1px solid #c9c9c9; border-radius: 0.25rem; font: inherit; box-sizing: border-box; }
    `
  );

  el(
    'lightning-combobox',
    `<label><span class="l"></span><select part="select"><slot></slot></select></label>`,
    `
    :host { display: block; margin: 0.25rem 0; font: inherit; }
    select { width: 100%; padding: 0.4rem 0.5rem; border: 1px solid #c9c9c9; border-radius: 0.25rem; font: inherit; }
    `
  );

  el(
    'lightning-spinner',
    `<div class="spin" role="status" aria-label="Loading"></div>`,
    `
    .spin {
      width: 1.5rem; height: 1.5rem; margin: 0.5rem auto;
      border: 2px solid #dddbda; border-top-color: #0176d3;
      border-radius: 50%; animation: s 0.7s linear infinite;
    }
    @keyframes s { to { transform: rotate(360deg); } }
    `
  );

  el(
    'lightning-card',
    `<article part="card"><header part="title"><slot name="title"></slot><slot name="actions"></slot></header><div part="body"><slot></slot><slot name="footer"></slot></div></article>`,
    `
    :host { display: block; }
    article {
      background: #fff; border: 1px solid #e5e5e5; border-radius: 0.25rem;
      box-shadow: 0 1px 2px rgba(0,0,0,.05); overflow: hidden;
    }
    header {
      display: flex; align-items: center; justify-content: space-between;
      gap: 0.5rem; padding: 0.75rem 1rem; border-bottom: 1px solid #e5e5e5;
      font-weight: 700; color: #032d60;
    }
    [part="body"] { padding: 0.5rem 0; }
    `
  );

  el(
    'lightning-badge',
    `<span part="badge"><slot></slot></span>`,
    `
    span {
      display: inline-block; padding: 0.1rem 0.4rem; border-radius: 0.25rem;
      background: #ecebea; color: #2e2e2e; font-size: 0.7rem; font-weight: 700;
    }
    `
  );

  el(
    'lightning-icon',
    `<span part="icon" aria-hidden="true">◆</span>`,
    `
    :host { display: inline-flex; align-items: center; color: #0176d3; }
    span { font-size: 0.85rem; line-height: 1; }
    :host([icon-name*="announcement"]) span::before { content: '📢'; font-size: 0.9rem; }
    :host([icon-name*="info"]) span::before { content: 'ℹ️'; font-size: 0.85rem; }
    :host([icon-name*="announcement"]) span, :host([icon-name*="info"]) span { font-size: 0; }
    :host([icon-name*="announcement"]) span::before, :host([icon-name*="info"]) span::before { font-size: 0.9rem; }
    `
  );

  el(
    'lightning-button-group',
    `<div part="group"><slot></slot></div>`,
    `:host { display: inline-flex; gap: 0.25rem; } div { display: inline-flex; gap: 0.25rem; }`
  );

  el(
    'lightning-radio-group',
    `<fieldset><legend class="l"></legend><slot></slot></fieldset>`,
    `fieldset { border: 0; padding: 0; margin: 0.25rem 0; } legend { font-size: 0.75rem; margin-bottom: 0.25rem; }`
  );

  el(
    'lightning-formatted-text',
    `<span part="text"><slot></slot></span>`,
    `:host { display: inline; font: inherit; }`
  );

  el(
    'lightning-formatted-number',
    `<span part="number"><slot></slot></span>`,
    `:host { display: inline; font: inherit; }`
  );

  el(
    'lightning-layout',
    `<div part="layout"><slot></slot></div>`,
    `:host { display: block; } div { display: flex; flex-wrap: wrap; gap: 0.5rem; }`
  );

  el(
    'lightning-layout-item',
    `<div part="item"><slot></slot></div>`,
    `:host { display: block; flex: 1 1 auto; min-width: 0; }`
  );

  el(
    'lightning-tabset',
    `<div part="tabs"><slot name="tabs"></slot><div part="content"><slot></slot></div></div>`,
    `:host { display: block; }`
  );

  el(
    'lightning-tab',
    `<div part="tab"><slot></slot></div>`,
    `:host { display: block; padding: 0.5rem 0; }`
  );
}

/** Tags covered by registerLightningStubs (for compat reports). */
export const LIGHTNING_STUB_TAGS = [
  'lightning-button',
  'lightning-input',
  'lightning-textarea',
  'lightning-combobox',
  'lightning-spinner',
  'lightning-card',
  'lightning-badge',
  'lightning-icon',
  'lightning-button-group',
  'lightning-radio-group',
  'lightning-formatted-text',
  'lightning-formatted-number',
  'lightning-layout',
  'lightning-layout-item',
  'lightning-tabset',
  'lightning-tab'
] as const;
