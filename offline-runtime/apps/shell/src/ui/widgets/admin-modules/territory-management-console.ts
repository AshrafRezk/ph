import { LitElement, html, nothing, type TemplateResult } from 'lit';
import { customElement, property, state } from 'lit/decorators.js';
import { adminApex, adminToast, reduceAdminError } from './api';
import type { AdminModuleContext, TerritoryTreeNode } from './types';

const THERAPY_AREA_OPTIONS = [
  { label: 'Diabetes', value: 'Diabetes' },
  { label: 'CHC', value: 'CHC' },
  { label: 'Cardiovascular', value: 'Cardiovascular' },
  { label: 'Gastroenterology', value: 'Gastroenterology' }
];

const ROLE_OPTIONS = [
  { label: 'Medical Rep (mr)', value: 'mr' },
  { label: 'District Manager (dm)', value: 'dm' }
];

const LEVEL_OPTIONS = [
  { label: 'Line (Product Line)', value: 'Line' },
  { label: 'District', value: 'District' },
  { label: 'Medical Rep Territory', value: 'MR' }
];

interface TerritoryAssignment {
  userName: string;
  role?: string;
}

interface AdminTerritoryNode extends TerritoryTreeNode {
  externalId?: string;
  assignments?: TerritoryAssignment[];
  isVacant?: boolean;
  canEdit?: boolean;
  canDelete?: boolean;
  canAddChild?: boolean;
}

interface FlatTerritoryRow {
  key: string;
  id: string;
  name: string;
  externalId?: string;
  level?: string;
  depth: number;
  depthStyle: string;
  hasChildren: boolean;
  expanded: boolean;
  assignmentLabel: string;
  vacantClass: string;
  vacantLabel: string;
  canEdit?: boolean;
  canDelete?: boolean;
  canAddChild?: boolean;
}

interface ProductLineRow {
  id: string;
  name: string;
  externalId?: string;
  therapyArea?: string;
  districtCount?: number;
  repCount?: number;
  productCount?: number;
}

interface AssignableUser {
  id: string;
  name?: string;
  username?: string;
  label?: string;
  title?: string;
  businessUnit?: string;
}

type ActiveTab = 'lines' | 'territories' | 'users';

@customElement('osr-territory-management-console')
export class OsrTerritoryManagementConsole extends LitElement {
  @property({ attribute: false }) ctx!: AdminModuleContext;

  @state() private activeTab: ActiveTab = 'lines';
  @state() private lineRows: ProductLineRow[] = [];
  @state() private treeRoots: AdminTerritoryNode[] = [];
  @state() private flatRows: FlatTerritoryRow[] = [];
  @state() private userRows: AssignableUser[] = [];
  @state() private parentOptions: { label: string; value: string }[] = [];
  @state() private expandedIds = new Set<string>();
  @state() private isSaving = false;
  @state() private showAssignModal = false;
  @state() private showTerritoryModal = false;
  @state() private showLineModal = false;
  @state() private showUserModal = false;
  @state() private assignTerritoryId: string | null = null;
  @state() private assignTerritoryName: string | null = null;
  @state() private selectedUserId: string | null = null;
  @state() private userSearchTerm = '';
  @state() private draftTerritory = {
    recordId: null as string | null,
    name: '',
    externalId: '',
    parentId: null as string | null,
    level: 'District'
  };
  @state() private draftLine = { name: '', code: '', therapyArea: 'Diabetes' };
  @state() private draftUser = {
    firstName: '',
    lastName: '',
    teamCode: '',
    roleKey: 'mr',
    territoryId: null as string | null
  };

  createRenderRoot() {
    return this;
  }

  connectedCallback() {
    super.connectedCallback();
    void this.refreshAll();
  }

  updated(changed: Map<string, unknown>) {
    super.updated(changed);
    if (changed.has('userSearchTerm')) {
      void this.loadUsers();
    }
    if (changed.has('draftTerritory') && this.showTerritoryModal) {
      void this.loadParentOptions();
    }
  }

  private formatAssignments(node: AdminTerritoryNode): string {
    if (!node.assignments?.length) return 'Vacant';
    return node.assignments
      .map((a) => `${a.userName}${a.role ? ` (${a.role})` : ''}`)
      .join(', ');
  }

  private initializeExpanded() {
    if (this.expandedIds.size > 0) return;
    for (const root of this.treeRoots) {
      this.expandedIds.add(root.id);
      if (root.children) {
        for (const child of root.children) {
          this.expandedIds.add(child.id);
        }
      }
    }
    this.expandedIds = new Set(this.expandedIds);
  }

  private rebuildFlatRows() {
    const rows: FlatTerritoryRow[] = [];
    for (const root of this.treeRoots) {
      this.flattenNode(root as AdminTerritoryNode, 0, rows);
    }
    this.flatRows = rows;
  }

  private flattenNode(node: AdminTerritoryNode, depth: number, rows: FlatTerritoryRow[]) {
    const expanded = this.expandedIds.has(node.id);
    rows.push({
      key: node.id,
      id: node.id,
      name: node.name,
      externalId: node.externalId,
      level: node.level,
      depth,
      depthStyle: `padding-left: ${depth * 1.25}rem`,
      hasChildren: !!node.hasChildren,
      expanded,
      assignmentLabel: this.formatAssignments(node),
      vacantClass: node.isVacant ? 'badge badge-vacant' : 'badge badge-assigned',
      vacantLabel: node.isVacant ? 'Vacant' : 'Assigned',
      canEdit: node.canEdit,
      canDelete: node.canDelete,
      canAddChild: node.canAddChild
    });
    if (expanded && node.children) {
      for (const child of node.children) {
        this.flattenNode(child as AdminTerritoryNode, depth + 1, rows);
      }
    }
  }

  private async loadLines() {
    try {
      const data = (await adminApex(this.ctx, 'TerritoryManagementController.getProductLines')) as ProductLineRow[];
      this.lineRows = (data ?? []).map((line) => ({
        ...line,
        therapyLabel: line.therapyArea || 'Unmapped'
      })) as ProductLineRow[];
    } catch (error) {
      adminToast(this.ctx, 'Load failed', reduceAdminError(error), 'error');
      this.lineRows = [];
    }
  }

  private async loadTree() {
    try {
      const data = (await adminApex(this.ctx, 'TerritoryManagementController.getTerritoryTree')) as AdminTerritoryNode[];
      this.treeRoots = data ?? [];
      this.initializeExpanded();
      this.rebuildFlatRows();
    } catch (error) {
      adminToast(this.ctx, 'Load failed', reduceAdminError(error), 'error');
      this.treeRoots = [];
      this.flatRows = [];
    }
  }

  private async loadUsers() {
    try {
      const data = (await adminApex(this.ctx, 'TerritoryManagementController.getAssignableUsers', {
        searchTerm: this.userSearchTerm
      })) as AssignableUser[];
      this.userRows = data ?? [];
    } catch (error) {
      this.userRows = [];
    }
  }

  private async loadParentOptions() {
    try {
      const data = (await adminApex(this.ctx, 'TerritoryManagementController.getParentOptions', {
        childLevel: this.draftTerritory.level
      })) as { label: string; id: string }[];
      this.parentOptions = (data ?? []).map((opt) => ({ label: opt.label, value: opt.id }));
    } catch {
      this.parentOptions = [];
    }
  }

  private async refreshAll() {
    await Promise.all([this.loadLines(), this.loadTree(), this.loadUsers()]);
  }

  private handleToggle(id: string) {
    if (this.expandedIds.has(id)) this.expandedIds.delete(id);
    else this.expandedIds.add(id);
    this.expandedIds = new Set(this.expandedIds);
    this.rebuildFlatRows();
  }

  private async handleConfirmAssign() {
    if (!this.assignTerritoryId || !this.selectedUserId) return;
    this.isSaving = true;
    try {
      const role = (await adminApex(this.ctx, 'TerritoryManagementController.resolveAssignmentRole', {
        userId: this.selectedUserId
      })) as string;
      await adminApex(this.ctx, 'TerritoryManagementController.assignUserToTerritory', {
        territoryId: this.assignTerritoryId,
        userId: this.selectedUserId,
        role
      });
      this.showAssignModal = false;
      await this.refreshAll();
      adminToast(this.ctx, 'User assigned', 'Territory assignment updated.', 'success');
    } catch (error) {
      adminToast(this.ctx, 'Assign failed', reduceAdminError(error), 'error');
    } finally {
      this.isSaving = false;
    }
  }

  private async handleMakeVacant(id: string, name: string) {
    if (!window.confirm(`Remove all user assignments from ${name}?`)) return;
    try {
      await adminApex(this.ctx, 'TerritoryManagementController.clearTerritoryAssignments', { territoryId: id });
      await this.refreshAll();
      adminToast(this.ctx, 'Territory vacant', 'All assignments were removed.', 'success');
    } catch (error) {
      adminToast(this.ctx, 'Update failed', reduceAdminError(error), 'error');
    }
  }

  private async handleSaveTerritory() {
    this.isSaving = true;
    try {
      await adminApex(this.ctx, 'TerritoryManagementController.saveTerritory', { form: this.draftTerritory });
      this.showTerritoryModal = false;
      await this.refreshAll();
      adminToast(this.ctx, 'Territory saved', 'Territory details were updated.', 'success');
    } catch (error) {
      adminToast(this.ctx, 'Save failed', reduceAdminError(error), 'error');
    } finally {
      this.isSaving = false;
    }
  }

  private async handleSaveLine() {
    this.isSaving = true;
    try {
      await adminApex(this.ctx, 'TerritoryManagementController.createProductLine', {
        name: this.draftLine.name,
        code: this.draftLine.code,
        therapyArea: this.draftLine.therapyArea
      });
      if (this.draftLine.therapyArea) {
        await adminApex(this.ctx, 'TerritoryManagementController.syncDefaultLineProductAlignments');
      }
      this.showLineModal = false;
      await this.refreshAll();
      adminToast(
        this.ctx,
        'Line created',
        'Product line and default district/MR territories were created.',
        'success'
      );
    } catch (error) {
      adminToast(this.ctx, 'Create failed', reduceAdminError(error), 'error');
    } finally {
      this.isSaving = false;
    }
  }

  private async handleSaveUser() {
    this.isSaving = true;
    try {
      const result = (await adminApex(this.ctx, 'TerritoryManagementController.createPharmaUser', {
        firstName: this.draftUser.firstName,
        lastName: this.draftUser.lastName,
        teamCode: this.draftUser.teamCode,
        roleKey: this.draftUser.roleKey,
        territoryId: this.draftUser.territoryId,
        roleInTerritory: null
      })) as { message: string };
      this.showUserModal = false;
      await this.refreshAll();
      adminToast(this.ctx, 'User created', result.message, 'success');
    } catch (error) {
      adminToast(this.ctx, 'Create failed', reduceAdminError(error), 'error');
    } finally {
      this.isSaving = false;
    }
  }

  private async handleDeleteTerritory(id: string, name: string) {
    if (!window.confirm(`Delete territory ${name}? This cannot be undone.`)) return;
    try {
      await adminApex(this.ctx, 'TerritoryManagementController.deleteTerritory', { territoryId: id });
      await this.refreshAll();
      adminToast(this.ctx, 'Territory deleted', `${name} was removed.`, 'success');
    } catch (error) {
      adminToast(this.ctx, 'Delete failed', reduceAdminError(error), 'error');
    }
  }

  private get assignUserOptions() {
    return this.userRows.map((user) => ({
      label: user.label || `${user.name} (${user.username})`,
      value: user.id
    }));
  }

  private get userTerritoryOptions() {
    return this.flatRows.map((row) => ({ label: `${row.name} (${row.level})`, value: row.id }));
  }

  render() {
    const isTerritorySaveDisabled =
      this.isSaving ||
      !this.draftTerritory.name ||
      (!this.draftTerritory.recordId && !this.draftTerritory.externalId);
    const isLineSaveDisabled = this.isSaving || !this.draftLine.name || !this.draftLine.code;
    const isUserSaveDisabled =
      this.isSaving ||
      !this.draftUser.firstName ||
      !this.draftUser.lastName ||
      !this.draftUser.teamCode ||
      !this.draftUser.roleKey;
    const isAssignDisabled = this.isSaving || !this.selectedUserId;

    return html`
      <article class="osr-lwc-mirror territory-management-root">
        <section class="territory-console">
          <header class="console-header">
            <p class="console-subtitle">
              Manage Pharma product lines, territory hierarchy, and field force users.
            </p>
          </header>

          <nav class="admin-tabs" aria-label="Territory management tabs">
            ${(['lines', 'territories', 'users'] as ActiveTab[]).map(
              (tab) => html`
                <button
                  type="button"
                  class=${`admin-tab${this.activeTab === tab ? ' admin-tab--active' : ''}`}
                  @click=${() => (this.activeTab = tab)}
                >
                  ${tab === 'lines' ? 'Product Lines' : tab === 'territories' ? 'Territories' : 'Users'}
                </button>
              `
            )}
          </nav>

          ${this.activeTab === 'lines'
            ? html`
                <div class="tab-toolbar">
                  <button
                    type="button"
                    class="slds-button slds-button_brand"
                    @click=${() => {
                      this.draftLine = { name: '', code: '', therapyArea: 'Diabetes' };
                      this.showLineModal = true;
                    }}
                  >
                    Add Product Line
                  </button>
                </div>
                ${this.lineRows.length > 0
                  ? html`<div class="line-grid">
                      ${this.lineRows.map(
                        (line) => html`
                          <article class="line-card">
                            <div>
                              <h3 class="line-name">${line.name}</h3>
                              <span class="line-code">${line.externalId}</span>
                            </div>
                            <p class="line-therapy">${line.therapyArea || 'Unmapped'}</p>
                            <div class="line-stats">
                              <span>${line.districtCount ?? 0} districts</span>
                              <span>${line.repCount ?? 0} reps</span>
                              <span>${line.productCount ?? 0} products</span>
                            </div>
                            <button
                              type="button"
                              class="slds-button slds-button_neutral"
                              @click=${() => {
                                this.draftTerritory = {
                                  recordId: line.id,
                                  name: line.name,
                                  externalId: line.externalId ?? '',
                                  parentId: null,
                                  level: 'Line'
                                };
                                this.showTerritoryModal = true;
                              }}
                            >
                              Edit Line
                            </button>
                          </article>
                        `
                      )}
                    </div>`
                  : html`<div class="empty-state">
                      <p>No product lines found. Run territory seeding or add a new line.</p>
                    </div>`}
              `
            : nothing}

          ${this.activeTab === 'territories'
            ? html`
                <div class="tab-toolbar">
                  <button
                    type="button"
                    class="slds-button slds-button_neutral"
                    @click=${() => {
                      this.draftTerritory = {
                        recordId: null,
                        name: '',
                        externalId: '',
                        parentId: null,
                        level: 'District'
                      };
                      this.showTerritoryModal = true;
                    }}
                  >
                    Add Territory
                  </button>
                </div>
                ${this.flatRows.length > 0
                  ? html`<table class="territory-table">
                      <thead>
                        <tr>
                          <th>Territory</th>
                          <th>Level</th>
                          <th>Assigned User</th>
                          <th>Status</th>
                          <th>Actions</th>
                        </tr>
                      </thead>
                      <tbody>
                        ${this.flatRows.map(
                          (row) => html`
                            <tr>
                              <td>
                                <div class="territory-name-cell" style=${row.depthStyle}>
                                  ${row.hasChildren
                                    ? html`<button
                                        type="button"
                                        class="toggle-btn"
                                        title="Expand or collapse"
                                        @click=${() => this.handleToggle(row.id)}
                                      >
                                        ${row.expanded ? '▼' : '▶'}
                                      </button>`
                                    : html`<span class="toggle-spacer"></span>`}
                                  <div class="territory-labels">
                                    <span class="territory-name">${row.name}</span>
                                    <span class="territory-ext">${row.externalId ?? ''}</span>
                                  </div>
                                </div>
                              </td>
                              <td><span class="level-badge">${row.level}</span></td>
                              <td>${row.assignmentLabel}</td>
                              <td><span class=${row.vacantClass}>${row.vacantLabel}</span></td>
                              <td class="actions">
                                ${row.canEdit
                                  ? html`<button
                                      type="button"
                                      class="slds-button slds-button_neutral"
                                      @click=${() => {
                                        this.draftTerritory = {
                                          recordId: row.id,
                                          name: row.name,
                                          externalId: row.externalId ?? '',
                                          parentId: null,
                                          level: row.level ?? 'District'
                                        };
                                        this.showTerritoryModal = true;
                                      }}
                                    >
                                      Edit
                                    </button>`
                                  : nothing}
                                ${row.canAddChild
                                  ? html`<button
                                      type="button"
                                      class="slds-button slds-button_neutral"
                                      @click=${() => {
                                        const childLevel =
                                          row.level === 'Head Office'
                                            ? 'Line'
                                            : row.level === 'Line'
                                              ? 'District'
                                              : 'MR';
                                        this.draftTerritory = {
                                          recordId: null,
                                          name: '',
                                          externalId: '',
                                          parentId: row.id,
                                          level: childLevel
                                        };
                                        this.showTerritoryModal = true;
                                      }}
                                    >
                                      Add Child
                                    </button>`
                                  : nothing}
                                <button
                                  type="button"
                                  class="slds-button slds-button_neutral"
                                  @click=${() => {
                                    this.assignTerritoryId = row.id;
                                    this.assignTerritoryName = row.name;
                                    this.selectedUserId = null;
                                    this.userSearchTerm = '';
                                    this.showAssignModal = true;
                                  }}
                                >
                                  Assign
                                </button>
                                <button
                                  type="button"
                                  class="slds-button slds-button_neutral"
                                  @click=${() => this.handleMakeVacant(row.id, row.name)}
                                >
                                  Vacant
                                </button>
                                ${row.canDelete
                                  ? html`<button
                                      type="button"
                                      class="slds-button slds-button_destructive"
                                      @click=${() => this.handleDeleteTerritory(row.id, row.name)}
                                    >
                                      Delete
                                    </button>`
                                  : nothing}
                              </td>
                            </tr>
                          `
                        )}
                      </tbody>
                    </table>`
                  : html`<div class="empty-state">
                      <p>No territories found. Run territory seeding to populate the hierarchy.</p>
                    </div>`}
              `
            : nothing}

          ${this.activeTab === 'users'
            ? html`
                <div class="tab-toolbar">
                  <label class="admin-field">
                    <span>Search users</span>
                    <input
                      type="search"
                      .value=${this.userSearchTerm}
                      @input=${(ev: Event) => (this.userSearchTerm = (ev.target as HTMLInputElement).value)}
                    />
                  </label>
                  <button
                    type="button"
                    class="slds-button slds-button_brand"
                    @click=${() => {
                      this.draftUser = {
                        firstName: '',
                        lastName: '',
                        teamCode: '',
                        roleKey: 'mr',
                        territoryId: null
                      };
                      this.showUserModal = true;
                    }}
                  >
                    Create User
                  </button>
                </div>
                ${this.userRows.length > 0
                  ? html`<table class="territory-table">
                      <thead>
                        <tr>
                          <th>Name</th>
                          <th>Username</th>
                          <th>Title</th>
                          <th>Business Unit</th>
                        </tr>
                      </thead>
                      <tbody>
                        ${this.userRows.map(
                          (user) => html`
                            <tr>
                              <td>${user.name}</td>
                              <td>${user.username}</td>
                              <td>${user.title ?? '—'}</td>
                              <td>${user.businessUnit ?? '—'}</td>
                            </tr>
                          `
                        )}
                      </tbody>
                    </table>`
                  : html`<div class="empty-state">
                      <p>No pharma users found. Create a demo user or run territory seeding.</p>
                    </div>`}
              `
            : nothing}

          ${this.showAssignModal
            ? html`
                <section class="admin-modal" role="dialog" aria-modal="true">
                  <div class="admin-modal-backdrop" @click=${() => (this.showAssignModal = false)}></div>
                  <div class="admin-modal-panel">
                    <h3 class="manager-title">Assign User — ${this.assignTerritoryName}</h3>
                    <label class="admin-field">
                      <span>Search users</span>
                      <input
                        type="search"
                        .value=${this.userSearchTerm}
                        @input=${(ev: Event) => (this.userSearchTerm = (ev.target as HTMLInputElement).value)}
                      />
                    </label>
                    <label class="admin-field">
                      <span>User</span>
                      <select
                        @change=${(ev: Event) =>
                          (this.selectedUserId = (ev.target as HTMLSelectElement).value || null)}
                      >
                        <option value="">Select a user</option>
                        ${this.assignUserOptions.map(
                          (opt) => html`<option value=${opt.value}>${opt.label}</option>`
                        )}
                      </select>
                    </label>
                    <div class="modal-actions">
                      <button type="button" class="slds-button slds-button_neutral" @click=${() => (this.showAssignModal = false)}>
                        Cancel
                      </button>
                      <button
                        type="button"
                        class="slds-button slds-button_brand"
                        ?disabled=${isAssignDisabled}
                        @click=${this.handleConfirmAssign}
                      >
                        Assign
                      </button>
                    </div>
                  </div>
                </section>
              `
            : nothing}

          ${this.showTerritoryModal
            ? html`
                <section class="admin-modal" role="dialog" aria-modal="true">
                  <div class="admin-modal-backdrop" @click=${() => (this.showTerritoryModal = false)}></div>
                  <div class="admin-modal-panel">
                    <h3 class="manager-title">
                      ${this.draftTerritory.recordId ? 'Edit Territory' : 'Add Territory'}
                    </h3>
                    <label class="admin-field">
                      <span>Territory Name</span>
                      <input
                        .value=${this.draftTerritory.name}
                        @input=${(ev: Event) =>
                          (this.draftTerritory = {
                            ...this.draftTerritory,
                            name: (ev.target as HTMLInputElement).value
                          })}
                      />
                    </label>
                    <label class="admin-field">
                      <span>External Id</span>
                      <input
                        .value=${this.draftTerritory.externalId}
                        ?disabled=${!!this.draftTerritory.recordId}
                        @input=${(ev: Event) =>
                          (this.draftTerritory = {
                            ...this.draftTerritory,
                            externalId: (ev.target as HTMLInputElement).value
                          })}
                      />
                    </label>
                    ${!this.draftTerritory.recordId
                      ? html`
                          <label class="admin-field">
                            <span>Level</span>
                            <select
                              .value=${this.draftTerritory.level}
                              @change=${(ev: Event) =>
                                (this.draftTerritory = {
                                  ...this.draftTerritory,
                                  level: (ev.target as HTMLSelectElement).value
                                })}
                            >
                              ${LEVEL_OPTIONS.map(
                                (opt) => html`<option value=${opt.value}>${opt.label}</option>`
                              )}
                            </select>
                          </label>
                          <label class="admin-field">
                            <span>Parent Territory</span>
                            <select
                              @change=${(ev: Event) =>
                                (this.draftTerritory = {
                                  ...this.draftTerritory,
                                  parentId: (ev.target as HTMLSelectElement).value || null
                                })}
                            >
                              <option value="">None</option>
                              ${this.parentOptions.map(
                                (opt) => html`<option value=${opt.value}>${opt.label}</option>`
                              )}
                            </select>
                          </label>
                        `
                      : nothing}
                    <div class="modal-actions">
                      <button type="button" class="slds-button slds-button_neutral" @click=${() => (this.showTerritoryModal = false)}>
                        Cancel
                      </button>
                      <button
                        type="button"
                        class="slds-button slds-button_brand"
                        ?disabled=${isTerritorySaveDisabled}
                        @click=${this.handleSaveTerritory}
                      >
                        Save
                      </button>
                    </div>
                  </div>
                </section>
              `
            : nothing}

          ${this.showLineModal
            ? html`
                <section class="admin-modal" role="dialog" aria-modal="true">
                  <div class="admin-modal-backdrop" @click=${() => (this.showLineModal = false)}></div>
                  <div class="admin-modal-panel">
                    <h3 class="manager-title">Add Product Line</h3>
                    <p class="console-subtitle">
                      Creates a line under Head Office plus a default district and MR territory.
                    </p>
                    <label class="admin-field">
                      <span>Line Name</span>
                      <input
                        .value=${this.draftLine.name}
                        @input=${(ev: Event) =>
                          (this.draftLine = { ...this.draftLine, name: (ev.target as HTMLInputElement).value })}
                      />
                    </label>
                    <label class="admin-field">
                      <span>Line Code</span>
                      <input
                        placeholder="e.g. CARDIO"
                        .value=${this.draftLine.code}
                        @input=${(ev: Event) =>
                          (this.draftLine = { ...this.draftLine, code: (ev.target as HTMLInputElement).value })}
                      />
                    </label>
                    <label class="admin-field">
                      <span>Therapy Area</span>
                      <select
                        .value=${this.draftLine.therapyArea}
                        @change=${(ev: Event) =>
                          (this.draftLine = {
                            ...this.draftLine,
                            therapyArea: (ev.target as HTMLSelectElement).value
                          })}
                      >
                        ${THERAPY_AREA_OPTIONS.map(
                          (opt) => html`<option value=${opt.value}>${opt.label}</option>`
                        )}
                      </select>
                    </label>
                    <div class="modal-actions">
                      <button type="button" class="slds-button slds-button_neutral" @click=${() => (this.showLineModal = false)}>
                        Cancel
                      </button>
                      <button
                        type="button"
                        class="slds-button slds-button_brand"
                        ?disabled=${isLineSaveDisabled}
                        @click=${this.handleSaveLine}
                      >
                        Create Line
                      </button>
                    </div>
                  </div>
                </section>
              `
            : nothing}

          ${this.showUserModal
            ? html`
                <section class="admin-modal" role="dialog" aria-modal="true">
                  <div class="admin-modal-backdrop" @click=${() => (this.showUserModal = false)}></div>
                  <div class="admin-modal-panel">
                    <h3 class="manager-title">Create Pharma User</h3>
                    <p class="console-subtitle">
                      Creates a demo user with username pattern team.role@pharma.demo.
                    </p>
                    <div class="form-grid">
                      <label class="admin-field">
                        <span>First Name</span>
                        <input
                          .value=${this.draftUser.firstName}
                          @input=${(ev: Event) =>
                            (this.draftUser = {
                              ...this.draftUser,
                              firstName: (ev.target as HTMLInputElement).value
                            })}
                        />
                      </label>
                      <label class="admin-field">
                        <span>Last Name</span>
                        <input
                          .value=${this.draftUser.lastName}
                          @input=${(ev: Event) =>
                            (this.draftUser = {
                              ...this.draftUser,
                              lastName: (ev.target as HTMLInputElement).value
                            })}
                        />
                      </label>
                    </div>
                    <label class="admin-field">
                      <span>Team Code</span>
                      <input
                        placeholder="e.g. cardio"
                        .value=${this.draftUser.teamCode}
                        @input=${(ev: Event) =>
                          (this.draftUser = {
                            ...this.draftUser,
                            teamCode: (ev.target as HTMLInputElement).value
                          })}
                      />
                    </label>
                    <label class="admin-field">
                      <span>Role</span>
                      <select
                        .value=${this.draftUser.roleKey}
                        @change=${(ev: Event) =>
                          (this.draftUser = {
                            ...this.draftUser,
                            roleKey: (ev.target as HTMLSelectElement).value
                          })}
                      >
                        ${ROLE_OPTIONS.map((opt) => html`<option value=${opt.value}>${opt.label}</option>`)}
                      </select>
                    </label>
                    <label class="admin-field">
                      <span>Assign to Territory (optional)</span>
                      <select
                        @change=${(ev: Event) =>
                          (this.draftUser = {
                            ...this.draftUser,
                            territoryId: (ev.target as HTMLSelectElement).value || null
                          })}
                      >
                        <option value="">None</option>
                        ${this.userTerritoryOptions.map(
                          (opt) => html`<option value=${opt.value}>${opt.label}</option>`
                        )}
                      </select>
                    </label>
                    <div class="modal-actions">
                      <button type="button" class="slds-button slds-button_neutral" @click=${() => (this.showUserModal = false)}>
                        Cancel
                      </button>
                      <button
                        type="button"
                        class="slds-button slds-button_brand"
                        ?disabled=${isUserSaveDisabled}
                        @click=${this.handleSaveUser}
                      >
                        Create User
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
    'osr-territory-management-console': OsrTerritoryManagementConsole;
  }
}

export function renderTerritoryManagementConsole(ctx: AdminModuleContext): TemplateResult {
  return html`<osr-territory-management-console .ctx=${ctx}></osr-territory-management-console>`;
}
