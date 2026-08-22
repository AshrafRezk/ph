import { sfFetch } from '@osr/sync';
import type { AdminModuleContext } from './types';

const API_VERSION = (import.meta.env.VITE_SF_API_VERSION as string) || '61.0';

function parseApexErrors(errors: unknown): string {
  if (!errors) return 'Apex call failed';
  if (Array.isArray(errors)) {
    return errors
      .map((e) => (typeof e === 'object' && e && 'message' in e ? String((e as { message: string }).message) : String(e)))
      .join(', ');
  }
  if (typeof errors === 'object' && errors && 'message' in errors) {
    return String((errors as { message: string }).message);
  }
  return String(errors);
}

function extractApexOutput(body: Record<string, unknown>): unknown {
  if (body.isSuccess === false) {
    throw new Error(parseApexErrors(body.errors));
  }
  const ov = body.outputValues as Record<string, unknown> | undefined;
  if (!ov) return null;
  const keys = Object.keys(ov);
  if (keys.length === 1) return ov[keys[0]!];
  if (keys.length === 0) return null;
  return ov;
}

/** Invoke @AuraEnabled Apex via Salesforce REST custom actions API. */
export async function callAdminApex(
  auth: { accessToken: string; instanceUrl: string },
  method: string,
  params: Record<string, unknown> = {}
): Promise<unknown> {
  const [controller, action] = method.split('.');
  if (!controller || !action) throw new Error(`Invalid Apex method: ${method}`);
  const url = `${auth.instanceUrl.replace(/\/$/, '')}/services/data/v${API_VERSION}/actions/custom/apex/${controller}/${action}`;
  const res = await sfFetch(url, {
    method: 'POST',
    accessToken: auth.accessToken,
    body: { inputs: [params] }
  });
  const text = await res.text();
  let body: Record<string, unknown> = {};
  try {
    body = text ? (JSON.parse(text) as Record<string, unknown>) : {};
  } catch {
    throw new Error(text || `Apex HTTP ${res.status}`);
  }
  if (!res.ok) {
    const msg =
      (body as { message?: string }).message ||
      (Array.isArray(body) && body[0] && typeof body[0] === 'object' && 'message' in body[0]
        ? String((body[0] as { message: string }).message)
        : text) ||
      `Apex HTTP ${res.status}`;
    throw new Error(msg);
  }
  return extractApexOutput(body);
}

export async function adminApex(
  ctx: AdminModuleContext,
  method: string,
  params: Record<string, unknown> = {}
): Promise<unknown> {
  if (ctx.invokeApex) return ctx.invokeApex(method, params);
  if (!ctx.sfAuth?.accessToken) {
    throw new Error('Sign in while online to use this admin module.');
  }
  return callAdminApex(ctx.sfAuth, method, params);
}

export function adminToast(
  ctx: AdminModuleContext,
  title: string,
  message: string,
  variant: 'success' | 'error' | 'warning' | 'info' = 'info'
): void {
  ctx.toast?.({ title, message, variant });
}

export function reduceAdminError(error: unknown): string {
  if (error instanceof Error) return error.message;
  if (typeof error === 'object' && error && 'body' in error) {
    const body = (error as { body?: { message?: string } | Array<{ message?: string }> }).body;
    if (Array.isArray(body)) return body.map((b) => b.message).filter(Boolean).join(', ');
    if (body?.message) return body.message;
  }
  return String(error);
}
