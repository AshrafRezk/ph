import { LitElement, html, nothing, type TemplateResult } from 'lit';
import { customElement, property, state } from 'lit/decorators.js';
import { adminApex, adminToast, reduceAdminError } from './api';
import type { AdminModuleContext } from './types';

const TABS = [
  { id: 'import', label: 'Import' },
  { id: 'viewer', label: 'Viewer' }
] as const;

type TabId = (typeof TABS)[number]['id'];

interface PreviewRow {
  rowNumber: number;
  dataSource: string;
  reportMonth: string;
  pharmacyExternalId: string;
  productExternalId: string;
  quantityWithdrawn: number;
  isValid: boolean;
  validationMessage?: string;
}

interface ImportResult {
  rowsInserted: number;
  rowsUpdated: number;
  rowsFailed: number;
  errorLog?: string;
}

interface ViewerRow {
  recordId: string;
  reportMonth: string;
  dataSource: string;
  pharmacyName: string;
  brickName: string;
  productName: string;
  quantity: number;
  revenue: number;
}

interface BatchRow {
  batchId: string;
  fileName: string;
  rowsInserted: number;
  rowsUpdated: number;
  rowsFailed: number;
}

function downloadTextFile(fileName: string, content: string): void {
  const blob = new Blob([content], { type: 'text/plain;charset=utf-8' });
  const url = URL.createObjectURL(blob);
  const anchor = document.createElement('a');
  anchor.href = url;
  anchor.download = fileName;
  anchor.click();
  URL.revokeObjectURL(url);
}

function formatCurrency(value: number): string {
  return Number(value || 0).toLocaleString(undefined, {
    style: 'currency',
    currency: 'EGP',
    maximumFractionDigits: 0
  });
}

@customElement('osr-pharmacy-sales-data-admin')
export class OsrPharmacySalesDataAdmin extends LitElement {
  @property({ attribute: false }) ctx!: AdminModuleContext;

  @state() private activeTab: TabId = 'import';
  @state() private csvContent = '';
  @state() private fileName = '';
  @state() private previewRows: PreviewRow[] = [];
  @state() private importResult: ImportResult | null = null;
  @state() private isImporting = false;
  @state() private isPreviewing = false;
  @state() private viewerRows: ViewerRow[] = [];
  @state() private batchRows: BatchRow[] = [];
  @state() private selectedViewerRows = new Set<string>();

  createRenderRoot() {
    return this;
  }

  connectedCallback() {
    super.connectedCallback();
    void this.loadViewerData();
  }

  private get tabs() {
    return TABS.map((tab) => ({
      ...tab,
      className: `tab-btn${this.activeTab === tab.id ? ' tab-btn--active' : ''}`
    }));
  }

  private get isImportTab(): boolean {
    return this.activeTab === 'import';
  }

  private get isViewerTab(): boolean {
    return this.activeTab === 'viewer';
  }

  private get hasPreview(): boolean {
    return this.previewRows.length > 0;
  }

  private get hasImportResult(): boolean {
    return Boolean(this.importResult);
  }

  private handleTabClick(ev: Event) {
    const tabId = (ev.currentTarget as HTMLButtonElement).dataset.tabId as TabId | undefined;
    if (!tabId) return;
    this.activeTab = tabId;
    if (tabId === 'viewer') {
      void this.loadViewerData();
    }
  }

  private async handleDownloadTemplate() {
    try {
      const template = await adminApex(this.ctx, 'PharmacySalesDataAdminController.getCsvTemplate', {});
      downloadTextFile('pharmacy_sales_template.csv', String(template ?? ''));
    } catch (error) {
      adminToast(this.ctx, 'Template error', reduceAdminError(error), 'error');
    }
  }

  private async handleFileChange(ev: Event) {
    const input = ev.target as HTMLInputElement;
    const file = input.files?.[0];
    if (!file) return;
    this.fileName = file.name;
    try {
      this.csvContent = await file.text();
      await this.runPreview();
    } catch (error) {
      adminToast(this.ctx, 'File read error', reduceAdminError(error), 'error');
    }
  }

  private async runPreview() {
    if (!this.csvContent) return;
    this.isPreviewing = true;
    try {
      const result = (await adminApex(this.ctx, 'PharmacySalesDataAdminController.previewSalesDataCsv', {
        csvContent: this.csvContent
      })) as { previewRows?: PreviewRow[] };
      this.previewRows = result?.previewRows ?? [];
      this.importResult = null;
    } catch (error) {
      adminToast(this.ctx, 'Preview error', reduceAdminError(error), 'error');
    } finally {
      this.isPreviewing = false;
    }
  }

  private async handleImport() {
    if (!this.csvContent) {
      adminToast(this.ctx, 'Import', 'Choose a CSV file first.', 'warning');
      return;
    }
    this.isImporting = true;
    try {
      const result = (await adminApex(this.ctx, 'PharmacySalesDataAdminController.importSalesDataCsv', {
        csvContent: this.csvContent,
        fileName: this.fileName
      })) as ImportResult;
      this.importResult = result;
      adminToast(
        this.ctx,
        'Import complete',
        `${result.rowsInserted} inserted, ${result.rowsUpdated} updated, ${result.rowsFailed} failed.`,
        result.rowsFailed > 0 ? 'warning' : 'success'
      );
      await this.loadViewerData();
    } catch (error) {
      adminToast(this.ctx, 'Import error', reduceAdminError(error), 'error');
    } finally {
      this.isImporting = false;
    }
  }

  private async loadViewerData() {
    try {
      const viewerData = await adminApex(this.ctx, 'PharmacySalesDataAdminController.getWithdrawalRows', {
        startMonth: null,
        endMonth: null,
        dataSource: 'All',
        brickId: null,
        rowLimit: 200
      });
      const batchData = await adminApex(this.ctx, 'PharmacySalesDataAdminController.getImportBatches', {
        rowLimit: 20
      });
      this.viewerRows = Array.isArray(viewerData) ? (viewerData as ViewerRow[]) : [];
      this.batchRows = Array.isArray(batchData) ? (batchData as BatchRow[]) : [];
    } catch (error) {
      adminToast(this.ctx, 'Viewer error', reduceAdminError(error), 'error');
    }
  }

  private handleViewerRowToggle(ev: Event) {
    const checkbox = ev.target as HTMLInputElement;
    const recordId = checkbox.dataset.recordId;
    if (!recordId) return;
    const next = new Set(this.selectedViewerRows);
    if (checkbox.checked) next.add(recordId);
    else next.delete(recordId);
    this.selectedViewerRows = next;
  }

  private handleSelectAllViewer(ev: Event) {
    const checkbox = ev.target as HTMLInputElement;
    if (checkbox.checked) {
      this.selectedViewerRows = new Set(this.viewerRows.map((row) => row.recordId));
    } else {
      this.selectedViewerRows = new Set();
    }
  }

  private async handleDeleteSelected() {
    if (!this.selectedViewerRows.size) {
      adminToast(this.ctx, 'Delete', 'Select rows to delete.', 'warning');
      return;
    }
    try {
      await adminApex(this.ctx, 'PharmacySalesDataAdminController.deleteWithdrawalRows', {
        recordIds: [...this.selectedViewerRows]
      });
      this.selectedViewerRows = new Set();
      await this.loadViewerData();
      adminToast(this.ctx, 'Deleted', 'Selected withdrawal rows removed.', 'success');
    } catch (error) {
      adminToast(this.ctx, 'Delete error', reduceAdminError(error), 'error');
    }
  }

  private async handleSeedDemo() {
    try {
      const result = (await adminApex(this.ctx, 'PharmacySalesDataAdminController.seedDemoData', {})) as {
        message?: string;
      };
      adminToast(this.ctx, 'Demo seed', result?.message ?? 'Demo data seeded.', 'success');
      await this.loadViewerData();
    } catch (error) {
      adminToast(this.ctx, 'Seed error', reduceAdminError(error), 'error');
    }
  }

  private handleDownloadErrorLog() {
    if (!this.importResult?.errorLog) return;
    downloadTextFile('import_errors.txt', this.importResult.errorLog);
  }

  render() {
    const allSelected =
      this.viewerRows.length > 0 && this.selectedViewerRows.size === this.viewerRows.length;

    return html`
      <div class="osr-lwc-mirror admin-module">
        <section class="sales-admin">
          <header class="sales-admin-header">
            <div>
              <h2 class="sales-admin-title">Sales Data</h2>
              <p class="sales-admin-subtitle">
                Import IbnSina / Pharmaoverseas CSV files and review loaded sell-out data.
              </p>
            </div>
            <button type="button" class="slds-button slds-button_neutral" @click=${this.handleSeedDemo}>
              Seed Demo Data
            </button>
          </header>

          <nav class="tab-bar" aria-label="Sales data sections">
            ${this.tabs.map(
              (tab) => html`
                <button
                  type="button"
                  class=${tab.className}
                  data-tab-id=${tab.id}
                  @click=${this.handleTabClick}
                >
                  ${tab.label}
                </button>
              `
            )}
          </nav>

          ${this.isImportTab
            ? html`
                <div class="panel">
                  <div class="import-actions">
                    <button
                      type="button"
                      class="slds-button slds-button_neutral"
                      @click=${this.handleDownloadTemplate}
                    >
                      Download CSV Template
                    </button>
                    <div class="filter-field">
                      <label for="sales-csv-upload">Upload CSV</label>
                      <input
                        id="sales-csv-upload"
                        type="file"
                        accept=".csv"
                        @change=${this.handleFileChange}
                      />
                    </div>
                    <button
                      type="button"
                      class="slds-button slds-button_brand"
                      ?disabled=${this.isImporting}
                      @click=${this.handleImport}
                    >
                      ${this.isImporting ? 'Importing…' : 'Import'}
                    </button>
                  </div>

                  ${this.isPreviewing ? html`<p class="empty-copy">Previewing CSV…</p>` : nothing}

                  ${this.hasPreview
                    ? html`
                        <h3 class="section-title">Preview (first rows)</h3>
                        <table class="preview-table">
                          <thead>
                            <tr>
                              <th>#</th>
                              <th>Source</th>
                              <th>Month</th>
                              <th>Pharmacy Ext Id</th>
                              <th>Product Ext Id</th>
                              <th>Qty</th>
                              <th>Status</th>
                            </tr>
                          </thead>
                          <tbody>
                            ${this.previewRows.map(
                              (row) => html`
                                <tr>
                                  <td>${row.rowNumber}</td>
                                  <td>${row.dataSource}</td>
                                  <td>${row.reportMonth}</td>
                                  <td>${row.pharmacyExternalId}</td>
                                  <td>${row.productExternalId}</td>
                                  <td>${row.quantityWithdrawn}</td>
                                  <td>${row.isValid ? 'Valid' : row.validationMessage}</td>
                                </tr>
                              `
                            )}
                          </tbody>
                        </table>
                      `
                    : nothing}

                  ${this.hasImportResult
                    ? html`
                        <div class="import-result">
                          <p>
                            Inserted: ${this.importResult!.rowsInserted} · Updated:
                            ${this.importResult!.rowsUpdated} · Failed: ${this.importResult!.rowsFailed}
                          </p>
                          ${this.importResult!.errorLog
                            ? html`
                                <button
                                  type="button"
                                  class="slds-button slds-button_neutral"
                                  @click=${this.handleDownloadErrorLog}
                                >
                                  Download Error Log
                                </button>
                              `
                            : nothing}
                        </div>
                      `
                    : nothing}
                </div>
              `
            : nothing}

          ${this.isViewerTab
            ? html`
                <div class="panel">
                  <div class="viewer-actions">
                    <button
                      type="button"
                      class="slds-button slds-button_destructive"
                      @click=${this.handleDeleteSelected}
                    >
                      Delete Selected
                    </button>
                    <button
                      type="button"
                      class="slds-button slds-button_neutral"
                      @click=${() => void this.loadViewerData()}
                    >
                      Refresh
                    </button>
                  </div>

                  <table class="manager-table">
                    <thead>
                      <tr>
                        <th>
                          <input
                            type="checkbox"
                            aria-label="Select all rows"
                            .checked=${allSelected}
                            @change=${this.handleSelectAllViewer}
                          />
                        </th>
                        <th>Month</th>
                        <th>Source</th>
                        <th>Pharmacy</th>
                        <th>Brick</th>
                        <th>Product</th>
                        <th>Qty</th>
                        <th>Revenue</th>
                      </tr>
                    </thead>
                    <tbody>
                      ${this.viewerRows.length === 0
                        ? html`
                            <tr>
                              <td colspan="8">No withdrawal rows loaded.</td>
                            </tr>
                          `
                        : this.viewerRows.map(
                            (row) => html`
                              <tr>
                                <td>
                                  <input
                                    type="checkbox"
                                    data-record-id=${row.recordId}
                                    .checked=${this.selectedViewerRows.has(row.recordId)}
                                    @change=${this.handleViewerRowToggle}
                                  />
                                </td>
                                <td>${row.reportMonth}</td>
                                <td>${row.dataSource}</td>
                                <td>${row.pharmacyName}</td>
                                <td>${row.brickName}</td>
                                <td>${row.productName}</td>
                                <td>${row.quantity}</td>
                                <td>${formatCurrency(row.revenue)}</td>
                              </tr>
                            `
                          )}
                    </tbody>
                  </table>

                  <h3 class="section-title">Recent Import Batches</h3>
                  <table class="manager-table">
                    <thead>
                      <tr>
                        <th>File</th>
                        <th>Inserted</th>
                        <th>Updated</th>
                        <th>Failed</th>
                      </tr>
                    </thead>
                    <tbody>
                      ${this.batchRows.length === 0
                        ? html`
                            <tr>
                              <td colspan="4">No import batches yet.</td>
                            </tr>
                          `
                        : this.batchRows.map(
                            (row) => html`
                              <tr>
                                <td>${row.fileName}</td>
                                <td>${row.rowsInserted}</td>
                                <td>${row.rowsUpdated}</td>
                                <td>${row.rowsFailed}</td>
                              </tr>
                            `
                          )}
                    </tbody>
                  </table>
                </div>
              `
            : nothing}
        </section>
      </div>
    `;
  }
}

declare global {
  interface HTMLElementTagNameMap {
    'osr-pharmacy-sales-data-admin': OsrPharmacySalesDataAdmin;
  }
}

export function renderPharmacySalesDataAdmin(ctx: AdminModuleContext): TemplateResult {
  return html`<osr-pharmacy-sales-data-admin .ctx=${ctx}></osr-pharmacy-sales-data-admin>`;
}
