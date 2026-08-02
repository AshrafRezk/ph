/**
 * Shared Leaflet map for Today Plan, Planner, and future map:true fidelity entries.
 * Leaflet CSS is also injected into Lit shadow via mirror-styles (document import alone
 * is not enough for shadow DOM).
 */
import L from 'leaflet';
import 'leaflet/dist/leaflet.css';

export interface OsrMapMarker {
  id: string;
  lat: number;
  lon: number;
  label?: string;
  kind?: 'hcp' | 'hco' | 'you' | 'other' | 'risk-high' | 'risk-med' | 'risk-low';
  selected?: boolean;
}

export interface OsrMapHandle {
  map: L.Map;
  setMarkers: (markers: OsrMapMarker[]) => void;
  /** Draw a driving/route polyline. Pass [] or null to clear. */
  setRoute: (latLngs: [number, number][] | null, opts?: { color?: string; fit?: boolean }) => void;
  flyToId: (id: string) => void;
  invalidateSize: () => void;
  destroy: () => void;
}

const KIND_COLOR: Record<string, string> = {
  hcp: '#0176d3',
  hco: '#6a1b9a',
  you: '#2e844a',
  other: '#706e6b',
  'risk-high': '#ba0517',
  'risk-med': '#fe9339',
  'risk-low': '#2e844a'
};

const CAIRO: [number, number] = [30.0444, 31.2357];

function isFiniteLatLng(lat: unknown, lon: unknown): lat is number {
  return Number.isFinite(Number(lat)) && Number.isFinite(Number(lon));
}

function safeCenter(center?: [number, number] | null): [number, number] {
  if (center && isFiniteLatLng(center[0], center[1])) {
    return [Number(center[0]), Number(center[1])];
  }
  return CAIRO;
}

function pinIcon(kind: string, selected: boolean): L.DivIcon {
  const color = KIND_COLOR[kind] ?? KIND_COLOR.other;
  if (kind === 'you') {
    return L.divIcon({
      className: 'osr-map-pin osr-map-pin-you',
      html: `<span style="display:block;width:18px;height:18px;border-radius:50%;background:#2e844a;border:3px solid #fff;box-shadow:0 0 0 3px rgba(46,132,74,.35),0 1px 4px rgba(0,0,0,.35)"></span>`,
      iconSize: [18, 18],
      iconAnchor: [9, 9]
    });
  }
  const size = selected ? 16 : 12;
  return L.divIcon({
    className: 'osr-map-pin',
    html: `<span style="display:block;width:${size}px;height:${size}px;border-radius:50%;background:${color};border:2px solid #fff;box-shadow:0 1px 4px rgba(0,0,0,.35)"></span>`,
    iconSize: [size, size],
    iconAnchor: [size / 2, size / 2]
  });
}

export function createOsrMap(
  el: HTMLElement,
  opts: {
    center?: [number, number];
    zoom?: number;
    markers?: OsrMapMarker[];
    onMarkerClick?: (id: string) => void;
    fitBounds?: boolean;
  } = {}
): OsrMapHandle {
  // Ensure host has a paint size before Leaflet measures it
  if (!el.style.minHeight) el.style.minHeight = '24rem';
  if (!el.style.height) el.style.height = '100%';
  if (!el.style.width) el.style.width = '100%';

  let destroyed = false;
  const timers: number[] = [];
  const scheduleInvalidate = (map: L.Map) => {
    if (destroyed) return;
    requestAnimationFrame(() => {
      if (destroyed) return;
      try {
        map.invalidateSize({ animate: false });
      } catch {
        /* map may already be torn down */
      }
      timers.push(
        window.setTimeout(() => {
          if (destroyed) return;
          try {
            map.invalidateSize({ animate: false });
          } catch {
            /* ignore */
          }
        }, 120)
      );
      timers.push(
        window.setTimeout(() => {
          if (destroyed) return;
          try {
            map.invalidateSize({ animate: false });
          } catch {
            /* ignore */
          }
        }, 400)
      );
    });
  };

  const map = L.map(el, {
    zoomControl: true,
    attributionControl: true
  }).setView(safeCenter(opts.center), opts.zoom ?? 12);

  L.tileLayer('https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png', {
    maxZoom: 19,
    attribution: '&copy; OpenStreetMap'
  }).addTo(map);

  const layer = L.layerGroup().addTo(map);
  const routeLayer = L.layerGroup().addTo(map);
  const byId = new Map<string, L.Marker>();
  let lastRoute: [number, number][] | null = null;

  const setMarkers = (markers: OsrMapMarker[]) => {
    if (destroyed) return;
    layer.clearLayers();
    byId.clear();
    const latLngs: L.LatLngExpression[] = [];
    for (const m of markers) {
      if (!isFiniteLatLng(m.lat, m.lon)) continue;
      const marker = L.marker([m.lat, m.lon], {
        icon: pinIcon(m.kind ?? 'hcp', !!m.selected),
        title: m.label ?? m.id,
        zIndexOffset: m.kind === 'you' ? 600 : m.selected ? 400 : 0
      });
      if (m.label) marker.bindPopup(m.label);
      marker.on('click', () => opts.onMarkerClick?.(m.id));
      marker.addTo(layer);
      byId.set(m.id, marker);
      latLngs.push([m.lat, m.lon]);
    }
    if ((opts.fitBounds ?? true) && !lastRoute?.length) {
      try {
        if (latLngs.length > 1) {
          const bounds = L.latLngBounds(latLngs);
          if (bounds.isValid()) {
            map.fitBounds(bounds, { padding: [28, 28], maxZoom: 14 });
          }
        } else if (latLngs.length === 1) {
          map.setView(latLngs[0] as L.LatLngExpression, 14);
        }
      } catch {
        /* ignore bad viewport */
      }
    }
    scheduleInvalidate(map);
  };

  const setRoute = (
    latLngs: [number, number][] | null,
    routeOpts: { color?: string; fit?: boolean } = {}
  ) => {
    if (destroyed) return;
    routeLayer.clearLayers();
    const clean = (latLngs || []).filter((p) => isFiniteLatLng(p[0], p[1])) as [number, number][];
    lastRoute = clean.length ? clean : null;
    if (!lastRoute || lastRoute.length < 2) {
      lastRoute = null;
      scheduleInvalidate(map);
      return;
    }
    try {
      const line = L.polyline(lastRoute, {
        color: routeOpts.color ?? '#2e7d32',
        weight: 5,
        opacity: 0.85
      });
      line.addTo(routeLayer);
      if (routeOpts.fit !== false) {
        const bounds = line.getBounds();
        if (bounds.isValid()) {
          map.fitBounds(bounds.pad(0.15));
        }
      }
    } catch {
      lastRoute = null;
    }
    scheduleInvalidate(map);
  };

  if (opts.markers?.length) setMarkers(opts.markers);
  scheduleInvalidate(map);

  let ro: ResizeObserver | null = null;
  if (typeof ResizeObserver !== 'undefined') {
    ro = new ResizeObserver(() => {
      if (!destroyed) scheduleInvalidate(map);
    });
    ro.observe(el);
  }

  return {
    map,
    setMarkers,
    setRoute,
    flyToId: (id: string) => {
      if (destroyed) return;
      const m = byId.get(id);
      if (m) {
        try {
          map.flyTo(m.getLatLng(), Math.max(map.getZoom(), 15), { duration: 0.45 });
          m.openPopup();
        } catch {
          /* ignore */
        }
      }
    },
    invalidateSize: () => scheduleInvalidate(map),
    destroy: () => {
      destroyed = true;
      for (const t of timers) window.clearTimeout(t);
      timers.length = 0;
      ro?.disconnect();
      ro = null;
      try {
        map.remove();
      } catch {
        /* ignore */
      }
    }
  };
}

export function pinKindFromRecordType(recordTypeName?: string, developerName?: string): 'hcp' | 'hco' {
  const s = `${recordTypeName ?? ''} ${developerName ?? ''}`.toLowerCase();
  if (s.includes('pharmac') || s.includes('hco') || s.includes('hospital') || s.includes('institution')) {
    return 'hco';
  }
  return 'hcp';
}
