import { LitElement, html, nothing, type TemplateResult } from 'lit';
import { customElement, property, state } from 'lit/decorators.js';
import { adminApex, adminToast, reduceAdminError } from './api';
import type { AdminModuleContext } from './types';

interface PresentationRow {
  id: string;
  name: string;
  status: string;
  formatType: string;
  productName: string;
  imageUrl?: string;
  slideCount: number;
}

const STATUS_OPTIONS = [
  { label: 'All', value: 'All' },
  { label: 'Available', value: 'Available' },
  { label: 'Draft', value: 'Draft' },
  { label: 'Deactivated', value: 'Deactivated' }
];

@customElement('osr-clm-admin-console')
export class OsrClmAdminConsole extends LitElement {
  @property({ attribute: false }) ctx!: AdminModuleContext;

  @state() private statusFilter = 'All';
  @state() private presentations: PresentationRow[] = [];
  @state() private loading = false;
  @state() private showWizard = false;
  @state() private selectedPresentationId: string | null = null;

  createRenderRoot() {
    return this;
  }

  connectedCallback() {
    super.connectedCallback();
    void this.loadPresentations();
  }

  updated(changed: Map<string, unknown>) {
    super.updated(changed);
    if (changed.has('ctx') && this.ctx) {
      void this.loadPresentations();
    }
  }

  private get embedded(): boolean {
    return !!this.ctx?.embedded;
  }

  private get containerClass(): string {
    return this.embedded ? 'clm-admin-console clm-admin-console-embedded' : 'clm-admin-console';
  }

  private async loadPresentations() {
    if (!this.ctx) return;
    this.loading = true;
    try {
      const data = await adminApex(this.ctx, 'ClmAdminController.getPresentations', {
        statusFilter: this.statusFilter
      });
      this.presentations = Array.isArray(data) ? (data as PresentationRow[]) : [];
    } catch (error) {
      adminToast(this.ctx, 'Load failed', reduceAdminError(error), 'error');
      this.presentations = [];
    } finally {
      this.loading = false;
    }
  }

  private handleStatusFilter(ev: Event) {
    this.statusFilter = (ev.target as HTMLSelectElement).value;
    void this.loadPresentations();
  }

  private handleNew() {
    this.selectedPresentationId = null;
    this.showWizard = true;
  }

  private handleEdit(ev: Event) {
    this.selectedPresentationId = (ev.currentTarget as HTMLButtonElement).dataset.id ?? null;
    this.showWizard = true;
  }

  private async handleDeactivate(ev: Event) {
    const presentationId = (ev.currentTarget as HTMLButtonElement).dataset.id;
    if (!presentationId) return;
    try {
      await adminApex(this.ctx, 'ClmAdminController.deactivatePresentation', { presentationId });
      await this.loadPresentations();
      adminToast(
        this.ctx,
        'Presentation deactivated',
        'The presentation is no longer available to reps.',
        'success'
      );
    } catch (error) {
      adminToast(this.ctx, 'Deactivate failed', reduceAdminError(error), 'error');
    }
  }

  private handleWizardClose() {
    this.showWizard = false;
    this.selectedPresentationId = null;
    void this.loadPresentations();
  }

  render() {
    return html`
      <div class="osr-lwc-mirror admin-module">
        <section class=${this.containerClass}>
          ${this.embedded
            ? nothing
            : html`
                <header class="admin-header">
                  <svg width="20" height="20" viewBox="0 0 52 52" fill="currentColor" aria-hidden="true">
                    <path d="M6 8h40a2 2 0 012 2v28a2 2 0 01-2 2H6a2 2 0 01-2-2V10a2 2 0 012-2zm4 32h32V14H10v26z" />
                  </svg>
                  <div>
                    <h1>CLM Admin Console</h1>
                    <p>Upload presentations, configure slides, and manage territory availability.</p>
                  </div>
                </header>
              `}

          <section class="presentation-manager">
            <header class="manager-header">
              <div class="filter-field">
                <label for="clm-status-filter">Filter</label>
                <select
                  id="clm-status-filter"
                  .value=${this.statusFilter}
                  @change=${this.handleStatusFilter}
                >
                  ${STATUS_OPTIONS.map(
                    (opt) => html`<option value=${opt.value}>${opt.label}</option>`
                  )}
                </select>
              </div>
              <button type="button" class="slds-button slds-button_brand" @click=${this.handleNew}>
                New Presentation
              </button>
            </header>

            ${this.loading
              ? html`<p class="empty-copy">Loading presentations…</p>`
              : html`
                  <table class="manager-table">
                    <thead>
                      <tr>
                        <th>Name</th>
                        <th>Status</th>
                        <th>Format</th>
                        <th>Product</th>
                        <th>Slides</th>
                        <th>Actions</th>
                      </tr>
                    </thead>
                    <tbody>
                      ${this.presentations.length === 0
                        ? html`
                            <tr>
                              <td colspan="6">No presentations found.</td>
                            </tr>
                          `
                        : this.presentations.map(
                            (row) => html`
                              <tr>
                                <td>${row.name}</td>
                                <td>${row.status}</td>
                                <td>${row.formatType}</td>
                                <td>
                                  <div class="product-cell">
                                    ${row.imageUrl
                                      ? html`<img
                                          src=${row.imageUrl}
                                          alt=""
                                          width="24"
                                          height="24"
                                          style="border-radius:4px"
                                        />`
                                      : nothing}
                                    <span>${row.productName ?? '—'}</span>
                                  </div>
                                </td>
                                <td>${row.slideCount ?? 0}</td>
                                <td class="actions">
                                  <button
                                    type="button"
                                    class="slds-button slds-button_neutral"
                                    data-id=${row.id}
                                    @click=${this.handleEdit}
                                  >
                                    Edit
                                  </button>
                                  <button
                                    type="button"
                                    class="slds-button slds-button_neutral"
                                    data-id=${row.id}
                                    @click=${this.handleDeactivate}
                                  >
                                    Deactivate
                                  </button>
                                </td>
                              </tr>
                            `
                          )}
                    </tbody>
                  </table>
                `}

            ${this.showWizard
              ? html`
                  <section class="new-modal" role="dialog" aria-modal="true" aria-label="Presentation wizard">
                    <div class="new-modal-backdrop" @click=${this.handleWizardClose}></div>
                    <div class="new-modal-panel">
                      <h3 class="new-modal-title">Presentation Wizard</h3>
                      <p class="empty-copy">
                        Presentation wizard opens in Salesforce when online.
                      </p>
                      ${this.selectedPresentationId
                        ? html`<p class="empty-copy">Presentation ID: ${this.selectedPresentationId}</p>`
                        : nothing}
                      <div class="new-modal-actions">
                        <button
                          type="button"
                          class="slds-button slds-button_brand"
                          @click=${this.handleWizardClose}
                        >
                          Close
                        </button>
                      </div>
                    </div>
                  </section>
                `
              : nothing}
          </section>
        </section>
      </div>
    `;
  }
}

declare global {
  interface HTMLElementTagNameMap {
    'osr-clm-admin-console': OsrClmAdminConsole;
  }
}

export function renderClmAdminConsole(ctx: AdminModuleContext): TemplateResult {
  return html`<osr-clm-admin-console .ctx=${ctx}></osr-clm-admin-console>`;
}
