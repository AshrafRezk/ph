/**
 * Shell-side bridge handlers: SQLite / apex-cache / outbox / navigation / toast.
 */
import type { BridgeHandler, BridgeDataSource } from '@osr/bridge';
import type { SqlExecutor } from '@osr/db';
import {
  getApexPayload,
  getRecord,
  getObjectDescribe,
  listRecords,
  kvGet,
  kvSet,
  getLwcBundle
} from '@osr/db';
import { APEX_BINDING_TO_CACHE_KEY } from '@osr/ui-runtime';
import { compileToolingBundle, scanLwcSource } from '@osr/lwc-compile/scan';

export type ShellBridgeContext = {
  db: SqlExecutor | null;
  online: boolean;
  /** Prefer live Apex when online (still writes through to cache when possible). */
  liveApex?: boolean;
  openRecord?: (objectApi: string, id: string) => void;
  openVisitShell?: (id: string) => void;
  openPlanner?: () => void;
  openTab?: (developerName: string) => void;
  toast?: (detail: { title?: string; message?: string; variant?: string }) => void;
  confirm?: (message: string) => Promise<boolean>;
  onResize?: (bundle: string, height: number) => void;
  /** Optional live Apex invoker */
  invokeLiveApex?: (
    method: string,
    params: Record<string, unknown>
  ) => Promise<unknown>;
};

const COMPILED_KV_PREFIX = 'osr.lwc.compiled.';

export function createShellBridgeHandler(ctx: ShellBridgeContext): BridgeHandler {
  return async (method, params) => {
    switch (method) {
      case 'ping':
        return {
          result: { ok: true, online: ctx.online, t: Date.now(), echo: params },
          source: 'local'
        };
      case 'net.status':
        return { result: { online: ctx.online }, source: 'local' };
      case 'ui.getRecord': {
        if (!ctx.db) throw new Error('DB not ready');
        const recordId = String(params.recordId ?? '');
        const objectApi = String(params.objectApi ?? params.objectApiName ?? 'Account');
        const rec = await getRecord(ctx.db, objectApi, recordId);
        if (!rec) throw new Error(`Record not found: ${objectApi}/${recordId}`);
        return { result: rec, source: 'cache' };
      }
      case 'ui.getObjectInfo': {
        if (!ctx.db) throw new Error('DB not ready');
        const objectApi = String(params.objectApi ?? params.objectApiName ?? '');
        const info = await getObjectDescribe(ctx.db, objectApi);
        return { result: info, source: 'cache' };
      }
      case 'ui.getList': {
        if (!ctx.db) throw new Error('DB not ready');
        const objectApi = String(params.objectApi ?? '');
        const rows = await listRecords(ctx.db, objectApi, Number(params.pageSize ?? 50));
        return { result: { records: rows }, source: 'cache' };
      }
      case 'apex.invoke':
      case 'apex.wire':
        return invokeApex(ctx, String(params.method ?? ''), (params.params as Record<string, unknown>) ?? {});
      case 'nav.navigate': {
        const pageRef = params.pageRef as {
          type?: string;
          attributes?: Record<string, unknown>;
        };
        handleNavigate(ctx, pageRef);
        return { result: true, source: 'local' };
      }
      case 'nav.generateUrl':
        return { result: '#', source: 'local' };
      case 'ui.toast': {
        ctx.toast?.({
          title: params.title != null ? String(params.title) : undefined,
          message: params.message != null ? String(params.message) : undefined,
          variant: params.variant != null ? String(params.variant) : undefined
        });
        return { result: true, source: 'local' };
      }
      case 'ui.confirm': {
        const ok = ctx.confirm
          ? await ctx.confirm(String(params.message ?? 'Confirm?'))
          : true;
        return { result: ok, source: 'local' };
      }
      case 'host.resize': {
        const bundle = String(params.bundle ?? '');
        const height = Number(params.height ?? 120);
        ctx.onResize?.(bundle, height);
        return { result: true, source: 'local' };
      }
      case 'lwc.getCompiledModule':
        return getCompiledModule(ctx, String(params.bundle ?? ''));
      default:
        throw new Error(`Unhandled bridge method: ${method}`);
    }
  };
}

async function invokeApex(
  ctx: ShellBridgeContext,
  method: string,
  params: Record<string, unknown>
): Promise<{ result: unknown; source: BridgeDataSource }> {
  const short = method.replace(/^.*\//, '');
  const cacheKey =
    APEX_BINDING_TO_CACHE_KEY[short] ??
    APEX_BINDING_TO_CACHE_KEY[method] ??
    null;

  if (ctx.db && cacheKey) {
    const cached = await getApexPayload(ctx.db, cacheKey);
    if (cached) {
      // officeMessages etc. may be raw array or wrapped
      let payload: unknown = cached.payload;
      if (
        cacheKey === 'officeMessages' &&
        payload &&
        typeof payload === 'object' &&
        !Array.isArray(payload) &&
        Array.isArray((payload as { messages?: unknown }).messages)
      ) {
        payload = (payload as { messages: unknown[] }).messages;
      }
      // Background live refresh
      if (ctx.online && ctx.liveApex && ctx.invokeLiveApex) {
        void ctx.invokeLiveApex(method, params).catch(() => undefined);
      }
      return { result: payload, source: 'cache' };
    }
  }

  if (ctx.online && ctx.invokeLiveApex) {
    const result = await ctx.invokeLiveApex(method, params);
    return { result, source: 'live' };
  }

  if (ctx.db && cacheKey) {
    return { result: cacheKey === 'officeMessages' ? [] : null, source: 'cache' };
  }

  throw new Error(`Apex unavailable offline and no cache: ${method}`);
}

function handleNavigate(
  ctx: ShellBridgeContext,
  pageRef?: { type?: string; attributes?: Record<string, unknown> }
) {
  if (!pageRef) return;
  const attrs = pageRef.attributes ?? {};
  if (pageRef.type === 'standard__recordPage' && attrs.recordId) {
    const objectApi = String(attrs.objectApiName ?? 'Visit__c');
    const id = String(attrs.recordId);
    if (objectApi === 'Visit__c' || objectApi === 'Visit') {
      ctx.openVisitShell?.(id);
      return;
    }
    ctx.openRecord?.(objectApi, id);
    return;
  }
  if (pageRef.type === 'standard__navItemPage' && attrs.apiName) {
    const api = String(attrs.apiName);
    if (api === 'Field_Rep_Planner' || api.toLowerCase().includes('planner')) {
      ctx.openPlanner?.();
      return;
    }
    ctx.openTab?.(api);
    return;
  }
  if (attrs.recordId && attrs.objectApiName) {
    ctx.openRecord?.(String(attrs.objectApiName), String(attrs.recordId));
  }
}

async function getCompiledModule(
  ctx: ShellBridgeContext,
  bundle: string
): Promise<{ result: { sourceJs?: string; version?: string; compat?: unknown }; source: BridgeDataSource }> {
  if (!ctx.db) throw new Error('DB not ready');
  const name = bundle.startsWith('c/') ? bundle : `c/${bundle}`;
  const cached = await kvGet(ctx.db, COMPILED_KV_PREFIX + name);
  if (cached) {
    try {
      const parsed = JSON.parse(cached) as { sourceJs?: string; version?: string; compat?: unknown };
      return { result: parsed, source: 'cache' };
    } catch {
      /* fall through */
    }
  }

  const row = await getLwcBundle(ctx.db, name);
  if (!row?.sourceJsRaw && !row?.sourceHtml) {
    return { result: {}, source: 'cache' };
  }

  const compat = scanLwcSource(name, row.sourceJsRaw ?? '', row.sourceHtml ?? '');
  const compiled = await compileToolingBundle({
    bundleName: name,
    sourceJsRaw: row.sourceJsRaw,
    sourceHtml: row.sourceHtml,
    sourceCss: row.sourceCss
  });

  if (compiled.ok && compiled.code) {
    const payload = {
      sourceJs: compiled.code,
      version: row.version,
      compat,
      error: compiled.error
    };
    await kvSet(ctx.db, COMPILED_KV_PREFIX + name, JSON.stringify(payload));
    return { result: payload, source: 'local' };
  }

  return {
    result: { compat, sourceJs: undefined },
    source: 'local'
  };
}

/** Compile all synced Tooling LWC bundles into kv cache (post-sync). */
export async function compileSyncedLwcs(
  db: SqlExecutor,
  bundleNames: string[]
): Promise<{ compiled: number; reports: ReturnType<typeof scanLwcSource>[] }> {
  const reports: ReturnType<typeof scanLwcSource>[] = [];
  let compiled = 0;
  for (const raw of bundleNames) {
    const name = raw.startsWith('c/') ? raw : `c/${raw}`;
    const row = await getLwcBundle(db, name);
    if (!row) continue;
    const compat = scanLwcSource(name, row.sourceJsRaw ?? row.sourceJs ?? '', row.sourceHtml ?? '');
    reports.push(compat);
    if (!row.sourceJsRaw && !row.sourceHtml) continue;
    const result = await compileToolingBundle({
      bundleName: name,
      sourceJsRaw: row.sourceJsRaw,
      sourceHtml: row.sourceHtml,
      sourceCss: row.sourceCss
    });
    if (result.ok && result.code) {
      await kvSet(
        db,
        COMPILED_KV_PREFIX + name,
        JSON.stringify({
          sourceJs: result.code,
          version: row.version,
          compat,
          error: result.error
        })
      );
      compiled++;
    }
  }
  return { compiled, reports };
}
