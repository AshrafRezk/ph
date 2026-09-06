// Offline shell uses client-side fetch of /downloads/apk-latest.json.
import { makeDualApex } from './_wireAdapter.js';

export default makeDualApex(async (params = {}) => {
    const base = String(params?.baseUrl || 'https://salesforceoffline.com').replace(/\/$/, '');
    try {
        const response = await fetch(`${base}/downloads/apk-latest.json`, {
            cache: 'no-store',
            credentials: 'omit'
        });
        if (!response.ok) {
            return { baseUrl: base };
        }
        const meta = await response.json();
        return {
            baseUrl: base,
            version: meta?.version || null,
            file: meta?.file || null,
            fileName: meta?.fileName || null
        };
    } catch (_e) {
        return { baseUrl: base };
    }
});
