import { isOffline, plannerApiFetch } from '../apex/restHelper.js';
import { sfPath, sfSoql } from './sfRest.js';

function enc(id) {
    return encodeURIComponent(String(id || ''));
}

function get(suffix, { fresh = true } = {}) {
    return plannerApiFetch(sfPath(suffix), { method: 'GET', fresh });
}

function send(suffix, method, body) {
    return plannerApiFetch(sfPath(suffix), {
        method,
        body: body === undefined ? undefined : JSON.stringify(body),
        timeoutMs: 60000
    });
}

export function analyticsOffline() {
    return isOffline();
}

export function currentUserId() {
    try {
        return (localStorage.getItem('zeta.pwa.sfUserId') || '').trim();
    } catch (_err) {
        return '';
    }
}

/* ---------- Reports ---------- */

export function runSavedReport(reportId, options) {
    return get(`/analytics/reports/${enc(reportId)}?includeDetails=true`, options);
}

export function describeReport(reportId, options) {
    return get(`/analytics/reports/${enc(reportId)}/describe`, options);
}

export function runReportWithMetadata(reportId, reportMetadata) {
    const path = reportId
        ? `/analytics/reports/${enc(reportId)}?includeDetails=true`
        : '/analytics/reports/query?includeDetails=true';
    return send(path, 'POST', { reportMetadata });
}

export function saveReport(reportId, reportMetadata) {
    return send(`/analytics/reports/${enc(reportId)}`, 'PATCH', { reportMetadata });
}

export async function createReport(reportMetadata) {
    const meta = { ...reportMetadata };
    delete meta.id;
    delete meta.developerName;
    return send('/analytics/reports', 'POST', { reportMetadata: meta });
}

export async function saveReportAs(sourceId, reportMetadata, { name, folderId }) {
    const meta = { ...reportMetadata, name, folderId };
    if (!sourceId) return createReport(meta);
    const clone = await send(`/analytics/reports?cloneId=${enc(sourceId)}`, 'POST', {
        reportMetadata: { name, folderId }
    });
    const newId = clone && clone.reportMetadata && clone.reportMetadata.id;
    if (!newId) return clone;
    const next = { ...meta, id: newId };
    delete next.developerName;
    return saveReport(newId, next);
}

export function listReportTypes(options) {
    return get('/analytics/reportTypes', options);
}

export function describeReportType(type, options) {
    return get(`/analytics/reportTypes/${enc(type)}`, options);
}

export async function listFolders(type) {
    const rows = await sfSoql(
        `SELECT Id, Name, DeveloperName, AccessType FROM Folder WHERE Type = '${type}' ORDER BY Name LIMIT 500`
    );
    const folders = rows
        .filter((row) => row.Id && row.Name)
        .map((row) => ({ id: row.Id, name: row.Name }));
    const userId = currentUserId();
    if (userId) {
        folders.unshift({
            id: userId,
            name: type === 'Report' ? 'Private Reports' : 'Private Dashboards'
        });
    }
    return folders;
}

/* ---------- Dashboards ---------- */

export function getDashboardResults(dashboardId, filterOptionIds = [], options) {
    const query = filterOptionIds
        .map((id, i) => (id ? `filter${i + 1}=${enc(id)}` : ''))
        .filter(Boolean)
        .join('&');
    return get(`/analytics/dashboards/${enc(dashboardId)}${query ? `?${query}` : ''}`, options);
}

export function describeDashboard(dashboardId, options) {
    return get(`/analytics/dashboards/${enc(dashboardId)}/describe`, options);
}

export function refreshDashboard(dashboardId, filterOptionIds = []) {
    const filters = filterOptionIds.filter(Boolean);
    return send(
        `/analytics/dashboards/${enc(dashboardId)}`,
        'PUT',
        filters.length ? { filters } : {}
    );
}

export async function saveDashboard(dashboardId, dashboardMetadata) {
    return send(`/analytics/dashboards/${enc(dashboardId)}`, 'PATCH', dashboardMetadata);
}

export async function saveDashboardAs(sourceId, dashboardMetadata, { name, folderId }) {
    const clone = await send(`/analytics/dashboards?cloneId=${enc(sourceId)}`, 'POST', {
        name,
        folderId
    });
    const newId =
        (clone && (clone.id || (clone.dashboardMetadata && clone.dashboardMetadata.id))) || null;
    if (!newId) return clone;
    await saveDashboard(newId, { ...dashboardMetadata, id: newId, name, folderId });
    return { id: newId };
}

export async function createDashboard({ name, folderId }) {
    return send('/analytics/dashboards', 'POST', { name, folderId });
}
