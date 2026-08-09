/**
 * Fidelity / Vite catalog registry — which LWC bundles get offline Vite/Lit ports.
 * Renderers are registered by the shell (avoids ui-runtime → shell cycle).
 */

export type FidelityMode = 'hydrate' | 'lit' | 'vite' | 'ce' | 'iframe-engine';

export interface FidelityEntry {
  bundle: string;
  cacheKeys: string[];
  mode: FidelityMode;
  /** Mount shared Leaflet map slot when overlay requests it. */
  map?: boolean;
  label?: string;
}

/** Apex method import → apex_payload_cache key */
export const APEX_BINDING_TO_CACHE_KEY: Record<string, string> = {
  'FieldRepHomeController.getTodayPlan': 'todayPlan',
  'FieldPlannerController.fetchPlannerData': 'plannerWeek',
  'FieldPlannerController.getPlannerData': 'plannerWeek',
  'FieldPlannerController.searchAccountsPage': 'plannerAccounts',
  'FieldPlannerController.getPlannerViewerContext': 'plannerViewer',
  'FieldRepHomeController.getHomeMetrics': 'homeMetrics',
  'FieldRepHomeController.getAccountCoverageRows': 'accountCoverage',
  'FieldRepHomeController.getPerformanceGamification': 'gamification',
  'FieldRepHomeController.getPerformanceRankings': 'rankings',
  'FieldRepHomeController.getNextBestCustomers': 'nextBestCustomers',
  'HomeOfficeMessageController.getActiveMessages': 'officeMessages',
  'ClmMetricsController.getRepPresentationManifest': 'clmManifest',
  'ClmMetricsController.getDeployedRatingLayoutJson': 'clmManifest',
  'MyLearningController.getMyCourses': 'myLearning'
};

/** Pharma Field Vite catalog — offline-first Lit ports. */
const ENTRIES: FidelityEntry[] = [
  {
    bundle: 'c/fieldRepHomeTodayPlan',
    cacheKeys: ['todayPlan', 'plannerViewer'],
    mode: 'vite',
    map: true,
    label: "Today's Plan"
  },
  {
    bundle: 'c/fieldRepHomeMetrics',
    cacheKeys: ['homeMetrics', 'gamification', 'rankings', 'accountCoverage'],
    mode: 'vite',
    label: 'Metrics'
  },
  {
    bundle: 'c/fieldRepHomeNextBestCustomer',
    cacheKeys: ['nextBestCustomers'],
    mode: 'vite',
    label: 'Next Best Customer'
  },
  {
    bundle: 'c/homeOfficeMessages',
    cacheKeys: ['officeMessages'],
    mode: 'vite',
    label: 'Office Messages'
  },
  {
    bundle: 'c/fieldRepHomeClmPrefetch',
    cacheKeys: ['clmManifest'],
    mode: 'vite',
    label: 'CLM Content'
  },
  {
    bundle: 'c/repLocationPublisher',
    cacheKeys: [],
    mode: 'vite',
    label: 'My Location'
  },
  {
    bundle: 'c/reportsHub',
    cacheKeys: [],
    mode: 'vite',
    label: 'Reports'
  },
  {
    bundle: 'c/fieldRepPlanner',
    cacheKeys: ['plannerWeek', 'plannerAccounts', 'plannerViewer'],
    mode: 'vite',
    map: true,
    label: 'Planner'
  },
  {
    bundle: 'c/visitCallShell',
    cacheKeys: ['todayPlan', 'plannerWeek', 'clmManifest'],
    mode: 'vite',
    label: 'Visit Call'
  },
  {
    bundle: 'c/visitCallShellLite',
    cacheKeys: ['todayPlan', 'plannerWeek', 'clmManifest'],
    mode: 'vite',
    label: 'Visit Call'
  },
  {
    bundle: 'c/accountsTab',
    cacheKeys: ['plannerAccounts'],
    mode: 'vite',
    label: 'Accounts'
  },
  {
    bundle: 'c/accountsTabOceList',
    cacheKeys: ['plannerAccounts'],
    mode: 'vite',
    label: 'Accounts'
  },
  {
    bundle: 'c/timeOffSubmission',
    cacheKeys: ['plannerWeek'],
    mode: 'vite',
    label: 'Request Time Off'
  },
  {
    bundle: 'c/clmPresentationsHub',
    cacheKeys: ['clmManifest'],
    mode: 'vite',
    label: 'CLM Presentations'
  },
  {
    bundle: 'c/clmPlayer',
    cacheKeys: ['clmManifest'],
    mode: 'vite',
    label: 'CLM Player'
  },
  {
    bundle: 'c/clmMessageFeedback',
    cacheKeys: ['clmManifest'],
    mode: 'vite',
    label: 'CLM Message Feedback'
  },
  {
    bundle: 'c/clmRatingsCapture',
    cacheKeys: ['clmManifest'],
    mode: 'vite',
    label: 'CLM Ratings Capture'
  },
  {
    bundle: 'c/clmVisitPresentations',
    cacheKeys: ['clmManifest'],
    mode: 'vite',
    label: 'Visit Presentations'
  },
  {
    bundle: 'c/accountAffiliationNetwork',
    cacheKeys: [],
    mode: 'vite',
    label: 'Affiliations'
  },
  {
    bundle: 'c/accountRatingsPanel',
    cacheKeys: [],
    mode: 'vite',
    label: 'Ratings'
  },
  {
    bundle: 'c/accountVisitInsightsPanel',
    cacheKeys: ['todayPlan', 'plannerWeek'],
    mode: 'vite',
    label: 'Visit Insights'
  },
  {
    bundle: 'c/clmAccountActivityHistory',
    cacheKeys: ['clmManifest'],
    mode: 'vite',
    label: 'CLM Activity'
  },
  {
    bundle: 'c/coachingEventEvaluation',
    cacheKeys: [],
    mode: 'vite',
    label: 'Coaching Evaluation'
  },
  {
    bundle: 'c/coachingEventInsights',
    cacheKeys: [],
    mode: 'vite',
    label: 'Coaching Insights'
  },
  {
    bundle: 'c/myLearning',
    cacheKeys: ['myLearning'],
    mode: 'vite',
    label: 'My Learning'
  },
  // Visit children — rendered inside visitCallShell; registered for FlexiPage/hydrate skip
  {
    bundle: 'c/visitAccountAffiliations',
    cacheKeys: [],
    mode: 'vite',
    label: 'Visit Affiliations'
  },
  {
    bundle: 'c/visitAttendeePicker',
    cacheKeys: [],
    mode: 'vite',
    label: 'Attendees'
  },
  {
    bundle: 'c/visitProductDetailPanel',
    cacheKeys: [],
    mode: 'vite',
    label: 'Products'
  },
  {
    bundle: 'c/visitSampleGrid',
    cacheKeys: [],
    mode: 'vite',
    label: 'Samples'
  },
  {
    bundle: 'c/visitNeighbouringPharmacies',
    cacheKeys: [],
    mode: 'vite',
    label: 'Neighbouring Pharmacies'
  },
  {
    bundle: 'c/visitContextInsights',
    cacheKeys: ['todayPlan', 'plannerWeek'],
    mode: 'vite',
    label: 'Context Insights'
  },
  {
    bundle: 'c/visitCoachingFormModal',
    cacheKeys: [],
    mode: 'vite',
    label: 'Coaching'
  },
  {
    bundle: 'c/visitMedicalInquiryModal',
    cacheKeys: [],
    mode: 'vite',
    label: 'Medical Inquiry'
  }
];

const byBundle = new Map(ENTRIES.map((e) => [e.bundle, e]));

/** All fidelity-managed bundle names (never prefer offlineHost for these). */
export const FIDELITY_BUNDLES = new Set(ENTRIES.map((e) => e.bundle));

/** @deprecated use FIDELITY_BUNDLES */
export const FIDELITY_LIT_BUNDLES = FIDELITY_BUNDLES;

export function getFidelityEntry(bundle: string): FidelityEntry | undefined {
  const name = normalizeBundle(bundle);
  return byBundle.get(name);
}

export function isFidelityBundle(bundle: string): boolean {
  return FIDELITY_BUNDLES.has(normalizeBundle(bundle));
}

export function listFidelityEntries(): FidelityEntry[] {
  return [...ENTRIES];
}

/** Register or override an entry (future LWCs). */
export function registerFidelityEntry(entry: FidelityEntry): void {
  const name = normalizeBundle(entry.bundle);
  const next = { ...entry, bundle: name };
  byBundle.set(name, next);
  FIDELITY_BUNDLES.add(name);
  const idx = ENTRIES.findIndex((e) => e.bundle === name);
  if (idx >= 0) ENTRIES[idx] = next;
  else ENTRIES.push(next);
}

export function cacheKeysForBindings(bindings: string[] | undefined): string[] {
  if (!bindings?.length) return [];
  const keys = new Set<string>();
  for (const b of bindings) {
    const raw = b.replace(/^.*\//, '').replace(/\.js$/, '');
    const short = raw.includes('.') ? raw : b;
    const mapped = APEX_BINDING_TO_CACHE_KEY[short] ?? APEX_BINDING_TO_CACHE_KEY[b];
    if (mapped) keys.add(mapped);
  }
  return [...keys];
}

function normalizeBundle(bundle: string): string {
  const s = bundle.trim();
  if (s.startsWith('c/')) return s;
  if (s.startsWith('c:')) return `c/${s.slice(2)}`;
  if (s.includes('/')) return s;
  return `c/${s}`;
}
