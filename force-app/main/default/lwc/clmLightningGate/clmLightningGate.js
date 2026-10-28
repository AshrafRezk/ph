/** CLM plays on the offline Field app. Lightning only points reps there. */

export const OFFLINE_CLM_URL = 'https://www.salesforceoffline.com/';

export function isLightningUiHost() {
    if (typeof window === 'undefined' || !window.location?.hostname) {
        return false;
    }
    const host = window.location.hostname.toLowerCase();
    // PWA (salesforceoffline.com) must keep playing decks — only native Lightning UI redirects.
    return host.includes('lightning.force.com');
}

export function openOfflineClmApp() {
    if (typeof window === 'undefined') {
        return;
    }
    window.open(OFFLINE_CLM_URL, '_blank', 'noopener,noreferrer');
}
