/**
 * Answers Salesforce REST paths with fictional sample data for the store-review demo.
 * Unknown reads come back empty (the app's own empty states show); writes succeed and stay
 * on the device. Every unmatched path is logged as `[demo] unhandled` for coverage work.
 */
import { DEMO_USER, demoQuery, demoApexGet } from './demoData.js';

let idCounter = 0;

function newId(prefix = 'a0D') {
    idCounter += 1;
    return `${prefix}DEMO${String(Date.now()).slice(-6)}${String(idCounter).padStart(3, '0')}`.slice(0, 18);
}

function ok(body) {
    return { status: 200, body };
}

export async function demoResponse(pathWithQuery, method, rawBody) {
    const [path, search = ''] = pathWithQuery.split('?');
    const params = new URLSearchParams(search);

    if (path === '/services/oauth2/userinfo') {
        return ok(DEMO_USER.userinfo);
    }

    if (/\/services\/data\/v[\d.]+\/query\/?$/.test(path) || /\/services\/data\/v[\d.]+\/queryAll\/?$/.test(path)) {
        return ok(demoQuery(params.get('q') || ''));
    }

    if (method === 'DELETE') {
        return { status: 204, body: null };
    }

    if (method === 'POST' || method === 'PATCH' || method === 'PUT') {
        let body = rawBody;
        try {
            body = typeof rawBody === 'string' ? JSON.parse(rawBody) : rawBody;
        } catch (_err) {
            /* keep raw */
        }
        if (/\/composite\/sobjects/.test(path)) {
            const records = Array.isArray(body?.records) ? body.records : [];
            return ok(records.map(() => ({ id: newId(), success: true, errors: [] })));
        }
        const apex = demoApexGet(path, params, method, body);
        if (apex !== undefined) return ok(apex);
        if (method === 'PATCH') return { status: 204, body: null };
        return ok({ id: newId(), success: true, errors: [] });
    }

    const apex = demoApexGet(path, params, method, null);
    if (apex !== undefined) return ok(apex);

    console.warn('[demo] unhandled', method, pathWithQuery);
    if (/\/sobjects\/[^/]+\/describe/.test(path)) {
        return ok({ fields: [], recordTypeInfos: [] });
    }
    if (/\/services\/apexrest\//.test(path)) {
        return ok({});
    }
    return ok({ totalSize: 0, done: true, records: [] });
}
