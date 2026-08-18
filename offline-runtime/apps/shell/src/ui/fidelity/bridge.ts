/**
 * Shell Vite catalog bridge: registry metadata + Lit overlays for Pharma Field LWCs.
 */
import { html, nothing, type TemplateResult } from 'lit';
import {
  getFidelityEntry,
  isFidelityBundle,
  mountHydratedLwc,
  type FidelityEntry
} from '@osr/ui-runtime';
import type { SqlExecutor } from '@osr/db';
import type { ApexCacheSnapshot } from '../apex-cache';
import { renderFidelityTodayPlan } from '../widgets/today-plan';
import { renderFidelityMetrics } from '../widgets/metrics';
import { renderFidelityNextBest } from '../widgets/next-best';
import { renderFidelityMessages } from '../widgets/messages';
import { renderFidelityClmPrefetch } from '../widgets/clm-prefetch';
import { renderFidelityPlanner } from '../widgets/planner';
import { renderRepLocationPublisher } from '../widgets/rep-location';
import { renderVisitCallShell } from '../widgets/visit-call-shell';
import { renderAccountsTab } from '../widgets/accounts-tab';
import { renderTimeOffSubmission } from '../widgets/time-off';
import {
  renderClmPresentationsHub,
  renderClmPlayer,
  renderClmMessageFeedback,
  renderClmRatingsCapture
} from '../widgets/clm-hub';
import {
  renderAccountAffiliationNetwork,
  renderAccountRatingsPanel,
  renderAccountVisitInsights,
  renderClmAccountActivity
} from '../widgets/account-panels';
import { renderCoachingEventEvaluation, renderCoachingEventInsights } from '../widgets/coaching-event';
import { renderMyLearning } from '../widgets/my-learning';
import { renderPharmacySalesDashboard } from '../widgets/pharmacy-sales-dashboard';
import { renderLwcIframe } from '../lwc-iframe';
import type { LocationTrackerState } from '../../location/rep-location-tracker';
import type { PlannerAccountFilters, PlannerCollection } from '../planner-accounts';
import type { AccountSummaryDto } from '../apex-cache';

export { isFidelityBundle, getFidelityEntry };

export interface FidelityCtx {
  label: string;
  snap: ApexCacheSnapshot | null;
  online: boolean;
  cached: boolean;
  messageIndex?: number;
  leaderboardScope?: 'bu' | 'company';
  metricsFilter?: string;
  metricsSearch?: string;
  metricsPage?: number;
  selectedVisitId?: string | null;
  plannerWeekStart?: string;
  plannerMode?: 'calendar' | 'map';
  plannerSearch?: string;
  selectedAccountId?: string | null;
  plannerAccountFilters?: PlannerAccountFilters;
  plannerFilterPanelOpen?: boolean;
  plannerCollections?: PlannerCollection[];
  plannerSelectedCollectionId?: string | null;
  plannerSaveCollectionOpen?: boolean;
  plannerMapDay?: string;
  promotionalProjects?: { id: string; name: string }[];
  selectedContextUserId?: string | null;
  syncing?: boolean;
  locationState?: LocationTrackerState;
  planChoiceSlot?: string | null;
  visitDetailId?: string | null;
  totModalStart?: string | null;
  promoModalStart?: string | null;
  visitShellId?: string | null;
  recordId?: string | null;
  objectApi?: string | null;
  accountRows?: AccountSummaryDto[] | null;
  clmPlayerId?: string | null;
  myLearningInstanceId?: string | null;
  iframeHeights?: Record<string, number>;
  sfAuth?: { accessToken: string; instanceUrl: string } | null;
  clmPrefetching?: boolean;
  requestUpdate?: () => void;
  actions: {
    openPlanner: () => void;
    openVisit: (id: string) => void;
    openVisitShell?: (id: string) => void;
    closeVisitShell?: () => void;
    openAccount: (id: string) => void;
    openClm: () => void;
    prefetchClmAssets?: () => void;
    openClmPlayer?: (presentationId: string) => void;
    closeClmPlayer?: () => void;
    completeClmSession?: (payload: {
      presentationId: string;
      sessionKey: string;
      visitId?: string | null;
      messages: { name: string; sentiment: string | null }[];
      ratingScore: string;
      ratingNotes: string;
    }) => void;
    setClmPlayerId?: (id: string | null) => void;
    planVisit?: (accountId: string) => void;
    postponeVisit?: (visitId: string) => void;
    removeVisit?: (visitId: string) => void;
    setMessageIndex?: (i: number) => void;
    setLeaderboardScope?: (s: 'bu' | 'company') => void;
    setMetricsFilter?: (f: string) => void;
    setMetricsSearch?: (q: string) => void;
    setMetricsPage?: (p: number) => void;
    setSelectedVisitId?: (id: string | null) => void;
    setPlannerWeekStart?: (iso: string) => void;
    setPlannerMode?: (m: 'calendar' | 'map') => void;
    setPlannerMapDay?: (dayKey: string) => void;
    setPlannerSearch?: (q: string) => void;
    setSelectedAccountId?: (id: string | null) => void;
    setPlannerAccountFilters?: (f: PlannerAccountFilters) => void;
    clearPlannerAccountFilters?: () => void;
    togglePlannerFilterPanel?: () => void;
    closePlannerFilterPanel?: () => void;
    setPlannerSelectedCollectionId?: (id: string | null) => void;
    openSavePlannerCollection?: () => void;
    closeSavePlannerCollection?: () => void;
    savePlannerCollection?: (
      name: string,
      accountIds: string[],
      filters: PlannerAccountFilters
    ) => void;
    deletePlannerCollection?: (id: string) => void;
    addAccountToPlannerCollection?: (collectionId: string, accountId: string) => void;
    reorderDayVisits?: (
      orderedVisitIds: string[],
      dayKey: string,
      legs?: { distanceKm: number; durationMin: number }[]
    ) => void;
    rescheduleVisit?: (visitId: string, startIso: string, endIso: string) => void;
    createDraftVisit?: (accountId: string, startIso: string) => void;
    loadPlannerWeek?: (weekStart: string) => void;
    openPlanChoice?: (startIso: string) => void;
    closePlanChoice?: () => void;
    openTotModal?: (startIso: string) => void;
    closeTotModal?: () => void;
    openPromoModal?: (startIso: string) => void;
    closePromoModal?: () => void;
    closeVisitDetail?: () => void;
    saveVisitDetail?: (visitId: string, status: string, cancellationReason: string) => void;
    createTimeOff?: (input: {
      startIso: string;
      typeValue: string;
      spanType: string;
      durationHours?: string;
      comments?: string;
    }) => void;
    createPromoVisit?: (projectId: string, startIso: string) => void;
    setLocationSharing?: (enabled: boolean) => void;
    saveVisitCallReport?: (visitId: string, fields: Record<string, unknown>) => void;
    setIframeHeight?: (bundle: string, height: number) => void;
    setContextUserId?: (userId: string | null) => void;
    setMyLearningInstanceId?: (id: string | null) => void;
  };
}

type LitRenderer = (ctx: FidelityCtx) => TemplateResult | typeof nothing | null;

const litRenderers = new Map<string, LitRenderer>();

function register(bundle: string, fn: LitRenderer) {
  litRenderers.set(bundle, fn);
}

register('c/fieldRepHomeTodayPlan', (ctx) =>
  renderFidelityTodayPlan({
    label: ctx.label,
    payload: ctx.snap?.todayPlan ?? null,
    viewer: ctx.snap?.plannerViewer ?? null,
    selectedContextUserId: ctx.selectedContextUserId,
    cached: ctx.cached,
    selectedVisitId: ctx.selectedVisitId ?? null,
    onSelectVisit: ctx.actions.setSelectedVisitId,
    onOpenPlanner: ctx.actions.openPlanner,
    onOpenVisit: (id) => {
      // Today Plan "View call" → full visit call shell (not stacked modals)
      ctx.actions.openVisitShell?.(id);
    },
    onOpenAccount: ctx.actions.openAccount,
    onPostpone: ctx.actions.postponeVisit,
    onRemove: ctx.actions.removeVisit,
    onContextUserChange: ctx.actions.setContextUserId
  })
);

register('c/fieldRepHomeMetrics', (ctx) =>
  renderFidelityMetrics({
    label: ctx.label,
    metrics: ctx.snap?.homeMetrics ?? null,
    gamification: ctx.snap?.gamification ?? null,
    rankings: ctx.snap?.rankings ?? null,
    accountCoverage: (ctx.snap?.accountCoverage as Record<string, unknown>[] | null) ?? null,
    cached: ctx.cached,
    leaderboardScope: ctx.leaderboardScope ?? 'bu',
    filter: ctx.metricsFilter ?? 'All',
    search: ctx.metricsSearch ?? '',
    page: ctx.metricsPage ?? 0,
    onScope: ctx.actions.setLeaderboardScope,
    onFilter: ctx.actions.setMetricsFilter,
    onSearch: ctx.actions.setMetricsSearch,
    onPage: ctx.actions.setMetricsPage,
    onOpenAccount: ctx.actions.openAccount
  })
);

register('c/fieldRepHomeNextBestCustomer', (ctx) =>
  renderFidelityNextBest({
    label: ctx.label,
    rows: ctx.snap?.nextBestCustomers ?? null,
    cached: ctx.cached,
    onOpenAccount: ctx.actions.openAccount,
    onPlanVisit: ctx.actions.planVisit
  })
);

register('c/homeOfficeMessages', (ctx) =>
  renderFidelityMessages({
    label: ctx.label,
    messages: ctx.snap?.officeMessages ?? null,
    cached: ctx.cached,
    index: ctx.messageIndex ?? 0,
    onIndex: ctx.actions.setMessageIndex
  })
);

register('c/fieldRepHomeClmPrefetch', (ctx) =>
  renderFidelityClmPrefetch({
    label: ctx.label,
    presentations: ctx.snap?.clmManifest?.presentations ?? null,
    cached: ctx.cached,
    syncing: ctx.syncing || ctx.clmPrefetching,
    onBrowse: ctx.actions.openClm,
    onPrefetch: ctx.actions.prefetchClmAssets
  })
);

register('c/repLocationPublisher', (ctx) =>
  renderRepLocationPublisher({
    label: ctx.label,
    state: ctx.locationState!,
    onToggleSharing: ctx.actions.setLocationSharing
  })
);

register('c/reportsHub', (ctx) => html`
  <div class="osr-lwc-mirror slds-card slds-p-around_medium">
    <strong>${ctx.label || 'Reports'}</strong>
    <p class="slds-text-color_weak">
      Open object tabs from the nav for synced records. Use list / cards / calendar / kanban views and global search.
    </p>
  </div>
`);

register('c/fieldRepPlanner', (ctx) =>
  renderFidelityPlanner({
    label: ctx.label,
    week: ctx.snap?.plannerWeek ?? null,
    accounts: ctx.snap?.plannerAccounts?.accounts ?? null,
    totalAccounts: ctx.snap?.plannerAccounts?.totalCount,
    cached: ctx.cached,
    weekStart: ctx.plannerWeekStart,
    mode: ctx.plannerMode ?? 'calendar',
    search: ctx.plannerSearch ?? '',
    selectedAccountId: ctx.selectedAccountId ?? null,
    mapDay: ctx.plannerMapDay,
    accountFilters: ctx.plannerAccountFilters,
    filterPanelOpen: ctx.plannerFilterPanelOpen,
    collections: ctx.plannerCollections,
    selectedCollectionId: ctx.plannerSelectedCollectionId,
    saveCollectionOpen: ctx.plannerSaveCollectionOpen,
    planChoiceSlot: ctx.planChoiceSlot,
    visitDetailId: ctx.visitDetailId,
    totModalStart: ctx.totModalStart,
    promoModalStart: ctx.promoModalStart,
    promotionalProjects: ctx.promotionalProjects,
    viewer: ctx.snap?.plannerViewer ?? null,
    selectedContextUserId: ctx.selectedContextUserId,
    onWeekChange: ctx.actions.setPlannerWeekStart,
    onMode: ctx.actions.setPlannerMode,
    onMapDayChange: ctx.actions.setPlannerMapDay,
    onSearch: ctx.actions.setPlannerSearch,
    onSelectAccount: ctx.actions.setSelectedAccountId,
    onSetAccountFilters: ctx.actions.setPlannerAccountFilters,
    onClearAccountFilters: ctx.actions.clearPlannerAccountFilters,
    onToggleFilterPanel: ctx.actions.togglePlannerFilterPanel,
    onCloseFilterPanel: ctx.actions.closePlannerFilterPanel,
    onSelectCollection: ctx.actions.setPlannerSelectedCollectionId,
    onOpenSaveCollection: ctx.actions.openSavePlannerCollection,
    onCloseSaveCollection: ctx.actions.closeSavePlannerCollection,
    onSaveCollection: ctx.actions.savePlannerCollection,
    onDeleteCollection: ctx.actions.deletePlannerCollection,
    onAddAccountToCollection: ctx.actions.addAccountToPlannerCollection,
    onCreateDraft: ctx.actions.createDraftVisit,
    onOpenPlanChoice: ctx.actions.openPlanChoice,
    onClosePlanChoice: ctx.actions.closePlanChoice,
    onOpenTotModal: ctx.actions.openTotModal,
    onCloseTotModal: ctx.actions.closeTotModal,
    onOpenPromoModal: ctx.actions.openPromoModal,
    onClosePromoModal: ctx.actions.closePromoModal,
    onCloseVisitDetail: ctx.actions.closeVisitDetail,
    onSaveVisitDetail: ctx.actions.saveVisitDetail,
    onCreateTimeOff: ctx.actions.createTimeOff,
    onCreatePromo: ctx.actions.createPromoVisit,
    onReorderDayVisits: ctx.actions.reorderDayVisits,
    // SF planner: calendar click opens quick detail modal only
    onOpenVisit: (id) => {
      ctx.actions.openVisit?.(id);
    },
    onViewVisit: (id) => {
      ctx.actions.closeVisitDetail?.();
      ctx.actions.openVisitShell?.(id);
    },
    onOpenAccount: ctx.actions.openAccount,
    onPostponeVisit: ctx.actions.postponeVisit,
    onRemoveVisit: ctx.actions.removeVisit,
    onContextUserChange: ctx.actions.setContextUserId,
    onRescheduleVisit: ctx.actions.rescheduleVisit,
    requestUpdate: ctx.requestUpdate
  })
);

register('c/visitCallShell', (ctx) => {
  const id = ctx.visitShellId || ctx.recordId;
  if (!id) {
    return html`<div class="osr-lwc-mirror slds-p-around_medium slds-text-color_weak">
      Open a visit from Today's Plan or the Visits tab.
    </div>`;
  }
  return renderVisitCallShell({
    visitId: id,
    snap: ctx.snap,
    cached: ctx.cached,
    onOpenAccount: ctx.actions.openAccount,
    onOpenClm: ctx.actions.openClm,
    onOpenClmPlayer: ctx.actions.openClmPlayer,
    onSave: ctx.actions.saveVisitCallReport,
    requestUpdate: ctx.requestUpdate
  });
});

register('c/visitCallShellLite', (ctx) => litRenderers.get('c/visitCallShell')!(ctx));

register('c/accountsTab', (ctx) =>
  renderAccountsTab({
    label: ctx.label,
    accounts:
      ctx.accountRows ??
      (ctx.snap?.plannerAccounts?.accounts as AccountSummaryDto[] | null) ??
      null,
    collections: ctx.plannerCollections,
    selectedCollectionId: ctx.plannerSelectedCollectionId,
    cached: ctx.cached,
    onOpenAccount: ctx.actions.openAccount,
    onPlanVisit: ctx.actions.planVisit,
    onSelectCollection: ctx.actions.setPlannerSelectedCollectionId,
    requestUpdate: ctx.requestUpdate
  })
);
register('c/accountsTabOceList', (ctx) => litRenderers.get('c/accountsTab')!(ctx));

register('c/timeOffSubmission', (ctx) =>
  renderTimeOffSubmission({
    label: ctx.label,
    online: ctx.online,
    onSubmit: ctx.actions.createTimeOff,
    requestUpdate: ctx.requestUpdate
  })
);

register('c/clmPresentationsHub', (ctx) =>
  renderClmPresentationsHub({
    label: ctx.label,
    presentations: ctx.snap?.clmManifest?.presentations ?? null,
    cached: ctx.cached,
    onOpenPlayer: (id) => ctx.actions.openClmPlayer?.(id) ?? ctx.actions.setClmPlayerId?.(id)
  })
);

register('c/clmPlayer', (ctx) =>
  renderClmPlayer({
    presentationId: ctx.clmPlayerId ?? ctx.recordId ?? null,
    presentations: ctx.snap?.clmManifest?.presentations ?? null,
    visitId: ctx.visitShellId,
    sfAuth: ctx.sfAuth ?? null,
    online: ctx.online,
    onBack: () => ctx.actions.closeClmPlayer?.() ?? ctx.actions.setClmPlayerId?.(null),
    onComplete: (payload) => ctx.actions.completeClmSession?.(payload),
    requestUpdate: ctx.requestUpdate
  })
);

register('c/clmMessageFeedback', (ctx) =>
  renderClmMessageFeedback({
    sessionId: ctx.clmPlayerId,
    requestUpdate: ctx.requestUpdate
  })
);

register('c/clmRatingsCapture', (ctx) =>
  renderClmRatingsCapture({
    visitId: ctx.visitShellId,
    sessionId: ctx.clmPlayerId,
    requestUpdate: ctx.requestUpdate
  })
);

register('c/clmVisitPresentations', (ctx) =>
  renderClmPresentationsHub({
    label: 'Visit Presentations',
    presentations: ctx.snap?.clmManifest?.presentations ?? null,
    cached: ctx.cached,
    onOpenPlayer: (id) => ctx.actions.openClmPlayer?.(id)
  })
);

register('c/accountAffiliationNetwork', (ctx) =>
  renderAccountAffiliationNetwork({
    recordId: ctx.recordId,
    label: ctx.label,
    snap: ctx.snap,
    onOpenAccount: ctx.actions.openAccount,
    requestUpdate: ctx.requestUpdate
  })
);
register('c/accountRatingsPanel', (ctx) =>
  renderAccountRatingsPanel({ recordId: ctx.recordId, label: ctx.label })
);
register('c/accountVisitInsightsPanel', (ctx) =>
  renderAccountVisitInsights({
    recordId: ctx.recordId,
    label: ctx.label,
    snap: ctx.snap,
    onOpenVisit: (id) => {
      ctx.actions.openVisitShell?.(id);
    }
  })
);
register('c/clmAccountActivityHistory', (ctx) =>
  renderClmAccountActivity({
    recordId: ctx.recordId,
    label: ctx.label,
    presentations: ctx.snap?.clmManifest?.presentations ?? null,
    snap: ctx.snap
  })
);

register('c/coachingEventEvaluation', (ctx) =>
  renderCoachingEventEvaluation({
    recordId: ctx.recordId,
    label: ctx.label,
    online: ctx.online
  })
);
register('c/coachingEventInsights', (ctx) =>
  renderCoachingEventInsights({
    recordId: ctx.recordId,
    label: ctx.label
  })
);

register('c/myLearning', (ctx) =>
  renderMyLearning({
    label: ctx.label,
    courses: ctx.snap?.myLearning ?? null,
    cached: ctx.cached,
    selectedInstanceId: ctx.myLearningInstanceId ?? null,
    onOpenCourse: (id) => ctx.actions.setMyLearningInstanceId?.(id),
    onBackToCatalog: () => ctx.actions.setMyLearningInstanceId?.(null),
    onShowCertificate: (id) => ctx.actions.setMyLearningInstanceId?.(id)
  })
);

register('c/pharmacySalesDashboard', (ctx) =>
  renderPharmacySalesDashboard({
    label: ctx.label,
    data: ctx.snap?.pharmacySalesData ?? null,
    insights: ctx.snap?.pharmacySalesInsights ?? null,
    cached: ctx.cached,
    online: ctx.online
  })
);

/** Visit child slots — point at visit shell sections via thin cards when mounted alone. */
for (const b of [
  'c/visitAccountAffiliations',
  'c/visitAttendeePicker',
  'c/visitProductDetailPanel',
  'c/visitSampleGrid',
  'c/visitNeighbouringPharmacies',
  'c/visitContextInsights',
  'c/visitCoachingFormModal',
  'c/visitMedicalInquiryModal'
] as const) {
  register(b, (ctx) => {
    const id = ctx.visitShellId || ctx.recordId;
    if (!id) {
      return html`<div class="osr-lwc-mirror slds-p-around_small slds-text-color_weak">
        Open from Visit Call Report.
      </div>`;
    }
    return renderVisitCallShell({
      visitId: id,
      snap: ctx.snap,
      cached: ctx.cached,
      onOpenAccount: ctx.actions.openAccount,
      onOpenClm: ctx.actions.openClm,
      onOpenClmPlayer: ctx.actions.openClmPlayer,
      onSave: ctx.actions.saveVisitCallReport,
      requestUpdate: ctx.requestUpdate
    });
  });
}

export function renderFidelity(bundle: string, ctx: FidelityCtx): TemplateResult | typeof nothing | null {
  const entry = getFidelityEntry(bundle);
  if (!entry) return null;

  if (entry.mode === 'iframe-engine') {
    const height = ctx.iframeHeights?.[entry.bundle] ?? 180;
    return html`
      <div class="osr-lwc-mirror osr-lwc-iframe-wrap" data-bundle=${entry.bundle}>
        ${renderLwcIframe({
          bundle: entry.bundle,
          recordId: ctx.recordId,
          height
        })}
      </div>
    `;
  }

  if (entry.mode === 'vite' || entry.mode === 'lit' || entry.mode === 'ce') {
    const fn = litRenderers.get(entry.bundle);
    return fn ? fn(ctx) : null;
  }

  return html`
    <div class="osr-lwc-mirror">
      <div class="lwc-host" data-hydrate-bundle=${entry.bundle} data-lwc-host=${`hydrate-${entry.bundle}`}></div>
    </div>
  `;
}

export async function mountHydrateHosts(
  db: SqlExecutor,
  root: ParentNode,
  snap: ApexCacheSnapshot | null,
  cached: boolean
): Promise<void> {
  const hosts = root.querySelectorAll<HTMLElement>('[data-hydrate-bundle]');
  for (const host of hosts) {
    const bundle = host.getAttribute('data-hydrate-bundle');
    if (!bundle) continue;
    const entry = getFidelityEntry(bundle);
    const data = dataForEntry(entry, snap);
    await mountHydratedLwc(db, host, bundle, { data, cached, title: entry?.label });
  }
}

function dataForEntry(
  entry: FidelityEntry | undefined,
  snap: ApexCacheSnapshot | null
): Record<string, unknown> {
  if (!entry || !snap) return {};
  const out: Record<string, unknown> = { ...((snap as unknown as Record<string, unknown>) ?? {}) };
  for (const key of entry.cacheKeys) {
    const v = (snap as unknown as Record<string, unknown>)[key];
    if (v != null) out[key] = v;
  }
  return out;
}
