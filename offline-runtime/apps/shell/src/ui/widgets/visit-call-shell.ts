import { html, nothing, type TemplateResult } from 'lit';
import { ref } from 'lit/directives/ref.js';
import type { AccountSummaryDto, ApexCacheSnapshot, VisitSummaryDto } from '../apex-cache';
import { createOsrMap, pinKindFromRecordType, type OsrMapHandle } from '../map/osr-leaflet';
import { renderAccountKindBadge, resolveAccountKind } from './account-type';
import { renderAffiliationNetwork } from './affiliation-network';

const neighbourMaps = new WeakMap<Element, OsrMapHandle>();
let activeNeighbourMap: OsrMapHandle | null = null;

const SECTIONS = [
  { id: 'details', label: 'Details' },
  { id: 'affiliations', label: 'Affiliations' },
  { id: 'attendees', label: 'Attendees' },
  { id: 'products', label: 'Products' },
  { id: 'samples', label: 'Samples' },
  { id: 'presentations', label: 'Presentations' }
] as const;

type SectionId = (typeof SECTIONS)[number]['id'];

type Attendee = {
  accountId: string;
  accountName: string;
  specialty?: string;
  accountTypeLabel?: string;
  isPrimary?: boolean;
};

type ProductDetail = {
  productId: string;
  productName: string;
  detailType: string;
  notes: string;
  topics: string[];
  sentiment: string;
};

type SampleLine = {
  productId: string;
  productName: string;
  quantity: number;
  lot?: string;
  recipientId?: string;
};

type ShellState = {
  section: SectionId;
  status: string;
  objective: string;
  notes: string;
  nextVisitDate: string;
  cancellationReason: string;
  modal: 'none' | 'coaching' | 'medical' | 'whatsapp' | 'reminder';
  attendees: Attendee[];
  selectedProductIds: string[];
  products: ProductDetail[];
  samples: SampleLine[];
  attendeePickerOpen: boolean;
  attendeeQuery: string;
  pharmacyFilter: 'all' | 'pharmacy' | 'nearby';
};

const TOPICS = ['Efficacy', 'Indication', 'Safety', 'Side Effects', 'Usage'] as const;
const DETAIL_TYPES = ['Detail', 'Reprint', 'Reminder'] as const;
const SENTIMENTS = ['Negative', 'Neutral', 'Positive'] as const;

const TERRITORY_PRODUCTS = [
  { id: 'CPI_COLOVERIN_135', name: 'Coloverin 135 mg', family: 'Coloverin' },
  { id: 'CPI_COLOVERIN_D_135_40', name: 'Coloverin D 135/40 mg', family: 'Coloverin' },
  { id: 'CPI_COLOVERIN_SR_200', name: 'Coloverin SR 200 mg', family: 'Coloverin' },
  { id: 'CPI_VERSERC_16', name: 'Verserc 16 mg', family: 'Verserc' },
  { id: 'CPI_DANTRELAX_25', name: 'Dantrelax 25 mg', family: 'Dantrelax' },
  { id: 'CPI_ROSUVAST_10', name: 'Rosuvast 10 mg', family: 'Rosuvast' },
  { id: 'CPI_ALGESAL', name: 'Algesal Suractive Cream', family: 'Algesal' },
  { id: 'CPI_SOULFORT', name: 'Soulfort Capsules', family: 'Soulfort' },
  { id: 'CPI_GENOLIGHT', name: 'Genolight Whitening Cream', family: 'Genolight' }
];

const SAMPLE_PRODUCTS = [
  { id: 'CPI_COLOVERIN_135_S', name: 'Coloverin 135 mg Sample' },
  { id: 'CPI_VERSERC_16_S', name: 'Verserc 16 mg Sample' },
  { id: 'CPI_DANTRELAX_25_S', name: 'Dantrelax 25 mg Sample' },
  { id: 'CPI_ROSUVAST_10_S', name: 'Rosuvast 10 mg Sample' },
  { id: 'CPI_ALGESAL_S', name: 'Algesal Suractive Cream Sample' },
  { id: 'CPI_SOULFORT_S', name: 'Soulfort Capsules Sample' },
  { id: 'CPI_GENOLIGHT_S', name: 'Genolight Whitening Cream Sample' }
];

const shellUi = new Map<string, ShellState>();

function uiFor(visitId: string, visit?: VisitSummaryDto | null): ShellState {
  let state = shellUi.get(visitId);
  if (!state) {
    const primary: Attendee = {
      accountId: String(visit?.accountId || visitId),
      accountName: String(visit?.accountName || 'Account'),
      specialty: visit?.accountSpecialty,
      accountTypeLabel: visit?.accountRecordTypeName || 'Account',
      isPrimary: true
    };
    state = {
      section: 'details',
      status: String(visit?.status || 'Draft'),
      objective: String(visit?.visitObjective || ''),
      notes: '',
      nextVisitDate: '',
      cancellationReason: '',
      modal: 'none',
      attendees: [primary],
      selectedProductIds: [],
      products: [],
      samples: [],
      attendeePickerOpen: false,
      attendeeQuery: '',
      pharmacyFilter: 'all'
    };
    shellUi.set(visitId, state);
  }
  return state;
}

function findVisit(snap: ApexCacheSnapshot | null, visitId: string): VisitSummaryDto | null {
  const pools = [snap?.todayPlan?.visits, snap?.plannerWeek?.visits].filter(Boolean);
  for (const list of pools) {
    const hit = (list as VisitSummaryDto[]).find((v) => String(v.id) === visitId);
    if (hit) return hit;
  }
  return null;
}

function allVisits(snap: ApexCacheSnapshot | null): VisitSummaryDto[] {
  const pools = [snap?.todayPlan?.visits, snap?.plannerWeek?.visits].filter(Boolean) as VisitSummaryDto[][];
  const out: VisitSummaryDto[] = [];
  const seen = new Set<string>();
  for (const list of pools) {
    for (const v of list) {
      const id = String(v.id ?? '');
      if (!id || seen.has(id)) continue;
      seen.add(id);
      out.push(v);
    }
  }
  return out;
}

function formatDateTime(value?: string | null): string {
  if (!value) return '—';
  const d = new Date(value);
  if (Number.isNaN(d.getTime())) return String(value);
  return d.toLocaleString([], {
    weekday: 'short',
    month: 'short',
    day: 'numeric',
    hour: '2-digit',
    minute: '2-digit'
  });
}

function durationLabel(visit: VisitSummaryDto): string {
  if (!visit.startDateTime || !visit.endDateTime) return '—';
  const a = new Date(visit.startDateTime).getTime();
  const b = new Date(visit.endDateTime).getTime();
  if (!Number.isFinite(a) || !Number.isFinite(b) || b <= a) return '—';
  const mins = Math.round((b - a) / 60000);
  return mins >= 60 ? `${Math.floor(mins / 60)}h ${mins % 60}m` : `${mins} min`;
}

function haversineKm(lat1: number, lon1: number, lat2: number, lon2: number): number {
  const toRad = (d: number) => (d * Math.PI) / 180;
  const R = 6371;
  const dLat = toRad(lat2 - lat1);
  const dLon = toRad(lon2 - lon1);
  const a =
    Math.sin(dLat / 2) ** 2 +
    Math.cos(toRad(lat1)) * Math.cos(toRad(lat2)) * Math.sin(dLon / 2) ** 2;
  return R * 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a));
}

function isPharmacyLike(a: AccountSummaryDto): boolean {
  const kind = resolveAccountKind(a);
  return kind === 'pharmacy' || kind === 'hco';
}

function initials(name: string): string {
  return name
    .split(/\s+/)
    .filter(Boolean)
    .slice(0, 2)
    .map((p) => p[0]?.toUpperCase() || '')
    .join('');
}

function presentationRows(snap: ApexCacheSnapshot | null) {
  const raw = (snap?.clmManifest?.presentations ?? []) as {
    id?: string;
    presentationId?: string;
    name?: string;
    title?: string;
    productName?: string;
    formatType?: string;
    slideCount?: number;
  }[];
  if (raw.length) {
    return raw.map((p) => ({
      id: String(p.id ?? p.presentationId ?? ''),
      name: String(p.name ?? p.title ?? 'Presentation'),
      productName: p.productName || '—',
      formatType: p.formatType || 'PDF',
      slideCount: p.slideCount ?? 0
    }));
  }
  return TERRITORY_PRODUCTS.slice(0, 5).map((p) => ({
    id: `demo_${p.id}`,
    name: `${p.family} Core Detail Aid`,
    productName: p.name,
    formatType: 'PDF',
    slideCount: 12,
    demo: true as const
  }));
}

function syncProductSelection(state: ShellState) {
  const selected = new Set(state.selectedProductIds);
  state.products = state.products.filter((p) => selected.has(p.productId));
  for (const id of state.selectedProductIds) {
    if (state.products.some((p) => p.productId === id)) continue;
    const meta = TERRITORY_PRODUCTS.find((p) => p.id === id);
    state.products.push({
      productId: id,
      productName: meta?.name || id,
      detailType: 'Detail',
      notes: '',
      topics: [],
      sentiment: 'Neutral'
    });
  }
}

export function renderVisitCallShell(opts: {
  visitId: string;
  snap: ApexCacheSnapshot | null;
  cached?: boolean;
  onOpenAccount?: (id: string) => void;
  onOpenClm?: () => void;
  onOpenClmPlayer?: (presentationId: string) => void;
  onSave?: (visitId: string, fields: Record<string, unknown>) => void;
  requestUpdate?: () => void;
}): TemplateResult {
  const visit = findVisit(opts.snap, opts.visitId);
  const state = uiFor(opts.visitId, visit);
  const bump = () => opts.requestUpdate?.();
  const accounts = opts.snap?.plannerAccounts?.accounts ?? [];

  if (!visit) {
    return html`
      <div class="osr-lwc-mirror visit-call-shell slds-card slds-p-around_medium">
        <h2 class="slds-text-heading_medium">Visit Call Report</h2>
        <p class="slds-text-color_weak">
          Visit ${opts.visitId} is not in the offline planner cache yet. Open after sync, or edit from the record form.
        </p>
      </div>
    `;
  }

  const locked = ['Completed', 'Cancelled'].includes(String(visit.status || ''));
  const rt = String(visit.accountRecordTypeName || visit.accountRecordTypeDeveloperName || 'Account');
  const statusKey = String(state.status || visit.status || 'Draft').toLowerCase();

  const lat = Number(visit.accountLatitude);
  const lon = Number(visit.accountLongitude);
  const hasGeo = Number.isFinite(lat) && Number.isFinite(lon);

  const neighbors = accounts
    .filter((a) => a.id && String(a.id) !== String(visit.accountId))
    .map((a) => {
      const alat = Number(a.latitude);
      const alon = Number(a.longitude);
      const dist =
        hasGeo && Number.isFinite(alat) && Number.isFinite(alon)
          ? haversineKm(lat, lon, alat, alon)
          : a.city && visit.accountCity && a.city === visit.accountCity
            ? 2.5
            : 99;
      return { account: a, km: dist, pharmacy: isPharmacyLike(a) };
    })
    .filter((n) => n.km <= 8 || n.pharmacy)
    .sort((a, b) => a.km - b.km);

  const filteredNeighbors = neighbors.filter((n) => {
    if (state.pharmacyFilter === 'pharmacy') return n.pharmacy;
    if (state.pharmacyFilter === 'nearby') return n.km <= 3;
    return true;
  });

  const history = allVisits(opts.snap)
    .filter((v) => String(v.id) !== opts.visitId && String(v.accountId) === String(visit.accountId))
    .sort((a, b) => String(b.startDateTime ?? '').localeCompare(String(a.startDateTime ?? '')));

  const territoryHistory = allVisits(opts.snap)
    .filter(
      (v) =>
        String(v.id) !== opts.visitId &&
        String(v.accountId) !== String(visit.accountId) &&
        ((visit.accountCity && v.accountCity === visit.accountCity) ||
          (visit.accountSpecialty && v.accountSpecialty === visit.accountSpecialty))
    )
    .sort((a, b) => String(b.startDateTime ?? '').localeCompare(String(a.startDateTime ?? '')))
    .slice(0, 5);

  const attendeeIds = new Set(state.attendees.map((a) => a.accountId));
  const attendeeCandidates = accounts
    .filter((a) => a.id && !attendeeIds.has(String(a.id)))
    .filter((a) => {
      const q = state.attendeeQuery.trim().toLowerCase();
      if (!q) return true;
      return `${a.name || ''} ${a.specialty || ''} ${a.city || ''}`.toLowerCase().includes(q);
    })
    .slice(0, 20);

  const presentations = presentationRows(opts.snap);

  const savePayload = () =>
    opts.onSave?.(opts.visitId, {
      Status__c: state.status,
      Cancellation_Reason__c: state.cancellationReason || null,
      Visit_Objective__c: state.objective || null,
      Visit_Notes__c: state.notes || null,
      Next_Visit_Date__c: state.nextVisitDate || null,
      _attendees: state.attendees,
      _products: state.products,
      _samples: state.samples
    });

  return html`
    <div class="osr-lwc-mirror visit-call-shell">
      ${opts.cached
        ? html`<div class="slds-notify slds-notify_alert slds-theme_info slds-m-around_x-small">
            Showing cached visit from device
          </div>`
        : nothing}

      <section class="visit-hero">
        <div class="visit-hero-top">
          ${renderAccountKindBadge(visit, { label: rt, compact: true })}
          <span class="status-badge status-badge-${statusKey}">${state.status || visit.status || 'Draft'}</span>
        </div>
        <h1 class="visit-account-name">${visit.accountName || visit.name || 'Visit'}</h1>
        <p class="visit-account-meta">
          ${[visit.accountSpecialty, visit.accountCity].filter(Boolean).join(' · ') || 'No specialty / city on file'}
        </p>
        <div class="visit-hero-actions">
          ${visit.accountId
            ? html`<button
                type="button"
                class="slds-button slds-button_neutral"
                @click=${() => opts.onOpenAccount?.(String(visit.accountId))}
              >
                View Account
              </button>`
            : nothing}
          <button
            type="button"
            class="slds-button slds-button_neutral"
            @click=${() => {
              state.modal = 'coaching';
              bump();
            }}
          >
            Coaching
          </button>
          <button
            type="button"
            class="slds-button slds-button_neutral"
            @click=${() => {
              state.modal = 'medical';
              bump();
            }}
          >
            Medical Inquiry
          </button>
          <button
            type="button"
            class="slds-button slds-button_neutral"
            @click=${() => {
              state.modal = 'whatsapp';
              bump();
            }}
          >
            Send products survey on WhatsApp
          </button>
          <button
            type="button"
            class="slds-button slds-button_neutral"
            @click=${() => {
              state.modal = 'reminder';
              bump();
            }}
          >
            Message meeting reminder
          </button>
        </div>
      </section>

      <div class="shell-layout">
        <nav class="shell-nav" aria-label="Call report sections">
          ${SECTIONS.map(
            (s) => html`
              <button
                type="button"
                class="nav-item ${state.section === s.id ? 'nav-item-active' : ''}"
                @click=${() => {
                  state.section = s.id;
                  bump();
                }}
              >
                ${s.label}
              </button>
            `
          )}
        </nav>

        <main class="shell-content">
          ${state.section === 'details'
            ? html`<article class="visit-panel">
                <h2 class="visit-panel-title">Visit Details</h2>
                <dl class="visit-detail-list">
                  <div class="visit-detail-row">
                    <dt>Visit</dt>
                    <dd>${visit.name || visit.id}</dd>
                  </div>
                  <div class="visit-detail-row">
                    <dt>Start</dt>
                    <dd>${formatDateTime(visit.startDateTime)}</dd>
                  </div>
                  <div class="visit-detail-row">
                    <dt>End</dt>
                    <dd>${formatDateTime(visit.endDateTime)}</dd>
                  </div>
                  <div class="visit-detail-row">
                    <dt>Duration</dt>
                    <dd>${durationLabel(visit)}</dd>
                  </div>
                  <div class="visit-detail-row">
                    <dt>Visit Type</dt>
                    <dd>${visit.visitType || '—'}</dd>
                  </div>
                </dl>
                <div class="osr-form-grid">
                  <div class="slds-form-element">
                    <label class="slds-form-element__label" for="visit-status">Status</label>
                    <select
                      id="visit-status"
                      class="slds-select"
                      ?disabled=${locked}
                      .value=${state.status}
                      @change=${(e: Event) => {
                        state.status = (e.target as HTMLSelectElement).value;
                        bump();
                      }}
                    >
                      <option value="Draft">Draft</option>
                      <option value="Scheduled">Scheduled</option>
                      <option value="Completed">Completed</option>
                      <option value="Cancelled">Cancelled</option>
                    </select>
                  </div>
                  ${state.status === 'Cancelled'
                    ? html`
                        <div class="slds-form-element">
                          <label class="slds-form-element__label" for="visit-cancel-reason"
                            >Cancellation Reason</label
                          >
                          <textarea
                            id="visit-cancel-reason"
                            class="slds-textarea"
                            ?disabled=${locked}
                            .value=${state.cancellationReason}
                            @input=${(e: Event) => {
                              state.cancellationReason = (e.target as HTMLTextAreaElement).value;
                            }}
                          ></textarea>
                        </div>
                      `
                    : nothing}
                  <div class="osr-form-grid osr-form-grid-2">
                    <div class="slds-form-element">
                      <label class="slds-form-element__label" for="visit-objective"
                        >Visit Objective</label
                      >
                      <textarea
                        id="visit-objective"
                        class="slds-textarea"
                        ?disabled=${locked}
                        placeholder="What do you want to achieve on this call?"
                        .value=${state.objective}
                        @input=${(e: Event) => {
                          state.objective = (e.target as HTMLTextAreaElement).value;
                        }}
                      ></textarea>
                    </div>
                    <div class="slds-form-element">
                      <label class="slds-form-element__label" for="visit-notes">Visit Notes</label>
                      <textarea
                        id="visit-notes"
                        class="slds-textarea"
                        ?disabled=${locked}
                        placeholder="Key discussion points and outcomes."
                        .value=${state.notes}
                        @input=${(e: Event) => {
                          state.notes = (e.target as HTMLTextAreaElement).value;
                        }}
                      ></textarea>
                    </div>
                  </div>
                  <div class="slds-form-element">
                    <label class="slds-form-element__label" for="visit-next-date"
                      >Next Visit Date</label
                    >
                    <input
                      id="visit-next-date"
                      class="slds-input"
                      type="date"
                      ?disabled=${locked}
                      .value=${state.nextVisitDate}
                      @input=${(e: Event) => {
                        state.nextVisitDate = (e.target as HTMLInputElement).value;
                      }}
                    />
                  </div>
                </div>
              </article>`
            : nothing}

          ${state.section === 'affiliations'
            ? html`<article class="visit-panel">
                ${renderAffiliationNetwork({
                  rootId: String(visit.accountId || ''),
                  rootAccount:
                    accounts.find((a) => String(a.id) === String(visit.accountId)) ||
                    ({
                      id: visit.accountId,
                      name: visit.accountName,
                      specialty: visit.accountSpecialty,
                      city: visit.accountCity,
                      recordTypeName: visit.accountRecordTypeName,
                      recordTypeDeveloperName: visit.accountRecordTypeDeveloperName
                    } as AccountSummaryDto),
                  snap: opts.snap,
                  title: 'Affiliations Network',
                  subtitle: `Interactive chart for ${visit.accountName || 'this account'} — brick / specialty / city / HCP↔HCO from offline territory cache.`,
                  onOpenAccount: opts.onOpenAccount,
                  requestUpdate: opts.requestUpdate
                })}
              </article>`
            : nothing}

          ${state.section === 'attendees'
            ? html`<article class="visit-panel">
                <h2 class="visit-panel-title">Attendees</h2>
                <p class="visit-panel-sub">Primary attendee is the visit account. Add HCPs/HCOs from your territory list.</p>
                <div class="attendee-list">
                  ${state.attendees.map(
                    (a) => html`
                      <div class="attendee-chip ${a.isPrimary ? 'is-primary' : ''}">
                        <div>
                          <strong>${a.accountName}</strong>
                          <div class="meta-line">
                            ${a.isPrimary ? 'Primary' : 'Attendee'} · ${a.accountTypeLabel || 'Account'}
                            ${a.specialty ? ` · ${a.specialty}` : ''}
                          </div>
                        </div>
                        ${!a.isPrimary && !locked
                          ? html`<button
                              type="button"
                              title="Remove"
                              @click=${() => {
                                state.attendees = state.attendees.filter((x) => x.accountId !== a.accountId);
                                bump();
                              }}
                            >
                              ×
                            </button>`
                          : nothing}
                      </div>
                    `
                  )}
                </div>
                ${!locked
                  ? html`
                      <button
                        type="button"
                        class="slds-button slds-button_neutral"
                        @click=${() => {
                          state.attendeePickerOpen = !state.attendeePickerOpen;
                          bump();
                        }}
                      >
                        ${state.attendeePickerOpen ? 'Close picker' : 'Add attendee'}
                      </button>
                      ${state.attendeePickerOpen
                        ? html`<div class="picker-panel">
                            <input
                              class="slds-input"
                              placeholder="Search territory accounts…"
                              .value=${state.attendeeQuery}
                              @input=${(e: Event) => {
                                state.attendeeQuery = (e.target as HTMLInputElement).value;
                                bump();
                              }}
                            />
                            <div class="picker-list">
                              ${attendeeCandidates.length
                                ? attendeeCandidates.map(
                                    (c) => html`
                                      <div class="picker-row">
                                        <div>
                                          <strong>${c.name}</strong>
                                          <div class="meta-line affil-meta-row">
                                            ${renderAccountKindBadge(c, {
                                              label: c.recordTypeName || undefined,
                                              compact: true
                                            })}
                                            <span>${[c.specialty, c.city].filter(Boolean).join(' · ') || '—'}</span>
                                          </div>
                                        </div>
                                        <button
                                          type="button"
                                          class="slds-button slds-button_brand"
                                          @click=${() => {
                                            state.attendees = [
                                              ...state.attendees,
                                              {
                                                accountId: String(c.id),
                                                accountName: c.name || 'Account',
                                                specialty: c.specialty,
                                                accountTypeLabel: c.recordTypeName || 'Account',
                                                isPrimary: false
                                              }
                                            ];
                                            bump();
                                          }}
                                        >
                                          Add
                                        </button>
                                      </div>
                                    `
                                  )
                                : html`<p class="empty-hint">No matching accounts.</p>`}
                            </div>
                          </div>`
                        : nothing}
                    `
                  : nothing}
              </article>`
            : nothing}

          ${state.section === 'products'
            ? html`<article class="visit-panel">
                <h2 class="visit-panel-title">Products to Detail</h2>
                <p class="visit-panel-sub">Select territory products, then capture detail type, topics, and sentiment.</p>
                <div class="product-layout">
                  <aside class="product-sidebar">
                    <h4 class="sidebar-title" style="margin-top:0">Territory Products</h4>
                    ${TERRITORY_PRODUCTS.map((p) => {
                      const checked = state.selectedProductIds.includes(p.id);
                      return html`
                        <label class="sidebar-item-label">
                          <input
                            type="checkbox"
                            ?disabled=${locked}
                            .checked=${checked}
                            @change=${(e: Event) => {
                              const on = (e.target as HTMLInputElement).checked;
                              state.selectedProductIds = on
                                ? [...state.selectedProductIds, p.id]
                                : state.selectedProductIds.filter((id) => id !== p.id);
                              syncProductSelection(state);
                              bump();
                            }}
                          />
                          <span class="product-thumb">${initials(p.family)}</span>
                          <span>${p.name}</span>
                        </label>
                      `;
                    })}
                  </aside>
                  <div class="product-main">
                    ${state.products.length
                      ? state.products.map(
                          (p, idx) => html`
                            <article class="product-card">
                              <header class="product-card-header">
                                <span class="product-thumb">${initials(p.productName)}</span>
                                <span class="product-order">#${idx + 1}</span>
                                <strong style="flex:1">${p.productName}</strong>
                                ${!locked
                                  ? html`<button
                                      type="button"
                                      class="slds-button slds-button_neutral"
                                      @click=${() => {
                                        state.selectedProductIds = state.selectedProductIds.filter(
                                          (id) => id !== p.productId
                                        );
                                        syncProductSelection(state);
                                        bump();
                                      }}
                                    >
                                      Remove
                                    </button>`
                                  : nothing}
                              </header>
                              <label class="slds-form-element__label">Detail Type</label>
                              <select
                                class="slds-select"
                                ?disabled=${locked}
                                .value=${p.detailType}
                                @change=${(e: Event) => {
                                  p.detailType = (e.target as HTMLSelectElement).value;
                                  bump();
                                }}
                              >
                                ${DETAIL_TYPES.map((t) => html`<option value=${t}>${t}</option>`)}
                              </select>
                              <label class="slds-form-element__label slds-m-top_small">Topics discussed</label>
                              <div class="topic-grid">
                                ${TOPICS.map((t) => {
                                  const on = p.topics.includes(t);
                                  return html`<button
                                    type="button"
                                    class="topic-chip ${on ? 'is-on' : ''}"
                                    ?disabled=${locked}
                                    @click=${() => {
                                      p.topics = on ? p.topics.filter((x) => x !== t) : [...p.topics, t];
                                      bump();
                                    }}
                                  >
                                    ${t}
                                  </button>`;
                                })}
                              </div>
                              <label class="slds-form-element__label slds-m-top_small">Sentiment</label>
                              <div class="sentiment-row">
                                ${SENTIMENTS.map(
                                  (s) => html`<button
                                    type="button"
                                    class="sentiment-btn ${p.sentiment === s ? 'is-on' : ''}"
                                    ?disabled=${locked}
                                    @click=${() => {
                                      p.sentiment = s;
                                      bump();
                                    }}
                                  >
                                    ${s}
                                  </button>`
                                )}
                              </div>
                              <label class="slds-form-element__label slds-m-top_small">Notes</label>
                              <textarea
                                class="slds-textarea"
                                ?disabled=${locked}
                                .value=${p.notes}
                                @input=${(e: Event) => {
                                  p.notes = (e.target as HTMLTextAreaElement).value;
                                }}
                              ></textarea>
                            </article>
                          `
                        )
                      : html`<p class="empty-hint">Check products on the left to start detailing.</p>`}
                  </div>
                </div>
              </article>`
            : nothing}

          ${state.section === 'samples'
            ? html`<article class="visit-panel">
                <h2 class="visit-panel-title">Samples</h2>
                <p class="visit-panel-sub">Record sample drops with quantity and optional recipient attendee.</p>
                ${!locked
                  ? html`<div style="display:flex;flex-wrap:wrap;gap:0.35rem;margin-bottom:0.75rem">
                      ${SAMPLE_PRODUCTS.map(
                        (p) => html`<button
                          type="button"
                          class="slds-button slds-button_neutral"
                          @click=${() => {
                            if (state.samples.some((s) => s.productId === p.id)) return;
                            state.samples = [
                              ...state.samples,
                              {
                                productId: p.id,
                                productName: p.name,
                                quantity: 1,
                                recipientId: state.attendees[0]?.accountId
                              }
                            ];
                            bump();
                          }}
                        >
                          + ${p.name}
                        </button>`
                      )}
                    </div>`
                  : nothing}
                ${state.samples.length
                  ? state.samples.map(
                      (s) => html`
                        <div class="sample-row">
                          <strong>${s.productName}</strong>
                          <div style="display:grid;grid-template-columns:6rem 1fr 1fr auto;gap:0.4rem;margin-top:0.4rem;align-items:end">
                            <div>
                              <label class="slds-form-element__label">Qty</label>
                              <input
                                class="slds-input"
                                type="number"
                                min="1"
                                ?disabled=${locked}
                                .value=${String(s.quantity)}
                                @input=${(e: Event) => {
                                  s.quantity = Number((e.target as HTMLInputElement).value) || 1;
                                }}
                              />
                            </div>
                            <div>
                              <label class="slds-form-element__label">Lot</label>
                              <input
                                class="slds-input"
                                ?disabled=${locked}
                                .value=${s.lot || ''}
                                @input=${(e: Event) => {
                                  s.lot = (e.target as HTMLInputElement).value;
                                }}
                              />
                            </div>
                            <div>
                              <label class="slds-form-element__label">Recipient</label>
                              <select
                                class="slds-select"
                                ?disabled=${locked}
                                .value=${s.recipientId || ''}
                                @change=${(e: Event) => {
                                  s.recipientId = (e.target as HTMLSelectElement).value;
                                }}
                              >
                                ${state.attendees.map(
                                  (a) => html`<option value=${a.accountId}>${a.accountName}</option>`
                                )}
                              </select>
                            </div>
                            ${!locked
                              ? html`<button
                                  type="button"
                                  class="slds-button slds-button_neutral"
                                  @click=${() => {
                                    state.samples = state.samples.filter((x) => x.productId !== s.productId);
                                    bump();
                                  }}
                                >
                                  Remove
                                </button>`
                              : nothing}
                          </div>
                        </div>
                      `
                    )
                  : html`<p class="empty-hint">No samples added yet.</p>`}
              </article>`
            : nothing}

          ${state.section === 'presentations'
            ? html`<article class="visit-panel">
                <h2 class="visit-panel-title">Presentations</h2>
                <p class="visit-panel-sub">
                  Open a CLM presentation to capture slide time and feedback on this visit.
                  ${opts.snap?.clmManifest?.presentations?.length
                    ? ` ${opts.snap.clmManifest.presentations.length} deck(s) cached.`
                    : ' Showing territory starter decks until CLM sync completes.'}
                </p>
                <div style="margin-bottom:0.75rem">
                  <button type="button" class="slds-button slds-button_neutral" @click=${() => opts.onOpenClm?.()}>
                    Open CLM library
                  </button>
                </div>
                <h3 class="sidebar-title">Available Presentations</h3>
                <div class="card-grid">
                  ${presentations.map(
                    (p) => html`
                      <article class="pres-card">
                        <h4>${p.name}</h4>
                        <p class="meta-line">${p.formatType} · ${p.slideCount || '—'} slides</p>
                        <p class="meta-line">Product: ${p.productName}</p>
                        <button
                          type="button"
                          class="slds-button slds-button_brand slds-m-top_x-small"
                          ?disabled=${locked}
                          @click=${() => {
                            opts.onOpenClmPlayer?.(p.id);
                          }}
                        >
                          Open
                        </button>
                      </article>
                    `
                  )}
                </div>
                <h3 class="sidebar-title slds-m-top_medium">Sessions on This Visit</h3>
                <p class="empty-hint">No presentation sessions logged yet. Open a deck to start tracking.</p>
              </article>`
            : nothing}
        </main>

        <aside class="shell-sidebar" aria-label="Neighbouring pharmacies and call history">
          <section class="sidebar-card">
            <h2 class="sidebar-title">Neighbouring Pharmacies</h2>
            <div class="pharmacy-filters">
              ${(['all', 'pharmacy', 'nearby'] as const).map(
                (f) => html`<button
                  type="button"
                  class="pharmacy-filter ${state.pharmacyFilter === f ? 'is-active' : ''}"
                  @click=${() => {
                    state.pharmacyFilter = f;
                    bump();
                  }}
                >
                  ${f === 'all' ? 'All' : f === 'pharmacy' ? 'In list / Pharmacy' : 'Near (<3km)'}
                </button>`
              )}
            </div>
            ${hasGeo
              ? html`<div
                  class="neighbour-map"
                  ${ref((el: Element | undefined) => {
                    if (!(el instanceof HTMLElement)) {
                      if (activeNeighbourMap) {
                        activeNeighbourMap.destroy();
                        activeNeighbourMap = null;
                      }
                      return;
                    }
                    if (!Number.isFinite(lat) || !Number.isFinite(lon)) return;
                    const markers = [
                      {
                        id: 'visit-account',
                        lat,
                        lon,
                        label: visit.accountName || 'Visit account',
                        kind: pinKindFromRecordType(
                          visit.accountRecordTypeName,
                          visit.accountRecordTypeDeveloperName
                        ),
                        selected: true
                      },
                      ...filteredNeighbors
                        .filter(
                          (n) =>
                            Number.isFinite(Number(n.account.latitude)) &&
                            Number.isFinite(Number(n.account.longitude))
                        )
                        .slice(0, 12)
                        .map((n) => ({
                          id: String(n.account.id),
                          lat: Number(n.account.latitude),
                          lon: Number(n.account.longitude),
                          label: `${n.account.name || 'Account'} · ${n.km.toFixed(1)} km`,
                          kind: pinKindFromRecordType(
                            n.account.recordTypeName,
                            n.account.recordTypeDeveloperName
                          )
                        }))
                    ];
                    let handle = neighbourMaps.get(el);
                    if (!handle) {
                      handle = createOsrMap(el, {
                        center: [lat, lon],
                        zoom: 14,
                        fitBounds: true,
                        onMarkerClick: (id) => {
                          if (id !== 'visit-account') opts.onOpenAccount?.(id);
                        }
                      });
                      neighbourMaps.set(el, handle);
                    }
                    activeNeighbourMap = handle;
                    handle.setMarkers(markers);
                    handle.invalidateSize();
                  })}
                ></div>`
              : html`<p class="empty-hint">Visit account has no coordinates — ranking by city / pharmacy type.</p>`}
            ${filteredNeighbors.length
              ? filteredNeighbors.slice(0, 8).map(
                  (n) => html`
                    <div class="pharmacy-row">
                      <strong>${n.account.name || 'Account'}</strong>
                      <div class="meta-line affil-meta-row">
                        ${renderAccountKindBadge(n.account, {
                          label: n.account.recordTypeName || undefined,
                          compact: true
                        })}
                        <span
                          >${n.km < 90 ? `${n.km.toFixed(1)} km` : 'City match'}${n.account.city
                            ? ` · ${n.account.city}`
                            : ''}</span
                        >
                      </div>
                      ${n.account.id
                        ? html`<button
                            type="button"
                            class="slds-button slds-button_neutral slds-m-top_xx-small"
                            @click=${() => opts.onOpenAccount?.(String(n.account.id))}
                          >
                            Open
                          </button>`
                        : nothing}
                    </div>
                  `
                )
              : html`<p class="empty-hint">No neighbouring accounts in the offline cache.</p>`}
          </section>

          <section class="sidebar-card">
            <h2 class="sidebar-title">Call History</h2>
            <h3 class="meta-line" style="font-weight:700;margin-bottom:0.35rem">Previous visits · this account</h3>
            ${history.length
              ? history.slice(0, 5).map(
                  (v) => html`
                    <div class="history-row">
                      <strong>${v.name || 'Visit'}</strong>
                      <div class="meta-line">${formatDateTime(v.startDateTime)} · ${v.status || '—'}</div>
                      ${v.visitObjective
                        ? html`<div class="meta-line">${v.visitObjective}</div>`
                        : nothing}
                    </div>
                  `
                )
              : html`<p class="empty-hint">No prior visits for this account in cache.</p>`}

            <h3 class="meta-line" style="font-weight:700;margin:0.65rem 0 0.35rem">Nearby territory calls</h3>
            ${territoryHistory.length
              ? territoryHistory.map(
                  (v) => html`
                    <div class="history-row">
                      <strong>${v.accountName || v.name || 'Visit'}</strong>
                      <div class="meta-line">
                        ${formatDateTime(v.startDateTime)} · ${v.accountSpecialty || '—'} · ${v.status || '—'}
                      </div>
                    </div>
                  `
                )
              : html`<p class="empty-hint">No related territory visits in cache.</p>`}
          </section>
        </aside>
      </div>

      <footer class="visit-footer">
        ${locked
          ? html`<p class="empty-hint">This visit is ${visit.status} and locked for edits.</p>`
          : html`<button type="button" class="slds-button slds-button_brand" @click=${savePayload}>
              Save Visit
            </button>`}
      </footer>

      ${state.modal !== 'none'
        ? html`
            <section role="dialog" class="slds-modal slds-fade-in-open osr-planner-modal">
              <div class="slds-modal__container">
                <header class="slds-modal__header">
                  <h2 class="slds-text-heading_medium">
                    ${state.modal === 'coaching'
                      ? 'Coaching Event'
                      : state.modal === 'medical'
                        ? 'Medical Inquiry'
                        : state.modal === 'whatsapp'
                          ? 'WhatsApp product survey'
                          : 'Meeting reminder'}
                  </h2>
                </header>
                <div class="slds-modal__content slds-p-around_medium">
                  ${state.modal === 'coaching'
                    ? html`
                        <p class="slds-m-bottom_small">
                          Coaching for <strong>${visit.accountName || 'this visit'}</strong>
                        </p>
                        <label class="slds-form-element__label">Overall score (1–5)</label>
                        <select class="slds-select" data-coaching-score>
                          ${[1, 2, 3, 4, 5].map((n) => html`<option value=${n}>${n}</option>`)}
                        </select>
                        <label class="slds-form-element__label slds-m-top_small">Comments</label>
                        <textarea
                          class="slds-textarea"
                          data-coaching-comments
                          placeholder="Strengths, coaching points, next steps…"
                        ></textarea>
                      `
                    : state.modal === 'medical'
                      ? html`
                          <label class="slds-form-element__label">Inquiry topic</label>
                          <input class="slds-input" data-mi-topic placeholder="Product / topic" />
                          <label class="slds-form-element__label slds-m-top_small">Details</label>
                          <textarea class="slds-textarea" data-mi-details></textarea>
                        `
                      : html`<p class="slds-text-color_weak">
                          WhatsApp / reminder actions need network connectivity. Capture notes on the Details tab
                          meanwhile.
                        </p>`}
                </div>
                <footer class="slds-modal__footer">
                  <button
                    type="button"
                    class="slds-button slds-button_neutral"
                    @click=${() => {
                      state.modal = 'none';
                      bump();
                    }}
                  >
                    Cancel
                  </button>
                  ${state.modal === 'coaching' || state.modal === 'medical'
                    ? html`<button
                        type="button"
                        class="slds-button slds-button_brand"
                        @click=${() => {
                          const score = (
                            document.querySelector('[data-coaching-score]') as HTMLSelectElement | null
                          )?.value;
                          const comments = (
                            document.querySelector('[data-coaching-comments]') as HTMLTextAreaElement | null
                          )?.value;
                          const topic = (
                            document.querySelector('[data-mi-topic]') as HTMLInputElement | null
                          )?.value;
                          const details = (
                            document.querySelector('[data-mi-details]') as HTMLTextAreaElement | null
                          )?.value;
                          if (state.modal === 'coaching') {
                            opts.onSave?.(opts.visitId, {
                              _coachingDraft: true,
                              Coaching_Score__c: score,
                              Coaching_Comments__c: comments
                            });
                          } else {
                            opts.onSave?.(opts.visitId, {
                              _medicalInquiryDraft: true,
                              Medical_Inquiry_Topic__c: topic,
                              Medical_Inquiry_Details__c: details
                            });
                          }
                          state.modal = 'none';
                          bump();
                        }}
                      >
                        Save draft
                      </button>`
                    : html`<button
                        type="button"
                        class="slds-button slds-button_brand"
                        @click=${() => {
                          state.modal = 'none';
                          bump();
                        }}
                      >
                        Close
                      </button>`}
                </footer>
              </div>
            </section>
            <div
              class="slds-backdrop slds-backdrop_open"
              @click=${() => {
                state.modal = 'none';
                bump();
              }}
            ></div>
          `
        : nothing}
    </div>
  `;
}
