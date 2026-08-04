import { html, nothing, type TemplateResult } from 'lit';
import { ref } from 'lit/directives/ref.js';
import {
  type VisitSummaryDto,
  type PlannerPayloadDto,
  formatVisitTimeRange,
  estimateRouteKm,
  haversineKm
} from '../apex-cache';
import { createOsrMap, pinKindFromRecordType, type OsrMapHandle } from '../map/osr-leaflet';
import { sldsButton } from '../slds/primitives';

const mapHandles = new WeakMap<Element, OsrMapHandle>();
let activeTodayMap: OsrMapHandle | null = null;

export function renderFidelityTodayPlan(opts: {
  label: string;
  payload: PlannerPayloadDto | null;
  viewer?: Record<string, unknown> | null;
  selectedContextUserId?: string | null;
  cached?: boolean;
  selectedVisitId?: string | null;
  onSelectVisit?: (id: string | null) => void;
  onOpenPlanner?: () => void;
  onOpenVisit?: (id: string) => void;
  onOpenAccount?: (id: string) => void;
  onPostpone?: (id: string) => void;
  onRemove?: (id: string) => void;
  onContextUserChange?: (userId: string | null) => void;
}): TemplateResult {
  const visits = [...(opts.payload?.visits ?? [])].sort((a, b) =>
    String(a.startDateTime ?? '').localeCompare(String(b.startDateTime ?? ''))
  );
  const route = estimateRouteKm(visits);
  const todayLabel = new Date().toLocaleDateString(undefined, {
    weekday: 'long',
    month: 'short',
    day: 'numeric'
  });
  const viewer = opts.viewer ?? {};
  const canSwitchView = viewer.canSwitchView === true;
  const defaultUserId = String(viewer.defaultUserId ?? '');
  const selectedUserId = opts.selectedContextUserId || defaultUserId;
  const isViewingSelf = !selectedUserId || selectedUserId === defaultUserId;
  const canMutate = isViewingSelf;
  const options = Array.isArray(viewer.options)
    ? (viewer.options as { userId?: string; label?: string; userName?: string }[])
    : [];
  const selectedLabel =
    options.find((o) => o.userId === selectedUserId)?.label ||
    options.find((o) => o.userId === selectedUserId)?.userName ||
    '';
  const viewingOther =
    canSwitchView && !isViewingSelf
      ? `Viewing ${selectedLabel || 'another rep'}'s plan (read-only)`
      : '';

  const outliers = detectOutliers(visits);
  const selected = opts.selectedVisitId ?? visits[0]?.id ?? null;

  const mountMap = (el: Element | undefined) => {
    if (!(el instanceof HTMLElement)) {
      if (activeTodayMap) {
        activeTodayMap.destroy();
        activeTodayMap = null;
      }
      return;
    }
    const markers = visits
      .filter((v) => Number.isFinite(Number(v.accountLatitude)) && Number.isFinite(Number(v.accountLongitude)))
      .map((v) => ({
        id: String(v.id),
        lat: Number(v.accountLatitude),
        lon: Number(v.accountLongitude),
        label: v.accountName || v.name,
        kind: pinKindFromRecordType(v.accountRecordTypeName, v.accountRecordTypeDeveloperName),
        selected: String(v.id) === String(selected)
      }));
    let handle = mapHandles.get(el);
    if (!handle) {
      handle = createOsrMap(el, {
        markers,
        onMarkerClick: (id) => opts.onSelectVisit?.(id),
        fitBounds: true
      });
      mapHandles.set(el, handle);
    } else {
      handle.setMarkers(markers);
      handle.invalidateSize();
    }
    activeTodayMap = handle;
    if (selected) handle.flyToId(String(selected));
  };

  const googleUrl =
    markersPath(visits).length > 0
      ? `https://www.google.com/maps/dir/${markersPath(visits).join('/')}`
      : '';

  return html`
    <article class="osr-lwc-mirror today-plan-card">
      <header class="today-plan-header">
        <div class="today-plan-heading">
          <h2 class="today-plan-title">
            ${opts.label || "Today’s Plan"}
            ${opts.cached ? html`<span class="osr-cache-pill">Cached</span>` : nothing}
          </h2>
          <p class="today-plan-subtitle">
            ${todayLabel} · ${visits.length} stop${visits.length === 1 ? '' : 's'}
            ${!isViewingSelf && selectedLabel ? ` · ${selectedLabel}` : ''}
          </p>
          ${canSwitchView
            ? html`<select
                class="today-plan-rep-picker slds-select"
                aria-label="View plan for"
                .value=${selectedUserId}
                @change=${(e: Event) => {
                  const v = (e.target as HTMLSelectElement).value;
                  opts.onContextUserChange?.(v || null);
                }}
              >
                <option value=${defaultUserId}>My plan</option>
                ${options.map(
                  (o) =>
                    html`<option value=${o.userId || ''}>
                      ${o.label || o.userName || o.userId}
                    </option>`
                )}
              </select>`
            : nothing}
          ${viewingOther ? html`<div class="viewing-other-banner">${viewingOther}</div>` : nothing}
        </div>
        <div class="today-plan-header-actions">
          ${googleUrl
            ? html`<a class="slds-button slds-button_neutral" href=${googleUrl} target="_blank" rel="noopener"
                >Navigate on Google</a
              >`
            : sldsButton('Navigate on Google', { variant: 'neutral', disabled: true })}
          ${sldsButton('Open Planner', { variant: 'brand', onClick: () => opts.onOpenPlanner?.() })}
        </div>
      </header>

      <div class="today-plan-body">
        ${visits.length === 0
          ? html`
              <div class="home-empty today-plan-empty">
                <div class="home-empty-visual" aria-hidden="true">
                  <div class="today-empty-map">
                    <span class="today-empty-pin today-empty-pin-a"></span>
                    <span class="today-empty-pin today-empty-pin-b"></span>
                    <span class="today-empty-pin today-empty-pin-c"></span>
                    <span class="today-empty-route"></span>
                  </div>
                </div>
                <strong class="home-empty-title">No account visits scheduled for today</strong>
                <p class="home-empty-copy">
                  Build your route in Planner — map stops, optimize travel, and navigate the day.
                </p>
                <button
                  type="button"
                  class="slds-button slds-button_brand home-empty-cta"
                  @click=${() => opts.onOpenPlanner?.()}
                >
                  Plan your day
                </button>
              </div>
            `
          : html`
              <div class="plan-layout">
                <div class="visit-list-col">
                  <div class="sidebar-section-title">Route stops</div>
                  ${outliers.length
                    ? html`
                        <div class="route-outlier-card">
                          <div class="sidebar-section-title">Distant stops</div>
                          <p class="route-outlier-summary">
                            ${outliers.length} stop(s) are far from the rest of today’s route.
                          </p>
                          <ul class="route-outlier-list">
                            ${outliers.map(
                              (o) => html`
                                <li class="route-outlier-item">
                                  <div>
                                    <strong>${o.accountName || o.name}</strong> — ${o.awayKm} km away
                                  </div>
                                  ${canMutate && o.id
                                    ? html`<div class="route-stop-actions">
                                        ${sldsButton('Postpone to tomorrow', {
                                          variant: 'neutral',
                                          onClick: (e) => {
                                            e.stopPropagation();
                                            opts.onPostpone?.(String(o.id));
                                          }
                                        })}
                                        ${sldsButton('Remove visit', {
                                          variant: 'destructive-text',
                                          onClick: (e) => {
                                            e.stopPropagation();
                                            opts.onRemove?.(String(o.id));
                                          }
                                        })}
                                      </div>`
                                    : nothing}
                                </li>
                              `
                            )}
                          </ul>
                        </div>
                      `
                    : nothing}
                  <div class="visit-list">
                    ${visits.map((v, i) =>
                      renderStop(v, i + 1, String(selected) === String(v.id), canMutate, opts, outliers)
                    )}
                  </div>
                </div>
                <div class="map-col">
                  <div class="map-wrapper">
                    <div class="map-container" ${ref(mountMap)}></div>
                  </div>
                  <div class="map-legend">
                    <span class="legend-item"><span class="legend-pin legend-pin-hcp"></span>HCP</span>
                    <span class="legend-item"><span class="legend-pin legend-pin-hco"></span>HCO</span>
                  </div>
                  <div class="route-summary">
                    <span class="route-summary-label">Route estimate</span>
                    <span class="route-summary-value"
                      >${route.km} km · ${route.minutes} min drive</span
                    >
                  </div>
                </div>
              </div>
              ${(() => {
                const ideas = buildOptimizationIdeas(visits, outliers, route);
                const unlinked = visits.filter((v) => !v.accountId).length;
                return html`
                  ${unlinked
                    ? html`<div class="unlinked-note">
                        ${unlinked} visit${unlinked === 1 ? '' : 's'} without an account are hidden
                        from the map route.
                      </div>`
                    : nothing}
                  <div class="ideas-panel">
                    <div class="sidebar-section-title">Optimization ideas</div>
                    ${ideas.length
                      ? html`<ul class="ideas-list">
                          ${ideas.map(
                            (text) => html`
                              <li class="ideas-item">
                                <div class="ideas-content"><span class="ideas-text">${text}</span></div>
                              </li>
                            `
                          )}
                        </ul>`
                      : html`<p class="slds-text-body_small slds-text-color_weak slds-p-around_small">
                          Route looks efficient for today's geocoded stops.
                        </p>`}
                  </div>
                `;
              })()}
            `}
      </div>
    </article>
  `;
}

function renderStop(
  v: VisitSummaryDto,
  index: number,
  selected: boolean,
  canMutate: boolean,
  opts: {
    onSelectVisit?: (id: string | null) => void;
    onOpenVisit?: (id: string) => void;
    onOpenAccount?: (id: string) => void;
    onPostpone?: (id: string) => void;
    onRemove?: (id: string) => void;
  },
  outliers: VisitSummaryDto[]
): TemplateResult {
  const status = String(v.status ?? 'Scheduled');
  const statusKey = status.toLowerCase();
  const kind = pinKindFromRecordType(v.accountRecordTypeName, v.accountRecordTypeDeveloperName);
  const isOutlier = outliers.some((o) => o.id === v.id);
  const stopClass = [
    'route-stop',
    selected ? 'route-stop-selected' : '',
    isOutlier ? 'route-stop-outlier' : ''
  ]
    .filter(Boolean)
    .join(' ');
  const orderClass = [
    'route-stop-order',
    kind === 'hco' ? 'route-stop-order-hco' : 'route-stop-order-hcp',
    isOutlier ? 'route-stop-order-outlier' : ''
  ]
    .filter(Boolean)
    .join(' ');
  const statusClass = `status-pill status-${statusKey}`;

  return html`
    <div
      class=${stopClass}
      role="button"
      tabindex="0"
      @click=${() => v.id && opts.onSelectVisit?.(String(v.id))}
    >
      <span class=${orderClass}>${index}</span>
      <div class="route-stop-body">
        <button
          type="button"
          class="account-name-link"
          @click=${(e: Event) => {
            e.stopPropagation();
            if (v.accountId) opts.onOpenAccount?.(String(v.accountId));
          }}
        >
          ${v.accountName || v.name || 'Visit'}
        </button>
        <div class="route-stop-type">${v.accountRecordTypeName || 'Account'}</div>
        ${v.accountSpecialty
          ? html`<div class="route-stop-specialty">${v.accountSpecialty}</div>`
          : nothing}
        <div class="route-stop-time">${formatVisitTimeRange(v.startDateTime, v.endDateTime)}</div>
        <div class="route-stop-meta">
          <span class=${statusClass}>${status}</span>
          ${isOutlier
            ? html`<span class="outlier-badge" title="Far from other stops">Route outlier</span>`
            : nothing}
          ${!Number.isFinite(Number(v.accountLatitude))
            ? html`<span class="geo-warning">No geocode</span>`
            : nothing}
        </div>
        <div class="route-stop-actions">
          ${sldsButton('View call', {
            variant: 'base',
            onClick: (e) => {
              e.stopPropagation();
              if (v.id) opts.onOpenVisit?.(String(v.id));
            }
          })}
          ${canMutate
            ? html`
                ${sldsButton('Postpone', {
                  variant: 'base',
                  onClick: (e) => {
                    e.stopPropagation();
                    if (v.id) opts.onPostpone?.(String(v.id));
                  }
                })}
                ${sldsButton('Remove', {
                  variant: 'base',
                  onClick: (e) => {
                    e.stopPropagation();
                    if (v.id) opts.onRemove?.(String(v.id));
                  }
                })}
              `
            : nothing}
        </div>
      </div>
    </div>
  `;
}

function markersPath(visits: VisitSummaryDto[]): string[] {
  return visits
    .filter((v) => Number.isFinite(Number(v.accountLatitude)) && Number.isFinite(Number(v.accountLongitude)))
    .map((v) => `${v.accountLatitude},${v.accountLongitude}`);
}

function detectOutliers(visits: VisitSummaryDto[]): (VisitSummaryDto & { awayKm: number })[] {
  const pts = visits.filter(
    (v) => Number.isFinite(Number(v.accountLatitude)) && Number.isFinite(Number(v.accountLongitude))
  );
  if (pts.length < 3) return [];
  const cx = pts.reduce((s, v) => s + Number(v.accountLatitude), 0) / pts.length;
  const cy = pts.reduce((s, v) => s + Number(v.accountLongitude), 0) / pts.length;
  const dists = pts.map((v) => ({
    v,
    d: haversineKm(cx, cy, Number(v.accountLatitude), Number(v.accountLongitude))
  }));
  const mean = dists.reduce((s, x) => s + x.d, 0) / dists.length;
  return dists
    .filter((x) => x.d > mean * 2.2 && x.d > 8)
    .map((x) => ({ ...x.v, awayKm: Math.round(x.d * 10) / 10 }));
}

function nearestNeighborOrder(visits: VisitSummaryDto[]): VisitSummaryDto[] {
  const pts = visits.filter(
    (v) => Number.isFinite(Number(v.accountLatitude)) && Number.isFinite(Number(v.accountLongitude))
  );
  if (pts.length < 2) return pts;
  const remaining = [...pts];
  const ordered: VisitSummaryDto[] = [remaining.shift()!];
  while (remaining.length) {
    const last = ordered[ordered.length - 1];
    let bestIdx = 0;
    let bestD = Infinity;
    for (let i = 0; i < remaining.length; i++) {
      const d = haversineKm(
        Number(last.accountLatitude),
        Number(last.accountLongitude),
        Number(remaining[i].accountLatitude),
        Number(remaining[i].accountLongitude)
      );
      if (d < bestD) {
        bestD = d;
        bestIdx = i;
      }
    }
    ordered.push(remaining.splice(bestIdx, 1)[0]);
  }
  return ordered;
}

function buildOptimizationIdeas(
  visits: VisitSummaryDto[],
  outliers: (VisitSummaryDto & { awayKm: number })[],
  route: { km: number; minutes: number }
): string[] {
  const ideas: string[] = [];
  const geocoded = visits.filter(
    (v) => Number.isFinite(Number(v.accountLatitude)) && Number.isFinite(Number(v.accountLongitude))
  );
  const missingGeo = visits.length - geocoded.length;
  if (!visits.length) {
    ideas.push('Add account visits in Planner to build today’s route.');
    return ideas;
  }
  if (missingGeo > 0) {
    ideas.push(
      `${missingGeo} stop${missingGeo === 1 ? '' : 's'} lack geocode — fix account addresses to improve routing.`
    );
  }
  if (outliers.length) {
    ideas.push(
      `${outliers.length} distant stop${outliers.length === 1 ? '' : 's'} inflate travel — postpone or remove outliers.`
    );
  }
  if (geocoded.length >= 3) {
    const optimized = nearestNeighborOrder(geocoded);
    const optRoute = estimateRouteKm(optimized);
    const savings = Math.round((route.minutes - optRoute.minutes) * 10) / 10;
    if (savings >= 5) {
      ideas.push(
        `Reordering stops could save ~${Math.round(savings)} min (${route.km} → ${optRoute.km} km). Open Planner → Map & Route to apply.`
      );
    } else if (geocoded.length >= 4) {
      ideas.push('Open Planner Map & Route to Build / Optimize the stop order for this day.');
    }
  } else if (geocoded.length > 0 && geocoded.length < 3) {
    ideas.push('Add more geocoded account visits in Planner to see route optimization.');
  }
  if (route.km > 80) {
    ideas.push('Today’s route is long — consider splitting visits across two days.');
  }
  return ideas.slice(0, 4);
}
