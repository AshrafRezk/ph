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

export const NavigationMixin = (Base) => {
    class Mixed extends Base {
        [NavigationMixin.Navigate](pageRef) {
            console.log('[NavigationMixin.Navigate]', pageRef);
            const recordId = pageRef?.attributes?.recordId;
            if (!recordId) {
                return;
            }
            navigateInApp(recordId, objectFromPageRef(pageRef), pageRef?.attributes?.actionName);
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
