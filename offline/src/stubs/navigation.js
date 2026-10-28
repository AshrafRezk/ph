const VISIT_OBJECTS = new Set(['Visit__c', 'Visit']);

function objectFromPageRef(pageRef) {
    return (
        pageRef?.attributes?.objectApiName ||
        pageRef?.attributes?.objectApi ||
        pageRef?.state?.objectApiName ||
        ''
    );
}

function navigateInApp(recordId, objectApiName, actionName) {
    if (!recordId) return;
    const detail = {
        recordId,
        objectApiName: objectApiName || '',
        actionName: actionName || 'view'
    };
    if (typeof window === 'undefined') return;
    window.dispatchEvent(new CustomEvent('zeta-navigate-record', { detail, bubbles: true, composed: true }));
    if (window.parent && window.parent !== window) {
        window.parent.postMessage({ type: 'zeta-navigate-record', ...detail }, '*');
    }
}

export function navigateNavItem(apiName, state) {
    if (typeof window === 'undefined' || !apiName) return;
    publishPageState(apiName, state);
    navigateTab(apiName);
}

function navigateTab(apiName, state = {}) {
    if (typeof window === 'undefined' || !apiName) return;
    const detail = { apiName, ...(state || {}) };
    window.dispatchEvent(new CustomEvent('zeta-navigate-tab', { detail }));
    if (window.parent && window.parent !== window) {
        window.parent.postMessage({ type: 'zeta-navigate-tab', ...detail }, '*');
    }
}

export const NavigationMixin = (Base) => {
    class Mixed extends Base {
        [NavigationMixin.Navigate](pageRef) {
            console.log('[NavigationMixin.Navigate]', pageRef);
            const type = pageRef?.type || '';
            const recordId = pageRef?.attributes?.recordId;
            const actionName = pageRef?.attributes?.actionName || 'view';
            const objectApiName = objectFromPageRef(pageRef);

            if (type === 'standard__app') {
                const nested = pageRef?.attributes?.pageRef;
                navigateTab(nested?.attributes?.apiName || pageRef?.attributes?.appTarget, {
                    appTarget: pageRef?.attributes?.appTarget || null,
                    accountId: pageRef?.state?.c__accountId || pageRef?.state?.accountId || null
                });
                return;
            }

            if (type === 'standard__navItemPage') {
                const apiName = pageRef?.attributes?.apiName;
                publishPageState(apiName, pageRef?.state);
                navigateTab(apiName, {
                    accountId: pageRef?.state?.c__accountId || pageRef?.state?.accountId || null
                });
                return;
            }

            if (type === 'standard__objectPage' && actionName === 'new') {
                // Offline: open a lightweight create flow via tab navigation event.
                navigateTab('Accounts_Tab', { action: 'newAccount', objectApiName });
                return;
            }

            if (type === 'standard__webPage') {
                const url = pageRef?.attributes?.url;
                if (url && typeof window !== 'undefined') {
                    // Google Maps waypoints use literal |; URLSearchParams encodes as %7C.
                    const openUrl = String(url).replace(/%7C/gi, '|');
                    window.open(openUrl, '_blank', 'noopener,noreferrer');
                }
                return;
            }

            if (!recordId) {
                return;
            }
            navigateInApp(recordId, objectApiName, actionName);
        }
        [NavigationMixin.GenerateUrl](pageRef) {
            const recordId = pageRef?.attributes?.recordId;
            const obj = objectFromPageRef(pageRef);
            if (!recordId) {
                return Promise.resolve('#');
            }
            if (VISIT_OBJECTS.has(obj)) {
                return Promise.resolve(`#visit/${encodeURIComponent(recordId)}`);
            }
            const base = (import.meta.env && import.meta.env.BASE_URL) || '/';
            return Promise.resolve(
                `${base}?recordId=${encodeURIComponent(recordId)}&object=${encodeURIComponent(obj || '')}`
            );
        }
    }
    return Mixed;
};

NavigationMixin.Navigate = Symbol('Navigate');
NavigationMixin.GenerateUrl = Symbol('GenerateUrl');

const HOME_PAGE_REF = { type: 'standard__namedPage', attributes: { pageName: 'home' } };
const PAGE_REF_EVENT = 'zeta-page-reference';
let currentPageRef = HOME_PAGE_REF;

// Only c__ state (e.g. c__productId, c__status) is carried over; plain tab
// switches keep the home reference existing offline components expect.
function publishPageState(apiName, state) {
    const carried = {};
    Object.entries(state || {}).forEach(([key, value]) => {
        if (key.startsWith('c__') && value !== undefined && value !== null) carried[key] = value;
    });
    if (!apiName || !Object.keys(carried).length || typeof window === 'undefined') return;
    currentPageRef = { type: 'standard__navItemPage', attributes: { apiName }, state: carried };
    window.dispatchEvent(new CustomEvent(PAGE_REF_EVENT, { detail: currentPageRef }));
}

/** @wire(CurrentPageReference) — home reference, or the last navItemPage navigation with c__ state. */
export function CurrentPageReference(dataCallback) {
    if (!(this instanceof CurrentPageReference)) {
        return currentPageRef;
    }
    this._dataCallback = dataCallback;
    this._onChange = () => this._emit();
}
CurrentPageReference.prototype._emit = function _emit() {
    if (this._dataCallback) {
        this._dataCallback({ data: currentPageRef, error: undefined });
    }
};
CurrentPageReference.prototype.connect = function connect() {
    if (typeof window !== 'undefined') window.addEventListener(PAGE_REF_EVENT, this._onChange);
    this._emit();
};
CurrentPageReference.prototype.update = function update() {};
CurrentPageReference.prototype.disconnect = function disconnect() {
    if (typeof window !== 'undefined') window.removeEventListener(PAGE_REF_EVENT, this._onChange);
    this._dataCallback = null;
};
