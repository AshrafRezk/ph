import { cacheRead, cacheWrite, idbGet, idbSet } from './tabCache.js';
import { sfGet, sfSoql } from './sfRest.js';
import { barChartHtml, extractChartSeries, extractMetric, extractReportTable, tableHtml } from './reportTable.js';
import { escapeHtml, errorMessage, formatRelative, formatSynced, isNetworkError } from './viewUtils.js';

const LIST_KEY = 'dashboards.catalog';
const DASH_IDB_PREFIX = 'dashboard.';

let rootEl = null;
let loadingList = false;
let currentDashboardId = null;
let catalog = [];

function dashCacheKey(id) {
    return `${DASH_IDB_PREFIX}${id}`;
}

function bannerHtml(savedAt, message) {
    const bits = [];
    if (savedAt) bits.push(escapeHtml(formatSynced(savedAt)));
    if (message) bits.push(escapeHtml(message));
    if (!bits.length) return '';
    return `<div class="osr-tab-banner" role="status">${bits.join(' ù ')}</div>`;
}

function ensureShell(root) {
    if (root.querySelector('.osr-dashboards')) return;
    root.innerHTML = `
        <section class="osr-tab osr-dashboards">
            <div data-dash-list>
                <header class="osr-tab-header">
                    <h1>Dashboards</h1>
                    <p>Open a Salesforce dashboard as metrics, tables, and simple charts. Last results stay available offline.</p>
                </header>
                <div data-dash-banner></div>
                <div class="osr-tab-toolbar">
                    <label class="osr-tab-search">
                        <span class="visually-hidden">Search dashboards</span>
                        <input type="search" data-dash-search placeholder="Search dashboardsù" />
                    </label>
                    <button type="button" class="osr-tab-btn" data-dash-refresh>Refresh</button>
                </div>
                <p class="osr-tab-empty" data-dash-empty>Loading dashboardsÖ</p>
                <ul class="osr-tab-list" data-dash-items></ul>
            </div>
            <div data-dash-detail hidden>
                <header class="osr-tab-header osr-tab-header--row">
                    <button type="button" class="osr-tab-btn" data-dash-back>Back</button>
                    <div>
                        <h1 data-dash-title>Dashboard</h1>
                        <p data-dash-sub></p>
                    </div>
                </header>
                <div data-dash-detail-banner></div>
                <div class="osr-dash-grid" data-dash-body></div>
            </div>
        </section>
    `;
    bind(root);
}

function bind(root) {
    const search = root.querySelector('[data-dash-search]');
    const refresh = root.querySelector('[data-dash-refresh]');
    const items = root.querySelector('[data-dash-items]');
    const back = root.querySelector('[data-dash-back]');
    if (search) search.addEventListener('input', () => renderList());
    if (refresh) refresh.addEventListener('click', () => loadCatalog({ force: true }));
    if (items) {
        items.addEventListener('click', (event) => {
            const btn = event.target.closest('[data-dash-id]');
            if (btn) openDashboard(btn.dataset.dashId);
        });
    }
    if (back) back.addEventListener('click', () => showList());
}

function filteredCatalog() {
    const term = (
        (rootEl &&
            rootEl.querySelector('[data-dash-search]') &&
            rootEl.querySelector('[data-dash-search]').value) ||
        ''
    )
        .trim()
        .toLowerCase();
    if (!term) return catalog;
    return catalog.filter((row) => {
        const hay = `${row.Title || ''} ${row.FolderName || ''} ${row.Description || ''}`.toLowerCase();
        return hay.includes(term);
    });
}

function renderList({ savedAt, message } = {}) {
    if (!rootEl) return;
    const banner = rootEl.querySelector('[data-dash-banner]');
    const list = rootEl.querySelector('[data-dash-items]');
    const empty = rootEl.querySelector('[data-dash-empty]');
    const rows = filteredCatalog();
    if (banner) banner.innerHTML = bannerHtml(savedAt, message);
    if (list) {
        list.innerHTML = rows
            .map(
                (row) => `<li>
                    <button type="button" class="osr-tab-card" data-dash-id="${escapeHtml(row.Id)}">
                        <span class="osr-tab-card-title">${escapeHtml(row.Title || 'Untitled dashboard')}</span>
                        <span class="osr-tab-card-meta">${escapeHtml(row.FolderName || 'Unfiled')}
                            ${row.LastViewedDate ? ` ù ${escapeHtml(formatRelative(row.LastViewedDate))}` : ''}</span>
                        ${row.Description ? `<span class="osr-tab-card-desc">${escapeHtml(row.Description)}</span>` : ''}
                    </button>
                </li>`
            )
            .join('');
    }
    if (empty) {
        empty.hidden = rows.length > 0;
        empty.textContent = catalog.length ? 'No dashboards match your search.' : 'No dashboards found.';
    }
}

function showList() {
    currentDashboardId = null;
    if (!rootEl) return;
    const list = rootEl.querySelector('[data-dash-list]');
    const detail = rootEl.querySelector('[data-dash-detail]');
    if (list) list.hidden = false;
    if (detail) detail.hidden = true;
}

function showDetail() {
    if (!rootEl) return;
    const list = rootEl.querySelector('[data-dash-list]');
    const detail = rootEl.querySelector('[data-dash-detail]');
    if (list) list.hidden = true;
    if (detail) detail.hidden = false;
}

function componentType(component) {
    return String((component && (component.type || component.componentType)) || '').toLowerCase();
}

function reportFromComponent(component, dataById) {
    const id = component && (component.id || component.componentId);
    const packed = id && dataById.get(String(id));
    return (
        (packed && (packed.reportResult || packed.report)) ||
        (component && (component.reportResult || component.report)) ||
        null
    );
}

function renderComponent(component, dataById) {
    const type = componentType(component);
    const title = component.header || component.title || component.name || 'Component';
    if (type.includes('visualforce') || type.includes('image') || type.includes('scontrol')) {
        return `<article class="osr-dash-card">
            <h2>${escapeHtml(title)}</h2>
            <p class="osr-tab-empty">This component isn't available offline.</p>
        </article>`;
    }
    const report = reportFromComponent(component, dataById);
    if (!report) {
        return `<article class="osr-dash-card">
            <h2>${escapeHtml(title)}</h2>
            <p class="osr-tab-empty">No cached result for this component.</p>
        </article>`;
    }
    let body = '';
    if (type.includes('metric') || type.includes('gauge')) {
        const metric = extractMetric(report);
        body = `<p class="osr-metric">${escapeHtml(metric.value)}</p>`;
    } else if (type.includes('chart') || type.includes('funnel') || type.includes('donut')) {
        body = barChartHtml(extractChartSeries(report));
    } else {
        try {
            body = tableHtml(extractReportTable(report));
        } catch (_err) {
            const metric = extractMetric(report);
            body = `<p class="osr-metric">${escapeHtml(metric.value)}</p>`;
        }
    }
    return `<article class="osr-dash-card"><h2>${escapeHtml(title)}</h2>${body}</article>`;
}

function paintDashboard(payload, { savedAt, message } = {}) {
    if (!rootEl) return;
    const title = rootEl.querySelector('[data-dash-title]');
    const sub = rootEl.querySelector('[data-dash-sub]');
    const banner = rootEl.querySelector('[data-dash-detail-banner]');
    const body = rootEl.querySelector('[data-dash-body]');
    const meta = (payload && (payload.dashboardMetadata || payload.metadata)) || payload || {};
    if (title) title.textContent = meta.name || meta.label || 'Dashboard';
    if (sub) sub.textContent = meta.description || 'Component results as last run in Salesforce';
    if (banner) banner.innerHTML = bannerHtml(savedAt, message);
    const components = meta.components || payload.components || [];
    const dataById = new Map();
    (payload.componentData || []).forEach((row) => {
        const id = row && (row.componentId || row.id);
        if (id) dataById.set(String(id), row);
    });
    if (body) {
        if (!components.length) {
            body.innerHTML = '<p class="osr-tab-empty">This dashboard has no components.</p>';
            return;
        }
        body.innerHTML = components.map((component) => renderComponent(component, dataById)).join('');
    }
}

async function hydrateComponentReports(payload) {
    const meta = (payload && (payload.dashboardMetadata || payload.metadata)) || {};
    const components = meta.components || payload.components || [];
    const dataById = new Map();
    (payload.componentData || []).forEach((row) => {
        const id = row && (row.componentId || row.id);
        if (id) dataById.set(String(id), row);
    });
    const missing = components.filter((component) => {
        const id = String(component.id || component.componentId || '');
        const packed = dataById.get(id);
        const hasResult = packed && (packed.reportResult || packed.report);
        return !hasResult && component.reportId;
    });
    if (!missing.length) return payload;
    const extras = await Promise.all(
        missing.map(async (component) => {
            try {
                const report = await sfGet(
                    `/analytics/reports/${encodeURIComponent(component.reportId)}?includeDetails=true`
                );
                return {
                    componentId: String(component.id || component.componentId),
                    reportResult: report
                };
            } catch (_err) {
                return null;
            }
        })
    );
    return {
        ...payload,
        componentData: [...(payload.componentData || []), ...extras.filter(Boolean)]
    };
}

async function fetchDashboard(recordId) {
    let payload = await sfGet(`/analytics/dashboards/${encodeURIComponent(recordId)}`);
    const statuses = (payload.componentData || []).map((row) => String(row.status || '').toUpperCase());
    if (statuses.some((status) => status === 'RUNNING' || status === 'NEW' || status === 'PENDING')) {
        await new Promise((resolve) => setTimeout(resolve, 1200));
        payload = await sfGet(`/analytics/dashboards/${encodeURIComponent(recordId)}`);
    }
    return hydrateComponentReports(payload);
}

async function loadCatalog({ force = false } = {}) {
    if (!rootEl || loadingList) return;
    loadingList = true;
    const cached = cacheRead(LIST_KEY);
    if (cached && cached.payload && !force) {
        catalog = cached.payload;
        renderList({ savedAt: cached.savedAt });
    }
    try {
        const records = await sfSoql(
            'SELECT Id, Title, FolderName, Description, LastViewedDate FROM Dashboard ORDER BY LastViewedDate DESC NULLS LAST, Title ASC LIMIT 200'
        );
        catalog = records;
        cacheWrite(LIST_KEY, records);
        renderList({ savedAt: Date.now() });
    } catch (error) {
        if (!catalog.length && cached && cached.payload) {
            catalog = cached.payload;
        }
        renderList({
            savedAt: cached && cached.savedAt,
            message: catalog.length
                ? isNetworkError(error)
                    ? 'Showing cached dashboard list.'
                    : errorMessage(error)
                : errorMessage(error)
        });
        if (!catalog.length) {
            const empty = rootEl.querySelector('[data-dash-empty]');
            if (empty) {
                empty.hidden = false;
                empty.textContent = errorMessage(error);
            }
        }
    } finally {
        loadingList = false;
    }
}

export async function openDashboard(recordId) {
    if (!recordId || !rootEl) return;
    currentDashboardId = recordId;
    showDetail();
    const title = rootEl.querySelector('[data-dash-title]');
    const body = rootEl.querySelector('[data-dash-body]');
    const banner = rootEl.querySelector('[data-dash-detail-banner]');
    if (title) title.textContent = 'Loading dashboardù';
    if (body) body.innerHTML = '<p class="osr-tab-empty">Loading componentsù</p>';
    const cached = await idbGet(dashCacheKey(recordId));
    if (cached && cached.payload) {
        paintDashboard(cached.payload, { savedAt: cached.savedAt, message: 'Loading latestù' });
    }
    try {
        const payload = await fetchDashboard(recordId);
        await idbSet(dashCacheKey(recordId), payload);
        paintDashboard(payload, { savedAt: Date.now() });
    } catch (error) {
        if (cached && cached.payload) {
            paintDashboard(cached.payload, {
                savedAt: cached.savedAt,
                message: isNetworkError(error)
                    ? 'Showing last cached dashboard.'
                    : errorMessage(error)
            });
            return;
        }
        if (banner) banner.innerHTML = bannerHtml(null, errorMessage(error));
        if (title) title.textContent = 'Dashboard unavailable';
        if (body) body.innerHTML = `<p class="osr-tab-empty">${escapeHtml(errorMessage(error))}</p>`;
    }
}

export function mountDashboardsView(root, options = {}) {
    if (!root) return;
    const remount = rootEl !== root || !root.querySelector('.osr-dashboards');
    rootEl = root;
    ensureShell(root);
    if (options.recordId) {
        openDashboard(options.recordId);
        if (!catalog.length) loadCatalog();
        return;
    }
    if (remount || !currentDashboardId) {
        currentDashboardId = remount ? null : currentDashboardId;
        showList();
        loadCatalog();
    }
}
