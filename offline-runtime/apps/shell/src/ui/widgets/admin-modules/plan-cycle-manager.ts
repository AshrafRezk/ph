import { LitElement, html, nothing, type TemplateResult } from 'lit';
import { customElement, property, state } from 'lit/decorators.js';
import { adminApex, adminToast, reduceAdminError } from './api';
import type { AdminModuleContext } from './types';

const MONTH_NAMES = [
  'January', 'February', 'March', 'April', 'May', 'June',
  'July', 'August', 'September', 'October', 'November', 'December'
];

interface MonthSummary {
  monthNumber: number;
  monthShortLabel: string;
  monthLabel: string;
  isCurrentMonth?: boolean;
  employeesWithPlans: number;
  totalEligibleEmployees: number;
}

interface EmployeeRow {
  employeeId: string;
  employeeName: string;
  territoryName?: string;
  hasPlan: boolean;
  timeCardId?: string;
  targetCount?: number;
}

interface TargetRow {
  id: string;
  accountName: string;
  potentiality?: string;
  targetVisitFrequency: number;
  actualVisits?: number;
  frequencyStatus?: string;
}

type ViewMode = 'year' | 'month' | 'edit';

@customElement('osr-plan-cycle-manager')
export class OsrPlanCycleManager extends LitElement {
  @property({ attribute: false }) ctx!: AdminModuleContext;

  @state() private selectedYear = new Date().getFullYear();
  @state() private selectedMonth: number | null = null;
  @state() private selectedEmployee: string | null = null;
  @state() private selectedTimeCardId: string | null = null;
  @state() private monthSummaries: MonthSummary[] = [];
  @state() private employeeRows: EmployeeRow[] = [];
  @state() private editableTargets: TargetRow[] = [];
  @state() private viewMode: ViewMode = 'year';
  @state() private isSaving = false;
  @state() private isCopying = false;
  @state() private showCopyModal = false;
  @state() private copySourceMonth = '1';
  @state() private copyTargetMonth = '';
  @state() private loading = false;

  createRenderRoot() {
    return this;
  }

  connectedCallback() {
    super.connectedCallback();
    void this.loadSummaries();
  }

  updated(changed: Map<string, unknown>) {
    super.updated(changed);
    if (changed.has('selectedMonth') && this.viewMode === 'month' && this.selectedMonth) {
      void this.loadEmployees();
    }
    if (changed.has('selectedTimeCardId') && this.selectedTimeCardId) {
      void this.loadTargets();
    }
  }

  private get yearOptions() {
    const currentYear = new Date().getFullYear();
    return [currentYear - 1, currentYear, currentYear + 1];
  }

  private get monthOptions() {
    return MONTH_NAMES.map((label, index) => ({ label, value: String(index + 1) }));
  }

  private get monthTiles() {
    return this.monthSummaries.map((month) => ({
      ...month,
      tileClass: `month-tile${month.isCurrentMonth ? ' month-tile--current' : ''}${
        this.selectedMonth === month.monthNumber ? ' month-tile--selected' : ''
      }`,
      coverageLabel: `${month.employeesWithPlans} / ${month.totalEligibleEmployees}`,
      coveragePercent:
        month.totalEligibleEmployees > 0
          ? Math.round((month.employeesWithPlans / month.totalEligibleEmployees) * 100)
          : 0
    }));
  }

  private get employeeTableRows() {
    return this.employeeRows.map((row) => ({
      ...row,
      statusLabel: row.hasPlan ? 'Has plan' : 'No plan',
      statusClass: row.hasPlan ? 'badge badge-plan' : 'badge badge-missing',
      targetLabel: row.hasPlan ? String(row.targetCount ?? 0) : '—',
      territoryLabel: row.territoryName || '—'
    }));
  }

  private get selectedMonthLabel() {
    if (!this.selectedMonth) return '';
    return `${MONTH_NAMES[this.selectedMonth - 1]} ${this.selectedYear}`;
  }

  private get isCopyDisabled() {
    return (
      this.isCopying ||
      !this.copySourceMonth ||
      !this.copyTargetMonth ||
      this.copySourceMonth === this.copyTargetMonth
    );
  }

  private get isSaveDisabled() {
    return this.isSaving || this.editableTargets.length === 0;
  }

  private async loadSummaries() {
    this.loading = true;
    try {
      const data = (await adminApex(this.ctx, 'PlanCycleAdminController.getYearMonthSummaries', {
        year: this.selectedYear
      })) as MonthSummary[];
      this.monthSummaries = data ?? [];
    } catch (error) {
      adminToast(this.ctx, 'Load failed', reduceAdminError(error), 'error');
      this.monthSummaries = [];
    } finally {
      this.loading = false;
    }
  }

  private async loadEmployees() {
    if (!this.selectedMonth) return;
    try {
      const data = (await adminApex(this.ctx, 'PlanCycleAdminController.getEmployeePlansForMonth', {
        year: this.selectedYear,
        month: this.selectedMonth
      })) as EmployeeRow[];
      this.employeeRows = data ?? [];
    } catch (error) {
      adminToast(this.ctx, 'Load failed', reduceAdminError(error), 'error');
      this.employeeRows = [];
    }
  }

  private async loadTargets() {
    if (!this.selectedTimeCardId) {
      this.editableTargets = [];
      return;
    }
    try {
      const data = (await adminApex(this.ctx, 'PlanCycleAdminController.getPlanTargets', {
        timeCardId: this.selectedTimeCardId
      })) as TargetRow[];
      this.editableTargets = (data ?? []).map((row) => ({
        id: row.id,
        accountName: row.accountName,
        potentiality: row.potentiality || '—',
        targetVisitFrequency: row.targetVisitFrequency,
        actualVisits: row.actualVisits ?? 0,
        frequencyStatus: row.frequencyStatus || '—'
      }));
    } catch (error) {
      adminToast(this.ctx, 'Load failed', reduceAdminError(error), 'error');
      this.editableTargets = [];
    }
  }

  private resetToYearView() {
    this.viewMode = 'year';
    this.selectedMonth = null;
    this.selectedEmployee = null;
    this.selectedTimeCardId = null;
    this.employeeRows = [];
    this.editableTargets = [];
  }

  private openEmployeeEditor(employeeId: string, timeCardId: string) {
    const employee = this.employeeRows.find((row) => row.employeeId === employeeId);
    this.selectedEmployee = employee ? employee.employeeName : 'Employee';
    this.selectedTimeCardId = timeCardId;
    this.viewMode = 'edit';
  }

  private handleYearChange(ev: Event) {
    this.selectedYear = Number((ev.target as HTMLSelectElement).value);
    this.resetToYearView();
    void this.loadSummaries();
  }

  private handleMonthTileClick(month: number) {
    this.selectedMonth = month;
    this.viewMode = 'month';
  }

  private handleBackToYear() {
    this.resetToYearView();
  }

  private handleBackToMonth() {
    this.viewMode = 'month';
    this.selectedEmployee = null;
    this.selectedTimeCardId = null;
    this.editableTargets = [];
  }

  private handleOpenCopyModal() {
    this.copySourceMonth = this.selectedMonth ? String(this.selectedMonth) : '1';
    this.copyTargetMonth = '';
    this.showCopyModal = true;
  }

  private async handleCopyPlans() {
    this.isCopying = true;
    try {
      const result = (await adminApex(this.ctx, 'PlanCycleAdminController.copyPlansBetweenMonths', {
        year: this.selectedYear,
        sourceMonth: Number(this.copySourceMonth),
        targetMonth: Number(this.copyTargetMonth),
        employeeIds: null
      })) as { targetsCopied: number; employeesCopied: number };
      adminToast(
        this.ctx,
        'Plans copied',
        `Copied ${result.targetsCopied} account targets for ${result.employeesCopied} employees.`,
        'success'
      );
      this.showCopyModal = false;
      await this.loadSummaries();
      if (this.selectedMonth) await this.loadEmployees();
    } catch (error) {
      adminToast(this.ctx, 'Copy failed', reduceAdminError(error), 'error');
    } finally {
      this.isCopying = false;
    }
  }

  private async handleCreatePlan(employeeId: string) {
    if (!this.selectedMonth) return;
    this.isSaving = true;
    try {
      const timeCardId = (await adminApex(this.ctx, 'PlanCycleAdminController.ensureEmployeePlan', {
        employeeId,
        year: this.selectedYear,
        month: this.selectedMonth
      })) as string;
      adminToast(this.ctx, 'Plan created', 'Monthly plan and account targets were initialized.', 'success');
      await this.loadEmployees();
      this.openEmployeeEditor(employeeId, timeCardId);
    } catch (error) {
      adminToast(this.ctx, 'Create failed', reduceAdminError(error), 'error');
    } finally {
      this.isSaving = false;
    }
  }

  private handleTargetFrequencyChange(id: string, value: number) {
    this.editableTargets = this.editableTargets.map((row) =>
      row.id === id ? { ...row, targetVisitFrequency: value } : row
    );
  }

  private async handleSaveTargets() {
    this.isSaving = true;
    try {
      await adminApex(this.ctx, 'PlanCycleAdminController.savePlanTargets', {
        updates: this.editableTargets.map((row) => ({
          id: row.id,
          targetVisitFrequency: row.targetVisitFrequency
        }))
      });
      adminToast(this.ctx, 'Plan updated', 'Visit targets were saved.', 'success');
      await this.loadTargets();
      await this.loadEmployees();
      await this.loadSummaries();
    } catch (error) {
      adminToast(this.ctx, 'Save failed', reduceAdminError(error), 'error');
    } finally {
      this.isSaving = false;
    }
  }

  render() {
    return html`
      <article class="osr-lwc-mirror plan-cycle-manager-root">
        <section class="plan-cycle-manager">
          <header class="manager-header">
            <div class="manager-intro">
              <h3 class="manager-title">Plan Cycle Manager</h3>
              <p class="manager-subtitle">
                Review monthly employee plans, edit account visit targets, and copy plans between months.
              </p>
            </div>
            <div class="manager-controls">
              <label class="admin-field">
                <span>Year</span>
                <select @change=${this.handleYearChange}>
                  ${this.yearOptions.map(
                    (y) => html`<option value=${y} ?selected=${y === this.selectedYear}>${y}</option>`
                  )}
                </select>
              </label>
              ${this.viewMode === 'month'
                ? html`<button type="button" class="slds-button slds-button_neutral" @click=${this.handleOpenCopyModal}>
                    Copy Plans
                  </button>`
                : nothing}
            </div>
          </header>

          ${this.viewMode === 'year'
            ? html`
                ${this.monthTiles.length > 0
                  ? html`<div class="month-grid">
                      ${this.monthTiles.map(
                        (month) => html`
                          <button
                            type="button"
                            class=${month.tileClass}
                            aria-label=${month.monthLabel}
                            @click=${() => this.handleMonthTileClick(month.monthNumber)}
                          >
                            <div class="month-tile-top">
                              <span class="month-short">${month.monthShortLabel}</span>
                              ${month.isCurrentMonth
                                ? html`<span class="month-current-pill">Current</span>`
                                : nothing}
                            </div>
                            <div class="month-count">${month.employeesWithPlans}</div>
                            <div class="month-meta">
                              <span>${month.coverageLabel} employees</span>
                              <span>${month.coveragePercent}% coverage</span>
                            </div>
                          </button>
                        `
                      )}
                    </div>`
                  : html`<div class="empty-state"><p>No plan cycle data for this year.</p></div>`}
              `
            : nothing}

          ${this.viewMode === 'month'
            ? html`
                <div class="breadcrumb-row">
                  <button type="button" class="slds-button slds-button_neutral" @click=${this.handleBackToYear}>
                    All months
                  </button>
                  <span class="breadcrumb-label">${this.selectedMonthLabel}</span>
                </div>
                ${this.employeeTableRows.length > 0
                  ? html`<table class="manager-table">
                      <thead>
                        <tr>
                          <th>Employee</th>
                          <th>Territory</th>
                          <th>Status</th>
                          <th>Account targets</th>
                          <th>Actions</th>
                        </tr>
                      </thead>
                      <tbody>
                        ${this.employeeTableRows.map(
                          (row) => html`
                            <tr>
                              <td>${row.employeeName}</td>
                              <td>${row.territoryLabel}</td>
                              <td><span class=${row.statusClass}>${row.statusLabel}</span></td>
                              <td>${row.targetLabel}</td>
                              <td class="actions">
                                ${row.hasPlan
                                  ? html`<button
                                      type="button"
                                      class="slds-button slds-button_neutral"
                                      @click=${() =>
                                        row.timeCardId &&
                                        this.openEmployeeEditor(row.employeeId, row.timeCardId)}
                                    >
                                      Edit
                                    </button>`
                                  : html`<button
                                      type="button"
                                      class="slds-button slds-button_neutral"
                                      ?disabled=${this.isSaving}
                                      @click=${() => this.handleCreatePlan(row.employeeId)}
                                    >
                                      Create plan
                                    </button>`}
                              </td>
                            </tr>
                          `
                        )}
                      </tbody>
                    </table>`
                  : html`<div class="empty-state"><p>No territory-assigned employees found.</p></div>`}
              `
            : nothing}

          ${this.viewMode === 'edit'
            ? html`
                <div class="breadcrumb-row">
                  <button type="button" class="slds-button slds-button_neutral" @click=${this.handleBackToMonth}>
                    ${this.selectedMonthLabel}
                  </button>
                  <span class="breadcrumb-label">${this.selectedEmployee}</span>
                </div>
                ${this.editableTargets.length > 0
                  ? html`
                      <table class="manager-table">
                        <thead>
                          <tr>
                            <th>Account</th>
                            <th>Potentiality</th>
                            <th>Target visits</th>
                            <th>Actual visits</th>
                            <th>Status</th>
                          </tr>
                        </thead>
                        <tbody>
                          ${this.editableTargets.map(
                            (row) => html`
                              <tr>
                                <td>${row.accountName}</td>
                                <td>${row.potentiality}</td>
                                <td>
                                  <input
                                    type="number"
                                    min="0"
                                    step="1"
                                    .value=${String(row.targetVisitFrequency)}
                                    @change=${(ev: Event) =>
                                      this.handleTargetFrequencyChange(
                                        row.id,
                                        Number((ev.target as HTMLInputElement).value)
                                      )}
                                  />
                                </td>
                                <td>${row.actualVisits}</td>
                                <td>${row.frequencyStatus}</td>
                              </tr>
                            `
                          )}
                        </tbody>
                      </table>
                      <div class="edit-actions">
                        <button
                          type="button"
                          class="slds-button slds-button_brand"
                          ?disabled=${this.isSaveDisabled}
                          @click=${this.handleSaveTargets}
                        >
                          Save targets
                        </button>
                      </div>
                    `
                  : html`<div class="empty-state"><p>No account targets on this plan yet.</p></div>`}
              `
            : nothing}

          ${this.showCopyModal
            ? html`
                <section class="copy-modal" role="dialog" aria-modal="true" aria-label="Copy plans between months">
                  <div class="copy-modal-backdrop" @click=${() => (this.showCopyModal = false)}></div>
                  <div class="copy-modal-panel">
                    <h3 class="manager-title">Copy plans between months</h3>
                    <p class="manager-subtitle">
                      Copy account visit targets from one month to another for all employees who already have a source
                      plan.
                    </p>
                    <div class="copy-modal-fields">
                      <label class="admin-field">
                        <span>Source month</span>
                        <select
                          .value=${this.copySourceMonth}
                          @change=${(ev: Event) =>
                            (this.copySourceMonth = (ev.target as HTMLSelectElement).value)}
                        >
                          ${this.monthOptions.map(
                            (opt) => html`<option value=${opt.value}>${opt.label}</option>`
                          )}
                        </select>
                      </label>
                      <label class="admin-field">
                        <span>Target month</span>
                        <select
                          .value=${this.copyTargetMonth}
                          @change=${(ev: Event) =>
                            (this.copyTargetMonth = (ev.target as HTMLSelectElement).value)}
                        >
                          <option value="">Select month</option>
                          ${this.monthOptions.map(
                            (opt) => html`<option value=${opt.value}>${opt.label}</option>`
                          )}
                        </select>
                      </label>
                    </div>
                    <div class="copy-modal-actions">
                      <button
                        type="button"
                        class="slds-button slds-button_neutral"
                        @click=${() => (this.showCopyModal = false)}
                      >
                        Cancel
                      </button>
                      <button
                        type="button"
                        class="slds-button slds-button_brand"
                        ?disabled=${this.isCopyDisabled}
                        @click=${this.handleCopyPlans}
                      >
                        Copy plans
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
    'osr-plan-cycle-manager': OsrPlanCycleManager;
  }
}

export function renderPlanCycleManager(ctx: AdminModuleContext): TemplateResult {
  return html`<osr-plan-cycle-manager .ctx=${ctx}></osr-plan-cycle-manager>`;
}
