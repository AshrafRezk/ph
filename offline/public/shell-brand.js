/* Shell brand for salesforceoffline.com.
   Logged out, and signed in to any org we do not know yet, the website is Salesforce.
   Signed in to a known customer org, the website uses that customer's brand.
   The native APK/IPA is built for one customer (this package is Zeta) and stays
   that brand even on the login screen.

   To add a customer such as ISA: add a CLIENTS entry, then matching
   .brand-<id> logo and copy slots in index.html (see the zeta slots). */
(function (global) {
    var INSTANCE_URL_KEY = 'zeta.pwa.sfInstanceUrl';
    var NATIVE_BRAND_ID = 'zeta';

    var GENERIC = {
        id: 'salesforce',
        productName: 'Salesforce',
        favicon: '/salesforce-logo.png',
        appleTouch: '/salesforce-logo-512.png'
    };

    var CLIENTS = [
        {
            id: 'zeta',
            productName: 'Zeta Co-Pilot',
            host: /^zetapharma(?:[.-]|$)/i,
            favicon: '/icon-192.png',
            appleTouch: '/icon-512.png'
        }
    ];

    var navLabel = '';

    function hostnameOf(value) {
        var raw = String(value || '').trim();
        if (!raw) return '';
        try {
            return new URL(raw).hostname.toLowerCase();
        } catch (e) {
            return raw
                .toLowerCase()
                .replace(/^https?:\/\//, '')
                .split('/')[0]
                .split(':')[0];
        }
    }

    function clientForInstance(instanceUrl) {
        var host = hostnameOf(instanceUrl);
        if (!host) return null;
        for (var i = 0; i < CLIENTS.length; i++) {
            if (CLIENTS[i].host.test(host)) return CLIENTS[i];
        }
        return null;
    }

    function clientById(id) {
        for (var i = 0; i < CLIENTS.length; i++) {
            if (CLIENTS[i].id === id) return CLIENTS[i];
        }
        return null;
    }

    function isNativeShell() {
        if (document.documentElement.classList.contains('osr-native')) return true;
        try {
            var cap = global.Capacitor;
            if (cap && typeof cap.isNativePlatform === 'function' && cap.isNativePlatform()) {
                return true;
            }
            if (cap && cap.isNative === true) return true;
            var platform = cap && typeof cap.getPlatform === 'function' ? cap.getPlatform() : '';
            if (platform === 'android' || platform === 'ios') return true;
        } catch (e) {
            /* ignore */
        }
        var ua = global.navigator.userAgent || '';
        if (/Capacitor/i.test(ua)) return true;
        var host = global.location.hostname || '';
        var port = global.location.port || '';
        if ((host === 'localhost' || host === '127.0.0.1') && !port && /android/i.test(ua)) {
            return true;
        }
        return false;
    }

    function readInstance() {
        try {
            return global.localStorage.getItem(INSTANCE_URL_KEY) || '';
        } catch (e) {
            return '';
        }
    }

    function hasSession() {
        try {
            var token = global.localStorage.getItem('zeta.pwa.sfAccessToken') || '';
            var refresh = global.localStorage.getItem('zeta.pwa.sfRefreshToken') || '';
            return !!(String(token).trim() || refresh);
        } catch (e) {
            return false;
        }
    }

    function resolve(options) {
        options = options || {};
        var native = options.native != null ? !!options.native : isNativeShell();
        if (native) return clientById(NATIVE_BRAND_ID) || GENERIC;
        var signedIn = options.signedIn != null ? !!options.signedIn : hasSession();
        if (!signedIn) return GENERIC;
        var instance = options.instanceUrl != null ? options.instanceUrl : readInstance();
        return clientForInstance(instance) || GENERIC;
    }

    function apply(options) {
        options = options || {};
        var brand = resolve(options);
        if (options.label != null) navLabel = options.label || '';
        document.documentElement.setAttribute('data-shell-brand', brand.id);

        var titleEl = document.querySelector('title[data-brand-screen]');
        var screen = titleEl ? titleEl.getAttribute('data-brand-screen') || '' : '';
        var pageLabel = screen || navLabel;
        var title = pageLabel
            ? pageLabel + (screen ? ' — ' : ' · ') + brand.productName
            : brand.productName;
        document.title = title;

        var apple = document.querySelector('meta[name="apple-mobile-web-app-title"]');
        if (apple) apple.setAttribute('content', brand.productName);
        var icon = document.querySelector('link[rel="icon"]');
        if (icon) icon.setAttribute('href', brand.favicon);
        var touch = document.querySelector('link[rel="apple-touch-icon"]');
        if (touch) touch.setAttribute('href', brand.appleTouch);

        var nodes = document.querySelectorAll('[data-brand-title]');
        for (var i = 0; i < nodes.length; i++) {
            nodes[i].setAttribute('title', title);
        }

        global.__SHELL_BRAND__ = brand;
        return brand;
    }

    global.ShellBrand = {
        apply: apply,
        resolve: resolve,
        productName: function () {
            return (global.__SHELL_BRAND__ || resolve()).productName;
        }
    };

    apply();
})(window);
