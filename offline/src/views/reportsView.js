import { cacheRead, cacheWrite } from './tabCache.js';
import { sfSoql } from './sfRest.js';
import { analyticsOffline, listReportTypes } from './analyticsApi.js';
import { mountReportBuilder } from './reportBuilder.js';
import { ICONS, openModal } from './analyticsUi.js';
import { escapeHtml, errorMessage, formatRelative, formatSynced, isNetworkError } from './viewUtils.js';
import { summarizeReportCatalog } from '../analyticsBrief.js';
import { publishAnalyticsSnapshot } from '../analyticsContext.js';

const LIST_KEY = 'reports.catalog.v2';
const COLLAPSE_KEY = 'reports.collapsedFolders';

let rootEl = null;
let loadingList = false;
let currentReportId = null;
let builder = null;
let catalog = [];
let listState = { savedAt: null, message: '' };
let formatFilter = 'all';

function collapsedFolders() {
    const cached = cacheRead(COLLAPSE_KEY);
    return new Set((cached && cached.payload) || []);
}

function toggleFolder(name) {
    const set = collapsedFolders();
    if (set.has(name)) set.delete(name);
    else set.add(name);
    cacheWrite(COLLAPSE_KEY, [...set]);
}

function ensureShell(root) {
    if (root.querySelector('.osr-reports')) return;
    root.innerHTML = `
        <section class="osr-tab osr-reports an-page">
            <div data-reports-list>
                <header class="an-hero">
                    <div>
                        <span class="an-hero-eyebrow">${ICONS.report}Analytics</span>
                        <h1>Reports</h1>
                        <p>Run, filter, chart, and build Salesforce reports. Your last results stay available offline.</p>
                    </div>
                    <div class="an-hero-actions">
                        <button type="button" class="an-btn" data-reports-refresh>${ICONS.refresh}<span>Refresh</span></button>
                        <button type="button" class="an-btn an-btn--primary" data-reports-new>${ICONS.plus}<span>New Report</span></button>
                    </div>
                </header>
                <div data-reports-banner></div>
                <div class="an-toolbar">
                    <label class="an-search">${ICONS.search}<input type="search" data-reports-search placeholder="Search reports, folders, descriptions" /></label>
                    <div class="an-seg" role="radiogroup" aria-label="Format" data-reports-format>
                        <button type="button" data-format="all" class="is-on">All</button>
                        <button type="button" data-format="Tabular">Tabular</button>
                        <button type="button" data-format="Summary">Summary</button>
                        <button type="button" data-format="Matrix">Matrix</button>
                    </div>
                </div>
                <div data-reports-content></div>
            </div>
            <div data-reports-detail hidden></div>
        </section>
    `;
    bind(root);
}

function bind(root) {
    root.querySelector('[data-reports-search]').addEventListener('input', () => renderList());
    root.querySelector('[data-reports-refresh]').addEventListener('click', () => loadCatalog({ force: true }));
    root.querySelector('[data-reports-new]').addEventListener('click', () => newReport());
    root.querySelector('[data-reports-format]').addEventListener('click', (event) => {
        const btn = event.target.closest('[data-format]');
        if (!btn) return;
        formatFilter = btn.dataset.format;
        root.querySelectorAll('[data-reports-format] [data-format]').forEach((el) => {
            el.classList.toggle('is-on', el === btn);
            el.setAttribute('aria-checked', String(el === btn));
        });
        renderList();
    });
    root.querySelector('[data-reports-content]').addEventListener('click', (event) => {
        const open = event.target.closest('[data-report-id]');
        if (open) {
            openReport(open.dataset.reportId);
            return;
        }
        const folder = event.target.closest('[data-folder-toggle]');
        if (folder) {
            toggleFolder(folder.dataset.folderToggle);
            renderList();
        }
    });
}

function searchTerm() {
    const input = rootEl && rootEl.querySelector('[data-reports-search]');
    return ((input && input.value) || '').trim().toLowerCase();
}

function filteredCatalog() {
    const term = searchTerm();
    return catalog.filter((row) => {
        if (formatFilter !== 'all' && String(row.Format || '') !== formatFilter) return false;
        if (!term) return true;
        const hay = `${row.Name || ''} ${row.FolderName || ''} ${row.Description || ''}`.toLowerCase();
        return hay.includes(term);
    });
}

function formatBadge(format) {
    const f = String(format || 'Tabular');
    return `<span class="an-badge an-badge--${escapeHtml(f.toLowerCase())}">${escapeHtml(f)}</span>`;
}

function reportRow(row) {
    return `<li>
        <button type="button" class="an-row" data-report-id="${escapeHtml(row.Id)}">
            <span class="an-row-icon">${ICONS.report}</span>
            <span class="an-row-main">
                <span class="an-row-title">${escapeHtml(row.Name || 'Untitled report')}</span>
                ${row.Description ? `<span class="an-row-desc">${escapeHtml(row.Description)}</span>` : ''}
            </span>
            ${formatBadge(row.Format)}
            <span class="an-row-meta">${row.LastRunDate ? `Run ${escapeHtml(formatRelative(row.LastRunDate))}` : 'Never run'}</span>
        </button>
    </li>`;
}

function recentCard(row) {
    return `<button type="button" class="an-card" data-report-id="${escapeHtml(row.Id)}">
        <span class="an-card-top">${ICONS.report}${formatBadge(row.Format)}</span>
        <span class="an-card-title">${escapeHtml(row.Name || 'Untitled report')}</span>
        <span class="an-card-meta">${escapeHtml(row.FolderName || 'Private Reports')}${row.LastRunDate ? ` \u00b7 ${escapeHtml(formatRelative(row.LastRunDate))}` : ''}</span>
    </button>`;
}

function renderList() {
    if (!rootEl) return;
    const banner = rootEl.querySelector('[data-reports-banner]');
    const content = rootEl.querySelector('[data-reports-content]');
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
        content.innerHTML = `<div class="an-empty">${ICONS.report}<strong>${catalog.length ? 'No reports match' : 'No reports yet'}</strong><span>${
            catalog.length ? 'Try a different search or format.' : 'Create a report to get started.'
        }</span></div>`;
        return;
    }
    const filtering = searchTerm() || formatFilter !== 'all';
    const recent = filtering ? [] : rows.filter((row) => row.LastRunDate).slice(0, 6);
    const folders = new Map();
    rows.forEach((row) => {
        const name = row.FolderName || 'Private Reports';
        if (!folders.has(name)) folders.set(name, []);
        folders.get(name).push(row);
    });
    const collapsed = collapsedFolders();
    const folderHtml = [...folders.entries()]
        .sort((a, b) => a[0].localeCompare(b[0]))
        .map(([name, list]) => {
            const isOpen = filtering || !collapsed.has(name);
            return `<section class="an-folder${isOpen ? ' is-open' : ''}">
                <button type="button" class="an-folder-head" data-folder-toggle="${escapeHtml(name)}" aria-expanded="${isOpen}">
                    <span class="an-chev"></span>${ICONS.folder}<span class="an-folder-name">${escapeHtml(name)}</span><em>${list.length}</em>
                </button>
                ${isOpen ? `<ul class="an-rows">${list.map(reportRow).join('')}</ul>` : ''}
            </section>`;
        })
        .join('');
    content.innerHTML = `
        ${recent.length ? `<h2 class="an-section-title">Recently run</h2><div class="an-cards">${recent.map(recentCard).join('')}</div>` : ''}
        <h2 class="an-section-title">${filtering ? `${rows.length} result${rows.length === 1 ? '' : 's'}` : 'All folders'}</h2>
        ${folderHtml}`;
}

function showList() {
    currentReportId = null;
    if (builder) {
        builder.destroy();
        builder = null;
    }
    if (!rootEl) return;
    rootEl.querySelector('[data-reports-list]').hidden = false;
    const detail = rootEl.querySelector('[data-reports-detail]');
    detail.hidden = true;
    detail.innerHTML = '';
    renderList();
    publishListContext();
}

function showDetail() {
    if (!rootEl) return null;
    rootEl.querySelector('[data-reports-list]').hidden = true;
    const detail = rootEl.querySelector('[data-reports-detail]');
    detail.hidden = false;
    return detail;
}

function mountBuilder(opts) {
    if (builder) builder.destroy();
    const detail = showDetail();
    if (!detail) return;
    builder = mountReportBuilder(detail, {
        ...opts,
        onBack: () => {
            builder = null;
            showList();
            loadCatalog();
        },
        onOpenReport: (id) => {
            loadCatalog({ force: true });
            openReport(id);
        }
    });
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
            'SELECT Id, Name, FolderName, Format, LastRunDate, LastModifiedDate, Description FROM Report ORDER BY LastRunDate DESC NULLS LAST, Name ASC LIMIT 500'
        );
        catalog = records;
        cacheWrite(LIST_KEY, records);
        listState = { savedAt: Date.now(), message: '' };
    } catch (error) {
        listState = {
            savedAt: cached && cached.savedAt,
            message: catalog.length
                ? isNetworkError(error)
                    ? 'Showing cached report list.'
                    : errorMessage(error)
                : errorMessage(error)
        };
    } finally {
        loadingList = false;
        if (!currentReportId) {
            renderList();
            publishListContext();
        }
    }
}

function publishListContext() {
    if (currentReportId) return;
    publishAnalyticsSnapshot(summarizeReportCatalog(catalog));
}

async function newReport() {
    if (analyticsOffline()) {
        await openModal({
            title: 'New report',
            body: '<p class="an-modal-text">Creating a report needs a connection to Salesforce. Try again when you\u2019re back online.</p>',
            actions: [{ id: 'ok', label: 'OK', primary: true }]
        });
        return;
    }
    let categories = [];
    let loadError = '';
    try {
        const types = await listReportTypes();
        categories = (Array.isArray(types) ? types : [])
            .map((cat) => ({
                label: cat.label,
                types: (cat.reportTypes || []).filter((t) => !t.isHidden)
            }))
            .filter((cat) => cat.types.length);
    } catch (error) {
        loadError = errorMessage(error);
    }
    let chosen = null;
    const res = await openModal({
        title: 'Choose a report type',
        wide: true,
        body: loadError
            ? `<p class="an-modal-text">${escapeHtml(loadError)}</p>`
            : `<label class="an-search">${ICONS.search}<input type="search" data-rt-search placeholder="Search report types" /></label>
               <div class="an-rt" data-rt-list></div>`,
        actions: [
            { id: 'cancel', label: 'Cancel' },
            { id: 'start', label: 'Start Report', primary: true }
        ],
        onMount(overlay) {
            const list = overlay.querySelector('[data-rt-list]');
            const search = overlay.querySelector('[data-rt-search]');
            const start = overlay.querySelector('[data-modal-action="start"]');
            if (start) start.disabled = true;
            if (!list) return;
            const paint = () => {
                const term = (search.value || '').trim().toLowerCase();
                list.innerHTML =
                    categories
                        .map((cat) => {
                            const hits = cat.types.filter(
                                (t) => !term || `${t.label} ${t.description || ''} ${cat.label}`.toLowerCase().includes(term)
                            );
                            if (!hits.length) return '';
                            return `<div class="an-rt-cat"><h3>${escapeHtml(cat.label)}</h3>${hits
                                .map(
                                    (t) =>
                                        `<button type="button" class="an-rt-item${chosen && chosen.type === t.type ? ' is-on' : ''}" data-rt="${escapeHtml(t.type)}" data-label="${escapeHtml(t.label)}"><strong>${escapeHtml(t.label)}</strong>${t.description ? `<span>${escapeHtml(t.description)}</span>` : ''}</button>`
                                )
                                .join('')}</div>`;
                        })
                        .join('') || '<p class="an-modal-text">No report types match.</p>';
            };
            paint();
            search.addEventListener('input', paint);
            list.addEventListener('click', (event) => {
                const item = event.target.closest('[data-rt]');
                if (!item) return;
                chosen = { type: item.dataset.rt, label: item.dataset.label };
                if (start) start.disabled = false;
                paint();
            });
            list.addEventListener('dblclick', (event) => {
                if (event.target.closest('[data-rt]') && start) start.click();
            });
        }
    });
    if (res.action !== 'start' || !chosen) return;
    currentReportId = null;
    mountBuilder({ reportType: chosen.type, typeLabel: chosen.label });
}

export async function openReport(recordId) {
    if (!recordId || !rootEl) return;
    currentReportId = recordId;
    const row = catalog.find((r) => r.Id === recordId);
    publishAnalyticsSnapshot({
        kind: 'report',
        id: recordId,
        name: (row && row.Name) || 'Report',
        folder: (row && row.FolderName) || '',
        format: (row && row.Format) || '',
        chart: '',
        status: 'loading',
        totals: [],
        groups: [],
        columns: [],
        filters: [],
        topRows: [],
        truncated: false,
        rowCount: 0
    });
    mountBuilder({ reportId: recordId, folderName: row && row.FolderName, name: row && row.Name });
}

export function mountReportsView(root, options = {}) {
    if (!root) return;
    const remount = rootEl !== root || !root.querySelector('.osr-reports');
    rootEl = root;
    ensureShell(root);
    if (options.recordId) {
        if (currentReportId !== options.recordId || !builder) openReport(options.recordId);
        if (!catalog.length) loadCatalog();
        return;
    }
    if (remount || !currentReportId) {
        showList();
        loadCatalog();
    }
}
