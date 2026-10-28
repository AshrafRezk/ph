import { cacheRead, cacheWrite } from './tabCache.js';
import { sfSoql } from './sfRest.js';
import { analyticsOffline, createDashboard, listFolders } from './analyticsApi.js';
import { mountDashboardBuilder } from './dashboardBuilder.js';
import { ICONS, openModal, toast } from './analyticsUi.js';
import { escapeHtml, errorMessage, formatRelative, formatSynced, isNetworkError } from './viewUtils.js';
import { summarizeDashboardCatalog } from '../analyticsBrief.js';
import { publishAnalyticsSnapshot } from '../analyticsContext.js';

const LIST_KEY = 'dashboards.catalog.v2';

let rootEl = null;
let loadingList = false;
let currentDashboardId = null;
let builder = null;
let catalog = [];
let listState = { savedAt: null, message: '' };

function ensureShell(root) {
    if (root.querySelector('.osr-dashboards')) return;
    root.innerHTML = `
        <section class="osr-tab osr-dashboards an-page">
            <div data-dash-list>
                <header class="an-hero">
                    <div>
                        <span class="an-hero-eyebrow">${ICONS.dashboard}Analytics</span>
                        <h1>Dashboards</h1>
                        <p>Live Salesforce dashboards with filters, drill-down, and editing. The last results stay available offline.</p>
                    </div>
                    <div class="an-hero-actions">
                        <button type="button" class="an-btn" data-dash-refresh>${ICONS.refresh}<span>Refresh</span></button>
                        <button type="button" class="an-btn an-btn--primary" data-dash-new>${ICONS.plus}<span>New Dashboard</span></button>
                    </div>
                </header>
                <div data-dash-banner></div>
                <div class="an-toolbar">
                    <label class="an-search">${ICONS.search}<input type="search" data-dash-search placeholder="Search dashboards" /></label>
                </div>
                <div data-dash-content></div>
            </div>
            <div data-dash-detail hidden></div>
        </section>
    `;
    bind(root);
}

function bind(root) {
    root.querySelector('[data-dash-search]').addEventListener('input', () => renderList());
    root.querySelector('[data-dash-refresh]').addEventListener('click', () => loadCatalog({ force: true }));
    root.querySelector('[data-dash-new]').addEventListener('click', () => newDashboard());
    root.querySelector('[data-dash-content]').addEventListener('click', (event) => {
        const btn = event.target.closest('[data-dash-id]');
        if (btn) openDashboard(btn.dataset.dashId);
    });
}

function filteredCatalog() {
    const input = rootEl && rootEl.querySelector('[data-dash-search]');
    const term = ((input && input.value) || '').trim().toLowerCase();
    if (!term) return catalog;
    return catalog.filter((row) =>
        `${row.Title || ''} ${row.FolderName || ''} ${row.Description || ''}`.toLowerCase().includes(term)
    );
}

function dashCard(row) {
    return `<button type="button" class="an-dash-card" data-dash-id="${escapeHtml(row.Id)}">
        <span class="an-dash-thumb" aria-hidden="true"><i></i><i></i><i></i><i></i><i></i></span>
        <span class="an-dash-body">
            <span class="an-card-title">${escapeHtml(row.Title || 'Untitled dashboard')}</span>
            <span class="an-card-meta">${ICONS.folder}${escapeHtml(row.FolderName || 'Private Dashboards')}</span>
            ${row.Description ? `<span class="an-row-desc">${escapeHtml(row.Description)}</span>` : ''}
            <span class="an-card-meta">${row.LastViewedDate ? `Viewed ${escapeHtml(formatRelative(row.LastViewedDate))}` : row.LastModifiedDate ? `Updated ${escapeHtml(formatRelative(row.LastModifiedDate))}` : ''}</span>
        </span>
    </button>`;
}

function renderList() {
    if (!rootEl) return;
    const banner = rootEl.querySelector('[data-dash-banner]');
    const content = rootEl.querySelector('[data-dash-content]');
    const bits = [];
    if (listState.savedAt) bits.push(formatSynced(listState.savedAt));
    if (listState.message) bits.push(listState.message);
    banner.innerHTML = bits.length
        ? `<div class="an-banner${analyticsOffline() ? ' an-banner--offline' : ''}" role="status"><span>${escapeHtml(bits.join(' \u00b7 '))}</span></div>`
        : '';
    if (loadingList && !catalog.length) {
        content.innerHTML = `<div class="an-skel-grid">${'<i></i>'.repeat(6)}</div>`;
        return;
    }
    const rows = filteredCatalog();
    if (!rows.length) {
        content.innerHTML = `<div class="an-empty">${ICONS.dashboard}<strong>${catalog.length ? 'No dashboards match' : 'No dashboards yet'}</strong><span>${catalog.length ? 'Try a different search.' : 'Create a dashboard to get started.'}</span></div>`;
        return;
    }
    const folders = new Map();
    rows.forEach((row) => {
        const name = row.FolderName || 'Private Dashboards';
        if (!folders.has(name)) folders.set(name, []);
        folders.get(name).push(row);
    });
    const recent = rows.filter((r) => r.LastViewedDate).slice(0, 4);
    const input = rootEl.querySelector('[data-dash-search]');
    const filtering = Boolean(input && input.value.trim());
    content.innerHTML = `
        ${!filtering && recent.length ? `<h2 class="an-section-title">Recently viewed</h2><div class="an-dash-cards">${recent.map(dashCard).join('')}</div>` : ''}
        ${[...folders.entries()]
            .sort((a, b) => a[0].localeCompare(b[0]))
            .map(
                ([name, list]) =>
                    `<h2 class="an-section-title">${ICONS.folder}${escapeHtml(name)}<em>${list.length}</em></h2><div class="an-dash-cards">${list.map(dashCard).join('')}</div>`
            )
            .join('')}`;
}

function showList() {
    currentDashboardId = null;
    if (builder) {
        builder.destroy();
        builder = null;
    }
    if (!rootEl) return;
    rootEl.querySelector('[data-dash-list]').hidden = false;
    const detail = rootEl.querySelector('[data-dash-detail]');
    detail.hidden = true;
    detail.innerHTML = '';
    renderList();
    publishListContext();
}

async function loadCatalog({ force = false } = {}) {
    if (!rootEl || loadingList) return;
    loadingList = true;
    const cached = cacheRead(LIST_KEY);
    if (cached && cached.payload && (!catalog.length || !force)) {
        catalog = cached.payload;
        listState = { savedAt: cached.savedAt, message: '' };
    }
    renderList();
    publishListContext();
    try {
        const records = await sfSoql(
            'SELECT Id, Title, FolderName, Description, LastViewedDate, LastModifiedDate FROM Dashboard ORDER BY LastViewedDate DESC NULLS LAST, Title ASC LIMIT 300'
        );
        catalog = records;
        cacheWrite(LIST_KEY, records);
        listState = { savedAt: Date.now(), message: '' };
    } catch (error) {
        listState = {
            savedAt: cached && cached.savedAt,
            message: catalog.length
                ? isNetworkError(error)
                    ? 'Showing cached dashboard list.'
                    : errorMessage(error)
                : errorMessage(error)
        };
    } finally {
        loadingList = false;
        if (!currentDashboardId) {
            renderList();
            publishListContext();
        }
    }
}

function publishListContext() {
    if (currentDashboardId) return;
    publishAnalyticsSnapshot(summarizeDashboardCatalog(catalog));
}

async function newDashboard() {
    if (analyticsOffline()) {
        await openModal({
            title: 'New dashboard',
            body: '<p class="an-modal-text">Creating a dashboard needs a connection to Salesforce.</p>',
            actions: [{ id: 'ok', label: 'OK', primary: true }]
        });
        return;
    }
    let folders = [];
    try {
        folders = await listFolders('Dashboard');
    } catch (_err) {
        folders = [];
    }
    const res = await openModal({
        title: 'New dashboard',
        body: `
            <label class="an-field"><span>Name</span><input class="an-input" name="name" maxlength="80" placeholder="e.g. Territory Performance"/></label>
            <label class="an-field"><span>Folder</span><select class="an-input" name="folderId">${folders.map((f) => `<option value="${escapeHtml(f.id)}">${escapeHtml(f.name)}</option>`).join('')}</select></label>`,
        actions: [
            { id: 'cancel', label: 'Cancel' },
            { id: 'create', label: 'Create', primary: true }
        ]
    });
    if (res.action !== 'create') return;
    const name = String(res.form.name || '').trim();
    if (!name) return;
    try {
        const out = await createDashboard({ name, folderId: res.form.folderId });
        const id = out && (out.id || (out.dashboardMetadata && out.dashboardMetadata.id));
        toast('Dashboard created');
        await loadCatalog({ force: true });
        if (id) openDashboard(id);
    } catch (error) {
        listState = { ...listState, message: `Couldn\u2019t create the dashboard: ${errorMessage(error)}` };
        renderList();
    }
}

export async function openDashboard(recordId) {
    if (!recordId || !rootEl) return;
    currentDashboardId = recordId;
    const row = catalog.find((r) => r.Id === recordId);
    publishAnalyticsSnapshot({
        kind: 'dashboard',
        id: recordId,
        name: (row && row.Title) || 'Dashboard',
        folder: (row && row.FolderName) || '',
        status: 'loading',
        filters: [],
        components: []
    });
    if (builder) builder.destroy();
    rootEl.querySelector('[data-dash-list]').hidden = true;
    const detail = rootEl.querySelector('[data-dash-detail]');
    detail.hidden = false;
    builder = mountDashboardBuilder(detail, {
        dashboardId: recordId,
        folderName: row && row.FolderName,
        name: row && row.Title,
        onBack: () => {
            builder = null;
            showList();
        },
        onOpenDashboard: (id) => {
            loadCatalog({ force: true });
            openDashboard(id);
        }
    });
}

export function mountDashboardsView(root, options = {}) {
    if (!root) return;
    const remount = rootEl !== root || !root.querySelector('.osr-dashboards');
    rootEl = root;
    ensureShell(root);
    if (options.recordId) {
        if (currentDashboardId !== options.recordId || !builder) openDashboard(options.recordId);
        if (!catalog.length) loadCatalog();
        return;
    }
    if (remount || !currentDashboardId) {
        showList();
        loadCatalog();
    }
}
