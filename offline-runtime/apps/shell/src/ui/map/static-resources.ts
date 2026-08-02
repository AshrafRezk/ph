/**
 * Resolve synced org StaticResources (Leaflet zip, pdf.js, …) from SQLite.
 * Lit fidelity maps use npm Leaflet; hydrated / future CE hosts can load these blobs.
 */
import type { SqlExecutor } from '@osr/db';
import { getStaticResource } from '@osr/db';

const objectUrls = new Map<string, string>();

export async function getSyncedStaticResourceBlob(
  db: SqlExecutor,
  name: string
): Promise<{ blob: Blob; contentType: string } | null> {
  const row = await getStaticResource(db, name);
  if (!row?.bodyBase64) return null;
  const bin = Uint8Array.from(atob(row.bodyBase64), (c) => c.charCodeAt(0));
  const contentType = row.contentType || 'application/octet-stream';
  return { blob: new Blob([bin], { type: contentType }), contentType };
}

/** Object URL for a synced StaticResource (revoked on replace). */
export async function getSyncedStaticResourceUrl(
  db: SqlExecutor,
  name: string
): Promise<string | null> {
  const got = await getSyncedStaticResourceBlob(db, name);
  if (!got) return null;
  const prev = objectUrls.get(name);
  if (prev) URL.revokeObjectURL(prev);
  const url = URL.createObjectURL(got.blob);
  objectUrls.set(name, url);
  return url;
}

export async function hasSyncedMapLibs(db: SqlExecutor): Promise<boolean> {
  const leaflet = await getStaticResource(db, 'leaflet');
  return !!leaflet?.bodyBase64;
}
