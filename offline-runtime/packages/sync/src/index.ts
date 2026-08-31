import {
  type SqlExecutor,
  upsertObjectDescribe,
  upsertLayout,
  upsertFlexiPage,
  upsertTab,
  upsertApp,
  upsertValidationRule,
  upsertListView,
  upsertAction,
  upsertCompactLayout,
  upsertUserPrefs,
  upsertRecord,
  softDeleteRecord,
  restoreSoftDeletedRecord,
  upsertFile,
  upsertLwcBundle,
  getSyncCursor,
  setSyncCursor,
  listPendingOutbox,
  listOutboxForPush,
  markOutbox,
  remapRecordId,
  addConflict,
  replaceSharingIdSet,
  kvGet,
  kvSet,
  enqueueOutbox,
  upsertApexPayload,
  upsertStaticResource,
  appendLog,
  nowIso,
  listApps,
  getLayoutsForObject,
  listListViewsForObject,
  getCompactLayoutForObject
} from '@osr/db';

const SYNC_FIELD_BASE = ['Id', 'Name', 'Subject', 'SystemModstamp'] as const;
const MAX_SYNC_FIELDS = 120;

function fieldsFromLayoutJson(layout: unknown, out: Set<string>): void {
  if (!layout || typeof layout !== 'object') return;
  const o = layout as Record<string, unknown>;
  for (const f of (o.highlightsFields as string[] | undefined) ?? []) {
    if (f) out.add(f);
  }
  if (typeof o.pathField === 'string' && o.pathField) out.add(o.pathField);
  for (const s of (o.sections as { columns?: unknown[][] }[] | undefined) ?? []) {
    for (const col of s.columns ?? []) {
      for (const cell of col ?? []) {
        const field =
          typeof cell === 'string'
            ? cell
            : typeof cell === 'object' && cell && 'field' in cell
              ? String((cell as { field?: string }).field ?? '')
              : '';
        if (field) out.add(field);
      }
    }
  }
  for (const rl of (o.relatedLists as { lookupField?: string; fields?: string[] }[] | undefined) ??
    []) {
    if (rl.lookupField) out.add(rl.lookupField);
    for (const f of rl.fields ?? []) {
      if (f) out.add(f);
    }
  }
}

/** Derive SOQL field list from synced layouts, list views, and compact layout. */
export async function collectSyncFieldsFromLocalMetadata(
  db: SqlExecutor,
  objectApi: string
): Promise<string[]> {
  const fields = new Set<string>(SYNC_FIELD_BASE);
  for (const layout of await getLayoutsForObject(db, objectApi)) {
    fieldsFromLayoutJson(layout, fields);
  }
  for (const lv of await listListViewsForObject(db, objectApi)) {
    const cols = lv.listview.columns;
    if (!Array.isArray(cols)) continue;
    for (const c of cols) {
      const f = typeof c === 'string' ? c : c?.fieldOrColumn;
      if (f) fields.add(f);
    }
  }
  const compact = await getCompactLayoutForObject(db, objectApi);
  for (const f of compact?.compact?.fields ?? []) {
    if (f) fields.add(f);
  }
  return [...fields].slice(0, MAX_SYNC_FIELDS);
}

function mergeObjectSyncFields(existing: string[] | undefined, discovered: string[]): string[] {
  const merged = new Set<string>(['Id', 'SystemModstamp']);
  for (const f of existing ?? []) {
    if (f) merged.add(f);
  }
  for (const f of discovered) {
    if (f) merged.add(f);
  }
  return [...merged].slice(0, MAX_SYNC_FIELDS);
}

export interface OAuthConfig {
  loginUrl: string;
  clientId: string;
  redirectUri: string;
  apiVersion?: string;
}

export interface TokenSet {
  accessToken: string;
  refreshToken?: string;
  instanceUrl: string;
  issuedAt: string;
  expiresAt?: string;
}

export interface SyncProfile {
  name: string;
  objects: {
    apiName: string;
    soqlFilter?: string;
    fields?: string[];
  }[];
  flexiPages?: string[];
  tabs?: string[];
  apps?: string[];
  lwcBundles?: string[];
  fileScopes?: { linkedEntityObject?: string; maxBytes?: number }[];
}

export interface SyncHttpClient {
  get<T = unknown>(path: string): Promise<T>;
  post<T = unknown>(path: string, body: unknown): Promise<T>;
}

const TOKEN_KEY = 'osr.oauth.tokens';

export function buildAuthorizeUrl(cfg: OAuthConfig, codeChallenge: string, state: string): string {
  const u = new URL(`${cfg.loginUrl.replace(/\/$/, '')}/services/oauth2/authorize`);
  u.searchParams.set('response_type', 'code');
  u.searchParams.set('client_id', cfg.clientId);
  u.searchParams.set('redirect_uri', cfg.redirectUri);
  u.searchParams.set('code_challenge', codeChallenge);
  u.searchParams.set('code_challenge_method', 'S256');
  u.searchParams.set('state', state);
  u.searchParams.set('prompt', 'login');
  return u.toString();
}

export async function createPkce(): Promise<{ verifier: string; challenge: string }> {
  const verifier = base64Url(crypto.getRandomValues(new Uint8Array(32)));
  const digest = await crypto.subtle.digest('SHA-256', new TextEncoder().encode(verifier));
  const challenge = base64Url(new Uint8Array(digest));
  return { verifier, challenge };
}

function base64Url(bytes: Uint8Array): string {
  let s = '';
  bytes.forEach((b) => {
    s += String.fromCharCode(b);
  });
  return btoa(s).replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, '');
}

export async function exchangeCode(
  cfg: OAuthConfig,
  code: string,
  verifier: string
): Promise<TokenSet> {
  const body = new URLSearchParams({
    grant_type: 'authorization_code',
    client_id: cfg.clientId,
    redirect_uri: cfg.redirectUri,
    code,
    code_verifier: verifier
  });
  const res = await fetch(`${cfg.loginUrl.replace(/\/$/, '')}/services/oauth2/token`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
    body
  });
  if (!res.ok) throw new Error(`Token exchange failed: ${res.status} ${await res.text()}`);
  const json = (await res.json()) as Record<string, string>;
  return {
    accessToken: json.access_token,
    refreshToken: json.refresh_token,
    instanceUrl: json.instance_url,
    issuedAt: nowIso()
  };
}

export async function saveTokens(db: SqlExecutor, tokens: TokenSet): Promise<void> {
  await kvSet(db, TOKEN_KEY, JSON.stringify(tokens));
}

export async function loadTokens(db: SqlExecutor): Promise<TokenSet | null> {
  const raw = await kvGet(db, TOKEN_KEY);
  if (!raw || raw === 'null') return null;
  try {
    return JSON.parse(raw) as TokenSet;
  } catch {
    return null;
  }
}

export function createSfClient(tokens: TokenSet, apiVersion = '61.0'): SyncHttpClient {
  const base = tokens.instanceUrl.replace(/\/$/, '');
  async function request<T>(method: string, path: string, body?: unknown): Promise<T> {
    const url = path.startsWith('http') ? path : `${base}${path}`;
    const ctrl = new AbortController();
    const timer = setTimeout(() => ctrl.abort(), 45_000);
    let res: Response;
    try {
      res = await sfFetch(url, {
        method,
        accessToken: tokens.accessToken,
        body,
        signal: ctrl.signal
      });
    } catch (e) {
      if (e instanceof Error && e.name === 'AbortError') {
        throw new Error(`SF ${method} ${path} → timeout after 45s`);
      }
      throw e;
    } finally {
      clearTimeout(timer);
    }
    if (!res.ok) {
      throw new Error(`SF ${method} ${path} → ${res.status}: ${await res.text()}`);
    }
    if (res.status === 204) return undefined as T;
    const text = await res.text();
    if (!text) return undefined as T;
    return JSON.parse(text) as T;
  }
  return {
    get: (path) => request('GET', path),
    post: (path, body) => request('POST', path, body)
  };
}

/** True when running in a browser tab (not Capacitor native). */
export function isBrowserWebClient(): boolean {
  if (typeof window === 'undefined') return false;
  try {
    const Cap = (window as unknown as { Capacitor?: { isNativePlatform?: () => boolean } }).Capacitor;
    if (Cap?.isNativePlatform?.()) return false;
  } catch {
    /* ignore */
  }
  return true;
}

/**
 * Salesforce fetch that uses Netlify `sf-api` proxy on web (CORS),
 * and direct fetch elsewhere (native CapacitorHttp patches fetch).
 */
export async function sfFetch(
  url: string,
  opts: {
    method?: string;
    accessToken: string;
    body?: unknown;
    headers?: Record<string, string>;
    signal?: AbortSignal;
  }
): Promise<Response> {
  const method = (opts.method || 'GET').toUpperCase();
  if (isBrowserWebClient()) {
    const proxyRes = await fetch('/.netlify/functions/sf-api', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json', Accept: 'application/json' },
      body: JSON.stringify({
        url,
        method,
        authorization: `Bearer ${opts.accessToken}`,
        body: opts.body ?? null,
        headers: opts.headers
      }),
      signal: opts.signal
    });
    // Proxy returns upstream status/body; treat as the Salesforce response.
    return proxyRes;
  }

  return fetch(url, {
    method,
    headers: {
      Authorization: `Bearer ${opts.accessToken}`,
      Accept: opts.headers?.Accept ?? 'application/json',
      ...(opts.body != null && method !== 'GET' && method !== 'DELETE'
        ? { 'Content-Type': 'application/json' }
        : {}),
      ...opts.headers
    },
    body:
      opts.body != null && method !== 'GET' && method !== 'DELETE'
        ? typeof opts.body === 'string'
          ? opts.body
          : JSON.stringify(opts.body)
        : undefined,
    signal: opts.signal
  });
}

/** Fetch binary Salesforce content (CLM slide PNGs, PDFs) through the same proxy as sfFetch. */
export async function sfFetchArrayBuffer(
  url: string,
  accessToken: string,
  signal?: AbortSignal
): Promise<{ buffer: ArrayBuffer; contentType: string }> {
  const res = await sfFetch(url, {
    accessToken,
    signal,
    headers: { Accept: '*/*' }
  });
  if (!res.ok) {
    throw new Error(`SF GET ${url} → ${res.status}`);
  }
  return {
    buffer: await res.arrayBuffer(),
    contentType: res.headers.get('content-type') || 'application/octet-stream'
  };
}

/** Sync Pack REST paths */
export const OSR_API = {
  hello: '/services/apexrest/osr/v1/hello',
  profile: '/services/apexrest/osr/v1/profile',
  metadata: '/services/apexrest/osr/v1/metadata',
  data: '/services/apexrest/osr/v1/data',
  files: '/services/apexrest/osr/v1/files',
  staticResources: '/services/apexrest/osr/v1/static-resources',
  lwc: '/services/apexrest/osr/v1/lwc',
  apexCache: '/services/apexrest/osr/v1/apex-cache',
  outbox: '/services/apexrest/osr/v1/outbox',
  sharing: '/services/apexrest/osr/v1/sharing',
  prefs: '/services/apexrest/osr/v1/prefs'
} as const;

export interface PullResult {
  channels: Record<string, { ok: boolean; count: number; error?: string }>;
}

/** Drift / integrity check between local SQLite and Salesforce. */
export type SyncValidationIssue = {
  objectApi: string;
  kind: 'missing_local' | 'missing_server' | 'modstamp_drift' | 'stale_outbox' | 'count_gap' | 'error';
  recordId?: string;
  detail: string;
};

export type SyncValidationReport = {
  checkedObjects: string[];
  repaired: number;
  issues: SyncValidationIssue[];
  ok: boolean;
};

/** Progress event emitted during fullSync / pullAll / pullData. */
export interface SyncProgress {
  phase: 'push' | 'metadata' | 'sharing' | 'data' | 'files' | 'staticResources' | 'lwc' | 'apexCache' | 'prefs';
  /** Short UI label, e.g. Metadata, Accounts, Files, LWCs — may include (3/8). */
  channel: string;
  objectApi?: string;
  /** Overall step (1-based) for the progress bar. */
  current: number;
  /** Total steps (channels + objects); 0 = indeterminate. */
  total: number;
}

export interface SyncHooks {
  afterMetadata?: () => Promise<void> | void;
  onProgress?: (progress: SyncProgress) => void;
  /** planDate / week range sent to apex-cache before record pulls */
  apexCache?: {
    weekStart?: string;
    weekEnd?: string;
    planDate?: string;
    contextUserId?: string;
  };
}

/** Human label for an sObject API name (Account → Accounts, Visit__c → Visits). */
export function syncChannelLabel(apiName: string): string {
  const base = apiName.replace(/__c$/i, '').replace(/_/g, ' ').trim();
  if (!base) return apiName;
  if (/ies$/i.test(base) || /ses$/i.test(base) || /s$/i.test(base)) return base;
  if (/y$/i.test(base)) return `${base.slice(0, -1)}ies`;
  return `${base}s`;
}

/** Local calendar date as yyyy-MM-dd. */
export function isoDateLocal(d: Date = new Date()): string {
  const y = d.getFullYear();
  const m = String(d.getMonth() + 1).padStart(2, '0');
  const day = String(d.getDate()).padStart(2, '0');
  return `${y}-${m}-${day}`;
}

/** Sunday–Saturday week containing `d` (matches Field Rep Planner). */
export function sundayWeekRange(d: Date = new Date()): { weekStart: string; weekEnd: string } {
  const start = new Date(d.getFullYear(), d.getMonth(), d.getDate());
  start.setDate(start.getDate() - start.getDay());
  const end = new Date(start);
  end.setDate(start.getDate() + 6);
  return { weekStart: isoDateLocal(start), weekEnd: isoDateLocal(end) };
}

export type OutboxPushFailure = {
  clientId: string;
  op: string;
  objectApi?: string;
  recordId?: string;
  error: string;
  status: 'failed' | 'conflict';
};

export type PushOutboxResult = {
  synced: number;
  failed: number;
  conflicts: number;
  failures: OutboxPushFailure[];
};

export class SyncEngine {
  constructor(
    private db: SqlExecutor,
    private client: SyncHttpClient,
    private options: {
      conflictPolicy?: 'server-wins' | 'client-wins' | 'manual';
      maxOutboxBatch?: number;
      backoffBaseMs?: number;
    } = {}
  ) {}

  async hello(): Promise<{ ok: boolean; orgId?: string; userId?: string; message?: string }> {
    return this.client.get(OSR_API.hello);
  }

  async fetchProfile(): Promise<SyncProfile> {
    return this.client.get(OSR_API.profile);
  }

  async pullAll(profile?: SyncProfile, hooks?: SyncHooks): Promise<PullResult> {
    let p = profile ?? (await this.fetchProfile());
    const result: PullResult = { channels: {} };
    const report = (progress: SyncProgress) => {
      try {
        hooks?.onProgress?.(progress);
      } catch {
        /* UI progress must not fail sync */
      }
    };

    // Indeterminate until object count is known after metadata
    report({ phase: 'metadata', channel: 'Metadata', current: 1, total: 0 });
    result.channels.metadata = await this.safe('metadata', () => this.pullMetadata(p));
    // Expand profile from synced tabs/describes so data + LWC cover discovered app objects
    const beforeObjects = p.objects.length;
    p = await this.enrichProfileFromLocalMetadata(p);
    if (p.objects.length > beforeObjects) {
      // Second metadata pass for newly discovered tab sObjects (esp. REST fallback)
      report({ phase: 'metadata', channel: 'Apps', current: 1, total: 0 });
      const again = await this.safe('metadata', () => this.pullMetadata(p));
      result.channels.metadata = {
        ok: result.channels.metadata.ok && again.ok,
        count: (result.channels.metadata.count ?? 0) + again.count,
        error: again.error ?? result.channels.metadata.error
      };
      p = await this.enrichProfileFromLocalMetadata(p);
    }
    // Let UI show App Launcher as soon as metadata lands — don't wait for data
    try {
      await hooks?.afterMetadata?.();
    } catch {
      /* UI hook must not fail sync */
    }

    report({ phase: 'sharing', channel: 'Sharing', current: 2, total: 0 });
    result.channels.sharing = await this.safe('sharing', () => this.pullSharing(p));
    // Only pull objects we actually have describes for (skip Home/Chatter stubs)
    p = await this.filterQueryableObjects(p);
    const objectCount = p.objects.length;
    // Steps: metadata + sharing + apex-cache + each object + files + staticResources + lwc + prefs
    const total = 3 + objectCount + 4;

    report({
      phase: 'apexCache',
      channel: 'Caching planner…',
      current: 3,
      total
    });
    result.channels.apexCache = await this.safe('apexCache', () =>
      this.pullApexCache(hooks?.apexCache)
    );

    const dataResult = await this.pullDataResilient(p, {
      onObject: (obj, index, ofTotal) => {
        const step = 3 + index;
        const label = syncChannelLabel(obj.apiName);
        report({
          phase: 'data',
          channel: `${label} (${index}/${ofTotal})`,
          objectApi: obj.apiName,
          current: step,
          total
        });
      }
    });
    result.channels.data = {
      ok: dataResult.errors.length === 0,
      count: dataResult.count,
      error: dataResult.errors.length
        ? dataResult.errors.slice(0, 5).join('; ')
        : undefined
    };
    for (const err of dataResult.errors) {
      const api = err.split(':')[0]?.trim() || 'object';
      result.channels[`data:${api}`] = { ok: false, count: 0, error: err };
    }

    report({
      phase: 'files',
      channel: 'Files',
      current: 3 + objectCount + 1,
      total
    });
    result.channels.files = await this.safe('files', () => this.pullFiles(p));

    report({
      phase: 'staticResources',
      channel: 'Map libraries',
      current: 3 + objectCount + 2,
      total
    });
    result.channels.staticResources = await this.safe('staticResources', () =>
      this.pullStaticResources()
    );

    report({
      phase: 'lwc',
      channel: 'LWCs',
      current: 3 + objectCount + 3,
      total
    });
    result.channels.lwc = await this.safe('lwc', () => this.pullLwc(p));

    report({
      phase: 'prefs',
      channel: 'Preferences',
      current: 3 + objectCount + 4,
      total
    });
    result.channels.prefs = await this.safe('prefs', () => this.pullPrefs());
    return result;
  }

  /** Keep only objects present in local meta_objects (described/queryable). */
  private async filterQueryableObjects(profile: SyncProfile): Promise<SyncProfile> {
    const { rows } = await this.db.execute(`SELECT api_name FROM meta_objects`);
    const known = new Set(rows.map((r) => String(r.api_name)));
    const stub =
      /^(Home|Chatter|File|Files|Dashboard|Report|Wave|WaveHome|Analytics|Today|Content|Feed|People|Profile|CollaborationGroup|Forecasting3|Forecasting)$/i;
    const objects = profile.objects.filter((o) => {
      if (!o?.apiName || stub.test(o.apiName) || o.apiName.startsWith('tab_')) return false;
      // If we have any describes, require membership; otherwise keep profile shortlist
      if (known.size > 0) return known.has(o.apiName);
      return true;
    });
    return { ...profile, objects };
  }

  /** Merge objects / LWC bundles discovered during metadata into the working profile. */
  private async enrichProfileFromLocalMetadata(profile: SyncProfile): Promise<SyncProfile> {
    const { rows: tabRows } = await this.db.execute(
      `SELECT developer_name, tab_json FROM meta_tabs ORDER BY sort_order ASC`
    );
    const { rows: objRows } = await this.db.execute(`SELECT api_name FROM meta_objects`);
    const { rows: flexiRows } = await this.db.execute(
      `SELECT developer_name, page_json FROM meta_flexipages`
    );

    const have = new Set(profile.objects.map((o) => o.apiName));
    const objects = [...profile.objects];
    const tabs = new Set(profile.tabs ?? []);
    const lwcBundles = new Set(profile.lwcBundles ?? []);
    const normalizeBundle = (raw: string) => {
      const s = raw.trim();
      if (!s) return null;
      if (s.startsWith('c/')) return s;
      if (s.startsWith('c:')) return `c/${s.slice(2)}`;
      const colon = s.indexOf(':');
      if (colon > 0) return `${s.slice(0, colon)}/${s.slice(colon + 1)}`;
      if (s.includes('/')) return s;
      return `c/${s}`;
    };

    const addObject = (apiName: string) => {
      const name = apiName.replace(/^standard-/, '');
      if (!name || have.has(name) || name.startsWith('tab_')) return;
      // Skip non-sObject navigation stubs (Home/Chatter/etc. are not queryable APIs)
      if (
        /^(Home|Chatter|File|Files|Dashboard|Report|Wave|WaveHome|Analytics|Today|Content|Feed|People|Profile|CollaborationGroup)$/i.test(
          name
        )
      ) {
        return;
      }
      have.add(name);
      // Omit speculative fields — Apex sanitizes / defaults per describe
      objects.push({
        apiName: name,
        fields: ['Id', 'SystemModstamp']
      });
      tabs.add(name);
    };

    for (const r of objRows) {
      addObject(String(r.api_name));
    }
    for (const r of tabRows) {
      try {
        const tab = JSON.parse(String(r.tab_json ?? '{}')) as {
          objectApi?: string;
          tabType?: string;
          type?: string;
          lwcBundle?: string;
          lwcComponent?: string;
          pageDeveloperName?: string;
          flexiPage?: string;
        };
        const tabType = tab.tabType ?? tab.type;
        if (tab.objectApi && (tabType === 'object' || !tabType)) {
          addObject(tab.objectApi);
        } else if (tabType === 'object' || (!tabType && !tab.pageDeveloperName && !tab.lwcBundle)) {
          // Legacy: developer name may be the sObject API
          const dn = String(r.developer_name ?? '');
          if (dn && !dn.startsWith('tab_') && (dn.endsWith('__c') || !dn.includes('_'))) {
            addObject(dn);
          }
        }
        const lwcRef = tab.lwcBundle ?? tab.lwcComponent;
        if (lwcRef) {
          const b = normalizeBundle(lwcRef);
          if (b) lwcBundles.add(b);
        }
      } catch {
        /* ignore */
      }
    }

    // Merge server-discovered LWC list from last metadata pull
    try {
      const discoveredRaw = await kvGet(this.db, 'osr.discovered_lwc');
      if (discoveredRaw) {
        const discovered = JSON.parse(discoveredRaw) as string[];
        for (const raw of discovered) {
          const b = normalizeBundle(raw);
          if (b) lwcBundles.add(b);
        }
      }
    } catch {
      /* ignore */
    }
    for (const r of flexiRows) {
      try {
        const page = JSON.parse(String(r.page_json ?? '{}')) as {
          regions?: { components?: { type?: string; attributes?: Record<string, unknown> }[] }[];
        };
        for (const region of page.regions ?? []) {
          for (const c of region.components ?? []) {
            const type = c.type ?? '';
            if (
              type.startsWith('c/') ||
              type.startsWith('c:') ||
              /^[a-zA-Z]\w*:/.test(type) ||
              (type.includes('/') && !type.startsWith('force:') && !type.startsWith('flexipage:') && !type.startsWith('osr:'))
            ) {
              const b = normalizeBundle(type);
              if (b) lwcBundles.add(b);
            }
            const fqn = c.attributes?.fqn;
            if (typeof fqn === 'string' && fqn) {
              const b = normalizeBundle(fqn);
              if (b) lwcBundles.add(b);
            }
          }
        }
      } catch {
        /* ignore */
      }
      if (String(r.developer_name).toLowerCase().includes('home')) {
        for (const b of [
          'c/fieldRepHomeTodayPlan',
          'c/fieldRepHomeMetrics',
          'c/fieldRepHomeNextBestCustomer',
          'c/fieldRepHomeClmPrefetch',
          'c/homeOfficeMessages',
          'c/repLocationPublisher',
          'c/reportsHub'
        ]) {
          lwcBundles.add(b);
        }
      }
    }

    for (const o of objects) {
      if (o.apiName !== 'Visit__c') continue;
      if (
        !o.soqlFilter ||
        /LAST_N_DAYS:30\b/.test(o.soqlFilter) ||
        /Planned_Date__c/.test(o.soqlFilter)
      ) {
        // Pharma uses Visit_Date__c (not Planned_Date__c). Apex drops unknown __c fields.
        o.soqlFilter =
          'Visit_Date__c = LAST_N_DAYS:60 OR Visit_Date__c = NEXT_N_DAYS:30 OR Visit_Date__c = TODAY';
      }
      if (o.fields?.includes('Planned_Date__c') && !o.fields.includes('Visit_Date__c')) {
        o.fields = [
          ...o.fields.filter((f) => f !== 'Planned_Date__c'),
          'Visit_Date__c',
          'Start_Date__c',
          'Status__c',
          'Account__c'
        ];
      }
    }

    // Tab-discovered objects (e.g. Coaching_Event__c) were Id-only — merge layout/list fields.
    for (const o of objects) {
      const discovered = await collectSyncFieldsFromLocalMetadata(this.db, o.apiName);
      o.fields = mergeObjectSyncFields(o.fields, discovered);
    }

    return {
      ...profile,
      objects,
      tabs: Array.from(tabs),
      lwcBundles: Array.from(lwcBundles)
    };
  }

  private async safe(
    name: string,
    fn: () => Promise<number>
  ): Promise<{ ok: boolean; count: number; error?: string }> {
    try {
      const count = await fn();
      return { ok: true, count };
    } catch (e) {
      const error = e instanceof Error ? e.message : String(e);
      try {
        await appendLog(this.db, {
          category: 'sync',
          source: name,
          message: error,
          detail: {
            channel: name,
            stack: e instanceof Error ? e.stack?.slice(0, 2000) : undefined
          },
          tags: ['pull']
        });
      } catch {
        /* logging must not break sync */
      }
      return { ok: false, count: 0, error };
    }
  }

  async pullMetadata(profile: SyncProfile): Promise<number> {
    const cursor = await getSyncCursor(this.db, 'metadata');
    const payload = await this.client.post<{
      objects?: { apiName: string; label: string; keyPrefix?: string; describe: unknown }[];
      layouts?: {
        id: string;
        objectApi: string;
        recordTypeId?: string;
        name: string;
        layout: unknown;
      }[];
      flexiPages?: { id: string; developerName: string; type?: string; page: unknown }[];
      tabs?: {
        id: string;
        developerName: string;
        label: string;
        sortOrder?: number;
        tab: unknown;
      }[];
      apps?: { id: string; developerName: string; label: string; app: unknown }[];
      validationRules?: {
        id: string;
        objectApi: string;
        name: string;
        active: boolean;
        errorCondition: string;
        errorMessage: string;
        errorDisplayField?: string;
        rule: unknown;
      }[];
      listViews?: {
        id: string;
        objectApi: string;
        developerName: string;
        label: string;
        listview: unknown;
      }[];
      actions?: {
        id: string;
        objectApi: string;
        name: string;
        label: string;
        action: unknown;
      }[];
      compactLayouts?: {
        id: string;
        objectApi: string;
        name: string;
        compact: unknown;
      }[];
      /** Auto-discovered from FlexiPage regions during metadata sync */
      lwcBundles?: string[];
      cursor?: string;
      warning?: string;
    }>(OSR_API.metadata, {
      cursor: cursor.cursor,
      objects: profile.objects.map((o) => o.apiName),
      flexiPages: profile.flexiPages ?? [],
      tabs: profile.tabs ?? [],
      apps: profile.apps ?? []
    });

    let n = 0;
    for (const o of payload.objects ?? []) {
      await upsertObjectDescribe(this.db, o.apiName, o.label, o.describe, o.keyPrefix);
      n++;
    }
    for (const l of payload.layouts ?? []) {
      await upsertLayout(this.db, l);
      n++;
    }
    for (const p of payload.flexiPages ?? []) {
      await upsertFlexiPage(this.db, p);
      n++;
    }
    for (const t of payload.tabs ?? []) {
      await upsertTab(this.db, t);
      n++;
    }
    for (const a of payload.apps ?? []) {
      await upsertApp(this.db, a);
      n++;
    }
    for (const v of payload.validationRules ?? []) {
      await upsertValidationRule(this.db, v);
      n++;
    }
    for (const lv of payload.listViews ?? []) {
      await upsertListView(this.db, lv);
      n++;
    }
    for (const act of payload.actions ?? []) {
      await upsertAction(this.db, act);
      n++;
    }
    for (const cl of payload.compactLayouts ?? []) {
      await upsertCompactLayout(this.db, cl);
      n++;
    }
    // Persist server-discovered LWC pull list for enrichProfileFromLocalMetadata
    if (payload.lwcBundles?.length) {
      await kvSet(this.db, 'osr.discovered_lwc', JSON.stringify(payload.lwcBundles));
    }
    await setSyncCursor(this.db, 'metadata', payload.cursor ?? nowIso(), {
      profile: profile.name
    });
    n += await this.pullUserNavPreferences();
    return n;
  }

  /** UI API: user's personalized nav bar order per Lightning app. */
  async pullUserNavPreferences(apiVersion = '61.0'): Promise<number> {
    const apps = await listApps(this.db);
    let n = 0;
    for (const app of apps) {
      const id = app.id?.trim() ?? '';
      if (!/^[a-zA-Z0-9]{15,18}$/.test(id)) continue;
      try {
        const res = await this.client.get<{ navItems?: Record<string, unknown>[] }>(
          `/services/data/v${apiVersion}/ui-api/apps/${id}/user-nav-items?formFactor=Large`
        );
        const raw = res.navItems ?? [];
        if (!raw.length) continue;
        const userNavItems: {
          developerName: string;
          label?: string;
          iconUrl?: string | null;
          objectApiName?: string | null;
          itemType?: string | null;
          pageReference?: Record<string, unknown> | null;
        }[] = [];
        for (const item of raw) {
          const developerName = String(item.developerName ?? '').trim();
          if (!developerName) continue;
          userNavItems.push({
            developerName,
            label: item.label != null ? String(item.label) : undefined,
            iconUrl: item.iconUrl != null ? String(item.iconUrl) : null,
            objectApiName: item.objectApiName != null ? String(item.objectApiName) : null,
            itemType: item.itemType != null ? String(item.itemType) : null,
            pageReference:
              item.pageReference && typeof item.pageReference === 'object'
                ? (item.pageReference as Record<string, unknown>)
                : null
          });
        }
        if (!userNavItems.length) continue;
        await upsertApp(this.db, {
          id: app.id,
          developerName: app.developerName,
          label: app.label,
          app: { ...app.app, userNavItems }
        });
        n++;
      } catch {
        /* UI API unavailable for this app/user — fall back to app tab list */
      }
    }
    return n;
  }

  async pullSharing(profile: SyncProfile): Promise<number> {
    const payload = await this.client.post<{
      sets?: { objectApi: string; ids: string[] }[];
    }>(OSR_API.sharing, { profileName: profile.name, objects: profile.objects.map((o) => o.apiName) });

    let n = 0;
    for (const s of payload.sets ?? []) {
      await replaceSharingIdSet(this.db, profile.name, s.objectApi, s.ids);
      n += s.ids.length;
    }
    await setSyncCursor(this.db, 'sharing', nowIso());
    return n;
  }

  async pullData(profile: SyncProfile): Promise<number> {
    const r = await this.pullDataResilient(profile);
    if (r.errors.length && r.count === 0) {
      throw new Error(`Data pull failed: ${r.errors.slice(0, 5).join('; ')}`);
    }
    return r.count;
  }

  /** Per-object try/catch — never aborts the whole data channel on one bad sObject. */
  async pullDataResilient(
    profile: SyncProfile,
    hooks?: {
      onObject?: (
        obj: SyncProfile['objects'][number],
        index: number,
        ofTotal: number
      ) => void;
    }
  ): Promise<{ count: number; errors: string[] }> {
    let total = 0;
    const objectErrors: string[] = [];
    const ofTotal = profile.objects.length;
    let index = 0;
    for (const obj of profile.objects) {
      index++;
      try {
        hooks?.onObject?.(obj, index, ofTotal);
      } catch {
        /* progress hook must not fail sync */
      }
      const channel = `data:${obj.apiName}`;
      try {
        const cursor = await getSyncCursor(this.db, channel);
        let pageCursor = cursor.cursor;
        let hasMore = true;
        let objectTotal = 0;
        while (hasMore) {
          const page = await this.client.post<{
            records: Record<string, unknown>[];
            deletedIds?: string[];
            nextCursor?: string | null;
            done: boolean;
            error?: string | null;
            objectApi?: string;
          }>(OSR_API.data, {
            objectApi: obj.apiName,
            fields: obj.fields,
            filter: obj.soqlFilter,
            cursor: pageCursor,
            pageSize: 500
          });
          if (page.error && (!page.records || page.records.length === 0) && page.done !== false) {
            objectErrors.push(`${obj.apiName}: ${page.error}`);
            hasMore = false;
            break;
          }
          for (const r of page.records ?? []) {
            const id = String(r.Id);
            await upsertRecord(this.db, obj.apiName, id, r, String(r.SystemModstamp ?? ''));
            total++;
            objectTotal++;
          }
          for (const id of page.deletedIds ?? []) {
            await softDeleteRecord(this.db, obj.apiName, id);
          }
          if (page.error && objectTotal > 0) {
            // Soft warning (e.g. filter skipped) — keep going
          }
          pageCursor = page.nextCursor ?? null;
          hasMore = !page.done && !!page.nextCursor;
          await setSyncCursor(this.db, channel, pageCursor);
          if (objectTotal === 0 && (page.records?.length ?? 0) === 0) hasMore = false;
          if (objectTotal >= 2500) hasMore = false;
          // Hard page cap — avoid infinite cursor loops
          if (objectTotal > 0 && Math.ceil(objectTotal / 500) >= 6) hasMore = false;
        }
      } catch (e) {
        objectErrors.push(`${obj.apiName}: ${e instanceof Error ? e.message : String(e)}`);
      }
    }
    return { count: total, errors: objectErrors };
  }

  /** Fetch one record when local SQLite is missing or only has Id/stamp. */
  async fetchRecordById(
    objectApi: string,
    recordId: string,
    fields?: string[],
    apiVersion = '61.0'
  ): Promise<Record<string, unknown> | null> {
    if (!recordId || recordId.startsWith('local_')) return null;
    const fieldList = fields?.length
      ? mergeObjectSyncFields(fields, [])
      : await collectSyncFieldsFromLocalMetadata(this.db, objectApi);
    if (!fieldList.length) return null;

    try {
      const qs = fieldList.map(encodeURIComponent).join(',');
      const rec = await this.client.get<Record<string, unknown>>(
        `/services/data/v${apiVersion}/sobjects/${encodeURIComponent(objectApi)}/${encodeURIComponent(recordId)}?fields=${qs}`
      );
      if (rec?.Id) {
        await upsertRecord(
          this.db,
          objectApi,
          String(rec.Id),
          rec,
          String(rec.SystemModstamp ?? '')
        );
        return rec;
      }
    } catch {
      /* REST by Id unavailable — try Sync Pack data API */
    }

    try {
      const page = await this.client.post<{
        records?: Record<string, unknown>[];
        error?: string | null;
      }>(OSR_API.data, {
        objectApi,
        fields: fieldList,
        filter: `Id = '${recordId.replace(/'/g, "\\'")}'`,
        pageSize: 1
      });
      const rec = page.records?.[0];
      if (rec?.Id) {
        await upsertRecord(
          this.db,
          objectApi,
          String(rec.Id),
          rec,
          String(rec.SystemModstamp ?? '')
        );
        return rec;
      }
    } catch {
      /* offline or denied */
    }
    return null;
  }

  async pullFiles(profile: SyncProfile): Promise<number> {
    const cursor = await getSyncCursor(this.db, 'files');
    const payload = await this.client.post<{
      files: {
        contentVersionId: string;
        contentDocumentId?: string;
        title?: string;
        path: string;
        hash?: string;
        size?: number;
        mimeType?: string;
        downloadUrl?: string;
      }[];
      cursor?: string;
    }>(OSR_API.files, {
      cursor: cursor.cursor,
      scopes: profile.fileScopes ?? []
    });
    let n = 0;
    for (const f of payload.files) {
      // Path may be a remote URL marker; shell downloads to Filesystem
      await upsertFile(this.db, f);
      n++;
    }
    await setSyncCursor(this.db, 'files', payload.cursor ?? nowIso());
    return n;
  }

  /**
   * Pull allowlisted StaticResources (Leaflet / pdf.js / geo) for offline map & CLM hosts.
   */
  async pullStaticResources(names?: string[]): Promise<number> {
    const payload = await this.client.post<{
      ok?: boolean;
      resources?: {
        name: string;
        contentType?: string;
        bodyBase64?: string;
        size?: number;
        cacheControl?: string;
        error?: string;
      }[];
      error?: string;
    }>(OSR_API.staticResources, {
      names: names ?? ['leaflet', 'pdfjs', 'egyptGovernoratesGeoJson']
    });
    if (payload.error && !payload.resources?.length) {
      throw new Error(payload.error);
    }
    let n = 0;
    for (const r of payload.resources ?? []) {
      if (!r?.name || r.error || !r.bodyBase64) continue;
      await upsertStaticResource(this.db, {
        name: r.name,
        contentType: r.contentType,
        bodyBase64: r.bodyBase64,
        size: r.size,
        cacheControl: r.cacheControl
      });
      n++;
    }
    await setSyncCursor(this.db, 'staticResources', nowIso());
    return n;
  }

  async pullLwc(profile: SyncProfile): Promise<number> {
    const payload = await this.client.post<{
      bundles: {
        bundleName: string;
        version: string;
        moduleUrl?: string;
        sourceJs?: string;
        sourceHtml?: string;
        sourceCss?: string;
        sourceJsRaw?: string;
        sourceMetaXml?: string;
        sourceKind?: string;
        hasOrgSource?: boolean;
        apexBindings?: string[];
      }[];
    }>(OSR_API.lwc, { bundles: profile.lwcBundles ?? [] });
    let n = 0;
    for (const b of payload.bundles) {
      const name = b.bundleName?.startsWith('c:')
        ? `c/${b.bundleName.slice(2)}`
        : b.bundleName?.includes('/')
          ? b.bundleName
          : b.bundleName
            ? `c/${b.bundleName}`
            : b.bundleName;
      await upsertLwcBundle(this.db, {
        ...b,
        bundleName: name || b.bundleName
      });
      n++;
    }
    await setSyncCursor(this.db, 'lwc', nowIso());
    return n;
  }

  /**
   * Pull allowlisted Apex DTOs (Home metrics, planner week, NBC, etc.) into SQLite.
   * Optional keys / week range; defaults to full Home+Planner set for today/current week.
   */
  async pullApexCache(opts?: {
    keys?: string[];
    weekStart?: string;
    weekEnd?: string;
    planDate?: string;
    contextUserId?: string;
  }): Promise<number> {
    const today = new Date();
    const planDate = opts?.planDate ?? isoDateLocal(today);
    const { weekStart, weekEnd } = opts?.weekStart && opts?.weekEnd
      ? { weekStart: opts.weekStart, weekEnd: opts.weekEnd }
      : sundayWeekRange(today);
    const payload = await this.client.post<{
      ok?: boolean;
      entries?: { key: string; payload?: unknown; error?: string; fetchedAt?: string }[];
      error?: string;
    }>(OSR_API.apexCache, {
      keys: opts?.keys,
      weekStart,
      weekEnd,
      planDate,
      contextUserId: opts?.contextUserId
    });
    if (payload.error && !payload.entries?.length) {
      throw new Error(payload.error);
    }
    let n = 0;
    for (const e of payload.entries ?? []) {
      if (!e?.key) continue;
      // Store even when payload is null so UI can show a structured empty state
      await upsertApexPayload(this.db, e.key, e.payload ?? { __error: e.error ?? null });
      n++;
    }
    await setSyncCursor(this.db, 'apexCache', nowIso());
    return n;
  }

  /** Pull all Osr_User_Preference__c rows for the running user into local SQLite. */
  async pullPrefs(): Promise<number> {
    const payload = await this.client.get<{
      ok?: boolean;
      prefs?: {
        objectApi: string;
        favourites?: string[];
        pinnedListViewId?: string | null;
        calendarField?: string | null;
      }[];
      error?: string;
    }>(OSR_API.prefs);
    if (payload.error && !payload.prefs?.length) {
      throw new Error(payload.error);
    }
    let n = 0;
    for (const p of payload.prefs ?? []) {
      if (!p?.objectApi) continue;
      await upsertUserPrefs(this.db, {
        objectApi: p.objectApi,
        favourites: Array.isArray(p.favourites) ? p.favourites.map(String) : [],
        pinnedListViewId: p.pinnedListViewId ?? null,
        calendarField: p.calendarField ?? null
      });
      n++;
    }
    await setSyncCursor(this.db, 'prefs', nowIso());
    return n;
  }

  /** Write-through upsert of one object's prefs (online). Still caches locally first. */
  async pushObjectPrefs(prefs: {
    objectApi: string;
    favourites: string[];
    pinnedListViewId: string | null;
    calendarField: string | null;
  }): Promise<void> {
    await upsertUserPrefs(this.db, prefs);
    await this.client.post(OSR_API.prefs, {
      objectApi: prefs.objectApi,
      favourites: prefs.favourites,
      pinnedListViewId: prefs.pinnedListViewId,
      calendarField: prefs.calendarField
    });
  }

  /** Push all pending outbox batches before any pull (local changes first). */
  async drainOutbox(maxRounds = 40): Promise<PushOutboxResult> {
    const totals: PushOutboxResult = { synced: 0, failed: 0, conflicts: 0, failures: [] };
    for (let round = 0; round < maxRounds; round++) {
      const pending = await listOutboxForPush(this.db, 1);
      if (!pending.length) break;
      const batch = await this.pushOutbox();
      totals.synced += batch.synced;
      totals.failed += batch.failed;
      totals.conflicts += batch.conflicts;
      totals.failures.push(...batch.failures);
      if (batch.synced === 0 && batch.failed === 0 && batch.conflicts === 0) break;
    }
    return totals;
  }

  async pushOutbox(): Promise<PushOutboxResult> {
    const batch = await listOutboxForPush(this.db, this.options.maxOutboxBatch ?? 25);
    let synced = 0;
    let failed = 0;
    let conflicts = 0;
    const failures: OutboxPushFailure[] = [];
    if (!batch.length) return { synced, failed, conflicts, failures };

    const response = await this.client.post<{
      results: {
        clientId: string;
        status: 'synced' | 'failed' | 'conflict';
        error?: string;
        serverRecord?: Record<string, unknown>;
        clientRecord?: Record<string, unknown>;
        serverId?: string;
      }[];
    }>(OSR_API.outbox, {
      actions: batch.map((b) => ({
        clientId: b.id,
        op: b.op,
        objectApi: b.objectApi,
        recordId: b.recordId,
        payload: b.payload,
        attempts: b.attempts
      }))
    });

    const policy = this.options.conflictPolicy ?? 'manual';
    for (const r of response.results) {
      if (r.status === 'synced') {
        const item = batch.find((b) => b.id === r.clientId);
        if (
          item?.objectApi &&
          item.recordId?.startsWith('local_') &&
          r.serverId &&
          r.serverId !== item.recordId
        ) {
          try {
            await remapRecordId(
              this.db,
              item.objectApi,
              item.recordId,
              r.serverId,
              r.serverRecord ?? (item.payload as Record<string, unknown> | undefined)
            );
          } catch {
            /* remap must not block outbox ack */
          }
        }
        await markOutbox(this.db, r.clientId, 'synced');
        synced++;
      } else if (r.status === 'conflict') {
        conflicts++;
        const item = batch.find((b) => b.id === r.clientId);
        failures.push({
          clientId: r.clientId,
          op: item?.op ?? 'update',
          objectApi: item?.objectApi,
          recordId: item?.recordId,
          error: r.error ?? 'Server version is newer',
          status: 'conflict'
        });
        await addConflict(this.db, {
          outboxId: r.clientId,
          objectApi: batch.find((b) => b.id === r.clientId)?.objectApi,
          recordId: batch.find((b) => b.id === r.clientId)?.recordId,
          server: r.serverRecord ?? {},
          client: r.clientRecord ?? batch.find((b) => b.id === r.clientId)?.payload
        });
        if (policy === 'server-wins') {
          await markOutbox(this.db, r.clientId, 'synced', 'server-wins');
        } else if (policy === 'client-wins') {
          // leave pending for retry with force flag — mark failed for visibility
          await markOutbox(this.db, r.clientId, 'failed', 'client-wins-retry');
        } else {
          await markOutbox(this.db, r.clientId, 'conflict', r.error ?? 'conflict');
        }
        try {
          await appendLog(this.db, {
            category: 'sync',
            source: 'outbox',
            message: r.error ?? 'conflict',
            detail: {
              outboxId: r.clientId,
              status: r.status,
              objectApi: batch.find((b) => b.id === r.clientId)?.objectApi,
              recordId: batch.find((b) => b.id === r.clientId)?.recordId
            },
            tags: ['push', 'conflict']
          });
        } catch {
          /* ignore */
        }
      } else {
        const item = batch.find((b) => b.id === r.clientId);
        failures.push({
          clientId: r.clientId,
          op: item?.op ?? 'update',
          objectApi: item?.objectApi,
          recordId: item?.recordId,
          error: r.error ?? 'Sync failed',
          status: 'failed'
        });
        await markOutbox(this.db, r.clientId, 'failed', r.error ?? 'failed');
        if (item?.op === 'delete' && item.objectApi && item.recordId) {
          try {
            await restoreSoftDeletedRecord(this.db, item.objectApi, item.recordId);
          } catch {
            /* restore must not block failure reporting */
          }
        }
        failed++;
        try {
          await appendLog(this.db, {
            category: 'sync',
            source: 'outbox',
            message: r.error ?? 'failed',
            detail: {
              outboxId: r.clientId,
              status: 'failed',
              objectApi: batch.find((b) => b.id === r.clientId)?.objectApi,
              recordId: batch.find((b) => b.id === r.clientId)?.recordId
            },
            tags: ['push', 'failed']
          });
        } catch {
          /* ignore */
        }
      }
    }
    return { synced, failed, conflicts, failures };
  }

  /**
   * Compare a sample of local records to Salesforce and repair drift.
   * Intended to run every N successful syncs (e.g. every 5th).
   */
  async validateLocalAgainstServer(objectApis?: string[]): Promise<SyncValidationReport> {
    const issues: SyncValidationIssue[] = [];
    let repaired = 0;
    const checkedObjects: string[] = [];

    let objects = objectApis?.filter(Boolean) ?? [];
    if (!objects.length) {
      try {
        const { rows } = await this.db.execute(
          `SELECT DISTINCT object_api AS object_api FROM records WHERE deleted=0 LIMIT 40`
        );
        objects = rows.map((r) => String(r.object_api)).filter(Boolean);
      } catch {
        objects = [];
      }
    }
    const preferred = ['Account', 'Visit__c', 'Contact', 'Product2', 'Event', 'Task'];
    objects = [
      ...preferred.filter((o) => objects.includes(o)),
      ...objects.filter((o) => !preferred.includes(o))
    ].slice(0, 8);
    if (!objects.length) objects = ['Account', 'Visit__c'];

    const pending = await listPendingOutbox(this.db, 100);
    for (const item of pending) {
      if ((item.attempts ?? 0) >= 3) {
        issues.push({
          objectApi: item.objectApi || 'Unknown',
          kind: 'stale_outbox',
          recordId: item.recordId,
          detail: `Outbox ${item.op} still pending after ${item.attempts} attempts`
        });
      }
    }

    for (const objectApi of objects) {
      checkedObjects.push(objectApi);
      try {
        const { rows: localRows } = await this.db.execute(
          `SELECT id, payload_json, version FROM records WHERE object_api=? AND deleted=0 LIMIT 400`,
          [objectApi]
        );
        const localById = new Map<
          string,
          { payload: Record<string, unknown>; serverUpdatedAt: string }
        >();
        for (const row of localRows) {
          const id = String(row.id);
          if (id.startsWith('local_')) continue;
          try {
            localById.set(id, {
              payload: JSON.parse(String(row.payload_json)) as Record<string, unknown>,
              serverUpdatedAt: String(row.version ?? '')
            });
          } catch {
            /* skip bad row */
          }
        }

        const page = await this.client.post<{
          records?: Record<string, unknown>[];
          error?: string | null;
        }>(OSR_API.data, {
          objectApi,
          fields: ['Id', 'Name', 'SystemModstamp', 'LastModifiedDate'],
          pageSize: 200
        });

        if (page.error && !(page.records?.length)) {
          issues.push({
            objectApi,
            kind: 'error',
            detail: page.error
          });
          continue;
        }

        const serverRecords = page.records ?? [];
        const serverIds = new Set(serverRecords.map((r) => String(r.Id)));

        if (localById.size > 0 && serverRecords.length === 0) {
          issues.push({
            objectApi,
            kind: 'count_gap',
            detail: `Local has ${localById.size} synced row(s) but server returned 0 — possible query/permission issue`
          });
        } else if (Math.abs(localById.size - serverRecords.length) > 25) {
          issues.push({
            objectApi,
            kind: 'count_gap',
            detail: `Local sample ${localById.size} vs server recent page ${serverRecords.length}`
          });
        }

        for (const remote of serverRecords) {
          const id = String(remote.Id ?? '');
          if (!id) continue;
          const remoteStamp = String(remote.SystemModstamp ?? remote.LastModifiedDate ?? '');
          const local = localById.get(id);
          if (!local) {
            await upsertRecord(this.db, objectApi, id, remote, remoteStamp);
            repaired++;
            issues.push({
              objectApi,
              kind: 'missing_local',
              recordId: id,
              detail: 'Present on server, missing locally — pulled'
            });
            continue;
          }
          const localStamp = String(
            local.serverUpdatedAt || local.payload.SystemModstamp || local.payload.LastModifiedDate || ''
          );
          if (remoteStamp && localStamp && remoteStamp !== localStamp) {
            const remoteTime = Date.parse(remoteStamp);
            const localTime = Date.parse(localStamp);
            if (Number.isFinite(remoteTime) && Number.isFinite(localTime) && remoteTime > localTime) {
              await upsertRecord(this.db, objectApi, id, { ...local.payload, ...remote }, remoteStamp);
              repaired++;
              issues.push({
                objectApi,
                kind: 'modstamp_drift',
                recordId: id,
                detail: `Server newer (${remoteStamp} > ${localStamp}) — updated local`
              });
            } else if (
              Number.isFinite(remoteTime) &&
              Number.isFinite(localTime) &&
              localTime > remoteTime &&
              !pending.some((p) => p.recordId === id)
            ) {
              // Local claims newer but nothing queued — re-enqueue update so it truly syncs
              await enqueueOutbox(this.db, {
                op: 'update',
                objectApi,
                recordId: id,
                payload: local.payload
              });
              repaired++;
              issues.push({
                objectApi,
                kind: 'modstamp_drift',
                recordId: id,
                detail: `Local newer without outbox — re-queued push (${localStamp} > ${remoteStamp})`
              });
            }
          }
        }

        // Sample local IDs not on the recent server page — verify they still exist
        const orphanCandidates = [...localById.keys()].filter((id) => !serverIds.has(id)).slice(0, 15);
        if (orphanCandidates.length) {
          const idList = orphanCandidates.map((id) => `'${id.replace(/'/g, "\\'")}'`).join(',');
          try {
            const check = await this.client.post<{ records?: Record<string, unknown>[] }>(OSR_API.data, {
              objectApi,
              fields: ['Id', 'SystemModstamp'],
              filter: `Id IN (${idList})`,
              pageSize: orphanCandidates.length
            });
            const found = new Set((check.records ?? []).map((r) => String(r.Id)));
            for (const id of orphanCandidates) {
              if (!found.has(id)) {
                issues.push({
                  objectApi,
                  kind: 'missing_server',
                  recordId: id,
                  detail: 'Local copy not found on server (deleted remotely or never synced)'
                });
              }
            }
            for (const remote of check.records ?? []) {
              const id = String(remote.Id);
              const stamp = String(remote.SystemModstamp ?? '');
              const local = localById.get(id);
              if (local && stamp && stamp !== String(local.serverUpdatedAt || local.payload.SystemModstamp || '')) {
                await upsertRecord(this.db, objectApi, id, { ...local.payload, ...remote }, stamp);
                repaired++;
              }
            }
          } catch (e) {
            issues.push({
              objectApi,
              kind: 'error',
              detail: `Orphan check failed: ${e instanceof Error ? e.message : String(e)}`
            });
          }
        }
      } catch (e) {
        issues.push({
          objectApi,
          kind: 'error',
          detail: e instanceof Error ? e.message : String(e)
        });
      }
    }

    // Cap issue list for UI; keep all repairs already applied
    const capped = issues.slice(0, 40);
    return {
      checkedObjects,
      repaired,
      issues: capped,
      ok: capped.filter((i) => i.kind !== 'count_gap').length === 0 || repaired > 0
    };
  }

  async fullSync(
    hooks?: SyncHooks
  ): Promise<{ pull: PullResult; push: PushOutboxResult }> {
    let push: PushOutboxResult = { synced: 0, failed: 0, conflicts: 0, failures: [] };
    try {
      hooks?.onProgress?.({ phase: 'push', channel: 'Outbox', current: 0, total: 0 });
    } catch {
      /* ignore */
    }
    try {
      push = await this.drainOutbox();
    } catch (e) {
      // Outbox failures must not block pull / leave UI spinning
      try {
        await appendLog(this.db, {
          category: 'sync',
          source: 'outbox',
          message: e instanceof Error ? e.message : String(e),
          detail: { stack: e instanceof Error ? e.stack?.slice(0, 2000) : undefined },
          tags: ['push', 'batch-error']
        });
      } catch {
        /* ignore */
      }
    }
    const pull = await this.pullAll(undefined, hooks);
    return { pull, push };
  }
}

/** Local-first write helper used by UI */
export async function localSaveRecord(
  db: SqlExecutor,
  objectApi: string,
  record: Record<string, unknown>,
  isNew: boolean
): Promise<{ recordId: string; outboxId: string }> {
  const id = String(record.Id ?? `local_${crypto.randomUUID()}`);
  const payload = { ...record, Id: id };
  await upsertRecord(db, objectApi, id, payload);
  const outboxId = await enqueueOutbox(db, {
    op: isNew ? 'create' : 'update',
    objectApi,
    recordId: id,
    payload
  });
  return { recordId: id, outboxId };
}

export async function localDeleteRecord(
  db: SqlExecutor,
  objectApi: string,
  recordId: string
): Promise<string> {
  await softDeleteRecord(db, objectApi, recordId);
  return enqueueOutbox(db, {
    op: 'delete',
    objectApi,
    recordId,
    payload: { Id: recordId }
  });
}

/** Demo / offline mock client for skeleton without org */
export function createMockSyncClient(seed?: Partial<SyncProfile>): SyncHttpClient {
  const profile: SyncProfile = {
    name: seed?.name ?? 'Default_Field_Rep',
    objects: seed?.objects ?? [
      { apiName: 'Account', fields: ['Id', 'Name', 'Industry', 'Phone', 'SystemModstamp'] },
      {
        apiName: 'Visit__c',
        fields: ['Id', 'Name', 'Account__c', 'Status__c', 'Planned_Date__c', 'SystemModstamp'],
        soqlFilter: 'Planned_Date__c = LAST_N_DAYS:14'
      }
    ],
    flexiPages: seed?.flexiPages ?? ['Account_Record_Page', 'Field_Rep_Home'],
    tabs: seed?.tabs ?? [
      'Account',
      'Contact',
      'Lead',
      'Opportunity',
      'Visit__c',
      'Task',
      'Event'
    ],
    apps: seed?.apps ?? ['*'],
    lwcBundles: seed?.lwcBundles ?? [
      'c/visitCallShellLite',
      'c/clmPlayerLite',
      'c/fieldRepHomeTodayPlan',
      'c/fieldRepHomeMetrics',
      'c/fieldRepHomeNextBestCustomer',
      'c/fieldRepHomeClmPrefetch',
      'c/homeOfficeMessages',
      'c/repLocationPublisher',
      'c/reportsHub'
    ],
    fileScopes: seed?.fileScopes ?? [{ linkedEntityObject: 'Visit__c', maxBytes: 5_000_000 }]
  };

  const accounts = [
    { Id: '001MOCK000000001', Name: 'Cairo Central Pharmacy', Industry: 'Pharmacy', Phone: '+20-2-123', SystemModstamp: nowIso() },
    { Id: '001MOCK000000002', Name: 'Dr. Hassan Clinic', Industry: 'HCP', Phone: '+20-2-456', SystemModstamp: nowIso() }
  ];
  const visits = [
    {
      Id: 'a0VMMOCK0000001',
      Name: 'V-1001',
      Account__c: '001MOCK000000001',
      Status__c: 'Planned',
      Planned_Date__c: new Date().toISOString().slice(0, 10),
      SystemModstamp: nowIso()
    }
  ];

  return {
    async get<T = unknown>(path: string): Promise<T> {
      if (path.includes('/hello')) {
        return {
          ok: true,
          orgId: '00DMOCK',
          userId: '005MOCK',
          message: 'OSR Sync Pack hello'
        } as T;
      }
      if (path.includes('/profile')) return profile as T;
      if (path.includes('/prefs')) {
        return { ok: true, userId: '005MOCK', prefs: [] } as T;
      }
      throw new Error(`Mock GET unknown: ${path}`);
    },
    async post<T = unknown>(path: string, body: unknown): Promise<T> {
      if (path.includes('/prefs')) {
        const b = body as {
          objectApi: string;
          favourites?: string[];
          pinnedListViewId?: string | null;
          calendarField?: string | null;
        };
        return {
          ok: true,
          userId: '005MOCK',
          prefs: [
            {
              objectApi: b.objectApi,
              favourites: b.favourites ?? [],
              pinnedListViewId: b.pinnedListViewId ?? null,
              calendarField: b.calendarField ?? null
            }
          ]
        } as T;
      }
      if (path.includes('/metadata')) {
        return {
          cursor: nowIso(),
          objects: [
            {
              apiName: 'Account',
              label: 'Account',
              keyPrefix: '001',
              describe: {
                name: 'Account',
                label: 'Account',
                fields: [
                  { name: 'Name', label: 'Account Name', type: 'string', required: true },
                  {
                    name: 'Industry',
                    label: 'Industry',
                    type: 'picklist',
                    required: false,
                    picklistValues: ['Healthcare', 'Technology', 'Manufacturing']
                  },
                  { name: 'Phone', label: 'Phone', type: 'phone', required: false }
                ]
              }
            },
            {
              apiName: 'Visit__c',
              label: 'Visit',
              keyPrefix: 'a0V',
              describe: {
                name: 'Visit__c',
                label: 'Visit',
                fields: [
                  { name: 'Name', label: 'Visit Name', type: 'string', required: false },
                  { name: 'Account__c', label: 'Account', type: 'reference', required: true, referenceTo: ['Account'] },
                  {
                    name: 'Status__c',
                    label: 'Status',
                    type: 'picklist',
                    required: true,
                    picklistValues: ['Planned', 'In Progress', 'Completed', 'Cancelled']
                  },
                  { name: 'Planned_Date__c', label: 'Planned Date', type: 'date', required: false }
                ]
              }
            }
          ],
          layouts: [
            {
              id: 'layAccount',
              objectApi: 'Account',
              name: 'Account Layout',
              layout: {
                source: 'mock',
                sections: [
                  {
                    label: 'Information',
                    columns: [
                      [
                        { field: 'Name', behavior: 'Required' },
                        { field: 'Industry', behavior: 'Edit' },
                        { field: 'Phone', behavior: 'Edit' }
                      ]
                    ]
                  }
                ],
                relatedLists: [
                  {
                    relatedList: 'Visits',
                    label: 'Visits',
                    objectApi: 'Visit__c',
                    lookupField: 'Account__c',
                    fields: ['Name', 'Status__c', 'Planned_Date__c']
                  },
                  {
                    relatedList: 'Contacts',
                    label: 'Contacts',
                    objectApi: 'Contact',
                    lookupField: 'AccountId',
                    fields: ['Name', 'Title', 'Phone']
                  }
                ],
                highlightsFields: ['Name', 'Industry', 'Phone'],
                platformActionList: ['Edit', 'Delete', 'NewContact'],
                pathField: null,
                pathValues: []
              }
            },
            {
              id: 'layVisit',
              objectApi: 'Visit__c',
              name: 'Visit Layout',
              layout: {
                source: 'mock',
                sections: [
                  {
                    label: 'Visit',
                    columns: [
                      [
                        { field: 'Name', behavior: 'Edit' },
                        { field: 'Account__c', behavior: 'Required' },
                        { field: 'Status__c', behavior: 'Required' },
                        { field: 'Planned_Date__c', behavior: 'Edit' }
                      ]
                    ]
                  }
                ],
                relatedLists: [],
                highlightsFields: ['Name', 'Status__c', 'Planned_Date__c', 'Account__c'],
                platformActionList: ['Edit', 'Delete'],
                pathField: 'Status__c',
                pathValues: ['Planned', 'In Progress', 'Completed', 'Cancelled']
              }
            }
          ],
          flexiPages: [
            {
              id: 'fp1',
              developerName: 'Account_Record_Page',
              type: 'RecordPage',
              page: {
                type: 'RecordPage',
                sobjectType: 'Account',
                source: 'mock',
                formFactor: 'Large',
                templates: [
                  { name: 'default', formFactor: 'Large', regions: ['header', 'main', 'sidebar'] },
                  { name: 'phone', formFactor: 'Small', regions: ['header', 'main'] }
                ],
                regions: [
                  {
                    name: 'header',
                    components: [{ type: 'force:highlightsPanel' }]
                  },
                  {
                    name: 'main',
                    components: [
                      {
                        type: 'force:pathAssistant',
                        attributes: { picklistApiName: 'Industry' }
                      },
                      {
                        type: 'flexipage:fieldSection',
                        attributes: { label: 'Details' },
                        fieldInstances: [
                          { fieldApiName: 'Name', uiBehavior: 'Required' },
                          { fieldApiName: 'Industry', uiBehavior: 'Edit' },
                          { fieldApiName: 'Phone', uiBehavior: 'Edit' }
                        ],
                        visibilityRule: { criteria: null }
                      },
                      { type: 'c/visitCallShellLite', attributes: { label: 'Visit actions' } }
                    ]
                  },
                  {
                    name: 'sidebar',
                    formFactor: 'Large',
                    components: [
                      {
                        type: 'force:relatedListSingleContainer',
                        attributes: {
                          relatedListApiName: 'Visits',
                          parentFieldApiName: 'Account__c'
                        }
                      }
                    ]
                  }
                ]
              }
            },
            {
              id: 'fpHome',
              developerName: 'Field_Rep_Home',
              type: 'HomePage',
              page: {
                type: 'HomePage',
                source: 'mock',
                regions: [
                  {
                    name: 'main',
                    components: [
                      { type: 'osr:todayVisits', attributes: { label: "Today's Visits" } },
                      { type: 'osr:recentAccounts', attributes: { label: 'Accounts' } },
                      { type: 'osr:quickLinks', attributes: { label: 'Quick Links' } },
                      { type: 'c/visitCallShellLite', attributes: { label: 'Visit Call Shell' } },
                      { type: 'c/clmPlayerLite', attributes: { label: 'CLM Player' } }
                    ]
                  },
                  {
                    name: 'sidebar',
                    components: [
                      { type: 'osr:syncStatus', attributes: { label: 'Offline Sync' } }
                    ]
                  }
                ]
              }
            },
            {
              id: 'fpPlanner',
              developerName: 'Field_Rep_Planner',
              type: 'AppPage',
              page: {
                type: 'AppPage',
                source: 'mock',
                regions: [
                  {
                    name: 'main',
                    components: [
                      { type: 'c/fieldRepPlanner', attributes: { label: 'Planner' } }
                    ]
                  }
                ]
              }
            }
          ],
          tabs: [
            { id: 't1', developerName: 'Account', label: 'Accounts', sortOrder: 1, tab: { objectApi: 'Account', tabType: 'object' } },
            { id: 't2', developerName: 'Visit__c', label: 'Visits', sortOrder: 2, tab: { objectApi: 'Visit__c', tabType: 'object' } },
            {
              id: 't3',
              developerName: 'Field_Rep_Planner',
              label: 'Planner',
              sortOrder: 3,
              tab: {
                tabType: 'flexipage',
                pageDeveloperName: 'Field_Rep_Planner'
              }
            },
            {
              id: 't4',
              developerName: 'CLM_Presentations',
              label: 'CLM Presentations',
              sortOrder: 4,
              tab: { tabType: 'lwc', lwcBundle: 'c/clmPresentationsHub' }
            }
          ],
          apps: [
            {
              id: 'a1',
              developerName: 'LightningSales',
              label: 'Pharma Field',
              app: {
                tabDeveloperNames: [
                  'Field_Rep_Planner',
                  'Account',
                  'Visit__c',
                  'CLM_Presentations',
                  'Lead',
                  'Contact',
                  'Opportunity',
                  'Task',
                  'Event'
                ],
                homeFlexiPageDeveloperName: 'Field_Rep_Home',
                source: 'mock'
              }
            },
            {
              id: 'a2',
              developerName: 'SDO_Sales_App',
              label: 'Sales',
              app: {
                tabDeveloperNames: ['Account', 'Contact', 'Opportunity', 'Lead'],
                homeFlexiPageDeveloperName: 'Field_Rep_Home',
                source: 'mock'
              }
            },
            {
              id: 'a3',
              developerName: 'Zeta_Management',
              label: 'Pharma Management',
              app: {
                tabDeveloperNames: ['Account', 'Opportunity', 'Case'],
                homeFlexiPageDeveloperName: 'Field_Rep_Home',
                source: 'mock'
              }
            }
          ],
          validationRules: [
            {
              id: 'vr1',
              objectApi: 'Account',
              name: 'Name_Required',
              active: true,
              errorCondition: 'ISBLANK(Name)',
              errorMessage: 'Account Name is required',
              errorDisplayField: 'Name',
              rule: {}
            },
            {
              id: 'vr2',
              objectApi: 'Visit__c',
              name: 'Status_Required',
              active: true,
              errorCondition: 'ISBLANK(Status__c)',
              errorMessage: 'Status is required',
              errorDisplayField: 'Status__c',
              rule: {}
            }
          ],
          listViews: [
            {
              id: '00BMMOCKALLACC',
              objectApi: 'Account',
              developerName: 'AllAccounts',
              label: 'All Accounts',
              listview: {
                id: '00BMMOCKALLACC',
                developerName: 'AllAccounts',
                label: 'All Accounts',
                soqlCompatible: true,
                columns: [
                  { fieldOrColumn: 'Name', label: 'Account Name', type: 'string', sortable: true },
                  { fieldOrColumn: 'Industry', label: 'Industry', type: 'picklist', sortable: true },
                  { fieldOrColumn: 'Phone', label: 'Phone', type: 'phone', sortable: false }
                ],
                filters: [],
                filtersSupported: true,
                displayType: 'List',
                kanbanGroupField: 'Industry',
                recordIds: accounts.map((a) => a.Id)
              }
            },
            {
              id: '00BMMOCKALLVIS',
              objectApi: 'Visit__c',
              developerName: 'All',
              label: 'All',
              listview: {
                id: '00BMMOCKALLVIS',
                developerName: 'All',
                label: 'All',
                soqlCompatible: true,
                columns: [
                  { fieldOrColumn: 'Name', label: 'Visit Name', type: 'string', sortable: true },
                  { fieldOrColumn: 'Status__c', label: 'Status', type: 'picklist', sortable: true },
                  { fieldOrColumn: 'Planned_Date__c', label: 'Planned Date', type: 'date', sortable: true }
                ],
                filters: [],
                filtersSupported: true,
                displayType: 'List',
                kanbanGroupField: 'Status__c',
                recordIds: visits.map((v) => v.Id)
              }
            },
            {
              id: '00BMMOCKPLANNED',
              objectApi: 'Visit__c',
              developerName: 'Planned_Visits',
              label: 'Planned Visits',
              listview: {
                id: '00BMMOCKPLANNED',
                developerName: 'Planned_Visits',
                label: 'Planned Visits',
                soqlCompatible: true,
                columns: [
                  { fieldOrColumn: 'Name', label: 'Visit Name', type: 'string', sortable: true },
                  { fieldOrColumn: 'Status__c', label: 'Status', type: 'picklist', sortable: true },
                  { fieldOrColumn: 'Planned_Date__c', label: 'Planned Date', type: 'date', sortable: true }
                ],
                filters: [{ field: 'Status__c', operation: 'equals', value: 'Planned' }],
                booleanFilter: '1',
                filtersSupported: true,
                displayType: 'List',
                kanbanGroupField: 'Status__c',
                recordIds: visits.filter((v) => v.Status__c === 'Planned').map((v) => v.Id)
              }
            }
          ],
          actions: [
            {
              id: 'actAccEdit',
              objectApi: 'Account',
              name: 'Edit',
              label: 'Edit',
              action: { type: 'StandardButton', actionType: 'Edit', offlineSafe: true }
            },
            {
              id: 'actAccDelete',
              objectApi: 'Account',
              name: 'Delete',
              label: 'Delete',
              action: { type: 'StandardButton', actionType: 'Delete', offlineSafe: true }
            },
            {
              id: 'actAccNewContact',
              objectApi: 'Account',
              name: 'NewContact',
              label: 'New Contact',
              action: {
                type: 'QuickAction',
                actionType: 'Create',
                targetObject: 'Contact',
                offlineSafe: true,
                fieldDefaults: {}
              }
            },
            {
              id: 'actVisEdit',
              objectApi: 'Visit__c',
              name: 'Edit',
              label: 'Edit',
              action: { type: 'StandardButton', actionType: 'Edit', offlineSafe: true }
            }
          ],
          compactLayouts: [
            {
              id: 'clAccount',
              objectApi: 'Account',
              name: 'Account Compact',
              compact: { fields: ['Name', 'Industry', 'Phone'] }
            },
            {
              id: 'clVisit',
              objectApi: 'Visit__c',
              name: 'Visit Compact',
              compact: { fields: ['Name', 'Status__c', 'Planned_Date__c', 'Account__c'] }
            }
          ]
        } as T;
      }
      if (path.includes('/sharing')) {
        return {
          sets: [
            { objectApi: 'Account', ids: accounts.map((a) => a.Id) },
            { objectApi: 'Visit__c', ids: visits.map((v) => v.Id) }
          ]
        } as T;
      }
      if (path.includes('/data')) {
        const b = body as { objectApi: string };
        const records = b.objectApi === 'Account' ? accounts : b.objectApi === 'Visit__c' ? visits : [];
        return { records, deletedIds: [], nextCursor: null, done: true } as T;
      }
      if (path.includes('/files')) {
        return {
          cursor: nowIso(),
          files: [
            {
              contentVersionId: '068MOCKFILE001',
              contentDocumentId: '069MOCKDOC001',
              title: 'Coloverin_CLM_Deck.pdf',
              path: 'mock://files/Coloverin_CLM_Deck.pdf',
              hash: 'abc123',
              size: 1024,
              mimeType: 'application/pdf'
            }
          ]
        } as T;
      }
      if (path.includes('/static-resources')) {
        return {
          ok: true,
          resources: [
            {
              name: 'leaflet',
              contentType: 'application/zip',
              bodyBase64: 'UEsDBAoAAAAAA=======', // placeholder; live sync pulls real zip
              size: 16,
              cacheControl: 'Public'
            }
          ]
        } as T;
      }
      if (path.includes('/lwc')) {
        return {
          bundles: [
            {
              bundleName: 'c/visitCallShell',
              version: '1',
              sourceJs: `export default class VisitCallShell extends HTMLElement {
  connectedCallback(){ this.innerHTML = '<div class="lwc-stub"><h3>Visit Call Shell</h3><p>Prefer Lit fidelity port.</p></div>'; }
}`
            },
            {
              bundleName: 'c/visitCallShellLite',
              version: '1',
              sourceJs: `export default class VisitCallShellLite extends HTMLElement {
  connectedCallback(){ this.innerHTML = '<div class="lwc-stub"><h3>Visit Call Shell (offline LWC)</h3><p>Tier A stub — local adapters.</p></div>'; }
}`
            },
            {
              bundleName: 'c/clmPlayerLite',
              version: '1',
              sourceJs: `export default class ClmPlayerLite extends HTMLElement {
  connectedCallback(){ this.innerHTML = '<div class="lwc-stub"><h3>CLM Player (offline)</h3><p>Filesystem-backed deck playback stub.</p></div>'; }
}`
            }
          ]
        } as T;
      }
      if (path.includes('/apex-cache')) {
        const now = nowIso();
        return {
          ok: true,
          entries: [
            {
              key: 'todayPlan',
              fetchedAt: now,
              payload: {
                visits: visits.map((v) => ({
                  id: v.Id,
                  name: v.Name,
                  accountId: v.Account__c,
                  accountName: accounts.find((a) => a.Id === v.Account__c)?.Name ?? 'Account',
                  status: v.Status__c,
                  startDateTime: `${v.Planned_Date__c}T15:00:00.000Z`,
                  endDateTime: `${v.Planned_Date__c}T16:00:00.000Z`,
                  accountSpecialty: 'General',
                  accountRecordTypeName: 'Medical Professional (HCP)',
                  accountLatitude: 30.0444,
                  accountLongitude: 31.2357
                })),
                timeOffBlocks: []
              }
            },
            {
              key: 'plannerWeek',
              fetchedAt: now,
              payload: {
                visits: visits.map((v) => ({
                  id: v.Id,
                  name: v.Name,
                  accountId: v.Account__c,
                  accountName: accounts.find((a) => a.Id === v.Account__c)?.Name ?? 'Account',
                  status: v.Status__c,
                  startDateTime: `${v.Planned_Date__c}T15:00:00.000Z`,
                  endDateTime: `${v.Planned_Date__c}T16:00:00.000Z`
                })),
                timeOffBlocks: []
              }
            },
            {
              key: 'plannerAccounts',
              fetchedAt: now,
              payload: {
                accounts: accounts.map((a) => ({
                  id: a.Id,
                  name: a.Name,
                  specialty: 'General',
                  specialtyApiValue: 'General',
                  city: 'Cairo',
                  recordTypeName: 'Pharmacy',
                  recordTypeDeveloperName: 'Pharmacy',
                  classification: 'A',
                  brickId: 'brick1',
                  brickName: 'Helwan'
                })),
                hasMore: false,
                totalCount: accounts.length
              }
            },
            {
              key: 'homeMetrics',
              fetchedAt: now,
              payload: {
                visitCoveragePercent: 42,
                customerCoveragePercent: 35,
                lfPercentTotal: 20,
                rfPercentTotal: 40,
                mfPercentTotal: 10,
                byClassification: [
                  {
                    classification: 'A',
                    visitCoveragePercent: 50,
                    customerCoveragePercent: 40,
                    lfPercent: 0,
                    rfPercent: 50,
                    mfPercent: 0
                  },
                  {
                    classification: 'B',
                    visitCoveragePercent: 30,
                    customerCoveragePercent: 25,
                    lfPercent: 20,
                    rfPercent: 30,
                    mfPercent: 10
                  },
                  {
                    classification: 'C',
                    visitCoveragePercent: 20,
                    customerCoveragePercent: 15,
                    lfPercent: 40,
                    rfPercent: 20,
                    mfPercent: 20
                  }
                ]
              }
            },
            {
              key: 'gamification',
              fetchedAt: now,
              payload: {
                userFirstName: 'Rep',
                streaks: { activityStreak: 1, coverageStreak: 0 },
                badges: [
                  { badgeId: 'coverage_champion', earned: false, progressPercent: 0 },
                  { badgeId: 'on_target', earned: false, progressPercent: 0 },
                  { badgeId: 'class_a_ace', earned: false, progressPercent: 0 },
                  { badgeId: 'streak_starter', earned: false, progressPercent: 33 },
                  { badgeId: 'perfect_week', earned: false, progressPercent: 20 },
                  { badgeId: 'early_bird', earned: true, progressPercent: 100 }
                ]
              }
            },
            {
              key: 'rankings',
              fetchedAt: now,
              payload: {
                buName: 'Diabetes',
                buRank: 1,
                buTotal: 1,
                companyRank: 5,
                companyTotal: 7,
                myCoveragePercent: 42,
                isFirstInBu: true,
                top5InBu: [
                  {
                    rank: 1,
                    name: 'You',
                    coveragePercent: 42,
                    isCurrentUser: true,
                    badgeIcon: '🥇'
                  }
                ],
                top5Company: []
              }
            },
            {
              key: 'nextBestCustomers',
              fetchedAt: now,
              payload: accounts.slice(0, 5).map((a, i) => ({
                rank: i + 1,
                accountId: a.Id,
                accountName: a.Name,
                specialty: 'General',
                actualVisits: 0,
                targetVisits: 1,
                visitGap: 1,
                planned: false,
                plannedToday: false,
                score: 90 - i * 5
              }))
            },
            {
              key: 'officeMessages',
              fetchedAt: now,
              payload: [
                {
                  recordId: 'a0XMOCKMSG001',
                  subject: 'Q2 Empacoza Trio focus',
                  body: 'Prioritize Empacoza Trio discussions this week.',
                  authorName: 'Head Office',
                  publishedLabel: 'Today',
                  priority: 'High',
                  isHighPriority: true
                }
              ]
            },
            {
              key: 'clmManifest',
              fetchedAt: now,
              payload: { presentations: [], ratingLayoutJson: null }
            },
            {
              key: 'myLearning',
              fetchedAt: now,
              payload: [
                {
                  instanceId: 'a0LMOCKCOURSE001',
                  materialId: 'a0KMOCKMAT001',
                  title: 'Diabetes Line I Fundamentals',
                  description: 'Core product and disease-state training.',
                  status: 'In Progress',
                  progress: 35,
                  issueCertificate: true,
                  canShowCertificate: false
                }
              ]
            },
            {
              key: 'accountCoverage',
              fetchedAt: now,
              payload: []
            },
            {
              key: 'plannerViewer',
              fetchedAt: now,
              payload: {
                viewerMode: 'self',
                canSwitchView: false,
                defaultUserId: '005MOCKUSER',
                options: []
              }
            }
          ]
        } as T;
      }
      if (path.includes('/outbox')) {
        const b = body as { actions: { clientId: string }[] };
        return {
          results: (b.actions ?? []).map((a) => ({ clientId: a.clientId, status: 'synced' as const }))
        } as T;
      }
      throw new Error(`Mock POST unknown: ${path}`);
    }
  };
}
