import { LitElement, html, nothing, type TemplateResult } from 'lit';
import { customElement, property, state } from 'lit/decorators.js';
import { adminApex, adminToast, reduceAdminError } from './api';
import { flattenTerritoryTree, initExpandedFromRoots } from './territory-tree';
import type { AdminModuleContext, TerritoryTreeNode } from './types';
import type { FlatTerritoryRow } from './territory-tree';

const DATA_SOURCE_OPTIONS = [
  { label: 'IQVIA IMS', value: 'IQVIA IMS' },
  { label: 'IbnSina', value: 'IbnSina' },
  { label: 'Pharmaoverseas', value: 'Pharmaoverseas' }
];

interface BrickRow {
  brickId: string;
  brickName: string;
  brickCode?: string;
  dataSource?: string;
  city?: string;
  governorate?: string;
  pharmacyCount?: number;
  isActive?: boolean;
  statusLabel?: string;
  rowClass?: string;
}

interface PharmacyRow {
  membershipId: string;
  pharmacyName: string;
  pharmacyType?: string;
}

@customElement('osr-bricks-management-console')
export class OsrBricksManagementConsole extends LitElement {
  @property({ attribute: false }) ctx!: AdminModuleContext;

  @state() private treeRoots: TerritoryTreeNode[] = [];
  @state() private territoryFlatRows: FlatTerritoryRow[] = [];
  @state() private territoryExpandedIds = new Set<string>();
  @state() private selectedTerritoryId: string | null = null;
  @state() private selectedTerritoryName = 'All Territories';
  @state() private brickRows: BrickRow[] = [];
  @state() private pharmacyRows: PharmacyRow[] = [];
  @state() private pharmacyOptions: { label: string; value: string }[] = [];
  @state() private selectedBrickId: string | null = null;
  @state() private selectedBrickName = '';
  @state() private selectedPharmacyId: string | null = null;
  @state() private pharmacySearchTerm = '';
  @state() private brickSearchTerm = '';
  @state() private showBrickModal = false;
  @state() private isSaving = false;
  @state() private isSeeding = false;
  @state() private draftBrick = {
    recordId: null as string | null,
    name: '',
    externalId: '',
    brickCode: '',
    dataSource: 'IQVIA IMS',
    governorate: '',
    city: '',
    isActive: true
  };

  createRenderRoot() {
    return this;
  }

  connectedCallback() {
    super.connectedCallback();
    void this.loadTerritoryTree();
    void this.loadBricks();
  }

  updated(changed: Map<string, unknown>) {
    super.updated(changed);
    if (changed.has('selectedTerritoryId')) {
      void this.loadBricks();
      this.selectedBrickId = null;
      this.selectedBrickName = '';
      this.pharmacyRows = [];
    }
    if (changed.has('selectedBrickId') && this.selectedBrickId) {
      void this.loadPharmacies();
    }
    if (changed.has('pharmacySearchTerm')) {
      void this.loadPharmacyOptions();
    }
  }

  private rebuildTerritoryRows() {
    this.territoryFlatRows = flattenTerritoryTree(this.treeRoots, this.territoryExpandedIds, {
      selectedId: this.selectedTerritoryId,
      includeAllRow: true
    });
  }

  private get filteredBrickRows() {
    const term = this.brickSearchTerm.trim().toLowerCase();
    if (!term) return this.brickRows;
    return this.brickRows.filter(
      (row) =>
        (row.brickName || '').toLowerCase().includes(term) ||
        (row.brickCode || '').toLowerCase().includes(term) ||
        (row.city || '').toLowerCase().includes(term) ||
        (row.dataSource || '').toLowerCase().includes(term)
    );
  }

  private async loadTerritoryTree() {
    try {
      const data = (await adminApex(this.ctx, 'TerritoryManagementController.getTerritoryTree')) as TerritoryTreeNode[];
      this.treeRoots = data ?? [];
      if (this.territoryExpandedIds.size === 0) {
        this.territoryExpandedIds = initExpandedFromRoots(this.treeRoots);
      }
      this.rebuildTerritoryRows();
    } catch (error) {
      adminToast(this.ctx, 'Load failed', reduceAdminError(error), 'error');
    }
  }

  private async loadBricks() {
    try {
      const data = (await adminApex(this.ctx, 'BricksManagementController.getBricksByTerritory', {
        territory2Id: this.selectedTerritoryId
      })) as BrickRow[];
      this.brickRows = (data ?? []).map((row) => ({
        ...row,
        statusLabel: row.isActive !== false ? 'Active' : 'Inactive',
        rowClass: row.brickId === this.selectedBrickId ? 'brick-row brick-row--selected' : 'brick-row'
      }));
    } catch (error) {
      adminToast(this.ctx, 'Load failed', reduceAdminError(error), 'error');
      this.brickRows = [];
    }
  }

  private async loadPharmacies() {
    if (!this.selectedBrickId) {
      this.pharmacyRows = [];
      return;
    }
    try {
      const data = (await adminApex(this.ctx, 'BricksManagementController.getBrickPharmacies', {
        brickId: this.selectedBrickId
      })) as PharmacyRow[];
      this.pharmacyRows = data ?? [];
    } catch (error) {
      this.pharmacyRows = [];
    }
  }

  private async loadPharmacyOptions() {
    try {
      const data = (await adminApex(this.ctx, 'BricksManagementController.searchPharmacyOptions', {
        searchTerm: this.pharmacySearchTerm
      })) as { label: string; value: string }[];
      this.pharmacyOptions = data ?? [];
    } catch {
      this.pharmacyOptions = [];
    }
  }

  private handleTerritoryToggle(id: string) {
    if (this.territoryExpandedIds.has(id)) this.territoryExpandedIds.delete(id);
    else this.territoryExpandedIds.add(id);
    this.territoryExpandedIds = new Set(this.territoryExpandedIds);
    this.rebuildTerritoryRows();
  }

  private handleTerritorySelect(id: string | null, name: string) {
    this.selectedTerritoryId = id;
    this.selectedTerritoryName = name;
    this.rebuildTerritoryRows();
  }

  private handleBrickSelect(brickId: string, brickName: string) {
    this.selectedBrickId = brickId;
    this.selectedBrickName = brickName;
    this.brickRows = this.brickRows.map((row) => ({
      ...row,
      rowClass: row.brickId === brickId ? 'brick-row brick-row--selected' : 'brick-row'
    }));
  }

  private async handleSaveBrick() {
    this.isSaving = true;
    try {
      const brickId = (await adminApex(this.ctx, 'BricksManagementController.upsertBrick', {
        recordId: this.draftBrick.recordId,
        name: this.draftBrick.name,
        externalId: this.draftBrick.externalId,
        brickCode: this.draftBrick.brickCode,
        dataSource: this.draftBrick.dataSource,
        governorate: this.draftBrick.governorate,
        city: this.draftBrick.city,
        territory2Id: this.selectedTerritoryId,
        isActive: this.draftBrick.isActive
      })) as string;
      if (this.selectedTerritoryId && !this.draftBrick.recordId) {
        await adminApex(this.ctx, 'BricksManagementController.assignBrickToTerritory', {
          brickId,
          territory2Id: this.selectedTerritoryId
        });
      }
      this.showBrickModal = false;
      await this.loadBricks();
      adminToast(this.ctx, 'Success', 'Brick saved.', 'success');
    } catch (error) {
      adminToast(this.ctx, 'Save failed', reduceAdminError(error), 'error');
    } finally {
      this.isSaving = false;
    }
  }

  private async handleAssignTerritory(brickId: string) {
    if (!this.selectedTerritoryId) {
      adminToast(this.ctx, 'Select territory', 'Choose a territory on the left first.', 'warning');
      return;
    }
    try {
      await adminApex(this.ctx, 'BricksManagementController.assignBrickToTerritory', {
        brickId,
        territory2Id: this.selectedTerritoryId
      });
      await this.loadBricks();
      adminToast(this.ctx, 'Aligned', 'Brick aligned to territory.', 'success');
    } catch (error) {
      adminToast(this.ctx, 'Alignment failed', reduceAdminError(error), 'error');
    }
  }

  private async handleDeleteBrick(brickId: string) {
    try {
      await adminApex(this.ctx, 'BricksManagementController.deleteBrick', { brickId });
      if (this.selectedBrickId === brickId) {
        this.selectedBrickId = null;
        this.selectedBrickName = '';
        this.pharmacyRows = [];
      }
      await this.loadBricks();
      adminToast(this.ctx, 'Deleted', 'Brick removed.', 'success');
    } catch (error) {
      adminToast(this.ctx, 'Delete failed', reduceAdminError(error), 'error');
    }
  }

  private async handleAddPharmacy() {
    if (!this.selectedBrickId || !this.selectedPharmacyId) return;
    try {
      await adminApex(this.ctx, 'BricksManagementController.addPharmacyToBrick', {
        brickId: this.selectedBrickId,
        pharmacyId: this.selectedPharmacyId
      });
      this.selectedPharmacyId = null;
      await this.loadPharmacies();
      await this.loadBricks();
      adminToast(this.ctx, 'Added', 'Pharmacy linked to brick.', 'success');
    } catch (error) {
      adminToast(this.ctx, 'Add failed', reduceAdminError(error), 'error');
    }
  }

  private async handleRemovePharmacy(membershipId: string) {
    try {
      await adminApex(this.ctx, 'BricksManagementController.removePharmacyFromBrick', { membershipId });
      await this.loadPharmacies();
      await this.loadBricks();
      adminToast(this.ctx, 'Removed', 'Pharmacy removed from brick.', 'success');
    } catch (error) {
      adminToast(this.ctx, 'Remove failed', reduceAdminError(error), 'error');
    }
  }

  private async handleSeedDemoData() {
    this.isSeeding = true;
    try {
      const result = (await adminApex(this.ctx, 'BricksManagementController.seedBrickDemoData')) as {
        message?: string;
      };
      await this.loadBricks();
      if (this.selectedBrickId) await this.loadPharmacies();
      adminToast(this.ctx, 'Demo data loaded', result.message || 'Brick demo data refreshed.', 'success');
    } catch (error) {
      adminToast(this.ctx, 'Seed failed', reduceAdminError(error), 'error');
    } finally {
      this.isSeeding = false;
    }
  }

  render() {
    const filtered = this.filteredBrickRows;
    const isSaveBrickDisabled = this.isSaving || !this.draftBrick.name.trim();
    const isAddPharmacyDisabled = !this.selectedBrickId || !this.selectedPharmacyId;

    return html`
      <article class="osr-lwc-mirror bricks-management-root">
        <section class="bricks-console">
          <header class="console-header">
            <div>
              <p class="console-subtitle">
                Align IQVIA IMS / IbnSina / Pharmaoverseas geographic bricks to territories and manage pharmacy
                membership.
              </p>
            </div>
            <div class="console-header-actions">
              <button
                type="button"
                class="slds-button slds-button_neutral"
                ?disabled=${this.isSeeding}
                @click=${this.handleSeedDemoData}
              >
                Load Demo Bricks
              </button>
              <button
                type="button"
                class="slds-button slds-button_brand"
                @click=${() => {
                  this.draftBrick = {
                    recordId: null,
                    name: '',
                    externalId: '',
                    brickCode: '',
                    dataSource: 'IQVIA IMS',
                    governorate: '',
                    city: '',
                    isActive: true
                  };
                  this.showBrickModal = true;
                }}
              >
                New Brick
              </button>
            </div>
          </header>

          <div class="console-panels">
            <section class="panel panel-territories">
              <div class="panel-heading">
                <h3>Territories</h3>
                <p class="panel-caption">Filter bricks by aligned territory</p>
              </div>
              ${this.territoryFlatRows.length > 0
                ? html`<ul class="tree-list" role="tree">
                    ${this.territoryFlatRows.map(
                      (row) => html`
                        <li class=${row.rowClass} role="treeitem">
                          <div class="tree-row-content" style=${row.depthStyle}>
                            ${row.hasChildren
                              ? html`<button
                                  type="button"
                                  class="toggle-btn"
                                  @click=${() => row.id && this.handleTerritoryToggle(row.id)}
                                >
                                  ${row.expanded ? '▼' : '▶'}
                                </button>`
                              : html`<span class="toggle-spacer"></span>`}
                            <button
                              type="button"
                              class="territory-select-btn"
                              @click=${() => this.handleTerritorySelect(row.id, row.name)}
                            >
                              ${row.name}
                            </button>
                          </div>
                        </li>
                      `
                    )}
                  </ul>`
                : html`<div class="empty-state"><p>No territories found. Run territory seeding first.</p></div>`}
            </section>

            <section class="panel panel-bricks">
              <div class="panel-heading">
                <h3>Bricks — ${this.selectedTerritoryName}</h3>
                <input
                  type="search"
                  placeholder="Search by name, code, city..."
                  .value=${this.brickSearchTerm}
                  @input=${(ev: Event) => (this.brickSearchTerm = (ev.target as HTMLInputElement).value)}
                />
              </div>
              ${filtered.length > 0
                ? html`<div class="brick-list">
                    ${filtered.map(
                      (brick) => html`
                        <article class=${brick.rowClass}>
                          <button
                            type="button"
                            class="brick-select-btn"
                            @click=${() => this.handleBrickSelect(brick.brickId, brick.brickName)}
                          >
                            <span class="brick-name">${brick.brickName}</span>
                            <span class="brick-meta">
                              ${brick.brickCode} · ${brick.dataSource} · ${brick.city}
                            </span>
                            <span class="brick-count">${brick.pharmacyCount ?? 0} pharmacies</span>
                          </button>
                          <div class="brick-actions">
                            <button
                              type="button"
                              class="slds-button slds-button_icon"
                              title="Edit brick"
                              @click=${() => {
                                this.draftBrick = {
                                  recordId: brick.brickId,
                                  name: brick.brickName,
                                  externalId: '',
                                  brickCode: brick.brickCode || '',
                                  dataSource: brick.dataSource || 'IQVIA IMS',
                                  governorate: brick.governorate || '',
                                  city: brick.city || '',
                                  isActive: brick.isActive !== false
                                };
                                this.showBrickModal = true;
                              }}
                            >
                              ✎
                            </button>
                            <button
                              type="button"
                              class="slds-button slds-button_icon"
                              title="Align to selected territory"
                              @click=${() => this.handleAssignTerritory(brick.brickId)}
                            >
                              ⊕
                            </button>
                            <button
                              type="button"
                              class="slds-button slds-button_icon"
                              title="Delete brick"
                              @click=${() => this.handleDeleteBrick(brick.brickId)}
                            >
                              ×
                            </button>
                          </div>
                        </article>
                      `
                    )}
                  </div>`
                : html`<div class="empty-state"><p>No bricks for this territory. Create one or load demo data.</p></div>`}
            </section>

            <section class="panel panel-pharmacies">
              <div class="panel-heading">
                <h3>
                  ${this.selectedBrickName ? `Pharmacies — ${this.selectedBrickName}` : 'Pharmacies'}
                </h3>
              </div>
              ${this.selectedBrickId
                ? html`
                    <div class="pharmacy-add-row">
                      <label class="admin-field">
                        <span>Search pharmacies</span>
                        <input
                          type="search"
                          .value=${this.pharmacySearchTerm}
                          @input=${(ev: Event) =>
                            (this.pharmacySearchTerm = (ev.target as HTMLInputElement).value)}
                        />
                      </label>
                      <label class="admin-field">
                        <span>Pharmacy account</span>
                        <select
                          @change=${(ev: Event) =>
                            (this.selectedPharmacyId = (ev.target as HTMLSelectElement).value || null)}
                        >
                          <option value="">Select pharmacy</option>
                          ${this.pharmacyOptions.map(
                            (opt) => html`<option value=${opt.value}>${opt.label}</option>`
                          )}
                        </select>
                      </label>
                      <button
                        type="button"
                        class="slds-button slds-button_brand"
                        ?disabled=${isAddPharmacyDisabled}
                        @click=${this.handleAddPharmacy}
                      >
                        Add to Brick
                      </button>
                    </div>
                    <table class="pharmacy-table">
                      <thead>
                        <tr>
                          <th>Pharmacy</th>
                          <th>Type</th>
                          <th></th>
                        </tr>
                      </thead>
                      <tbody>
                        ${this.pharmacyRows.map(
                          (row) => html`
                            <tr>
                              <td>${row.pharmacyName}</td>
                              <td>${row.pharmacyType ?? '—'}</td>
                              <td>
                                <button
                                  type="button"
                                  class="slds-button slds-button_icon"
                                  title="Remove from brick"
                                  @click=${() => this.handleRemovePharmacy(row.membershipId)}
                                >
                                  ×
                                </button>
                              </td>
                            </tr>
                          `
                        )}
                      </tbody>
                    </table>
                  `
                : html`<div class="empty-state">
                    <p>Select a brick to view and manage linked pharmacy accounts.</p>
                  </div>`}
            </section>
          </div>

          ${this.showBrickModal
            ? html`
                <section class="brick-modal" role="dialog" aria-modal="true">
                  <div class="brick-modal-backdrop" @click=${() => (this.showBrickModal = false)}></div>
                  <div class="brick-modal-panel">
                    <h3 class="manager-title">${this.draftBrick.recordId ? 'Edit Brick' : 'New Brick'}</h3>
                    <div class="brick-form-grid">
                      <label class="admin-field">
                        <span>Brick Name</span>
                        <input
                          .value=${this.draftBrick.name}
                          @input=${(ev: Event) =>
                            (this.draftBrick = {
                              ...this.draftBrick,
                              name: (ev.target as HTMLInputElement).value
                            })}
                        />
                      </label>
                      <label class="admin-field">
                        <span>External ID</span>
                        <input
                          .value=${this.draftBrick.externalId}
                          @input=${(ev: Event) =>
                            (this.draftBrick = {
                              ...this.draftBrick,
                              externalId: (ev.target as HTMLInputElement).value
                            })}
                        />
                      </label>
                      <label class="admin-field">
                        <span>Brick Code (IQVIA)</span>
                        <input
                          .value=${this.draftBrick.brickCode}
                          @input=${(ev: Event) =>
                            (this.draftBrick = {
                              ...this.draftBrick,
                              brickCode: (ev.target as HTMLInputElement).value
                            })}
                        />
                      </label>
                      <label class="admin-field">
                        <span>Data Source</span>
                        <select
                          .value=${this.draftBrick.dataSource}
                          @change=${(ev: Event) =>
                            (this.draftBrick = {
                              ...this.draftBrick,
                              dataSource: (ev.target as HTMLSelectElement).value
                            })}
                        >
                          ${DATA_SOURCE_OPTIONS.map(
                            (opt) => html`<option value=${opt.value}>${opt.label}</option>`
                          )}
                        </select>
                      </label>
                      <label class="admin-field">
                        <span>Governorate</span>
                        <input
                          .value=${this.draftBrick.governorate}
                          @input=${(ev: Event) =>
                            (this.draftBrick = {
                              ...this.draftBrick,
                              governorate: (ev.target as HTMLInputElement).value
                            })}
                        />
                      </label>
                      <label class="admin-field">
                        <span>City / District</span>
                        <input
                          .value=${this.draftBrick.city}
                          @input=${(ev: Event) =>
                            (this.draftBrick = {
                              ...this.draftBrick,
                              city: (ev.target as HTMLInputElement).value
                            })}
                        />
                      </label>
                      <label class="admin-field">
                        <input
                          type="checkbox"
                          .checked=${this.draftBrick.isActive}
                          @change=${(ev: Event) =>
                            (this.draftBrick = {
                              ...this.draftBrick,
                              isActive: (ev.target as HTMLInputElement).checked
                            })}
                        />
                        <span>Active</span>
                      </label>
                    </div>
                    <div class="brick-modal-actions">
                      <button type="button" class="slds-button slds-button_neutral" @click=${() => (this.showBrickModal = false)}>
                        Cancel
                      </button>
                      <button
                        type="button"
                        class="slds-button slds-button_brand"
                        ?disabled=${isSaveBrickDisabled}
                        @click=${this.handleSaveBrick}
                      >
                        Save
                      </button>
                    </div>
                  </div>
                </section>
              `
            : nothing}
        </section>
      </article>
    `;
  }
}

declare global {
  interface HTMLElementTagNameMap {
    'osr-bricks-management-console': OsrBricksManagementConsole;
  }
}

export function renderBricksManagementConsole(ctx: AdminModuleContext): TemplateResult {
  return html`<osr-bricks-management-console .ctx=${ctx}></osr-bricks-management-console>`;
}
