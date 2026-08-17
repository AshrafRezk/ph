import { sfFetch, sfFetchArrayBuffer } from '@osr/sync';

const DB_NAME = 'osrClmAssets';
const DB_VERSION = 2;
const STORE = 'assets';
const API_VERSION = (import.meta.env.VITE_SF_API_VERSION as string) || '61.0';

export type ClmAuth = { accessToken: string; instanceUrl: string };

export type ClmPresentationAsset = {
  id?: string;
  presentationId?: string;
  name?: string;
  formatType?: string;
  contentDocumentId?: string;
  sequences?: {
    slideImageUrl?: string;
    thumbnailUrl?: string;
    sequenceName?: string;
    name?: string;
    order?: number;
    sequenceOrder?: number;
    messageNames?: string;
    pageNumber?: number;
  }[];
};

export type ClmSlideMedia = {
  objectUrl: string;
  kind: 'image' | 'pdf';
};

let dbPromise: Promise<IDBDatabase> | null = null;

function hashKey(input: string): string {
  let h = 5381;
  for (let i = 0; i < input.length; i += 1) h = (h * 33) ^ input.charCodeAt(i);
  return `clm_${(h >>> 0).toString(36)}_${input.length}`;
}

function openDb(): Promise<IDBDatabase> {
  if (dbPromise) return dbPromise;
  dbPromise = new Promise((resolve, reject) => {
    const req = indexedDB.open(DB_NAME, DB_VERSION);
    req.onupgradeneeded = (event) => {
      const db = req.result;
      if (event.oldVersion > 0 && event.oldVersion < 2 && db.objectStoreNames.contains(STORE)) {
        db.deleteObjectStore(STORE);
      }
      if (!db.objectStoreNames.contains(STORE)) {
        db.createObjectStore(STORE);
      }
    };
    req.onsuccess = () => resolve(req.result);
    req.onerror = () => reject(req.error ?? new Error('CLM asset DB failed'));
  });
  return dbPromise;
}

async function getCachedBlob(key: string): Promise<Blob | null> {
  try {
    const db = await openDb();
    return await new Promise((resolve, reject) => {
      const tx = db.transaction(STORE, 'readonly');
      const req = tx.objectStore(STORE).get(key);
      req.onsuccess = () => {
        const v = req.result;
        resolve(v instanceof Blob ? v : null);
      };
      req.onerror = () => reject(req.error);
    });
  } catch {
    return null;
  }
}

async function putCachedBlob(key: string, blob: Blob): Promise<void> {
  const db = await openDb();
  await new Promise<void>((resolve, reject) => {
    const tx = db.transaction(STORE, 'readwrite');
    tx.objectStore(STORE).put(blob, key);
    tx.oncomplete = () => resolve();
    tx.onerror = () => reject(tx.error);
  });
}

export async function deleteCachedClmAsset(assetPath: string): Promise<void> {
  try {
    const db = await openDb();
    const key = hashKey(assetPath);
    await new Promise<void>((resolve, reject) => {
      const tx = db.transaction(STORE, 'readwrite');
      tx.objectStore(STORE).delete(key);
      tx.oncomplete = () => resolve();
      tx.onerror = () => reject(tx.error);
    });
  } catch {
    /* ignore */
  }
}

export function resolveSalesforceUrl(path: string, instanceUrl: string): string {
  if (path.startsWith('http://') || path.startsWith('https://')) return path;
  const base = instanceUrl.replace(/\/$/, '');
  return `${base}${path.startsWith('/') ? path : `/${path}`}`;
}

/** Shepherd servlet URLs need a ContentVersion id for REST VersionData (Bearer-safe). */
export function parseContentVersionId(path: string): string | null {
  if (!path) return null;
  const downloadMatch = path.match(/\/version\/download\/([a-zA-Z0-9]{15,18})/);
  if (downloadMatch) return downloadMatch[1];
  try {
    const base = path.startsWith('http') ? path : `https://placeholder.local${path.startsWith('/') ? path : `/${path}`}`;
    const url = new URL(base);
    const fromQuery = url.searchParams.get('versionId');
    if (fromQuery && /^[a-zA-Z0-9]{15,18}$/.test(fromQuery)) return fromQuery;
  } catch {
    /* ignore */
  }
  return null;
}

function versionDataPath(contentVersionId: string): string {
  return `/services/data/v${API_VERSION}/sobjects/ContentVersion/${contentVersionId}/VersionData`;
}

function sniffBlobKind(buffer: ArrayBuffer): 'image' | 'pdf' | 'html' | 'unknown' {
  const bytes = new Uint8Array(buffer.slice(0, 16));
  if (bytes.length >= 4 && bytes[0] === 0x89 && bytes[1] === 0x50 && bytes[2] === 0x4e && bytes[3] === 0x47) {
    return 'image';
  }
  if (bytes.length >= 3 && bytes[0] === 0xff && bytes[1] === 0xd8 && bytes[2] === 0xff) {
    return 'image';
  }
  if (bytes.length >= 4 && bytes[0] === 0x25 && bytes[1] === 0x50 && bytes[2] === 0x44 && bytes[3] === 0x46) {
    return 'pdf';
  }
  const text = new TextDecoder().decode(bytes).trimStart().toLowerCase();
  if (text.startsWith('<!doctype') || text.startsWith('<html') || text.startsWith('{')) {
    return 'html';
  }
  return 'unknown';
}

function mimeForKind(kind: 'image' | 'pdf' | 'unknown', contentType: string): string {
  if (kind === 'pdf') return 'application/pdf';
  if (kind === 'image') {
    if (contentType.startsWith('image/')) return contentType;
    return 'image/png';
  }
  return contentType || 'application/octet-stream';
}

async function queryLatestContentVersionId(
  contentDocumentId: string,
  auth: ClmAuth
): Promise<string | null> {
  const q = encodeURIComponent(
    `SELECT Id FROM ContentVersion WHERE ContentDocumentId='${contentDocumentId}' AND IsLatest=true LIMIT 1`
  );
  const url = resolveSalesforceUrl(`/services/data/v${API_VERSION}/query?q=${q}`, auth.instanceUrl);
  const res = await sfFetch(url, {
    accessToken: auth.accessToken,
    headers: { Accept: 'application/json' }
  });
  if (!res.ok) return null;
  const json = (await res.json()) as { records?: { Id?: string }[] };
  const id = json.records?.[0]?.Id;
  return id ? String(id) : null;
}

async function fetchVersionDataBlob(contentVersionId: string, auth: ClmAuth): Promise<Blob> {
  const path = versionDataPath(contentVersionId);
  const fullUrl = resolveSalesforceUrl(path, auth.instanceUrl);
  const { buffer, contentType } = await sfFetchArrayBuffer(fullUrl, auth.accessToken);
  const kind = sniffBlobKind(buffer);
  if (kind === 'html') {
    throw new Error('Salesforce returned HTML instead of slide bytes — check file access.');
  }
  return new Blob([buffer], { type: mimeForKind(kind, contentType) });
}

async function fetchRemoteAssetBlob(assetPath: string, auth: ClmAuth): Promise<Blob> {
  const versionId = parseContentVersionId(assetPath);
  if (versionId) {
    return fetchVersionDataBlob(versionId, auth);
  }
  if (assetPath.includes('/document/download/')) {
    const docMatch = assetPath.match(/\/document\/download\/([a-zA-Z0-9]{15,18})/);
    const docId = docMatch?.[1];
    if (docId) {
      const latest = await queryLatestContentVersionId(docId, auth);
      if (latest) return fetchVersionDataBlob(latest, auth);
    }
  }
  // Last resort: direct URL (works for some CDN / absolute URLs)
  const fullUrl = resolveSalesforceUrl(assetPath, auth.instanceUrl);
  const { buffer, contentType } = await sfFetchArrayBuffer(fullUrl, auth.accessToken);
  const kind = sniffBlobKind(buffer);
  if (kind === 'html') {
    throw new Error('Could not load slide — Salesforce file URL is not OAuth-accessible.');
  }
  return new Blob([buffer], { type: mimeForKind(kind, contentType) });
}

export async function fetchClmAssetBlob(
  assetPath: string,
  auth: ClmAuth,
  online: boolean,
  opts?: { skipCache?: boolean }
): Promise<Blob | null> {
  const key = hashKey(assetPath);
  if (!opts?.skipCache) {
    const cached = await getCachedBlob(key);
    if (cached) {
      const buf = await cached.arrayBuffer();
      const kind = sniffBlobKind(buf);
      if (kind !== 'html') return cached;
      await deleteCachedClmAsset(assetPath);
    }
  }
  if (!online) return null;
  const blob = await fetchRemoteAssetBlob(assetPath, auth);
  const kind = sniffBlobKind(await blob.arrayBuffer());
  if (kind === 'html') {
    throw new Error('Downloaded slide file is not a valid image or PDF.');
  }
  await putCachedBlob(key, blob);
  return blob;
}

const objectUrls = new Map<string, string>();

export async function getSlideMediaObjectUrl(
  imagePath: string | undefined | null,
  auth: ClmAuth,
  online: boolean,
  opts?: { skipCache?: boolean }
): Promise<ClmSlideMedia | null> {
  if (!imagePath) return null;
  const blob = await fetchClmAssetBlob(imagePath, auth, online, opts);
  if (!blob) return null;
  const buf = await blob.arrayBuffer();
  const kind = sniffBlobKind(buf);
  if (kind === 'html') return null;
  const cacheKey = hashKey(imagePath);
  const prev = objectUrls.get(cacheKey);
  if (prev) URL.revokeObjectURL(prev);
  const objectUrl = URL.createObjectURL(blob);
  objectUrls.set(cacheKey, objectUrl);
  return { objectUrl, kind: kind === 'pdf' ? 'pdf' : 'image' };
}

export async function getPresentationPdfObjectUrl(
  contentDocumentId: string,
  auth: ClmAuth,
  online: boolean
): Promise<string | null> {
  const path = `/sfc/servlet.shepherd/document/download/${encodeURIComponent(contentDocumentId)}`;
  const media = await getSlideMediaObjectUrl(path, auth, online);
  return media?.objectUrl ?? null;
}

export async function countCachedClmAssets(): Promise<number> {
  try {
    const db = await openDb();
    return await new Promise((resolve, reject) => {
      const tx = db.transaction(STORE, 'readonly');
      const req = tx.objectStore(STORE).count();
      req.onsuccess = () => resolve(req.result);
      req.onerror = () => reject(req.error);
    });
  } catch {
    return 0;
  }
}

export async function prefetchPresentationAssets(
  presentation: ClmPresentationAsset,
  auth: ClmAuth,
  onProgress?: (completed: number, total: number) => void
): Promise<void> {
  const tasks: string[] = [];
  if (presentation.formatType === 'PDF' && presentation.contentDocumentId) {
    tasks.push(
      `/sfc/servlet.shepherd/document/download/${encodeURIComponent(presentation.contentDocumentId)}`
    );
  }
  for (const seq of presentation.sequences ?? []) {
    const url = seq.slideImageUrl || seq.thumbnailUrl;
    if (url) tasks.push(url);
  }
  let completed = 0;
  for (const path of tasks) {
    try {
      await fetchClmAssetBlob(path, auth, true);
    } catch (e) {
      console.warn('CLM prefetch failed', presentation.name, path, e);
    }
    completed += 1;
    onProgress?.(completed, tasks.length);
  }
}

export async function prefetchAllPresentations(
  presentations: ClmPresentationAsset[],
  auth: ClmAuth,
  onProgress?: (completed: number, total: number, name?: string) => void
): Promise<void> {
  let done = 0;
  const total = presentations.length;
  for (const p of presentations) {
    await prefetchPresentationAssets(p, auth, (c, t) => {
      onProgress?.(done, total, p.name);
      if (c === t) done += 1;
    });
  }
}
