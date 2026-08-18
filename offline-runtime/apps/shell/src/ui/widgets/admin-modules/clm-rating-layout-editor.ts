import { LitElement, html, nothing, type TemplateResult } from 'lit';
import { customElement, property, state } from 'lit/decorators.js';
import { adminApex, adminToast, reduceAdminError } from './api';
import {
  parseLayoutJson,
  serializeLayout,
  getDefaultLayout,
  getSectionCounts,
  fieldIdentity,
  SECTION_ORDER,
  SECTION_LABELS,
  type LayoutField,
  type LayoutState
} from './rating-layout-utils';
import type { AdminModuleContext } from './types';

interface RatingLayoutRow {
  id: string;
  name: string;
  status: string;
  fieldsJson?: string;
  accountCount?: number;
  territoryCount?: number;
  productCount?: number;
}

interface CatalogField extends LayoutField {
  sectionKey: string;
  identity?: string;
  checked?: boolean;
}

interface DecoratedLayout extends RatingLayoutRow {
  itemClass: string;
  statusClass: string;
  countChips: { key: string; label: string }[];
}

function mergeCatalogOptions(
  layoutField: LayoutField,
  catalogField: CatalogField | undefined
): LayoutField['options'] {
  if (layoutField.options?.length) return layoutField.options;
  return catalogField?.options || [];
}

@customElement('osr-clm-rating-layout-editor')
export class OsrClmRatingLayoutEditor extends LitElement {
  @property({ attribute: false }) ctx!: AdminModuleContext;

  @state() private layouts: DecoratedLayout[] = [];
  @state() private rawLayouts: RatingLayoutRow[] = [];
  @state() private catalog: CatalogField[] = [];
  @state() private selectedLayoutId: string | null = null;
  @state() private selectedLayout: { id?: string; name: string; status: string } | null = null;
  @state() private layoutState: LayoutState = getDefaultLayout();
  @state() private activeSection = 'account';
  @state() private searchTerm = '';

  createRenderRoot() {
    return this;
  }

  connectedCallback() {
    super.connectedCallback();
    void this.loadLayouts();
    void this.loadCatalog();
  }

  private decorateLayoutRow(layout: RatingLayoutRow): DecoratedLayout {
    const counts = getSectionCounts(layout.fieldsJson ?? '');
    return {
      ...layout,
      itemClass:
        layout.id === this.selectedLayoutId ? 'layout-item layout-item-selected' : 'layout-item',
      statusClass: layout.status === 'Deployed' ? 'status-deployed' : 'status-draft',
      countChips: [
        { key: 'account', label: `Account ${counts.accountCount || layout.accountCount || 0}` },
        { key: 'territory', label: `Territory ${counts.territoryCount || layout.territoryCount || 0}` },
        { key: 'product', label: `Product ${counts.productCount || layout.productCount || 0}` }
      ]
    };
  }

  private refreshLayoutListClasses() {
    this.layouts = this.rawLayouts.map((layout) => this.decorateLayoutRow(layout));
  }

  private async loadLayouts() {
    try {
      const data = (await adminApex(this.ctx, 'ClmAdminController.getRatingLayouts')) as RatingLayoutRow[];
      this.rawLayouts = data ?? [];
      this.refreshLayoutListClasses();
    } catch (error) {
      adminToast(this.ctx, 'Load failed', reduceAdminError(error), 'error');
      this.rawLayouts = [];
      this.layouts = [];
    }
  }

  private async loadCatalog() {
    try {
      const data = (await adminApex(this.ctx, 'ClmAdminController.getRatingFieldCatalog')) as CatalogField[];
      this.catalog = data ?? [];
    } catch {
      this.catalog = [];
    }
  }

  private get sectionTabs() {
    return SECTION_ORDER.map((key) => ({
      key,
      label: SECTION_LABELS[key] ?? key,
      className: key === this.activeSection ? 'section-tab section-tab-active' : 'section-tab'
    }));
  }

  private get catalogFields() {
    const term = this.searchTerm.trim().toLowerCase();
    const selectedIds = new Set(
      (this.layoutState.sections[this.activeSection] || []).map((field) => fieldIdentity(field))
    );
    return this.catalog
      .filter((field) => field.sectionKey === this.activeSection)
      .filter((field) => {
        if (!term) return true;
        return (
          field.label.toLowerCase().includes(term) ||
          field.fieldApiName.toLowerCase().includes(term)
        );
      })
      .map((field) => ({
        ...field,
        identity: fieldIdentity(field),
        checked: selectedIds.has(fieldIdentity(field))
      }));
  }

  private get selectedSectionFields() {
    return (this.layoutState.sections[this.activeSection] || [])
      .slice()
      .sort((a, b) => (a.order || 0) - (b.order || 0))
      .map((field, index, list) => ({
        ...field,
        identity: fieldIdentity(field),
        canMoveUp: index > 0,
        canMoveDown: index < list.length - 1
      }));
  }

  private get layoutJson() {
    return serializeLayout(this.layoutState);
  }

  private handleNew() {
    this.selectedLayoutId = null;
    this.selectedLayout = { name: 'New Rating Layout', status: 'Draft' };
    this.layoutState = getDefaultLayout();
    this.activeSection = 'account';
  }

  private handleSelect(layoutId: string) {
    const layout = this.rawLayouts.find((item) => item.id === layoutId);
    if (!layout) return;
    this.selectedLayoutId = layout.id;
    this.selectedLayout = { id: layout.id, name: layout.name, status: layout.status };
    this.layoutState = parseLayoutJson(layout.fieldsJson);
    this.activeSection = 'account';
    this.refreshLayoutListClasses();
  }

  private addFieldIfMissing(
    sectionFields: LayoutField[],
    fieldApiName: string,
    label: string,
    widget: string,
    order: number
  ) {
    const exists = sectionFields.some(
      (field) =>
        field.fieldApiName === fieldApiName && field.objectApiName === 'Account_Territory_Fields__c'
    );
    if (exists) return;
    sectionFields.push({
      objectApiName: 'Account_Territory_Fields__c',
      fieldApiName,
      label,
      widget,
      order
    });
  }

  private addCalculatedIfMissing(
    sectionFields: LayoutField[],
    fieldApiName: string,
    label: string,
    calculatedFrom: string[],
    order: number
  ) {
    const exists = sectionFields.some(
      (field) =>
        field.fieldApiName === fieldApiName && field.objectApiName === 'Account_Territory_Fields__c'
    );
    if (exists) return;
    sectionFields.push({
      objectApiName: 'Account_Territory_Fields__c',
      fieldApiName,
      label,
      widget: 'calculatedBadge',
      calculatedFrom,
      readOnly: true,
      order
    });
  }

  private ensureKolAtfFields(sectionFields: LayoutField[], catalogField: CatalogField) {
    if (this.activeSection !== 'accountTerritory') return;
    if (catalogField.fieldApiName === 'Is_KOL__c') {
      this.addFieldIfMissing(sectionFields, 'KOL_In_What__c', 'KOL Reason', 'picklist', 6);
    }
  }

  private ensureCalculatedAtfFields(sectionFields: LayoutField[], catalogField: CatalogField) {
    if (this.activeSection !== 'accountTerritory') return;
    if (catalogField.fieldApiName === 'Potential__c' || catalogField.fieldApiName === 'Penetration__c') {
      this.addCalculatedIfMissing(
        sectionFields,
        'Matrix_Rating__c',
        'Matrix Rating',
        ['Potential__c', 'Penetration__c'],
        30
      );
      this.addCalculatedIfMissing(
        sectionFields,
        'Classification__c',
        'Classification',
        ['Matrix_Rating__c'],
        40
      );
    }
  }

  private handleCatalogToggle(identity: string, checked: boolean) {
    const catalogField = this.catalog.find((field) => fieldIdentity(field) === identity);
    if (!catalogField) return;
    const sectionFields = [...(this.layoutState.sections[this.activeSection] || [])];
    const existingIndex = sectionFields.findIndex((field) => fieldIdentity(field) === identity);
    if (checked) {
      if (existingIndex >= 0) return;
      sectionFields.push({
        objectApiName: catalogField.objectApiName,
        fieldApiName: catalogField.fieldApiName,
        label: catalogField.label,
        widget: catalogField.widget,
        options: catalogField.options || [],
        readOnly: catalogField.readOnly === true,
        order: (sectionFields.length + 1) * 10
      });
      this.ensureCalculatedAtfFields(sectionFields, catalogField);
      this.ensureKolAtfFields(sectionFields, catalogField);
    } else if (existingIndex >= 0) {
      sectionFields.splice(existingIndex, 1);
    }
    this.layoutState = {
      ...this.layoutState,
      sections: { ...this.layoutState.sections, [this.activeSection]: sectionFields }
    };
  }

  private updateSectionFields(sectionFields: LayoutField[]) {
    const reordered = sectionFields.map((field, index) => ({
      ...field,
      order: (index + 1) * 10,
      options: mergeCatalogOptions(
        field,
        this.catalog.find((item) => fieldIdentity(item) === fieldIdentity(field))
      )
    }));
    this.layoutState = {
      ...this.layoutState,
      sections: { ...this.layoutState.sections, [this.activeSection]: reordered }
    };
  }

  private handleRemoveField(identity: string) {
    const sectionFields = (this.layoutState.sections[this.activeSection] || []).filter(
      (field) => fieldIdentity(field) !== identity
    );
    this.updateSectionFields(sectionFields);
  }

  private handleMoveField(identity: string, direction: 'up' | 'down') {
    const sectionFields = [...(this.layoutState.sections[this.activeSection] || [])];
    const index = sectionFields.findIndex((field) => fieldIdentity(field) === identity);
    if (index < 0) return;
    const targetIndex = direction === 'up' ? index - 1 : index + 1;
    if (targetIndex < 0 || targetIndex >= sectionFields.length) return;
    const [moved] = sectionFields.splice(index, 1);
    sectionFields.splice(targetIndex, 0, moved!);
    this.updateSectionFields(sectionFields);
  }

  private async handleSave() {
    if (!this.selectedLayout) return;
    const counts = getSectionCounts(this.layoutState);
    const total = counts.accountCount + counts.territoryCount + counts.productCount;
    if (total === 0) {
      adminToast(this.ctx, 'Add at least one field', 'Select fields from any rating section.', 'warning');
      return;
    }
    try {
      const saved = (await adminApex(this.ctx, 'ClmAdminController.saveRatingLayout', {
        layout: {
          ...this.selectedLayout,
          fieldsJson: this.layoutJson,
          accountCount: counts.accountCount,
          territoryCount: counts.territoryCount,
          productCount: counts.productCount
        }
      })) as RatingLayoutRow;
      this.selectedLayoutId = saved.id;
      this.selectedLayout = saved;
      this.layoutState = parseLayoutJson(saved.fieldsJson);
      await this.loadLayouts();
      this.refreshLayoutListClasses();
      adminToast(this.ctx, 'Layout saved', saved.name, 'success');
    } catch (error) {
      adminToast(this.ctx, 'Save failed', reduceAdminError(error), 'error');
    }
  }

  private async handleDeploy() {
    if (!this.selectedLayout?.id) {
      await this.handleSave();
    }
    if (!this.selectedLayout?.id) return;
    try {
      await adminApex(this.ctx, 'ClmAdminController.deployRatingLayout', {
        layoutId: this.selectedLayout.id
      });
      this.selectedLayout = { ...this.selectedLayout, status: 'Deployed' };
      await this.loadLayouts();
      this.refreshLayoutListClasses();
      adminToast(this.ctx, 'Layout deployed', 'Field reps will see this form during visits.', 'success');
    } catch (error) {
      adminToast(this.ctx, 'Deploy failed', reduceAdminError(error), 'error');
    }
  }

  render() {
    return html`
      <article class="osr-lwc-mirror clm-rating-layout-editor-root">
        <section class="rating-layout-editor">
          <header class="editor-header">
            <div>
              <h2>Rating Layouts</h2>
              <p>Design account, territory, and product rating forms with a live rep preview.</p>
            </div>
            <button type="button" class="slds-button slds-button_brand" @click=${this.handleNew}>
              New Layout
            </button>
          </header>

          <div class="editor-grid">
            <aside class="layout-list">
              <h3 class="layout-list-title">Layouts</h3>
              ${this.layouts.length > 0
                ? this.layouts.map(
                    (layout) => html`
                      <button
                        type="button"
                        class=${layout.itemClass}
                        @click=${() => this.handleSelect(layout.id)}
                      >
                        <span class="layout-name">${layout.name}</span>
                        <span class=${layout.statusClass}>${layout.status}</span>
                        <span class="layout-counts">
                          ${layout.countChips.map(
                            (chip) => html`<span class="count-chip">${chip.label}</span>`
                          )}
                        </span>
                      </button>
                    `
                  )
                : html`<p class="layout-empty">No layouts yet. Create one to get started.</p>`}
            </aside>

            ${this.selectedLayout
              ? html`
                  <div class="editor-main">
                    <div class="layout-meta">
                      <label class="admin-field">
                        <span>Layout Name</span>
                        <input
                          .value=${this.selectedLayout.name}
                          @input=${(ev: Event) =>
                            (this.selectedLayout = {
                              ...this.selectedLayout!,
                              name: (ev.target as HTMLInputElement).value
                            })}
                        />
                      </label>
                      ${this.selectedLayout.status === 'Deployed'
                        ? html`<span class="deployed-badge">Deployed — active for field reps</span>`
                        : nothing}
                    </div>

                    <div class="editor-split">
                      <section class="picker-pane">
                        <nav class="section-tabs" aria-label="Rating sections">
                          ${this.sectionTabs.map(
                            (tab) => html`
                              <button
                                type="button"
                                class=${tab.className}
                                @click=${() => {
                                  this.activeSection = tab.key;
                                  this.searchTerm = '';
                                }}
                              >
                                ${tab.label}
                              </button>
                            `
                          )}
                        </nav>

                        <input
                          type="search"
                          placeholder="Quick find fields..."
                          .value=${this.searchTerm}
                          @input=${(ev: Event) => (this.searchTerm = (ev.target as HTMLInputElement).value)}
                        />

                        <div class="catalog-list">
                          ${this.catalogFields.map(
                            (field) => html`
                              <label class="catalog-item">
                                <input
                                  type="checkbox"
                                  .checked=${field.checked}
                                  @change=${(ev: Event) =>
                                    this.handleCatalogToggle(
                                      field.identity!,
                                      (ev.target as HTMLInputElement).checked
                                    )}
                                />
                                <span class="catalog-label">${field.label}</span>
                                <span class="catalog-meta">${field.widget}</span>
                              </label>
                            `
                          )}
                        </div>

                        ${this.selectedSectionFields.length > 0
                          ? html`
                              <div class="selected-fields">
                                <h4>Selected Fields</h4>
                                ${this.selectedSectionFields.map(
                                  (field) => html`
                                    <div class="selected-field-row">
                                      <span>${field.label}</span>
                                      <div class="selected-field-actions">
                                        <button
                                          type="button"
                                          class="order-btn"
                                          ?disabled=${!field.canMoveUp}
                                          @click=${() => this.handleMoveField(field.identity!, 'up')}
                                        >
                                          ↑
                                        </button>
                                        <button
                                          type="button"
                                          class="order-btn"
                                          ?disabled=${!field.canMoveDown}
                                          @click=${() => this.handleMoveField(field.identity!, 'down')}
                                        >
                                          ↓
                                        </button>
                                        <button
                                          type="button"
                                          class="remove-btn"
                                          @click=${() => this.handleRemoveField(field.identity!)}
                                        >
                                          ×
                                        </button>
                                      </div>
                                    </div>
                                  `
                                )}
                              </div>
                            `
                          : nothing}
                      </section>

                      <section class="preview-pane">
                        <header>
                          <h3>Layout JSON Preview</h3>
                          <p class="console-subtitle">Serialized layout payload saved to Salesforce</p>
                        </header>
                        <pre class="json-preview">${this.layoutJson}</pre>
                      </section>
                    </div>

                    <footer class="editor-actions">
                      <button type="button" class="slds-button slds-button_neutral" @click=${this.handleSave}>
                        Save Draft
                      </button>
                      <button type="button" class="slds-button slds-button_brand" @click=${this.handleDeploy}>
                        Deploy
                      </button>
                    </footer>
                  </div>
                `
              : html`
                  <article class="layout-placeholder">
                    <h3>Select or create a layout</h3>
                    <p>Choose a layout from the list, or click <strong>New Layout</strong> to begin.</p>
                  </article>
                `}
          </div>
        </section>
      </article>
    `;
  }
}

declare global {
  interface HTMLElementTagNameMap {
    'osr-clm-rating-layout-editor': OsrClmRatingLayoutEditor;
  }
}

export function renderClmRatingLayoutEditor(ctx: AdminModuleContext): TemplateResult {
  return html`<osr-clm-rating-layout-editor .ctx=${ctx}></osr-clm-rating-layout-editor>`;
}
