import { LitElement, css, html, nothing, type TemplateResult } from 'lit';
import { customElement, state } from 'lit/decorators.js';
import {
  openDatabase,
  type SqlExecutor,
  listRecords,
  listPendingOutbox,
  listListViewsForObject,
  searchRecords,
  kvGet,
  kvSet,
  getObjectDescribe,
  getUserPrefs,
  upsertUserPrefs,
  fieldLabelFromDescribe,
  fieldsFromDescribe,
  dateFieldsFromDescribe,
  resolveLookupDisplay,
  upsertApexPayload,
  getApexPayload,
  getRecord,
  listLogs,
  appendLog,
  clearLogs,
  countLogs,
  type LogEntry,
  type DescribeFieldInfo,
  type UserObjectPrefs
} from '@osr/db';
import { Capacitor } from '@capacitor/core';
import { Preferences } from '@capacitor/preferences';
import {
  beginSalesforceLogin,
  completeSalesforceLogin,
  createLiveSyncEngine,
  installOAuthDeepLinkHandler,
  clearSession,
  loadSession,
  loginUrlFromPageParams,
  extractMyDomainLabel,
  myDomainLoginUrlFromLabel,
  isStandardSalesforceLogin,
  PRODUCTION_LOGIN,
  SANDBOX_LOGIN,
  MY_DOMAIN_SUFFIX,
  type TokenSet
} from '../auth/oauth';
import type { SyncProgress } from '@osr/sync';
import { sundayWeekRange, isoDateLocal, localSaveRecord, localDeleteRecord } from '@osr/sync';
import { repLocationTracker } from '../location/rep-location-tracker';
import type { LocationTrackerState } from '../location/rep-location-tracker';
import { exportSupportBundle } from '../support/export-bundle';
import {
  type NavRoute,
  type AppSummary,
  type FlexiPageModel,
  type FlexiComponent,
  type LayoutModel,
  loadNavigation,
  loadHomeView,
  loadRecordView,
  loadRelatedLists,
  saveWithValidation,
  getConflicts,
  applyConflictResolution,
  mountLwc,
  isCustomLwcType,
  lwcBundleFromComponent,
  humanizeComponentLabel,
  normalizeLwcBundleName,
  hasUsableLwcBundle,
  getFlexiPage,
  parseFlexiPage,
  isFidelityBundle,
  enqueueClmSession,
  formFactorFromWidth,
  selectRegionsForFormFactor,
  isComponentVisible,
  resolveFieldSectionFields,
  isFieldReadonly,
  isFieldRequired,
  classifyActionKind,
  isFieldHomeLayout,
  planFieldHomeRegions,
  sortFieldHomeComponents,
  APEX_BINDING_TO_CACHE_KEY,
  type FormFactor,
  type OfflineAction,
  type RelatedListMeta
} from '@osr/ui-runtime';
import { BridgeHost } from '@osr/bridge';
import { createShellBridgeHandler, compileSyncedLwcs } from './shell-bridge';
import {
  type ListViewMode,
  type PickerListView,
  applyListViewFilter,
  columnsForView,
  formatDayHeading,
  groupByCalendarDay,
  groupByKanban
} from './list-helpers';
import {
  searchableFieldsForObject,
  filterRowsByTextSearch,
  detectKanbanFieldSmart,
  detectDateFieldSmart,
  suggestDefaultListMode,
  crmHubSearchPlaceholder,
  crmHubSubtitle
} from './crmhub-list';
import {
  type ApexCacheSnapshot,
  loadApexCacheSnapshot,
  ensurePlannerAccountsFallback,
  type VisitSummaryDto,
  type PlannerPayloadDto,
  haversineKm
} from './apex-cache';
import {
  renderFidelity,
  mountHydrateHosts,
  type FidelityCtx
} from './fidelity/bridge';
import { mirrorStyles } from './widgets/mirror-styles';
import { renderAccountHub } from './widgets/account-panels';

const CURRENT_APP_KEY = 'osr.currentApp';
const SYNC_SUCCESS_COUNT_KEY = 'osr.sync.successCount';
/** Auto background sync while online. */
const BG_SYNC_INTERVAL_MS = 5 * 60 * 1000;
/** Run local↔server integrity check every N successful syncs. */
const VALIDATE_EVERY_N_SYNCS = 5;

function todayIsoDate() {
  return isoDateLocal(new Date());
}

/** Open / actionable row heuristics that work across common CRM objects. */
function isOpenWorkItem(r: Record<string, unknown>) {
  const status = String(r.Status__c ?? r.Status ?? r.StageName ?? '').toLowerCase();
  if (!status) return true;
  return (
    status === 'planned' ||
    status === 'in progress' ||
    status === 'open' ||
    status === 'not started' ||
    status === 'prospecting' ||
    status === 'new'
  );
}

function recordTitle(r: Record<string, unknown>): string {
  return String(r.Name ?? r.Subject ?? r.CaseNumber ?? r.Title ?? r.Id ?? '');
}

function workDateValue(r: Record<string, unknown>): string {
  return String(
    r.Planned_Date__c ??
      r.Visit_Date__c ??
      r.Start_Date__c ??
      r.ActivityDate ??
      r.StartDateTime ??
      r.CloseDate ??
      ''
  );
}

function recordSubtitle(r: Record<string, unknown>): string {
  const parts = [
    r.Status__c ?? r.Status ?? r.StageName,
    workDateValue(r) || null,
    r.Type ?? r.Industry ?? r.BillingCity
  ]
    .map((v) => (v != null && String(v) !== '' ? String(v).slice(0, 40) : ''))
    .filter(Boolean);
  return parts.join(' · ');
}

/**
 * SLDS standard icon palette + simplified white glyphs (viewBox 0 0 52 52).
 * Colors match Lightning Design System standard icon backgrounds.
 */
type SldsIconSpec = { color: string; path: string };

const SLDS_ICON_MAP: Record<string, SldsIconSpec> = {
  home: {
    color: '#1b96ff',
    path: 'M26 6L6 22v24h14V32h12v14h14V22L26 6z'
  },
  account: {
    color: '#7f8de1',
    path: 'M10 44V20l16-10 16 10v24H10zm8-6h16V24L26 18 18 24v14zM26 32a4 4 0 100-8 4 4 0 000 8z'
  },
  contact: {
    color: '#8c65f7',
    path: 'M26 8a8 8 0 110 16 8 8 0 010-16zM10 44c0-9 7-14 16-14s16 5 16 14H10z'
  },
  lead: {
    color: '#f88962',
    path: 'M26 7a7 7 0 110 14 7 7 0 010-14zM12 44c0-7 6-12 14-12s14 5 14 12H12zm24-26l8 2-2 4-6-1v-5z'
  },
  opportunity: {
    color: '#fcb95b',
    path: 'M26 6l4 12h12l-10 8 4 12-10-7-10 7 4-12-10-8h12z'
  },
  case: {
    color: '#f2cf5b',
    path: 'M10 14h32v28H10V14zm6 6v4h20v-4H16zm0 10v4h14v-4H16z'
  },
  task: {
    color: '#4bc076',
    path: 'M10 12h32v28H10V12zm6 6v4h20v-4H16zm0 8v4h16v-4H16zm0 8v4h12v-4H16z'
  },
  event: {
    color: '#eb7092',
    path: 'M14 10h4v4h16v-4h4v4h4v32H10V14h4v-4zm-2 12v18h28V22H12zm6 4h6v6h-6v-6z'
  },
  report: {
    color: '#2e844a',
    path: 'M12 42V18h8v24h-8zm10 0V10h8v32h-8zm10 0V26h8v16h-8z'
  },
  dashboard: {
    color: '#ef7ead',
    path: 'M8 8h16v16H8V8zm20 0h16v10H28V8zM8 28h10v16H8V28zm14 6h22v10H22V34z'
  },
  menu: {
    color: '#706e6b',
    path: 'M10 14h32v4H10v-4zm0 10h32v4H10v-4zm0 10h32v4H10v-4z'
  },
  custom: {
    color: '#0176d3',
    path: 'M26 8l4 10h10l-8 6 3 10-9-6-9 6 3-10-8-6h10z'
  },
  visit: {
    color: '#0b827c',
    path: 'M26 6c-8 0-14 6-14 14 0 10 14 26 14 26s14-16 14-26c0-8-6-14-14-14zm0 20a6 6 0 110-12 6 6 0 010 12z'
  }
};

const OBJECT_TO_SLDS: Record<string, string> = {
  Home: 'home',
  Account: 'account',
  Contact: 'contact',
  Lead: 'lead',
  Opportunity: 'opportunity',
  Case: 'case',
  Task: 'task',
  Event: 'event',
  Report: 'report',
  Dashboard: 'dashboard',
  Visit__c: 'visit',
  Visit: 'visit',
  Menu: 'menu'
};

const ICON_COLORS = [
  '#0176d3',
  '#2e844a',
  '#7f8de1',
  '#fcb95b',
  '#f88962',
  '#4bc076',
  '#eb7092',
  '#f2cf5b',
  '#9050e9',
  '#0b827c'
];

function sldsKeyFor(name: string): string {
  const bare = (name || '').replace(/^standard-/i, '').trim();
  if (OBJECT_TO_SLDS[bare]) return OBJECT_TO_SLDS[bare];
  const lower = bare.toLowerCase();
  if (lower.includes('home')) return 'home';
  if (lower.includes('account')) return 'account';
  if (lower.includes('contact')) return 'contact';
  if (lower.includes('lead')) return 'lead';
  if (lower.includes('opportunit')) return 'opportunity';
  if (lower.includes('case')) return 'case';
  if (lower.includes('task')) return 'task';
  if (lower.includes('event')) return 'event';
  if (lower.includes('visit')) return 'visit';
  if (lower.includes('report')) return 'report';
  if (lower.includes('menu')) return 'menu';
  return 'custom';
}

function iconFor(name: string): { color: string; key: string } {
  const key = sldsKeyFor(name);
  const known = SLDS_ICON_MAP[key] ?? SLDS_ICON_MAP.custom!;
  if (key !== 'custom') return { color: known.color, key };
  let hash = 0;
  for (let i = 0; i < name.length; i++) hash = (hash * 31 + name.charCodeAt(i)) >>> 0;
  return { color: ICON_COLORS[hash % ICON_COLORS.length]!, key: 'custom' };
}

function renderSldsGlyph(name: string, size = 18): TemplateResult {
  const { key } = iconFor(name);
  const spec = SLDS_ICON_MAP[key] ?? SLDS_ICON_MAP.custom!;
  return html`<svg
    class="slds-glyph"
    viewBox="0 0 52 52"
    width=${size}
    height=${size}
    aria-hidden="true"
    focusable="false"
  >
    <path fill="#fff" d=${spec.path}></path>
  </svg>`;
}

function renderIconTile(
  name: string,
  opts: { iconUrl?: string | null; size?: number; className?: string } = {}
): TemplateResult {
  const size = opts.size ?? 32;
  const ic = iconFor(name);
  const cls = opts.className ?? 'nav-glyph';
  const glyphSize = Math.round(size * 0.55);
  if (opts.iconUrl) {
    return html`<span
      class="${cls} has-img"
      style="width:${size}px;height:${size}px;background:${ic.color}"
    >
      <img
        src=${opts.iconUrl}
        alt=""
        width=${glyphSize}
        height=${glyphSize}
        decoding="async"
        @error=${(e: Event) => {
          const img = e.target as HTMLImageElement;
          const parent = img.parentElement;
          if (!parent) return;
          img.remove();
          parent.classList.remove('has-img');
          const svgNs = 'http://www.w3.org/2000/svg';
          const svgEl = document.createElementNS(svgNs, 'svg');
          svgEl.setAttribute('viewBox', '0 0 52 52');
          svgEl.setAttribute('width', String(glyphSize));
          svgEl.setAttribute('height', String(glyphSize));
          svgEl.setAttribute('aria-hidden', 'true');
          const path = document.createElementNS(svgNs, 'path');
          path.setAttribute('fill', '#fff');
          path.setAttribute('d', (SLDS_ICON_MAP[ic.key] ?? SLDS_ICON_MAP.custom!).path);
          svgEl.appendChild(path);
          parent.appendChild(svgEl);
        }}
      />
    </span>`;
  }
  return html`<span
    class=${cls}
    style="background:${ic.color};width:${size}px;height:${size}px"
  >
    ${renderSldsGlyph(name, glyphSize)}
  </span>`;
}

type TabRow = {
  id: string;
  developerName: string;
  label: string;
  tab: {
    objectApi?: string;
    tabType?: string;
    type?: string;
    pageDeveloperName?: string;
    lwcBundle?: string;
    url?: string;
    iconUrl?: string;
  };
};

type ObjectRef = { apiName: string; label: string };

@customElement('osr-app')
export class OsrApp extends LitElement {
  @state() private db: SqlExecutor | null = null;
  @state() private online = typeof navigator !== 'undefined' ? navigator.onLine : true;
  @state() private route: NavRoute = { kind: 'launcher' };
  @state() private apps: AppSummary[] = [];
  @state() private tabs: TabRow[] = [];
  @state() private currentApp: string | null = null;
  @state() private appLabel = '';
  @state() private status = 'Starting…';
  @state() private syncMode: 'sync-pack' | 'rest-fallback' | 'mock' | 'logged-out' = 'logged-out';
  @state() private tokens: TokenSet | null = null;
  @state() private listRows: Record<string, unknown>[] = [];
  @state() private record: Record<string, unknown> | null = null;
  @state() private layout: LayoutModel | null = null;
  @state() private flexiPage: FlexiPageModel | null = null;
  @state() private homeFlexi: FlexiPageModel | null = null;
  @state() private related: {
    name: string;
    objectApi: string;
    fields?: string[];
    records: Record<string, unknown>[];
  }[] = [];
  @state() private formErrors: string[] = [];
  @state() private fieldErrors: Record<string, string> = {};
  @state() private objectActions: OfflineAction[] = [];
  @state() private compactFields: string[] = [];
  @state() private formFactor: FormFactor = 'Large';
  @state() private listFilterWarning: string | null = null;
  @state() private listColumns: string[] = [];
  @state() private inlineEditId: string | null = null;
  @state() private inlineEditField: string | null = null;
  @state() private inlineEditValue = '';
  @state() private conflicts: Awaited<ReturnType<typeof getConflicts>> = [];
  @state() private supportLogs: LogEntry[] = [];
  @state() private supportLogCount = 0;
  @state() private exportingSupport = false;
  @state() private pendingCount = 0;
  @state() private loginUrl = PRODUCTION_LOGIN;
  /** Raw My Domain label/host shown in the custom domain field. */
  @state() private customDomainInput = '';
  @state() private loginEnv: 'production' | 'sandbox' | 'custom' = 'production';
  @state() private userLabel = 'Not signed in';
  @state() private syncing = false;
  /** Live channel/object progress from SyncEngine (null when idle). */
  @state() private syncProgress: SyncProgress | null = null;
  /** True until the first post-login sync attempt finishes (ok or fail). */
  @state() private initialSyncPending = false;
  @state() private syncFailedMessage: string | null = null;
  /** Last integrity check summary (every 5th sync). */
  @state() private syncValidationSummary: string | null = null;
  private bgSyncTimer: ReturnType<typeof setInterval> | null = null;
  private successfulSyncCount = 0;
  @state() private launcherFilter = '';
  @state() private editing = false;
  /** Today's / open work rows from the resolved work object (Visit, Task, Event, …). */
  @state() private homeWorkRows: Record<string, unknown>[] = [];
  /** Recent records from Account (if present) or primary tab object. */
  @state() private homeRecentRows: Record<string, unknown>[] = [];
  @state() private workObject: ObjectRef | null = null;
  @state() private recentObject: ObjectRef | null = null;
  @state() private homeObjectCounts: { apiName: string; label: string; count: number }[] = [];
  /** Record opened in modal overlay (list stays underneath). */
  @state() private modalOpen = false;
  @state() private modalObjectApi = '';
  @state() private listViewMode: ListViewMode = 'list';
  @state() private activeListViewId = 'all';
  @state() private objectListViews: PickerListView[] = [];
  @state() private favouriteListViewIds: string[] = [];
  @state() private pinnedListViewId: string | null = null;
  @state() private calendarFieldPref: string | null = null;
  @state() private listPickerOpen = false;
  @state() private calendarPickerOpen = false;
  @state() private objectDescribe: Record<string, unknown> | null = null;
  @state() private fieldMeta: DescribeFieldInfo[] = [];
  /** fieldApi → resolved lookup display for current modal record */
  @state() private lookupNames: Record<
    string,
    { id: string; name: string; objectApi: string | null }
  > = {};
  @state() private globalSearch = '';
  @state() private searchHits: { objectApi: string; record: Record<string, unknown> }[] = [];
  @state() private searchOpen = false;
  /** Bundles with runnable synced CE source — prefer mount over Lit stand-ins. */
  @state() private usableLwc = new Set<string>();
  @state() private customTabFlexi: FlexiPageModel | null = null;
  @state() private customTabLwc: string | null = null;
  @state() private customTabUnsupported: string | null = null;
  @state() private apexSnapshot: ApexCacheSnapshot | null = null;
  @state() private messageCarouselIndex = 0;
  /** When custom tab is fieldRepPlanner, render Lit planner instead of offlineHost. */
  @state() private customTabFidelityPlanner = false;
  @state() private leaderboardScope: 'bu' | 'company' = 'bu';
  @state() private metricsFilter = 'All';
  @state() private metricsSearch = '';
  @state() private metricsPage = 0;
  @state() private selectedVisitId: string | null = null;
  @state() private plannerWeekStart = '';
  @state() private plannerMode: 'calendar' | 'map' = 'calendar';
  @state() private plannerMapDay = '';
  @state() private plannerSearch = '';
  @state() private selectedAccountId: string | null = null;
  @state() private plannerAccountFilters: import('./planner-accounts').PlannerAccountFilters = {
    recordType: 'ALL',
    specialty: 'ALL',
    classification: 'ALL',
    brickId: 'ALL'
  };
  @state() private plannerFilterPanelOpen = false;
  @state() private plannerCollections: import('./planner-accounts').PlannerCollection[] = [];
  @state() private plannerSelectedCollectionId: string | null = null;
  @state() private plannerSaveCollectionOpen = false;
  @state() private iframeHeights: Record<string, number> = {};
  @state() private toastMessage: string | null = null;
  @state() private lwcCompatSummary: string | null = null;
  @state() private objectListSearch = '';
  @state() private clmPlayerId: string | null = null;
  @state() private myLearningInstanceId: string | null = null;
  @state() private locationState: import('../location/rep-location-tracker').LocationTrackerState = {
    sharing: true,
    permissionDenied: false,
    lastPoint: null,
    error: null,
    watching: false
  };
  @state() private planChoiceSlot: string | null = null;
  @state() private visitDetailId: string | null = null;
  @state() private totModalStart: string | null = null;
  @state() private promoModalStart: string | null = null;
  @state() private visitShellId: string | null = null;
  @state() private selectedContextUserId: string | null = null;
  /** When set, CLM player overlay is shown above visit shell / tabs. */
  @state() private clmPlayerOverlayOpen = false;

  private removeDeepLink?: () => void;
  private searchTimer: ReturnType<typeof setTimeout> | null = null;
  private unsubLocation?: () => void;
  private detachBridge?: () => void;
  private bridgeHost?: BridgeHost;
  /** Monotonic token so in-flight openList/loadHome can't clobber a newer nav. */
  private navToken = 0;

  static styles = [
    mirrorStyles,
    css`
    /* Shadow DOM does not inherit light-DOM * { box-sizing } — without this,
       width:100% + padding overflows and “bleeds” on the right. */
    :host,
    :host *,
    :host *::before,
    :host *::after {
      box-sizing: border-box;
    }

    :host {
      display: block;
      min-height: 100vh;
      min-height: 100dvh;
      width: 100%;
      max-width: 100%;
      overflow-x: hidden;
      background: var(--sf-bg);
      color: var(--sf-text);
      font-family: var(--font);
    }

    .shell {
      display: grid;
      grid-template-rows: auto 1fr auto;
      min-height: 100vh;
      min-height: 100dvh;
      width: 100%;
      max-width: 100%;
      overflow-x: hidden;
      padding-top: var(--safe-top);
      padding-bottom: var(--safe-bottom);
      padding-left: var(--safe-left);
      padding-right: var(--safe-right);
    }

    .topbar {
      display: flex;
      align-items: center;
      gap: 10px;
      min-height: 52px;
      min-width: 0;
      width: 100%;
      max-width: 100%;
      padding: 8px 12px;
      background: var(--sf-surface);
      border-bottom: 1px solid var(--sf-border);
      position: sticky;
      top: 0;
      z-index: 20;
    }

    .topbar-wrap {
      position: sticky;
      top: 0;
      z-index: 20;
      background: var(--sf-surface);
      border-bottom: 1px solid var(--sf-border);
    }

    .topbar-wrap .topbar {
      position: relative;
      top: auto;
      z-index: auto;
      border-bottom: none;
    }

    .sync-progress-track {
      height: 3px;
      width: 100%;
      background: #d8e6f8;
      overflow: hidden;
      flex-shrink: 0;
    }

    .sync-progress-fill {
      height: 100%;
      background: var(--sf-blue);
      border-radius: 0 2px 2px 0;
      transition: width 0.25s ease;
      min-width: 0;
    }

    .sync-progress-fill.indeterminate {
      width: 35%;
      min-width: 35%;
      border-radius: 2px;
      animation: osr-progress-indeterminate 1.2s ease-in-out infinite;
    }

    @keyframes osr-progress-indeterminate {
      0% {
        transform: translateX(-120%);
      }
      100% {
        transform: translateX(320%);
      }
    }

    .sync-progress-block {
      width: 100%;
      max-width: 280px;
      margin-top: 8px;
    }

    .sync-progress-block .sync-progress-track {
      height: 6px;
      border-radius: 999px;
    }

    .sync-progress-block .sync-progress-fill {
      border-radius: 999px;
    }

    .sync-progress-block .sync-progress-fill.indeterminate {
      border-radius: 999px;
    }

    .topbar-logo {
      height: 28px;
      width: auto;
      max-width: none;
      object-fit: contain;
      object-position: left center;
      flex-shrink: 0;
      display: block;
    }

    .avatar {
      width: 36px;
      height: 36px;
      border-radius: 50%;
      background: var(--sf-blue);
      color: #fff;
      display: grid;
      place-items: center;
      font-weight: 700;
      font-size: 12px;
      flex-shrink: 0;
    }

    .top-title {
      flex: 1;
      min-width: 0;
    }

    .top-title h1 {
      margin: 0;
      font-size: 17px;
      font-weight: 700;
      line-height: 1.2;
      white-space: nowrap;
      overflow: hidden;
      text-overflow: ellipsis;
    }

    .top-title p {
      margin: 2px 0 0;
      font-size: 11px;
      color: var(--sf-muted);
      white-space: nowrap;
      overflow: hidden;
      text-overflow: ellipsis;
    }

    .pill {
      border-radius: 999px;
      padding: 4px 10px;
      font-size: 11px;
      font-weight: 600;
      background: #eef4ff;
      color: var(--sf-blue-dark);
      border: none;
    }

    .pill.offline {
      background: #fcebea;
      color: var(--sf-danger);
    }

    .icon-btn {
      width: var(--sf-touch);
      height: var(--sf-touch);
      border: none;
      border-radius: 50%;
      background: transparent;
      color: var(--sf-blue);
      font-size: 18px;
      cursor: pointer;
      display: grid;
      place-items: center;
    }

    .icon-btn:disabled {
      opacity: 0.4;
    }

    .body {
      min-height: 0;
      min-width: 0;
      overflow: auto;
      overflow-x: hidden;
      -webkit-overflow-scrolling: touch;
      width: 100%;
      max-width: 100%;
    }

    .body.has-bottom {
      padding-bottom: calc(64px + var(--safe-bottom));
    }

    .layout-wide {
      display: block;
      width: 100%;
      max-width: 100%;
      min-width: 0;
      min-height: 100%;
    }

    .rail {
      display: none;
    }

    .main-pane {
      width: 100%;
      max-width: 100%;
      min-width: 0;
      min-height: 100%;
      overflow-x: hidden;
    }

    .split {
      display: block;
      width: 100%;
      min-height: 100%;
    }

    .split-list,
    .split-detail {
      width: 100%;
    }

    .bottom-nav {
      position: fixed;
      left: 0;
      right: 0;
      bottom: 0;
      display: flex;
      background: var(--sf-bottom);
      border-top: 1px solid var(--sf-border);
      padding-bottom: var(--safe-bottom);
      /* Above visit/CLM overlays so Home always receives taps */
      z-index: 120;
    }

    .bottom-nav button {
      flex: 1;
      border: none;
      background: transparent;
      padding: 8px 4px;
      min-height: 56px;
      display: flex;
      flex-direction: column;
      align-items: center;
      justify-content: center;
      gap: 2px;
      color: var(--sf-muted);
      font-size: 10px;
      cursor: pointer;
    }

    .bottom-nav button.active {
      color: var(--sf-blue);
      font-weight: 700;
    }

    .bottom-nav .nav-glyph {
      width: 32px;
      height: 32px;
      border-radius: 6px;
      display: grid;
      place-items: center;
      color: #fff;
      background: var(--sf-muted);
      overflow: hidden;
      flex-shrink: 0;
    }

    .bottom-nav .nav-glyph.has-img {
      background: #fff;
      border: 1px solid var(--sf-border);
    }

    .bottom-nav .nav-glyph img,
    .bottom-nav .nav-glyph .slds-glyph {
      display: block;
    }

    .bottom-nav button.active .nav-glyph {
      box-shadow: 0 0 0 2px rgba(1, 118, 211, 0.35);
    }

    .osr-toast {
      position: fixed;
      left: 50%;
      bottom: calc(72px + var(--safe-bottom));
      transform: translateX(-50%);
      z-index: 80;
      max-width: min(92vw, 420px);
      padding: 10px 14px;
      border-radius: 8px;
      background: #032d60;
      color: #fff;
      font-size: 13px;
      box-shadow: 0 8px 24px rgba(0, 0, 0, 0.2);
    }

    .osr-lwc-iframe-wrap {
      min-height: 80px;
    }

    /* —— Login —— */
    .login {
      min-height: 100vh;
      min-height: 100dvh;
      display: flex;
      flex-direction: column;
      justify-content: center;
      padding: 24px 20px;
      background: linear-gradient(180deg, #eaf5fe 0%, #f3f3f3 45%);
    }

    .login-card {
      width: 100%;
      max-width: 420px;
      margin: 0 auto;
      background: var(--sf-surface);
      border-radius: 12px;
      padding: 28px 20px;
      box-shadow: var(--sf-shadow);
    }

    .login-card h1 {
      margin: 0 0 8px;
      font-size: 22px;
      color: var(--sf-blue-dark);
    }

    .login-brand {
      display: flex;
      align-items: center;
      justify-content: center;
      margin-bottom: 16px;
    }

    .login-brand img {
      height: 72px;
      width: auto;
      max-width: 200px;
      object-fit: contain;
    }

    .login-card p {
      margin: 0 0 20px;
      color: var(--sf-muted);
      font-size: 14px;
    }

    .login-theme-note {
      margin: -8px 0 16px;
      padding: 10px 12px;
      border-radius: 8px;
      background: #eef6ff;
      border: 1px solid #c9e0f7;
      color: #032d60;
      font-size: 12px;
      line-height: 1.4;
    }

    .login-theme-note code {
      font-size: 11px;
      word-break: break-all;
    }

    .domain-combo {
      display: flex;
      align-items: stretch;
      min-height: var(--sf-touch);
      border: 1px solid var(--sf-border);
      border-radius: var(--sf-control-radius, 12px);
      background: var(--sf-control-bg, #f2f4f7);
      overflow: hidden;
    }

    .domain-combo:focus-within {
      border-color: var(--sf-blue, #0176d3);
      box-shadow: 0 0 0 3px rgba(1, 118, 211, 0.15);
      background: #fff;
    }

    .domain-combo input {
      flex: 1;
      min-width: 0;
      border: 0;
      background: transparent;
      border-radius: 0;
      padding: 10px 12px;
      font-size: 15px;
      outline: none;
      box-shadow: none;
      min-height: var(--sf-touch);
    }

    .domain-combo .domain-suffix {
      display: flex;
      align-items: center;
      padding: 0 12px;
      background: #e8eef5;
      color: #54698d;
      font-size: 13px;
      font-weight: 600;
      white-space: nowrap;
      border-left: 1px solid var(--sf-border);
      user-select: none;
    }

    .field {
      display: flex;
      flex-direction: column;
      gap: 8px;
      margin-bottom: 16px;
    }

    .field label {
      font-size: 13px;
      font-weight: 600;
      letter-spacing: -0.01em;
      color: var(--sf-muted);
    }

    .field select,
    .field input,
    .search {
      min-height: var(--sf-touch);
      border: 1px solid var(--sf-border);
      border-radius: var(--sf-control-radius, 12px);
      padding: 10px 14px;
      background: var(--sf-control-bg, #f2f4f7);
      width: 100%;
      font: inherit;
      font-weight: 500;
      color: var(--sf-text);
      outline: none;
      transition: background-color 0.18s ease, border-color 0.18s ease, box-shadow 0.18s ease;
    }

    .field select:focus,
    .field input:focus,
    .search:focus {
      background: #fff;
      border-color: var(--sf-blue);
      box-shadow: var(--sf-control-focus, 0 0 0 4px rgba(1, 118, 211, 0.16));
    }

    .primary {
      width: 100%;
      min-height: 48px;
      border: none;
      border-radius: 980px;
      background: linear-gradient(180deg, #1b8aef 0%, var(--sf-blue) 100%);
      color: #fff;
      font-weight: 700;
      letter-spacing: -0.01em;
      cursor: pointer;
      box-shadow: 0 1px 2px rgba(1, 118, 211, 0.28);
    }

    .ghost {
      border: none;
      background: transparent;
      color: var(--sf-link);
      cursor: pointer;
      min-height: var(--sf-touch);
      padding: 8px 12px;
    }

    .danger-text {
      color: var(--sf-danger);
      font-size: 13px;
    }

    /* —— App Launcher —— */
    .launcher {
      padding: 16px;
      width: 100%;
      max-width: 960px;
      margin: 0 auto;
    }

    .launcher h2 {
      margin: 0 0 12px;
      font-size: 20px;
    }

    .app-grid {
      display: grid;
      grid-template-columns: repeat(3, minmax(0, 1fr));
      gap: 12px;
      margin-top: 16px;
    }

    .app-tile {
      border: 1px solid var(--sf-border);
      background: var(--sf-surface);
      border-radius: 12px;
      padding: 16px 8px;
      min-height: 104px;
      display: flex;
      flex-direction: column;
      align-items: center;
      justify-content: center;
      gap: 10px;
      cursor: pointer;
      text-align: center;
    }

    .app-tile:active {
      transform: scale(0.98);
    }

    .app-icon {
      width: 40px;
      height: 40px;
      border-radius: 8px;
      display: grid;
      place-items: center;
      color: #fff;
      font-weight: 800;
      font-size: 16px;
      overflow: hidden;
      flex-shrink: 0;
      background: transparent;
    }

    .app-icon.has-img {
      background: #fff;
      border: 1px solid var(--sf-border);
    }

    .app-icon img {
      width: 32px;
      height: 32px;
      max-width: 32px;
      max-height: 32px;
      object-fit: contain;
      object-position: center;
      image-rendering: auto;
    }

    .metric-grid {
      display: grid;
      grid-template-columns: repeat(3, minmax(0, 1fr));
      gap: 8px;
    }

    .metric-cell {
      background: #fff;
      border: 1px solid var(--sf-border);
      border-radius: 4px;
      padding: 12px 8px;
      text-align: center;
    }

    .metric-cell strong {
      display: block;
      font-size: 22px;
      font-weight: 700;
      color: var(--sf-blue);
      line-height: 1.2;
    }

    .metric-cell span {
      font-size: 11px;
      color: var(--sf-muted);
      margin-top: 2px;
      display: block;
    }

    .sf-empty {
      padding: 28px 16px;
      text-align: center;
      color: var(--sf-muted);
      font-size: 13px;
      line-height: 1.45;
    }

    .sf-empty strong {
      display: block;
      color: var(--sf-text);
      font-size: 14px;
      font-weight: 700;
      margin-bottom: 6px;
    }

    .standin-note {
      display: none;
    }

    .app-tile span {
      font-size: 12px;
      font-weight: 600;
      line-height: 1.2;
    }

    /* —— Home / FlexiPage —— */
    .page {
      padding: 12px clamp(12px, 2.5vw, 24px);
      width: 100%;
      max-width: min(1100px, 100%);
      margin: 0 auto;
      min-width: 0;
    }

    /* Object lists: use full main-pane width; rows fill the content column */
    .page.crmhub-list {
      max-width: none;
      width: 100%;
    }

    .page.crmhub-list .list-chrome .slds-input,
    .page.crmhub-list .list-chrome input[type='search'] {
      width: 100%;
      max-width: 100%;
      min-width: 0;
    }

    .page.crmhub-list .calendar-day,
    .page.crmhub-list .card-grid,
    .page.crmhub-list .kanban-board {
      width: 100%;
      min-width: 0;
    }

    .regions {
      display: flex;
      flex-direction: column;
      gap: 12px;
    }

    .region-grid {
      display: flex;
      flex-direction: column;
      gap: 12px;
    }

    .home-flexi {
      display: flex;
      flex-direction: column;
      gap: 16px;
    }

    .home-flexi-top,
    .home-flexi-main,
    .home-flexi-side,
    .regions {
      display: flex;
      flex-direction: column;
      gap: 16px;
      min-width: 0;
    }

    .home-flexi-body {
      display: flex;
      flex-direction: column;
      gap: 16px;
    }

    .home-flexi-body.has-sidebar {
      display: grid;
      grid-template-columns: minmax(0, 1.75fr) minmax(280px, 1fr);
      gap: 16px;
      align-items: start;
    }

    @media (max-width: 900px) {
      .home-flexi-body.has-sidebar {
        grid-template-columns: 1fr;
      }
    }

    .comp-card {
      background: var(--sf-surface);
      border: 1px solid var(--sf-border);
      border-radius: 4px;
      overflow: hidden;
      box-shadow: 0 1px 2px rgba(0, 0, 0, 0.05);
    }

    .comp-card header {
      padding: 10px 14px;
      border-bottom: 1px solid #e5e5e5;
      font-size: 13px;
      font-weight: 700;
      color: var(--sf-text);
      text-transform: none;
      letter-spacing: 0;
      background: #fff;
    }

    .comp-card header::before {
      content: '';
      display: inline-block;
      width: 3px;
      height: 12px;
      background: var(--sf-blue);
      border-radius: 1px;
      margin-right: 8px;
      vertical-align: -1px;
    }

    .comp-card .body-pad {
      padding: 0;
      background: #fff;
    }

    .comp-card .body-pad > .row:last-child,
    .comp-card .body-pad > button.row:last-child {
      border-bottom: none;
    }

    .comp-card .body-pad .metric-grid,
    .comp-card .body-pad .sf-empty,
    .comp-card .body-pad .rich-text,
    .comp-card .body-pad .lwc-host {
      padding: 12px 14px;
    }

    .comp-card .cta-row {
      padding: 10px 14px 14px;
      border-top: 1px solid #f3f3f3;
    }

    .lwc-host {
      min-height: 48px;
    }

    .lwc-missing {
      padding: 16px;
      background: #fff;
      color: var(--sf-muted);
      font-size: 13px;
    }

    .rich-text {
      font-size: 14px;
      line-height: 1.45;
      color: var(--sf-text);
    }

    /* —— List —— */
    .list-toolbar {
      display: flex;
      align-items: center;
      justify-content: space-between;
      gap: 8px;
      margin-bottom: 10px;
    }

    .list-toolbar h2 {
      margin: 0;
      font-size: 18px;
    }

    .list-chrome {
      display: flex;
      flex-direction: column;
      gap: 10px;
      margin-bottom: 12px;
    }

    .list-chrome-row {
      display: flex;
      flex-wrap: wrap;
      align-items: center;
      gap: 8px;
      width: 100%;
      min-width: 0;
    }

    .list-chrome-row .view-mode-toggle {
      flex: 0 1 auto;
      max-width: 100%;
      overflow-x: auto;
      -webkit-overflow-scrolling: touch;
    }

    .list-view-select {
      min-height: 36px;
      border: 1px solid var(--sf-border);
      border-radius: 8px;
      padding: 6px 10px;
      background: #fff;
      font-size: 13px;
      max-width: 100%;
      flex: 1 1 160px;
    }

    .lv-picker {
      position: relative;
      flex: 1 1 180px;
      min-width: 0;
    }

    .lv-picker-trigger {
      width: 100%;
      min-height: 36px;
      border: 1px solid var(--sf-border);
      border-radius: 8px;
      padding: 6px 10px;
      background: #fff;
      font-size: 13px;
      text-align: left;
      display: flex;
      align-items: center;
      justify-content: space-between;
      gap: 8px;
      cursor: pointer;
    }

    .lv-picker-menu {
      position: absolute;
      z-index: 30;
      top: calc(100% + 4px);
      left: 0;
      right: 0;
      max-height: 280px;
      overflow: auto;
      background: #fff;
      border: 1px solid var(--sf-border);
      border-radius: 10px;
      box-shadow: 0 8px 24px rgba(15, 23, 42, 0.12);
      padding: 4px;
    }

    .lv-option {
      display: flex;
      align-items: center;
      gap: 2px;
      border-radius: 8px;
    }

    .lv-option.active {
      background: #eef4ff;
    }

    .lv-option .lv-select {
      flex: 1;
      min-width: 0;
      text-align: left;
      border: none;
      background: transparent;
      padding: 8px 10px;
      font-size: 13px;
      cursor: pointer;
    }

    .lv-icon-btn {
      width: 32px;
      height: 32px;
      border: none;
      background: transparent;
      border-radius: 6px;
      cursor: pointer;
      color: var(--sf-muted);
      font-size: 15px;
      line-height: 1;
      flex-shrink: 0;
    }

    .lv-icon-btn.on {
      color: #0b5cab;
      font-weight: 700;
    }

    .lv-icon-btn:hover {
      background: #f3f6fb;
    }

    .cal-picker-backdrop {
      position: fixed;
      inset: 0;
      background: rgba(15, 23, 42, 0.35);
      z-index: 80;
      display: grid;
      place-items: center;
      padding: 16px;
    }

    .cal-picker {
      width: min(420px, 100%);
      background: #fff;
      border-radius: 12px;
      padding: 16px;
      border: 1px solid var(--sf-border);
    }

    .cal-picker h3 {
      margin: 0 0 6px;
      font-size: 16px;
    }

    .cal-picker p {
      margin: 0 0 12px;
      color: var(--sf-muted);
      font-size: 13px;
    }

    .cal-picker select {
      width: 100%;
      min-height: 40px;
      margin-bottom: 12px;
      border: 1px solid var(--sf-border);
      border-radius: 8px;
      padding: 8px 10px;
      background: #fff;
    }

    .cal-picker-actions {
      display: flex;
      justify-content: flex-end;
      gap: 8px;
    }

    a.lookup-link,
    button.lookup-link {
      color: var(--sf-blue);
      background: none;
      border: none;
      padding: 0;
      font: inherit;
      font-weight: 600;
      cursor: pointer;
      text-align: left;
      text-decoration: underline;
      text-underline-offset: 2px;
    }

    .field-readonly {
      display: block;
      min-height: 36px;
      padding: 8px 0;
      font-size: 14px;
      color: var(--sf-text);
    }

    .view-mode-toggle {
      display: inline-flex;
      border: 1px solid var(--sf-border);
      border-radius: 8px;
      overflow: hidden;
      background: #fff;
      flex-shrink: 1;
      min-width: 0;
    }

    .view-mode-toggle button {
      border: none;
      background: transparent;
      padding: 8px 10px;
      font-size: 12px;
      font-weight: 600;
      color: var(--sf-muted);
      cursor: pointer;
      min-height: 36px;
      min-width: 0;
      flex: 1 1 auto;
      white-space: nowrap;
    }

    .view-mode-toggle button.active {
      background: var(--sf-blue);
      color: #fff;
    }

    .card-grid {
      display: grid;
      grid-template-columns: repeat(auto-fill, minmax(160px, 1fr));
      gap: 10px;
    }

    .record-card {
      border: 1px solid var(--sf-border);
      border-radius: 10px;
      background: #fff;
      padding: 14px 12px;
      text-align: left;
      cursor: pointer;
      min-height: 88px;
      display: flex;
      flex-direction: column;
      gap: 8px;
    }

    .record-card strong {
      font-size: 14px;
      line-height: 1.3;
    }

    .record-card small {
      color: var(--sf-muted);
      font-size: 12px;
    }

    .calendar-day {
      margin-bottom: 14px;
    }

    .calendar-day h3 {
      margin: 0 0 8px;
      font-size: 13px;
      color: var(--sf-muted);
      font-weight: 700;
      text-transform: uppercase;
      letter-spacing: 0.03em;
    }

    .kanban-board {
      display: flex;
      gap: 10px;
      overflow-x: auto;
      padding-bottom: 8px;
      -webkit-overflow-scrolling: touch;
    }

    .kanban-col {
      flex: 0 0 220px;
      background: #f3f3f3;
      border-radius: 10px;
      padding: 8px;
      max-height: min(70vh, 640px);
      overflow: auto;
    }

    .kanban-col h3 {
      margin: 4px 6px 10px;
      font-size: 12px;
      font-weight: 700;
      color: var(--sf-muted);
    }

    .kanban-col .row {
      margin-bottom: 6px;
    }

    .list-table {
      width: 100%;
      border-collapse: collapse;
      background: #fff;
      border: 1px solid var(--sf-border);
      border-radius: 8px;
      overflow: hidden;
      font-size: 13px;
    }

    .list-table th,
    .list-table td {
      text-align: left;
      padding: 10px 12px;
      border-bottom: 1px solid #f0f0f0;
    }

    .list-table th {
      background: #fafaf9;
      color: var(--sf-muted);
      font-weight: 600;
      font-size: 11px;
      text-transform: uppercase;
      letter-spacing: 0.03em;
    }

    .list-table tr {
      cursor: pointer;
    }

    .list-table tr:hover td {
      background: #f7f9fc;
    }

    .top-search-wrap {
      position: relative;
      flex: 1 1 140px;
      max-width: 320px;
      min-width: 0;
    }

    .top-search {
      width: 100%;
      min-height: 36px;
      border: 1px solid var(--sf-border);
      border-radius: 18px;
      padding: 6px 12px 6px 34px;
      background: #fff url("data:image/svg+xml,%3Csvg xmlns='http://www.w3.org/2000/svg' width='14' height='14' viewBox='0 0 24 24' fill='none' stroke='%23706e6b' stroke-width='2'%3E%3Ccircle cx='11' cy='11' r='7'/%3E%3Cpath d='M20 20l-3-3'/%3E%3C/svg%3E")
        12px center no-repeat;
      font-size: 13px;
    }

    .search-dropdown {
      position: absolute;
      top: calc(100% + 4px);
      left: 0;
      right: 0;
      z-index: 40;
      background: #fff;
      border: 1px solid var(--sf-border);
      border-radius: 10px;
      box-shadow: 0 8px 24px rgba(0, 0, 0, 0.12);
      max-height: 320px;
      overflow: auto;
    }

    .search-dropdown button {
      display: flex;
      gap: 10px;
      width: 100%;
      text-align: left;
      border: none;
      border-bottom: 1px solid #f3f3f3;
      background: #fff;
      padding: 10px 12px;
      cursor: pointer;
      align-items: center;
    }

    .search-dropdown button strong {
      display: block;
      font-size: 13px;
    }

    .search-dropdown button small {
      color: var(--sf-muted);
      font-size: 11px;
    }

    .search-dropdown .empty-hit {
      padding: 12px;
      color: var(--sf-muted);
      font-size: 13px;
    }

    /* Record modal */
    .record-modal-backdrop {
      position: fixed;
      inset: 0;
      z-index: 80;
      background: rgba(8, 7, 7, 0.45);
      display: flex;
      align-items: stretch;
      justify-content: center;
      padding: 0;
    }

    .record-modal {
      background: var(--sf-bg);
      width: 100%;
      max-width: 100%;
      height: 100%;
      max-height: 100%;
      display: flex;
      flex-direction: column;
      overflow: hidden;
      box-shadow: 0 12px 40px rgba(0, 0, 0, 0.25);
    }

    .visit-shell-overlay {
      position: fixed;
      inset: 0;
      bottom: calc(56px + var(--safe-bottom, 0px));
      z-index: 85;
      background: var(--sf-bg);
      display: flex;
      flex-direction: column;
      overflow: hidden;
    }

    .clm-player-overlay {
      position: fixed;
      inset: 0;
      bottom: calc(56px + var(--safe-bottom, 0px));
      z-index: 95;
      background: var(--sf-bg);
      display: flex;
      flex-direction: column;
      overflow: hidden;
    }

    .clm-player-overlay-body {
      flex: 1;
      overflow: auto;
      min-height: 0;
    }

    .visit-shell-overlay-header {
      display: flex;
      align-items: center;
      justify-content: space-between;
      gap: 8px;
      min-height: 52px;
      padding: 8px 12px;
      border-bottom: 1px solid var(--sf-border);
      background: #fff;
      flex-shrink: 0;
    }

    .visit-shell-overlay-body {
      flex: 1;
      overflow: auto;
      padding: 0;
    }

    .record-modal-header {
      display: flex;
      align-items: center;
      gap: 8px;
      min-height: 52px;
      padding: 8px 12px;
      border-bottom: 1px solid var(--sf-border);
      background: #fff;
      flex-shrink: 0;
    }

    .record-modal-header h2 {
      margin: 0;
      font-size: 16px;
      flex: 1;
      min-width: 0;
      overflow: hidden;
      text-overflow: ellipsis;
      white-space: nowrap;
    }

    .record-modal-close {
      border: none;
      background: transparent;
      font-size: 22px;
      line-height: 1;
      width: 40px;
      height: 40px;
      border-radius: 8px;
      cursor: pointer;
      color: var(--sf-text);
    }

    .record-modal-body {
      flex: 1;
      overflow: auto;
      padding: 12px;
      -webkit-overflow-scrolling: touch;
    }

    @media (min-width: 768px) {
      .record-modal-backdrop {
        align-items: center;
        padding: 24px;
      }

      .record-modal {
        width: min(920px, 94vw);
        height: min(88vh, 900px);
        max-height: 88vh;
        border-radius: 12px;
      }
    }

    .row {
      display: flex;
      align-items: center;
      gap: 12px;
      width: 100%;
      max-width: 100%;
      min-width: 0;
      text-align: left;
      background: #fff;
      border: 1px solid rgba(15, 23, 42, 0.06);
      border-radius: 12px;
      padding: 12px 14px;
      margin: 0 0 8px;
      cursor: pointer;
      min-height: var(--sf-touch);
      box-shadow: 0 1px 2px rgba(15, 23, 42, 0.04);
    }

    .row > div {
      flex: 1 1 auto;
      min-width: 0;
      overflow: hidden;
    }

    .row-icon {
      width: 32px;
      height: 32px;
      border-radius: 6px;
      display: grid;
      place-items: center;
      color: #fff;
      flex-shrink: 0;
      overflow: hidden;
    }

    .row-icon.has-img {
      background: #fff;
      border: 1px solid var(--sf-border);
    }

    .row-icon img,
    .row-icon .slds-glyph {
      display: block;
    }

    .row strong {
      display: block;
      font-size: 15px;
      overflow: hidden;
      text-overflow: ellipsis;
      white-space: nowrap;
    }

    .row small {
      display: block;
      color: var(--sf-muted);
      font-size: 12px;
      overflow: hidden;
      text-overflow: ellipsis;
      white-space: nowrap;
    }

    /* —— Record —— */
    .highlights {
      background: var(--sf-surface);
      border: 1px solid var(--sf-border);
      border-radius: 10px;
      padding: 16px;
      margin-bottom: 12px;
    }

    .highlights .obj {
      font-size: 12px;
      color: var(--sf-muted);
      text-transform: uppercase;
      letter-spacing: 0.04em;
    }

    .highlights h2 {
      margin: 4px 0 12px;
      font-size: 22px;
    }

    .hl-fields {
      display: grid;
      grid-template-columns: 1fr;
      gap: 10px;
      margin-bottom: 12px;
    }

    .hl-fields div span {
      display: block;
      font-size: 11px;
      color: var(--sf-muted);
    }

    .hl-fields div strong {
      font-size: 14px;
    }

    .actions {
      display: flex;
      flex-wrap: wrap;
      gap: 8px;
    }

    .actions button {
      border: 1px solid var(--sf-border);
      background: #fff;
      border-radius: 20px;
      padding: 8px 14px;
      cursor: pointer;
      color: var(--sf-link);
      font-weight: 600;
    }

    .path {
      display: flex;
      gap: 4px;
      overflow-x: auto;
      margin-bottom: 12px;
      padding-bottom: 4px;
    }

    .path-step {
      flex: 0 0 auto;
      background: var(--sf-path);
      color: #fff;
      padding: 8px 14px;
      font-size: 12px;
      font-weight: 600;
      clip-path: polygon(0 0, calc(100% - 10px) 0, 100% 50%, calc(100% - 10px) 100%, 0 100%, 10px 50%);
      padding-left: 18px;
    }

    .path-step.active {
      background: var(--sf-path-active);
    }

    .field-grid {
      display: grid;
      grid-template-columns: 1fr;
      gap: 14px;
    }

    .field-grid label {
      display: flex;
      flex-direction: column;
      gap: 8px;
      font-size: 13px;
      font-weight: 600;
      letter-spacing: -0.01em;
      color: var(--sf-muted);
    }

    .field-grid input,
    .field-grid select,
    .field-grid textarea {
      min-height: var(--sf-touch);
      border: 1px solid var(--sf-border);
      border-radius: var(--sf-control-radius, 12px);
      padding: 10px 14px;
      background: var(--sf-control-bg, #f2f4f7);
      font: inherit;
      font-weight: 500;
      color: var(--sf-text);
      outline: none;
      transition: background-color 0.18s ease, border-color 0.18s ease, box-shadow 0.18s ease;
    }

    .field-grid input:focus,
    .field-grid select:focus,
    .field-grid textarea:focus {
      background: #fff;
      border-color: var(--sf-blue);
      box-shadow: var(--sf-control-focus, 0 0 0 4px rgba(1, 118, 211, 0.16));
    }

    .field-grid input:disabled,
    .field-grid select:disabled,
    .field-grid textarea:disabled {
      background: #eef0f3;
      color: #64748b;
      opacity: 0.7;
    }

    .menu-list {
      background: var(--sf-surface);
      border: 1px solid var(--sf-border);
      border-radius: 12px;
      overflow: hidden;
    }

    .menu-list button {
      width: 100%;
      display: flex;
      align-items: center;
      justify-content: space-between;
      gap: 12px;
      padding: 14px 16px;
      border: none;
      border-bottom: 1px solid var(--sf-border);
      background: transparent;
      text-align: left;
      cursor: pointer;
      min-height: var(--sf-touch);
      font-size: 15px;
    }

    .menu-list button:last-child {
      border-bottom: none;
    }

    .empty {
      padding: 32px 16px;
      text-align: center;
      color: var(--sf-muted);
    }

    /* —— Initial sync overlay —— */
    .sync-overlay {
      position: fixed;
      inset: 0;
      z-index: 100;
      display: grid;
      place-items: center;
      padding: 24px;
      padding-top: calc(24px + var(--safe-top));
      padding-bottom: calc(24px + var(--safe-bottom));
      background: rgba(3, 45, 96, 0.55);
      backdrop-filter: blur(4px);
      pointer-events: all;
    }

    .sync-modal {
      width: min(100%, 360px);
      background: var(--sf-surface);
      border-radius: 28px;
      padding: 36px 28px 28px;
      text-align: center;
      box-shadow: 0 12px 40px rgba(0, 0, 0, 0.25);
      display: flex;
      flex-direction: column;
      align-items: center;
      gap: 14px;
    }

    .sync-modal h2 {
      margin: 0;
      font-size: 18px;
      color: var(--sf-blue-dark);
    }

    .sync-modal-status {
      margin: 0;
      font-size: 13px;
      color: var(--sf-muted);
      line-height: 1.4;
      max-height: 4.5em;
      overflow: hidden;
    }

    /* Material 3 indeterminate circular progress */
    .m3-circular {
      width: 48px;
      height: 48px;
      margin: 4px 0 8px;
    }
    .m3-circular svg {
      width: 48px;
      height: 48px;
      animation: m3-rotate 1.4s linear infinite;
    }
    .m3-circular .track {
      fill: none;
      stroke: #d8e6f8;
      stroke-width: 4;
    }
    .m3-circular .indicator {
      fill: none;
      stroke: #0176d3;
      stroke-width: 4;
      stroke-linecap: round;
      stroke-dasharray: 80, 200;
      stroke-dashoffset: 0;
      animation: m3-dash 1.4s ease-in-out infinite;
    }
    @keyframes m3-rotate {
      to {
        transform: rotate(360deg);
      }
    }
    @keyframes m3-dash {
      0% {
        stroke-dasharray: 1, 200;
        stroke-dashoffset: 0;
      }
      50% {
        stroke-dasharray: 100, 200;
        stroke-dashoffset: -15;
      }
      100% {
        stroke-dasharray: 100, 200;
        stroke-dashoffset: -120;
      }
    }

    .sync-spinner {
      width: 36px;
      height: 36px;
      border: 3px solid #d8e6f8;
      border-top-color: var(--sf-blue);
      border-radius: 50%;
      animation: osr-spin 0.8s linear infinite;
      margin-top: 4px;
    }

    @keyframes osr-spin {
      to {
        transform: rotate(360deg);
      }
    }


    @media (min-width: 480px) {
      .app-grid {
        grid-template-columns: repeat(4, minmax(0, 1fr));
      }
    }

    @media (min-width: 768px) {
      :host {
        height: 100%;
        height: 100dvh;
        max-height: 100dvh;
        overflow: hidden;
      }

      .shell {
        grid-template-rows: auto 1fr;
        height: 100%;
        height: 100dvh;
        max-height: 100dvh;
        overflow: hidden;
      }

      .body {
        overflow: hidden;
        min-height: 0;
      }

      /* Launcher has no rail/main-pane — body itself must scroll. */
      .body:not(.has-bottom) {
        overflow: auto;
        -webkit-overflow-scrolling: touch;
      }

      .body.has-bottom {
        padding-bottom: 0;
      }

      .bottom-nav {
        display: none;
      }

      .layout-wide {
        display: grid;
        grid-template-columns: var(--sf-rail) minmax(0, 1fr);
        height: 100%;
        min-height: 0;
        width: 100%;
      }

      .rail {
        display: flex;
        flex-direction: column;
        align-items: center;
        align-self: stretch;
        gap: 8px;
        padding: 12px 8px;
        background: #032d60;
        color: #fff;
        height: 100%;
        min-height: 0;
        overflow-y: auto;
        -webkit-overflow-scrolling: touch;
      }

      .rail button {
        width: 56px;
        min-height: 56px;
        border: none;
        border-radius: 10px;
        background: transparent;
        color: #fff;
        display: flex;
        flex-direction: column;
        align-items: center;
        justify-content: center;
        gap: 4px;
        font-size: 10px;
        cursor: pointer;
        padding: 6px;
      }

      .rail button.active {
        background: rgba(255, 255, 255, 0.18);
      }

      .rail .nav-glyph {
        width: 32px;
        height: 32px;
        border-radius: 6px;
        display: grid;
        place-items: center;
        background: transparent;
        overflow: hidden;
        box-shadow: 0 1px 2px rgba(0, 0, 0, 0.2);
      }

      .rail .nav-glyph.has-img {
        background: #fff;
      }

      .rail button.active .nav-glyph {
        box-shadow: 0 0 0 2px rgba(255, 255, 255, 0.55);
      }

      .main-pane {
        min-width: 0;
        min-height: 0;
        height: 100%;
        width: 100%;
        max-width: 100%;
        background: var(--sf-bg);
        overflow-x: hidden;
        overflow-y: auto;
        -webkit-overflow-scrolling: touch;
      }

      .launcher {
        max-width: none;
        width: 100%;
        padding: 24px 28px;
      }

      .app-grid {
        grid-template-columns: repeat(5, minmax(0, 1fr));
      }

      .hl-fields {
        grid-template-columns: repeat(2, minmax(0, 1fr));
      }

      .field-grid {
        grid-template-columns: repeat(2, minmax(0, 1fr));
      }

      .region-grid.has-sidebar {
        display: grid;
        grid-template-columns: 1.6fr 1fr;
        gap: 12px;
        align-items: start;
      }

      .page {
        width: 100%;
        max-width: none;
        padding: 16px clamp(16px, 2vw, 28px);
      }

      .page.crmhub-list {
        padding-right: 0;
      }

      .page.crmhub-list .list-toolbar,
      .page.crmhub-list .list-chrome,
      .page.crmhub-list .empty {
        padding-right: clamp(16px, 2vw, 28px);
      }

      .page.crmhub-list .calendar-day h3 {
        padding-right: clamp(16px, 2vw, 28px);
      }

      /* Calendar rows bleed to the right edge of the pane */
      .page.crmhub-list .calendar-day .row {
        border-radius: 12px 0 0 12px;
        border-right: none;
      }

      .page.crmhub-list .card-grid,
      .page.crmhub-list .kanban-board,
      .page.crmhub-list .list-table {
        margin-right: clamp(16px, 2vw, 28px);
        width: auto;
        max-width: calc(100% - clamp(16px, 2vw, 28px));
      }
    }

    /* Phone: keep equal gutters; rows stay fully contained */
    @media (max-width: 767px) {
      .topbar {
        gap: 8px;
        padding: 8px 10px;
        min-width: 0;
      }

      .top-search-wrap {
        flex: 1 1 96px;
        max-width: none;
      }

      .page,
      .page.crmhub-list {
        padding: 12px;
        max-width: 100%;
      }

      .page.crmhub-list .calendar-day .row {
        border-radius: 12px;
        border-right: 1px solid rgba(15, 23, 42, 0.06);
      }

      .page.crmhub-list .card-grid,
      .page.crmhub-list .kanban-board,
      .page.crmhub-list .list-table {
        margin-right: 0;
        width: 100%;
        max-width: 100%;
      }

      .list-chrome-row .lv-picker {
        flex: 1 1 100%;
      }

      .list-chrome-row .view-mode-toggle {
        flex: 1 1 100%;
        width: 100%;
      }

      .view-mode-toggle button {
        padding: 8px 6px;
        font-size: 11px;
      }
    }

    @media (min-width: 1024px) {
      .app-grid {
        grid-template-columns: repeat(6, minmax(0, 1fr));
      }

      .split.master-detail {
        display: grid;
        grid-template-columns: minmax(280px, 38%) minmax(0, 62%);
        height: 100%;
        min-height: 0;
        max-height: 100%;
        width: 100%;
      }

      .split-list {
        border-right: 1px solid var(--sf-border);
        overflow: auto;
        height: 100%;
        max-height: 100%;
        min-height: 0;
        padding: 12px;
        background: #fafaf9;
      }

      .split-detail {
        overflow: auto;
        height: 100%;
        max-height: 100%;
        min-height: 0;
        min-width: 0;
        width: 100%;
      }
    }
  `];

  connectedCallback() {
    super.connectedCallback();
    this.applyLoginUrlFromParams();
    this.updateFormFactor();
    window.addEventListener('online', this.onOnline);
    window.addEventListener('offline', this.onOffline);
    window.addEventListener('keydown', this.onKeyDown);
    window.addEventListener('resize', this.onResize);
    this.ensureBridge();
    void this.boot();
  }

  /** Prefer ?domain= / ?loginUrl= so OAuth hits My Domain (org themed login). */
  private applyLoginUrlFromParams() {
    if (typeof window === 'undefined') return;
    const fromParams = loginUrlFromPageParams(window.location.search);
    if (!fromParams) return;
    this.loginUrl = fromParams;
    this.loginEnv = isStandardSalesforceLogin(fromParams)
      ? fromParams.replace(/\/$/, '').toLowerCase() === SANDBOX_LOGIN
        ? 'sandbox'
        : 'production'
      : 'custom';
    this.customDomainInput = extractMyDomainLabel(fromParams);
  }

  private setLoginEnvironment(env: 'production' | 'sandbox' | 'custom') {
    this.loginEnv = env;
    if (env === 'production') {
      this.loginUrl = PRODUCTION_LOGIN;
      return;
    }
    if (env === 'sandbox') {
      this.loginUrl = SANDBOX_LOGIN;
      return;
    }
    const next = myDomainLoginUrlFromLabel(this.customDomainInput);
    if (next) this.loginUrl = next;
  }

  private applyCustomDomainInput(raw: string) {
    // Users type only the label (abcd); strip accidental full-host paste
    this.customDomainInput = extractMyDomainLabel(raw);
    this.loginEnv = 'custom';
    const next = myDomainLoginUrlFromLabel(this.customDomainInput);
    if (next) this.loginUrl = next;
  }

  disconnectedCallback() {
    super.disconnectedCallback();
    window.removeEventListener('online', this.onOnline);
    window.removeEventListener('offline', this.onOffline);
    window.removeEventListener('keydown', this.onKeyDown);
    window.removeEventListener('resize', this.onResize);
    this.stopBackgroundSync();
    this.removeDeepLink?.();
    this.unsubLocation?.();
    this.detachBridge?.();
    void repLocationTracker.stop();
  }

  private ensureBridge() {
    this.detachBridge?.();
    const self = this;
    this.bridgeHost = new BridgeHost(
      createShellBridgeHandler({
        get db() {
          return self.db;
        },
        get online() {
          return self.online;
        },
        liveApex: true,
        openRecord: (objectApi, id) => void self.openRecord(objectApi, id),
        openVisitShell: (id) => {
          self.visitDetailId = null;
          self.modalOpen = false;
          self.record = null;
          self.visitShellId = id;
        },
        openPlanner: () => {
          const tab = self.tabs.find(
            (t) =>
              t.developerName === 'Field_Rep_Planner' ||
              t.tab.pageDeveloperName === 'Field_Rep_Planner' ||
              t.tab.lwcBundle?.includes('fieldRepPlanner')
          );
          if (tab) void self.openAppTab(tab);
        },
        openTab: (developerName) => {
          const tab = self.tabs.find((t) => t.developerName === developerName);
          if (tab) void self.openAppTab(tab);
        },
        toast: (d) => {
          self.toastMessage = [d.title, d.message].filter(Boolean).join(' — ') || 'Notification';
          window.setTimeout(() => {
            self.toastMessage = null;
          }, 3200);
        },
        confirm: async (message) => window.confirm(message),
        onResize: (bundle, height) => {
          const next = Math.max(80, Math.round(height));
          if (self.iframeHeights[bundle] === next) return;
          self.iframeHeights = { ...self.iframeHeights, [bundle]: next };
        },
        invokeLiveApex: async (method) => {
          if (!self.db || !self.tokens) throw new Error('Not authenticated');
          const short = method.replace(/^.*\//, '');
          const cacheKey =
            APEX_BINDING_TO_CACHE_KEY[short] ?? APEX_BINDING_TO_CACHE_KEY[method] ?? null;
          const { engine } = await createLiveSyncEngine(self.db, self.tokens);
          await engine.pullApexCache(cacheKey ? { keys: [cacheKey] } : undefined);
          if (!cacheKey) return null;
          const cached = await getApexPayload(self.db, cacheKey);
          let payload: unknown = cached?.payload ?? null;
          if (
            cacheKey === 'officeMessages' &&
            payload &&
            typeof payload === 'object' &&
            !Array.isArray(payload) &&
            Array.isArray((payload as { messages?: unknown }).messages)
          ) {
            payload = (payload as { messages: unknown[] }).messages;
          }
          void self.refreshApexSnapshot();
          return payload;
        }
      })
    );
    this.detachBridge = this.bridgeHost.attach(window);
  }

  private onOnline = () => {
    this.online = true;
    void this.refreshApexSnapshot();
    void repLocationTracker.flushToOutbox().then(() => this.refreshPending());
    this.startBackgroundSync();
    // Catch up as soon as connectivity returns
    void this.runSync({ background: true });
  };
  private onOffline = () => {
    this.online = false;
    this.stopBackgroundSync();
  };
  private onResize = () => this.updateFormFactor();
  private updateFormFactor() {
    if (typeof window === 'undefined') return;
    this.formFactor = formFactorFromWidth(window.innerWidth);
  }
  private onKeyDown = (e: KeyboardEvent) => {
    if (e.key === 'Escape') {
      if (this.modalOpen) {
        e.preventDefault();
        this.closeRecordModal();
      } else if (this.searchOpen) {
        this.searchOpen = false;
      }
    }
  };

  private async boot() {
    const db = await openDatabase();
    this.db = db;
    await this.loadPlannerCollections();
    this.unsubLocation = repLocationTracker.subscribe((s: LocationTrackerState) => {
      this.locationState = s;
    });
    await repLocationTracker.init(db);
    this.removeDeepLink = installOAuthDeepLinkHandler(
      db,
      async (tokens) => {
        this.tokens = tokens;
        await this.afterLogin(tokens);
      },
      (message) => {
        this.status = `Login failed: ${message}`;
      }
    );

    if (typeof window !== 'undefined' && window.location.pathname.includes('/oauth/callback')) {
      try {
        this.tokens = await completeSalesforceLogin(db, window.location.href);
        window.history.replaceState({}, '', '/');
        await this.afterLogin(this.tokens);
        return;
      } catch (e) {
        this.syncMode = 'logged-out';
        this.status = `Login failed: ${e instanceof Error ? e.message : String(e)}`;
        window.history.replaceState({}, '', '/');
        return;
      }
    }

    this.tokens = await loadSession(db);
    if (this.tokens) {
      await this.afterLogin(this.tokens);
    } else {
      this.syncMode = 'logged-out';
      this.status = 'Sign in to Salesforce';
    }
  }

  private async afterLogin(tokens: TokenSet) {
    this.userLabel = tokens.instanceUrl.replace(/^https?:\/\//, '').split('.')[0] ?? 'SF';
    const saved =
      (await Preferences.get({ key: CURRENT_APP_KEY })).value ??
      (this.db ? await kvGet(this.db, CURRENT_APP_KEY) : null);
    this.currentApp = saved;
    this.initialSyncPending = this.apps.length === 0;
    this.syncFailedMessage = null;
    this.status = this.formatSyncingStatus();
    this.route = { kind: 'launcher' };
    await this.runSync({ initial: true });
    await this.refreshNav();
    if (!this.apps.length) {
      this.route = { kind: 'launcher' };
      if (!this.syncFailedMessage) {
        this.syncFailedMessage =
          'No apps synced yet. Check Sync Pack profile / network and tap Retry.';
      }
      this.status = this.syncFailedMessage;
      return;
    }
    this.startBackgroundSync();
    if (!this.currentApp) {
      this.route = { kind: 'launcher' };
      this.status = 'Choose an app';
    } else {
      this.route = { kind: 'home' };
      await this.loadHome();
      this.status = `Synced (${this.syncMode})`;
    }
  }

  private async refreshNav() {
    if (!this.db) return;
    const nav = await loadNavigation(this.db, this.currentApp);
    this.apps = nav.apps;
    this.tabs = nav.tabs as typeof this.tabs;
    if (this.currentApp) {
      const app = this.apps.find((a) => a.developerName === this.currentApp);
      this.appLabel = app?.label ?? this.currentApp;
    }
    this.pendingCount = (await listPendingOutbox(this.db)).length;
    this.conflicts = await getConflicts(this.db);
    void this.refreshSupportLogs();
  }

  private async refreshPending() {
    if (!this.db) return;
    this.pendingCount = (await listPendingOutbox(this.db)).length;
  }

  private async refreshSupportLogs() {
    if (!this.db) return;
    this.supportLogs = await listLogs(this.db, { category: 'sync', limit: 100 });
    this.supportLogCount = await countLogs(this.db, 'sync');
  }

  private formatSyncStatus(
    channels: Record<string, { ok: boolean; count: number; error?: string }>,
    mode: string
  ): string {
    const failed = Object.entries(channels)
      .filter(([, c]) => !c.ok)
      .map(([name, c]) => `${name}${c.error ? ` (${c.error.slice(0, 80)})` : ''}`);
    if (!failed.length) {
      const dataCount = channels.data?.count ?? 0;
      return `Synced (${mode}) · ${dataCount} records`;
    }
    const dataFail = failed.filter((f) => f.startsWith('data'));
    if (dataFail.length && channels.metadata?.ok) {
      return `Sync partial · ${dataFail.slice(0, 2).join('; ')}`;
    }
    return `Sync issues · ${failed.slice(0, 2).join('; ')}`;
  }

  /** Status line while sync is running: "Syncing in background… Accounts (3/8)". */
  private formatSyncingStatus(progress?: SyncProgress | null): string {
    const channel = progress?.channel?.trim();
    return channel ? `Syncing in background… ${channel}` : 'Syncing in background…';
  }

  private startBackgroundSync() {
    this.stopBackgroundSync();
    if (!this.tokens || !this.online) return;
    this.bgSyncTimer = setInterval(() => {
      if (!this.online || !this.tokens || this.syncing) return;
      void this.runSync({ background: true });
    }, BG_SYNC_INTERVAL_MS);
  }

  private stopBackgroundSync() {
    if (this.bgSyncTimer != null) {
      clearInterval(this.bgSyncTimer);
      this.bgSyncTimer = null;
    }
  }

  private async loadSuccessfulSyncCount() {
    if (!this.db) return;
    const raw = await kvGet(this.db, SYNC_SUCCESS_COUNT_KEY);
    const n = Number(raw ?? 0);
    this.successfulSyncCount = Number.isFinite(n) && n > 0 ? Math.floor(n) : 0;
  }

  private async bumpSuccessfulSyncCount(): Promise<number> {
    this.successfulSyncCount += 1;
    if (this.db) {
      await kvSet(this.db, SYNC_SUCCESS_COUNT_KEY, String(this.successfulSyncCount));
    }
    return this.successfulSyncCount;
  }

  private applySyncProgress(progress: SyncProgress) {
    this.syncProgress = progress;
    this.status = this.formatSyncingStatus(progress);
  }

  private renderSyncProgressBar() {
    const p = this.syncProgress;
    const determinate = !!p && p.total > 0;
    const pct = determinate ? Math.max(2, Math.min(100, Math.round((p!.current / p!.total) * 100))) : 0;
    return html`
      <div
        class="sync-progress-track"
        role="progressbar"
        aria-valuemin="0"
        aria-valuemax=${determinate ? p!.total : 100}
        aria-valuenow=${determinate ? p!.current : 0}
        aria-label=${this.formatSyncingStatus(p)}
      >
        <div
          class="sync-progress-fill ${determinate ? '' : 'indeterminate'}"
          style=${determinate ? `width:${pct}%` : ''}
        ></div>
      </div>
    `;
  }

  private async runSync(opts: { initial?: boolean; background?: boolean } = {}) {
    if (!this.db || !this.tokens) return;
    if (this.syncing) return;
    if (opts.background && !this.online) return;
    this.syncing = true;
    this.syncProgress = null;
    this.syncFailedMessage = null;
    if (opts.initial || this.apps.length === 0) {
      this.initialSyncPending = true;
    }
    this.status = opts.background
      ? 'Background sync…'
      : this.formatSyncingStatus();
    const SYNC_TIMEOUT_MS = opts.background ? 120_000 : 180_000;
    try {
      if (!this.successfulSyncCount) await this.loadSuccessfulSyncCount();
      const { engine, mode } = await createLiveSyncEngine(this.db, this.tokens);
      this.syncMode = mode;
      const syncPromise = engine.fullSync({
        onProgress: (progress) => {
          if (!opts.background) this.applySyncProgress(progress);
          else {
            this.syncProgress = progress;
            const channel = progress.channel?.trim();
            this.status = channel ? `Background sync… ${channel}` : 'Background sync…';
          }
        },
        afterMetadata: async () => {
          await this.refreshNav();
          if (this.apps.length > 0) {
            this.syncFailedMessage = null;
          }
          if (!opts.background && !this.syncProgress) {
            this.status = this.formatSyncingStatus({
              phase: 'metadata',
              channel: 'Apps',
              current: 1,
              total: 0
            });
          }
        }
      });
      const timeoutPromise = new Promise<never>((_, reject) => {
        setTimeout(
          () =>
            reject(
              new Error(
                opts.background
                  ? 'Background sync timed out — will retry'
                  : 'Sync timed out after 3 minutes — tap Retry'
              )
            ),
          SYNC_TIMEOUT_MS
        );
      });
      const result = await Promise.race([syncPromise, timeoutPromise]);
      await this.refreshNav();
      await this.refreshApexSnapshot();
      // Runtime-compile synced Tooling LWC sources into kv cache for iframe engine
      try {
        const bundles = [
          'c/homeOfficeMessages',
          'c/fieldRepHomeTodayPlan',
          'c/fieldRepHomeNextBestCustomer',
          'c/fieldRepHomeMetrics',
          'c/fieldRepPlanner',
          'c/visitCallShell',
          'c/repLocationPublisher'
        ];
        const { compiled, reports } = await compileSyncedLwcs(this.db, bundles);
        if (compiled > 0) {
          console.info(`[osr] compiled ${compiled} LWC bundle(s) for iframe engine`);
        }
        const blockers = reports.filter(
          (r) =>
            !isFidelityBundle(r.bundleName) &&
            (r.unresolved.length > 0 || (r.unsupportedLightningBase?.length ?? 0) > 0)
        );
        if (blockers.length) {
          console.info('[osr] LWC compatibility unresolved imports', blockers);
          this.lwcCompatSummary = `${blockers.length} synced LWC(s) need stubs: ${blockers
            .map((b) => b.bundleName.replace(/^c\//, ''))
            .slice(0, 4)
            .join(', ')}${blockers.length > 4 ? '…' : ''}`;
        } else {
          this.lwcCompatSummary = null;
        }
      } catch (e) {
        console.warn('[osr] LWC compile pass failed', e);
      }

      const successCount = await this.bumpSuccessfulSyncCount();
      let validationNote = '';
      if (successCount > 0 && successCount % VALIDATE_EVERY_N_SYNCS === 0) {
        this.status = 'Validating local ↔ Salesforce…';
        try {
          const report = await engine.validateLocalAgainstServer();
          const drift = report.issues.filter((i) => i.kind !== 'count_gap' && i.kind !== 'error');
          const errors = report.issues.filter((i) => i.kind === 'error');
          if (report.repaired > 0 || drift.length || errors.length) {
            validationNote = ` · validated (repaired ${report.repaired}${
              drift.length ? `, ${drift.length} drift` : ''
            }${errors.length ? `, ${errors.length} err` : ''})`;
            this.syncValidationSummary = `Integrity check #${successCount}: repaired ${report.repaired} · ${report.issues
              .slice(0, 3)
              .map((i) => `${i.objectApi}:${i.kind}`)
              .join(', ')}${report.issues.length > 3 ? '…' : ''}`;
            console.info('[osr] sync validation', report);
            window.setTimeout(() => {
              if (this.syncValidationSummary?.startsWith(`Integrity check #${successCount}`)) {
                this.syncValidationSummary = null;
              }
            }, 8000);
            // Push any re-queued drift immediately
            if (report.repaired > 0) {
              try {
                await engine.pushOutbox();
              } catch {
                /* next cycle */
              }
            }
          } else {
            validationNote = ' · validated OK';
            this.syncValidationSummary = `Integrity check #${successCount}: local matches Salesforce sample`;
            window.setTimeout(() => {
              if (this.syncValidationSummary?.startsWith(`Integrity check #${successCount}`)) {
                this.syncValidationSummary = null;
              }
            }, 5000);
          }
        } catch (e) {
          validationNote = ' · validation skipped';
          this.syncValidationSummary = `Integrity check failed: ${
            e instanceof Error ? e.message : String(e)
          }`;
          console.warn('[osr] sync validation failed', e);
        }
      }

      this.status = `${this.formatSyncStatus(result.pull.channels, mode)}${validationNote}${
        opts.background ? ' · auto' : ''
      }`;
      this.pendingCount = (await listPendingOutbox(this.db)).length;
      // Enrich local support logs with UI context (auto / outbox) for CloudAstick exports
      const failedChannels = Object.entries(result.pull.channels).filter(([, c]) => !c.ok);
      if (failedChannels.length && this.db) {
        const tags = [
          opts.background ? 'auto' : 'manual',
          `mode:${mode}`,
          `outbox ${this.pendingCount}`
        ];
        try {
          await appendLog(this.db, {
            category: 'sync',
            source: 'status',
            message: this.formatSyncStatus(result.pull.channels, mode),
            detail: {
              channels: Object.fromEntries(
                failedChannels.map(([name, c]) => [name, { error: c.error, count: c.count }])
              ),
              push: result.push
            },
            tags
          });
        } catch {
          /* ignore */
        }
      }
      if (result.push.failed > 0 || result.push.conflicts > 0) {
        try {
          await appendLog(this.db, {
            category: 'sync',
            source: 'outbox',
            message: `Push: ${result.push.synced} synced, ${result.push.failed} failed, ${result.push.conflicts} conflicts`,
            detail: result.push,
            tags: [opts.background ? 'auto' : 'manual', 'push']
          });
        } catch {
          /* ignore */
        }
      }
      void this.refreshSupportLogs();
      const metaFailed = result.pull.channels.metadata && !result.pull.channels.metadata.ok;
      if (this.apps.length === 0) {
        this.syncFailedMessage = metaFailed
          ? result.pull.channels.metadata?.error ?? 'Metadata sync failed'
          : 'No apps returned from Sync Pack. Tap Retry.';
      }
      if (this.online && this.tokens) this.startBackgroundSync();
    } catch (e) {
      const msg = e instanceof Error ? e.message : String(e);
      this.status = opts.background ? `Background sync: ${msg}` : `Sync failed: ${msg}`;
      if (!opts.background && this.apps.length === 0) this.syncFailedMessage = msg;
      if (this.db) {
        try {
          await appendLog(this.db, {
            category: 'sync',
            source: 'runSync',
            message: msg,
            detail: { background: !!opts.background, stack: e instanceof Error ? e.stack?.slice(0, 2000) : undefined },
            tags: [opts.background ? 'auto' : 'manual', 'exception']
          });
        } catch {
          /* ignore */
        }
        void this.refreshSupportLogs();
      }
      try {
        await this.refreshNav();
      } catch {
        /* ignore */
      }
    } finally {
      this.syncing = false;
      this.syncProgress = null;
      this.initialSyncPending = false;
    }
  }

  /** Full-screen overlay while first sync has no apps yet (or failed with Retry). */
  private showSyncOverlay(): boolean {
    if (!this.tokens) return false;
    if (this.apps.length > 0) return false;
    return this.syncing || this.initialSyncPending || !!this.syncFailedMessage;
  }

  private renderSyncOverlay() {
    if (!this.showSyncOverlay()) return nothing;
    const failed = !!this.syncFailedMessage && !this.syncing;
    return html`
      <div class="sync-overlay" role="dialog" aria-modal="true" aria-labelledby="sync-overlay-title">
        <div class="sync-modal">
          ${!failed
            ? html`
                <div class="m3-circular" aria-hidden="true">
                  <svg viewBox="0 0 48 48">
                    <circle class="track" cx="24" cy="24" r="20"></circle>
                    <circle class="indicator" cx="24" cy="24" r="20"></circle>
                  </svg>
                </div>
              `
            : nothing}
          <h2 id="sync-overlay-title">${failed ? 'Sync needs attention' : 'Setting up offline…'}</h2>
          <p class="sync-modal-status">
            ${failed
              ? this.syncFailedMessage
              : this.syncProgress?.channel
                ? this.syncProgress.channel
                : this.status || 'Connecting to Salesforce…'}
          </p>
          ${failed
            ? html`
                <button
                  class="primary"
                  style="width:auto;min-width:140px;margin-top:8px"
                  @click=${() => this.runSync({ initial: true })}
                >
                  Retry
                </button>
              `
            : nothing}
        </div>
      </div>
    `;
  }

  private async selectApp(developerName: string) {
    this.currentApp = developerName;
    await Preferences.set({ key: CURRENT_APP_KEY, value: developerName });
    if (this.db) await kvSet(this.db, CURRENT_APP_KEY, developerName);
    await this.refreshNav();
    this.route = { kind: 'home' };
    await this.loadHome();
  }

  private objectTabs(): TabRow[] {
    return this.tabs.filter((t) => {
      const typ = this.tabTypeOf(t);
      return typ === 'object' && Boolean(t.tab?.objectApi);
    });
  }

  /** All navigable tabs for the selected app (objects + FlexiPage/LWC custom tabs). */
  private appNavTabs(): TabRow[] {
    return this.tabs.filter((t) => {
      const dn = t.developerName.toLowerCase();
      if (dn === 'home' || dn.endsWith('_home_app') || dn === 'tab_home') return false;
      return true;
    });
  }

  private tabTypeOf(t: TabRow): string {
    if (t.tab.tabType) return t.tab.tabType;
    if (t.tab.lwcBundle) return 'lwc';
    if (t.tab.pageDeveloperName) return 'flexipage';
    if (t.tab.type === 'object' || (t.tab.objectApi && !t.tab.pageDeveloperName && !t.tab.lwcBundle)) {
      return 'object';
    }
    if (t.tab.type) return t.tab.type;
    if (t.developerName.endsWith('__c')) return 'object';
    return 'unknown';
  }

  private async refreshUsableLwcs(page: FlexiPageModel | null, extraBundles: string[] = []) {
    if (!this.db) return;
    const next = new Set<string>();
    const candidates = new Set<string>(extraBundles);
    for (const region of page?.regions ?? []) {
      for (const c of region.components) {
        const b = lwcBundleFromComponent(c);
        if (b) candidates.add(b);
      }
    }
    for (const b of candidates) {
      if (await hasUsableLwcBundle(this.db, b)) next.add(b);
    }
    this.usableLwc = next;
  }

  /** Known custom-tab → LWC when FlexiPage sync left a record-layout stub. */
  private knownTabLwcFallback(t: TabRow): string | null {
    const page = t.tab.pageDeveloperName ?? t.developerName;
    const map: Record<string, string> = {
      Field_Rep_Planner: 'c/fieldRepPlanner',
      Accounts_Tab: 'c/accountsTab',
      Request_Time_Off: 'c/timeOffSubmission',
      Time_Off_Submission: 'c/timeOffSubmission',
      CLM_Presentations: 'c/clmPresentationsHub'
    };
    if (t.tab.lwcBundle) return normalizeLwcBundleName(t.tab.lwcBundle);
    return map[t.developerName] ?? map[page] ?? null;
  }

  /** True when FlexiPage only has record chrome (highlights / fields / related). */
  private isRecordLayoutStub(page: FlexiPageModel | null): boolean {
    if (!page?.regions?.length) return true;
    let hasCustom = false;
    let hasRecordChrome = false;
    for (const region of page.regions) {
      for (const c of region.components) {
        const typ = c.type || '';
        if (lwcBundleFromComponent(c) || isCustomLwcType(typ)) hasCustom = true;
        if (
          typ === 'force:highlightsPanel' ||
          typ.includes('fieldSection') ||
          typ.includes('relatedList')
        ) {
          hasRecordChrome = true;
        }
      }
    }
    return !hasCustom && (hasRecordChrome || page.regions.every((r) => !r.components.length));
  }

  private async openAppTab(t: TabRow) {
    const token = ++this.navToken;
    this.dismissChromeOverlays({ keepClm: false });
    this.closeRecordModal({ keepRoute: true });
    const typ = this.tabTypeOf(t);
    // Only object tabs open list views — never FlexiPage/LWC with a stray objectApi
    if (typ === 'object' && t.tab.objectApi) {
      await this.openList(t.tab.objectApi, token);
      return;
    }
    if (typ === 'object' && !t.tab.pageDeveloperName && !t.tab.lwcBundle) {
      const api = t.tab.objectApi ?? t.developerName;
      await this.openList(api, token);
      return;
    }
    if (token !== this.navToken) return;
    this.route = { kind: 'tab', developerName: t.developerName };
    this.customTabFlexi = null;
    this.customTabLwc = null;
    this.customTabUnsupported = null;
    await this.loadCustomTab(t);
  }

  private async loadCustomTab(t: TabRow) {
    if (!this.db) return;
    const typ = this.tabTypeOf(t);
    this.status = t.label;
    this.customTabFidelityPlanner = false;

    const mountLwcTab = async (bundle: string) => {
      const b = normalizeLwcBundleName(bundle);
      if (isFidelityBundle(b)) {
        this.customTabLwc = b;
        this.customTabFlexi = null;
        this.customTabFidelityPlanner = b === 'c/fieldRepPlanner';
        if (b === 'c/fieldRepPlanner' && !this.plannerWeekStart) {
          this.plannerWeekStart = sundayWeekRange().weekStart;
        }
        await this.refreshApexSnapshot(
          b === 'c/fieldRepPlanner' ? { weekStart: this.plannerWeekStart || undefined } : undefined
        );
        return;
      }
      this.customTabLwc = b;
      this.customTabFlexi = null;
      await this.refreshUsableLwcs(null, [b]);
      await this.updateComplete;
      const host = this.renderRoot.querySelector(
        '[data-lwc-host="custom-tab-lwc"]'
      ) as HTMLElement | null;
      if (host) {
        try {
          const mounted = await mountLwc(this.db!, host, b, {});
          if (!mounted) {
            host.innerHTML = `<div class="sf-empty"><strong>LWC not synced</strong><div>${b}</div></div>`;
          }
        } catch (e) {
          host.innerHTML = `<div class="lwc-missing">${e instanceof Error ? e.message : String(e)}</div>`;
        }
      }
    };

    if (typ === 'lwc' && t.tab.lwcBundle) {
      await mountLwcTab(normalizeLwcBundleName(t.tab.lwcBundle));
      return;
    }
    if (typ === 'flexipage' || t.tab.pageDeveloperName) {
      const pageName = t.tab.pageDeveloperName ?? t.developerName;
      const raw = await getFlexiPage(this.db, pageName);
      const flexi = parseFlexiPage(raw);
      if (!flexi || this.isRecordLayoutStub(flexi)) {
        const fallback = this.knownTabLwcFallback(t);
        if (fallback) {
          await mountLwcTab(fallback);
          return;
        }
        if (!flexi) {
          this.customTabUnsupported = `FlexiPage “${pageName}” is not synced yet. Sync while online.`;
          return;
        }
      }
      this.customTabFlexi = flexi;
      await this.refreshUsableLwcs(this.customTabFlexi);
      await this.updateComplete;
      await this.mountPageLwcs(this.customTabFlexi, 'tab');
      return;
    }
    // Aura tabs that are really LWC (CLM) — try known fallback before giving up
    if (typ === 'aura' || typ === 'unknown' || typ === 'navigation') {
      const fallback = this.knownTabLwcFallback(t);
      if (fallback) {
        await mountLwcTab(fallback);
        return;
      }
    }
    if (typ === 'url' || typ === 'visualforce' || typ === 'aura') {
      this.customTabUnsupported = `“${t.label}” (${typ}) is not available offline.`;
      return;
    }
    this.customTabUnsupported = `“${t.label}” has no offline renderer yet.`;
  }

  private tabForObject(apiName: string): TabRow | undefined {
    return this.objectTabs().find((t) => t.tab.objectApi === apiName);
  }

  /** Prefer Visit-like objects, then Task/Event, else first object tab. */
  private resolveWorkObject(): ObjectRef | null {
    const tabs = this.objectTabs();
    const prefer = [
      'Visit__c',
      'Visit',
      'Task',
      'Event',
      'Case',
      'Opportunity',
      'Lead'
    ];
    for (const api of prefer) {
      const t = tabs.find((x) => x.tab.objectApi === api);
      if (t?.tab.objectApi) return { apiName: t.tab.objectApi, label: t.label };
    }
    const first = tabs[0];
    if (first?.tab.objectApi) return { apiName: first.tab.objectApi, label: first.label };
    return null;
  }

  /** Prefer Account when in app tabs; else first object that isn't the work object. */
  private resolveRecentObject(work: ObjectRef | null): ObjectRef | null {
    const tabs = this.objectTabs();
    const account = tabs.find((t) => t.tab.objectApi === 'Account');
    if (account?.tab.objectApi) return { apiName: 'Account', label: account.label };
    const other = tabs.find((t) => t.tab.objectApi && t.tab.objectApi !== work?.apiName);
    if (other?.tab.objectApi) return { apiName: other.tab.objectApi, label: other.label };
    if (work) return work;
    const first = tabs[0];
    if (first?.tab.objectApi) return { apiName: first.tab.objectApi, label: first.label };
    return null;
  }

  private filterTodayWork(rows: Record<string, unknown>[]): Record<string, unknown>[] {
    const today = todayIsoDate();
    const dated = rows.filter((r) => {
      const planned = workDateValue(r).slice(0, 10);
      return planned === today || (isOpenWorkItem(r) && !planned);
    });
    if (dated.length) return dated;
    return rows.filter(isOpenWorkItem).slice(0, 8);
  }

  /** Close fullscreen overlays that sit above bottom nav and block Home taps. */
  private dismissChromeOverlays(opts?: { keepClm?: boolean }) {
    this.visitShellId = null;
    this.visitDetailId = null;
    this.planChoiceSlot = null;
    this.totModalStart = null;
    this.promoModalStart = null;
    this.plannerSaveCollectionOpen = false;
    this.plannerFilterPanelOpen = false;
    if (!opts?.keepClm) {
      this.clmPlayerId = null;
      this.clmPlayerOverlayOpen = false;
    }
  }

  private async loadHome(expectedToken?: number) {
    if (!this.db) return;
    if (expectedToken != null && expectedToken !== this.navToken) return;
    const home = await loadHomeView(this.db, this.currentApp);
    if (expectedToken != null && expectedToken !== this.navToken) return;
    this.appLabel = home.appLabel || this.appLabel;
    this.homeFlexi = home.flexiPage;

    const work = this.resolveWorkObject();
    const recent = this.resolveRecentObject(work);
    this.workObject = work;
    this.recentObject = recent;

    this.homeWorkRows = work ? await listRecords(this.db, work.apiName, 100) : [];
    this.homeRecentRows = recent ? await listRecords(this.db, recent.apiName, 30) : [];

    const counts: { apiName: string; label: string; count: number }[] = [];
    for (const t of this.objectTabs().slice(0, 3)) {
      if (expectedToken != null && expectedToken !== this.navToken) return;
      const api = t.tab.objectApi!;
      const rows = await listRecords(this.db, api, 500);
      counts.push({ apiName: api, label: t.label, count: rows.length });
    }
    this.homeObjectCounts = counts;

    this.pendingCount = (await listPendingOutbox(this.db)).length;
    this.status = home.homeDeveloperName
      ? `Home · ${home.homeDeveloperName}`
      : 'Home (no FlexiPage synced)';
    await this.refreshApexSnapshot();
    if (expectedToken != null && expectedToken !== this.navToken) return;
    await this.refreshUsableLwcs(home.flexiPage);
    await this.updateComplete;
    await this.mountPageLwcs(home.flexiPage, 'home');
  }

  /** Online: refresh Apex DTOs via Sync Pack / REST fallback; offline: last SQLite snapshot. */
  private async refreshApexSnapshot(opts?: { weekStart?: string; contextUserId?: string | null }) {
    if (!this.db) return;
    const weekStart = opts?.weekStart || this.plannerWeekStart || undefined;
    const contextUserId =
      opts?.contextUserId !== undefined ? opts.contextUserId : this.selectedContextUserId;
    try {
      if (this.online && this.tokens) {
        const { engine } = await createLiveSyncEngine(this.db, this.tokens);
        const pullOpts: {
          weekStart?: string;
          weekEnd?: string;
          contextUserId?: string;
        } = {};
        if (weekStart) {
          const { weekEnd } = sundayWeekRange(new Date(weekStart + 'T12:00:00'));
          pullOpts.weekStart = weekStart;
          pullOpts.weekEnd = weekEnd;
        }
        if (contextUserId) pullOpts.contextUserId = contextUserId;
        await engine.pullApexCache(pullOpts);
        let snap = await loadApexCacheSnapshot(this.db);
        snap.fromCache = false;
        const sqliteAccounts = await listRecords(this.db, 'Account', 500);
        snap = ensurePlannerAccountsFallback(snap, sqliteAccounts);
        this.apexSnapshot = snap;
        return;
      }
    } catch {
      /* fall through */
    }
    let snap = await loadApexCacheSnapshot(this.db);
    const sqliteAccounts = await listRecords(this.db, 'Account', 500);
    this.apexSnapshot = ensurePlannerAccountsFallback(snap, sqliteAccounts);
  }

  private async loadPlannerWeek(weekStart: string) {
    this.plannerWeekStart = weekStart;
    await this.refreshApexSnapshot({ weekStart });
  }

  private async loadPlannerCollections() {
    try {
      const { value } = await Preferences.get({ key: 'osr.planner.collections' });
      if (!value) {
        this.plannerCollections = [];
        return;
      }
      const parsed = JSON.parse(value) as { collections?: import('./planner-accounts').PlannerCollection[] };
      this.plannerCollections = Array.isArray(parsed.collections) ? parsed.collections : [];
    } catch {
      this.plannerCollections = [];
    }
  }

  private async persistPlannerCollections() {
    await Preferences.set({
      key: 'osr.planner.collections',
      value: JSON.stringify({ collections: this.plannerCollections })
    });
  }

  private async savePlannerCollection(
    name: string,
    accountIds: string[],
    filters: import('./planner-accounts').PlannerAccountFilters
  ) {
    const collection = {
      id: `col_${Date.now()}`,
      name,
      accountIds,
      filterSnapshot: { ...filters }
    };
    this.plannerCollections = [...this.plannerCollections, collection];
    this.plannerSelectedCollectionId = collection.id;
    this.plannerSaveCollectionOpen = false;
    await this.persistPlannerCollections();
  }

  private async deletePlannerCollection(id: string) {
    this.plannerCollections = this.plannerCollections.filter((c) => c.id !== id);
    if (this.plannerSelectedCollectionId === id) this.plannerSelectedCollectionId = null;
    await this.persistPlannerCollections();
  }

  private async addAccountToPlannerCollection(collectionId: string, accountId: string) {
    this.plannerCollections = this.plannerCollections.map((c) => {
      if (c.id !== collectionId) return c;
      if (c.accountIds.includes(accountId)) return c;
      return { ...c, accountIds: [...c.accountIds, accountId] };
    });
    await this.persistPlannerCollections();
  }

  private fidelityCtx(label: string): FidelityCtx {
    const snap = this.apexSnapshot;
    const cached = !!snap?.fromCache && !this.online;
    return {
      label,
      snap,
      online: this.online,
      cached,
      messageIndex: this.messageCarouselIndex,
      leaderboardScope: this.leaderboardScope,
      metricsFilter: this.metricsFilter,
      metricsSearch: this.metricsSearch,
      metricsPage: this.metricsPage,
      selectedVisitId: this.selectedVisitId,
      plannerWeekStart: this.plannerWeekStart || sundayWeekRange().weekStart,
      plannerMode: this.plannerMode,
      plannerMapDay: this.plannerMapDay || undefined,
      promotionalProjects:
        ((this.apexSnapshot as { promotionalProjects?: { id: string; name: string }[] } | null)
          ?.promotionalProjects as { id: string; name: string }[] | undefined) ?? [],
      selectedContextUserId: this.selectedContextUserId,
      plannerSearch: this.plannerSearch,
      selectedAccountId: this.selectedAccountId,
      plannerAccountFilters: this.plannerAccountFilters,
      plannerFilterPanelOpen: this.plannerFilterPanelOpen,
      plannerCollections: this.plannerCollections,
      plannerSelectedCollectionId: this.plannerSelectedCollectionId,
      plannerSaveCollectionOpen: this.plannerSaveCollectionOpen,
      syncing: !!this.syncProgress || this.initialSyncPending,
      locationState: this.locationState,
      planChoiceSlot: this.planChoiceSlot,
      visitDetailId: this.visitDetailId,
      totModalStart: this.totModalStart,
      promoModalStart: this.promoModalStart,
      visitShellId: this.visitShellId,
      recordId: this.record ? String(this.record.Id ?? '') : this.visitShellId,
      objectApi: this.modalObjectApi || null,
      accountRows: this.apexSnapshot?.plannerAccounts?.accounts ?? null,
      clmPlayerId: this.clmPlayerId,
      myLearningInstanceId: this.myLearningInstanceId,
      iframeHeights: this.iframeHeights,
      requestUpdate: () => this.requestUpdate(),
      actions: {
        openPlanner: () => {
          const tab = this.tabs.find(
            (t) =>
              t.developerName === 'Field_Rep_Planner' ||
              t.tab.pageDeveloperName === 'Field_Rep_Planner' ||
              t.tab.lwcBundle?.includes('fieldRepPlanner')
          );
          if (tab) void this.openAppTab(tab);
        },
        openVisit: (id) => {
          this.visitShellId = null;
          this.visitDetailId = id;
        },
        openVisitShell: (id) => {
          this.visitDetailId = null;
          this.modalOpen = false;
          this.record = null;
          this.visitShellId = id;
        },
        closeVisitShell: () => {
          this.visitShellId = null;
        },
        openAccount: (id) => void this.openRecord('Account', id),
        openClm: () => {
          this.clmPlayerId = null;
          this.clmPlayerOverlayOpen = false;
          const tab = this.tabs.find(
            (t) =>
              t.developerName === 'CLM_Presentations' ||
              t.tab.lwcBundle?.includes('clmPresentations')
          );
          if (tab) void this.openAppTab(tab);
        },
        openClmPlayer: (presentationId) => {
          this.clmPlayerId = presentationId;
          this.clmPlayerOverlayOpen = true;
        },
        closeClmPlayer: () => {
          this.clmPlayerId = null;
          this.clmPlayerOverlayOpen = false;
        },
        completeClmSession: (payload) => {
          void this.completeClmSession(payload);
        },
        setClmPlayerId: (id) => {
          this.clmPlayerId = id;
          this.clmPlayerOverlayOpen = Boolean(id);
        },
        setContextUserId: (userId) => {
          this.selectedContextUserId = userId;
          void this.refreshApexSnapshot({ contextUserId: userId });
        },
        setMyLearningInstanceId: (id) => {
          this.myLearningInstanceId = id;
        },
        planVisit: (accountId) => void this.planVisit(accountId),
        postponeVisit: (visitId) => void this.postponeVisit(visitId),
        removeVisit: (visitId) => void this.removeVisit(visitId),
        setMessageIndex: (i) => {
          this.messageCarouselIndex = i;
        },
        setLeaderboardScope: (s) => {
          this.leaderboardScope = s;
        },
        setMetricsFilter: (f) => {
          this.metricsFilter = f;
          this.metricsPage = 0;
        },
        setMetricsSearch: (q) => {
          this.metricsSearch = q;
          this.metricsPage = 0;
        },
        setMetricsPage: (p) => {
          this.metricsPage = p;
        },
        setSelectedVisitId: (id) => {
          this.selectedVisitId = id;
        },
        setPlannerWeekStart: (iso) => {
          this.plannerWeekStart = iso;
        },
        setPlannerMode: (m) => {
          this.plannerMode = m;
          if (m === 'map' && !this.plannerMapDay) {
            const d = new Date();
            const y = d.getFullYear();
            const mo = String(d.getMonth() + 1).padStart(2, '0');
            const day = String(d.getDate()).padStart(2, '0');
            this.plannerMapDay = `${y}-${mo}-${day}`;
          }
        },
        setPlannerMapDay: (dayKey) => {
          this.plannerMapDay = dayKey;
        },
        setPlannerSearch: (q) => {
          this.plannerSearch = q;
        },
        setSelectedAccountId: (id) => {
          this.selectedAccountId = id;
        },
        setPlannerAccountFilters: (f) => {
          this.plannerAccountFilters = { ...this.plannerAccountFilters, ...f };
        },
        clearPlannerAccountFilters: () => {
          this.plannerAccountFilters = {
            recordType: 'ALL',
            specialty: 'ALL',
            classification: 'ALL',
            brickId: 'ALL'
          };
        },
        togglePlannerFilterPanel: () => {
          this.plannerFilterPanelOpen = !this.plannerFilterPanelOpen;
        },
        closePlannerFilterPanel: () => {
          this.plannerFilterPanelOpen = false;
        },
        setPlannerSelectedCollectionId: (id) => {
          this.plannerSelectedCollectionId = id;
        },
        openSavePlannerCollection: () => {
          this.plannerSaveCollectionOpen = true;
        },
        closeSavePlannerCollection: () => {
          this.plannerSaveCollectionOpen = false;
        },
        savePlannerCollection: (name, accountIds, filters) => {
          void this.savePlannerCollection(name, accountIds, filters);
        },
        deletePlannerCollection: (id) => {
          void this.deletePlannerCollection(id);
        },
        addAccountToPlannerCollection: (collectionId, accountId) => {
          void this.addAccountToPlannerCollection(collectionId, accountId);
        },
        reorderDayVisits: (orderedVisitIds, dayKey, legs) => {
          void this.reorderDayVisits(orderedVisitIds, dayKey, legs);
        },
        rescheduleVisit: (visitId, startIso, endIso) => {
          void this.rescheduleVisit(visitId, startIso, endIso);
        },
        createDraftVisit: (accountId, startIso) => void this.createDraftVisit(accountId, startIso),
        loadPlannerWeek: (ws) => void this.loadPlannerWeek(ws),
        openPlanChoice: (startIso) => {
          this.planChoiceSlot = startIso;
        },
        closePlanChoice: () => {
          this.planChoiceSlot = null;
        },
        openTotModal: (startIso) => {
          this.planChoiceSlot = null;
          this.totModalStart = startIso;
        },
        closeTotModal: () => {
          this.totModalStart = null;
        },
        openPromoModal: (startIso) => {
          this.planChoiceSlot = null;
          this.promoModalStart = startIso;
        },
        closePromoModal: () => {
          this.promoModalStart = null;
        },
        closeVisitDetail: () => {
          this.visitDetailId = null;
        },
        saveVisitDetail: (visitId, status, cancellationReason) =>
          void this.saveVisitDetail(visitId, status, cancellationReason),
        createTimeOff: (input) => void this.createTimeOff(input),
        createPromoVisit: (projectId, startIso) => void this.createPromoVisit(projectId, startIso),
        setLocationSharing: (enabled) => void repLocationTracker.setSharing(enabled),
        saveVisitCallReport: (visitId, fields) => void this.saveVisitCallReport(visitId, fields),
        setIframeHeight: (bundle, height) => {
          const next = Math.max(80, Math.round(height));
          if (this.iframeHeights[bundle] === next) return;
          this.iframeHeights = { ...this.iframeHeights, [bundle]: next };
        }
      }
    };
  }

  private renderFidelityBundle(bundle: string, label: string) {
    return renderFidelity(bundle, this.fidelityCtx(label));
  }

  private async planVisit(accountId: string) {
    if (!this.db || !accountId) return;
    const start = new Date();
    start.setMinutes(0, 0, 0);
    start.setHours(start.getHours() + 1);
    const end = new Date(start.getTime() + 30 * 60 * 1000);
    const id = `local_${crypto.randomUUID()}`;
    const payload: Record<string, unknown> = {
      Id: id,
      Account__c: accountId,
      Status__c: 'Draft',
      StartDateTime__c: start.toISOString(),
      EndDateTime__c: end.toISOString(),
      Name: 'Planned visit'
    };
    await localSaveRecord(this.db, 'Visit__c', payload, true);
    await this.patchPlannerCaches((visits) => {
      const account = this.apexSnapshot?.plannerAccounts?.accounts?.find((a) => a.id === accountId);
      visits.push({
        id,
        accountId,
        accountName: account?.name,
        status: 'Draft',
        startDateTime: String(payload.StartDateTime__c),
        endDateTime: String(payload.EndDateTime__c),
        accountLatitude: account?.latitude ?? null,
        accountLongitude: account?.longitude ?? null
      });
      return visits;
    });
    this.pendingCount = (await listPendingOutbox(this.db)).length;
    this.status = 'Visit planned · queued for sync';
  }

  private async createDraftVisit(accountId: string, startIso: string) {
    if (!this.db || !accountId) {
      this.status = 'Select an account before planning a visit';
      return;
    }
    const start = new Date(startIso);
    if (Number.isNaN(start.getTime())) {
      this.status = 'Invalid visit time';
      return;
    }
    try {
      const end = new Date(start.getTime() + 60 * 60 * 1000);
      const id = `local_${crypto.randomUUID()}`;
      const account =
        this.apexSnapshot?.plannerAccounts?.accounts?.find((a) => a.id === accountId) ?? null;
      const accountName = account?.name || 'Account';
      const payload: Record<string, unknown> = {
        Id: id,
        Account__c: accountId,
        Status__c: 'Draft',
        StartDateTime__c: start.toISOString(),
        EndDateTime__c: end.toISOString(),
        Planned_Date__c: isoDateLocal(start),
        Name: `Visit — ${accountName}`
      };
      await localSaveRecord(this.db, 'Visit__c', payload, true);
      await this.patchPlannerCaches((visits) => {
        visits.push({
          id,
          name: String(payload.Name),
          accountId,
          accountName,
          status: 'Draft',
          startDateTime: start.toISOString(),
          endDateTime: end.toISOString(),
          accountSpecialty: account?.specialty,
          accountRecordTypeName: account?.recordTypeName,
          accountRecordTypeDeveloperName: account?.recordTypeDeveloperName,
          accountLatitude: account?.latitude ?? null,
          accountLongitude: account?.longitude ?? null
        });
        return visits;
      });
      this.planChoiceSlot = null;
      this.pendingCount = (await listPendingOutbox(this.db)).length;
      this.status = `Draft visit · ${accountName} · queued for sync`;
    } catch (e) {
      this.status = `Could not create visit: ${e instanceof Error ? e.message : String(e)}`;
    }
  }

  private async saveVisitDetail(visitId: string, status: string, cancellationReason: string) {
    if (!this.db || !visitId) return;
    const existing = (await getRecord(this.db, 'Visit__c', visitId)) ?? { Id: visitId };
    const payload = {
      ...existing,
      Id: visitId,
      Status__c: status,
      Cancellation_Reason__c: cancellationReason || null
    };
    await localSaveRecord(this.db, 'Visit__c', payload, String(visitId).startsWith('local_'));
    await this.patchPlannerCaches((visits) =>
      visits.map((v) => (v.id === visitId ? { ...v, status } : v))
    );
    this.visitDetailId = null;
    this.pendingCount = (await listPendingOutbox(this.db)).length;
    this.status = 'Visit updated · queued for sync';
  }

  private async createTimeOff(input: {
    startIso: string;
    typeValue: string;
    spanType: string;
    durationHours?: string;
    comments?: string;
  }) {
    if (!this.db) return;
    const start = new Date(input.startIso);
    if (Number.isNaN(start.getTime())) {
      this.status = 'Invalid time-off start';
      return;
    }
    try {
      const hours = Number(input.durationHours || 2);
      const end =
        input.spanType === 'Full_Day'
          ? new Date(start.getFullYear(), start.getMonth(), start.getDate(), 23, 59, 0)
          : new Date(start.getTime() + Math.max(1, hours) * 60 * 60 * 1000);
      const id = `local_${crypto.randomUUID()}`;
      const payload: Record<string, unknown> = {
        Id: id,
        Type__c: input.typeValue || 'Training',
        Span_Type__c: input.spanType || 'Hours',
        Start_Date_Time__c: start.toISOString(),
        End_Date_Time__c: end.toISOString(),
        Start_Date__c: start.toISOString().slice(0, 10),
        End_Date__c: end.toISOString().slice(0, 10),
        Stage__c: 'Draft',
        Comments__c: input.comments || null,
        Name: `TOT — ${input.typeValue || 'Training'}`
      };
      await localSaveRecord(this.db, 'Time_Off_Request__c', payload, true);
      const base = this.apexSnapshot ?? (await loadApexCacheSnapshot(this.db));
      const week = base.plannerWeek ?? { visits: [], timeOffBlocks: [] };
      const blocks = [
        ...((week.timeOffBlocks as Record<string, unknown>[]) ?? []),
        {
          id,
          typeLabel: input.typeValue || 'Training',
          name: payload.Name,
          startDateTime: start.toISOString(),
          endDateTime: end.toISOString()
        }
      ];
      this.apexSnapshot = {
        ...base,
        plannerWeek: { ...week, visits: week.visits ?? [], timeOffBlocks: blocks }
      };
      await upsertApexPayload(this.db, 'plannerWeek', this.apexSnapshot.plannerWeek);
      this.totModalStart = null;
      this.planChoiceSlot = null;
      this.pendingCount = (await listPendingOutbox(this.db)).length;
      this.status = 'Time off queued for sync';
    } catch (e) {
      this.status = `Could not create time off: ${e instanceof Error ? e.message : String(e)}`;
    }
  }

  private async createPromoVisit(projectId: string, startIso: string) {
    if (!this.db || !projectId) return;
    const start = new Date(startIso);
    if (Number.isNaN(start.getTime())) return;
    const end = new Date(start.getTime() + 60 * 60 * 1000);
    const id = `local_${crypto.randomUUID()}`;
    const projects =
      ((this.apexSnapshot as { promotionalProjects?: { id: string; name: string }[] } | null)
        ?.promotionalProjects as { id: string; name: string }[] | undefined) ?? [];
    const project = projects.find((p) => p.id === projectId);
    const payload: Record<string, unknown> = {
      Id: id,
      Status__c: 'Draft',
      StartDateTime__c: start.toISOString(),
      EndDateTime__c: end.toISOString(),
      Pharma_Project__c: projectId,
      Visit_Objective__c: project?.name ? `Promotional: ${project.name}` : 'Promotional Event',
      Name: project?.name || 'Promotional Event'
    };
    await localSaveRecord(this.db, 'Visit__c', payload, true);
    await this.patchPlannerCaches((visits) => {
      visits.push({
        id,
        name: String(payload.Name),
        status: 'Draft',
        startDateTime: start.toISOString(),
        endDateTime: end.toISOString(),
        visitObjective: String(payload.Visit_Objective__c),
        zetaProjectId: projectId,
        zetaProjectName: project?.name
      });
      return visits;
    });
    this.promoModalStart = null;
    this.pendingCount = (await listPendingOutbox(this.db)).length;
    this.status = 'Promotional event queued for sync';
  }

  private async saveVisitCallReport(visitId: string, fields: Record<string, unknown>) {
    if (!this.db || !visitId) return;
    const existing = (await getRecord(this.db, 'Visit__c', visitId)) ?? { Id: visitId };
    const payload = { ...existing, ...fields, Id: visitId };
    await localSaveRecord(this.db, 'Visit__c', payload, String(visitId).startsWith('local_'));
    this.pendingCount = (await listPendingOutbox(this.db)).length;
    this.status = 'Call report saved · queued for sync';
    if (this.record && String(this.record.Id) === visitId) {
      this.record = payload;
    }
  }

  private async postponeVisit(visitId: string) {
    if (!this.db || !visitId) return;
    const existing = (await getRecord(this.db, 'Visit__c', visitId)) ?? { Id: visitId };
    const shift = (iso?: unknown) => {
      if (!iso) return undefined;
      const d = new Date(String(iso));
      if (Number.isNaN(d.getTime())) return String(iso);
      d.setDate(d.getDate() + 1);
      return d.toISOString();
    };
    const payload = {
      ...existing,
      Id: visitId,
      StartDateTime__c: shift(existing.StartDateTime__c) ?? existing.StartDateTime__c,
      EndDateTime__c: shift(existing.EndDateTime__c) ?? existing.EndDateTime__c
    };
    await localSaveRecord(this.db, 'Visit__c', payload, String(visitId).startsWith('local_'));
    await this.patchPlannerCaches((visits) =>
      visits.map((v) =>
        v.id === visitId
          ? {
              ...v,
              startDateTime: String(payload.StartDateTime__c ?? v.startDateTime),
              endDateTime: String(payload.EndDateTime__c ?? v.endDateTime)
            }
          : v
      )
    );
    this.pendingCount = (await listPendingOutbox(this.db)).length;
    this.status = 'Visit postponed · queued for sync';
  }

  private async removeVisit(visitId: string) {
    if (!this.db || !visitId) return;
    await localDeleteRecord(this.db, 'Visit__c', visitId);
    await this.patchPlannerCaches((visits) => visits.filter((v) => v.id !== visitId));
    if (this.selectedVisitId === visitId) this.selectedVisitId = null;
    if (this.visitDetailId === visitId) this.visitDetailId = null;
    this.pendingCount = (await listPendingOutbox(this.db)).length;
    this.status = 'Visit removed · queued for sync';
  }

  /** Apply optimized stop order using travel legs (prev end + drive), not fixed hourly slots. */
  private async reorderDayVisits(
    orderedVisitIds: string[],
    dayKey: string,
    legs?: { distanceKm: number; durationMin: number }[]
  ) {
    if (!this.db || !orderedVisitIds.length || !dayKey) return;
    const weekVisits = this.apexSnapshot?.plannerWeek?.visits ?? [];
    const byId = new Map(weekVisits.map((v) => [String(v.id), v]));
    const ordered = orderedVisitIds
      .map((id) => byId.get(String(id)))
      .filter(Boolean) as VisitSummaryDto[];

    const DEFAULT_VISIT_MS = 60 * 60 * 1000;
    const visitDuration = (v: VisitSummaryDto) => {
      const s = v.startDateTime ? new Date(v.startDateTime) : null;
      const e = v.endDateTime ? new Date(v.endDateTime) : null;
      if (s && e && !Number.isNaN(s.getTime()) && !Number.isNaN(e.getTime())) {
        return Math.max(30 * 60 * 1000, e.getTime() - s.getTime());
      }
      return DEFAULT_VISIT_MS;
    };

    // Build travel minutes between consecutive stops. Prefer OSRM legs when present.
    // Legs from route include a leading "from current location" entry (index 0).
    const driveMinutesBetween = (from: VisitSummaryDto, to: VisitSummaryDto, legIndex: number) => {
      const fromRoute = legs?.[legIndex]?.durationMin;
      if (fromRoute != null && Number.isFinite(fromRoute)) return Math.max(0, fromRoute);
      const aLat = Number(from.accountLatitude);
      const aLon = Number(from.accountLongitude);
      const bLat = Number(to.accountLatitude);
      const bLon = Number(to.accountLongitude);
      if (
        Number.isFinite(aLat) &&
        Number.isFinite(aLon) &&
        Number.isFinite(bLat) &&
        Number.isFinite(bLon)
      ) {
        return Math.max(1, Math.round(haversineKm(aLat, aLon, bLat, bLon) * 1.4));
      }
      return 5;
    };

    const [y, m, d] = dayKey.split('-').map(Number);
    let cursor: Date;
    if (ordered[0]?.startDateTime) {
      cursor = new Date(ordered[0].startDateTime);
      if (Number.isNaN(cursor.getTime())) {
        cursor = new Date(y, m - 1, d, 9, 0, 0, 0);
      }
    } else {
      cursor = new Date(y, m - 1, d, 9, 0, 0, 0);
    }

    const updates = new Map<string, { start: string; end: string }>();
    // If legs include current-location → first stop, apply that drive before stop 0.
    const hasOriginLeg = Boolean(legs && legs.length > ordered.length);
    if (hasOriginLeg && legs?.[1]) {
      // Keep first stop's planned start; origin drive is informational for the map only.
    }

    ordered.forEach((visit, i) => {
      if (i > 0) {
        // legs[i] or legs[i+1] when origin is included
        const legIndex = hasOriginLeg ? i + 1 : i;
        const driveMs = driveMinutesBetween(ordered[i - 1], visit, legIndex) * 60 * 1000;
        cursor = new Date(cursor.getTime() + driveMs);
      }
      const start = new Date(cursor.getTime());
      const end = new Date(start.getTime() + visitDuration(visit));
      updates.set(String(visit.id), { start: start.toISOString(), end: end.toISOString() });
      cursor = end;
    });

    for (const [visitId, times] of updates) {
      const existing = (await getRecord(this.db, 'Visit__c', visitId)) ?? { Id: visitId };
      const payload = {
        ...existing,
        Id: visitId,
        StartDateTime__c: times.start,
        EndDateTime__c: times.end
      };
      await localSaveRecord(this.db, 'Visit__c', payload, String(visitId).startsWith('local_'));
    }
    await this.patchPlannerCaches((visits) =>
      visits.map((v) => {
        const t = v.id ? updates.get(String(v.id)) : undefined;
        return t ? { ...v, startDateTime: t.start, endDateTime: t.end } : v;
      })
    );
    this.pendingCount = (await listPendingOutbox(this.db)).length;
    this.status = 'Route applied to calendar · queued for sync';
  }

  private async patchPlannerCaches(
    mutator: (visits: VisitSummaryDto[]) => VisitSummaryDto[]
  ): Promise<void> {
    if (!this.db) return;
    const base = this.apexSnapshot ?? {
      todayPlan: null,
      plannerWeek: null,
      plannerAccounts: null,
      plannerViewer: null,
      homeMetrics: null,
      accountCoverage: null,
      gamification: null,
      rankings: null,
      nextBestCustomers: null,
      officeMessages: null,
      clmManifest: null,
      myLearning: null,
      fetchedAt: {},
      fromCache: true
    };
    const week = base.plannerWeek ?? { visits: [], timeOffBlocks: [] };
    const nextWeek: PlannerPayloadDto = {
      ...week,
      visits: mutator([...(week.visits ?? [])]),
      timeOffBlocks: week.timeOffBlocks ?? []
    };
    const todayKey = todayIsoDate();
    const todayVisits = (nextWeek.visits ?? []).filter((v) => {
      const raw = String(v.startDateTime ?? '');
      if (raw.startsWith(todayKey)) return true;
      const d = new Date(raw);
      if (Number.isNaN(d.getTime())) return false;
      return isoDateLocal(d) === todayKey;
    });
    const nextToday: PlannerPayloadDto = {
      ...(base.todayPlan ?? { visits: [], timeOffBlocks: [] }),
      visits: todayVisits,
      timeOffBlocks: base.todayPlan?.timeOffBlocks ?? []
    };
    const next: ApexCacheSnapshot = {
      ...base,
      todayPlan: nextToday,
      plannerWeek: nextWeek
    };
    this.apexSnapshot = next;
    await upsertApexPayload(this.db, 'todayPlan', next.todayPlan);
    await upsertApexPayload(this.db, 'plannerWeek', next.plannerWeek);
  }

  protected updated() {
    if (!this.db) return;
    const snap = this.apexSnapshot;
    const cached = !!snap?.fromCache && !this.online;
    void mountHydrateHosts(this.db, this.renderRoot, snap, cached);
  }

  private async openList(objectApi: string, expectedToken?: number) {
    if (!this.db) return;
    if (expectedToken != null && expectedToken !== this.navToken) return;
    this.closeRecordModal({ keepRoute: true });
    this.route = { kind: 'list', objectApi };
    this.objectListSearch = '';
    this.listRows = await listRecords(this.db, objectApi, 500);
    if (expectedToken != null && expectedToken !== this.navToken) return;
    this.updateFormFactor();
    this.listPickerOpen = false;
    this.calendarPickerOpen = false;
    this.objectDescribe = await getObjectDescribe(this.db, objectApi);
    if (expectedToken != null && expectedToken !== this.navToken) return;
    this.fieldMeta = fieldsFromDescribe(this.objectDescribe);
    const synced = await listListViewsForObject(this.db, objectApi);
    if (expectedToken != null && expectedToken !== this.navToken) return;
    this.objectListViews = synced.map((v) => ({
      id: v.id,
      developerName: v.developerName,
      label: v.label,
      recordIds: v.listview.recordIds,
      columns: Array.isArray(v.listview.columns)
        ? v.listview.columns.map((c) =>
            typeof c === 'string'
              ? { fieldOrColumn: c }
              : {
                  fieldOrColumn: c.fieldOrColumn,
                  label: c.label,
                  type: c.type
                }
          )
        : undefined,
      filters: v.listview.filters,
      booleanFilter: v.listview.booleanFilter,
      filtersSupported: v.listview.filtersSupported,
      kanbanGroupField: v.listview.kanbanGroupField,
      displayType: v.listview.displayType
    }));
    const prefs = await getUserPrefs(this.db, objectApi);
    this.favouriteListViewIds = prefs?.favourites ?? [];
    this.pinnedListViewId = prefs?.pinnedListViewId ?? null;
    this.calendarFieldPref = prefs?.calendarField ?? null;
    const pinnedOk =
      this.pinnedListViewId &&
      this.objectListViews.some(
        (v) => v.id === this.pinnedListViewId || v.developerName === this.pinnedListViewId
      );
    this.activeListViewId = pinnedOk ? (this.pinnedListViewId as string) : 'all';
    this.refreshListColumns();
    // Smart default view from describe + rows (any object tab)
    const describeDates = dateFieldsFromDescribe(this.objectDescribe).map((f) => f.name);
    const dateField = detectDateFieldSmart(
      this.listRows,
      this.calendarFieldPref,
      describeDates,
      this.fieldMeta
    );
    const activeView = this.objectListViews.find(
      (v) => v.id === this.activeListViewId || v.developerName === this.activeListViewId
    );
    const kanbanField = detectKanbanFieldSmart(
      this.listRows,
      activeView?.kanbanGroupField,
      this.fieldMeta
    );
    this.listViewMode = suggestDefaultListMode({
      formFactor: this.formFactor,
      hasDate: !!dateField,
      hasKanban: !!kanbanField,
      objectApi,
      rowCount: this.listRows.length
    });
    const objectLabel =
      (this.objectDescribe?.label as string | undefined) ?? objectApi.replace(/__c$/, '');
    this.status = `${objectLabel} · ${this.listRows.length} records`;
  }

  private refreshListColumns() {
    const view = this.objectListViews.find(
      (v) => v.id === this.activeListViewId || v.developerName === this.activeListViewId
    );
    const cols = columnsForView(view);
    // Keep columns that exist on at least one row or describe
    this.listColumns = cols.filter(
      (c) =>
        this.fieldMeta.some((f) => f.name === c) ||
        this.listRows.some((r) => r[c] != null) ||
        c === 'Name'
    );
    if (!this.listColumns.length) this.listColumns = ['Name'];
  }

  private filteredListRows(): Record<string, unknown>[] {
    const result = applyListViewFilter(this.listRows, this.activeListViewId, this.objectListViews);
    const fields = searchableFieldsForObject(this.fieldMeta, this.listColumns, this.listRows);
    return filterRowsByTextSearch(result.rows, this.objectListSearch, fields);
  }

  private currentListFilterWarning(): string | null {
    return applyListViewFilter(this.listRows, this.activeListViewId, this.objectListViews)
      .filterWarning;
  }

  private currentListViewLabel(): string {
    if (this.activeListViewId === 'all') return 'All';
    if (this.activeListViewId === 'recent') return 'Recently Viewed';
    const v = this.objectListViews.find(
      (x) => x.id === this.activeListViewId || x.developerName === this.activeListViewId
    );
    return v?.label ?? 'List view';
  }

  private sortedListViews(): PickerListView[] {
    const fav = new Set(this.favouriteListViewIds);
    return [...this.objectListViews].sort((a, b) => {
      const af = fav.has(a.id) || fav.has(a.developerName) ? 0 : 1;
      const bf = fav.has(b.id) || fav.has(b.developerName) ? 0 : 1;
      if (af !== bf) return af - bf;
      return a.label.localeCompare(b.label);
    });
  }

  private async persistObjectPrefs(objectApi: string, next: UserObjectPrefs) {
    if (!this.db) return;
    this.favouriteListViewIds = next.favourites;
    this.pinnedListViewId = next.pinnedListViewId;
    this.calendarFieldPref = next.calendarField;
    await upsertUserPrefs(this.db, next);
    if (this.online && this.tokens) {
      try {
        const { engine } = await createLiveSyncEngine(this.db, this.tokens);
        await engine.pushObjectPrefs(next);
      } catch {
        /* local cache remains; next sync will pull/push */
      }
    }
  }

  private async toggleFavourite(objectApi: string, viewId: string) {
    const set = new Set(this.favouriteListViewIds);
    if (set.has(viewId)) set.delete(viewId);
    else set.add(viewId);
    await this.persistObjectPrefs(objectApi, {
      objectApi,
      favourites: [...set],
      pinnedListViewId: this.pinnedListViewId,
      calendarField: this.calendarFieldPref
    });
  }

  private async togglePin(objectApi: string, viewId: string) {
    const nextPin = this.pinnedListViewId === viewId ? null : viewId;
    await this.persistObjectPrefs(objectApi, {
      objectApi,
      favourites: this.favouriteListViewIds,
      pinnedListViewId: nextPin,
      calendarField: this.calendarFieldPref
    });
    if (nextPin) this.activeListViewId = nextPin;
  }

  private async saveCalendarField(objectApi: string, field: string) {
    await this.persistObjectPrefs(objectApi, {
      objectApi,
      favourites: this.favouriteListViewIds,
      pinnedListViewId: this.pinnedListViewId,
      calendarField: field || null
    });
    this.calendarPickerOpen = false;
    if (field) this.listViewMode = 'calendar';
  }

  private requestCalendarMode(objectApi: string) {
    const describeDates = dateFieldsFromDescribe(this.objectDescribe);
    if (!this.calendarFieldPref && describeDates.length > 0) {
      this.calendarPickerOpen = true;
      return;
    }
    this.listViewMode = 'calendar';
  }

  private fieldLabel(apiName: string): string {
    return fieldLabelFromDescribe(this.objectDescribe, apiName);
  }

  private fieldInfo(apiName: string): DescribeFieldInfo | undefined {
    return this.fieldMeta.find((f) => f.name === apiName);
  }

  private async refreshLookupNames(record: Record<string, unknown> | null) {
    if (!this.db || !record) {
      this.lookupNames = {};
      return;
    }
    const next: Record<string, { id: string; name: string; objectApi: string | null }> = {};
    for (const f of this.fieldMeta) {
      if (f.type !== 'reference') continue;
      const val = record[f.name];
      if (val == null || String(val) === '') continue;
      next[f.name] = await resolveLookupDisplay(this.db, f, record);
    }
    this.lookupNames = next;
  }

  private async openRecord(objectApi: string, recordId: string) {
    if (!this.db) return;
    this.searchOpen = false;
    this.globalSearch = '';
    this.searchHits = [];
    this.listPickerOpen = false;
    this.modalOpen = true;
    this.modalObjectApi = objectApi;
    this.editing = false;
    this.updateFormFactor();
    const view = await loadRecordView(this.db, objectApi, recordId);
    this.record = view.record;
    this.layout = view.layout as LayoutModel | null;
    this.flexiPage = view.flexiPage;
    this.objectDescribe = view.describe ?? (await getObjectDescribe(this.db, objectApi));
    this.fieldMeta = fieldsFromDescribe(this.objectDescribe);
    this.objectActions = (view.actions ?? []).map((a) => ({
      id: a.id,
      name: a.name,
      label: a.label,
      actionType: a.action.actionType,
      targetObject: a.action.targetObject,
      offlineSafe: a.action.offlineSafe,
      fieldDefaults: a.action.fieldDefaults,
      apexName: a.action.apexName
    }));
    this.compactFields =
      view.compactLayout?.fields ??
      (view.layout as LayoutModel | null)?.highlightsFields ??
      [];
    await this.refreshLookupNames(this.record);
    const layoutRelated = (view.layout as LayoutModel | null)?.relatedLists as
      | RelatedListMeta[]
      | undefined;
    this.related = await loadRelatedLists(this.db, objectApi, recordId, layoutRelated);
    this.formErrors = [];
    this.fieldErrors = {};
    this.status = view.flexiPageDeveloperName
      ? `Record · ${view.flexiPageDeveloperName}`
      : `Record · ${objectApi}`;
    await this.refreshUsableLwcs(view.flexiPage);
    await this.updateComplete;
    await this.mountPageLwcs(view.flexiPage, 'record');
  }

  private closeRecordModal(opts?: { keepRoute?: boolean }) {
    this.modalOpen = false;
    this.modalObjectApi = '';
    this.editing = false;
    this.formErrors = [];
    this.fieldErrors = {};
    this.record = null;
    this.layout = null;
    this.flexiPage = null;
    this.related = [];
    this.objectActions = [];
    this.compactFields = [];
    if (!opts?.keepRoute && this.route.kind === 'list') {
      this.status = `${this.route.objectApi} · ${this.listRows.length} records`;
    }
  }

  private async onGlobalSearchInput(value: string) {
    this.globalSearch = value;
    this.searchOpen = value.trim().length >= 2;
    if (this.searchTimer) clearTimeout(this.searchTimer);
    if (!this.searchOpen || !this.db) {
      this.searchHits = [];
      return;
    }
    this.searchTimer = setTimeout(async () => {
      if (!this.db) return;
      this.searchHits = await searchRecords(this.db, value, 30);
    }, 180);
  }

  private async mountPageLwcs(page: FlexiPageModel | null, prefix: string) {
    if (!this.db || !page) return;
    for (const region of page.regions) {
      for (let i = 0; i < region.components.length; i++) {
        const c = region.components[i];
        const bundle = lwcBundleFromComponent(c);
        if (!bundle) continue;
        // Registry fidelity ports already rendered (Lit or hydrate host)
        if (isFidelityBundle(bundle)) continue;
        const hostId = `${prefix}-${region.name}-${i}`;
        const el = this.renderRoot.querySelector(`[data-lwc-host="${hostId}"]`) as HTMLElement | null;
        if (!el) continue;
        try {
          const mounted = await mountLwc(this.db, el, bundle, {
            ...(c.attributes ?? {}),
            recordId: this.modalOpen ? String(this.record?.Id ?? '') : undefined,
            objectApi: this.modalOpen ? this.modalObjectApi : undefined
          });
          if (!mounted) {
            el.innerHTML = `<div class="sf-empty"><strong>No items to display</strong></div>`;
          }
        } catch (e) {
          el.innerHTML = `<div class="lwc-missing">Failed to mount ${bundle}: ${
            e instanceof Error ? e.message : String(e)
          }</div>`;
        }
      }
    }
  }

  private async saveRecord() {
    if (!this.db || !this.modalOpen || !this.record || !this.modalObjectApi) return;
    const isNew = String(this.record.Id ?? '').startsWith('local_');
    const result = await saveWithValidation(this.db, this.modalObjectApi, this.record, isNew);
    if (!result.ok) {
      this.formErrors = result.validation.errors.map((e) => e.message);
      const fe: Record<string, string> = {};
      for (const e of result.validation.errors) {
        if (e.field) fe[e.field] = e.message;
      }
      this.fieldErrors = fe;
      return;
    }
    this.formErrors = [];
    this.fieldErrors = {};
    this.editing = false;
    this.pendingCount = (await listPendingOutbox(this.db)).length;
    this.status = `Saved · outbox ${this.pendingCount}`;
    if (result.recordId) {
      await this.openRecord(this.modalObjectApi, result.recordId);
      if (this.route.kind === 'list' && this.route.objectApi === this.modalObjectApi) {
        this.listRows = await listRecords(this.db, this.modalObjectApi, 500);
      }
    }
  }

  private async runObjectAction(action: OfflineAction) {
    const kind = classifyActionKind(action);
    if (kind === 'unsupported') {
      this.status = `${action.label} unavailable offline`;
      return;
    }
    if (kind === 'edit') {
      this.editing = true;
      return;
    }
    if (kind === 'delete' && this.db && this.record?.Id && this.modalObjectApi) {
      await localDeleteRecord(this.db, this.modalObjectApi, String(this.record.Id));
      this.pendingCount = (await listPendingOutbox(this.db)).length;
      this.closeRecordModal();
      if (this.route.kind === 'list') {
        this.listRows = await listRecords(this.db, this.route.objectApi, 500);
      }
      this.status = 'Deleted · queued for sync';
      return;
    }
    if (kind === 'create') {
      const target = action.targetObject || this.modalObjectApi;
      if (!target || !this.db) return;
      const id = `local_${Date.now()}`;
      const defaults = { ...(action.fieldDefaults ?? {}) };
      if (this.record?.Id && this.modalObjectApi) {
        // Heuristic parent link
        defaults[`${this.modalObjectApi.replace('__c', '')}Id`] =
          defaults[`${this.modalObjectApi.replace('__c', '')}Id`] ?? this.record.Id;
        if (this.modalObjectApi === 'Account') {
          defaults.AccountId = this.record.Id;
          defaults.Account__c = this.record.Id;
        }
      }
      await this.openRecord(target, id);
      this.record = { Id: id, Name: '', ...defaults };
      this.editing = true;
      return;
    }
    this.status = `${action.label} · offline navigate`;
  }

  private async commitInlineEdit(objectApi: string) {
    if (!this.db || !this.inlineEditId || !this.inlineEditField) return;
    const row = this.listRows.find((r) => String(r.Id) === this.inlineEditId);
    if (!row) return;
    const next = { ...row, [this.inlineEditField]: this.inlineEditValue };
    const result = await saveWithValidation(this.db, objectApi, next, false);
    if (!result.ok) {
      this.status = result.validation.errors.map((e) => e.message).join('; ') || 'Validation failed';
      return;
    }
    this.listRows = this.listRows.map((r) =>
      String(r.Id) === this.inlineEditId ? next : r
    );
    this.inlineEditId = null;
    this.inlineEditField = null;
    this.inlineEditValue = '';
    this.pendingCount = (await listPendingOutbox(this.db)).length;
    this.status = `Inline saved · outbox ${this.pendingCount}`;
  }

  private async logout() {
    this.stopBackgroundSync();
    if (this.db) await clearSession(this.db);
    await Preferences.remove({ key: CURRENT_APP_KEY });
    this.tokens = null;
    this.currentApp = null;
    this.apps = [];
    this.tabs = [];
    this.syncMode = 'logged-out';
    this.route = { kind: 'launcher' };
    this.status = 'Signed out';
    this.syncValidationSummary = null;
  }

  private titleText(): string {
    if (!this.tokens) return 'Salesforce';
    if (this.modalOpen) {
      return String(this.record?.Name ?? this.record?.Subject ?? this.modalObjectApi);
    }
    switch (this.route.kind) {
      case 'launcher':
        return 'App Launcher';
      case 'home':
        return this.appLabel || 'Home';
      case 'menu':
        return 'Menu';
      case 'list':
        return (
          this.tabs.find((t) => (t.tab as { objectApi?: string }).objectApi === (this.route as { objectApi: string }).objectApi)
            ?.label ?? (this.route as { objectApi: string }).objectApi
        );
      case 'tab': {
        const dn = this.route.developerName;
        return this.tabs.find((t) => t.developerName === dn)?.label ?? dn;
      }
      case 'record':
        return String(this.record?.Name ?? this.route.objectApi);
      case 'conflicts':
        return 'Conflicts';
      case 'logs':
        return 'Support logs';
      default:
        return this.appLabel || 'OSR';
    }
  }

  private navItems() {
    const items: {
      key: string;
      label: string;
      iconName: string;
      iconUrl?: string | null;
      action: () => void;
      active: boolean;
    }[] = [
      {
        key: 'home',
        label: 'Home',
        iconName: 'Home',
        action: () => {
          const token = ++this.navToken;
          this.dismissChromeOverlays();
          this.closeRecordModal({ keepRoute: true });
          this.route = { kind: 'home' };
          void this.loadHome(token);
        },
        active: this.route.kind === 'home' && !this.modalOpen
      }
    ];
    // Show object + custom tabs from the selected app (phone: 4 + menu)
    for (const t of this.appNavTabs().slice(0, 4)) {
      const typ = this.tabTypeOf(t);
      const iconName = t.tab.objectApi ?? t.developerName;
      items.push({
        key: t.developerName,
        label: t.label,
        iconName,
        iconUrl: t.tab.iconUrl ?? null,
        action: () => void this.openAppTab(t),
        active:
          (this.route.kind === 'list' &&
            typ === 'object' &&
            this.route.objectApi === (t.tab.objectApi ?? t.developerName)) ||
          (this.route.kind === 'tab' && this.route.developerName === t.developerName)
      });
    }
    items.push({
      key: 'menu',
      label: 'Menu',
      iconName: 'Menu',
      action: () => {
        const token = ++this.navToken;
        this.dismissChromeOverlays();
        this.closeRecordModal({ keepRoute: true });
        this.route = { kind: 'menu' };
        void token;
      },
      active:
        this.route.kind === 'menu' ||
        this.route.kind === 'launcher' ||
        this.route.kind === 'conflicts' ||
        this.route.kind === 'logs'
    });
    return items;
  }

  render() {
    if (!this.tokens) return this.renderLogin();

    const showChromeNav = this.route.kind !== 'launcher';
    return html`
      <div class="shell">
        <div class="topbar-wrap">
          <header class="topbar">
            <img class="topbar-logo" src="/salesforce-cloud.png" alt="Salesforce" height="28" />
            <div class="avatar">${(this.userLabel || 'SF').slice(0, 2).toUpperCase()}</div>
            <div class="top-title">
              <h1>${this.titleText()}</h1>
              <p>${this.status}${this.pendingCount ? ` · outbox ${this.pendingCount}` : ''}</p>
            </div>
            ${showChromeNav
              ? html`
                  <div class="top-search-wrap">
                    <input
                      class="top-search"
                      type="search"
                      placeholder="Search…"
                      .value=${this.globalSearch}
                      @input=${(e: Event) =>
                        void this.onGlobalSearchInput((e.target as HTMLInputElement).value)}
                      @focus=${() => {
                        if (this.globalSearch.trim().length >= 2) this.searchOpen = true;
                      }}
                      @keydown=${(e: KeyboardEvent) => {
                        if (e.key === 'Escape') {
                          this.searchOpen = false;
                          this.globalSearch = '';
                          this.searchHits = [];
                        }
                      }}
                    />
                    ${this.searchOpen ? this.renderSearchDropdown() : nothing}
                  </div>
                `
              : nothing}
            <span class="pill ${this.online ? '' : 'offline'}">${this.online ? 'Online' : 'Offline'}</span>
            <button class="icon-btn" ?disabled=${this.syncing} @click=${() => this.runSync()} title="Sync">
              ↻
            </button>
          </header>
          ${this.syncing ? this.renderSyncProgressBar() : nothing}
        </div>

        <div class="body ${showChromeNav ? 'has-bottom' : ''}">
          ${this.route.kind === 'launcher'
            ? this.renderLauncher()
            : html`
                <div class="layout-wide">
                  <nav class="rail" aria-label="App navigation">
                    ${this.navItems().map(
                      (n) => html`
                        <button class=${n.active ? 'active' : ''} @click=${n.action}>
                          ${renderIconTile(n.iconName, { iconUrl: n.iconUrl, size: 32 })}
                          ${n.label}
                        </button>
                      `
                    )}
                  </nav>
                  <div class="main-pane">${this.renderMain()}</div>
                </div>
              `}
        </div>

        ${showChromeNav
          ? html`
              <nav class="bottom-nav" aria-label="Bottom navigation">
                ${this.navItems().map(
                  (n) => html`
                    <button class=${n.active ? 'active' : ''} @click=${n.action}>
                      ${renderIconTile(n.iconName, { iconUrl: n.iconUrl, size: 28 })}
                      ${n.label}
                    </button>
                  `
                )}
              </nav>
            `
          : nothing}
        ${this.modalOpen ? this.renderRecordModal() : nothing}
        ${this.visitShellId ? this.renderVisitShellOverlay() : nothing}
        ${this.clmPlayerOverlayOpen && this.clmPlayerId ? this.renderClmPlayerOverlay() : nothing}
        ${this.renderSyncOverlay()}
        ${this.toastMessage
          ? html`<div class="osr-toast" role="status">${this.toastMessage}</div>`
          : nothing}
        ${this.syncValidationSummary && !this.syncing
          ? html`<div class="osr-toast" style="bottom:4.5rem;opacity:.95" role="status">
              ${this.syncValidationSummary}
            </div>`
          : nothing}
        ${this.lwcCompatSummary && !this.syncing && !this.syncValidationSummary
          ? html`<div class="osr-toast" style="bottom:4.5rem;opacity:.92" role="status">${this.lwcCompatSummary}</div>`
          : nothing}
      </div>
    `;
  }

  private renderSearchDropdown() {
    return html`
      <div class="search-dropdown" role="listbox">
        ${this.searchHits.length === 0
          ? html`<div class="empty-hit">No matches in offline data</div>`
          : this.searchHits.map(
              (h) => html`
                <button
                  role="option"
                  @click=${() => void this.openRecord(h.objectApi, String(h.record.Id))}
                >
                  ${renderIconTile(h.objectApi, { size: 28, className: 'row-icon' })}
                  <div>
                    <strong>${recordTitle(h.record)}</strong>
                    <small>${h.objectApi} · ${recordSubtitle(h.record) || String(h.record.Id)}</small>
                  </div>
                </button>
              `
            )}
      </div>
    `;
  }

  private renderLogin() {
    const env = this.loginEnv;
    const customReady = !!myDomainLoginUrlFromLabel(this.customDomainInput);
    const themed = env === 'custom' && customReady;
    return html`
      <div class="login">
        <div class="login-card">
          <div class="login-brand">
            <img src="/salesforce-cloud.png" alt="Salesforce" width="180" height="120" />
          </div>
          <h1>Offline Runtime</h1>
          <p>Sign in with your Salesforce org. Works offline after sync.</p>
          ${themed
            ? html`<div class="login-theme-note">
                My Domain login — Salesforce will show your org’s themed login page.<br />
                <code>${this.loginUrl}</code>
              </div>`
            : nothing}
          <div class="field">
            <label>Environment</label>
            <select
              .value=${env}
              @change=${(e: Event) => {
                const v = (e.target as HTMLSelectElement).value as
                  | 'production'
                  | 'sandbox'
                  | 'custom';
                this.setLoginEnvironment(v);
              }}
            >
              <option value="production">Production</option>
              <option value="sandbox">Sandbox</option>
              <option value="custom">Custom Domain</option>
            </select>
          </div>
          ${env === 'custom'
            ? html`<div class="field">
                <label>My Domain</label>
                <div class="domain-combo">
                  <input
                    type="text"
                    placeholder="abcd"
                    inputmode="url"
                    autocomplete="off"
                    autocapitalize="off"
                    spellcheck="false"
                    aria-label="My Domain name"
                    .value=${this.customDomainInput}
                    @input=${(e: Event) => {
                      this.applyCustomDomainInput((e.target as HTMLInputElement).value);
                    }}
                  />
                  <span class="domain-suffix">${MY_DOMAIN_SUFFIX}</span>
                </div>
              </div>`
            : nothing}
          <button
            class="primary"
            ?disabled=${env === 'custom' && !customReady}
            @click=${async () => {
              if (!this.db) return;
              const resolved =
                env === 'custom'
                  ? myDomainLoginUrlFromLabel(this.customDomainInput) || this.loginUrl
                  : this.loginUrl;
              this.loginUrl = resolved;
              this.status = themed
                ? 'Opening themed Salesforce login…'
                : 'Opening Salesforce login…';
              try {
                await beginSalesforceLogin(this.db, { loginUrl: resolved });
              } catch (e) {
                this.status = `Login failed: ${e instanceof Error ? e.message : String(e)}`;
              }
            }}
          >
            Log In to Salesforce
          </button>
          ${this.status && this.status !== 'Sign in to Salesforce'
            ? html`<p class="danger-text" style="margin-top:12px">${this.status}</p>`
            : nothing}
          <p style="margin-top:16px;font-size:12px;color:var(--sf-muted)">
            ${Capacitor.isNativePlatform() ? 'Native app' : 'Web'} · PKCE OAuth
            ${!Capacitor.isNativePlatform()
              ? html` · tip: <code>?domain=abcd</code>`
              : nothing}
          </p>
        </div>
      </div>
    `;
  }

  private renderLauncher() {
    const q = this.launcherFilter.trim().toLowerCase();
    const apps = this.apps.filter(
      (a) => !q || a.label.toLowerCase().includes(q) || a.developerName.toLowerCase().includes(q)
    );
    return html`
      <div class="launcher">
        <h2>App Launcher</h2>
        <input
          class="search"
          placeholder="Search apps"
          .value=${this.launcherFilter}
          @input=${(e: Event) => {
            this.launcherFilter = (e.target as HTMLInputElement).value;
          }}
        />
        ${apps.length === 0
          ? html`<div class="empty">No apps synced yet. Tap sync, or check Sync Pack profile Apps.</div>`
          : html`
              <div class="app-grid">
                ${apps.map((a) => {
                  const imgUrl = a.iconUrl || null;
                  return html`
                    <button class="app-tile" @click=${() => this.selectApp(a.developerName)}>
                      ${imgUrl
                        ? html`<div class="app-icon has-img">
                            <img
                              src=${imgUrl}
                              alt=""
                              width="32"
                              height="32"
                              decoding="async"
                              @error=${(e: Event) => {
                                const img = e.target as HTMLImageElement;
                                const parent = img.parentElement!;
                                img.remove();
                                parent.classList.remove('has-img');
                                parent.style.background = iconFor(a.developerName).color;
                                parent.replaceChildren();
                                // Force re-render via SLDS path inject
                                const svgNs = 'http://www.w3.org/2000/svg';
                                const svgEl = document.createElementNS(svgNs, 'svg');
                                svgEl.setAttribute('viewBox', '0 0 52 52');
                                svgEl.setAttribute('width', '20');
                                svgEl.setAttribute('height', '20');
                                const path = document.createElementNS(svgNs, 'path');
                                path.setAttribute('fill', '#fff');
                                path.setAttribute(
                                  'd',
                                  (SLDS_ICON_MAP[iconFor(a.developerName).key] ?? SLDS_ICON_MAP.custom!)
                                    .path
                                );
                                svgEl.appendChild(path);
                                parent.appendChild(svgEl);
                              }}
                            />
                          </div>`
                        : renderIconTile(a.developerName, { size: 40, className: 'app-icon' })}
                      <span>${a.label}</span>
                    </button>
                  `;
                })}
              </div>
            `}
        <div style="margin-top:20px;text-align:center">
          <button class="ghost" @click=${() => this.logout()}>Log Out</button>
        </div>
      </div>
    `;
  }

  private renderMain() {
    switch (this.route.kind) {
      case 'home':
        return this.renderHome();
      case 'list':
        return this.renderList();
      case 'tab':
        return this.renderCustomTab();
      case 'record':
        // Legacy route — prefer modal; fall back to list if we somehow land here
        return this.renderList();
      case 'menu':
        return this.renderMenu();
      case 'conflicts':
        return this.renderConflicts();
      case 'logs':
        return this.renderSupportLogs();
      default:
        return this.renderHome();
    }
  }

  private renderHome() {
    const page = this.homeFlexi;
    return html`
      <div class="page">
        <div class="list-toolbar">
          <h2>Home</h2>
          <button
            class="ghost"
            @click=${() => {
              this.route = { kind: 'launcher' };
            }}
          >
            App Launcher
          </button>
        </div>
        ${page
          ? this.renderFlexiRegions(page, 'home')
          : html`
              <section class="comp-card">
                <header>Home</header>
                <div class="body-pad">
                  <div class="sf-empty">
                    <strong>No Home page synced</strong>
                    Sync while online to load this app&apos;s Home FlexiPage.
                  </div>
                  <div class="cta-row">
                    <button
                      class="primary"
                      style="width:auto;padding:0 16px"
                      @click=${() => this.runSync()}
                    >
                      Sync now
                    </button>
                  </div>
                </div>
              </section>
            `}
      </div>
    `;
  }

  private renderOsrTodayWork() {
    const work = this.workObject;
    const list = this.filterTodayWork(this.homeWorkRows).slice(0, 6);
    const header = work
      ? work.apiName === 'Visit__c' || work.apiName === 'Visit'
        ? "Today's Visits"
        : `Today's ${work.label}`
      : "Today's Plan";
    return html`
      <section class="comp-card">
        <header>${header}</header>
        <div class="body-pad">
          ${!work || list.length === 0
            ? html`<div class="sf-empty"><strong>No items to display</strong></div>`
            : list.map(
                (r) => html`
                  <button class="row" @click=${() => this.openRecord(work.apiName, String(r.Id))}>
                    ${renderIconTile(work.apiName, { size: 32, className: 'row-icon' })}
                    <div>
                      <strong>${recordTitle(r)}</strong>
                      <small>${recordSubtitle(r)}</small>
                    </div>
                  </button>
                `
              )}
          ${work
            ? html`
                <div class="cta-row">
                  <button
                    class="ghost"
                    style="padding-left:0"
                    @click=${() => this.openList(work.apiName)}
                  >
                    View All
                  </button>
                </div>
              `
            : nothing}
        </div>
      </section>
    `;
  }

  private renderOsrRecentRecords() {
    const recent = this.recentObject;
    const rows = this.homeRecentRows.slice(0, 6);
    const isAccounts = recent?.apiName === 'Account';
    const header = recent ? (isAccounts ? 'Accounts' : `Recent ${recent.label}`) : 'Recent';
    return html`
      <section class="comp-card">
        <header>${header}</header>
        <div class="body-pad">
          ${!recent || rows.length === 0
            ? html`<div class="sf-empty"><strong>No items to display</strong></div>`
            : rows.map(
                (r) => html`
                  <button class="row" @click=${() => this.openRecord(recent.apiName, String(r.Id))}>
                    ${renderIconTile(recent.apiName, { size: 32, className: 'row-icon' })}
                    <div>
                      <strong>${recordTitle(r)}</strong>
                      <small>${recordSubtitle(r)}</small>
                    </div>
                  </button>
                `
              )}
          ${recent
            ? html`
                <div class="cta-row">
                  <button
                    class="ghost"
                    style="padding-left:0"
                    @click=${() => this.openList(recent.apiName)}
                  >
                    View All
                  </button>
                </div>
              `
            : nothing}
        </div>
      </section>
    `;
  }

  private renderOsrQuickLinks() {
    const links = this.appNavTabs().slice(0, 8);
    return html`
      <section class="comp-card">
        <header>Quick Links</header>
        <div class="body-pad">
          ${links.length === 0
            ? html`<div class="sf-empty"><strong>No items to display</strong></div>`
            : links.map((t) => {
                const iconName = t.tab.objectApi ?? t.developerName;
                return html`
                  <button class="row" @click=${() => void this.openAppTab(t)}>
                    ${renderIconTile(iconName, { size: 32, className: 'row-icon' })}
                    <div>
                      <strong>${t.label}</strong>
                      <small>${this.tabTypeOf(t)}</small>
                    </div>
                  </button>
                `;
              })}
        </div>
      </section>
    `;
  }

  private renderOsrSyncStatus() {
    return html`
      <section class="comp-card">
        <header>Offline Sync</header>
        <div class="body-pad rich-text">
          <div><strong>Mode:</strong> ${this.syncMode}</div>
          <div><strong>Outbox:</strong> ${this.pendingCount}</div>
          <div><strong>Conflicts:</strong> ${this.conflicts.length}</div>
          <div class="cta-row" style="padding-left:0;border:none">
            <button class="ghost" style="padding-left:0" @click=${() => this.runSync()}>
              Sync now
            </button>
          </div>
        </div>
      </section>
    `;
  }

  private renderFlexiRegions(page: FlexiPageModel, prefix: string) {
    const regions = selectRegionsForFormFactor(
      page.regions ?? [],
      this.formFactor,
      page.templates
    );

    const renderRegion = (r: { name: string; components: FlexiComponent[] }) =>
      r.components
        .filter((c) => isComponentVisible(c.visibilityRule, this.record))
        .map((c, i) => this.renderComponent(c, `${prefix}-${r.name}-${i}`));

    if (isFieldHomeLayout(page.type, regions)) {
      const plan = planFieldHomeRegions(
        regions.map((r) => ({
          name: r.name,
          components: r.components as FlexiComponent[]
        })),
        this.formFactor
      );
      // Single-region AppPage (Field_Rep_Home_App): sort the main stack by LWC priority
      if (plan.main.length === 1 && !plan.side) {
        plan.main[0] = {
          ...plan.main[0],
          components: sortFieldHomeComponents(plan.main[0].components as FlexiComponent[])
        };
      }
      return html`
        <div class="home-flexi" data-flexi-order="field-home" data-form-factor=${this.formFactor}>
          <div class="home-flexi-body ${plan.side ? 'has-sidebar' : ''}">
            <div class="home-flexi-main regions">
              ${plan.main.map((r) =>
                renderRegion({ name: r.name, components: r.components as FlexiComponent[] })
              )}
            </div>
            ${plan.side
              ? html`<div class="home-flexi-side regions">${renderRegion({
                  name: plan.side.name,
                  components: plan.side.components as FlexiComponent[]
                })}</div>`
              : nothing}
          </div>
        </div>
      `;
    }

    // Preserve metadata region order; only split named sidebar for wide layout.
    const hasSidebar =
      this.formFactor !== 'Small' && regions.some((r) => r.name === 'sidebar');
    if (!hasSidebar) {
      return html`
        <div class="region-grid" data-flexi-order="preserved" data-form-factor=${this.formFactor}>
          <div class="regions">
            ${regions.map((r) => renderRegion(r))}
          </div>
        </div>
      `;
    }
    return html`
      <div class="region-grid has-sidebar" data-flexi-order="preserved" data-form-factor=${this.formFactor}>
        <div class="regions">
          ${regions.filter((r) => r.name !== 'sidebar').map((r) => renderRegion(r))}
        </div>
        <div class="regions">
          ${regions.filter((r) => r.name === 'sidebar').map((r) => renderRegion(r))}
        </div>
      </div>
    `;
  }

  private renderComponent(c: FlexiComponent, hostId: string) {
    const type = c.type || '';
    const bundle = lwcBundleFromComponent(c);
    const rawLabel =
      c.attributes?.label ??
      c.attributes?.title ??
      c.attributes?.masterLabel ??
      c.attributes?.Name;
    const label = String(
      rawLabel && String(rawLabel).trim()
        ? rawLabel
        : bundle
          ? humanizeComponentLabel(bundle)
          : humanizeComponentLabel(type)
    );

    if (type === 'osr:todayVisits') return this.renderOsrTodayWork();
    if (type === 'osr:recentAccounts') return this.renderOsrRecentRecords();
    if (type === 'osr:quickLinks') return this.renderOsrQuickLinks();
    if (type === 'osr:syncStatus') return this.renderOsrSyncStatus();

    if (type === 'force:highlightsPanel') {
      return this.renderHighlightsCard();
    }
    if (type === 'force:pathAssistant') {
      const pathField =
        String(c.attributes?.picklistApiName ?? '') ||
        this.layout?.pathField ||
        'Status__c';
      return this.renderPath(String(pathField));
    }
    if (
      type === 'flexipage:fieldSection' ||
      type.includes('fieldSection') ||
      type === 'flexipage:fieldInstance'
    ) {
      const section = resolveFieldSectionFields(
        c.attributes,
        c.fieldInstances,
        this.layout as Parameters<typeof resolveFieldSectionFields>[2]
      );
      return html`
        <section class="comp-card">
          <header>${section.label || label || 'Details'}</header>
          <div class="body-pad">${this.renderFieldSection(section.fields)}</div>
        </section>
      `;
    }
    if (type.includes('relatedList')) {
      const relName = String(
        c.attributes?.relatedListApiName ?? c.attributes?.relatedListName ?? 'Related'
      );
      return html`
        <section class="comp-card">
          <header>${relName}</header>
          <div class="body-pad">${this.renderRelated(relName)}</div>
        </section>
      `;
    }
    if (type === 'flexipage:richText' || type.includes('richText')) {
      return html`
        <section class="comp-card">
          <header>${label}</header>
          <div class="body-pad rich-text">${String(c.attributes?.body ?? '')}</div>
        </section>
      `;
    }

    // Custom LWCs (c:foo / c/foo / ns:foo)
    if (bundle || isCustomLwcType(type)) {
      const b = bundle ?? type;
      if (isFidelityBundle(b)) {
        const fidelity = this.renderFidelityBundle(b, label);
        if (fidelity) return fidelity;
      }
      return html`
        <section class="comp-card">
          <header>${label || humanizeComponentLabel(b)}</header>
          <div class="body-pad">
            <div class="lwc-host" data-lwc-host=${hostId}></div>
          </div>
        </section>
      `;
    }

    return html`
      <section class="comp-card">
        <header>${humanizeComponentLabel(type)}</header>
        <div class="body-pad">
          <div class="sf-empty"><strong>No items to display</strong></div>
          <div class="sf-empty" style="margin-top:8px;font-size:12px;opacity:.7">
            Unsupported offline (${type})
          </div>
        </div>
      </section>
    `;
  }

  private renderList() {
    if (this.route.kind !== 'list' && this.route.kind !== 'record') return nothing;
    const objectApi =
      this.route.kind === 'list'
        ? this.route.objectApi
        : this.route.kind === 'record'
          ? this.route.objectApi
          : '';
    if (!objectApi) return nothing;
    const rows = this.filteredListRows();
    const listFilterWarning = this.currentListFilterWarning();
    const describeDates = dateFieldsFromDescribe(this.objectDescribe).map((f) => f.name);
    const dateField = detectDateFieldSmart(
      this.listRows,
      this.calendarFieldPref,
      describeDates,
      this.fieldMeta
    );
    const activeView = this.objectListViews.find(
      (v) => v.id === this.activeListViewId || v.developerName === this.activeListViewId
    );
    const kanbanField = detectKanbanFieldSmart(
      this.listRows,
      activeView?.kanbanGroupField,
      this.fieldMeta
    );
    const listColumns =
      this.listColumns.length > 0
        ? this.listColumns
        : columnsForView(activeView).filter(
            (c) =>
              this.fieldMeta.some((f) => f.name === c) ||
              this.listRows.some((r) => r[c] != null) ||
              c === 'Name'
          );
    const searchFields = searchableFieldsForObject(this.fieldMeta, listColumns, this.listRows);
    const objectLabel =
      (this.objectDescribe?.label as string | undefined) ??
      objectApi.replace(/__c$/, '').replace(/_/g, ' ');
    const modes: { id: ListViewMode; label: string; enabled: boolean }[] = [
      { id: 'list', label: 'List', enabled: true },
      { id: 'cards', label: 'Cards', enabled: true },
      {
        id: 'calendar',
        label: 'Calendar',
        enabled: !!dateField || describeDates.length > 0
      },
      { id: 'kanban', label: 'Kanban', enabled: !!kanbanField }
    ];
    const mode =
      modes.find((m) => m.id === this.listViewMode && m.enabled)?.id ??
      ('list' as ListViewMode);
    const favSet = new Set(this.favouriteListViewIds);
    const calFields = dateFieldsFromDescribe(this.objectDescribe);

    return html`
      <div class="page crmhub-list">
        <div class="list-toolbar">
          <div>
            <h2>${this.titleText()}</h2>
            <p style="margin:0;font-size:12px;color:var(--sf-muted)">
              ${crmHubSubtitle({
                shown: rows.length,
                total: this.listRows.length,
                viewLabel: this.currentListViewLabel(),
                mode,
                offline: !this.online
              })}
            </p>
          </div>
          <button
            class="primary"
            style="width:auto;padding:0 16px"
            @click=${async () => {
              if (!this.db) return;
              const id = `local_${Date.now()}`;
              await this.openRecord(objectApi, id);
              this.record = { Id: id, Name: '' };
              this.editing = true;
            }}
          >
            New
          </button>
        </div>
        <div class="list-chrome" style="margin-bottom:8px">
          <input
            class="slds-input"
            type="search"
            placeholder=${crmHubSearchPlaceholder(objectLabel, searchFields.length)}
            .value=${this.objectListSearch}
            @input=${(e: Event) => {
              this.objectListSearch = (e.target as HTMLInputElement).value;
            }}
          />
        </div>
        ${listFilterWarning
          ? html`<div class="pill offline" style="margin:0 0 8px;display:inline-block">
              ${listFilterWarning}
            </div>`
          : nothing}
        <div class="list-chrome">
          <div class="list-chrome-row">
            <div class="lv-picker">
              <button
                class="lv-picker-trigger"
                type="button"
                @click=${() => {
                  this.listPickerOpen = !this.listPickerOpen;
                }}
              >
                <span>${this.currentListViewLabel()}</span>
                <span aria-hidden="true">▾</span>
              </button>
              ${this.listPickerOpen
                ? html`
                    <div class="lv-picker-menu" role="listbox">
                      ${[
                        { id: 'all', label: 'All' },
                        { id: 'recent', label: 'Recently Viewed' }
                      ].map(
                        (opt) => html`
                          <div
                            class="lv-option ${this.activeListViewId === opt.id ? 'active' : ''}"
                          >
                            <button
                              class="lv-select"
                              type="button"
                              @click=${() => {
                                this.activeListViewId = opt.id;
                                this.listPickerOpen = false;
                                this.refreshListColumns();
                              }}
                            >
                              ${opt.label}
                            </button>
                          </div>
                        `
                      )}
                      ${this.sortedListViews().map((v) => {
                        const isFav = favSet.has(v.id) || favSet.has(v.developerName);
                        const isPin = this.pinnedListViewId === v.id;
                        const isActive = this.activeListViewId === v.id;
                        return html`
                          <div class="lv-option ${isActive ? 'active' : ''}">
                            <button
                              class="lv-select"
                              type="button"
                              @click=${() => {
                                this.activeListViewId = v.id;
                                this.listPickerOpen = false;
                                this.refreshListColumns();
                              }}
                            >
                              ${v.label}${isPin ? ' · pinned' : ''}${isFav ? ' · ★' : ''}
                            </button>
                            <button
                              class="lv-icon-btn ${isFav ? 'on' : ''}"
                              type="button"
                              title=${isFav ? 'Remove favourite' : 'Favourite'}
                              aria-label=${isFav ? 'Remove favourite' : 'Favourite'}
                              @click=${(e: Event) => {
                                e.stopPropagation();
                                void this.toggleFavourite(objectApi, v.id);
                              }}
                            >
                              ${isFav ? '★' : '☆'}
                            </button>
                            <button
                              class="lv-icon-btn ${isPin ? 'on' : ''}"
                              type="button"
                              title=${isPin ? 'Unpin' : 'Pin as default'}
                              aria-label=${isPin ? 'Unpin' : 'Pin as default'}
                              @click=${(e: Event) => {
                                e.stopPropagation();
                                void this.togglePin(objectApi, v.id);
                              }}
                            >
                              ${isPin ? 'Pinned' : 'Pin'}
                            </button>
                          </div>
                        `;
                      })}
                    </div>
                  `
                : nothing}
            </div>
            <div class="view-mode-toggle" role="group" aria-label="View mode">
              ${modes.map(
                (m) => html`
                  <button
                    class=${mode === m.id ? 'active' : ''}
                    ?disabled=${!m.enabled}
                    title=${m.enabled ? m.label : `${m.label} unavailable`}
                    @click=${() => {
                      if (!m.enabled) return;
                      if (m.id === 'calendar') this.requestCalendarMode(objectApi);
                      else this.listViewMode = m.id;
                    }}
                  >
                    ${m.label}
                  </button>
                `
              )}
            </div>
          </div>
          ${mode === 'calendar' && dateField
            ? html`<div style="font-size:12px;color:var(--sf-muted)">
                Calendar field:
                <button
                  class="ghost"
                  style="padding:0;font-size:12px"
                  @click=${() => {
                    this.calendarPickerOpen = true;
                  }}
                >
                  ${this.fieldLabel(dateField)} (${dateField})
                </button>
              </div>`
            : nothing}
          ${mode === 'kanban' && kanbanField
            ? html`<div style="font-size:12px;color:var(--sf-muted)">
                Board by ${this.fieldLabel(kanbanField)} (${kanbanField})
              </div>`
            : nothing}
        </div>
        ${this.listRows.length === 0
          ? html`<div class="empty">No offline records for ${objectLabel}. Sync while online.</div>`
          : rows.length === 0
            ? html`<div class="empty">
                ${this.objectListSearch.trim()
                  ? `No ${objectLabel} match “${this.objectListSearch.trim()}”.`
                  : 'No records in this list view.'}
              </div>`
            : mode === 'cards'
              ? this.renderCardsView(objectApi, rows)
              : mode === 'calendar' && dateField
                ? this.renderCalendarView(objectApi, rows, dateField)
                : mode === 'kanban' && kanbanField
                  ? this.renderKanbanView(objectApi, rows, kanbanField)
                  : this.renderTableView(objectApi, rows, listColumns)}
        ${this.calendarPickerOpen
          ? html`
              <div
                class="cal-picker-backdrop"
                @click=${(e: Event) => {
                  if (e.target === e.currentTarget) this.calendarPickerOpen = false;
                }}
              >
                <div class="cal-picker" role="dialog" aria-modal="true" aria-label="Calendar field">
                  <h3>Calendar date field</h3>
                  <p>Choose which Date or Date/Time field to use for ${objectApi}.</p>
                  <select
                    id="osr-cal-field"
                    .value=${this.calendarFieldPref ?? calFields[0]?.name ?? ''}
                  >
                    ${calFields.length
                      ? calFields.map(
                          (f) => html`<option value=${f.name}>${f.label} (${f.name})</option>`
                        )
                      : html`<option value="">No date fields found</option>`}
                  </select>
                  <div class="cal-picker-actions">
                    <button
                      type="button"
                      @click=${() => {
                        this.calendarPickerOpen = false;
                      }}
                    >
                      Cancel
                    </button>
                    <button
                      class="primary"
                      type="button"
                      style="width:auto;padding:0 16px"
                      ?disabled=${!calFields.length}
                      @click=${() => {
                        const sel = this.renderRoot.querySelector(
                          '#osr-cal-field'
                        ) as HTMLSelectElement | null;
                        void this.saveCalendarField(objectApi, sel?.value ?? '');
                      }}
                    >
                      Use field
                    </button>
                  </div>
                </div>
              </div>
            `
          : nothing}
      </div>
    `;
  }

  private renderTableView(
    objectApi: string,
    rows: Record<string, unknown>[],
    columns?: string[]
  ) {
    const cols = columns?.length ? columns : this.listColumns.length ? this.listColumns : ['Name'];
    const allowInline = this.formFactor === 'Large';
    return html`
      <div style="overflow-x:auto">
        <table class="list-table">
          <thead>
            <tr>
              ${cols.map((c) => html`<th>${this.fieldLabel(c)}</th>`)}
            </tr>
          </thead>
          <tbody>
            ${rows.map((r) => {
              const id = String(r.Id ?? '');
              return html`
                <tr>
                  ${cols.map((c) => {
                    const editing =
                      allowInline &&
                      this.inlineEditId === id &&
                      this.inlineEditField === c;
                    const info = this.fieldInfo(c);
                    const canEdit =
                      allowInline &&
                      info?.type !== 'reference' &&
                      c !== 'Id';
                    return html`
                      <td
                        @dblclick=${(e: Event) => {
                          e.stopPropagation();
                          if (!canEdit) {
                            void this.openRecord(objectApi, id);
                            return;
                          }
                          this.inlineEditId = id;
                          this.inlineEditField = c;
                          this.inlineEditValue = String(r[c] ?? '');
                        }}
                        @click=${() => {
                          if (!editing) void this.openRecord(objectApi, id);
                        }}
                      >
                        ${editing
                          ? html`<input
                              .value=${this.inlineEditValue}
                              @click=${(e: Event) => e.stopPropagation()}
                              @input=${(e: Event) => {
                                this.inlineEditValue = (e.target as HTMLInputElement).value;
                              }}
                              @keydown=${(e: KeyboardEvent) => {
                                if (e.key === 'Enter') void this.commitInlineEdit(objectApi);
                                if (e.key === 'Escape') {
                                  this.inlineEditId = null;
                                  this.inlineEditField = null;
                                }
                              }}
                              @blur=${() => void this.commitInlineEdit(objectApi)}
                            />`
                          : c === cols[0]
                            ? html`<strong>${String(r[c] ?? recordTitle(r))}</strong>`
                            : String(r[c] ?? '—')}
                      </td>
                    `;
                  })}
                </tr>
              `;
            })}
          </tbody>
        </table>
      </div>
    `;
  }

  private renderCardsView(objectApi: string, rows: Record<string, unknown>[]) {
    return html`
      <div class="card-grid">
        ${rows.map((r) => {
          const id = String(r.Id ?? '');
          return html`
            <button class="record-card" @click=${() => void this.openRecord(objectApi, id)}>
              ${renderIconTile(objectApi, { size: 28, className: 'row-icon' })}
              <strong>${recordTitle(r)}</strong>
              <small>${recordSubtitle(r) || id}</small>
            </button>
          `;
        })}
      </div>
    `;
  }

  private renderCalendarView(
    objectApi: string,
    rows: Record<string, unknown>[],
    dateField: string
  ) {
    const groups = groupByCalendarDay(rows, dateField);
    return html`
      ${groups.map(
        (g) => html`
          <div class="calendar-day">
            <h3>${formatDayHeading(g.day)}</h3>
            ${g.rows.map((r) => {
              const id = String(r.Id ?? '');
              return html`
                <button class="row" @click=${() => void this.openRecord(objectApi, id)}>
                  ${renderIconTile(objectApi, { size: 32, className: 'row-icon' })}
                  <div>
                    <strong>${recordTitle(r)}</strong>
                    <small>${recordSubtitle(r) || id}</small>
                  </div>
                </button>
              `;
            })}
          </div>
        `
      )}
    `;
  }

  private renderKanbanView(objectApi: string, rows: Record<string, unknown>[], field: string) {
    const cols = groupByKanban(rows, field);
    return html`
      <div class="kanban-board">
        ${cols.map(
          (c) => html`
            <div class="kanban-col">
              <h3>${c.key} (${c.rows.length})</h3>
              ${c.rows.map((r) => {
                const id = String(r.Id ?? '');
                return html`
                  <button class="row" @click=${() => void this.openRecord(objectApi, id)}>
                    <div>
                      <strong>${recordTitle(r)}</strong>
                      <small>${workDateValue(r) || id}</small>
                    </div>
                  </button>
                `;
              })}
            </div>
          `
        )}
      </div>
    `;
  }

  private renderRecordModal() {
    if (!this.modalOpen) return nothing;
    const title = String(
      this.record?.Name ?? this.record?.Subject ?? this.record?.CaseNumber ?? 'Record'
    );
    return html`
      <div
        class="record-modal-backdrop"
        @click=${(e: Event) => {
          if (e.target === e.currentTarget) this.closeRecordModal();
        }}
      >
        <div class="record-modal" role="dialog" aria-modal="true" aria-label=${title}>
          <div class="record-modal-header">
            <button class="ghost" style="padding-left:0" @click=${() => this.closeRecordModal()}>
              ← Back
            </button>
            <h2>${title}</h2>
            <button
              class="record-modal-close"
              title="Close"
              @click=${() => this.closeRecordModal()}
            >
              ×
            </button>
          </div>
          <div class="record-modal-body">${this.renderRecord()}</div>
        </div>
      </div>
    `;
  }

  /** Full-screen visit call report (c/visitCallShell Lit port) — not the generic record form. */
  private renderVisitShellOverlay() {
    if (!this.visitShellId) return nothing;
    return html`
      <div class="visit-shell-overlay" role="dialog" aria-modal="true" aria-label="Visit call report">
        <div class="visit-shell-overlay-header">
          <button
            type="button"
            class="ghost"
            style="padding-left:0"
            @click=${() => {
              this.visitShellId = null;
            }}
          >
            ← Back to Planner
          </button>
          <button
            type="button"
            class="record-modal-close"
            title="Close"
            @click=${() => {
              this.visitShellId = null;
            }}
          >
            ×
          </button>
        </div>
        <div class="visit-shell-overlay-body">
          ${this.renderFidelityBundle('c/visitCallShell', 'Visit Call Report')}
        </div>
      </div>
    `;
  }

  /** CLM player + sentiment/ratings — sits above visit shell so Open actually launches. */
  private renderClmPlayerOverlay() {
    if (!this.clmPlayerId) return nothing;
    return html`
      <div class="clm-player-overlay" role="dialog" aria-modal="true" aria-label="CLM Player">
        <div class="clm-player-overlay-body">
          ${this.renderFidelityBundle('c/clmPlayer', 'CLM Player')}
        </div>
      </div>
    `;
  }

  private async completeClmSession(payload: {
    presentationId: string;
    sessionKey: string;
    visitId?: string | null;
    messages: { name: string; sentiment: string | null }[];
    ratingScore: string;
    ratingNotes: string;
  }) {
    if (!this.db) return;
    try {
      await enqueueClmSession(this.db, {
        actionType: 'complete',
        clientSessionKey: payload.sessionKey,
        visitId: payload.visitId || this.visitShellId || undefined,
        presentationId: payload.presentationId,
        payload: {
          messages: payload.messages,
          ratingScore: payload.ratingScore,
          ratingNotes: payload.ratingNotes,
          completedAt: new Date().toISOString()
        }
      });
      this.pendingCount = (await listPendingOutbox(this.db)).length;
      this.status = 'CLM session queued for sync';
      this.toastMessage = 'CLM sentiment & ratings saved offline';
      window.setTimeout(() => {
        if (this.toastMessage === 'CLM sentiment & ratings saved offline') this.toastMessage = null;
      }, 2800);
    } catch (e) {
      this.status = `CLM save failed: ${e instanceof Error ? e.message : String(e)}`;
    }
  }

  private async rescheduleVisit(visitId: string, startIso: string, endIso: string) {
    if (!this.db || !visitId) return;
    try {
      const start = new Date(startIso);
      const end = new Date(endIso);
      if (Number.isNaN(start.getTime()) || Number.isNaN(end.getTime())) return;
      const existing = (await getRecord(this.db, 'Visit__c', visitId)) ?? { Id: visitId };
      const payload = {
        ...existing,
        Id: visitId,
        StartDateTime__c: start.toISOString(),
        EndDateTime__c: end.toISOString(),
        Planned_Date__c: isoDateLocal(start)
      };
      await localSaveRecord(this.db, 'Visit__c', payload, String(visitId).startsWith('local_'));
      await this.patchPlannerCaches((visits) =>
        visits.map((v) =>
          String(v.id) === visitId
            ? {
                ...v,
                startDateTime: start.toISOString(),
                endDateTime: end.toISOString()
              }
            : v
        )
      );
      this.pendingCount = (await listPendingOutbox(this.db)).length;
      this.status = 'Visit rescheduled · queued for sync';
    } catch (e) {
      this.status = `Could not reschedule: ${e instanceof Error ? e.message : String(e)}`;
    }
  }

  private renderRecord() {
    if (!this.modalOpen) return nothing;
    if (this.modalObjectApi === 'Account' && this.record) {
      const accountId = String(this.record.Id ?? '');
      return html`
        ${this.formErrors.length
          ? html`<p class="danger-text">${this.formErrors.join(' · ')}</p>`
          : nothing}
        ${renderAccountHub({
          recordId: accountId,
          record: this.record,
          snap: this.apexSnapshot,
          editing: this.editing,
          onOpenVisit: (id) => {
            this.closeRecordModal({ keepRoute: true });
            this.visitDetailId = null;
            this.visitShellId = id;
          },
          onOpenAccount: (id) => void this.openRecord('Account', id),
          onToggleEdit: () => {
            this.editing = !this.editing;
          },
          onDelete: () =>
            void this.runObjectAction({
              id: 'delete',
              name: 'Delete',
              label: 'Delete',
              actionType: 'Delete',
              offlineSafe: true
            }),
          detailsSlot: this.editing
            ? html`<section class="comp-card" style="border:0;box-shadow:none;padding:0">
                <div class="body-pad" style="padding:0">${this.renderFieldSection()}</div>
              </section>`
            : nothing,
          requestUpdate: () => this.requestUpdate()
        })}
      `;
    }
    const page = this.flexiPage;
    return html`
      ${this.formErrors.length
        ? html`<p class="danger-text">${this.formErrors.join(' · ')}</p>`
        : nothing}
      ${page
        ? this.renderFlexiRegions(page, 'record')
        : html`${this.renderHighlightsCard()}
            <section class="comp-card">
              <header>Details</header>
              <div class="body-pad">${this.renderFieldSection()}</div>
            </section>
            <section class="comp-card">
              <header>Related</header>
              <div class="body-pad">${this.renderRelated()}</div>
            </section>`}
    `;
  }

  private renderHighlightsCard() {
    const name = String(this.record?.Name ?? this.record?.Subject ?? 'New record');
    const objectApi = this.modalObjectApi;
    const objectLabel =
      (this.objectDescribe?.label as string | undefined) ?? objectApi;
    const preferred =
      this.compactFields.length > 0
        ? this.compactFields
        : this.layout?.highlightsFields?.length
          ? this.layout.highlightsFields
          : [
              'Industry',
              'Phone',
              'Status__c',
              'Planned_Date__c',
              'Visit_Date__c',
              'Status',
              'StageName',
              'Subject',
              'ActivityDate',
              'Account__c',
              'AccountId'
            ];
    const fields = preferred
      .filter((f) => f !== 'Name' && f !== 'Subject')
      .filter((f) => this.record && this.record[f] != null && this.record[f] !== '')
      .slice(0, 4);
    const actions =
      this.objectActions.length > 0
        ? this.objectActions
        : [
            { id: 'edit', name: 'Edit', label: 'Edit', actionType: 'Edit', offlineSafe: true },
            { id: 'delete', name: 'Delete', label: 'Delete', actionType: 'Delete', offlineSafe: true }
          ];
    return html`
      <div class="highlights">
        <div class="obj">${objectLabel}</div>
        <h2>${name}</h2>
        <div class="hl-fields">
          ${fields.map((f) => {
            const info = this.fieldInfo(f);
            const lookup = this.lookupNames[f];
            return html`
              <div>
                <span>${this.fieldLabel(f)}</span>
                <strong>
                  ${info?.type === 'reference' && lookup
                    ? lookup.objectApi && lookup.id
                      ? html`<button
                          class="lookup-link"
                          type="button"
                          @click=${() => void this.openRecord(lookup.objectApi!, lookup.id)}
                        >
                          ${lookup.name || lookup.id}
                        </button>`
                      : lookup.name || String(this.record?.[f] ?? '—')
                    : String(this.record?.[f] ?? '—')}
                </strong>
              </div>
            `;
          })}
        </div>
        <div class="actions">
          ${actions.slice(0, 6).map((a) => {
            const kind = classifyActionKind(a);
            const disabled = kind === 'unsupported';
            if (a.name === 'Edit' || kind === 'edit') {
              return html`<button
                ?disabled=${disabled}
                title=${disabled ? 'Unavailable offline' : a.label}
                @click=${() => {
                  this.editing = !this.editing;
                }}
              >
                ${this.editing ? 'Cancel' : a.label}
              </button>`;
            }
            return html`<button
              ?disabled=${disabled}
              title=${disabled ? 'Unavailable offline' : a.label}
              @click=${() => void this.runObjectAction(a)}
            >
              ${a.label}
            </button>`;
          })}
          ${this.editing
            ? html`<button @click=${() => this.saveRecord()}>Save</button>`
            : nothing}
        </div>
      </div>
    `;
  }

  private renderPath(field: string) {
    const fromLayout = this.layout?.pathValues?.length ? this.layout.pathValues : null;
    const info = this.fieldInfo(field);
    const fromPicklist = info?.picklistValues?.map((p) =>
      typeof p === 'string' ? p : String((p as { value?: string }).value ?? p)
    );
    const stages =
      fromLayout ??
      fromPicklist ??
      ['Planned', 'In Progress', 'Completed', 'Cancelled'];
    const current = String(this.record?.[field] ?? stages[0] ?? '');
    return html`
      <div class="path">
        ${stages.map(
          (s) => html`<div class="path-step ${s === current ? 'active' : ''}">${s}</div>`
        )}
      </div>
    `;
  }

  private renderTypedFieldEditor(key: string, behavior?: string) {
    const info = this.fieldInfo(key);
    const val = this.record?.[key];
    const lookup = this.lookupNames[key];
    const isLookup = info?.type === 'reference';
    const readonly = isFieldReadonly(behavior) || !this.editing;
    const required = isFieldRequired(behavior, info?.required);
    const err = this.fieldErrors[key];
    const label = html`${this.fieldLabel(key)}${required ? ' *' : ''}`;

    if (readonly || isLookup) {
      return html`
        <label class=${err ? 'field-error' : ''}>
          ${label}
          ${isLookup && lookup
            ? html`<span class="field-readonly">
                ${lookup.objectApi && lookup.id
                  ? html`<button
                      class="lookup-link"
                      type="button"
                      @click=${() => void this.openRecord(lookup.objectApi!, lookup.id)}
                    >
                      ${lookup.name || lookup.id}
                    </button>`
                  : lookup.name || String(val ?? '—')}
              </span>`
            : html`<span class="field-readonly">${val == null || val === '' ? '—' : String(val)}</span>`}
          ${err ? html`<small style="color:#ba0517">${err}</small>` : nothing}
        </label>
      `;
    }

    const type = info?.type ?? 'string';
    const setVal = (v: unknown) => {
      if (!this.record) return;
      this.record = { ...this.record, [key]: v };
    };

    if (type === 'boolean') {
      return html`
        <label class=${err ? 'field-error' : ''}>
          ${label}
          <input
            type="checkbox"
            .checked=${Boolean(val)}
            @change=${(e: Event) => setVal((e.target as HTMLInputElement).checked)}
          />
          ${err ? html`<small style="color:#ba0517">${err}</small>` : nothing}
        </label>
      `;
    }
    if (type === 'textarea' || type === 'longtextarea') {
      return html`
        <label class=${err ? 'field-error' : ''}>
          ${label}
          <textarea
            .value=${String(val ?? '')}
            @input=${(e: Event) => setVal((e.target as HTMLTextAreaElement).value)}
          ></textarea>
          ${err ? html`<small style="color:#ba0517">${err}</small>` : nothing}
        </label>
      `;
    }
    if (type === 'picklist' && info?.picklistValues?.length) {
      const opts = info.picklistValues.map((p) =>
        typeof p === 'string' ? p : String((p as { value?: string; label?: string }).value ?? p)
      );
      return html`
        <label class=${err ? 'field-error' : ''}>
          ${label}
          <select
            .value=${String(val ?? '')}
            @change=${(e: Event) => setVal((e.target as HTMLSelectElement).value)}
          >
            <option value=""></option>
            ${opts.map((o) => html`<option value=${o} ?selected=${String(val ?? '') === o}>${o}</option>`)}
          </select>
          ${err ? html`<small style="color:#ba0517">${err}</small>` : nothing}
        </label>
      `;
    }
    const inputType =
      type === 'date'
        ? 'date'
        : type === 'datetime'
          ? 'datetime-local'
          : type === 'int' || type === 'double' || type === 'currency' || type === 'percent'
            ? 'number'
            : type === 'email'
              ? 'email'
              : type === 'phone'
                ? 'tel'
                : 'text';
    return html`
      <label class=${err ? 'field-error' : ''}>
        ${label}
        <input
          type=${inputType}
          .value=${String(val ?? '')}
          @input=${(e: Event) => setVal((e.target as HTMLInputElement).value)}
        />
        ${err ? html`<small style="color:#ba0517">${err}</small>` : nothing}
      </label>
    `;
  }

  private renderFieldSection(
    fields?: { field: string; behavior?: string }[]
  ) {
    const resolved =
      fields ??
      (this.layout?.sections ?? [{ label: 'Information', columns: [[{ field: 'Name' }]] }]).flatMap(
        (s) => s.columns.flat()
      );
    return html`
      <div class="field-grid">
        ${resolved.map((f) => this.renderTypedFieldEditor(f.field, f.behavior))}
      </div>
      ${this.formErrors.length
        ? html`<div style="color:#ba0517;margin-top:8px">
            ${this.formErrors.map((e) => html`<div>${e}</div>`)}
          </div>`
        : nothing}
    `;
  }

  private renderRelated(filterName?: string) {
    let lists = this.related;
    if (filterName) {
      const needle = filterName.toLowerCase();
      const matched = lists.filter(
        (r) =>
          r.name.toLowerCase().includes(needle) ||
          needle.includes(r.name.toLowerCase()) ||
          r.objectApi.toLowerCase().includes(needle)
      );
      if (matched.length) lists = matched;
    }
    if (!lists.length) return html`<div class="empty">No related lists</div>`;
    return html`
      ${lists.map(
        (rel) => html`
          <div style="margin-bottom:12px">
            <strong>${rel.name}</strong> (${rel.records.length})
            ${rel.records.slice(0, 8).map((r) => {
              const cols = rel.fields?.length
                ? rel.fields
                : ['Name', 'Status__c', 'Status', 'Subject'];
              const subtitle = cols
                .filter((c) => c !== 'Name' && c !== 'Subject')
                .map((c) => r[c])
                .filter((v) => v != null && String(v) !== '')
                .map(String)
                .slice(0, 2)
                .join(' · ');
              return html`
                <button
                  class="row"
                  style="margin-top:8px"
                  @click=${() => this.openRecord(rel.objectApi, String(r.Id))}
                >
                  <div>
                    <strong>${String(r.Name ?? r.Subject ?? r.Id)}</strong>
                    <small>${subtitle}</small>
                  </div>
                </button>
              `;
            })}
          </div>
        `
      )}
    `;
  }

  private renderMenu() {
    const navTabs = this.appNavTabs();
    return html`
      <div class="page">
        <div class="menu-list">
          <button
            @click=${() => {
              this.route = { kind: 'launcher' };
            }}
          >
            <span>App Launcher (${this.apps.length} apps)</span><span>›</span>
          </button>
          <button @click=${() => this.runSync()}>
            <span>Sync now (${this.syncMode})</span><span>›</span>
          </button>
          <button
            @click=${() => {
              this.route = { kind: 'conflicts' };
            }}
          >
            <span>Conflicts (${this.conflicts.length})</span><span>›</span>
          </button>
          <button
            @click=${() => {
              this.route = { kind: 'logs' };
              void this.refreshSupportLogs();
            }}
          >
            <span>Support logs (${this.supportLogCount})</span><span>›</span>
          </button>
          <button @click=${() => this.logout()}>
            <span>Log Out</span><span>›</span>
          </button>
        </div>
        <h3 style="margin:20px 0 8px;font-size:14px;color:var(--sf-muted)">All tabs in this app</h3>
        <div class="menu-list">
          ${navTabs.length === 0
            ? html`<button disabled><span>No tabs synced</span></button>`
            : navTabs.map((t) => {
                const typ = this.tabTypeOf(t);
                const iconName = t.tab.objectApi ?? t.developerName;
                return html`
                  <button @click=${() => void this.openAppTab(t)}>
                    <span style="display:flex;align-items:center;gap:10px">
                      ${renderIconTile(iconName, {
                        iconUrl: t.tab.iconUrl,
                        size: 28,
                        className: 'row-icon'
                      })}
                      ${t.label}
                      <small style="color:var(--sf-muted)">${typ}</small>
                    </span>
                    <span>›</span>
                  </button>
                `;
              })}
        </div>
      </div>
    `;
  }

  private renderCustomTab() {
    if (this.route.kind !== 'tab') return nothing;
    const dn = this.route.developerName;
    const tab = this.tabs.find((t) => t.developerName === dn);
    const lwcBundle =
      this.clmPlayerId &&
      (this.customTabLwc === 'c/clmPresentationsHub' ||
        tab?.tab.lwcBundle?.includes('clmPresentations'))
        ? 'c/clmPlayer'
        : this.customTabLwc;
    return html`
      <div class="page">
        ${lwcBundle && isFidelityBundle(lwcBundle)
          ? nothing
          : html`<div class="list-toolbar">
              <h2>${tab?.label ?? dn}</h2>
            </div>`}
        ${this.customTabUnsupported
          ? html`<div class="empty">
              <strong>${this.customTabUnsupported}</strong>
            </div>`
          : lwcBundle
            ? isFidelityBundle(lwcBundle)
              ? this.renderFidelityBundle(lwcBundle, tab?.label ?? 'LWC')
              : html`<section class="comp-card">
                    <header>${tab?.label ?? 'LWC'}</header>
                    <div class="body-pad">
                      <div class="lwc-host" data-lwc-host="custom-tab-lwc"></div>
                    </div>
                  </section>`
            : this.customTabFlexi
              ? this.renderFlexiRegions(this.customTabFlexi, 'tab')
              : html`<div class="empty">Loading tab…</div>`}
      </div>
    `;
  }

  private renderConflicts() {
    return html`
      <div class="page">
        <h2>Conflicts</h2>
        ${this.conflicts.length === 0
          ? html`<div class="empty">No open conflicts</div>`
          : this.conflicts.map(
              (c) => html`
                <section class="comp-card" style="margin-bottom:10px">
                  <header>${c.objectApi} · ${c.recordId}</header>
                  <div class="body-pad actions">
                    <button
                      @click=${async () => {
                        if (!this.db) return;
                        await applyConflictResolution(this.db, c.id, 'server-wins');
                        this.conflicts = await getConflicts(this.db);
                      }}
                    >
                      Server wins
                    </button>
                    <button
                      @click=${async () => {
                        if (!this.db) return;
                        await applyConflictResolution(this.db, c.id, 'client-wins');
                        this.conflicts = await getConflicts(this.db);
                      }}
                    >
                      Client wins
                    </button>
                  </div>
                </section>
              `
            )}
      </div>
    `;
  }

  private async exportSupportLogsZip() {
    if (!this.db || this.exportingSupport) return;
    this.exportingSupport = true;
    this.status = 'Preparing support ZIP…';
    try {
      const result = await exportSupportBundle(this.db, {
        appVersion: '0.1.0-beta.19',
        syncMode: this.syncMode,
        currentApp: this.currentApp,
        online: this.online
      });
      this.status =
        result.savedTo === 'download'
          ? `Support ZIP downloaded · ${result.fileName}`
          : `Support ZIP ready · send to CloudAstick · ${result.fileName}`;
    } catch (e) {
      this.status = `Support export failed: ${e instanceof Error ? e.message : String(e)}`;
    } finally {
      this.exportingSupport = false;
    }
  }

  private renderSupportLogs() {
    return html`
      <div class="page">
        <div class="list-toolbar">
          <h2>Support logs</h2>
          <button
            class="ghost"
            ?disabled=${this.exportingSupport || !this.db}
            @click=${() => void this.exportSupportLogsZip()}
          >
            ${this.exportingSupport ? 'Exporting…' : 'Export ZIP'}
          </button>
        </div>
        <p style="margin:0 0 12px;color:var(--sf-muted);font-size:13px;line-height:1.4">
          Sync issues are stored locally. Export a ZIP and send it to the CloudAstick team for
          support.
        </p>
        <div class="actions" style="margin-bottom:12px;display:flex;gap:8px;flex-wrap:wrap">
          <button @click=${() => void this.refreshSupportLogs()}>Refresh</button>
          <button
            class="ghost"
            ?disabled=${!this.db || this.supportLogCount === 0}
            @click=${async () => {
              if (!this.db) return;
              await clearLogs(this.db, 'sync');
              await this.refreshSupportLogs();
              this.status = 'Support logs cleared';
            }}
          >
            Clear logs
          </button>
        </div>
        ${this.supportLogs.length === 0
          ? html`<div class="empty">No sync issues logged yet</div>`
          : this.supportLogs.map((log) => {
              const when = log.createdAt.replace('T', ' ').replace(/\.\d+Z$/, 'Z');
              const tags = (log.tags ?? []).join(' · ');
              return html`
                <section class="comp-card" style="margin-bottom:10px">
                  <header>${log.source ?? log.category} · ${when}</header>
                  <div class="body-pad">
                    <div style="font-size:13px;word-break:break-word">${log.message}</div>
                    ${tags
                      ? html`<small style="color:var(--sf-muted)">${tags}</small>`
                      : nothing}
                  </div>
                </section>
              `;
            })}
      </div>
    `;
  }
}

declare global {
  interface HTMLElementTagNameMap {
    'osr-app': OsrApp;
  }
}
