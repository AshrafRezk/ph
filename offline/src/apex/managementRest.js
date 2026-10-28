import { makeDualApex } from './_wireAdapter.js';
import { plannerApiFetch } from './restHelper.js';
import { apexError } from './learningShared.js';

function queryString(params) {
    const search = new URLSearchParams();
    Object.entries(params || {}).forEach(([key, value]) => {
        if (value !== undefined && value !== null && value !== '') {
            search.set(key, String(value));
        }
    });
    const text = search.toString();
    return text ? `?${text}` : '';
}

const REQUEST_TIMEOUT_MS = 35000;

function withTimeout(promise, label) {
    let timer;
    const timeout = new Promise((_, reject) => {
        timer = setTimeout(() => {
            reject(new Error(`${label} took too long. Check your connection and try again.`));
        }, REQUEST_TIMEOUT_MS);
    });
    return Promise.race([promise, timeout]).finally(() => clearTimeout(timer));
}

export function managementApex(path, pick) {
    return makeDualApex(async (config) => {
        try {
            const params = pick ? pick(config || {}) : {};
            return await withTimeout(
                plannerApiFetch(`/services/apexrest/management/v1/${path}${queryString(params)}`, {
                    fresh: true,
                    timeoutMs: REQUEST_TIMEOUT_MS
                }),
                'Team KPI'
            );
        } catch (error) {
            throw apexError(error?.body?.message || error?.message || 'Unable to load management data.');
        }
    });
}
