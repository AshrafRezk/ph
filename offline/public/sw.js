const CACHE_NAME = 'zeta-field-pwa-v5';
const APP_SHELL = [
    '/',
    '/index.html',
    '/manifest.webmanifest',
    '/salesforce-logo.svg',
    '/salesforce-logo.png',
    '/android-logo.svg',
    '/apple-logo.svg',
    '/accounts.html',
    '/accounts.js',
    '/accounts.css',
    '/account.html',
    '/account.js',
    '/account.css',
    '/visits.html',
    '/visits.js',
    '/visits.css',
    '/shell.css'
];

self.addEventListener('install', (event) => {
    event.waitUntil(
        caches.open(CACHE_NAME).then((cache) => cache.addAll(APP_SHELL)).then(() => self.skipWaiting())
    );
});

self.addEventListener('activate', (event) => {
    event.waitUntil(
        caches.keys().then((keys) =>
            Promise.all(keys.filter((key) => key !== CACHE_NAME).map((key) => caches.delete(key)))
        ).then(() => self.clients.claim())
    );
});

self.addEventListener('fetch', (event) => {
    const url = new URL(event.request.url);
    if (url.pathname.startsWith('/services/') || url.pathname.startsWith('/.netlify/functions/')) {
        return;
    }
    if (event.request.method !== 'GET') {
        return;
    }

    // Never cache OAuth callback / authorize code navigations — stale HTML must not
    // swallow ?code&state or race token exchange.
    const isOAuthNav =
        url.pathname.includes('/oauth/callback') ||
        url.searchParams.has('code') ||
        url.searchParams.has('error') ||
        url.searchParams.has('state');
    if (isOAuthNav) {
        event.respondWith(
            fetch(event.request).catch(async () => {
                const cached = await caches.match('/index.html');
                return cached || Response.error();
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
                    const copy = response.clone();
                    caches.open(CACHE_NAME).then((cache) => cache.put(event.request, copy));
                    return response;
                })
                .catch(() => cached || Response.error());
        })
    );
});
