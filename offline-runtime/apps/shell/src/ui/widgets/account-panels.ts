import { html, nothing, type TemplateResult } from 'lit';
import type { AccountSummaryDto, ApexCacheSnapshot, VisitSummaryDto } from '../apex-cache';
import {
  accountKindTitle,
  renderAccountKindBadge,
  renderAccountKindIconOnly,
  resolveAccountKind
} from './account-type';
import { renderAffiliationNetwork } from './affiliation-network';
import { renderPhoneActions } from './phone-actions';

type AccountHubTab = 'details' | 'affiliations' | 'insights' | 'activity';

const accountHubUi = new Map<string, { tab: AccountHubTab }>();

function hubUi(accountId: string) {
  let state = accountHubUi.get(accountId);
  if (!state) {
    state = { tab: 'details' };
    accountHubUi.set(accountId, state);
  }
  return state;
}

function visitsForAccount(snap: ApexCacheSnapshot | null, accountId: string | null | undefined): VisitSummaryDto[] {
  if (!accountId || !snap) return [];
  const pools = [snap.todayPlan?.visits, snap.plannerWeek?.visits].filter(Boolean) as VisitSummaryDto[][];
  const out: VisitSummaryDto[] = [];
  const seen = new Set<string>();
  for (const list of pools) {
    for (const v of list) {
      if (String(v.accountId) !== accountId) continue;
      const id = String(v.id ?? '');
      if (!id || seen.has(id)) continue;
      seen.add(id);
      out.push(v);
    }
  }
  return out.sort((a, b) => String(b.startDateTime ?? '').localeCompare(String(a.startDateTime ?? '')));
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

function findAccount(snap: ApexCacheSnapshot | null, accountId: string | null | undefined): AccountSummaryDto | null {
  if (!accountId || !snap?.plannerAccounts?.accounts) return null;
  return snap.plannerAccounts.accounts.find((a) => String(a.id) === accountId) ?? null;
}

function formatWhen(value?: string | null): string {
  if (!value) return '—';
  const d = new Date(value);
  if (Number.isNaN(d.getTime())) return String(value);
  return d.toLocaleString([], { month: 'short', day: 'numeric', hour: '2-digit', minute: '2-digit' });
}

function neighborsFor(
  snap: ApexCacheSnapshot | null,
  account: AccountSummaryDto | null,
  accountId: string
): AccountSummaryDto[] {
  const accounts = snap?.plannerAccounts?.accounts ?? [];
  return accounts
    .filter((a) => a.id && String(a.id) !== accountId)
    .filter((a) => {
      if (account?.city && a.city === account.city) return true;
      if (account?.brickId && a.brickId === account.brickId) return true;
      const blob = `${a.recordTypeName || ''} ${a.name || ''}`.toLowerCase();
      return blob.includes('pharm') || blob.includes('hco');
    })
    .slice(0, 8);
}

/** Full Account record hub — OCE-inspired layout (not the raw field dump). */
export function renderAccountHub(opts: {
  recordId: string;
  record: Record<string, unknown> | null;
  snap?: ApexCacheSnapshot | null;
  editing?: boolean;
  onOpenVisit?: (id: string) => void;
  onOpenAccount?: (id: string) => void;
  onToggleEdit?: () => void;
  onDelete?: () => void;
  detailsSlot?: TemplateResult | typeof nothing;
  requestUpdate?: () => void;
}): TemplateResult {
  const id = opts.recordId;
  const state = hubUi(id);
  const bump = () => opts.requestUpdate?.();
  const cached = findAccount(opts.snap ?? null, id);
  const name = String(opts.record?.Name ?? cached?.name ?? 'Account');
  const phone = String(opts.record?.Phone ?? opts.record?.Account_Phone__c ?? '');
  const specialty = String(cached?.specialty ?? opts.record?.Specialty__c ?? opts.record?.Industry ?? '');
  const city = String(cached?.city ?? opts.record?.BillingCity ?? '');
  const street = String(cached?.street ?? opts.record?.BillingStreet ?? '');
  const classification = String(cached?.classification ?? opts.record?.Classification__c ?? '');
  const kindSource = cached || opts.record;
  const kind = resolveAccountKind(kindSource);
  const typeLabel = String(cached?.recordTypeName ?? opts.record?.Type ?? accountKindTitle(kind));
  const addressLine = [street, city].filter(Boolean).join(', ');
  const actual = Number(cached?.actualVisits ?? 0);
  const target = Number(cached?.targetVisits ?? 0);
  const visits = visitsForAccount(opts.snap ?? null, id);
  const last = visits[0];
  const next = visits
    .filter((v) => v.startDateTime && new Date(v.startDateTime).getTime() >= Date.now())
    .sort((a, b) => String(a.startDateTime ?? '').localeCompare(String(b.startDateTime ?? '')))[0];
  const neighbors = neighborsFor(opts.snap ?? null, cached, id);
  const territoryCalls = allVisits(opts.snap ?? null)
    .filter((v) => String(v.accountId) !== id)
    .filter((v) => (city && v.accountCity === city) || (specialty && v.accountSpecialty === specialty))
    .slice(0, 6);

  return html`
    <div class="osr-lwc-mirror account-hub">
      <section class="account-hub-hero">
        <div class="account-hub-identity">
          ${renderAccountKindIconOnly(kindSource)}
          <div style="min-width:0;flex:1">
            <h2 class="account-hub-name">${name}</h2>
            <div class="account-hub-affiliation">
              ${renderAccountKindBadge(kindSource, { label: typeLabel, compact: true })}
              ${specialty
                ? html`<span class="account-hub-chip">${specialty}</span>`
                : nothing}
            </div>
            <p class="account-hub-meta account-hub-address">
              ${addressLine || 'No address on file'}
            </p>
            ${renderPhoneActions(phone)}
            <div class="account-hub-badges">
              ${classification
                ? html`<span class="oce-badge class-a">${classification}</span>`
                : nothing}
              <span class="oce-badge ${target > 0 ? 'target-yes' : ''}">
                Target ${target > 0 ? 'Yes' : 'No'}
              </span>
              <span class="oce-badge">Call plan ${actual} / ${target || 0}</span>
              ${cached?.frequencyStatus
                ? html`<span class="oce-badge">${cached.frequencyStatus}</span>`
                : nothing}
            </div>
          </div>
        </div>
        <div style="display:flex;flex-wrap:wrap;gap:0.35rem;margin-top:0.75rem">
          <button type="button" class="slds-button slds-button_neutral" @click=${() => opts.onToggleEdit?.()}>
            ${opts.editing ? 'Cancel edit' : 'Edit'}
          </button>
          <button type="button" class="slds-button slds-button_neutral" @click=${() => opts.onDelete?.()}>
            Delete
          </button>
        </div>
      </section>

      <div class="account-hub-layout">
        <div>
          <div class="account-hub-tabs" role="tablist">
            ${(
              [
                ['details', 'Details'],
                ['affiliations', 'Affiliations'],
                ['insights', 'Visit Insights'],
                ['activity', 'Activity']
              ] as const
            ).map(
              ([tab, label]) => html`<button
                type="button"
                class="account-hub-tab ${state.tab === tab ? 'is-active' : ''}"
                @click=${() => {
                  state.tab = tab;
                  bump();
                }}
              >
                ${label}
              </button>`
            )}
          </div>

          <section class="account-hub-panel">
            ${state.tab === 'details'
              ? html`
                  <div class="account-stat-grid">
                    <div class="account-stat">
                      <span>Last call</span>
                      <strong>${last ? formatWhen(last.startDateTime) : '—'}</strong>
                    </div>
                    <div class="account-stat">
                      <span>Next planned</span>
                      <strong>${next ? formatWhen(next.startDateTime) : '—'}</strong>
                    </div>
                    <div class="account-stat">
                      <span>Reach</span>
                      <strong>${target > 0 ? `${Math.round((actual / target) * 100)}%` : '—'}</strong>
                    </div>
                  </div>
                  ${opts.editing
                    ? opts.detailsSlot || nothing
                    : html`
                        <dl class="visit-detail-list">
                          <div class="visit-detail-row">
                            <dt>Account Name</dt>
                            <dd>${name}</dd>
                          </div>
                          <div class="visit-detail-row">
                            <dt>Type</dt>
                            <dd>${renderAccountKindBadge(kindSource, { label: typeLabel })}</dd>
                          </div>
                          <div class="visit-detail-row">
                            <dt>Specialty</dt>
                            <dd>${specialty || '—'}</dd>
                          </div>
                          <div class="visit-detail-row">
                            <dt>Classification</dt>
                            <dd>${classification || '—'}</dd>
                          </div>
                          <div class="visit-detail-row">
                            <dt>Address</dt>
                            <dd>${addressLine || '—'}</dd>
                          </div>
                          <div class="visit-detail-row">
                            <dt>Phone</dt>
                            <dd>${phone ? renderPhoneActions(phone) : '—'}</dd>
                          </div>
                          <div class="visit-detail-row">
                            <dt>Brick</dt>
                            <dd>${cached?.brickName || cached?.brickId || '—'}</dd>
                          </div>
                        </dl>
                        <p class="empty-hint">Use Edit for the full Salesforce field form.</p>
                      `}
                `
              : nothing}

            ${state.tab === 'affiliations'
              ? html`
                  ${renderAffiliationNetwork({
                    rootId: id,
                    rootAccount: cached || {
                      id,
                      name,
                      specialty,
                      city,
                      classification,
                      recordTypeName: typeLabel
                    },
                    snap: opts.snap,
                    title: 'Affiliations Network',
                    subtitle: `Interactive chart for ${name} — offline territory links (brick / specialty / city / HCP↔HCO).`,
                    onOpenAccount: opts.onOpenAccount,
                    requestUpdate: opts.requestUpdate
                  })}
                `
              : nothing}

            ${state.tab === 'insights'
              ? html`
                  <h3 class="visit-panel-title" style="margin-top:0">Visit Insights</h3>
                  <div class="account-stat-grid">
                    <div class="account-stat">
                      <span>Actual</span>
                      <strong>${actual}</strong>
                    </div>
                    <div class="account-stat">
                      <span>Target</span>
                      <strong>${target}</strong>
                    </div>
                    <div class="account-stat">
                      <span>Gap</span>
                      <strong>${Math.max(0, target - actual)}</strong>
                    </div>
                  </div>
                  ${visits.length
                    ? visits.slice(0, 10).map(
                        (v) => html`
                          <div class="history-row">
                            <strong>${v.name || 'Visit'}</strong>
                            <div class="meta-line">${formatWhen(v.startDateTime)} · ${v.status || '—'}</div>
                            <button
                              type="button"
                              class="slds-button slds-button_neutral slds-m-top_xx-small"
                              @click=${() => v.id && opts.onOpenVisit?.(String(v.id))}
                            >
                              Open visit
                            </button>
                          </div>
                        `
                      )
                    : html`<p class="empty-hint">No visits for this account in the offline planner cache.</p>`}
                `
              : nothing}

            ${state.tab === 'activity'
              ? html`
                  <h3 class="visit-panel-title" style="margin-top:0">Activity</h3>
                  <p class="visit-panel-sub">
                    ${(opts.snap?.clmManifest?.presentations?.length ?? 0) || 0} CLM presentation(s) available offline.
                    Account-specific engagement syncs when online.
                  </p>
                  ${visits.slice(0, 8).map(
                    (v) => html`
                      <div class="history-row">
                        <strong>${v.name || 'Visit'}</strong>
                        <div class="meta-line">
                          ${formatWhen(v.startDateTime)} · ${v.status || '—'}
                          ${v.visitObjective ? ` · ${v.visitObjective}` : ''}
                        </div>
                      </div>
                    `
                  )}
                  ${!visits.length
                    ? html`<p class="empty-hint">No activity rows in cache yet.</p>`
                    : nothing}
                `
              : nothing}
          </section>
        </div>

        <aside class="shell-sidebar" style="position:static">
          <section class="sidebar-card">
            <h2 class="sidebar-title">Neighbouring pharmacies</h2>
            ${neighbors.length
              ? neighbors.map(
                  (a) => html`
                    <div class="pharmacy-row">
                      <strong>${a.name}</strong>
                      <div class="meta-line affil-meta-row">
                        ${renderAccountKindBadge(a, {
                          label: a.recordTypeName || undefined,
                          compact: true
                        })}
                        <span>${[a.city, a.specialty].filter(Boolean).join(' · ') || '—'}</span>
                      </div>
                      ${a.id
                        ? html`<button
                            type="button"
                            class="slds-button slds-button_neutral slds-m-top_xx-small"
                            @click=${() => opts.onOpenAccount?.(String(a.id))}
                          >
                            Open
                          </button>`
                        : nothing}
                    </div>
                  `
                )
              : html`<p class="empty-hint">No neighbours in cache.</p>`}
          </section>
          <section class="sidebar-card">
            <h2 class="sidebar-title">Past visits / territory</h2>
            ${visits.slice(0, 4).map(
              (v) => html`
                <div class="history-row">
                  <strong>${v.name || 'Visit'}</strong>
                  <div class="meta-line">${formatWhen(v.startDateTime)} · ${v.status || '—'}</div>
                </div>
              `
            )}
            ${territoryCalls.map(
              (v) => html`
                <div class="history-row">
                  <strong>${v.accountName || v.name}</strong>
                  <div class="meta-line">${formatWhen(v.startDateTime)} · ${v.accountCity || '—'}</div>
                </div>
              `
            )}
            ${!visits.length && !territoryCalls.length
              ? html`<p class="empty-hint">No past visits in cache.</p>`
              : nothing}
          </section>
        </aside>
      </div>
    </div>
  `;
}

export function renderAccountAffiliationNetwork(opts: {
  recordId?: string | null;
  label?: string;
  snap?: ApexCacheSnapshot | null;
  onOpenAccount?: (id: string) => void;
  requestUpdate?: () => void;
}): TemplateResult {
  const id = String(opts.recordId || '');
  const account = findAccount(opts.snap ?? null, id);
  return html`
    <div class="osr-lwc-mirror slds-card slds-p-around_medium">
      ${renderAffiliationNetwork({
        rootId: id,
        rootAccount: account,
        snap: opts.snap,
        title: opts.label || 'Affiliations Network',
        subtitle: `Interactive offline network for ${account?.name || id || 'this account'}.`,
        onOpenAccount: opts.onOpenAccount,
        requestUpdate: opts.requestUpdate
      })}
    </div>
  `;
}

export function renderAccountRatingsPanel(opts: {
  recordId?: string | null;
  label?: string;
}): TemplateResult {
  return html`
    <div class="osr-lwc-mirror slds-card slds-p-around_medium">
      <h3 class="slds-text-heading_small">${opts.label || 'Ratings'}</h3>
      <p class="slds-text-color_weak slds-text-body_small">
        Account ratings captured during CLM / visits sync to Rating objects. Use Visit Call Report → Presentations /
        Coaching offline until child rows are available.
      </p>
    </div>
  `;
}

export function renderAccountVisitInsights(opts: {
  recordId?: string | null;
  label?: string;
  snap?: ApexCacheSnapshot | null;
  onOpenVisit?: (id: string) => void;
}): TemplateResult {
  const visits = visitsForAccount(opts.snap ?? null, opts.recordId);
  const account = findAccount(opts.snap ?? null, opts.recordId ?? null);
  const actual = Number(account?.actualVisits ?? 0);
  const target = Number(account?.targetVisits ?? 0);
  return html`
    <div class="osr-lwc-mirror slds-card slds-p-around_medium">
      <h3 class="slds-text-heading_small">${opts.label || 'Visit Insights'}</h3>
      <div class="account-stat-grid">
        <div class="account-stat"><span>Actual</span><strong>${actual}</strong></div>
        <div class="account-stat"><span>Target</span><strong>${target}</strong></div>
        <div class="account-stat"><span>Gap</span><strong>${Math.max(0, target - actual)}</strong></div>
      </div>
      ${!visits.length
        ? html`<p class="empty-hint">No visits for this account in the offline planner cache.</p>`
        : visits.slice(0, 12).map(
            (v) => html`
              <div class="history-row">
                <strong>${v.name || 'Visit'}</strong>
                <div class="meta-line">${formatWhen(v.startDateTime)} · ${v.status || '—'}</div>
                <button
                  type="button"
                  class="slds-button slds-button_neutral slds-m-top_xx-small"
                  @click=${() => v.id && opts.onOpenVisit?.(v.id)}
                >
                  Open visit
                </button>
              </div>
            `
          )}
    </div>
  `;
}

export function renderClmAccountActivity(opts: {
  recordId?: string | null;
  label?: string;
  presentations?: unknown[] | null;
  snap?: ApexCacheSnapshot | null;
}): TemplateResult {
  const n = opts.presentations?.length ?? 0;
  const visits = visitsForAccount(opts.snap ?? null, opts.recordId);
  return html`
    <div class="osr-lwc-mirror slds-card slds-p-around_medium">
      <h3 class="slds-text-heading_small">${opts.label || 'CLM Activity'}</h3>
      <p class="slds-text-color_weak slds-text-body_small">
        ${n} presentation(s) available offline for this rep. Recent visits for this account:
      </p>
      ${visits.slice(0, 8).map(
        (v) => html`
          <div class="history-row">
            <strong>${v.name || 'Visit'}</strong>
            <div class="meta-line">${formatWhen(v.startDateTime)} · ${v.status || '—'}</div>
          </div>
        `
      )}
      ${!visits.length ? html`<p class="empty-hint">No activity in cache.</p>` : nothing}
    </div>
  `;
}
