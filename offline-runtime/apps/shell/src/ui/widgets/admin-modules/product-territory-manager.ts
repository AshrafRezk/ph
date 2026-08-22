import { LitElement, html, nothing, type TemplateResult } from 'lit';
import { customElement, property, state } from 'lit/decorators.js';
import { adminApex, adminToast, reduceAdminError } from './api';
import type { AdminModuleContext, TerritoryTreeNode } from './types';

interface ProductFamilyNode {
  key: string;
  label: string;
  children?: ProductChildNode[];
}

interface ProductChildNode {
  key: string;
  label: string;
  productId: string;
  therapyArea?: string;
  productCode?: string;
  imageUrl?: string;
}

interface ProductFlatRow {
  key: string;
  rowKey: string;
  label: string;
  productId?: string;
  therapyArea?: string;
  depth: number;
  depthStyle: string;
  hasChildren: boolean;
  expanded: boolean;
  isFamily: boolean;
  isSelected: boolean;
  rowClass?: string;
}

interface AlignedTerritoryNode extends TerritoryTreeNode {
  aligned?: boolean;
}

interface TerritoryFlatRow {
  key: string;
  id: string;
  name: string;
  depth: number;
  depthStyle: string;
  hasChildren: boolean;
  expanded: boolean;
  checked: boolean;
}

@customElement('osr-product-territory-manager')
export class OsrProductTerritoryManager extends LitElement {
  @property({ attribute: false }) ctx!: AdminModuleContext;

  @state() private productRoots: ProductFamilyNode[] = [];
  @state() private territoryRoots: AlignedTerritoryNode[] = [];
  @state() private productFlatRows: ProductFlatRow[] = [];
  @state() private territoryFlatRows: TerritoryFlatRow[] = [];
  @state() private productExpandedKeys = new Set<string>();
  @state() private territoryExpandedIds = new Set<string>();
  @state() private selectedProductId: string | null = null;
  @state() private selectedProductLabel = '';
  @state() private selectedTerritoryIds = new Set<string>();
  @state() private productSearchTerm = '';
  @state() private territorySearchTerm = '';
  @state() private cascadeToChildren = true;
  @state() private isLoadingTerritories = false;
  @state() private isSaving = false;
  @state() private hasUnsavedChanges = false;

  createRenderRoot() {
    return this;
  }

  connectedCallback() {
    super.connectedCallback();
    void this.loadProducts();
  }

  private async loadProducts() {
    try {
      const data = (await adminApex(this.ctx, 'ProductCatalogAdminController.getProductCatalogTree')) as ProductFamilyNode[];
      this.productRoots = data ?? [];
      if (this.productExpandedKeys.size === 0) {
        for (const family of this.productRoots) {
          this.productExpandedKeys.add(family.key);
        }
        this.productExpandedKeys = new Set(this.productExpandedKeys);
      }
      this.rebuildProductRows();
    } catch (error) {
      adminToast(this.ctx, 'Product catalog error', reduceAdminError(error), 'error');
      this.productRoots = [];
      this.productFlatRows = [];
    }
  }

  private rebuildProductRows() {
    const term = this.productSearchTerm.trim().toLowerCase();
    const rows: ProductFlatRow[] = [];
    for (const family of this.productRoots) {
      const matchingChildren = (family.children || []).filter((product) => {
        if (!term) return true;
        return (
          (product.label || '').toLowerCase().includes(term) ||
          (product.productCode || '').toLowerCase().includes(term) ||
          (family.label || '').toLowerCase().includes(term)
        );
      });
      if (term && matchingChildren.length === 0 && !(family.label || '').toLowerCase().includes(term)) {
        continue;
      }
      const familyExpanded = term ? true : this.productExpandedKeys.has(family.key);
      rows.push({
        key: family.key,
        rowKey: family.key,
        label: family.label,
        depth: 0,
        depthStyle: 'padding-left: 0.25rem',
        hasChildren: matchingChildren.length > 0,
        expanded: familyExpanded,
        isFamily: true,
        isSelected: false
      });
      if (familyExpanded) {
        for (const product of matchingChildren) {
          const isSelected = product.productId === this.selectedProductId;
          rows.push({
            key: product.key,
            rowKey: product.key,
            label: product.label,
            productId: product.productId,
            therapyArea: product.therapyArea,
            depth: 1,
            depthStyle: 'padding-left: 1.5rem',
            hasChildren: false,
            expanded: false,
            isFamily: false,
            isSelected,
            rowClass: isSelected ? 'tree-row tree-row--selected' : 'tree-row'
          });
        }
      }
    }
    this.productFlatRows = rows;
  }

  private initializeTerritoryExpanded() {
    this.territoryExpandedIds = new Set();
    for (const root of this.territoryRoots) {
      this.territoryExpandedIds.add(root.id);
      if (root.children) {
        for (const child of root.children) {
          this.territoryExpandedIds.add(child.id);
        }
      }
    }
  }

  private rebuildTerritoryRows() {
    const term = this.territorySearchTerm.trim().toLowerCase();
    const rows: TerritoryFlatRow[] = [];
    for (const root of this.territoryRoots) {
      this.flattenTerritoryNode(root, 0, rows, term);
    }
    this.territoryFlatRows = rows;
  }

  private flattenTerritoryNode(
    node: AlignedTerritoryNode,
    depth: number,
    rows: TerritoryFlatRow[],
    term: string
  ) {
    const nameMatches = !term || (node.name || '').toLowerCase().includes(term);
    const childRows: TerritoryFlatRow[] = [];
    if (node.children) {
      for (const child of node.children) {
        this.flattenTerritoryNode(child as AlignedTerritoryNode, depth + 1, childRows, term);
      }
    }
    if (!nameMatches && childRows.length === 0) return;

    const expanded = term ? true : this.territoryExpandedIds.has(node.id);
    rows.push({
      key: node.id,
      id: node.id,
      name: node.name,
      depth,
      depthStyle: `padding-left: ${depth * 1.25}rem`,
      hasChildren: !!node.hasChildren,
      expanded,
      checked: this.selectedTerritoryIds.has(String(node.id))
    });
    if (expanded) rows.push(...childRows);
  }

  private collectAlignedIds(nodes: AlignedTerritoryNode[]): Set<string> {
    const ids = new Set<string>();
    const walk = (nodeList: AlignedTerritoryNode[]) => {
      for (const node of nodeList || []) {
        if (node.aligned) ids.add(String(node.id));
        if (node.children) walk(node.children as AlignedTerritoryNode[]);
      }
    };
    walk(nodes);
    return ids;
  }

  private findTerritoryNode(nodes: AlignedTerritoryNode[], territoryId: string): AlignedTerritoryNode | null {
    for (const node of nodes || []) {
      if (String(node.id) === String(territoryId)) return node;
      const match = this.findTerritoryNode((node.children || []) as AlignedTerritoryNode[], territoryId);
      if (match) return match;
    }
    return null;
  }

  private collectDescendantIds(node: AlignedTerritoryNode): string[] {
    const ids: string[] = [];
    const walk = (current: AlignedTerritoryNode) => {
      ids.push(String(current.id));
      for (const child of current.children || []) {
        walk(child as AlignedTerritoryNode);
      }
    };
    walk(node);
    return ids;
  }

  private async loadTerritoryTree() {
    if (!this.selectedProductId) {
      this.territoryRoots = [];
      this.territoryFlatRows = [];
      this.selectedTerritoryIds = new Set();
      return;
    }
    this.isLoadingTerritories = true;
    try {
      const tree = (await adminApex(this.ctx, 'ProductCatalogAdminController.getTerritoryTreeForProduct', {
        productId: this.selectedProductId
      })) as AlignedTerritoryNode[];
      this.territoryRoots = tree ?? [];
      this.selectedTerritoryIds = this.collectAlignedIds(this.territoryRoots);
      this.initializeTerritoryExpanded();
      this.rebuildTerritoryRows();
    } catch (error) {
      this.territoryRoots = [];
      this.territoryFlatRows = [];
      adminToast(this.ctx, 'Territory load failed', reduceAdminError(error), 'error');
    } finally {
      this.isLoadingTerritories = false;
    }
  }

  private async handleProductSelect(productId: string, productLabel: string) {
    if (!productId || productId === this.selectedProductId) return;
    if (this.hasUnsavedChanges) {
      const confirmed = window.confirm('You have unsaved territory changes. Discard them and switch product?');
      if (!confirmed) return;
    }
    this.selectedProductId = productId;
    this.selectedProductLabel = productLabel;
    this.hasUnsavedChanges = false;
    this.rebuildProductRows();
    await this.loadTerritoryTree();
  }

  private handleTerritoryCheck(territoryId: string, checked: boolean) {
    const node = this.findTerritoryNode(this.territoryRoots, territoryId);
    const targetIds =
      this.cascadeToChildren && node ? this.collectDescendantIds(node) : [String(territoryId)];
    const next = new Set(this.selectedTerritoryIds);
    for (const id of targetIds) {
      if (checked) next.add(id);
      else next.delete(id);
    }
    this.selectedTerritoryIds = next;
    this.hasUnsavedChanges = true;
    this.rebuildTerritoryRows();
  }

  private async handleSave() {
    if (!this.selectedProductId) return;
    this.isSaving = true;
    try {
      const territoryIds = Array.from(this.selectedTerritoryIds);
      await adminApex(this.ctx, 'ProductCatalogAdminController.saveProductTerritoryAlignments', {
        productId: this.selectedProductId,
        territoryIds
      });
      this.hasUnsavedChanges = false;
      await this.loadTerritoryTree();
      adminToast(
        this.ctx,
        'Alignment saved',
        `${territoryIds.length} territor${territoryIds.length === 1 ? 'y' : 'ies'} aligned to ${this.selectedProductLabel}.`,
        'success'
      );
    } catch (error) {
      adminToast(this.ctx, 'Save failed', reduceAdminError(error), 'error');
    } finally {
      this.isSaving = false;
    }
  }

  render() {
    const isSaveDisabled = !this.selectedProductId || this.isSaving || !this.hasUnsavedChanges;

    return html`
      <article class="osr-lwc-mirror product-territory-manager-root">
        <section class="product-territory-manager">
          <header class="manager-header">
            <p class="manager-subtitle">
              Select a product on the left, then align it to territories on the right. Check a parent territory to
              include all child territories when cascade is enabled.
            </p>
          </header>

          <div class="manager-panels">
            <section class="panel panel-products">
              <div class="panel-heading">
                <h3>Product Catalog</h3>
                <input
                  type="search"
                  placeholder="Search products..."
                  .value=${this.productSearchTerm}
                  @input=${(ev: Event) => {
                    this.productSearchTerm = (ev.target as HTMLInputElement).value;
                    this.rebuildProductRows();
                  }}
                />
              </div>
              ${this.productFlatRows.length > 0
                ? html`<ul class="tree-list" role="tree">
                    ${this.productFlatRows.map(
                      (row) => html`
                        <li class=${row.rowClass ?? 'tree-row'} role="treeitem">
                          <div class="tree-row-content" style=${row.depthStyle}>
                            ${row.hasChildren
                              ? html`<button
                                  type="button"
                                  class="toggle-btn"
                                  @click=${() => {
                                    if (this.productExpandedKeys.has(row.key)) {
                                      this.productExpandedKeys.delete(row.key);
                                    } else {
                                      this.productExpandedKeys.add(row.key);
                                    }
                                    this.productExpandedKeys = new Set(this.productExpandedKeys);
                                    this.rebuildProductRows();
                                  }}
                                >
                                  ${row.expanded ? '▼' : '▶'}
                                </button>`
                              : html`<span class="toggle-spacer"></span>`}
                            ${row.isFamily
                              ? html`<span class="family-label">${row.label}</span>`
                              : html`<button
                                  type="button"
                                  class="product-select-btn"
                                  @click=${() =>
                                    row.productId && this.handleProductSelect(row.productId, row.label)}
                                >
                                  <span class="product-text">
                                    <span class="product-name">${row.label}</span>
                                    <span class="product-meta">${row.therapyArea ?? ''}</span>
                                  </span>
                                </button>`}
                          </div>
                        </li>
                      `
                    )}
                  </ul>`
                : html`<div class="empty-state"><p>No Pharma products found. Run the product catalog seed first.</p></div>`}
            </section>

            <section class="panel panel-territories">
              <div class="panel-heading">
                <h3>
                  ${this.selectedProductLabel
                    ? `Territory Distribution — ${this.selectedProductLabel}`
                    : 'Territory Distribution'}
                </h3>
                <input
                  type="search"
                  placeholder="Search territories..."
                  ?disabled=${this.isLoadingTerritories}
                  .value=${this.territorySearchTerm}
                  @input=${(ev: Event) => {
                    this.territorySearchTerm = (ev.target as HTMLInputElement).value;
                    this.rebuildTerritoryRows();
                  }}
                />
              </div>
              ${this.selectedProductId
                ? html`
                    <div class="territory-toolbar">
                      <label class="admin-field">
                        <input
                          type="checkbox"
                          .checked=${this.cascadeToChildren}
                          @change=${(ev: Event) =>
                            (this.cascadeToChildren = (ev.target as HTMLInputElement).checked)}
                        />
                        <span>Cascade to child territories</span>
                      </label>
                      <span class="alignment-count">${this.selectedTerritoryIds.size} selected</span>
                    </div>
                    ${this.isLoadingTerritories
                      ? html`<div class="loading-state">Loading territories…</div>`
                      : this.territoryFlatRows.length > 0
                        ? html`<ul class="tree-list" role="tree">
                            ${this.territoryFlatRows.map(
                              (row) => html`
                                <li class="tree-row" role="treeitem">
                                  <div class="tree-row-content" style=${row.depthStyle}>
                                    ${row.hasChildren
                                      ? html`<button
                                          type="button"
                                          class="toggle-btn"
                                          @click=${() => {
                                            if (this.territoryExpandedIds.has(row.id)) {
                                              this.territoryExpandedIds.delete(row.id);
                                            } else {
                                              this.territoryExpandedIds.add(row.id);
                                            }
                                            this.territoryExpandedIds = new Set(this.territoryExpandedIds);
                                            this.rebuildTerritoryRows();
                                          }}
                                        >
                                          ${row.expanded ? '▼' : '▶'}
                                        </button>`
                                      : html`<span class="toggle-spacer"></span>`}
                                    <input
                                      type="checkbox"
                                      .checked=${row.checked}
                                      @change=${(ev: Event) =>
                                        this.handleTerritoryCheck(
                                          row.id,
                                          (ev.target as HTMLInputElement).checked
                                        )}
                                    />
                                    <span class="territory-name">${row.name}</span>
                                  </div>
                                </li>
                              `
                            )}
                          </ul>`
                        : html`<div class="empty-state">
                            <p>No territories found. Run territory seeding to populate the hierarchy.</p>
                          </div>`}
                  `
                : html`<div class="empty-state"><p>Select a product to view and edit territory alignment.</p></div>`}
            </section>
          </div>

          <footer class="manager-footer">
            <button
              type="button"
              class="slds-button slds-button_brand"
              ?disabled=${isSaveDisabled}
              @click=${this.handleSave}
            >
              Save Alignment
            </button>
          </footer>
        </section>
      </article>
    `;
  }
}

declare global {
  interface HTMLElementTagNameMap {
    'osr-product-territory-manager': OsrProductTerritoryManager;
  }
}

export function renderProductTerritoryManager(ctx: AdminModuleContext): TemplateResult {
  return html`<osr-product-territory-manager .ctx=${ctx}></osr-product-territory-manager>`;
}
