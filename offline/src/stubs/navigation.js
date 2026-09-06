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
    window.dispatchEvent(new CustomEvent('zeta-navigate-record', { detail }));
    if (window.parent && window.parent !== window) {
        window.parent.postMessage({ type: 'zeta-navigate-record', ...detail }, '*');
    }
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

            if (type === 'standard__navItemPage' || type === 'standard__app') {
                navigateTab(pageRef?.attributes?.apiName || pageRef?.attributes?.appTarget, {
                    accountId: pageRef?.state?.c__accountId || pageRef?.state?.accountId || null
                });
                return;
            }

            if (type === 'standard__objectPage' && actionName === 'new') {
                // Offline: open a lightweight create flow via tab navigation event.
                navigateTab('Accounts_Tab', { action: 'newAccount', objectApiName });
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
                return Promise.resolve(`/?visit=${encodeURIComponent(recordId)}`);
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

/** @wire(CurrentPageReference) — offline emits a minimal home page reference. */
export function CurrentPageReference(dataCallback) {
    if (!(this instanceof CurrentPageReference)) {
        return { type: 'standard__namedPage', attributes: { pageName: 'home' } };
    }
    this._dataCallback = dataCallback;
}
CurrentPageReference.prototype.connect = function connect() {
    if (this._dataCallback) {
        this._dataCallback({
            data: { type: 'standard__namedPage', attributes: { pageName: 'home' } },
            error: undefined
        });
    }
};
CurrentPageReference.prototype.update = function update() {};
CurrentPageReference.prototype.disconnect = function disconnect() {
    this._dataCallback = null;
};
