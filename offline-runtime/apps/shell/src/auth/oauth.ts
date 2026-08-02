import type { SqlExecutor } from '@osr/db';
import { nowIso } from '@osr/db';
import {
  type OAuthConfig,
  type TokenSet,
  type SyncHttpClient,
  buildAuthorizeUrl,
  createPkce,
  saveTokens,
  loadTokens,
  createSfClient,
  SyncEngine,
  createMockSyncClient,
  OSR_API
} from '@osr/sync';
import { Capacitor } from '@capacitor/core';
import { CapacitorHttp } from '@capacitor/core';
import { Browser } from '@capacitor/browser';
import { App as CapApp } from '@capacitor/app';
import { Preferences } from '@capacitor/preferences';

const PKCE_VERIFIER_KEY = 'osr.oauth.pkce_verifier';
const OAUTH_STATE_KEY = 'osr.oauth.state';
const LOGIN_URL_KEY = 'osr.oauth.login_url';

async function prefSet(key: string, value: string): Promise<void> {
  await Preferences.set({ key, value });
}

async function prefGet(key: string): Promise<string | null> {
  const { value } = await Preferences.get({ key });
  return value;
}

export function getOAuthConfig(): OAuthConfig {
  const isNative = Capacitor.isNativePlatform();
  const clientId = import.meta.env.VITE_SF_CLIENT_ID ?? '';
  const loginUrl = import.meta.env.VITE_SF_LOGIN_URL ?? 'https://login.salesforce.com';
  const redirectUri = isNative
    ? import.meta.env.VITE_SF_REDIRECT_URI ?? 'com.osr.offline://oauth/callback'
    : import.meta.env.VITE_SF_WEB_REDIRECT_URI ??
      import.meta.env.VITE_SF_REDIRECT_URI ??
      `${window.location.origin}/oauth/callback`;
  return { loginUrl, clientId, redirectUri, apiVersion: '61.0' };
}

/** Token exchange that works on native (CapacitorHttp) and web (Netlify proxy). */
export async function exchangeCodeRobust(
  cfg: OAuthConfig,
  code: string,
  verifier: string
): Promise<TokenSet> {
  const tokenUrl = `${cfg.loginUrl.replace(/\/$/, '')}/services/oauth2/token`;
  const form: Record<string, string> = {
    grant_type: 'authorization_code',
    client_id: cfg.clientId,
    redirect_uri: cfg.redirectUri,
    code,
    code_verifier: verifier
  };

  if (Capacitor.isNativePlatform()) {
    const res = await CapacitorHttp.post({
      url: tokenUrl,
      headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
      data: form,
      connectTimeout: 30000,
      readTimeout: 30000
    });
    if (res.status < 200 || res.status >= 300) {
      throw new Error(`Token exchange failed: ${res.status} ${JSON.stringify(res.data)}`);
    }
    const json = (typeof res.data === 'string' ? JSON.parse(res.data) : res.data) as Record<
      string,
      string
    >;
    return {
      accessToken: json.access_token,
      refreshToken: json.refresh_token,
      instanceUrl: json.instance_url,
      issuedAt: nowIso()
    };
  }

  // Web: Salesforce token endpoint blocks browser CORS — proxy via Netlify function
  const proxyUrl = '/.netlify/functions/sf-token';
  const res = await fetch(proxyUrl, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({
      tokenUrl,
      ...form
    })
  });
  if (!res.ok) {
    const text = await res.text();
    throw new Error(`Token exchange failed: ${res.status} ${text}`);
  }
  const json = (await res.json()) as Record<string, string>;
  return {
    accessToken: json.access_token,
    refreshToken: json.refresh_token,
    instanceUrl: json.instance_url,
    issuedAt: nowIso()
  };
}

export async function beginSalesforceLogin(
  db: SqlExecutor,
  opts?: { loginUrl?: string }
): Promise<void> {
  const cfg = getOAuthConfig();
  if (opts?.loginUrl) cfg.loginUrl = opts.loginUrl.replace(/\/$/, '');
  if (!cfg.clientId || cfg.clientId.includes('YOUR_')) {
    throw new Error('Connected App client id is not configured (VITE_SF_CLIENT_ID).');
  }
  const { verifier, challenge } = await createPkce();
  const state = crypto.randomUUID();
  // Persist outside in-memory SQLite so values survive browser/deep-link roundtrip
  await prefSet(PKCE_VERIFIER_KEY, verifier);
  await prefSet(OAUTH_STATE_KEY, state);
  await prefSet(LOGIN_URL_KEY, cfg.loginUrl);
  await prefSet('osr.oauth.redirect_uri', cfg.redirectUri);
  const url = buildAuthorizeUrl(cfg, challenge, state);

  if (Capacitor.isNativePlatform()) {
    await Browser.open({ url, windowName: '_blank', presentationStyle: 'popover' });
  } else {
    window.location.assign(url);
  }
}

export async function completeSalesforceLogin(
  db: SqlExecutor,
  callbackUrl: string
): Promise<TokenSet> {
  const normalized = callbackUrl
    .replace('com.osr.offline://', 'https://osr.local/')
    .replace('com.osr.offline:/', 'https://osr.local/');
  const u = new URL(normalized);
  const code = u.searchParams.get('code');
  const state = u.searchParams.get('state');
  const err = u.searchParams.get('error');
  if (err) throw new Error(u.searchParams.get('error_description') || err);
  if (!code) throw new Error('OAuth callback missing code');

  const expectedState = await prefGet(OAUTH_STATE_KEY);
  if (expectedState && state && expectedState !== state) {
    throw new Error('OAuth state mismatch — try logging in again');
  }
  const verifier = await prefGet(PKCE_VERIFIER_KEY);
  if (!verifier) throw new Error('Missing PKCE verifier — restart login');

  const cfg = getOAuthConfig();
  const storedLogin = await prefGet(LOGIN_URL_KEY);
  const storedRedirect = await prefGet('osr.oauth.redirect_uri');
  if (storedLogin) cfg.loginUrl = storedLogin;
  if (storedRedirect) cfg.redirectUri = storedRedirect;

  const tokens = await exchangeCodeRobust(cfg, code, verifier);
  await saveTokens(db, tokens);
  // Also persist tokens in Preferences for process restarts with memory DB
  await prefSet('osr.oauth.tokens', JSON.stringify(tokens));

  if (Capacitor.isNativePlatform()) {
    try {
      await Browser.close();
    } catch {
      /* ignore */
    }
  }
  return tokens;
}

export async function clearSession(db: SqlExecutor): Promise<void> {
  await saveTokens(db, {
    accessToken: '',
    instanceUrl: '',
    issuedAt: nowIso()
  });
  await Preferences.remove({ key: 'osr.oauth.tokens' });
  await Preferences.remove({ key: PKCE_VERIFIER_KEY });
  await Preferences.remove({ key: OAUTH_STATE_KEY });
}

export async function loadSession(db: SqlExecutor): Promise<TokenSet | null> {
  const fromDb = await loadTokens(db);
  if (fromDb?.accessToken) return fromDb;
  const raw = await prefGet('osr.oauth.tokens');
  if (!raw) return null;
  try {
    const tokens = JSON.parse(raw) as TokenSet;
    if (tokens?.accessToken) {
      await saveTokens(db, tokens);
      return tokens;
    }
  } catch {
    /* ignore */
  }
  return null;
}

export function installOAuthDeepLinkHandler(
  db: SqlExecutor,
  onSuccess: (tokens: TokenSet) => void,
  onError: (message: string) => void
): () => void {
  if (!Capacitor.isNativePlatform()) {
    return () => undefined;
  }
  const sub = CapApp.addListener('appUrlOpen', async ({ url }) => {
    if (!url.includes('oauth') || !url.includes('callback')) return;
    try {
      const tokens = await completeSalesforceLogin(db, url);
      onSuccess(tokens);
    } catch (e) {
      onError(e instanceof Error ? e.message : String(e));
    }
  });
  return () => {
    void sub.then((s) => s.remove());
  };
}

/** Prefer Sync Pack; fall back to standard Salesforce REST for any org. */
export async function createLiveSyncEngine(
  db: SqlExecutor,
  tokens: TokenSet
): Promise<{ engine: SyncEngine; mode: 'sync-pack' | 'rest-fallback' | 'mock' }> {
  if (!tokens.accessToken || tokens.accessToken === 'pending') {
    return { engine: new SyncEngine(db, createMockSyncClient()), mode: 'mock' };
  }
  const sf = createSfClient(tokens);
  try {
    const hello = await sf.get<{ ok?: boolean }>(OSR_API.hello);
    if (hello?.ok) {
      return { engine: new SyncEngine(db, sf), mode: 'sync-pack' };
    }
  } catch {
    /* Sync Pack not installed in this org */
  }
  return {
    engine: new SyncEngine(db, createRestFallbackClient(tokens)),
    mode: 'rest-fallback'
  };
}

/**
 * Implements Sync Pack-shaped responses using standard Salesforce REST + UI APIs
 * so any org works offline after login (without Sync Pack deploy).
 */
export function createRestFallbackClient(tokens: TokenSet): SyncHttpClient {
  const api = `v${(import.meta.env.VITE_SF_API_VERSION as string) || '61.0'}`;
  const baseClient = createSfClient(tokens);
  const instance = tokens.instanceUrl.replace(/\/$/, '');

  /** Cached discovery for this client instance (one sync session). */
  let discovered: {
    objects: string[];
    apps: { developerName: string; label: string; tabDeveloperNames: string[]; iconUrl?: string }[];
  } | null = null;

  async function sfGet<T>(path: string): Promise<T> {
    const full = path.startsWith('/services') ? path : `/services/data/${api}${path}`;
    if (Capacitor.isNativePlatform()) {
      const res = await CapacitorHttp.get({
        url: `${instance}${full}`,
        headers: {
          Authorization: `Bearer ${tokens.accessToken}`,
          Accept: 'application/json'
        }
      });
      if (res.status < 200 || res.status >= 300) {
        throw new Error(`SF GET ${full} → ${res.status}`);
      }
      return (typeof res.data === 'string' ? JSON.parse(res.data) : res.data) as T;
    }
    return baseClient.get<T>(full);
  }
  async function sfPost<T>(path: string, body: unknown): Promise<T> {
    const full = path.startsWith('/services') ? path : `/services/data/${api}${path}`;
    if (Capacitor.isNativePlatform()) {
      const res = await CapacitorHttp.post({
        url: `${instance}${full}`,
        headers: {
          Authorization: `Bearer ${tokens.accessToken}`,
          'Content-Type': 'application/json',
          Accept: 'application/json'
        },
        data: body as Record<string, unknown>
      });
      if (res.status < 200 || res.status >= 300) {
        throw new Error(`SF POST ${full} → ${res.status}`);
      }
      return (typeof res.data === 'string' ? JSON.parse(res.data) : res.data) as T;
    }
    return baseClient.post<T>(full, body);
  }

  const FALLBACK_STD = [
    'Account',
    'Contact',
    'Opportunity',
    'Lead',
    'Task',
    'Event',
    'Case',
    'User'
  ];

  async function discoverOrgShape() {
    if (discovered) return discovered;

    const objects: string[] = [];
    const prefer = new Set(FALLBACK_STD);

    try {
      const catalog = await sfGet<{
        sobjects: {
          name: string;
          label: string;
          queryable: boolean;
          createable: boolean;
          custom: boolean;
          deprecatedAndHidden?: boolean;
        }[];
      }>('/sobjects');
      const queryable = (catalog.sobjects ?? []).filter(
        (s) => s.queryable && !s.deprecatedAndHidden && s.name !== 'User'
      );
      // Prefer common CRM standards the user can query
      for (const name of FALLBACK_STD) {
        if (queryable.some((s) => s.name === name) && name !== 'User') objects.push(name);
      }
      // Add a handful of custom objects (any org) — never require Visit__c
      for (const s of queryable) {
        if (!s.custom) continue;
        if (objects.includes(s.name)) continue;
        if (s.name.endsWith('__Share') || s.name.endsWith('__History') || s.name.endsWith('__Feed')) {
          continue;
        }
        objects.push(s.name);
        if (objects.length >= 14) break;
      }
      // Fill with remaining standards if still thin
      for (const s of queryable) {
        if (s.custom || objects.includes(s.name)) continue;
        if (!prefer.has(s.name) && objects.length >= 12) continue;
        if (!objects.includes(s.name)) objects.push(s.name);
        if (objects.length >= 16) break;
      }
    } catch {
      objects.push(...FALLBACK_STD.filter((n) => n !== 'User'));
    }

    if (!objects.length) objects.push('Account', 'Contact', 'Task');

    type AppShape = {
      developerName: string;
      label: string;
      tabDeveloperNames: string[];
      iconUrl?: string;
    };
    const apps: AppShape[] = [];

    // App Switcher menu — available on most orgs without Sync Pack
    try {
      const menu = await sfGet<{
        appMenuItems?: {
          type?: string;
          name?: string;
          label?: string;
          icons?: { url?: string; contentType?: string; height?: number; width?: number }[];
        }[];
      }>('/appMenu/AppSwitcher');
      for (const item of menu.appMenuItems ?? []) {
        if (!item.name || !item.label) continue;
        const t = (item.type ?? '').toLowerCase();
        if (t && t !== 'tabset' && t !== 'network' && !t.includes('app')) {
          // still allow TabSet-like entries; skip pure external links when typed
          if (t === 'external' || t === 'node') continue;
        }
        apps.push({
          developerName: item.name,
          label: item.label,
          tabDeveloperNames: [...objects],
          iconUrl: item.icons?.[0]?.url
        });
        if (apps.length >= 40) break;
      }
    } catch {
      /* AppSwitcher may be restricted */
    }

    if (!apps.length) {
      apps.push({
        developerName: 'Offline',
        label: 'Offline',
        tabDeveloperNames: [...objects]
      });
    }

    discovered = { objects, apps };
    return discovered;
  }

  return {
    async get<T = unknown>(path: string): Promise<T> {
      if (path.includes('/hello')) {
        try {
          const u = await sfGet<{ user_id: string; organization_id: string }>(
            '/services/oauth2/userinfo'
          );
          return {
            ok: true,
            orgId: u.organization_id,
            userId: u.user_id,
            message: 'REST fallback (Sync Pack not installed in this org)'
          } as T;
        } catch {
          return {
            ok: true,
            message: 'REST fallback'
          } as T;
        }
      }
      if (path.includes('/profile')) {
        const shape = await discoverOrgShape();
        return {
          name: 'Rest_Fallback_Profile',
          objects: shape.objects.map((apiName) => ({
            apiName,
            fields:
              apiName === 'Task' || apiName === 'Event'
                ? ['Id', 'Subject', 'Status', 'ActivityDate', 'StartDateTime', 'WhatId', 'SystemModstamp']
                : apiName === 'Visit__c'
                  ? ['Id', 'Name', 'Account__c', 'Status__c', 'Planned_Date__c', 'SystemModstamp']
                  : ['Id', 'Name', 'SystemModstamp'],
            soqlFilter:
              apiName === 'Visit__c'
                ? 'Planned_Date__c = LAST_N_DAYS:60 OR Planned_Date__c = NEXT_N_DAYS:30 OR Planned_Date__c = TODAY'
                : undefined
          })),
          flexiPages: ['Offline_Home', 'Field_Rep_Home'],
          tabs: shape.objects,
          apps: shape.apps.map((a) => a.developerName),
          lwcBundles: [
            'c/fieldRepHomeTodayPlan',
            'c/fieldRepHomeMetrics',
            'c/fieldRepHomeNextBestCustomer',
            'c/fieldRepHomeClmPrefetch',
            'c/homeOfficeMessages',
            'c/repLocationPublisher',
            'c/reportsHub'
          ],
          fileScopes: []
        } as T;
      }
      if (path.includes('/prefs')) {
        // Without Sync Pack, prefs stay local-only
        return { ok: true, prefs: [], error: 'prefs require Sync Pack' } as T;
      }
      return sfGet(path);
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
          prefs: [
            {
              objectApi: b.objectApi,
              favourites: b.favourites ?? [],
              pinnedListViewId: b.pinnedListViewId ?? null,
              calendarField: b.calendarField ?? null
            }
          ],
          error: 'prefs require Sync Pack — cached locally only'
        } as T;
      }
      if (path.includes('/metadata')) {
        const req = body as { objects?: string[] };
        const shape = await discoverOrgShape();
        const objects = req.objects?.length ? req.objects : shape.objects;
        // Include tab objects from discovered apps
        const objectSet = new Set(objects);
        for (const a of shape.apps) {
          for (const t of a.tabDeveloperNames ?? []) {
            const name = t.replace(/^standard-/, '');
            if (name && !name.startsWith('tab_')) objectSet.add(name);
          }
        }
        for (const n of shape.objects) objectSet.add(n);
        const objectPayloads = [];
        const layouts = [];
        const tabs = [];
        let sort = 1;
        for (const apiName of objectSet) {
          try {
            const d = await sfGet<{
              name: string;
              label: string;
              labelPlural?: string;
              keyPrefix?: string;
              createable?: boolean;
              updateable?: boolean;
              fields: {
                name: string;
                label: string;
                type: string;
                nillable: boolean;
                createable: boolean;
                updateable?: boolean;
                picklistValues?: {
                  value: string;
                  label: string;
                  active: boolean;
                  defaultValue: boolean;
                }[];
                referenceTo?: string[];
              }[];
            }>(`/sobjects/${apiName}/describe`);
            const systemNames = new Set([
              'CreatedDate',
              'CreatedById',
              'LastModifiedDate',
              'LastModifiedById',
              'SystemModstamp',
              'LastActivityDate',
              'LastViewedDate',
              'LastReferencedDate',
              'OwnerId'
            ]);
            objectPayloads.push({
              apiName,
              label: d.label,
              keyPrefix: d.keyPrefix,
              describe: {
                name: d.name,
                label: d.label,
                labelPlural: d.labelPlural,
                keyPrefix: d.keyPrefix,
                createable: d.createable,
                updateable: d.updateable,
                fields: d.fields.map((f) => ({
                  name: f.name,
                  label: f.label,
                  type: f.type,
                  required: !f.nillable && f.createable,
                  nillable: f.nillable,
                  createable: f.createable,
                  updateable: f.updateable ?? false,
                  picklistValues: f.picklistValues ?? [],
                  referenceTo: f.referenceTo ?? []
                }))
              }
            });
            const infoFields = d.fields
              .filter(
                (f) =>
                  !['Id', 'IsDeleted'].includes(f.name) && !systemNames.has(f.name)
              )
              .map((f) => ({ field: f.name }));
            const systemFields = d.fields
              .filter((f) => systemNames.has(f.name))
              .map((f) => ({ field: f.name }));
            const sections = [
              { label: 'Information', columns: [infoFields] },
              ...(systemFields.length
                ? [{ label: 'System Information', columns: [systemFields] }]
                : [])
            ];
            layouts.push({
              id: `layout_${apiName}`,
              objectApi: apiName,
              name: `${d.label} Layout`,
              layout: { sections }
            });
            tabs.push({
              id: `tab_${apiName}`,
              developerName: apiName,
              label: d.labelPlural || d.label,
              sortOrder: sort++,
              tab: { objectApi: apiName }
            });
          } catch {
            /* skip inaccessible objects */
          }
        }
        const tabNames = tabs.map((t) => t.developerName);
        const apps = shape.apps.map((a, i) => ({
          id: `app_${a.developerName}_${i}`,
          developerName: a.developerName,
          label: a.label,
          app: {
            tabDeveloperNames: a.tabDeveloperNames?.length ? a.tabDeveloperNames : tabNames,
            homeFlexiPageDeveloperName: 'Offline_Home',
            iconUrl: a.iconUrl ?? null,
            source: 'rest-fallback'
          }
        }));

        // Salesforce list views (catalog + optional member IDs for offline filter)
        const listViews: {
          id: string;
          objectApi: string;
          developerName: string;
          label: string;
          listview: Record<string, unknown>;
        }[] = [];
        for (const apiName of objectSet) {
          try {
            const lvRes = await sfGet<{
              listviews?: {
                id: string;
                developerName: string;
                label: string;
                soqlCompatible?: boolean;
              }[];
            }>(`/sobjects/${apiName}/listviews`);
            let fetched = 0;
            for (const lv of lvRes.listviews ?? []) {
              if (!lv.id || !lv.developerName) continue;
              const entry: {
                id: string;
                objectApi: string;
                developerName: string;
                label: string;
                listview: Record<string, unknown>;
              } = {
                id: lv.id,
                objectApi: apiName,
                developerName: lv.developerName,
                label: lv.label || lv.developerName,
                listview: {
                  id: lv.id,
                  developerName: lv.developerName,
                  label: lv.label || lv.developerName,
                  soqlCompatible: lv.soqlCompatible !== false
                }
              };
              // Pull member IDs for a few views so offline filters work without SOQL
              if (fetched < 6 && lv.soqlCompatible !== false) {
                try {
                  const results = await sfGet<{
                    records?: { Id?: string; id?: string }[];
                  }>(`/sobjects/${apiName}/listviews/${lv.id}/results?limit=200`);
                  const ids = (results.records ?? [])
                    .map((r) => String(r.Id ?? r.id ?? ''))
                    .filter(Boolean);
                  if (ids.length) entry.listview.recordIds = ids;
                  fetched++;
                } catch {
                  /* results optional */
                }
              }
              listViews.push(entry);
              if (listViews.filter((x) => x.objectApi === apiName).length >= 12) break;
            }
          } catch {
            /* object may not expose listviews */
          }
        }

        return {
          cursor: nowIso(),
          objects: objectPayloads,
          layouts,
          flexiPages: [
            {
              id: 'fp_offline_home',
              developerName: 'Offline_Home',
              type: 'HomePage',
              page: {
                type: 'HomePage',
                regions: [
                  {
                    name: 'main',
                    components: [
                      {
                        type: 'c/fieldRepHomeTodayPlan',
                        attributes: { label: "Today's Plan" }
                      },
                      {
                        type: 'c/fieldRepHomeMetrics',
                        attributes: { label: 'Metrics' }
                      },
                      {
                        type: 'c/fieldRepHomeNextBestCustomer',
                        attributes: { label: 'Next Best Customer' }
                      },
                      {
                        type: 'osr:quickLinks',
                        attributes: { label: 'Quick Links' }
                      }
                    ]
                  }
                ]
              }
            }
          ],
          tabs,
          apps,
          validationRules: [],
          listViews
        } as T;
      }
      if (path.includes('/sharing')) {
        const req = body as { objects?: string[] };
        const shape = await discoverOrgShape();
        const sets = [];
        for (const apiName of req.objects ?? shape.objects) {
          try {
            const q = await sfGet<{ records: { Id: string }[] }>(
              `/query?q=${encodeURIComponent(`SELECT Id FROM ${apiName} LIMIT 500`)}`
            );
            sets.push({ objectApi: apiName, ids: q.records.map((r) => r.Id) });
          } catch {
            sets.push({ objectApi: apiName, ids: [] });
          }
        }
        return { sets } as T;
      }
      if (path.includes('/data')) {
        const req = body as {
          objectApi: string;
          fields?: string[];
          filter?: string;
          pageSize?: number;
        };
        const fields = req.fields?.length ? req.fields : ['Id', 'Name', 'SystemModstamp'];
        const fieldList = Array.from(new Set(['Id', ...fields, 'SystemModstamp']));
        const limit = Math.min(req.pageSize ?? 500, 500);
        const where = req.filter ? ` WHERE (${req.filter})` : '';
        try {
          const soql = `SELECT ${fieldList.join(',')} FROM ${req.objectApi}${where} ORDER BY SystemModstamp DESC LIMIT ${limit}`;
          const q = await sfGet<{ records: Record<string, unknown>[] }>(
            `/query?q=${encodeURIComponent(soql)}`
          );
          return { records: q.records, deletedIds: [], nextCursor: null, done: true } as T;
        } catch {
          // Some objects use Subject instead of Name (Task/Event)
          try {
            const alt = `SELECT Id, Subject, Status, ActivityDate, SystemModstamp FROM ${req.objectApi} ORDER BY SystemModstamp DESC LIMIT ${limit}`;
            const q = await sfGet<{ records: Record<string, unknown>[] }>(
              `/query?q=${encodeURIComponent(alt)}`
            );
            return { records: q.records, deletedIds: [], nextCursor: null, done: true } as T;
          } catch {
            try {
              const bare = `SELECT Id, SystemModstamp FROM ${req.objectApi} ORDER BY SystemModstamp DESC LIMIT ${limit}`;
              const q = await sfGet<{ records: Record<string, unknown>[] }>(
                `/query?q=${encodeURIComponent(bare)}`
              );
              return { records: q.records, deletedIds: [], nextCursor: null, done: true } as T;
            } catch {
              return { records: [], deletedIds: [], nextCursor: null, done: true } as T;
            }
          }
        }
      }
      if (path.includes('/files')) {
        try {
          const q = await sfGet<{
            records: {
              Id: string;
              ContentDocumentId: string;
              Title: string;
              ContentSize: number;
              FileType: string;
              Checksum?: string;
            }[];
          }>(
            `/query?q=${encodeURIComponent(
              'SELECT Id, ContentDocumentId, Title, ContentSize, FileType, Checksum FROM ContentVersion WHERE IsLatest = true ORDER BY SystemModstamp DESC LIMIT 30'
            )}`
          );
          return {
            cursor: nowIso(),
            files: q.records.map((cv) => ({
              contentVersionId: cv.Id,
              contentDocumentId: cv.ContentDocumentId,
              title: cv.Title,
              path: `${instance}/services/data/${api}/sobjects/ContentVersion/${cv.Id}/VersionData`,
              size: cv.ContentSize,
              mimeType: cv.FileType,
              hash: cv.Checksum,
              downloadUrl: `${instance}/services/data/${api}/sobjects/ContentVersion/${cv.Id}/VersionData`
            }))
          } as T;
        } catch {
          return { cursor: nowIso(), files: [] } as T;
        }
      }
      if (path.includes('/lwc')) {
        return { bundles: [] } as T;
      }
      if (path.includes('/apex-cache')) {
        const req = (body ?? {}) as {
          weekStart?: string;
          weekEnd?: string;
          planDate?: string;
          contextUserId?: string;
        };
        const entries = await buildRestApexCacheEntries(sfGet, req);
        return { ok: true, entries } as T;
      }
      if (path.includes('/outbox')) {
        const req = body as {
          actions: {
            clientId: string;
            op: string;
            objectApi?: string;
            recordId?: string;
            payload?: Record<string, unknown>;
          }[];
        };
        const results = [];
        for (const a of req.actions ?? []) {
          try {
            if (!a.objectApi) {
              results.push({ clientId: a.clientId, status: 'failed', error: 'No objectApi' });
              continue;
            }
            const payload = { ...(a.payload ?? {}) };
            delete payload.Id;
            for (const k of Object.keys(payload)) {
              if (k.startsWith('_')) delete payload[k];
            }
            if (a.op === 'create' || (a.recordId && String(a.recordId).startsWith('local_'))) {
              const created = await sfPost<{ id: string }>(`/sobjects/${a.objectApi}`, payload);
              results.push({ clientId: a.clientId, status: 'synced', serverId: created.id });
            } else if (a.op === 'delete' && a.recordId) {
              if (Capacitor.isNativePlatform()) {
                await CapacitorHttp.delete({
                  url: `${instance}/services/data/${api}/sobjects/${a.objectApi}/${a.recordId}`,
                  headers: { Authorization: `Bearer ${tokens.accessToken}` }
                });
              } else {
                await fetch(`${instance}/services/data/${api}/sobjects/${a.objectApi}/${a.recordId}`, {
                  method: 'DELETE',
                  headers: { Authorization: `Bearer ${tokens.accessToken}` }
                });
              }
              results.push({ clientId: a.clientId, status: 'synced' });
            } else if (a.recordId) {
              if (Capacitor.isNativePlatform()) {
                await CapacitorHttp.request({
                  method: 'PATCH',
                  url: `${instance}/services/data/${api}/sobjects/${a.objectApi}/${a.recordId}`,
                  headers: {
                    Authorization: `Bearer ${tokens.accessToken}`,
                    'Content-Type': 'application/json'
                  },
                  data: payload
                });
              } else {
                await fetch(`${instance}/services/data/${api}/sobjects/${a.objectApi}/${a.recordId}`, {
                  method: 'PATCH',
                  headers: {
                    Authorization: `Bearer ${tokens.accessToken}`,
                    'Content-Type': 'application/json'
                  },
                  body: JSON.stringify(payload)
                });
              }
              results.push({ clientId: a.clientId, status: 'synced', serverId: a.recordId });
            } else {
              results.push({ clientId: a.clientId, status: 'synced' });
            }
          } catch (e) {
            results.push({
              clientId: a.clientId,
              status: 'failed',
              error: e instanceof Error ? e.message : String(e)
            });
          }
        }
        return { results } as T;
      }
      return sfPost(path, body);
    }
  };
}

type SfGet = <T>(path: string) => Promise<T>;

async function soqlQuery<T extends Record<string, unknown>>(
  sfGet: SfGet,
  soql: string
): Promise<T[]> {
  try {
    const q = await sfGet<{ records?: T[] }>(`/query?q=${encodeURIComponent(soql)}`);
    return q.records ?? [];
  } catch {
    return [];
  }
}

function localDateIso(d = new Date()): string {
  const y = d.getFullYear();
  const m = String(d.getMonth() + 1).padStart(2, '0');
  const day = String(d.getDate()).padStart(2, '0');
  return `${y}-${m}-${day}`;
}

function addDaysIso(iso: string, n: number): string {
  const [y, m, d] = iso.split('-').map(Number);
  const dt = new Date(y, m - 1, d + n);
  return localDateIso(dt);
}

function startOfSundayIso(iso?: string): string {
  const base = iso ? new Date(iso + 'T12:00:00') : new Date();
  const x = new Date(base.getFullYear(), base.getMonth(), base.getDate());
  x.setDate(x.getDate() - x.getDay());
  return localDateIso(x);
}

/** Build Sync Pack–shaped apex-cache entries from standard REST SOQL (no Sync Pack). */
async function buildRestApexCacheEntries(
  sfGet: SfGet,
  req: { weekStart?: string; weekEnd?: string; planDate?: string; contextUserId?: string }
): Promise<{ key: string; fetchedAt: string; payload: unknown }[]> {
  const now = nowIso();
  const planDate = req.planDate || localDateIso();
  const weekStart = req.weekStart || startOfSundayIso(planDate);
  const weekEnd = req.weekEnd || addDaysIso(weekStart, 6);

  type AccRec = {
    Id: string;
    Name?: string;
    BillingCity?: string;
    ShippingCity?: string;
    BillingLatitude?: number | null;
    BillingLongitude?: number | null;
    ShippingLatitude?: number | null;
    ShippingLongitude?: number | null;
    Specialty__c?: string;
    Calculated_Classification__c?: string;
    Classification__c?: string;
    RecordType?: { Name?: string; DeveloperName?: string };
  };

  let accounts = await soqlQuery<AccRec>(
    sfGet,
    `SELECT Id, Name, BillingCity, ShippingCity, BillingLatitude, BillingLongitude,
      ShippingLatitude, ShippingLongitude, RecordType.Name, RecordType.DeveloperName
     FROM Account ORDER BY LastModifiedDate DESC LIMIT 200`
  );
  // Retry with optional custom fields if first query worked but we want richer data
  const rich = await soqlQuery<AccRec>(
    sfGet,
    `SELECT Id, Name, BillingCity, ShippingCity, BillingLatitude, BillingLongitude,
      ShippingLatitude, ShippingLongitude, Specialty__c, Calculated_Classification__c,
      Classification__c, RecordType.Name, RecordType.DeveloperName
     FROM Account ORDER BY LastModifiedDate DESC LIMIT 200`
  );
  if (rich.length) accounts = rich;

  const accountDtos = accounts.map((a) => ({
    id: a.Id,
    name: a.Name || 'Account',
    specialty: a.Specialty__c || undefined,
    specialtyApiValue: a.Specialty__c || undefined,
    city: a.BillingCity || a.ShippingCity || undefined,
    latitude: a.BillingLatitude ?? a.ShippingLatitude ?? null,
    longitude: a.BillingLongitude ?? a.ShippingLongitude ?? null,
    recordTypeName: a.RecordType?.Name,
    recordTypeDeveloperName: a.RecordType?.DeveloperName,
    classification: a.Calculated_Classification__c || a.Classification__c || undefined,
    targetVisits: 0,
    actualVisits: 0
  }));

  type VisitRec = {
    Id: string;
    Name?: string;
    Account__c?: string;
    Status__c?: string;
    Planned_Date__c?: string;
    StartDateTime__c?: string;
    EndDateTime__c?: string;
    Account__r?: {
      Name?: string;
      Specialty__c?: string;
      BillingLatitude?: number | null;
      BillingLongitude?: number | null;
      ShippingLatitude?: number | null;
      ShippingLongitude?: number | null;
      RecordType?: { Name?: string; DeveloperName?: string };
    };
  };

  let visits = await soqlQuery<VisitRec>(
    sfGet,
    `SELECT Id, Name, Account__c, Status__c, Planned_Date__c, StartDateTime__c, EndDateTime__c,
      Account__r.Name, Account__r.BillingLatitude, Account__r.BillingLongitude,
      Account__r.ShippingLatitude, Account__r.ShippingLongitude,
      Account__r.RecordType.Name, Account__r.RecordType.DeveloperName
     FROM Visit__c
     WHERE Planned_Date__c >= ${weekStart} AND Planned_Date__c <= ${weekEnd}
     ORDER BY Planned_Date__c ASC, StartDateTime__c ASC NULLS LAST
     LIMIT 200`
  );
  if (!visits.length) {
    visits = await soqlQuery<VisitRec>(
      sfGet,
      `SELECT Id, Name, Account__c, Status__c, StartDateTime__c, EndDateTime__c,
        Account__r.Name, Account__r.BillingLatitude, Account__r.BillingLongitude,
        Account__r.ShippingLatitude, Account__r.ShippingLongitude,
        Account__r.RecordType.Name, Account__r.RecordType.DeveloperName
       FROM Visit__c
       WHERE StartDateTime__c >= ${weekStart}T00:00:00.000Z
         AND StartDateTime__c <= ${weekEnd}T23:59:59.000Z
       ORDER BY StartDateTime__c ASC
       LIMIT 200`
    );
  }

  const toVisitDto = (v: VisitRec) => {
    const start =
      v.StartDateTime__c ||
      (v.Planned_Date__c ? `${v.Planned_Date__c}T09:00:00.000Z` : undefined);
    const end =
      v.EndDateTime__c ||
      (v.Planned_Date__c ? `${v.Planned_Date__c}T10:00:00.000Z` : undefined);
    const acct = accounts.find((a) => a.Id === v.Account__c);
    return {
      id: v.Id,
      name: v.Name,
      accountId: v.Account__c,
      accountName: v.Account__r?.Name || acct?.Name || 'Account',
      status: v.Status__c || 'Draft',
      startDateTime: start,
      endDateTime: end,
      accountSpecialty: (v.Account__r as { Specialty__c?: string } | undefined)?.Specialty__c,
      accountRecordTypeName: v.Account__r?.RecordType?.Name || acct?.RecordType?.Name,
      accountRecordTypeDeveloperName:
        v.Account__r?.RecordType?.DeveloperName || acct?.RecordType?.DeveloperName,
      accountLatitude:
        v.Account__r?.BillingLatitude ??
        v.Account__r?.ShippingLatitude ??
        acct?.BillingLatitude ??
        acct?.ShippingLatitude ??
        null,
      accountLongitude:
        v.Account__r?.BillingLongitude ??
        v.Account__r?.ShippingLongitude ??
        acct?.BillingLongitude ??
        acct?.ShippingLongitude ??
        null
    };
  };

  const weekVisits = visits.map(toVisitDto);
  const todayVisits = weekVisits.filter((v) => {
    const key = String(v.startDateTime ?? '').slice(0, 10);
    return key === planDate || String(v.startDateTime ?? '').includes(planDate);
  });

  // Viewer context: admin can switch across active users (REST heuristic when Sync Pack absent)
  let userInfo: { user_id?: string; organization_id?: string } = {};
  try {
    userInfo = await sfGet('/services/oauth2/userinfo');
  } catch {
    /* ignore */
  }
  const defaultUserId = req.contextUserId || userInfo.user_id || '';
  let canSwitchView = false;
  let viewerMode: 'self' | 'admin' = 'self';
  const viewerOptions: { userId: string; label: string; userName: string }[] = [];
  try {
    const me = await soqlQuery<{ Id: string; Profile?: { Name?: string } }>(
      sfGet,
      `SELECT Id, Profile.Name FROM User WHERE Id = '${defaultUserId || userInfo.user_id}' LIMIT 1`
    );
    const profileName = String(me[0]?.Profile?.Name ?? '').toLowerCase();
    if (profileName.includes('admin') || profileName.includes('system administrator')) {
      canSwitchView = true;
      viewerMode = 'admin';
      const users = await soqlQuery<{ Id: string; Name?: string }>(
        sfGet,
        `SELECT Id, Name FROM User WHERE IsActive = true AND Id != '${me[0]?.Id ?? ''}' ORDER BY Name LIMIT 40`
      );
      for (const u of users) {
        viewerOptions.push({
          userId: u.Id,
          userName: u.Name || u.Id,
          label: u.Name || u.Id
        });
      }
    }
  } catch {
    /* ignore */
  }

  const nbc = accountDtos.slice(0, 5).map((a, i) => ({
    rank: i + 1,
    accountId: a.id,
    accountName: a.name,
    specialty: a.specialty,
    actualVisits: 0,
    targetVisits: 1,
    visitGap: 1,
    planned: false,
    plannedToday: false,
    score: 90 - i * 5,
    calculatedClassification: a.classification
  }));

  return [
    {
      key: 'todayPlan',
      fetchedAt: now,
      payload: { visits: todayVisits, timeOffBlocks: [] }
    },
    {
      key: 'plannerWeek',
      fetchedAt: now,
      payload: { visits: weekVisits, timeOffBlocks: [] }
    },
    {
      key: 'plannerAccounts',
      fetchedAt: now,
      payload: {
        accounts: accountDtos,
        totalCount: accountDtos.length,
        hasMore: accountDtos.length >= 200
      }
    },
    {
      key: 'plannerViewer',
      fetchedAt: now,
      payload: {
        viewerMode,
        canSwitchView,
        defaultUserId: userInfo.user_id || defaultUserId,
        options: viewerOptions
      }
    },
    {
      key: 'homeMetrics',
      fetchedAt: now,
      payload: {
        visitCoveragePercent: 0,
        customerCoveragePercent: 0,
        lfPercentTotal: 0,
        rfPercentTotal: 0,
        mfPercentTotal: 0,
        byClassification: []
      }
    },
    {
      key: 'nextBestCustomers',
      fetchedAt: now,
      payload: nbc
    },
    {
      key: 'accountCoverage',
      fetchedAt: now,
      payload: accountDtos.slice(0, 50).map((a) => ({
        accountId: a.id,
        accountName: a.name,
        specialty: a.specialty,
        city: a.city,
        calculatedClassification: a.classification,
        actualVisits: 0,
        targetVisits: 0,
        visitGap: 0,
        reachPercent: 0,
        frequencyStatus: '—',
        isVisited: false
      }))
    },
    {
      key: 'gamification',
      fetchedAt: now,
      payload: {
        userFirstName: 'Rep',
        streaks: { activityStreak: 0, coverageStreak: 0 },
        badges: []
      }
    },
    {
      key: 'rankings',
      fetchedAt: now,
      payload: null
    },
    {
      key: 'officeMessages',
      fetchedAt: now,
      payload: []
    },
    {
      key: 'clmManifest',
      fetchedAt: now,
      payload: { presentations: [], ratingLayoutJson: null }
    }
  ];
}

export { loadTokens, saveTokens, type TokenSet };
