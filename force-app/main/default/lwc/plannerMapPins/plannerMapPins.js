import { loadScript, loadStyle } from 'lightning/platformResourceLoader';
import CLOUDASTICK_LOGO from '@salesforce/resourceUrl/CloudastickLogo';
import { accountTypeIconUrl } from 'c/accountTypeTheme';

export const HCP_RECORD_TYPES = new Set([
    'SDO_PersonAccounts',
    'Medical_Professional_HCP',
    'PersonAccount',
    'Business_Contact'
]);

export const HCO_RECORD_TYPES = new Set(['Institution_HCO', 'Pharmacy']);

export const PIN_COLORS = {
    hcp: '#3f7de5',
    hco: '#fdbf29',
    pharmacy: '#176935',
    pharmacyOut: '#ef6c00'
};

export function getPinColor(pinKind) {
    if (pinKind === 'pharmacy') {
        return PIN_COLORS.pharmacy;
    }
    if (pinKind === 'hco') {
        return PIN_COLORS.hco;
    }
    return PIN_COLORS.hcp;
}

export const HCP_PIN_SVG =
    '<svg viewBox="0 0 24 24" aria-hidden="true"><path fill="#fff" d="M12 12c2.2 0 4-1.8 4-4s-1.8-4-4-4-4 1.8-4 4 1.8 4 4 4zm0 2c-2.7 0-8 1.3-8 4v2h16v-2c0-2.7-5.3-4-8-4z"/></svg>';

export const HCO_PIN_SVG =
    '<svg viewBox="0 0 24 24" aria-hidden="true"><path fill="#fff" d="M12 7V3H2v18h20V7H12zm-2 12H6v-2h4v2zm0-4H6v-2h4v2zm0-4H6V9h4v2zm0-4H6V5h4v2zm6 12h-4v-2h4v2zm0-4h-4v-2h4v2zm0-4h-4V9h4v2zm0-4h-4V5h4v2zm8 12h-6v-2h2v-2h-2v-2h2v-2h-2V9h6v10zm-2-8h-2v2h2v-2zm0 4h-2v2h2v-2z"/></svg>';

export const OSM_TILE_URL = 'https://tile.openstreetmap.org/{z}/{x}/{y}.png';
export const MAP_TILE_CACHE = 'map-tiles-v1';
const MAX_PREFETCH_TILES = 220;
const PREFETCH_ZOOMS = [12, 13, 14];
export const MAP_INTELLIGENCE_ATTRIBUTION = 'Cloudastick Map Intelligence';
export const OSM_ATTRIBUTION = MAP_INTELLIGENCE_ATTRIBUTION;
export const CARTO_TILE_URL = 'https://basemaps.cartocdn.com/light_all/{z}/{x}/{y}.png';
export const CARTO_ATTRIBUTION =
    '&copy; <a href="https://www.openstreetmap.org/copyright">OpenStreetMap</a> contributors &copy; <a href="https://carto.com/attributions">CARTO</a>';
export const ESRI_STREET_TILE_URL =
    'https://server.arcgisonline.com/ArcGIS/rest/services/World_Street_Map/MapServer/tile/{z}/{y}/{x}';
export const ESRI_STREET_ATTRIBUTION =
    'Tiles &copy; Esri &mdash; Source: Esri, DeLorme, NAVTEQ, USGS, Intermap, iPC, NRCAN, Esri Japan, METI, Esri China (Hong Kong), Esri (Thailand), TomTom';

const PHARMACY_PIN_SIZE = [32, 42];
const PHARMACY_PIN_ANCHOR = [16, 40];
const PHARMACY_PIN_POPUP = [0, -34];
const MAP_FOOTNOTE_CSS =
    '.leaflet-bottom.leaflet-right .leaflet-control-attribution{' +
    'display:flex!important;align-items:center;gap:4px;margin:0!important;padding:2px 6px!important;' +
    'background:rgba(255,255,255,.82)!important;color:#333!important;border:0;border-radius:0;' +
    'box-shadow:none!important;font:11px/1.35 "Helvetica Neue",Arial,sans-serif!important;' +
    'white-space:nowrap;max-width:min(70vw,260px)}' +
    '.leaflet-control-attribution .cloudastick-map-logo{height:18px;width:18px;object-fit:contain;' +
    'display:inline-block;vertical-align:middle;flex:0 0 18px;background:#000;border-radius:3px}' +
    '.leaflet-control-attribution .cloudastick-map-label{font-weight:400}';

const PHARMACY_PIN_RESET_CSS =
    '.pharmacy-map-pin{background:transparent!important;border:none!important;box-shadow:none!important}' +
    '.pharmacy-pin{position:relative;width:32px;height:42px;background:transparent;border:none}' +
    '.pharmacy-pin-body{position:absolute;left:5px;top:2px;width:22px;height:22px;border:2.5px solid #fff;border-radius:50% 50% 50% 0;transform:rotate(-45deg);box-shadow:0 2px 6px rgba(0,0,0,.45)}' +
    '.pharmacy-pin-in .pharmacy-pin-body{background:#176935}' +
    '.pharmacy-pin-out .pharmacy-pin-body{background:#ef6c00}' +
    '.pharmacy-pin-center .pharmacy-pin-body{background:#176935}' +
    '.pharmacy-pin-cross-h{position:absolute;left:50%;top:11px;width:12px;height:3.5px;margin-left:-6px;background:#fff;border-radius:1px}' +
    '.pharmacy-pin-cross-v{position:absolute;left:50%;top:7px;width:3.5px;height:12px;margin-left:-1.75px;background:#fff;border-radius:1px}' +
    '.pharmacy-pin-dot{position:absolute;left:50%;top:10px;width:8px;height:8px;margin-left:-4px;background:#fff;border-radius:50%}';

const pinIconCache = new Map();

export function resolveAccountPinKind(recordTypeDeveloperName, recordTypeName) {
    const developerName = recordTypeDeveloperName || '';
    if (HCP_RECORD_TYPES.has(developerName)) {
        return 'hcp';
    }
    if (HCO_RECORD_TYPES.has(developerName)) {
        return 'hco';
    }
    const label = (recordTypeName || '').toLowerCase();
    if (label.includes('hcp') || label.includes('professional') || label.includes('person')) {
        return 'hcp';
    }
    if (
        label.includes('hco') ||
        label.includes('institution') ||
        label.includes('pharmacy') ||
        label.includes('clinic')
    ) {
        return 'hco';
    }
    return 'hcp';
}

export function resolveAccountTypeLabel(pinKind, recordTypeName) {
    if (recordTypeName) {
        return recordTypeName;
    }
    if (pinKind === 'pharmacy') {
        return 'Pharmacy';
    }
    if (pinKind === 'hco') {
        return 'Healthcare organization';
    }
    if (pinKind === 'hcp') {
        return 'Healthcare professional';
    }
    return 'Account';
}

export function resolveAccountListKind(recordTypeDeveloperName, recordTypeName) {
    const developerName = recordTypeDeveloperName || '';
    const label = (recordTypeName || '').toLowerCase();
    if (developerName === 'Pharmacy' || label.includes('pharmacy')) {
        return {
            kind: 'pharmacy',
            iconName: 'utility:store',
            label: recordTypeName || 'Pharmacy'
        };
    }
    if (
        HCP_RECORD_TYPES.has(developerName) ||
        label.includes('hcp') ||
        label.includes('professional') ||
        label.includes('person')
    ) {
        return {
            kind: 'hcp',
            iconName: 'utility:user',
            label: recordTypeName || 'HCP'
        };
    }
    if (
        HCO_RECORD_TYPES.has(developerName) ||
        label.includes('hco') ||
        label.includes('institution') ||
        label.includes('clinic')
    ) {
        return {
            kind: 'hco',
            iconName: 'utility:home',
            label: recordTypeName || 'HCO'
        };
    }
    return {
        kind: 'account',
        iconName: 'utility:company',
        label: recordTypeName || 'Account'
    };
}

export function createVisitPinIcon(pinKind, leaflet, isOutlier = false) {
    const cacheKey = `${pinKind}${isOutlier ? '-outlier' : ''}`;
    if (pinIconCache.has(cacheKey)) {
        return pinIconCache.get(cacheKey);
    }

    let icon;
    if (pinKind === 'unplanned') {
        icon = leaflet.divIcon({
            className: 'map-pin-icon-shell',
            html: '<div class="map-pin-marker map-pin-marker-unplanned" title="No visit planned"></div>',
            iconSize: [14, 14],
            iconAnchor: [7, 7],
            popupAnchor: [0, -8]
        });
    } else {
        const kind = pinKind === 'pharmacy' || pinKind === 'hco' || pinKind === 'hcp' ? pinKind : 'hcp';
        const titles = { pharmacy: 'Pharmacy', hco: 'HCO', hcp: 'HCP' };
        const colors = { pharmacy: '#176935', hco: '#fdbf29', hcp: '#3f7de5' };
        const outlierClass = isOutlier ? ' map-pin-marker-outlier' : '';
        const title = isOutlier ? 'Route outlier — far from other stops' : titles[kind];
        const glyph = accountTypeIconUrl(kind);
        icon = leaflet.divIcon({
            className: 'map-pin-icon-shell',
            html:
                `<div class="map-pin-marker map-pin-marker-${kind}${outlierClass}" title="${title}" ` +
                `style="width:30px;height:30px;border-radius:50%;background:#fff;border:2px solid ${colors[kind]};` +
                `box-shadow:0 2px 6px rgba(0,0,0,.35);display:flex;align-items:center;justify-content:center;">` +
                `<img src="${glyph}" alt="" style="width:20px;height:20px;object-fit:contain;" /></div>`,
            iconSize: [30, 30],
            iconAnchor: [15, 15],
            popupAnchor: [0, -16]
        });
    }

    pinIconCache.set(cacheKey, icon);
    return icon;
}

function pharmacyPinHtml(fillColor, glyph, toneClass) {
    const glyphHtml =
        glyph === 'dot'
            ? `<span class="pharmacy-pin-dot" style="position:absolute;left:50%;top:10px;width:8px;height:8px;margin-left:-4px;background:#fff;border-radius:50%;box-shadow:inset 0 0 0 2.5px ${fillColor}"></span>`
            : '<span class="pharmacy-pin-cross-h" style="position:absolute;left:50%;top:11px;width:12px;height:3.5px;margin-left:-6px;background:#fff;border-radius:1px"></span>' +
              '<span class="pharmacy-pin-cross-v" style="position:absolute;left:50%;top:7px;width:3.5px;height:12px;margin-left:-1.75px;background:#fff;border-radius:1px"></span>';

    return (
        `<div class="pharmacy-pin ${toneClass}" style="position:relative;width:32px;height:42px;background:transparent;border:none">` +
        `<div class="pharmacy-pin-body" style="position:absolute;left:5px;top:2px;width:22px;height:22px;background:${fillColor};border:2.5px solid #fff;border-radius:50% 50% 50% 0;transform:rotate(-45deg);box-shadow:0 2px 6px rgba(0,0,0,.45)"></div>` +
        glyphHtml +
        '</div>'
    );
}

function createTeardropIcon(cacheKey, fillColor, glyph, toneClass, leaflet) {
    if (pinIconCache.has(cacheKey)) {
        return pinIconCache.get(cacheKey);
    }
    const icon = leaflet.divIcon({
        className: 'pharmacy-map-pin',
        html: pharmacyPinHtml(fillColor, glyph, toneClass),
        iconSize: PHARMACY_PIN_SIZE,
        iconAnchor: PHARMACY_PIN_ANCHOR,
        popupAnchor: PHARMACY_PIN_POPUP
    });
    pinIconCache.set(cacheKey, icon);
    return icon;
}

export function styleNeighbourMapPin(marker) {
    const el = marker && (marker.getElement ? marker.getElement() : marker._icon);
    if (!el || !el.style) {
        return marker;
    }
    el.style.background = 'transparent';
    el.style.border = 'none';
    el.style.boxShadow = 'none';
    return marker;
}

export function fitNeighbourMapView(mapInstance, leaflet, center, points) {
    if (!mapInstance || !center) {
        return;
    }
    mapInstance.invalidateSize();
    const latlngs = [[center.lat, center.lng]];
    (points || []).forEach((point) => {
        if (point && Number.isFinite(point.lat) && Number.isFinite(point.lng)) {
            latlngs.push([point.lat, point.lng]);
        }
    });
    if (latlngs.length < 2) {
        mapInstance.setView([center.lat, center.lng], 14, { animate: false });
        return;
    }
    mapInstance.fitBounds(leaflet.latLngBounds(latlngs), {
        padding: [36, 36],
        maxZoom: 15,
        animate: false
    });
}

function injectPharmacyPinReset(mapInstance) {
    const pane = mapInstance && mapInstance.getContainer ? mapInstance.getContainer() : null;
    if (!pane || pane.querySelector('style[data-pharmacy-pins]')) {
        return;
    }
    const style = document.createElement('style');
    style.setAttribute('data-pharmacy-pins', 'true');
    style.textContent = PHARMACY_PIN_RESET_CSS;
    pane.appendChild(style);
}

export function createPharmacyPinIcon(inAccountList, leaflet) {
    const fillColor = inAccountList ? PIN_COLORS.pharmacy : PIN_COLORS.pharmacyOut;
    const cacheKey = inAccountList ? 'pharmacy-in-list' : 'pharmacy-out-of-list';
    const toneClass = inAccountList ? 'pharmacy-pin-in' : 'pharmacy-pin-out';
    return createTeardropIcon(cacheKey, fillColor, 'cross', toneClass, leaflet);
}

export function createAccountCenterPinIcon(leaflet) {
    return createTeardropIcon('pharmacy-center', PIN_COLORS.pharmacy, 'dot', 'pharmacy-pin-center', leaflet);
}

export async function ensureLeaflet(component, leafletResourceUrl) {
    if (window.L) {
        return window.L;
    }
    await loadStyle(component, `${leafletResourceUrl}/leaflet.css`);
    await loadScript(component, `${leafletResourceUrl}/leaflet.js`);
    delete window.L.Icon.Default.prototype._getIconUrl;
    window.L.Icon.Default.mergeOptions({
        iconRetinaUrl: `${leafletResourceUrl}/marker-icon-2x.png`,
        iconUrl: `${leafletResourceUrl}/marker-icon.png`,
        shadowUrl: `${leafletResourceUrl}/marker-shadow.png`
    });
    return window.L;
}

export function brandMapAttribution(mapInstance, leaflet) {
    addMapIntelligenceFootnote(mapInstance, leaflet);
}

function injectMapFootnoteCss(mapInstance) {
    const pane = mapInstance && mapInstance.getContainer ? mapInstance.getContainer() : null;
    if (!pane || pane.querySelector('style[data-cloudastick-footnote]')) {
        return;
    }
    const style = document.createElement('style');
    style.setAttribute('data-cloudastick-footnote', 'true');
    style.textContent = MAP_FOOTNOTE_CSS;
    pane.appendChild(style);
}

export function addMapIntelligenceFootnote(mapInstance, leaflet) {
    if (!mapInstance || !leaflet) {
        return;
    }
    injectMapFootnoteCss(mapInstance);
    const prefix =
        `<img class="cloudastick-map-logo" src="${CLOUDASTICK_LOGO}" alt="" />` +
        `<span class="cloudastick-map-label">${MAP_INTELLIGENCE_ATTRIBUTION}</span>`;
    if (mapInstance._cloudastickFootnote && mapInstance.removeControl) {
        try {
            mapInstance.removeControl(mapInstance._cloudastickFootnote);
        } catch (e) {
            /* ignore leftover custom banner */
        }
        mapInstance._cloudastickFootnote = null;
    }
    if (!mapInstance.attributionControl && leaflet.control && leaflet.control.attribution) {
        mapInstance.attributionControl = leaflet.control
            .attribution({ prefix, position: 'bottomright' })
            .addTo(mapInstance);
        return;
    }
    if (mapInstance.attributionControl && mapInstance.attributionControl.setPrefix) {
        mapInstance.attributionControl.setPrefix(prefix);
    }
}

export function addOsmTileLayer(mapInstance, leaflet) {
    const layer = createCachedOsmTileLayer(leaflet).addTo(mapInstance);
    addMapIntelligenceFootnote(mapInstance, leaflet);
    return layer;
}

function lngToTile(lng, zoom) {
    return Math.floor(((lng + 180) / 360) * 2 ** zoom);
}

function latToTile(lat, zoom) {
    const rad = (lat * Math.PI) / 180;
    return Math.floor(
        ((1 - Math.log(Math.tan(rad) + 1 / Math.cos(rad)) / Math.PI) / 2) * 2 ** zoom
    );
}

function osmTileUrl(z, x, y) {
    return `https://tile.openstreetmap.org/${z}/${x}/${y}.png`;
}

function createCachedOsmTileLayer(leaflet) {
    if (!leaflet?.TileLayer || typeof caches === 'undefined') {
        return leaflet.tileLayer(OSM_TILE_URL, { maxZoom: 19, attribution: '' });
    }
    const CachedOsm = leaflet.TileLayer.extend({
        createTile(coords, done) {
            const tile = document.createElement('img');
            tile.alt = '';
            tile.setAttribute('role', 'presentation');
            const url = this.getTileUrl(coords);
            const applySrc = (src, blobUrl) => {
                if (blobUrl) {
                    tile._osrBlobUrl = blobUrl;
                }
                tile.onload = () => done(null, tile);
                tile.onerror = (err) => done(err, tile);
                tile.src = src;
            };
            caches
                .open(MAP_TILE_CACHE)
                .then(async (cache) => {
                    const hit = await cache.match(url);
                    if (hit) {
                        const blob = await hit.blob();
                        const blobUrl = URL.createObjectURL(blob);
                        applySrc(blobUrl, blobUrl);
                        return;
                    }
                    const res = await fetch(url, { mode: 'cors', credentials: 'omit' });
                    if (res.ok) {
                        await cache.put(url, res.clone());
                        const blob = await res.blob();
                        const blobUrl = URL.createObjectURL(blob);
                        applySrc(blobUrl, blobUrl);
                        return;
                    }
                    applySrc(url, null);
                })
                .catch(() => applySrc(url, null));
            return tile;
        }
    });
    const layer = new CachedOsm(OSM_TILE_URL, {
        maxZoom: 19,
        attribution: '',
        crossOrigin: true
    });
    layer.on('tileunload', (event) => {
        const blobUrl = event?.tile?._osrBlobUrl;
        if (blobUrl) {
            URL.revokeObjectURL(blobUrl);
            event.tile._osrBlobUrl = null;
        }
    });
    return layer;
}

function collectTileUrls(points, zooms = PREFETCH_ZOOMS, maxTiles = MAX_PREFETCH_TILES) {
    const geo = (points || [])
        .map((point) => ({
            lat: Number(point.lat ?? point.latitude),
            lng: Number(point.lng ?? point.longitude)
        }))
        .filter((point) => Number.isFinite(point.lat) && Number.isFinite(point.lng));
    if (!geo.length) {
        return [];
    }
    const urls = [];
    const seen = new Set();
    for (const zoom of zooms) {
        const xs = geo.map((point) => lngToTile(point.lng, zoom));
        const ys = geo.map((point) => latToTile(point.lat, zoom));
        const minX = Math.min(...xs) - 1;
        const maxX = Math.max(...xs) + 1;
        const minY = Math.min(...ys) - 1;
        const maxY = Math.max(...ys) + 1;
        const world = 2 ** zoom;
        for (let x = minX; x <= maxX; x += 1) {
            for (let y = minY; y <= maxY; y += 1) {
                const wrappedX = ((x % world) + world) % world;
                const key = `${zoom}/${wrappedX}/${y}`;
                if (seen.has(key) || y < 0 || y >= world) {
                    continue;
                }
                seen.add(key);
                urls.push(osmTileUrl(zoom, wrappedX, y));
                if (urls.length >= maxTiles) {
                    return urls;
                }
            }
        }
    }
    return urls;
}

export async function prefetchMapAreaTiles(points, options = {}) {
    if (typeof caches === 'undefined' || typeof fetch !== 'function') {
        return 0;
    }
    const urls = collectTileUrls(points, options.zooms || PREFETCH_ZOOMS, options.maxTiles || MAX_PREFETCH_TILES);
    if (!urls.length) {
        return 0;
    }
    const cache = await caches.open(MAP_TILE_CACHE);
    let stored = 0;
    const concurrency = 6;
    for (let i = 0; i < urls.length; i += concurrency) {
        const batch = urls.slice(i, i + concurrency);
        await Promise.all(
            batch.map(async (url) => {
                try {
                    const hit = await cache.match(url);
                    if (hit) {
                        stored += 1;
                        return;
                    }
                    const res = await fetch(url, { mode: 'cors', credentials: 'omit' });
                    if (res.ok) {
                        await cache.put(url, res.clone());
                        stored += 1;
                    }
                } catch (_error) {
                    /* skip a missed tile; map still works online */
                }
            })
        );
    }
    return stored;
}

export function addNeighbourMapTileLayer(mapInstance, leaflet) {
    injectPharmacyPinReset(mapInstance);
    addMapIntelligenceFootnote(mapInstance, leaflet);
    const esri = leaflet.tileLayer(ESRI_STREET_TILE_URL, {
        maxZoom: 19,
        attribution: ''
    });
    const carto = leaflet.tileLayer(CARTO_TILE_URL, {
        maxZoom: 19,
        attribution: ''
    });
    let switchedToCarto = false;
    esri.on('tileerror', () => {
        if (switchedToCarto) {
            return;
        }
        switchedToCarto = true;
        mapInstance.removeLayer(esri);
        carto.addTo(mapInstance);
    });
    esri.addTo(mapInstance);
    return esri;
}