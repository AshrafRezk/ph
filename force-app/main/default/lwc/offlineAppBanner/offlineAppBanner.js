import { LightningElement, api, track } from 'lwc';
import getLatestOfflineAppMeta from '@salesforce/apex/OfflineAppBannerController.getLatestOfflineAppMeta';

const DEFAULT_BASE = 'https://salesforceoffline.com';
const VERSION_KEY = 'zeta.pwa.appVersion';
const RUNTIME_FLAG = '__OSR_RUNTIME__';

function parseVersionParts(raw) {
    const text = String(raw || '').trim();
    if (!text) {
        return null;
    }
    const match = text.match(/(\d+)(?:\.(\d+))?(?:\.(\d+))?(?:[-.](?:beta|b)\.?(\d+))?/i);
    if (!match) {
        return null;
    }
    return [
        Number(match[1] || 0),
        Number(match[2] || 0),
        Number(match[3] || 0),
        Number(match[4] || 0)
    ];
}

function compareAppVersions(a, b) {
    const left = parseVersionParts(a) || [0, 0, 0, 0];
    const right = parseVersionParts(b) || [0, 0, 0, 0];
    for (let i = 0; i < 4; i += 1) {
        if (left[i] !== right[i]) {
            return left[i] - right[i];
        }
    }
    return 0;
}

function detectClientMode() {
    if (typeof window === 'undefined') {
        return 'online';
    }

    const runtime = window[RUNTIME_FLAG];
    if (runtime?.shell === 'offline') {
        return 'offline';
    }

    try {
        if (window.Capacitor?.isNativePlatform?.()) {
            return 'offline';
        }
    } catch (_e) {
        // ignore
    }

    const host = String(window.location?.hostname || '').toLowerCase();
    if (
        host.includes('salesforceoffline') ||
        host === 'localhost' ||
        host.endsWith('.netlify.app')
    ) {
        // Netlify / local offline shell hosts the PWA itself.
        if (document?.documentElement?.classList?.contains('osr-offline-shell') || runtime?.shell) {
            return 'offline';
        }
        // Heuristic: Cap / standalone PWA on the offline domain.
        const standalone =
            window.matchMedia?.('(display-mode: standalone)')?.matches ||
            window.navigator?.standalone === true;
        if (standalone || /Capacitor/i.test(navigator.userAgent || '')) {
            return 'offline';
        }
    }

    const ua = navigator.userAgent || '';
    if (
        /SalesforceMobileSDK|S1Native|Salesforce1|CommunityHybrid|SFDCHybrid|iPhone.*Salesforce|Android.*Salesforce/i.test(
            ua
        )
    ) {
        return 'salesforceApp';
    }

    return 'online';
}

function readInstalledVersion() {
    if (typeof window === 'undefined') {
        return '';
    }
    const runtime = window[RUNTIME_FLAG];
    if (runtime?.version) {
        return String(runtime.version);
    }
    try {
        return localStorage.getItem(VERSION_KEY) || '';
    } catch (_e) {
        return '';
    }
}

export default class OfflineAppBanner extends LightningElement {
    @api downloadBaseUrl = DEFAULT_BASE;
    /** When true, suppress the promo inside the Salesforce mobile app. Default shows links. */
    @api hideInSalesforceApp = false;

    @track clientMode = 'online';
    @track installedVersion = '';
    @track latestVersion = '';
    @track latestFileName = '';
    @track iosHint = '';
    @track dismissed = false;
    @track ready = false;

    connectedCallback() {
        this.clientMode = detectClientMode();
        this.installedVersion = readInstalledVersion();
        void this.loadLatestMeta();
    }

    get baseUrl() {
        return String(this.downloadBaseUrl || DEFAULT_BASE).replace(/\/$/, '');
    }

    get androidHref() {
        return `${this.baseUrl}/downloads/osr-offline-latest.apk`;
    }

    get webAppHref() {
        return `${this.baseUrl}/`;
    }

    get androidMetaLabel() {
        if (this.latestVersion) {
            return `v${this.latestVersion}${this.latestFileName ? `  ${this.latestFileName}` : ''}`;
        }
        return 'APK install';
    }

    get updateAvailable() {
        if (!this.latestVersion) {
            return false;
        }
        if (!this.installedVersion) {
            // Offline shell without a stamped version  still nudge if we know latest.
            return this.clientMode === 'offline';
        }
        return compareAppVersions(this.installedVersion, this.latestVersion) < 0;
    }

    get showBanner() {
        if (this.dismissed || !this.ready) {
            return false;
        }
        if (this.clientMode === 'offline') {
            return this.updateAvailable;
        }
        if (this.clientMode === 'salesforceApp') {
            return this.hideInSalesforceApp !== true && this.hideInSalesforceApp !== 'true';
        }
        // Online Lightning Experience / browser
        return true;
    }

    get isUpdateMode() {
        return this.clientMode === 'offline' && this.updateAvailable;
    }

    get isPromoMode() {
        return this.clientMode !== 'offline';
    }

    get titleText() {
        if (this.isUpdateMode) {
            return 'A newer offline app is available';
        }
        if (this.clientMode === 'salesforceApp') {
            return 'Install the Offline Field app';
        }
        return 'Get the Offline Field app';
    }

    get bodyText() {
        if (this.isUpdateMode) {
            const current = this.installedVersion ? `You have v${this.installedVersion}. ` : '';
            return `${current}Download v${this.latestVersion} for the latest planner, visits, and offline fixes.`;
        }
        if (this.clientMode === 'salesforceApp') {
            return 'For tablet field work offline, install the dedicated Offline Field app  then sign in once with your Salesforce account.';
        }
        return 'Working from a tablet? Install the Offline Field app so reps can plan visits and detail even without a connection.';
    }

    get modeBadge() {
        if (this.clientMode === 'offline') return 'Offline app';
        if (this.clientMode === 'salesforceApp') return 'Salesforce app';
        return 'Online';
    }

    get hostClass() {
        return `offline-app-banner ${this.isUpdateMode ? 'is-update' : 'is-promo'}`;
    }

    async loadLatestMeta() {
        let meta = null;

        // Prefer direct fetch inside the offline shell (no Salesforce CSP).
        if (this.clientMode === 'offline') {
            meta = await this.fetchManifestClient(`${this.baseUrl}/downloads/apk-latest.json`);
            if (!meta) {
                meta = await this.fetchManifestClient('/downloads/apk-latest.json');
            }
        }

        if (!meta) {
            try {
                meta = await getLatestOfflineAppMeta({ baseUrl: this.baseUrl });
            } catch (_e) {
                meta = null;
            }
        }

        if (!meta && this.clientMode !== 'offline') {
            meta = await this.fetchManifestClient(`${this.baseUrl}/downloads/apk-latest.json`);
        }

        if (meta?.version) {
            this.latestVersion = String(meta.version);
            this.latestFileName = meta.fileName || meta.file || '';
        }

        // If the installed stamp is empty but we are offline on a local manifest, treat local as installed.
        if (this.clientMode === 'offline' && !this.installedVersion) {
            const local = await this.fetchManifestClient('/downloads/apk-latest.json');
            if (local?.version) {
                this.installedVersion = String(local.version);
                try {
                    localStorage.setItem(VERSION_KEY, this.installedVersion);
                } catch (_e) {
                    // ignore
                }
            }
        }

        this.ready = true;
    }

    async fetchManifestClient(url) {
        try {
            const response = await fetch(url, { cache: 'no-store', credentials: 'omit' });
            if (!response.ok) {
                return null;
            }
            return await response.json();
        } catch (_e) {
            return null;
        }
    }

    handleDismiss() {
        this.dismissed = true;
    }

    handleIosClick() {
        // iOS cannot sideload an IPA here  open the PWA and show Add to Home Screen guidance.
        this.iosHint =
            'On iPhone/iPad: open the Offline Field site in Safari ? Share ? Add to Home Screen. Or open the link below to sign in on the tablet browser.';
        try {
            window.open(this.webAppHref, '_blank');
        } catch (_e) {
            // ignore
        }
    }
}
