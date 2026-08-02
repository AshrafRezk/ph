/**
 * Lightweight routing helpers for offline Planner / Today Plan maps.
 * Prefers OSRM when online; falls back to straight-line legs via haversine.
 */
import { haversineKm } from '../apex-cache';

const OSRM_BASE = 'https://router.project-osrm.org';

export type RoutePoint = { lat: number; lon: number };

export type RouteLeg = {
  distanceKm: number;
  durationMin: number;
};

export type RouteResult = {
  distanceKm: number;
  durationMin: number;
  /** Leaflet-friendly [lat, lon][] including intermediates from OSRM when available. */
  latLngs: [number, number][];
  legs: RouteLeg[];
  source: 'osrm' | 'haversine';
};

export async function getCurrentPosition(): Promise<RoutePoint | null> {
  const finite = (lat: number, lon: number): RoutePoint | null =>
    Number.isFinite(lat) && Number.isFinite(lon) ? { lat, lon } : null;
  try {
    const { Geolocation } = await import('@capacitor/geolocation');
    const pos = await Geolocation.getCurrentPosition({
      enableHighAccuracy: true,
      timeout: 12000,
      maximumAge: 60_000
    });
    return finite(pos.coords.latitude, pos.coords.longitude);
  } catch {
    /* fall through to browser geolocation */
  }
  if (typeof navigator === 'undefined' || !navigator.geolocation) return null;
  return new Promise((resolve) => {
    navigator.geolocation.getCurrentPosition(
      (position) => resolve(finite(position.coords.latitude, position.coords.longitude)),
      () => resolve(null),
      { enableHighAccuracy: true, timeout: 12000, maximumAge: 60_000 }
    );
  });
}

function buildCoordPath(points: RoutePoint[]): string {
  return points.map((p) => `${p.lon},${p.lat}`).join(';');
}

function haversineRoute(points: RoutePoint[]): RouteResult {
  const latLngs: [number, number][] = points.map((p) => [p.lat, p.lon]);
  const legs: RouteLeg[] = [];
  let km = 0;
  for (let i = 1; i < points.length; i++) {
    const d = haversineKm(points[i - 1].lat, points[i - 1].lon, points[i].lat, points[i].lon);
    const durationMin = Math.max(1, Math.round(d * 1.4));
    legs.push({ distanceKm: Math.round(d * 10) / 10, durationMin });
    km += d;
  }
  // OSRM path is indexed by waypoint; include a synthetic first leg from "start"
  // so schedule packing can use legs[i] for travel into stop i.
  const paddedLegs: RouteLeg[] = [{ distanceKm: 0, durationMin: 0 }, ...legs];
  return {
    distanceKm: Math.round(km * 10) / 10,
    durationMin: Math.round(km * 1.4),
    latLngs,
    legs: paddedLegs,
    source: 'haversine'
  };
}

export async function fetchDrivingRoute(points: RoutePoint[]): Promise<RouteResult | null> {
  const valid = points.filter((p) => Number.isFinite(p.lat) && Number.isFinite(p.lon));
  if (valid.length < 2) return null;
  try {
    const url = `${OSRM_BASE}/route/v1/driving/${buildCoordPath(valid)}?overview=full&geometries=geojson`;
    const response = await fetch(url);
    const data = (await response.json()) as {
      code?: string;
      routes?: {
        distance?: number;
        duration?: number;
        geometry?: { coordinates?: [number, number][] };
        legs?: { distance?: number; duration?: number }[];
      }[];
    };
    const route = data.routes?.[0];
    if (data.code !== 'Ok' || !route?.geometry?.coordinates?.length) {
      return haversineRoute(valid);
    }
    const latLngs: [number, number][] = route.geometry.coordinates
      .map(([lng, lat]) => [lat, lng] as [number, number])
      .filter((p) => Number.isFinite(p[0]) && Number.isFinite(p[1]));
    if (latLngs.length < 2) {
      return haversineRoute(valid);
    }
    const legs: RouteLeg[] = [
      { distanceKm: 0, durationMin: 0 },
      ...(route.legs || []).map((leg) => ({
        distanceKm: Math.round(((leg.distance || 0) / 1000) * 10) / 10,
        durationMin: Math.max(1, Math.round((leg.duration || 0) / 60))
      }))
    ];
    return {
      distanceKm: Math.round(((route.distance || 0) / 1000) * 10) / 10,
      durationMin: Math.max(1, Math.round((route.duration || 0) / 60)),
      latLngs,
      legs,
      source: 'osrm'
    };
  } catch {
    return haversineRoute(valid);
  }
}

/** Pack visit start/end times: keep first start, then end_i + drive into next. */
export function computeScheduleFromRoute(
  ordered: { id: string; startDateTime?: string; durationMs?: number }[],
  legs: RouteLeg[],
  defaultVisitMs = 60 * 60 * 1000
): { visitId: string; start: Date; end: Date }[] {
  if (!ordered.length) return [];
  let cursor = ordered[0].startDateTime ? new Date(ordered[0].startDateTime) : new Date();
  if (Number.isNaN(cursor.getTime())) {
    cursor = new Date();
    cursor.setHours(9, 0, 0, 0);
  }
  const schedules: { visitId: string; start: Date; end: Date }[] = [];
  for (let i = 0; i < ordered.length; i++) {
    if (i > 0) {
      const driveMs = (legs[i]?.durationMin || 0) * 60 * 1000;
      cursor = new Date(cursor.getTime() + driveMs);
    }
    const durationMs = ordered[i].durationMs || defaultVisitMs;
    const start = new Date(cursor.getTime());
    const end = new Date(start.getTime() + durationMs);
    schedules.push({ visitId: ordered[i].id, start, end });
    cursor = end;
  }
  return schedules;
}
