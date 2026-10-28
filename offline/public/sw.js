const CACHE_NAME = 'zeta-field-pwa-v29';
const CLM_PKG_CACHE = 'clm-pkg-v1';
const MAP_TILE_CACHE = 'map-tiles-v1';
const CLM_PKG_PREFIX = '/clm-pkg/';
const APP_SHELL = [
    '/',
    '/index.html',
    '/manifest.webmanifest',
    '/icon-192.png',
    '/icon-512.png',
    '/zeta-logo.png',
    '/zeta-mark.png',
    '/salesforce-logo.svg',
    '/salesforce-logo.png',
    '/salesforce-logo-512.png',
    '/shell-brand.js',
    '/name-romanizer.json',
    '/site-privacy.html',
    '/android-logo.svg',
    '/apple-logo.svg',
    '/accounts.html',
    '/accounts.js',
    '/accounts.css',
    '/account.html',
    '/account.js',
    '/account.css',
    '/record.html',
    '/record.js',
    '/record.css',
    '/accountTypeTheme.js',
    '/icons/account/pharmacy.png',
    '/icons/account/hco.png',
    '/icons/account/hcp.png',
    '/visits.html',
    '/visits.js',
    '/visits.css',
    '/shell.css',
    '/vendor/pdfjs/pdf.min.js',
    '/vendor/pdfjs/pdf.worker.min.js',
    '/vendor/jszip/jszip.min.js',
    '/vendor/leaflet/leaflet.js',
    '/vendor/leaflet/leaflet.css',
    '/vendor/leaflet/marker-icon.png',
    '/vendor/leaflet/marker-icon-2x.png',
    '/vendor/leaflet/marker-shadow.png',
    '/vendor/leaflet/images/marker-icon.png',
    '/vendor/leaflet/images/marker-icon-2x.png',
    '/vendor/leaflet/images/marker-shadow.png',
    '/vendor/meeting/MeetingJsQR.js',
    '/vendor/meeting/ZetaBlueZ.png'
];

self.addEventListener('install', (event) => {
    event.waitUntil(
        caches
            .open(CACHE_NAME)
            .then((cache) =>
                Promise.all(
                    APP_SHELL.map((url) =>
                        cache.add(url).catch(() => {
                            /* skip missing public files so install still succeeds */
                        })
                    )
                )
            )
            .then(() => self.skipWaiting())
    );
});

self.addEventListener('activate', (event) => {
    event.waitUntil(
        caches
            .keys()
            .then((keys) =>
                Promise.all(
                    keys
                        .filter((key) => key !== CACHE_NAME && key !== CLM_PKG_CACHE && key !== MAP_TILE_CACHE)
                        .map((key) => caches.delete(key))
                )
            )
            .then(() => self.clients.claim())
    );
});

function isOAuthNav(url) {
    return (
        url.pathname.includes('/oauth/callback') ||
        url.searchParams.has('code') ||
        url.searchParams.has('error') ||
        url.searchParams.has('state')
    );
}

async function matchClmPackage(request) {
    const cache = await caches.open(CLM_PKG_CACHE);
    const url = new URL(request.url);
    url.search = '';
    url.hash = '';
    const encoded = await cache.match(url.href);
    if (encoded) {
        return encoded;
    }
    const ignored = await cache.match(request, { ignoreSearch: true });
    if (ignored) {
        return ignored;
    }
    try {
        const decodedPath = decodeURIComponent(url.pathname);
        if (decodedPath !== url.pathname) {
            const decoded = await cache.match(new URL(decodedPath, url.origin).href);
            if (decoded) {
                return decoded;
            }
        }
    } catch (error) {
        /* ignore decode errors */
    }
    return new Response('CLM asset not cached', { status: 404, statusText: 'Not Found' });
}

function isMapTileRequest(url) {
    const host = url.hostname;
    return (
        host === 'tile.openstreetmap.org' ||
        host.endsWith('.tile.openstreetmap.org') ||
        host.includes('basemaps.cartocdn.com') ||
        host.includes('arcgisonline.com')
    );
}

async function matchMapTile(request) {
    const cache = await caches.open(MAP_TILE_CACHE);
    const cached = await cache.match(request);
    if (cached) {
        return cached;
    }
    const response = await fetch(request);
    if (response && response.ok) {
        cache.put(request, response.clone());
    }
    return response;
}

self.addEventListener('fetch', (event) => {
    const url = new URL(event.request.url);
    if (url.pathname.startsWith('/services/') || url.pathname.startsWith('/.netlify/functions/')) {
        return;
    }
    // APK and version manifest must always come from the network. A stable
    // filename used to get cached, including a time the file was missing and
    // the SPA shell was saved in its place.
    if (url.pathname.startsWith('/downloads/')) {
        return;
    }
    if (event.request.method !== 'GET') {
        return;
    }

    if (isMapTileRequest(url)) {
        event.respondWith(
            matchMapTile(event.request).catch(async () => {
                const cache = await caches.open(MAP_TILE_CACHE);
                return (await cache.match(event.request)) || Response.error();
            })
        );
        return;
    }

    if (url.pathname.startsWith(CLM_PKG_PREFIX)) {
        event.respondWith(matchClmPackage(event.request));
        return;
    }

    if (isOAuthNav(url)) {
        event.respondWith(
            fetch(event.request)
                .then(async (response) => {
                    if (response && response.ok) return response;
                    const cached = await caches.match('/index.html');
                    return cached || response;
                })
                .catch(async () => {
                    const cached = await caches.match('/index.html');
                    return cached || Response.error();
                })
        );
        return;
    }

    const isNavigate =
        event.request.mode === 'navigate' ||
        (event.request.destination === 'document' && url.origin === self.location.origin);

    // Record page assets must be network-first so deploys are not stuck behind
    // a stale cache-first copy of the old highlights renderer.
    const isRecordAsset = /\/record\.(html|js|css)$/.test(url.pathname);

    // Vite dev-server modules keep the same URL across edits.
    const isDevModule = /^\/(src|@fs|@id|@vite|node_modules)\//.test(url.pathname);

    // HTML navigations (including pull-to-refresh) must try the network first so
    // a stale cached index.html cannot point at missing hashed bundles.
    if (isNavigate || isRecordAsset || isDevModule) {
        event.respondWith(
            fetch(event.request)
                .then((response) => {
                    if (response && response.ok) {
                        const copy = response.clone();
                        const cacheKey = isNavigate && !isRecordAsset ? '/index.html' : event.request;
                        caches.open(CACHE_NAME).then((cache) => cache.put(cacheKey, copy));
                    }
                    return response;
                })
                .catch(async () => {
                    const cached = await caches.match(event.request);
                    if (cached) {
                        return cached;
                    }
                    if (isNavigate) {
                        return (await caches.match('/index.html')) || Response.error();
                    }
                    return Response.error();
                })
        );
        return;
    }

    event.respondWith(
        caches.match(event.request).then((cached) => {
            if (cached) {
                return cached;
            }
            return fetch(event.request)
                .then((response) => {
                    if (response && response.ok) {
                        const copy = response.clone();
                        caches.open(CACHE_NAME).then((cache) => cache.put(event.request, copy));
                    }
                    return response;
                })
                .catch(() => cached || Response.error());
        })
    );
});
