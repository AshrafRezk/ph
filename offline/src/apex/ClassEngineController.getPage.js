import { plannerApiFetch } from './restHelper.js';

const BASE = '/services/apexrest/class-engine/v1';

function buildQuery(params = {}) {
    const qs = new URLSearchParams();
    Object.keys(params || {}).forEach((key) => {
        const value = params[key];
        if (value == null || value === '') {
            return;
        }
        qs.set(key, String(value));
    });
    const encoded = qs.toString();
    return encoded ? `?${encoded}` : '';
}

export default async function getPage(params = {}) {
    return plannerApiFetch(`${BASE}/page${buildQuery(params)}`, { method: 'GET' });
}
