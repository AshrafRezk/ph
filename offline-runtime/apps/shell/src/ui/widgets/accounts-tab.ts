import { html, nothing, type TemplateResult } from 'lit';
import { ref } from 'lit/directives/ref.js';
import type { AccountSummaryDto } from '../apex-cache';
import {
  FILTER_ALL,
  deriveFilterOptions,
  filterPlannerAccounts,
  type PlannerAccountFilters,
  type PlannerCollection
} from '../planner-accounts';
import { createOsrMap, type OsrMapHandle, type OsrMapMarker } from '../map/osr-leaflet';
import { renderAccountKindBadge } from './account-type';

const SCOPE_BOTH = 'both';
const SCOPE_IN = 'in';
const SCOPE_OUT = 'out';
const PAGE_SIZE = 10;
const MAP_PAGE_SIZE = 5;

type Risk = 'High' | 'Med' | 'Low';
type SortBy = 'name' | 'classification' | 'gap' | 'reach';

const ui = {
  search: '',
  scope: SCOPE_BOTH,
  recordType: FILTER_ALL,
  specialty: FILTER_ALL,
  classification: FILTER_ALL,
  sortBy: 'gap' as SortBy,
  sortDir: 'desc' as 'asc' | 'desc',
  viewMode: 'list' as 'list' | 'map',
  page: 1,
  mapPage: 1,
  selectedCollectionId: null as string | null,
  selectedAccountId: null as string | null,
  filtersOpen: false
};

const mapHandles = new WeakMap<Element, OsrMapHandle>();

interface AccountRow extends AccountSummaryDto {
  accountId: string;
  accountName: string;
  inPlan: boolean;
  visitGap: number;
  reachPercent: number;
  paceStatus: string;
  agentforceRisk: Risk;
  planCycleLabel: string;
}

function deriveRisk(a: AccountSummaryDto, gap: number): Risk {
  const freq = String(a.frequencyStatus ?? '').toLowerCase();
  if (freq.includes('critical') || gap >= 3) return 'High';
  if (freq.includes('behind') || freq.includes('at risk') || gap >= 1) return 'Med';
  return 'Low';
}

function toRows(accounts: AccountSummaryDto[]): AccountRow[] {
  return accounts
    .filter((a) => a.id)
    .map((a) => {
      const actual = Number(a.actualVisits ?? 0);
      const target = Number(a.targetVisits ?? 0);
      const visitGap = Math.max(0, target - actual);
      const reachPercent = target > 0 ? Math.round((actual / target) * 100) : 0;
      const inPlan = target > 0;
      const freq = String(a.frequencyStatus ?? '');
      const paceStatus =
        freq ||
        (visitGap >= 3 ? 'Critical' : visitGap >= 1 ? 'Behind' : inPlan ? 'On pace' : '—');
      return {
        ...a,
        accountId: String(a.id),
        accountName: a.name || 'Account',
        inPlan,
        visitGap,
        reachPercent,
        paceStatus,
        agentforceRisk: deriveRisk(a, visitGap),
        planCycleLabel: inPlan ? 'In plan' : 'Out of plan'
      };
    });
}

function applyScope(rows: AccountRow[], scope: string): AccountRow[] {
  if (scope === SCOPE_IN) return rows.filter((r) => r.inPlan);
  if (scope === SCOPE_OUT) return rows.filter((r) => !r.inPlan);
  return rows;
}

function sortRows(rows: AccountRow[], sortBy: SortBy, dir: 'asc' | 'desc'): AccountRow[] {
  const mul = dir === 'asc' ? 1 : -1;
  return [...rows].sort((a, b) => {
    let cmp = 0;
    if (sortBy === 'name') cmp = a.accountName.localeCompare(b.accountName);
    else if (sortBy === 'classification')
      cmp = String(a.classification ?? '').localeCompare(String(b.classification ?? ''));
    else if (sortBy === 'reach') cmp = a.reachPercent - b.reachPercent;
    else cmp = a.visitGap - b.visitGap;
    if (cmp === 0) cmp = a.accountName.localeCompare(b.accountName);
    return cmp * mul;
  });
}

function riskDotClass(risk: Risk): string {
  if (risk === 'High') return 'map-list-risk-high';
  if (risk === 'Med') return 'map-list-risk-med';
  return 'map-list-risk-low';
}

function riskKind(risk: Risk): OsrMapMarker['kind'] {
  if (risk === 'High') return 'risk-high';
  if (risk === 'Med') return 'risk-med';
  return 'risk-low';
}

/**
 * Vite catalog port for c/accountsTab — mirrors Salesforce accountsTab LWC
 * (toolbar filters, My lists, summary KPIs, list datatable, map + risk pins).
 */
export function renderAccountsTab(opts: {
  label: string;
  accounts: AccountSummaryDto[] | null;
  collections?: PlannerCollection[];
  selectedCollectionId?: string | null;
  cached?: boolean;
  onOpenAccount?: (id: string) => void;
  onPlanVisit?: (accountId: string) => void;
  onSelectCollection?: (id: string | null) => void;
  requestUpdate?: () => void;
}): TemplateResult {
  const bump = () => opts.requestUpdate?.();
  const collections = opts.collections ?? [];
  const selectedCollectionId =
    opts.selectedCollectionId !== undefined ? opts.selectedCollectionId : ui.selectedCollectionId;
  const selectedCollection =
    selectedCollectionId != null
      ? collections.find((c) => c.id === selectedCollectionId) ?? null
      : null;

  const filters: PlannerAccountFilters = {
    searchTerm: ui.search,
    recordType: ui.recordType,
    specialty: ui.specialty,
    classification: ui.classification,
    brickId: FILTER_ALL
  };
  const all = opts.accounts ?? [];
  const options = deriveFilterOptions(all);
  const filtered = filterPlannerAccounts(all, filters, selectedCollection);
  let rows = applyScope(toRows(filtered), ui.scope);
  rows = sortRows(rows, ui.sortBy, ui.sortDir);

  const summary = {
    totalCount: toRows(all).length,
    inPlanCount: toRows(all).filter((r) => r.inPlan).length,
    outPlanCount: toRows(all).filter((r) => !r.inPlan).length,
    behindPaceCount: toRows(all).filter((r) => {
      const f = r.paceStatus.toLowerCase();
      return f.includes('behind') || f.includes('critical') || r.visitGap >= 1;
    }).length,
    monthLabel: new Date().toLocaleDateString(undefined, { month: 'long', year: 'numeric' })
  };

  const pageCount = Math.max(1, Math.ceil(rows.length / PAGE_SIZE));
  if (ui.page > pageCount) ui.page = pageCount;
  const pageRows = rows.slice((ui.page - 1) * PAGE_SIZE, ui.page * PAGE_SIZE);
  const rangeStart = rows.length ? (ui.page - 1) * PAGE_SIZE + 1 : 0;
  const rangeEnd = Math.min(ui.page * PAGE_SIZE, rows.length);

  const mapEligible = rows.filter(
    (r) => Number.isFinite(Number(r.latitude)) && Number.isFinite(Number(r.longitude))
  );
  const mapPageCount = Math.max(1, Math.ceil(mapEligible.length / MAP_PAGE_SIZE));
  if (ui.mapPage > mapPageCount) ui.mapPage = mapPageCount;
  const mapPageRows = mapEligible.slice(
    (ui.mapPage - 1) * MAP_PAGE_SIZE,
    ui.mapPage * MAP_PAGE_SIZE
  );
  const mapRangeStart = mapEligible.length ? (ui.mapPage - 1) * MAP_PAGE_SIZE + 1 : 0;
  const mapRangeEnd = Math.min(ui.mapPage * MAP_PAGE_SIZE, mapEligible.length);

  const mountMap = (el: Element | undefined) => {
    if (!(el instanceof HTMLElement) || ui.viewMode !== 'map') return;
    const markers: OsrMapMarker[] = mapEligible.map((r) => ({
      id: r.accountId,
      lat: Number(r.latitude),
      lon: Number(r.longitude),
      label: r.accountName,
      kind: riskKind(r.agentforceRisk),
      selected: r.accountId === ui.selectedAccountId
    }));
    let handle = mapHandles.get(el);
    if (handle && !handle.isAlive()) {
      mapHandles.delete(el);
      handle = undefined;
    }
    if (!handle) {
      handle = createOsrMap(el, {
        markers,
        onMarkerClick: (id) => {
          ui.selectedAccountId = id;
          bump();
        },
        fitBounds: true
      });
      mapHandles.set(el, handle);
    } else {
      handle.setMarkers(markers);
      handle.invalidateSize();
    }
    if (ui.selectedAccountId) handle.flyToId(ui.selectedAccountId);
  };

  const setCollection = (id: string | null) => {
    ui.selectedCollectionId = id;
    ui.page = 1;
    ui.mapPage = 1;
    opts.onSelectCollection?.(id);
    bump();
  };

  return html`
    <div class="osr-lwc-mirror accounts-tab slds-card">
      <div class="accounts-shell">
        <header class="slds-p-vertical_small accounts-card-title" style="display:flex;align-items:center;gap:0.5rem;border-bottom:1px solid #e5e5e5;margin-bottom:0.25rem">
          <h2 class="slds-text-heading_small" style="margin:0;font-weight:700">${opts.label || 'Accounts'}</h2>
          ${opts.cached ? html`<span class="osr-cache-pill">Cached</span>` : nothing}
        </header>

        <div class="accounts-toolbar">
          <div class="accounts-search">
            <input
              type="search"
              placeholder="Search by name, specialty, city…"
              aria-label="Search accounts"
              .value=${ui.search}
              @input=${(e: Event) => {
                ui.search = (e.target as HTMLInputElement).value;
                ui.page = 1;
                ui.mapPage = 1;
                bump();
              }}
            />
          </div>
          <div class="toolbar-filter ${ui.filtersOpen ? 'is-open' : ''}">
            <select
              aria-label="Plan cycle"
              .value=${ui.scope}
              @change=${(e: Event) => {
                ui.scope = (e.target as HTMLSelectElement).value;
                ui.page = 1;
                bump();
              }}
            >
              <option value=${SCOPE_BOTH}>All Accounts</option>
              <option value=${SCOPE_IN}>In Plan Cycle</option>
              <option value=${SCOPE_OUT}>Out of Plan Cycle</option>
            </select>
          </div>
          <div class="toolbar-filter ${ui.filtersOpen ? 'is-open' : ''}">
            <select
              aria-label="Record type"
              .value=${ui.recordType}
              @change=${(e: Event) => {
                ui.recordType = (e.target as HTMLSelectElement).value;
                ui.page = 1;
                bump();
              }}
            >
              <option value=${FILTER_ALL}>All Record Types</option>
              ${options.recordTypes.map((t) => html`<option value=${t.value}>${t.label}</option>`)}
            </select>
          </div>
          <div class="toolbar-filter ${ui.filtersOpen ? 'is-open' : ''}">
            <select
              aria-label="Classification"
              .value=${ui.classification}
              @change=${(e: Event) => {
                ui.classification = (e.target as HTMLSelectElement).value;
                ui.page = 1;
                bump();
              }}
            >
              <option value=${FILTER_ALL}>All Classifications</option>
              ${options.classifications.map(
                (t) => html`<option value=${t.value}>${t.label}</option>`
              )}
            </select>
          </div>
          <div class="toolbar-filter ${ui.filtersOpen ? 'is-open' : ''}">
            <select
              aria-label="Sort by"
              .value=${ui.sortBy}
              @change=${(e: Event) => {
                ui.sortBy = (e.target as HTMLSelectElement).value as SortBy;
                bump();
              }}
            >
              <option value="gap">Visit Gap</option>
              <option value="classification">Classification</option>
              <option value="name">Name</option>
              <option value="reach">Reach %</option>
            </select>
          </div>
          <div class="toolbar-actions">
            <button
              type="button"
              class="slds-button slds-button_neutral"
              title="Filters"
              @click=${() => {
                ui.filtersOpen = !ui.filtersOpen;
                bump();
              }}
            >
              Filters
            </button>
            <button
              type="button"
              class="slds-button ${ui.viewMode === 'list' ? 'slds-button_brand' : 'slds-button_neutral'}"
              @click=${() => {
                ui.viewMode = 'list';
                bump();
              }}
            >
              List View
            </button>
            <button
              type="button"
              class="slds-button ${ui.viewMode === 'map' ? 'slds-button_brand' : 'slds-button_neutral'}"
              @click=${() => {
                ui.viewMode = 'map';
                bump();
              }}
            >
              Map View
            </button>
          </div>
        </div>

        <div class="account-collections">
          <div class="collections-section-title">My lists</div>
          <div class="collection-chips-row">
            <button
              type="button"
              class="collection-chip ${selectedCollectionId == null ? 'collection-chip-active' : ''}"
              @click=${() => setCollection(null)}
            >
              All accounts
            </button>
            ${collections.map(
              (c) => html`
                <button
                  type="button"
                  class="collection-chip ${selectedCollectionId === c.id
                    ? 'collection-chip-active'
                    : ''}"
                  title=${`${c.accountIds.length} accounts`}
                  @click=${() => setCollection(c.id)}
                >
                  ${c.name}
                </button>
              `
            )}
            ${!collections.length
              ? html`<span class="collections-empty-hint"
                  >Create lists in Field Rep Planner</span
                >`
              : nothing}
          </div>
        </div>

        <div class="summary-cards">
          <article class="summary-card">
            <span class="summary-value">${summary.totalCount}</span>
            <span class="summary-label">Total Accounts</span>
          </article>
          <article class="summary-card">
            <span class="summary-value">${summary.inPlanCount}</span>
            <span class="summary-label">In Plan Cycle</span>
          </article>
          <article class="summary-card">
            <span class="summary-value">${summary.outPlanCount}</span>
            <span class="summary-label">Out of Plan Cycle</span>
          </article>
          <article class="summary-card summary-card-warn">
            <span class="summary-value">${summary.behindPaceCount}</span>
            <span class="summary-label">Behind / Critical Pace</span>
          </article>
        </div>

        <p class="list-meta">
          ${rows.length} matching · ${summary.monthLabel}
          ${selectedCollection ? ` · list “${selectedCollection.name}”` : ''}
        </p>

        ${ui.viewMode === 'list'
          ? html`
              ${!all.length
                ? html`<div class="accounts-empty-state">
                    ${opts.cached
                      ? 'No accounts in offline cache for this scope. Sync while online, or check territory assignment.'
                      : 'No accounts available yet. Pull to sync Account records, then reopen Accounts.'}
                  </div>`
                : !rows.length
                  ? html`<div class="accounts-empty-state">
                      No accounts match the current filters.
                    </div>`
                  : html`
                      <div class="accounts-table-wrap">
                        <table class="accounts-data-table">
                          <thead>
                            <tr>
                              <th>Account</th>
                              <th>Class</th>
                              <th>Plan Cycle</th>
                              <th>Target</th>
                              <th>Actual</th>
                              <th>Gap</th>
                              <th>Frequency</th>
                              <th>Reach %</th>
                              <th>Risk</th>
                              <th>Specialty</th>
                              <th>City</th>
                              <th></th>
                            </tr>
                          </thead>
                          <tbody>
                            ${pageRows.map(
                              (r) => html`
                                <tr
                                  @click=${() => opts.onOpenAccount?.(r.accountId)}
                                >
                                  <td>
                                    <span class="acct-name">${r.accountName}</span>
                                    ${r.recordTypeName
                                      ? html`<span class="acct-sub affil-meta-row"
                                          >${renderAccountKindBadge(
                                            {
                                              recordTypeName: r.recordTypeName,
                                              name: r.accountName
                                            },
                                            { label: r.recordTypeName, compact: true }
                                          )}</span
                                        >`
                                      : nothing}
                                  </td>
                                  <td>${r.classification || '—'}</td>
                                  <td>${r.planCycleLabel}</td>
                                  <td>${r.targetVisits ?? 0}</td>
                                  <td>${r.actualVisits ?? 0}</td>
                                  <td>${r.visitGap}</td>
                                  <td
                                    class=${r.paceStatus.toLowerCase().includes('behind') ||
                                    r.paceStatus.toLowerCase().includes('critical')
                                      ? 'pace-behind'
                                      : 'pace-ok'}
                                  >
                                    ${r.paceStatus}
                                  </td>
                                  <td>${r.reachPercent}%</td>
                                  <td>
                                    <span class=${riskDotClass(r.agentforceRisk)}></span>
                                    ${r.agentforceRisk}
                                  </td>
                                  <td>${r.specialty || '—'}</td>
                                  <td>${r.city || '—'}</td>
                                  <td>
                                    ${opts.onPlanVisit
                                      ? html`<button
                                          type="button"
                                          class="slds-button slds-button_brand"
                                          @click=${(e: Event) => {
                                            e.stopPropagation();
                                            opts.onPlanVisit?.(r.accountId);
                                          }}
                                        >
                                          Plan visit
                                        </button>`
                                      : nothing}
                                  </td>
                                </tr>
                              `
                            )}
                          </tbody>
                        </table>
                      </div>
                      <div class="pagination-bar">
                        <span class="pagination-range"
                          >${rangeStart}–${rangeEnd} of ${rows.length}</span
                        >
                        <div class="pagination-controls">
                          <button
                            type="button"
                            class="page-btn"
                            ?disabled=${ui.page <= 1}
                            @click=${() => {
                              ui.page -= 1;
                              bump();
                            }}
                          >
                            Previous
                          </button>
                          <span class="page-label">Page ${ui.page} / ${pageCount}</span>
                          <button
                            type="button"
                            class="page-btn"
                            ?disabled=${ui.page >= pageCount}
                            @click=${() => {
                              ui.page += 1;
                              bump();
                            }}
                          >
                            Next
                          </button>
                        </div>
                      </div>
                    `}
            `
          : html`
              <div class="map-view-layout">
                <aside class="map-account-list">
                  <div class="map-list-header">
                    <span class="map-list-title">Accounts</span>
                    <span class="map-list-count"
                      >${mapEligible.length} geocoded of ${rows.length} matching</span
                    >
                  </div>
                  ${!mapPageRows.length
                    ? html`<p class="map-list-empty" style="padding:1rem;color:#706e6b;text-align:center">
                        No geocoded accounts match the current filters.
                      </p>`
                    : html`
                        <ul class="map-account-items" role="list">
                          ${mapPageRows.map(
                            (r) => html`
                              <li
                                class="map-account-item ${ui.selectedAccountId === r.accountId
                                  ? 'map-account-item-selected'
                                  : ''}"
                                @click=${() => {
                                  ui.selectedAccountId = r.accountId;
                                  bump();
                                }}
                              >
                                <div class="map-account-item-body">
                                  <div class="map-account-item-top">
                                    <span
                                      class=${riskDotClass(r.agentforceRisk)}
                                      title=${r.agentforceRisk}
                                    ></span>
                                    ${renderAccountKindBadge(
                                      {
                                        recordTypeName: r.recordTypeName,
                                        name: r.accountName
                                      },
                                      { label: r.recordTypeName || 'Account', compact: true }
                                    )}
                                    <span class="map-account-badge"
                                      >${r.classification || '—'}</span
                                    >
                                  </div>
                                  <p class="map-account-name">${r.accountName}</p>
                                  <p class="map-account-subtitle">
                                    ${[r.specialty, r.city, r.paceStatus].filter(Boolean).join(' · ')}
                                  </p>
                                </div>
                                <button
                                  type="button"
                                  class="slds-button slds-button_neutral"
                                  title="View account"
                                  @click=${(e: Event) => {
                                    e.stopPropagation();
                                    opts.onOpenAccount?.(r.accountId);
                                  }}
                                >
                                  Open
                                </button>
                              </li>
                            `
                          )}
                        </ul>
                        <div class="map-pagination-bar" style="padding:0.5rem;border-top:1px solid #e5e5e5;background:#fff">
                          <span class="pagination-range"
                            >${mapRangeStart}–${mapRangeEnd} of ${mapEligible.length}</span
                          >
                          <div class="pagination-controls" style="justify-content:center;margin-top:0.35rem">
                            <button
                              type="button"
                              class="page-btn"
                              ?disabled=${ui.mapPage <= 1}
                              @click=${() => {
                                ui.mapPage -= 1;
                                bump();
                              }}
                            >
                              Previous
                            </button>
                            <span class="page-label">Page ${ui.mapPage} / ${mapPageCount}</span>
                            <button
                              type="button"
                              class="page-btn"
                              ?disabled=${ui.mapPage >= mapPageCount}
                              @click=${() => {
                                ui.mapPage += 1;
                                bump();
                              }}
                            >
                              Next
                            </button>
                          </div>
                        </div>
                      `}
                </aside>
                <section class="map-panel">
                  <div class="map-legend">
                    <span class="legend-item"
                      ><span class="legend-pin legend-pin-high"></span> High risk</span
                    >
                    <span class="legend-item"
                      ><span class="legend-pin legend-pin-med"></span> Med risk</span
                    >
                    <span class="legend-item"
                      ><span class="legend-pin legend-pin-low"></span> Low risk</span
                    >
                  </div>
                  <div class="accounts-map" ${ref(mountMap)}></div>
                </section>
              </div>
            `}
      </div>
    </div>
  `;
}
