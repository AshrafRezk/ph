import type { SqlExecutor } from '@osr/db';
import {
  getRecord,
  listRecords,
  relatedRecords,
  getObjectDescribe,
  getLayoutsForObject,
  getValidationRules,
  getFlexiPage,
  listTabs,
  listApps,
  getApp,
  findFlexiPageForObject,
  listFlexiPages,
  getFile,
  getLwcBundle,
  listOpenConflicts,
  resolveConflict,
  upsertRecord,
  enqueueOutbox,
  listActionsForObject,
  getCompactLayoutForObject,
  type ActionRow
} from '@osr/db';
import { FormulaEvaluator, validateRecord, type ValidationResult } from '@osr/validation';
import { localSaveRecord, localDeleteRecord } from '@osr/sync';

import {
  formFactorFromWidth,
  selectRegionsForFormFactor,
  type FormFactor,
  type FlexiTemplate
} from './form-factor.js';
import {
  FIELD_HOME_BUNDLE_PRIORITY,
  isFieldHomeLayout,
  homeBundlePriority,
  sortFieldHomeComponents,
  planFieldHomeRegions,
  type HomeRegionPlan,
  type HomeFlexiComponent
} from './field-home-layout.js';
import {
  applyListFilters,
  filtersFullySupported,
  listColumnFieldNames,
  evalFilterClause,
  type ListFilterClause
} from './list-filters.js';
import {
  parseLayout,
  resolveFieldSectionFields,
  isFieldReadonly,
  isFieldRequired,
  type ParsedLayout,
  type FieldInstance,
  type LayoutFieldRef,
  type RelatedListMeta,
  type FieldBehavior
} from './layout-model.js';
import {
  isOfflineSafeAction,
  classifyActionKind,
  type OfflineAction
} from './actions.js';

export {
  formFactorFromWidth,
  selectRegionsForFormFactor,
  type FormFactor,
  type FlexiTemplate
};
export {
  FIELD_HOME_BUNDLE_PRIORITY,
  isFieldHomeLayout,
  homeBundlePriority,
  sortFieldHomeComponents,
  planFieldHomeRegions,
  type HomeRegionPlan,
  type HomeFlexiComponent
};
export {
  applyListFilters,
  filtersFullySupported,
  listColumnFieldNames,
  evalFilterClause,
  type ListFilterClause
};
export {
  parseLayout,
  resolveFieldSectionFields,
  isFieldReadonly,
  isFieldRequired,
  type ParsedLayout,
  type FieldInstance,
  type LayoutFieldRef,
  type RelatedListMeta,
  type FieldBehavior
};
export {
  isOfflineSafeAction,
  classifyActionKind,
  type OfflineAction
};

/** Local wire adapters — Tier A LDS stand-ins */
export class LocalWireAdapters {
  constructor(private db: SqlExecutor) {}

  async getRecord(objectApi: string, recordId: string) {
    return getRecord(this.db, objectApi, recordId);
  }

  async getList(objectApi: string, limit = 200) {
    return listRecords(this.db, objectApi, limit);
  }

  async getRelated(childObject: string, lookupField: string, parentId: string) {
    return relatedRecords(this.db, childObject, lookupField, parentId);
  }

  async getObjectInfo(objectApi: string) {
    return getObjectDescribe(this.db, objectApi);
  }

  async getLayout(objectApi: string, recordTypeId?: string | null) {
    const layouts = await getLayoutsForObject(this.db, objectApi, recordTypeId);
    return layouts[0] ?? null;
  }
}

export interface LayoutField {
  field: string;
  behavior?: string;
}

export interface LayoutSection {
  label: string;
  columns: LayoutField[][];
}

export interface LayoutModel {
  sections: LayoutSection[];
  relatedLists?: RelatedListMeta[];
  highlightsFields?: string[];
  platformActionList?: string[];
  pathField?: string | null;
  pathValues?: string[];
  source?: string;
}

export interface FlexiVisibilityRule {
  criteria?: string | null;
  booleanFilter?: string | null;
}

export interface FlexiComponent {
  type: string;
  name?: string;
  fqn?: string;
  attributes?: Record<string, unknown>;
  visibilityRule?: FlexiVisibilityRule | null;
  fieldInstances?: FieldInstance[];
}

export interface FlexiRegion {
  name: string;
  formFactor?: string | null;
  components: FlexiComponent[];
}

export interface FlexiPageModel {
  type?: string;
  sobjectType?: string | null;
  masterLabel?: string;
  source?: string;
  formFactor?: string | null;
  templates?: FlexiTemplate[];
  regions: FlexiRegion[];
}

function parseFieldInstances(raw: unknown): FieldInstance[] | undefined {
  if (!Array.isArray(raw) || !raw.length) return undefined;
  return raw
    .map((fi) => {
      if (!fi || typeof fi !== 'object') return null;
      const o = fi as Record<string, unknown>;
      const fieldApiName = String(
        o.fieldApiName ?? o.fieldItem ?? o.field ?? o.name ?? ''
      );
      if (!fieldApiName) return null;
      return {
        fieldApiName,
        uiBehavior: (o.uiBehavior as string | undefined) ?? (o.behavior as string | undefined),
        label: o.label as string | undefined
      } as FieldInstance;
    })
    .filter(Boolean) as FieldInstance[];
}

export function parseFlexiPage(raw: Record<string, unknown> | null | undefined): FlexiPageModel | null {
  if (!raw) return null;
  const regionsRaw = (raw.regions as FlexiRegion[] | undefined) ?? [];
  const regions: FlexiRegion[] = regionsRaw.map((r) => ({
    name: r.name || 'main',
    formFactor: r.formFactor ?? null,
    components: ((r.components as FlexiComponent[]) ?? []).map((c) => {
      const attrs = (c.attributes as Record<string, unknown>) ?? {};
      const fieldInstances =
        parseFieldInstances(c.fieldInstances) ??
        parseFieldInstances(attrs.fieldInstances) ??
        parseFieldInstances(attrs.fields);
      const vis =
        c.visibilityRule ??
        (attrs.visibilityRule as FlexiVisibilityRule | undefined) ??
        null;
      return {
        type: c.type || (c.fqn as string) || 'unknown',
        name: c.name,
        fqn: c.fqn,
        attributes: attrs,
        visibilityRule: vis,
        fieldInstances
      };
    })
  }));
  return {
    type: raw.type as string | undefined,
    sobjectType: (raw.sobjectType as string | null | undefined) ?? null,
    masterLabel: raw.masterLabel as string | undefined,
    source: raw.source as string | undefined,
    formFactor: (raw.formFactor as string | null | undefined) ?? null,
    templates: (raw.templates as FlexiTemplate[] | undefined) ?? undefined,
    regions
  };
}

/** Evaluate component visibility formula against record. Fail-open on errors. */
export function isComponentVisible(
  rule: FlexiVisibilityRule | null | undefined,
  record: Record<string, unknown> | null | undefined
): boolean {
  const criteria = rule?.criteria;
  if (!criteria || !String(criteria).trim()) return true;
  try {
    const ev = new FormulaEvaluator();
    const result = ev.evaluate(String(criteria), {
      ...(record ?? {}),
      $User: { Id: 'offline' }
    });
    if (result.warnings?.length) {
      /* unsupported subset — fail open */
    }
    return Boolean(result.value);
  } catch {
    return true;
  }
}

/** True for custom LWCs: `c/foo`, `c:foo`, `lwc:foo`, or `namespace:foo` (non-platform). */
export function isCustomLwcType(type: string): boolean {
  if (!type) return false;
  if (type === 'lwc' || type.startsWith('lwc:') || type.startsWith('c/') || type.startsWith('c:')) {
    return true;
  }
  // Tooling uses namespace:componentName — exclude platform prefixes
  const colon = type.indexOf(':');
  if (colon > 0) {
    const ns = type.slice(0, colon).toLowerCase();
    if (
      ns === 'force' ||
      ns === 'flexipage' ||
      ns === 'runtime_sales' ||
      ns === 'runtime_appointmentbooking' ||
      ns === 'runtime_commerce' ||
      ns === 'lightning' ||
      ns === 'osr'
    ) {
      return false;
    }
    return true;
  }
  return false;
}

/** Map FlexiPage component type/fqn to registry bundle name `c/bundleName`. */
export function lwcBundleFromComponent(c: FlexiComponent): string | null {
  if (c.fqn && typeof c.fqn === 'string') {
    return normalizeLwcBundleName(c.fqn);
  }
  if (c.type) {
    if (c.type.startsWith('c/') || c.type.startsWith('c:')) return normalizeLwcBundleName(c.type);
    if (c.type.startsWith('lwc:')) return normalizeLwcBundleName(`c/${c.type.slice(4)}`);
    if (c.type === 'lwc' && c.attributes?.fqn) {
      return normalizeLwcBundleName(String(c.attributes.fqn));
    }
    if (isCustomLwcType(c.type)) return normalizeLwcBundleName(c.type);
  }
  return null;
}

/** `c:foo` / `ns:foo` / `c/foo` / bare `foo` → `c/foo` (default namespace) or `ns/foo`. */
export function normalizeLwcBundleName(raw: string): string {
  const s = raw.trim();
  if (!s) return s;
  if (s.startsWith('c/')) return s;
  if (s.startsWith('c:')) return `c/${s.slice(2)}`;
  if (s.startsWith('lwc:')) return `c/${s.slice(4)}`;
  const colon = s.indexOf(':');
  if (colon > 0) {
    const ns = s.slice(0, colon);
    const name = s.slice(colon + 1);
    return ns === 'c' ? `c/${name}` : `${ns}/${name}`;
  }
  if (s.includes('/')) return s;
  return `c/${s}`;
}

/**
 * Bundles that the shell renders via Lit fidelity ports (Apex DTO cache).
 * Never prefer Sync Pack offlineHost / stub mounts for these.
 */
import {
  isFidelityBundle,
  cacheKeysForBindings,
  getFidelityEntry
} from './fidelity-registry.js';
import { buildHydratedDocument, type BinderData } from './hydrate.js';

export {
  FIDELITY_BUNDLES,
  FIDELITY_LIT_BUNDLES,
  getFidelityEntry,
  isFidelityBundle,
  listFidelityEntries,
  registerFidelityEntry,
  cacheKeysForBindings,
  APEX_BINDING_TO_CACHE_KEY,
  type FidelityEntry,
  type FidelityMode
} from './fidelity-registry.js';

export {
  hydrateTemplate,
  buildHydratedDocument,
  prepareTemplateHtml,
  type BinderData
} from './hydrate.js';

/** True when synced JS looks like a mountable custom-element module (not empty Tier-A stub). */
export function isUsableLwcSource(sourceJs?: string | null): boolean {
  if (!sourceJs || sourceJs.length < 80) return false;
  // Sync Pack Tier-A stub — empty "No items" card without host chrome
  if (
    sourceJs.includes('No items to display') &&
    !sourceJs.includes('osr-host-wrap') &&
    !sourceJs.includes('osr-host-body')
  ) {
    return false;
  }
  // Offline host with no real template (only empty-state copy)
  if (
    (sourceJs.includes('Synced from org · interactive logic') ||
      sourceJs.includes('Synced from org · interactive Apex/@wire')) &&
    sourceJs.includes('osr-empty')
  ) {
    return false;
  }
  return (
    sourceJs.includes('extends HTMLElement') ||
    sourceJs.includes('export default class') ||
    sourceJs.includes('customElements.define')
  );
}

/**
 * True when JS is runnable offline as a CE (no LWC/@salesforce imports).
 * Matches Sync Pack OsrLwcService.isRunnableOfflineJs.
 */
export function isRunnableOfflineLwcJs(sourceJs?: string | null): boolean {
  if (!sourceJs || sourceJs.length < 40) return false;
  if (sourceJs.includes("from 'lwc'") || sourceJs.includes('from "lwc"')) return false;
  if (sourceJs.includes('lightning/') || sourceJs.includes('@salesforce/')) return false;
  // Static offline hosts list Apex bindings — not interactive
  if (sourceJs.includes('osr-badge') && sourceJs.includes('Offline view')) return false;
  if (sourceJs.includes('osr-apex') || sourceJs.includes('Apex: ')) return false;
  return (
    sourceJs.includes('extends HTMLElement') ||
    sourceJs.includes('export default class') ||
    sourceJs.includes('customElements.define')
  );
}

/** Friendly card title from `c:fieldRepHomeTodayPlan` → `Today's Plan`. */
const LWC_LABEL_OVERRIDES: Record<string, string> = {
  fieldRepHomeTodayPlan: "Today's Plan",
  fieldRepHomeMetrics: 'Your Performance',
  fieldRepHomeNextBestCustomer: 'Top 5 NBC',
  fieldRepHomeClmPrefetch: 'CLM Content',
  homeOfficeMessages: 'Home Office Messages',
  repLocationPublisher: 'My Location',
  reportsHub: 'Reports',
  visitCallShell: 'Visit Call',
  visitCallShellLite: 'Visit Call',
  clmPlayerLite: 'CLM Player',
  fieldRepPlanner: 'Planner'
};

export function humanizeComponentLabel(typeOrBundle: string): string {
  const name = typeOrBundle
    .replace(/^lwc:/i, '')
    .replace(/^c[:/]/i, '')
    .replace(/^[\w.-]+[:/]/, '')
    .trim();
  if (LWC_LABEL_OVERRIDES[name]) return LWC_LABEL_OVERRIDES[name];
  const spaced = name
    .replace(/__/g, ' ')
    .replace(/_/g, ' ')
    .replace(/([a-z0-9])([A-Z])/g, '$1 $2')
    .replace(/\s+/g, ' ')
    .trim();
  if (!spaced) return typeOrBundle;
  // Drop noisy "Field Rep Home" prefix when present
  const cleaned = spaced.replace(/^Field Rep Home\s+/i, '').trim() || spaced;
  return cleaned.replace(/\b\w/g, (ch) => ch.toUpperCase());
}

export function extractRequiredFields(
  describe: Record<string, unknown> | null
): { apiName: string; label: string; required: boolean }[] {
  if (!describe) return [];
  const fields = (describe.fields as { name: string; label: string; required?: boolean; nillable?: boolean; createable?: boolean; updateable?: boolean; type?: string }[]) ?? [];
  return fields
    .filter((f) => f.name !== 'Id')
    .map((f) => ({
      apiName: f.name,
      label: f.label,
      required: Boolean(f.required) || f.nillable === false
    }));
}

export async function saveWithValidation(
  db: SqlExecutor,
  objectApi: string,
  record: Record<string, unknown>,
  isNew: boolean
): Promise<{ ok: boolean; validation: ValidationResult; recordId?: string; outboxId?: string }> {
  const describe = await getObjectDescribe(db, objectApi);
  const rules = await getValidationRules(db, objectApi);
  const required = extractRequiredFields(describe).filter((f) => f.required);
  const validation = validateRecord(record, rules, required);
  if (!validation.ok) {
    return { ok: false, validation };
  }
  const saved = await localSaveRecord(db, objectApi, record, isNew);
  return { ok: true, validation, recordId: saved.recordId, outboxId: saved.outboxId };
}

export type NavRoute =
  | { kind: 'launcher' }
  | { kind: 'home' }
  | { kind: 'menu' }
  | { kind: 'tab'; developerName: string; objectApi?: string }
  | { kind: 'list'; objectApi: string }
  | { kind: 'record'; objectApi: string; recordId: string }
  | { kind: 'flexipage'; developerName: string; recordId?: string; objectApi?: string }
  | { kind: 'file'; contentVersionId: string }
  | { kind: 'conflicts' }
  | { kind: 'logs' }
  | { kind: 'lwc'; bundleName: string; props?: Record<string, unknown> };

export type AppSummary = {
  id: string;
  developerName: string;
  label: string;
  tabDeveloperNames: string[];
  homeFlexiPageDeveloperName?: string | null;
  iconUrl?: string | null;
  logoUrl?: string | null;
};

export async function loadNavigation(db: SqlExecutor, selectedAppDeveloperName?: string | null) {
  const appsRaw = await listApps(db);
  const tabs = await listTabs(db);
  const apps: AppSummary[] = appsRaw.map((a) => ({
    id: a.id,
    developerName: a.developerName,
    label: a.label,
    tabDeveloperNames: (a.app.tabDeveloperNames as string[]) ?? tabs.map((t) => t.developerName),
    homeFlexiPageDeveloperName: (a.app.homeFlexiPageDeveloperName as string | null | undefined) ?? null,
    iconUrl: (a.app.iconUrl as string | null | undefined) ?? null,
    logoUrl: (a.app.logoUrl as string | null | undefined) ?? null
  }));

  let appTabs = tabs;
  if (selectedAppDeveloperName) {
    const app = apps.find((a) => a.developerName === selectedAppDeveloperName);
    if (app?.tabDeveloperNames?.length) {
      const order = app.tabDeveloperNames.map((n) => n.replace(/^standard-/, ''));
      const allowed = new Set(order);
      const byKey = new Map<string, (typeof tabs)[0]>();
      for (const t of tabs) {
        byKey.set(t.developerName, t);
        const objectApi = (t.tab as { objectApi?: string })?.objectApi;
        if (objectApi) byKey.set(objectApi, t);
      }
      const ordered: typeof tabs = [];
      const seen = new Set<string>();
      for (const name of order) {
        const t =
          byKey.get(name) ??
          tabs.find((x) => {
            const objectApi = (x.tab as { objectApi?: string })?.objectApi;
            return x.developerName === name || (objectApi != null && objectApi === name);
          });
        if (!t || seen.has(t.developerName)) continue;
        // Only include if this tab is in the app nav set
        const objectApi = (t.tab as { objectApi?: string })?.objectApi;
        if (
          allowed.has(t.developerName) ||
          allowed.has(`standard-${t.developerName}`) ||
          (objectApi != null && allowed.has(objectApi))
        ) {
          ordered.push(t);
          seen.add(t.developerName);
        }
      }
      // Append any extra matching tabs not listed (shouldn't happen often)
      for (const t of tabs) {
        if (seen.has(t.developerName)) continue;
        const objectApi = (t.tab as { objectApi?: string })?.objectApi;
        if (
          allowed.has(t.developerName) ||
          allowed.has(`standard-${t.developerName}`) ||
          (objectApi != null && allowed.has(objectApi))
        ) {
          ordered.push(t);
          seen.add(t.developerName);
        }
      }
      if (ordered.length) appTabs = ordered;
    }
  }

  return { apps, tabs: appTabs, allTabs: tabs };
}

export async function loadHomeView(db: SqlExecutor, appDeveloperName: string | null) {
  let homeName: string | null = null;
  let appLabel = 'Home';
  if (appDeveloperName) {
    const app = await getApp(db, appDeveloperName);
    if (app) {
      appLabel = app.label;
      homeName = (app.app.homeFlexiPageDeveloperName as string | null) ?? null;
    }
  }
  // Only fall back to Field_Rep_Home for Pharma Field / LightningSales
  const isPharmaField =
    appDeveloperName === 'LightningSales' ||
    (appLabel != null && appLabel.toLowerCase().includes('pharma field'));
  if (!homeName && isPharmaField) {
    const pages = await listFlexiPages(db);
    const preferred = pages.find((p) => p.developerName === 'Field_Rep_Home');
    homeName = preferred?.developerName ?? null;
  }
  if (!homeName && isPharmaField) {
    const pages = await listFlexiPages(db);
    const home = pages.find(
      (p) =>
        p.type === 'HomePage' ||
        p.page.type === 'HomePage' ||
        p.developerName.toLowerCase().includes('home')
    );
    homeName = home?.developerName ?? null;
  }
  const raw = homeName ? await getFlexiPage(db, homeName) : null;
  const flexiPage = parseFlexiPage(raw);
  const lwcBundles: string[] = [];
  for (const region of flexiPage?.regions ?? []) {
    for (const c of region.components) {
      const b = lwcBundleFromComponent(c);
      if (b) lwcBundles.push(b);
    }
  }
  return { appLabel, homeDeveloperName: homeName, flexiPage, lwcBundles };
}

export async function loadRecordView(db: SqlExecutor, objectApi: string, recordId: string) {
  const adapters = new LocalWireAdapters(db);
  const record = await adapters.getRecord(objectApi, recordId);
  const describe = await adapters.getObjectInfo(objectApi);
  const layoutRaw = await adapters.getLayout(objectApi);
  const layout = (parseLayout(layoutRaw) ?? layoutRaw) as LayoutModel | null;
  const found = await findFlexiPageForObject(db, objectApi);
  const flexiPage = parseFlexiPage(found?.page ?? null);
  const actions = await listActionsForObject(db, objectApi);
  const compact = await getCompactLayoutForObject(db, objectApi);
  return {
    record,
    describe,
    layout,
    flexiPage,
    flexiPageDeveloperName: found?.developerName ?? null,
    actions,
    compactLayout: compact?.compact ?? null
  };
}

export type RelatedListResult = {
  name: string;
  objectApi: string;
  lookupField: string;
  fields?: string[];
  records: Record<string, unknown>[];
};

/**
 * Load related lists from layout metadata when present; fall back to common patterns.
 */
export async function loadRelatedLists(
  db: SqlExecutor,
  parentObject: string,
  parentId: string,
  layoutRelated?: RelatedListMeta[] | null
): Promise<RelatedListResult[]> {
  const results: RelatedListResult[] = [];

  const fromLayout = (layoutRelated ?? []).filter((r) => r.objectApi && r.lookupField);
  if (fromLayout.length) {
    for (const r of fromLayout) {
      try {
        const records = await relatedRecords(db, r.objectApi!, r.lookupField!, parentId);
        results.push({
          name: r.label || r.relatedList,
          objectApi: r.objectApi!,
          lookupField: r.lookupField!,
          fields: r.fields,
          records
        });
      } catch {
        /* child not synced */
      }
    }
    if (results.length) return results;
  }

  const candidates: { parent: string; child: string; lookup: string; name: string }[] = [
    { parent: 'Account', child: 'Visit__c', lookup: 'Account__c', name: 'Visits' },
    { parent: 'Account', child: 'Contact', lookup: 'AccountId', name: 'Contacts' },
    { parent: 'Account', child: 'Opportunity', lookup: 'AccountId', name: 'Opportunities' },
    { parent: 'Account', child: 'Case', lookup: 'AccountId', name: 'Cases' },
    { parent: 'Contact', child: 'Task', lookup: 'WhoId', name: 'Tasks' }
  ];

  for (const c of candidates) {
    if (c.parent !== parentObject) continue;
    try {
      const records = await relatedRecords(db, c.child, c.lookup, parentId);
      if (records.length || c.child === 'Contact' || c.child === 'Opportunity') {
        results.push({
          name: c.name,
          objectApi: c.child,
          lookupField: c.lookup,
          records
        });
      }
    } catch {
      /* child object not in offline set */
    }
  }
  return results;
}

export async function loadObjectActions(db: SqlExecutor, objectApi: string): Promise<ActionRow[]> {
  return listActionsForObject(db, objectApi);
}

/** Register / render downloaded LWC (or HTMLElement) stubs — Tier A host */
const registered = new Map<string, CustomElementConstructor>();

/**
 * True when a bundle should be dynamically mounted instead of Lit fidelity ports.
 * Only staticResource / truly runnable CE JS qualify — offlineHost and stubs do not.
 */
export async function hasSyncedOrgLwc(db: SqlExecutor, bundleName: string): Promise<boolean> {
  const name = normalizeLwcBundleName(bundleName);
  if (isFidelityBundle(name)) return false;
  const bundle = await getLwcBundle(db, name);
  if (!bundle) return false;
  if (bundle.sourceKind === 'stub' || bundle.sourceKind === 'offlineHost') return false;
  if (bundle.sourceKind === 'staticResource' && isRunnableOfflineLwcJs(bundle.sourceJs)) {
    return true;
  }
  if (bundle.sourceKind === 'toolingSource' && isRunnableOfflineLwcJs(bundle.sourceJs)) {
    return true;
  }
  return isRunnableOfflineLwcJs(bundle.sourceJs);
}

/** Alias used by shell — prefer mount only for runnable CE bundles. */
export const hasUsableLwcBundle = hasSyncedOrgLwc;

/** True when org HTML/CSS exists (even as offlineHost) — for diagnostics only. */
export async function hasOrgLwcSource(db: SqlExecutor, bundleName: string): Promise<boolean> {
  const name = normalizeLwcBundleName(bundleName);
  const bundle = await getLwcBundle(db, name);
  if (!bundle) return false;
  if (bundle.sourceHtml || bundle.sourceCss || bundle.sourceJsRaw) return true;
  return Boolean(bundle.sourceJs && bundle.hasOrgSource);
}

export async function registerLwcFromDb(db: SqlExecutor, bundleName: string): Promise<boolean> {
  const name = normalizeLwcBundleName(bundleName);
  if (registered.has(name)) return true;
  const bundle = await getLwcBundle(db, name);
  if (!bundle) return false;
  let sourceJs = bundle.sourceJs;
  // If mountable JS missing but raw HTML/CSS present, compose a host on the client
  if (
    (!sourceJs || bundle.sourceKind === 'stub' || !isUsableLwcSource(sourceJs)) &&
    (bundle.sourceHtml || bundle.sourceCss)
  ) {
    sourceJs = composeOfflineHostFromParts(name, bundle.sourceHtml, bundle.sourceCss, bundle.sourceJsRaw);
  }
  if (!sourceJs) return false;
  const mountSource = sourceJs;
  const tag = bundleNameToTag(name);
  if (customElements.get(tag)) {
    registered.set(name, customElements.get(tag)!);
    return true;
  }
  try {
    const mod = await loadModuleFromSource(mountSource);
    if (mod) {
      customElements.define(tag, mod as CustomElementConstructor);
      registered.set(name, mod as CustomElementConstructor);
      return true;
    }
  } catch {
    // fall through
  }
  // Last resort: shadow host from HTML/CSS parts
  if (bundle.sourceHtml || bundle.sourceCss) {
    const html = bundle.sourceHtml ?? '';
    const css = bundle.sourceCss ?? '';
    class PartHost extends HTMLElement {
      connectedCallback() {
        const root = this.attachShadow({ mode: 'open' });
        root.innerHTML = `<style>${css}</style><div class="osr-lwc-body">${stripLwcTemplate(html)}</div>`;
      }
    }
    customElements.define(tag, PartHost);
    registered.set(name, PartHost);
    return true;
  }
  class StubElement extends HTMLElement {
    connectedCallback() {
      this.innerHTML = `<div class="lwc-stub"><strong>${escapeHtml(name)}</strong><pre>${escapeHtml(mountSource.slice(0, 400))}</pre></div>`;
    }
  }
  customElements.define(tag, StubElement);
  registered.set(name, StubElement);
  return true;
}

function stripLwcTemplate(html: string): string {
  let s = html.trim();
  if (s.toLowerCase().startsWith('<template')) {
    const gt = s.indexOf('>');
    const end = s.toLowerCase().lastIndexOf('</template>');
    if (gt > 0 && end > gt) s = s.slice(gt + 1, end).trim();
  }
  return s
    .replace(/\s+lwc:[a-z0-9_-]+(="[^"]*")?/gi, '')
    .replace(/\s+if:true="\{[^}]*\}"/gi, '')
    .replace(/\s+if:false="\{[^}]*\}"/gi, '')
    .replace(/\s+for:each="\{[^}]*\}"/gi, '')
    .replace(/\s+for:item="[^"]*"/gi, '')
    .replace(/\s+on[a-z]+="\{[^}]*\}"/gi, '')
    .replace(/\{[^}]+\}/g, '—');
}

function composeOfflineHostFromParts(
  bundleName: string,
  html?: string,
  css?: string,
  _jsRaw?: string
): string {
  const title = humanizeComponentLabel(bundleName);
  const body = stripLwcTemplate(html ?? '') ||
    '<div style="padding:20px;text-align:center;color:#706e6b">No items to display</div>';
  const style = css ?? '';
  // Escape for template literal embedding
  const esc = (s: string) =>
    s.replace(/\\/g, '\\\\').replace(/`/g, '\\`').replace(/\$\{/g, '\\${');
  return `export default class OsrPartHost extends HTMLElement {
  connectedCallback(){
    this.attachShadow({mode:'open'}).innerHTML = \`
      <style>${esc(style)}
        :host{display:block;font:13px/1.4 Salesforce Sans,Helvetica,Arial,sans-serif;color:#181818}
        .wrap{background:#fff;border:1px solid #c9c9c9;border-radius:4px;overflow:hidden}
        .hdr{padding:10px 12px;border-bottom:1px solid #e5e5e5;font-weight:700;font-size:13px;display:flex;justify-content:space-between}
        .badge{font-size:10px;color:#0176d3;background:#eef4ff;border-radius:4px;padding:2px 6px}
      </style>
      <div class="wrap">
        <div class="hdr"><span>${esc(title)}</span><span class="badge">Offline view</span></div>
        <div>${esc(body)}</div>
      </div>\`;
  }
}`;
}

async function loadModuleFromSource(source: string): Promise<CustomElementConstructor | null> {
  const rewritten = source.includes('export default')
    ? source
    : `export default ${source}`;
  const url = URL.createObjectURL(new Blob([rewritten], { type: 'text/javascript' }));
  try {
    const mod = await import(/* @vite-ignore */ url);
    return (mod.default ?? null) as CustomElementConstructor | null;
  } catch {
    return null;
  } finally {
    URL.revokeObjectURL(url);
  }
}

export function bundleNameToTag(bundleName: string): string {
  const normalized = normalizeLwcBundleName(bundleName);
  return (
    'osr-' +
    normalized
      .replace(/^[\w.-]+\//, '')
      .replace(/([a-z])([A-Z])/g, '$1-$2')
      .replace(/__/g, '-')
      .replace(/\//g, '-')
      .toLowerCase()
  );
}

function escapeHtml(s: string): string {
  return s.replace(/[&<>"']/g, (c) =>
    ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' })[c]!
  );
}

export async function mountLwc(
  db: SqlExecutor,
  host: HTMLElement,
  bundleName: string,
  props: Record<string, unknown> = {}
): Promise<HTMLElement | null> {
  const name = normalizeLwcBundleName(bundleName);
  const ok = await registerLwcFromDb(db, name);
  if (!ok) {
    host.innerHTML = `<div class="error">LWC bundle not synced: ${escapeHtml(name)}</div>`;
    return null;
  }
  const tag = bundleNameToTag(name);
  host.innerHTML = '';
  const el = document.createElement(tag);
  Object.entries(props).forEach(([k, v]) => {
    (el as HTMLElement & Record<string, unknown>)[k] = v;
    el.setAttribute(k, String(v));
  });
  host.appendChild(el);
  return el;
}

/**
 * Mount synced org HTML/CSS hydrated with Apex-cache (or arbitrary) data.
 * Light DOM under .osr-lwc-mirror so shared SLDS / Leaflet work.
 */
export async function mountHydratedLwc(
  db: SqlExecutor,
  host: HTMLElement,
  bundleName: string,
  opts: {
    data?: BinderData;
    title?: string;
    cached?: boolean;
    onAction?: (action: string, detail: Record<string, string>) => void;
  } = {}
): Promise<boolean> {
  const name = normalizeLwcBundleName(bundleName);
  const bundle = await getLwcBundle(db, name);
  if (!bundle?.sourceHtml && !bundle?.sourceCss) {
    host.innerHTML = `<div class="osr-lwc-mirror slds-text-align_center slds-p-around_medium"><strong>No synced template</strong><div>${escapeHtml(name)}</div></div>`;
    return false;
  }
  const entry = getFidelityEntry(name);
  const title = opts.title ?? entry?.label ?? humanizeComponentLabel(name);
  host.innerHTML = buildHydratedDocument(bundle.sourceHtml, bundle.sourceCss, opts.data ?? {}, {
    title,
    cached: opts.cached
  });
  if (opts.onAction) {
    host.querySelectorAll('[data-action]').forEach((node) => {
      node.addEventListener('click', (ev) => {
        ev.preventDefault();
        const el = ev.currentTarget as HTMLElement;
        const action = el.getAttribute('data-action') || 'click';
        const detail: Record<string, string> = {};
        for (const attr of el.attributes) {
          if (attr.name.startsWith('data-') && attr.name !== 'data-action') {
            detail[attr.name.slice(5)] = attr.value;
          }
        }
        opts.onAction?.(action, detail);
      });
    });
  }
  return true;
}

/** Resolve apexBindings on a synced bundle to cache keys (for hydrate data loading). */
export async function resolveBundleCacheKeys(
  db: SqlExecutor,
  bundleName: string
): Promise<string[]> {
  const name = normalizeLwcBundleName(bundleName);
  const entry = getFidelityEntry(name);
  if (entry?.cacheKeys?.length) return entry.cacheKeys;
  const bundle = await getLwcBundle(db, name);
  return cacheKeysForBindings(bundle?.apexBindings);
}

export async function openFileMeta(db: SqlExecutor, contentVersionId: string) {
  return getFile(db, contentVersionId);
}

export async function getConflicts(db: SqlExecutor) {
  return listOpenConflicts(db);
}

export async function applyConflictResolution(
  db: SqlExecutor,
  conflictId: string,
  resolution: 'server-wins' | 'client-wins' | 'merged',
  mergedRecord?: Record<string, unknown>
): Promise<void> {
  const open = await listOpenConflicts(db);
  const c = open.find((x) => x.id === conflictId);
  if (!c) return;
  if (resolution === 'server-wins' && c.objectApi && c.recordId) {
    await upsertRecord(db, c.objectApi, c.recordId, c.server as Record<string, unknown>);
  } else if (resolution === 'client-wins' && c.objectApi && c.recordId) {
    await upsertRecord(db, c.objectApi, c.recordId, c.client as Record<string, unknown>);
    await enqueueOutbox(db, {
      op: 'update',
      objectApi: c.objectApi,
      recordId: c.recordId,
      payload: c.client
    });
  } else if (resolution === 'merged' && mergedRecord && c.objectApi && c.recordId) {
    await upsertRecord(db, c.objectApi, c.recordId, mergedRecord);
    await enqueueOutbox(db, {
      op: 'update',
      objectApi: c.objectApi,
      recordId: c.recordId,
      payload: mergedRecord
    });
  }
  await resolveConflict(db, conflictId, resolution);
}

export { localDeleteRecord, getFlexiPage, listTabs, listApps, getApp };

/** Pharma journey ports — patterns from clmOfflineStore / visit shell */
export interface VisitOfflinePayload {
  visitId: string;
  accountId?: string;
  status?: string;
  callReport?: Record<string, unknown>;
  samples?: unknown[];
  updatedAt: string;
}

export async function putVisitPayload(db: SqlExecutor, payload: VisitOfflinePayload): Promise<void> {
  const existing = (await getRecord(db, 'Visit__c', payload.visitId)) ?? { Id: payload.visitId };
  const merged = {
    ...existing,
    ...payload.callReport,
    Status__c: payload.status ?? existing.Status__c,
    Account__c: payload.accountId ?? existing.Account__c,
    _offlineCallReport: payload.callReport ?? null,
    _offlineSamples: payload.samples ?? null,
    _offlineUpdatedAt: payload.updatedAt
  };
  await upsertRecord(db, 'Visit__c', payload.visitId, merged as Record<string, unknown>);
  await enqueueOutbox(db, {
    op: 'visit.upsert',
    objectApi: 'Visit__c',
    recordId: payload.visitId,
    payload: merged
  });
}

export async function getVisitPayload(
  db: SqlExecutor,
  visitId: string
): Promise<VisitOfflinePayload | null> {
  const rec = await getRecord(db, 'Visit__c', visitId);
  if (!rec) return null;
  return {
    visitId,
    accountId: rec.Account__c as string | undefined,
    status: rec.Status__c as string | undefined,
    callReport: (rec._offlineCallReport as Record<string, unknown>) ?? undefined,
    samples: (rec._offlineSamples as unknown[]) ?? undefined,
    updatedAt: String(rec._offlineUpdatedAt ?? rec.SystemModstamp ?? '')
  };
}

export interface ClmSessionAction {
  actionType: string;
  clientSessionKey: string;
  visitId?: string;
  presentationId?: string;
  payload?: Record<string, unknown>;
}

export async function enqueueClmSession(
  db: SqlExecutor,
  action: ClmSessionAction
): Promise<string> {
  return enqueueOutbox(db, {
    op: 'clm.session',
    objectApi: 'CLM_Session__c',
    recordId: action.clientSessionKey,
    payload: action
  });
}

export interface PlannerRescheduleItem {
  visitId: string;
  plannedDate: string;
}

export async function enqueuePlannerReschedule(
  db: SqlExecutor,
  items: PlannerRescheduleItem[]
): Promise<string> {
  return enqueueOutbox(db, {
    op: 'planner.reschedule',
    objectApi: 'Visit__c',
    payload: { items }
  });
}

export const SYNC_BUDGETS = {
  maxRecordsPerObject: 5000,
  maxFileBytesPerDevice: 500 * 1024 * 1024,
  maxOutboxBatch: 25,
  metadataRefreshHours: 24,
  pullTimeoutMs: 120_000
} as const;
