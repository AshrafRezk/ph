// Care Coach Co-pilot Apex stand-ins. Every method goes through the
// CareCoachRestApi Apex REST class, which calls the same @AuraEnabled method
// the LWC uses in Lightning (masking and sharing are enforced server-side).
// Reads are network-first and fall back to the IndexedDB copy when offline.
import { makeDualApex } from './_wireAdapter.js';
import { plannerApiFetch } from './restHelper.js';

const BASE = '/services/apexrest/carecoach/v1/';
const TIMEOUT_MS = 35000;

const LOCAL_DATETIME = /^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}(:\d{2})?$/;

function hasParams(params) {
    return params && typeof params === 'object' && Object.keys(params).length > 0;
}

// The offline datetime input emits local wall-clock text; Apex expects ISO UTC like Lightning sends.
function normalize(params) {
    const out = {};
    Object.entries(params || {}).forEach(([key, value]) => {
        out[key] = typeof value === 'string' && LOCAL_DATETIME.test(value) ? new Date(value).toISOString() : value;
    });
    return out;
}

export function careCoachRead(method) {
    return makeDualApex((params) => {
        const query = hasParams(params) ? `?p=${encodeURIComponent(JSON.stringify(normalize(params)))}` : '';
        return plannerApiFetch(`${BASE}${method}${query}`, { fresh: true, timeoutMs: TIMEOUT_MS });
    });
}

export function careCoachWrite(method) {
    return makeDualApex((params) =>
        plannerApiFetch(`${BASE}${method}`, {
            method: 'POST',
            body: JSON.stringify(normalize(params)),
            timeoutMs: TIMEOUT_MS
        })
    );
}
