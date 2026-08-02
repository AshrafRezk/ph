/**
 * Assemble a CloudAstick support ZIP from local sync logs + diagnostics.
 */
import {
  type SqlExecutor,
  listLogs,
  listOutboxByStatus,
  listOpenConflicts,
  listSyncState,
  listPendingOutbox
} from '@osr/db';
import { Capacitor } from '@capacitor/core';
import { Device } from '@capacitor/device';
import { Filesystem, Directory } from '@capacitor/filesystem';
import { bytesToBase64, makeZip } from './zip';

export type SupportExportMeta = {
  appVersion: string;
  syncMode?: string | null;
  currentApp?: string | null;
  online?: boolean;
};

export type SupportExportResult = {
  fileName: string;
  byteLength: number;
  /** Where the file was written (native) or 'download' (web). */
  savedTo: string;
};

function pretty(value: unknown): string {
  return JSON.stringify(value, null, 2);
}

async function deviceInfo(): Promise<Record<string, unknown>> {
  try {
    const [info, id] = await Promise.all([Device.getInfo(), Device.getId()]);
    return {
      platform: info.platform,
      operatingSystem: info.operatingSystem,
      osVersion: info.osVersion,
      model: info.model,
      manufacturer: info.manufacturer,
      isVirtual: info.isVirtual,
      webViewVersion: info.webViewVersion,
      deviceId: id.identifier,
      capacitorPlatform: Capacitor.getPlatform(),
      isNative: Capacitor.isNativePlatform()
    };
  } catch (e) {
    return {
      capacitorPlatform: Capacitor.getPlatform(),
      isNative: Capacitor.isNativePlatform(),
      error: e instanceof Error ? e.message : String(e)
    };
  }
}

function toArrayBuffer(bytes: Uint8Array): ArrayBuffer {
  const copy = new Uint8Array(bytes.byteLength);
  copy.set(bytes);
  return copy.buffer;
}

function downloadBlob(bytes: Uint8Array, fileName: string) {
  const blob = new Blob([toArrayBuffer(bytes)], { type: 'application/zip' });
  const url = URL.createObjectURL(blob);
  const a = document.createElement('a');
  a.href = url;
  a.download = fileName;
  a.rel = 'noopener';
  document.body.appendChild(a);
  a.click();
  a.remove();
  setTimeout(() => URL.revokeObjectURL(url), 2000);
}

async function tryNativeShare(bytes: Uint8Array, fileName: string): Promise<string | null> {
  if (!Capacitor.isNativePlatform()) return null;
  await Filesystem.writeFile({
    path: fileName,
    data: bytesToBase64(bytes),
    directory: Directory.Cache
  });
  const { uri } = await Filesystem.getUri({
    path: fileName,
    directory: Directory.Cache
  });

  // Prefer Web Share with files when the WebView supports it.
  try {
    const file = new File([toArrayBuffer(bytes)], fileName, { type: 'application/zip' });
    const nav = navigator as Navigator & {
      canShare?: (data: ShareData & { files?: File[] }) => boolean;
      share?: (data: ShareData & { files?: File[] }) => Promise<void>;
    };
    if (nav.canShare?.({ files: [file] }) && nav.share) {
      await nav.share({
        files: [file],
        title: 'OSR support logs',
        text: 'Offline Salesforce Runtime support bundle for CloudAstick'
      });
      return `shared:${uri}`;
    }
  } catch {
    /* fall through — file remains in Cache */
  }

  return uri;
}

export async function exportSupportBundle(
  db: SqlExecutor,
  meta: SupportExportMeta
): Promise<SupportExportResult> {
  const stamp = new Date().toISOString().replace(/[:.]/g, '-').slice(0, 19);
  const fileName = `osr-support-${stamp}.zip`;

  const [logs, failedOutbox, pendingOutbox, conflicts, syncState, device] = await Promise.all([
    listLogs(db, { limit: 500 }),
    listOutboxByStatus(db, ['failed', 'conflict'], 200),
    listPendingOutbox(db, 200),
    listOpenConflicts(db),
    listSyncState(db),
    deviceInfo()
  ]);

  const syncLogs = logs.filter((l) => l.category === 'sync');
  const readme = [
    'Offline Salesforce Runtime — support bundle',
    'Send this ZIP to the CloudAstick team for sync troubleshooting.',
    '',
    `Generated: ${new Date().toISOString()}`,
    `App version: ${meta.appVersion}`,
    `Sync mode: ${meta.syncMode ?? 'unknown'}`,
    `Current app: ${meta.currentApp ?? 'n/a'}`,
    `Online: ${meta.online ?? 'n/a'}`,
    '',
    'Contents:',
    '  README.txt           — this file',
    '  device.json          — device / OS / WebView',
    '  app-info.json        — app + session metadata (no tokens)',
    '  sync-logs.json       — local sync issue log table',
    '  outbox-failed.json   — failed / conflict outbox rows',
    '  outbox-pending.json  — pending outbox rows',
    '  conflicts.json       — open conflict records',
    '  sync-state.json      — per-channel sync cursors'
  ].join('\n');

  const zip = makeZip([
    { name: 'README.txt', data: readme },
    { name: 'device.json', data: pretty(device) },
    {
      name: 'app-info.json',
      data: pretty({
        appVersion: meta.appVersion,
        syncMode: meta.syncMode ?? null,
        currentApp: meta.currentApp ?? null,
        online: meta.online ?? null,
        generatedAt: new Date().toISOString(),
        logCount: logs.length,
        syncLogCount: syncLogs.length,
        failedOutboxCount: failedOutbox.length,
        pendingOutboxCount: pendingOutbox.length,
        openConflicts: conflicts.length
      })
    },
    { name: 'sync-logs.json', data: pretty(syncLogs.length ? syncLogs : logs) },
    { name: 'outbox-failed.json', data: pretty(failedOutbox) },
    { name: 'outbox-pending.json', data: pretty(pendingOutbox) },
    { name: 'conflicts.json', data: pretty(conflicts) },
    { name: 'sync-state.json', data: pretty(syncState) }
  ]);

  const nativeUri = await tryNativeShare(zip, fileName);
  if (nativeUri) {
    return { fileName, byteLength: zip.byteLength, savedTo: nativeUri };
  }

  downloadBlob(zip, fileName);
  return { fileName, byteLength: zip.byteLength, savedTo: 'download' };
}
