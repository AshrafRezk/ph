import { LitElement, html, nothing, type TemplateResult } from 'lit';
import { customElement, property } from 'lit/decorators.js';
import type { AdminModuleContext } from './types';

interface IntegrationItem {
  id: string;
  name: string;
  category: string;
  description: string;
  status: string;
  statusClass: string;
  icon: string;
  lastSync: string;
  actionLabel?: string | null;
  actionType?: 'admin' | 'tab' | null;
  adminComponent?: string;
  tabApiName?: string;
}

const INTEGRATIONS: IntegrationItem[] = [
  {
    id: 'ims-health',
    name: 'IQVIA IMS Health',
    category: 'Market Data',
    description:
      'Brick-level sell-out, market share, and geographic alignment for territory planning.',
    status: 'Connected',
    statusClass: 'status-pill status-pill--connected',
    icon: 'utility:chart',
    lastSync: 'Daily at 02:00',
    actionLabel: 'Manage Bricks',
    actionType: 'admin',
    adminComponent: 'bricksManagementConsole'
  },
  {
    id: 'onekey',
    name: 'OneKey Database',
    category: 'HCP / HCO Master',
    description: 'Validate and enrich HCP and HCO records with OneKey identifiers and affiliations.',
    status: 'Configured',
    statusClass: 'status-pill status-pill--configured',
    icon: 'utility:contact',
    lastSync: 'Weekly',
    actionLabel: null,
    actionType: null
  },
  {
    id: 'maps',
    name: 'Maps',
    category: 'Field Planning',
    description: 'OpenStreetMap routing and territory visualization in the Field Rep Planner.',
    status: 'Connected',
    statusClass: 'status-pill status-pill--connected',
    icon: 'utility:location',
    lastSync: 'Real-time',
    actionLabel: null,
    actionType: null
  },
  {
    id: 'mendix',
    name: 'Mendix',
    category: 'Low-Code Apps',
    description:
      'Bi-directional sync with Mendix apps for promo budgets, project management, and cross-dept workflows.',
    status: 'Pending Setup',
    statusClass: 'status-pill status-pill--pending',
    icon: 'utility:link',
    lastSync: '—',
    actionLabel: 'Open Mendix Hub',
    actionType: 'tab',
    tabApiName: 'Mendix_Integration'
  },
  {
    id: 'ibnsina-pharmaoverseas',
    name: 'Wholesaler Feeds (IbnSina / Pharmaoverseas)',
    category: 'Sell-Out Data',
    description: 'Import pharmacy withdrawal CSVs for sell-out analytics and coverage tracking.',
    status: 'Connected',
    statusClass: 'status-pill status-pill--connected',
    icon: 'utility:upload',
    lastSync: 'On demand',
    actionLabel: 'Sales Data Admin',
    actionType: 'admin',
    adminComponent: 'pharmacySalesDataAdmin'
  },
  {
    id: 'veeva-network',
    name: 'Veeva Network',
    category: 'HCP / HCO Master',
    description: 'Enterprise customer master data management and affiliation hierarchy.',
    status: 'Planned',
    statusClass: 'status-pill status-pill--planned',
    icon: 'utility:database',
    lastSync: '—',
    actionLabel: null,
    actionType: null
  },
  {
    id: 'outlook',
    name: 'Microsoft Outlook / Exchange',
    category: 'Productivity',
    description: 'Calendar sync for visit scheduling, coaching events, and field rep availability.',
    status: 'Planned',
    statusClass: 'status-pill status-pill--planned',
    icon: 'utility:event',
    lastSync: '—',
    actionLabel: null,
    actionType: null
  },
  {
    id: 'sap-erp',
    name: 'SAP / ERP',
    category: 'Finance & Supply',
    description: 'Order-to-cash, inventory, and financial reconciliation for sample and promo spend.',
    status: 'Planned',
    statusClass: 'status-pill status-pill--planned',
    icon: 'utility:money',
    lastSync: '—',
    actionLabel: null,
    actionType: null
  }
];

const PRIMARY_IDS = new Set(['ims-health', 'onekey', 'maps', 'mendix']);

function iconSvg(name: string, size = 20): TemplateResult {
  const s = size;
  switch (name) {
    case 'utility:chart':
      return html`<svg width="${s}" height="${s}" viewBox="0 0 52 52" fill="currentColor" aria-hidden="true">
        <path d="M8 40h36V12h4v32H8v-4zm8-8h4V20h-4v12zm8 0h4V8h-4v24zm8 0h4V16h-4v16z" />
      </svg>`;
    case 'utility:contact':
      return html`<svg width="${s}" height="${s}" viewBox="0 0 52 52" fill="currentColor" aria-hidden="true">
        <path
          d="M26 26a8 8 0 100-16 8 8 0 000 16zm-14 18c0-7.7 6.3-14 14-14s14 6.3 14 14v2H12v-2z"
        />
      </svg>`;
    case 'utility:location':
      return html`<svg width="${s}" height="${s}" viewBox="0 0 52 52" fill="currentColor" aria-hidden="true">
        <path
          d="M26 4c-8.3 0-15 6.7-15 15 0 11.2 15 29 15 29s15-17.8 15-29c0-8.3-6.7-15-15-15zm0 20a5 5 0 110-10 5 5 0 010 10z"
        />
      </svg>`;
    case 'utility:link':
      return html`<svg width="${s}" height="${s}" viewBox="0 0 52 52" fill="currentColor" aria-hidden="true">
        <path
          d="M22 30l-4 4a6 6 0 008.5 8.5l8-8a6 6 0 00-8.5-8.5l-2 2 3 3 2-2a2 2 0 012.8 2.8l-8 8a2 2 0 01-2.8-2.8l3-3-3-3zm8-8l4-4a6 6 0 00-8.5-8.5l-8 8a6 6 0 008.5 8.5l2-2-3-3-2 2a2 2 0 01-2.8-2.8l8-8a2 2 0 012.8 2.8l-3 3 3 3z"
        />
      </svg>`;
    case 'utility:upload':
      return html`<svg width="${s}" height="${s}" viewBox="0 0 52 52" fill="currentColor" aria-hidden="true">
        <path d="M26 6l12 12h-8v20h-8V18h-8L26 6zm-18 32h36v4H8v-4z" />
      </svg>`;
    case 'utility:database':
      return html`<svg width="${s}" height="${s}" viewBox="0 0 52 52" fill="currentColor" aria-hidden="true">
        <path d="M26 6c-11 0-20 3-20 7v26c0 4 9 7 20 7s20-3 20-7V13c0-4-9-7-20-7zm0 4c8.8 0 16 2.2 16 3s-7.2 3-16 3-16-2.2-16-3 7.2-3 16-3zm-16 9.5c2.6 1.4 9 2.5 16 2.5s13.4-1.1 16-2.5V22c-2.6 1.4-9 2.5-16 2.5s-13.4-1.1-16-2.5v-2.5zm0 10c2.6 1.4 9 2.5 16 2.5s13.4-1.1 16-2.5V32c-2.6 1.4-9 2.5-16 2.5s-13.4-1.1-16-2.5v-2.5z" />
      </svg>`;
    case 'utility:event':
      return html`<svg width="${s}" height="${s}" viewBox="0 0 52 52" fill="currentColor" aria-hidden="true">
        <path
          d="M14 8h4V4h4v4h8V4h4v4h4a2 2 0 012 2v32a2 2 0 01-2 2H14a2 2 0 01-2-2V10a2 2 0 012-2zm0 8v26h32V16H14z"
        />
      </svg>`;
    case 'utility:money':
      return html`<svg width="${s}" height="${s}" viewBox="0 0 52 52" fill="currentColor" aria-hidden="true">
        <path
          d="M26 4a22 22 0 100 44 22 22 0 000-44zm1 6v2.1a8 8 0 015.9 3.4l-3.5 2.1a4 4 0 00-2.4-1.5V20a6 6 0 016 6v2a6 6 0 01-4 5.7V36h-4v-2.3A8 8 0 0115.1 30l3.5-2.1a4 4 0 002.4 1.5V24a6 6 0 016-6V10z"
        />
      </svg>`;
    default:
      return html`<svg width="${s}" height="${s}" viewBox="0 0 52 52" fill="currentColor" aria-hidden="true">
        <circle cx="26" cy="26" r="10" />
      </svg>`;
  }
}

function renderIntegrationCard(item: IntegrationItem, compact: boolean, onAction: (id: string) => void) {
  const iconSize = compact ? 16 : 20;
  return html`
    <article class=${compact ? 'integration-card integration-card--compact' : 'integration-card'}>
      <div class="integration-card-top">
        <div class=${compact ? 'integration-icon-panel integration-icon-panel--compact' : 'integration-icon-panel'}>
          ${iconSvg(item.icon, iconSize)}
        </div>
        <span class=${item.statusClass}>${item.status}</span>
      </div>
      ${compact ? nothing : html`<p class="integration-category">${item.category}</p>`}
      <h4 class="integration-name">${item.name}</h4>
      <p class="integration-desc">${item.description}</p>
      ${compact
        ? nothing
        : html`
            <div class="integration-meta">
              <span class="integration-sync-label">Last sync</span>
              <span class="integration-sync-value">${item.lastSync}</span>
            </div>
          `}
      ${item.actionLabel
        ? html`
            <button
              type="button"
              class=${compact
                ? 'slds-button slds-button_neutral integration-action'
                : 'slds-button slds-button_brand integration-action'}
              data-integration-id=${item.id}
              @click=${() => onAction(item.id)}
            >
              ${item.actionLabel}
            </button>
          `
        : nothing}
    </article>
  `;
}

@customElement('osr-integrations-management')
export class OsrIntegrationsManagement extends LitElement {
  @property({ attribute: false }) ctx!: AdminModuleContext;

  createRenderRoot() {
    return this;
  }

  private get primaryIntegrations(): IntegrationItem[] {
    return INTEGRATIONS.filter((item) => PRIMARY_IDS.has(item.id));
  }

  private get additionalIntegrations(): IntegrationItem[] {
    return INTEGRATIONS.filter((item) => !PRIMARY_IDS.has(item.id));
  }

  private handleAction(integrationId: string) {
    const integration = INTEGRATIONS.find((item) => item.id === integrationId);
    if (!integration?.actionType) return;

    if (integration.actionType === 'tab') {
      if (integration.tabApiName) {
        this.ctx.openTab?.(integration.tabApiName);
      }
      return;
    }

    if (integration.actionType === 'admin' && integration.adminComponent) {
      this.ctx.openAdminModule?.(integration.adminComponent, integration.actionLabel ?? undefined);
    }
  }

  render() {
    return html`
      <div class="osr-lwc-mirror admin-module">
        <section class="integrations-console">
          <header class="integrations-header">
            <div class="integrations-header-text">
              <h2 class="integrations-title">Integrations Management</h2>
              <p class="integrations-subtitle">
                Monitor external data sources, master data providers, and platform connectors used
                across Pharma.
              </p>
            </div>
          </header>

          <section class="integrations-section">
            <h3 class="section-label">Core Integrations</h3>
            <div class="integrations-grid">
              ${this.primaryIntegrations.map((item) =>
                renderIntegrationCard(item, false, (id) => this.handleAction(id))
              )}
            </div>
          </section>

          <section class="integrations-section">
            <h3 class="section-label">Additional &amp; Recommended</h3>
            <p class="section-hint">
              Common pharma integrations to plan for as the platform matures.
            </p>
            <div class="integrations-grid integrations-grid--compact">
              ${this.additionalIntegrations.map((item) =>
                renderIntegrationCard(item, true, (id) => this.handleAction(id))
              )}
            </div>
          </section>
        </section>
      </div>
    `;
  }
}

declare global {
  interface HTMLElementTagNameMap {
    'osr-integrations-management': OsrIntegrationsManagement;
  }
}

export function renderIntegrationsManagement(ctx: AdminModuleContext): TemplateResult {
  return html`<osr-integrations-management .ctx=${ctx}></osr-integrations-management>`;
}
