import { LitElement, html, nothing, type TemplateResult } from 'lit';
import { customElement, property, state } from 'lit/decorators.js';
import { renderAdminModule, type AdminModuleContext } from './admin-modules';

interface AdminCard {
  id: string;
  accent: string;
  title: string;
  description: string;
  icon: string;
  componentName: string;
}

const ADMIN_CARDS: AdminCard[] = [
  {
    id: 'clm',
    accent: 'pink',
    title: 'CLM',
    description: 'Upload presentations, manage slides, and configure territory targeting.',
    icon: 'utility:screen',
    componentName: 'clmAdminConsole'
  },
  {
    id: 'rating-layouts',
    accent: 'orange',
    title: 'Rating Layouts',
    description: 'Design account, territory, and product rating forms with live preview.',
    icon: 'utility:rating',
    componentName: 'clmRatingLayoutEditor'
  },
  {
    id: 'coaching-management',
    accent: 'teal',
    title: 'Coaching Management',
    description: 'Browse coaching templates, create new templates, and open the template editor.',
    icon: 'utility:education',
    componentName: 'coachingTemplateManager'
  },
  {
    id: 'territory-management',
    accent: 'indigo',
    title: 'Territory Management',
    description: 'Manage product lines, edit territories, assign users, and create demo field force accounts.',
    icon: 'utility:target',
    componentName: 'territoryManagementConsole'
  },
  {
    id: 'bricks-management',
    accent: 'purple',
    title: 'Bricks Management',
    description: 'Define IQVIA IMS bricks, align them to territories, and manage pharmacy account membership.',
    icon: 'utility:location',
    componentName: 'bricksManagementConsole'
  },
  {
    id: 'products-manager',
    accent: 'green',
    title: 'Products Manager',
    description: 'Browse the product catalog by brand and align products to territory hierarchies.',
    icon: 'utility:product',
    componentName: 'productTerritoryManager'
  },
  {
    id: 'plan-manager',
    accent: 'teal',
    title: 'Plan Manager',
    description: 'Manage monthly plan cycles, review employee coverage, and copy plans between months.',
    icon: 'utility:chart',
    componentName: 'planCycleManager'
  },
  {
    id: 'sales-data',
    accent: 'blue',
    title: 'Sales Data',
    description: 'Import IbnSina / Pharmaoverseas withdrawal CSVs and review loaded sell-out data.',
    icon: 'utility:upload',
    componentName: 'pharmacySalesDataAdmin'
  },
  {
    id: 'integrations-management',
    accent: 'slate',
    title: 'Integrations Management',
    description: 'Monitor IMS Health, OneKey, Maps, Mendix, and other external platform connectors.',
    icon: 'utility:link',
    componentName: 'integrationsManagementConsole'
  }
];

@customElement('osr-admin-console')
export class OsrAdminConsole extends LitElement {
  @property({ type: String }) label = 'Setup / Modules';
  @property({ attribute: false }) moduleCtx: AdminModuleContext | null = null;

  @state() private searchTerm = '';
  @state() private showModal = false;
  @state() private modalTitle = '';
  @state() private selectedComponent = '';

  createRenderRoot() {
    return this;
  }

  private get cardsView() {
    const term = this.searchTerm.trim().toLowerCase();
    const filtered = term
      ? ADMIN_CARDS.filter(
          (card) =>
            card.title.toLowerCase().includes(term) ||
            card.description.toLowerCase().includes(term)
        )
      : ADMIN_CARDS;
    return filtered.map((card) => ({
      ...card,
      cardClass: `admin-card admin-card--${card.accent}`,
      ariaLabel: `${card.title}. ${card.description}`
    }));
  }

  private childCtx(): AdminModuleContext {
    const base: AdminModuleContext = this.moduleCtx ?? { online: false, db: null };
    return {
      ...base,
      openAdminModule: (componentName, title) => {
        this.selectedComponent = componentName;
        this.modalTitle = title || 'Admin Module';
        base.openAdminModule?.(componentName, title);
      }
    };
  }

  private openCard(card: AdminCard) {
    this.selectedComponent = card.componentName;
    this.modalTitle = card.title;
    this.showModal = true;
  }

  private closeModal() {
    this.showModal = false;
    this.selectedComponent = '';
    this.modalTitle = '';
  }

  private handleCardKeydown(ev: KeyboardEvent, card: AdminCard) {
    if (ev.key !== 'Enter' && ev.key !== ' ') return;
    ev.preventDefault();
    this.openCard(card);
  }

  render() {
    const cards = this.cardsView;
    return html`
      <div class="osr-lwc-mirror admin-console-root">
        <section class="admin-console">
          <header class="admin-header">
            <div class="admin-header-icon" aria-hidden="true">${iconSvg('utility:settings')}</div>
            <div class="admin-header-text">
              <h1 class="admin-header-title">${this.label || 'Setup / Modules'}</h1>
              <p class="admin-header-subtitle">
                Configure presentations, coaching, territory alignment, and operational settings.
              </p>
            </div>
          </header>

          <div class="admin-body">
            <div class="admin-search">
              <input
                class="admin-search-input"
                type="search"
                placeholder="Search items..."
                aria-label="Search modules"
                .value=${this.searchTerm}
                @input=${(ev: Event) => {
                  this.searchTerm = (ev.target as HTMLInputElement).value;
                }}
              />
            </div>

            <div class="admin-section-header">
              <span class="admin-section-chevron" aria-hidden="true">${iconSvg('utility:chevrondown', 12)}</span>
              <span class="admin-section-label">General</span>
              <span class="admin-section-count">${ADMIN_CARDS.length} modules</span>
            </div>

            <div class="admin-cards-grid">
              ${cards.map(
                (card) => html`
                  <article
                    class=${card.cardClass}
                    role="button"
                    tabindex="0"
                    aria-label=${card.ariaLabel}
                    @click=${() => this.openCard(card)}
                    @keydown=${(ev: KeyboardEvent) => this.handleCardKeydown(ev, card)}
                  >
                    <div class="admin-card-icon-panel" aria-hidden="true">${iconSvg(card.icon)}</div>
                    <div class="admin-card-body">
                      <h3 class="admin-card-title">${card.title}</h3>
                      <p class="admin-card-desc">${card.description}</p>
                    </div>
                    <div class="admin-card-chevron" aria-hidden="true">
                      ${iconSvg('utility:chevronright', 12)}
                    </div>
                  </article>
                `
              )}
            </div>

            ${cards.length === 0
              ? html`<div class="admin-empty"><p>No modules match your search.</p></div>`
              : nothing}
          </div>
        </section>

        ${this.showModal
          ? html`
              <div class="admin-console-modal-wrapper">
                <div
                  class="admin-console-backdrop"
                  role="presentation"
                  aria-hidden="true"
                  @click=${() => this.closeModal()}
                ></div>
                <section
                  role="dialog"
                  tabindex="-1"
                  class="slds-modal slds-fade-in-open slds-modal_large admin-console-modal"
                  aria-labelledby="admin-console-modal-heading"
                  aria-modal="true"
                >
                  <div class="slds-modal__container">
                    <header class="slds-modal__header">
                      <button
                        type="button"
                        class="slds-button slds-button_icon slds-modal__close slds-button_icon-inverse"
                        title="Close"
                        @click=${() => this.closeModal()}
                      >
                        ${iconSvg('utility:close', 14)}
                        <span class="slds-assistive-text">Close</span>
                      </button>
                      <h2 id="admin-console-modal-heading" class="slds-modal__title slds-hyphenate">
                        ${this.modalTitle}
                      </h2>
                    </header>
                    <div class="slds-modal__content slds-p-around_medium admin-module-host">
                      ${renderAdminModule(this.selectedComponent, this.childCtx())}
                    </div>
                  </div>
                </section>
              </div>
            `
          : nothing}
      </div>
    `;
  }
}

declare global {
  interface HTMLElementTagNameMap {
    'osr-admin-console': OsrAdminConsole;
  }
}

/** Vite catalog port for c/adminConsole — mirrors Salesforce adminConsole LWC. */
export function renderAdminConsole(opts: {
  label: string;
  moduleCtx: AdminModuleContext;
}): TemplateResult {
  return html`
    <osr-admin-console .label=${opts.label} .moduleCtx=${opts.moduleCtx}></osr-admin-console>
  `;
}

function iconSvg(name: string, size = 20): TemplateResult {
  const s = size;
  switch (name) {
    case 'utility:settings':
      return html`<svg width="${s}" height="${s}" viewBox="0 0 52 52" fill="currentColor" aria-hidden="true">
        <path
          d="M44.1 28.2l-1.8-.3a14.8 14.8 0 00-1.2-2.9l1-1.5a2 2 0 00-.3-2.6l-2.8-2.8a2 2 0 00-2.6-.3l-1.5 1a14.8 14.8 0 00-2.9-1.2l-.3-1.8A2 2 0 0029.8 14h-4a2 2 0 00-2 1.8l-.3 1.8a14.8 14.8 0 00-2.9 1.2l-1.5-1a2 2 0 00-2.6.3l-2.8 2.8a2 2 0 00-.3 2.6l1 1.5a14.8 14.8 0 00-1.2 2.9l-1.8.3A2 2 0 0014 29.8v4a2 2 0 001.8 2l1.8.3c.3 1 .7 2 1.2 2.9l-1 1.5a2 2 0 00.3 2.6l2.8 2.8a2 2 0 002.6.3l1.5-1c.9.5 1.9.9 2.9 1.2l.3 1.8A2 2 0 0025.8 48h4a2 2 0 002-1.8l.3-1.8c1-.3 2-.7 2.9-1.2l1.5 1a2 2 0 002.6-.3l2.8-2.8a2 2 0 00.3-2.6l-1-1.5c.5-.9.9-1.9 1.2-2.9l1.8-.3A2 2 0 0048 33.8v-4a2 2 0 00-1.9-2zM28 36a8 8 0 110-16 8 8 0 010 16z"
        />
      </svg>`;
    case 'utility:chevrondown':
      return html`<svg width="${s}" height="${s}" viewBox="0 0 52 52" fill="currentColor" aria-hidden="true">
        <path d="M8.2 18.3l17.5 17.4c.8.8 2 .8 2.8 0L46 18.3c.8-.8.8-2 0-2.8s-2-.8-2.8 0L26 32.7 11 15.5c-.8-.8-2-.8-2.8 0s-.8 2 0 2.8z" />
      </svg>`;
    case 'utility:chevronright':
      return html`<svg width="${s}" height="${s}" viewBox="0 0 52 52" fill="currentColor" aria-hidden="true">
        <path d="M18.3 8.2l17.4 17.5c.8.8.8 2 0 2.8L18.3 46c-.8.8-2 .8-2.8 0s-.8-2 0-2.8L32.7 26 15.5 11c-.8-.8-.8-2 0-2.8s2-.8 2.8 0z" />
      </svg>`;
    case 'utility:close':
      return html`<svg width="${s}" height="${s}" viewBox="0 0 52 52" fill="currentColor" aria-hidden="true">
        <path
          d="M31 26l13-13c1-1 1-2.6 0-3.5-1-1-2.6-1-3.5 0L26 22.5 13 9.5c-1-1-2.6-1-3.5 0-1 1-1 2.6 0 3.5L22.5 26 9.5 39c-1 1-1 2.6 0 3.5 1 1 2.6 1 3.5 0L26 29.5l13 13c1 1 2.6 1 3.5 0 1-1 1-2.6 0-3.5L31 26z"
        />
      </svg>`;
    case 'utility:screen':
      return html`<svg width="${s}" height="${s}" viewBox="0 0 52 52" fill="currentColor" aria-hidden="true">
        <path d="M6 8h40a2 2 0 012 2v28a2 2 0 01-2 2H6a2 2 0 01-2-2V10a2 2 0 012-2zm4 32h32V14H10v26z" />
      </svg>`;
    case 'utility:rating':
      return html`<svg width="${s}" height="${s}" viewBox="0 0 52 52" fill="currentColor" aria-hidden="true">
        <path d="M26 6l6.2 12.6L46 20.2l-10 9.7 2.4 13.8L26 38.8 13.6 43.7 16 29.9 6 20.2l13.8-1.6L26 6z" />
      </svg>`;
    case 'utility:education':
      return html`<svg width="${s}" height="${s}" viewBox="0 0 52 52" fill="currentColor" aria-hidden="true">
        <path d="M26 4L4 16v4l22 12 22-12v-4L26 4zm0 28L8 22v8l18 10 18-10v-8L26 32z" />
      </svg>`;
    case 'utility:target':
      return html`<svg width="${s}" height="${s}" viewBox="0 0 52 52" fill="currentColor" aria-hidden="true">
        <path
          d="M26 4a22 22 0 100 44 22 22 0 000-44zm0 8a14 14 0 110 28 14 14 0 010-28zm0 8a6 6 0 100 12 6 6 0 000-12z"
        />
      </svg>`;
    case 'utility:location':
      return html`<svg width="${s}" height="${s}" viewBox="0 0 52 52" fill="currentColor" aria-hidden="true">
        <path
          d="M26 4c-8.3 0-15 6.7-15 15 0 11.2 15 29 15 29s15-17.8 15-29c0-8.3-6.7-15-15-15zm0 20a5 5 0 110-10 5 5 0 010 10z"
        />
      </svg>`;
    case 'utility:product':
      return html`<svg width="${s}" height="${s}" viewBox="0 0 52 52" fill="currentColor" aria-hidden="true">
        <path d="M8 14h36v28H8V14zm4 4v20h28V18H12zm6 6h16v4H18v-4zm0 8h12v4H18v-4z" />
      </svg>`;
    case 'utility:chart':
      return html`<svg width="${s}" height="${s}" viewBox="0 0 52 52" fill="currentColor" aria-hidden="true">
        <path d="M8 40h36V12h4v32H8v-4zm8-8h4V20h-4v12zm8 0h4V8h-4v24zm8 0h4V16h-4v16z" />
      </svg>`;
    case 'utility:upload':
      return html`<svg width="${s}" height="${s}" viewBox="0 0 52 52" fill="currentColor" aria-hidden="true">
        <path d="M26 6l12 12h-8v20h-8V18h-8L26 6zm-18 32h36v4H8v-4z" />
      </svg>`;
    case 'utility:link':
      return html`<svg width="${s}" height="${s}" viewBox="0 0 52 52" fill="currentColor" aria-hidden="true">
        <path
          d="M22 30l-4 4a6 6 0 008.5 8.5l8-8a6 6 0 00-8.5-8.5l-2 2 3 3 2-2a2 2 0 012.8 2.8l-8 8a2 2 0 01-2.8-2.8l3-3-3-3zm8-8l4-4a6 6 0 00-8.5-8.5l-8 8a6 6 0 008.5 8.5l2-2-3-3-2 2a2 2 0 01-2.8-2.8l8-8a2 2 0 012.8 2.8l-3 3 3 3z"
        />
      </svg>`;
    default:
      return html`<svg width="${s}" height="${s}" viewBox="0 0 52 52" fill="currentColor" aria-hidden="true">
        <circle cx="26" cy="26" r="10" />
      </svg>`;
  }
}
