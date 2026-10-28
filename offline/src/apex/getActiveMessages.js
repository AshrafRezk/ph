import { makeDualApex } from './_wireAdapter.js';
import { loadHomeDashboard } from './homeDashboard.js';
import { plannerApiFetch } from './restHelper.js';

// Offline stand-in for HomeOfficeMessageController.getActiveMessages.
// Prefer the planner home/dashboard REST path (same Apex as Lightning) so
// audience filtering and FLS match the Field app. Fall back to SOQL if needed.
const API_VERSION = 'v62.0';
const LOOKBACK_DAYS = 90;
const DEFAULT_LIMIT = 8;

async function soql(query) {
    const path = `/services/data/${API_VERSION}/query?q=${encodeURIComponent(query)}`;
    const result = await plannerApiFetch(path);
    if (Array.isArray(result)) {
        // Salesforce error array
        const msg = result[0]?.message || 'SOQL failed';
        throw new Error(msg);
    }
    return result && Array.isArray(result.records) ? result.records : [];
}

function formatPublishedLabel(iso) {
    if (!iso) {
        return '';
    }
    const d = new Date(iso);
    if (Number.isNaN(d.getTime())) {
        return '';
    }
    const today = new Date();
    if (
        d.getFullYear() === today.getFullYear() &&
        d.getMonth() === today.getMonth() &&
        d.getDate() === today.getDate()
    ) {
        return 'Today';
    }
    return d.toLocaleDateString(undefined, {
        month: 'short',
        day: 'numeric',
        year: 'numeric'
    });
}

function audienceLabelFor(scope) {
    const s = (scope || '').trim();
    return s && s !== 'All Business Units' ? s : 'All Business Units';
}

function normalizeRow(r) {
    if (!r) {
        return null;
    }
    const priority = r.priority || r.Priority__c || 'Normal';
    const publishedOn = r.publishedOn || r.Published_On__c || null;
    return {
        recordId: r.recordId || r.Id,
        subject: r.subject || r.Name,
        body: r.body || r.Message_Body__c,
        authorName: r.authorName || (r.Author__r && r.Author__r.Name) || '',
        publishedOn,
        publishedLabel: r.publishedLabel || formatPublishedLabel(publishedOn),
        priority,
        audienceLabel: r.audienceLabel || audienceLabelFor(r.Audience_Scope__c || r.audienceScope),
        isHighPriority:
            r.isHighPriority === true ||
            priority === 'High'
    };
}

async function loadViaDashboard(rowLimit) {
    const dash = await loadHomeDashboard({});
    const raw = dash && Array.isArray(dash.messages) ? dash.messages : [];
    return raw
        .map(normalizeRow)
        .filter((row) => row && row.recordId && row.subject)
        .slice(0, rowLimit);
}

async function loadViaSoql(rowLimit) {
    const cutoff = new Date(Date.now() - LOOKBACK_DAYS * 24 * 60 * 60 * 1000)
        .toISOString()
        .replace(/\.\d{3}Z$/, 'Z');

    const rows = await soql(
        'SELECT Id, Name, Message_Body__c, Audience_Scope__c, Priority__c, ' +
            'Published_On__c, Author__r.Name FROM Home_Office_Message__c ' +
            `WHERE Is_Active__c = true AND Published_On__c >= ${cutoff} ` +
            'ORDER BY Priority__c DESC, Published_On__c DESC ' +
            `LIMIT ${rowLimit}`
    );
    return rows.map(normalizeRow).filter(Boolean);
}

async function loadActiveMessages(params) {
    const requested = params && params.limitSize ? Number(params.limitSize) : DEFAULT_LIMIT;
    const rowLimit = Math.min(Math.max(requested || DEFAULT_LIMIT, 1), 25);

    try {
        const fromDash = await loadViaDashboard(rowLimit);
        if (fromDash.length) {
            return fromDash;
        }
    } catch (_dashErr) {
        /* fall through to SOQL */
    }

    return loadViaSoql(rowLimit);
}

export default makeDualApex(loadActiveMessages);
