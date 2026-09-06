import { plannerApiFetch } from '../apex/restHelper.js';

export const SF_API_VERSION = 'v62.0';

export function sfPath(suffix) {
    const path = String(suffix || '');
    return path.startsWith('/services/')
        ? path
        : `/services/data/${SF_API_VERSION}${path.startsWith('/') ? path : `/${path}`}`;
}

export function sfGet(suffix) {
    return plannerApiFetch(sfPath(suffix), { method: 'GET' });
}

export function sfSend(suffix, method, body) {
    const options = { method };
    if (body !== undefined && method !== 'GET' && method !== 'DELETE') {
        options.body = typeof body === 'string' ? body : JSON.stringify(body);
    }
    return plannerApiFetch(sfPath(suffix), options);
}

export async function sfSoql(query) {
    const data = await sfGet(`/query?q=${encodeURIComponent(query)}`);
    return Array.isArray(data && data.records) ? data.records : [];
}
