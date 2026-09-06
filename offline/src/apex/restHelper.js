// Network status tracking - MANUAL MODE ONLY
// Auto-detection has been disabled. User must manually toggle offline/online mode.

export function isOffline() {
    // No longer auto-detect - this is kept for backward compatibility
    // but always returns false since mode is now manual
    return false;
}

function isBrowserWebClient() {
    try {
        const Cap = globalThis.Capacitor;
        if (Cap?.isNativePlatform?.()) return false;
    } catch {
        /* ignore */
    }
    return typeof window !== 'undefined';
}

/**
 * Salesforce REST fetch.
 * Browser web: POST through Netlify `sf-api` (CORS).
 * Capacitor native: direct fetch to the instance URL.
 */
export async function plannerApiFetch(path, options = {}) {
    const restBase = (typeof globalThis !== 'undefined' && globalThis.PLANNER_REST_BASE) || '';
    const token = (typeof globalThis !== 'undefined' && globalThis.PLANNER_ACCESS_TOKEN) || '';
    const headers = { Accept: 'application/json', ...(options.headers || {}) };
    if (token) {
        headers.Authorization = `Bearer ${token}`;
    }
    if (options.body && !headers['Content-Type']) {
        headers['Content-Type'] = 'application/json';
    }
    const fullUrl = `${String(restBase).replace(/\/$/, '')}${path}`;
    console.log('[REST] Fetching:', fullUrl);
    console.log('[REST] Token present:', !!token);

    let response;
    try {
        const controller = new AbortController();
        const timeoutId = setTimeout(() => controller.abort(), 30000);
        const method = options.method || 'GET';

        if (isBrowserWebClient() && token) {
            response = await fetch('/.netlify/functions/sf-api', {
                method: 'POST',
                headers: { 'Content-Type': 'application/json', Accept: 'application/json' },
                body: JSON.stringify({
                    url: fullUrl,
                    method,
                    authorization: `Bearer ${token}`,
                    body: options.body ?? null,
                    headers: { Accept: 'application/json', ...(options.headers || {}) }
                }),
                signal: controller.signal
            });
        } else {
            response = await fetch(fullUrl, {
                method,
                credentials: token ? 'omit' : 'same-origin',
                headers,
                body: options.body,
                signal: controller.signal
            });
        }
        clearTimeout(timeoutId);
    } catch (fetchError) {
        console.error('[REST] Fetch failed (possible CORS/network error):', fetchError.message);
        throw new Error(`Network error - possible CORS issue: ${fetchError.message}`);
    }
    console.log('[REST] Response status:', response.status);
    console.log('[REST] Content-Type:', response.headers.get('content-type'));

    if (!response.ok) {
        let detail = `HTTP ${response.status}`;
        try {
            const failed = await response.json();
            if (Array.isArray(failed) && failed[0] && failed[0].message) {
                detail = failed[0].message;
            } else if (failed && typeof failed === 'object') {
                detail = failed.message || failed.error || detail;
            }
        } catch (_parseError) {
            const text = await response.text();
            console.error('[REST] Non-JSON error response:', text.substring(0, 1000));
            detail = `${detail} - ${text.substring(0, 200)}`;
        }
        throw new Error(detail);
    }
    if (response.status === 204) {
        return null;
    }
    const contentType = response.headers.get('content-type');
    if (!contentType || !contentType.includes('application/json')) {
        const text = await response.text();
        console.error('[REST] Expected JSON but got:', contentType, text.substring(0, 1000));
        throw new Error(
            `Expected JSON response but got ${contentType || 'unknown'}: ${text.substring(0, 200)}`
        );
    }
    return response.json();
}
