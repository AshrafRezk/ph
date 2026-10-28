/**
 * Fictional sample data for the store-review demo. No real people, accounts or sales.
 * Each fixture module answers its own screens; the first one that returns a value wins.
 */
import * as home from './fixtures/home.js';
import * as planner from './fixtures/planner.js';
import * as visit from './fixtures/visit.js';

const FIXTURES = [planner, visit, home];


export const DEMO_USER = {
    id: '005DEMO00000000001',
    name: 'Demo Field Rep',
    userinfo: {
        user_id: '005DEMO00000000001',
        organization_id: '00DDEMO00000000001',
        name: 'Demo Field Rep',
        given_name: 'Demo',
        family_name: 'Field Rep',
        preferred_username: 'review.demo@zeta-copilot.app',
        email: 'review.demo@zeta-copilot.app',
        picture: '',
        zoneinfo: 'Africa/Cairo',
        locale: 'en_US'
    }
};

function fromObject(soql) {
    const match = /\bfrom\s+([A-Za-z0-9_]+)/i.exec(soql);
    return match ? match[1] : '';
}

function records(list) {
    return { totalSize: list.length, done: true, records: list };
}

/** SOQL by object. Unknown objects come back empty. */
export function demoQuery(soql) {
    const object = fromObject(soql);
    for (const fixture of FIXTURES) {
        const list = fixture.query(object, soql);
        if (list !== undefined) return records(list);
    }
    console.warn('[demo] query', object, soql.slice(0, 160));
    return records([]);
}

/** Apex REST and sObject paths. `undefined` means "not handled". */
const OUTBOX_PATH = '/services/apexrest/planner/v1/outbox';

/**
 * The outbox carries planner actions (new visits, time off, meetings) and visit-shell actions
 * (call reports, CLM sessions). Visit applies its actions; planner supplies ids for its creates.
 */
function drainDemoOutbox(body) {
    const shell = visit.handle(OUTBOX_PATH, new URLSearchParams(), 'POST', body) || {};
    const results = planner.outboxResults(body);
    const visitIdByClientKey = { ...(shell.visitIdByClientKey || {}) };
    results.forEach((r) => Object.assign(visitIdByClientKey, r.visitIdByClientKey || {}));
    (Array.isArray(body?.actions) ? body.actions : []).forEach((action) => {
        if (action?.actionType !== 'SAVE_CALL_REPORT') return;
        try {
            const report = JSON.parse(action.callReportJson || '{}');
            planner.markVisitStatus(report.visitId, report.status);
        } catch (_err) {
            /* malformed report: nothing to mirror */
        }
    });
    return { ...shell, results, visitIdByClientKey };
}

export function demoApexGet(path, params, method, body) {
    if (path === OUTBOX_PATH && method === 'POST') {
        return drainDemoOutbox(body);
    }
    for (const fixture of FIXTURES) {
        const result = fixture.handle(path, params, method, body);
        if (result !== undefined) return result;
    }
    return undefined;
}
