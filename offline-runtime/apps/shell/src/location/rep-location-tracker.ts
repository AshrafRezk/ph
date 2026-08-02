/**
 * Capacitor-backed GPS + device tracking for OSR shell.
 * Mirrors online repLocationPublisher throttle (90s / 100m) and queues offline.
 */
import { Geolocation, type Position, type CallbackID } from '@capacitor/geolocation';
import { Device } from '@capacitor/device';
import { App } from '@capacitor/app';
import {
  type SqlExecutor,
  enqueueOutbox,
  insertLocationTrail,
  getLatestLocationTrail,
  listUnsyncedLocationTrail,
  markLocationTrailSynced,
  kvGet,
  kvSet,
  type LocationTrailPoint
} from '@osr/db';

const UPLOAD_INTERVAL_MS = 90_000;
const MIN_MOVE_KM = 0.1;
const SHARING_KEY = 'rep_location_sharing';

export type DeviceSnapshot = {
  model: string;
  os: string;
  appVersion: string;
  deviceId: string;
};

export type LocationTrackerState = {
  sharing: boolean;
  permissionDenied: boolean;
  lastPoint: LocationTrailPoint | null;
  error: string | null;
  watching: boolean;
};

type Listener = (state: LocationTrackerState) => void;

function haversineKm(lat1: number, lon1: number, lat2: number, lon2: number): number {
  const toRad = (d: number) => (d * Math.PI) / 180;
  const R = 6371;
  const dLat = toRad(lat2 - lat1);
  const dLon = toRad(lon2 - lon1);
  const a =
    Math.sin(dLat / 2) ** 2 +
    Math.cos(toRad(lat1)) * Math.cos(toRad(lat2)) * Math.sin(dLon / 2) ** 2;
  return 2 * R * Math.asin(Math.sqrt(a));
}

async function readDeviceSnapshot(): Promise<DeviceSnapshot> {
  try {
    const [info, id, appInfo] = await Promise.all([
      Device.getInfo(),
      Device.getId(),
      App.getInfo().catch(() => ({ version: 'web' } as { version: string }))
    ]);
    return {
      model: info.model || info.name || 'Unknown',
      os: `${info.operatingSystem || 'unknown'} ${info.osVersion || ''}`.trim(),
      appVersion: appInfo.version || '0.0.0',
      deviceId: id.identifier || 'unknown'
    };
  } catch {
    return {
      model: 'Unknown',
      os: typeof navigator !== 'undefined' ? navigator.platform || 'web' : 'web',
      appVersion: '0.0.0',
      deviceId: 'web'
    };
  }
}

export class RepLocationTracker {
  private db: SqlExecutor | null = null;
  private watchId: CallbackID | null = null;
  private lastUploadedAt = 0;
  private lastUploadedPosition: { latitude: number; longitude: number } | null = null;
  private device: DeviceSnapshot | null = null;
  private listeners = new Set<Listener>();
  private state: LocationTrackerState = {
    sharing: true,
    permissionDenied: false,
    lastPoint: null,
    error: null,
    watching: false
  };

  async init(db: SqlExecutor): Promise<void> {
    this.db = db;
    const sharing = await kvGet(db, SHARING_KEY);
    this.state.sharing = sharing !== '0';
    this.state.lastPoint = await getLatestLocationTrail(db);
    this.device = await readDeviceSnapshot();
    this.emit();
    if (this.state.sharing && !this.state.permissionDenied) {
      await this.start();
    }
  }

  subscribe(listener: Listener): () => void {
    this.listeners.add(listener);
    listener(this.state);
    return () => this.listeners.delete(listener);
  }

  getState(): LocationTrackerState {
    return { ...this.state };
  }

  async setSharing(enabled: boolean): Promise<void> {
    this.state.sharing = enabled;
    if (this.db) await kvSet(this.db, SHARING_KEY, enabled ? '1' : '0');
    if (enabled) {
      await this.start();
    } else {
      await this.stop();
    }
    this.emit();
  }

  async start(): Promise<void> {
    if (this.watchId != null || this.state.permissionDenied || !this.state.sharing) return;
    try {
      const perm = await Geolocation.requestPermissions();
      if (perm.location === 'denied') {
        this.state.permissionDenied = true;
        this.state.error = 'Location permission denied';
        this.state.watching = false;
        this.emit();
        return;
      }
      this.watchId = await Geolocation.watchPosition(
        { enableHighAccuracy: true, timeout: 15000 },
        (position, err) => {
          if (err) {
            this.handleError(err);
            return;
          }
          if (position) void this.handlePosition(position);
        }
      );
      this.state.watching = true;
      this.state.error = null;
      this.emit();
    } catch (e) {
      this.handleError(e);
    }
  }

  async stop(): Promise<void> {
    if (this.watchId != null) {
      try {
        await Geolocation.clearWatch({ id: this.watchId });
      } catch {
        /* ignore */
      }
      this.watchId = null;
    }
    this.state.watching = false;
    this.emit();
  }

  /** Flush unsynced trail points into outbox for OsrOutboxService location.upsert */
  async flushToOutbox(): Promise<number> {
    if (!this.db) return 0;
    const pending = await listUnsyncedLocationTrail(this.db, 25);
    let n = 0;
    for (const point of pending) {
      await enqueueOutbox(this.db, {
        op: 'location.upsert',
        objectApi: 'Rep_Location_Snapshot__c',
        recordId: point.id,
        payload: {
          action: 'repLocation.upsert',
          latitude: point.latitude,
          longitude: point.longitude,
          accuracyMeters: point.accuracyMeters,
          recordedAt: point.recordedAt,
          source: point.source || 'Mobile',
          deviceModel: point.deviceModel,
          deviceOs: point.deviceOs,
          appVersion: point.appVersion,
          deviceId: point.deviceId
        }
      });
      await markLocationTrailSynced(this.db, point.id);
      n++;
    }
    return n;
  }

  private async handlePosition(position: Position): Promise<void> {
    if (!this.db || !this.state.sharing) return;
    const latitude = position.coords.latitude;
    const longitude = position.coords.longitude;
    const accuracy = position.coords.accuracy;
    const now = Date.now();
    const movedEnough =
      !this.lastUploadedPosition ||
      haversineKm(
        this.lastUploadedPosition.latitude,
        this.lastUploadedPosition.longitude,
        latitude,
        longitude
      ) >= MIN_MOVE_KM;
    const intervalElapsed = now - this.lastUploadedAt >= UPLOAD_INTERVAL_MS;
    if (!movedEnough && !intervalElapsed) return;

    if (!this.device) this.device = await readDeviceSnapshot();
    const recordedAt = new Date(position.timestamp || now).toISOString();
    const trailId = await insertLocationTrail(this.db, {
      latitude,
      longitude,
      accuracyMeters: accuracy,
      recordedAt,
      deviceModel: this.device.model,
      deviceOs: this.device.os,
      appVersion: this.device.appVersion,
      deviceId: this.device.deviceId,
      source: 'Mobile'
    });

    await enqueueOutbox(this.db, {
      op: 'location.upsert',
      objectApi: 'Rep_Location_Snapshot__c',
      recordId: trailId,
      payload: {
        action: 'repLocation.upsert',
        latitude,
        longitude,
        accuracyMeters: accuracy,
        recordedAt,
        source: 'Mobile',
        deviceModel: this.device.model,
        deviceOs: this.device.os,
        appVersion: this.device.appVersion,
        deviceId: this.device.deviceId
      }
    });
    await markLocationTrailSynced(this.db, trailId);

    this.lastUploadedAt = now;
    this.lastUploadedPosition = { latitude, longitude };
    this.state.lastPoint = await getLatestLocationTrail(this.db);
    this.state.error = null;
    this.emit();
  }

  private handleError(err: unknown): void {
    const message = err instanceof Error ? err.message : String(err ?? 'Location error');
    if (message.toLowerCase().includes('denied')) {
      this.state.permissionDenied = true;
      void this.stop();
    }
    this.state.error = message;
    this.emit();
  }

  private emit(): void {
    const snapshot = { ...this.state };
    for (const listener of this.listeners) {
      try {
        listener(snapshot);
      } catch {
        /* ignore */
      }
    }
  }
}

export const repLocationTracker = new RepLocationTracker();
