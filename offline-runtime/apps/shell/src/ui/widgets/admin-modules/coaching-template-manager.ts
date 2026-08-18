import { LitElement, html, nothing, type TemplateResult } from 'lit';
import { customElement, property, state } from 'lit/decorators.js';
import { adminApex, adminToast, reduceAdminError } from './api';
import type { AdminModuleContext } from './types';

interface TemplateSummary {
  id: string;
  title: string;
  templateType: string;
  isActive: boolean;
  startDate?: string;
  endDate?: string;
}

interface TemplateRow extends TemplateSummary {
  activeLabel: string;
  startDateLabel: string;
  endDateLabel: string;
}

const ACTIVE_OPTIONS = [
  { label: 'All', value: 'All' },
  { label: 'Active', value: 'Active' },
  { label: 'Inactive', value: 'Inactive' }
];

const TYPE_OPTIONS = [{ label: 'Field Coaching', value: 'Field Coaching' }];

function mapTemplateRow(row: TemplateSummary): TemplateRow {
  return {
    ...row,
    activeLabel: row.isActive ? 'Active' : 'Inactive',
    startDateLabel: row.startDate || '—',
    endDateLabel: row.endDate || '—'
  };
}

@customElement('osr-coaching-template-manager')
export class OsrCoachingTemplateManager extends LitElement {
  @property({ attribute: false }) ctx!: AdminModuleContext;

  @state() private searchTerm = '';
  @state() private activeFilter = 'All';
  @state() private templates: TemplateRow[] = [];
  @state() private loading = false;
  @state() private showNewModal = false;
  @state() private newTitle = '';
  @state() private newType = 'Field Coaching';
  @state() private isSaving = false;

  createRenderRoot() {
    return this;
  }

  connectedCallback() {
    super.connectedCallback();
    void this.loadTemplates();
  }

  updated(changed: Map<string, unknown>) {
    super.updated(changed);
    if (changed.has('ctx') && this.ctx) {
      void this.loadTemplates();
    }
  }

  private get hasRows(): boolean {
    return this.templates.length > 0;
  }

  private get isNewDisabled(): boolean {
    return this.isSaving || !this.newTitle.trim();
  }

  private async loadTemplates() {
    if (!this.ctx) return;
    this.loading = true;
    try {
      const data = await adminApex(this.ctx, 'CoachingAdminController.getTemplateSummaries', {
        searchTerm: this.searchTerm,
        activeFilter: this.activeFilter
      });
      const rows = Array.isArray(data) ? (data as TemplateSummary[]) : [];
      this.templates = rows.map(mapTemplateRow);
    } catch (error) {
      adminToast(this.ctx, 'Load failed', reduceAdminError(error), 'error');
      this.templates = [];
    } finally {
      this.loading = false;
    }
  }

  private handleSearch(ev: Event) {
    this.searchTerm = (ev.target as HTMLInputElement).value;
    void this.loadTemplates();
  }

  private handleActiveFilter(ev: Event) {
    this.activeFilter = (ev.target as HTMLSelectElement).value;
    void this.loadTemplates();
  }

  private handleNew() {
    this.newTitle = '';
    this.newType = 'Field Coaching';
    this.showNewModal = true;
  }

  private handleNewTitle(ev: Event) {
    this.newTitle = (ev.target as HTMLInputElement).value;
  }

  private handleNewType(ev: Event) {
    this.newType = (ev.target as HTMLSelectElement).value;
  }

  private handleCloseNew() {
    this.showNewModal = false;
    this.newTitle = '';
  }

  private async handleCreate() {
    const title = this.newTitle.trim();
    if (!title) return;
    this.isSaving = true;
    try {
      const templateId = await adminApex(this.ctx, 'CoachingAdminController.createTemplate', {
        title,
        templateType: this.newType
      });
      this.showNewModal = false;
      this.newTitle = '';
      await this.loadTemplates();
      adminToast(this.ctx, 'Template created', 'Opening the template editor.', 'success');
      if (typeof templateId === 'string' && templateId) {
        this.ctx.openRecord?.('Coaching_Template__c', templateId);
      }
    } catch (error) {
      adminToast(this.ctx, 'Create failed', reduceAdminError(error), 'error');
    } finally {
      this.isSaving = false;
    }
  }

  private handleOpen(ev: Event) {
    const templateId = (ev.currentTarget as HTMLButtonElement).dataset.id;
    if (templateId) {
      this.ctx.openRecord?.('Coaching_Template__c', templateId);
    }
  }

  render() {
    return html`
      <div class="osr-lwc-mirror admin-module">
        <section class="template-manager">
          <header class="manager-header">
            <div class="manager-filters">
              <div class="filter-field">
                <label for="coaching-search">Search</label>
                <input
                  id="coaching-search"
                  type="search"
                  .value=${this.searchTerm}
                  @input=${this.handleSearch}
                />
              </div>
              <div class="filter-field">
                <label for="coaching-status">Status</label>
                <select
                  id="coaching-status"
                  .value=${this.activeFilter}
                  @change=${this.handleActiveFilter}
                >
                  ${ACTIVE_OPTIONS.map(
                    (opt) => html`<option value=${opt.value}>${opt.label}</option>`
                  )}
                </select>
              </div>
            </div>
            <button type="button" class="slds-button slds-button_brand" @click=${this.handleNew}>
              New Template
            </button>
          </header>

          ${this.loading
            ? html`<p class="empty-copy">Loading templates…</p>`
            : this.hasRows
              ? html`
                  <table class="manager-table">
                    <thead>
                      <tr>
                        <th>Title</th>
                        <th>Type</th>
                        <th>Status</th>
                        <th>Start</th>
                        <th>End</th>
                        <th>Actions</th>
                      </tr>
                    </thead>
                    <tbody>
                      ${this.templates.map(
                        (row) => html`
                          <tr>
                            <td>${row.title}</td>
                            <td>${row.templateType}</td>
                            <td>${row.activeLabel}</td>
                            <td>${row.startDateLabel}</td>
                            <td>${row.endDateLabel}</td>
                            <td class="actions">
                              <button
                                type="button"
                                class="slds-button slds-button_neutral"
                                data-id=${row.id}
                                @click=${this.handleOpen}
                              >
                                Open
                              </button>
                            </td>
                          </tr>
                        `
                      )}
                    </tbody>
                  </table>
                `
              : html`
                  <div class="empty-state">
                    <p>No coaching templates found.</p>
                    <button type="button" class="slds-button slds-button_brand" @click=${this.handleNew}>
                      Create first template
                    </button>
                  </div>
                `}

          ${this.showNewModal
            ? html`
                <section class="new-modal" role="dialog" aria-modal="true" aria-label="New coaching template">
                  <div class="new-modal-backdrop" @click=${this.handleCloseNew}></div>
                  <div class="new-modal-panel">
                    <h3 class="new-modal-title">New Coaching Template</h3>
                    <div class="filter-field">
                      <label for="new-template-title">Template Title</label>
                      <input
                        id="new-template-title"
                        type="text"
                        required
                        .value=${this.newTitle}
                        @input=${this.handleNewTitle}
                      />
                    </div>
                    <div class="filter-field">
                      <label for="new-template-type">Template Type</label>
                      <select id="new-template-type" .value=${this.newType} @change=${this.handleNewType}>
                        ${TYPE_OPTIONS.map(
                          (opt) => html`<option value=${opt.value}>${opt.label}</option>`
                        )}
                      </select>
                    </div>
                    <div class="new-modal-actions">
                      <button type="button" class="slds-button slds-button_neutral" @click=${this.handleCloseNew}>
                        Cancel
                      </button>
                      <button
                        type="button"
                        class="slds-button slds-button_brand"
                        ?disabled=${this.isNewDisabled}
                        @click=${this.handleCreate}
                      >
                        ${this.isSaving ? 'Creating…' : 'Create'}
                      </button>
                    </div>
                  </div>
                </section>
              `
            : nothing}
        </section>
      </div>
    `;
  }
}

declare global {
  interface HTMLElementTagNameMap {
    'osr-coaching-template-manager': OsrCoachingTemplateManager;
  }
}

export function renderCoachingTemplateManager(ctx: AdminModuleContext): TemplateResult {
  return html`<osr-coaching-template-manager .ctx=${ctx}></osr-coaching-template-manager>`;
}
