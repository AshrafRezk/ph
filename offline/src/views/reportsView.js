import { cacheRead, cacheWrite, idbGet, idbSet } from './tabCache.js';
import { sfGet, sfSoql } from './sfRest.js';
import { extractReportTable, tableHtml } from './reportTable.js';
import { escapeHtml, errorMessage, formatRelative, formatSynced, isNetworkError } from './viewUtils.js';

const LIST_KEY = 'reports.catalog';
const REPORT_IDB_PREFIX = 'report.';

let rootEl = null;
let loadingList = false;
let currentReportId = null;
let catalog = [];

function reportCacheKey(id) {
    return `${REPORT_IDB_PREFIX}${id}`;
}

function bannerHtml(savedAt, message) {
    const bits = [];
    if (savedAt) bits.push(escapeHtml(formatSynced(savedAt)));
    if (message) bits.push(escapeHtml(message));
    if (!bits.length) return '';
    return `<div class="osr-tab-banner" role="status">${bits.join(' ù ')}</div>`;
}

function ensureShell(root) {
    if (root.querySelector('.osr-reports')) return;
    root.innerHTML = `
        <section class="osr-tab osr-reports">
            <div data-reports-list>
                <header class="osr-tab-header">
                    <h1>Reports</h1>
                    <p>Run a Salesforce report as a table. Results are cached for offline viewing.</p>
                </header>
                <div data-reports-banner></div>
                <div class="osr-tab-toolbar">
                    <label class="osr-tab-search">
                        <span class="visually-hidden">Search reports</span>
                        <input type="search" data-reports-search placeholder="Search reportsù" />
                    </label>
                    <button type="button" class="osr-tab-btn" data-reports-refresh>Refresh</button>
                </div>
                <p class="osr-tab-empty" data-reports-empty>Loading reportsÖ</p>
                <ul class="osr-tab-list" data-reports-items></ul>
            </div>
            <div data-reports-detail hidden>
                <header class="osr-tab-header osr-tab-header--row">
                    <button type="button" class="osr-tab-btn" data-reports-back>Back</button>
                    <div>
                        <h1 data-report-title>Report</h1>
                        <p data-report-sub></p>
                    </div>
                </header>
                <div data-report-banner></div>
                <div data-report-body></div>
            </div>
        </section>
    `;
    bind(root);
}

function bind(root) {
    const search = root.querySelector('[data-reports-search]');
    const refresh = root.querySelector('[data-reports-refresh]');
    const items = root.querySelector('[data-reports-items]');
    const back = root.querySelector('[data-reports-back]');
    if (search) {
        search.addEventListener('input', () => renderList());
    }
    if (refresh) {
        refresh.addEventListener('click', () => loadCatalog({ force: true }));
    }
    if (items) {
        items.addEventListener('click', (event) => {
            const btn = event.target.closest('[data-report-id]');
            if (btn) openReport(btn.dataset.reportId);
        });
    }
    if (back) {
        back.addEventListener('click', () => showList());
    }
}

function filteredCatalog() {
    const term = (
        (rootEl && rootEl.querySelector('[data-reports-search]') &&
            rootEl.querySelector('[data-reports-search]').value) ||
        ''
    )
        .trim()
        .toLowerCase();
    if (!term) return catalog;
    return catalog.filter((row) => {
        const hay = `${row.Name || ''} ${row.FolderName || ''} ${row.Description || ''}`.toLowerCase();
        return hay.includes(term);
    });
}

function renderList({ savedAt, message } = {}) {
    if (!rootEl) return;
    const banner = rootEl.querySelector('[data-reports-banner]');
    const list = rootEl.querySelector('[data-reports-items]');
    const empty = rootEl.querySelector('[data-reports-empty]');
    const rows = filteredCatalog();
    if (banner) banner.innerHTML = bannerHtml(savedAt, message);
    if (list) {
        list.innerHTML = rows
            .map(
                (row) => `<li>
                    <button type="button" class="osr-tab-card" data-report-id="${escapeHtml(row.Id)}">
                        <span class="osr-tab-card-title">${escapeHtml(row.Name || 'Untitled report')}</span>
                        <span class="osr-tab-card-meta">${escapeHtml(row.FolderName || 'Unfiled')}
                            ${row.LastRunDate ? ` ù ${escapeHtml(formatRelative(row.LastRunDate))}` : ''}</span>
                        ${row.Description ? `<span class="osr-tab-card-desc">${escapeHtml(row.Description)}</span>` : ''}
                    </button>
                </li>`
            )
            .join('');
    }
    if (empty) {
        empty.hidden = rows.length > 0;
        empty.textContent = catalog.length ? 'No reports match your search.' : 'No reports found.';
    }
}

function showList() {
    currentReportId = null;
    if (!rootEl) return;
    const list = rootEl.querySelector('[data-reports-list]');
    const detail = rootEl.querySelector('[data-reports-detail]');
    if (list) list.hidden = false;
    if (detail) detail.hidden = true;
}

function showDetail() {
    if (!rootEl) return;
    const list = rootEl.querySelector('[data-reports-list]');
    const detail = rootEl.querySelector('[data-reports-detail]');
    if (list) list.hidden = true;
    if (detail) detail.hidden = false;
}

function paintReport(report, { savedAt, message } = {}) {
    if (!rootEl) return;
    const title = rootEl.querySelector('[data-report-title]');
    const sub = rootEl.querySelector('[data-report-sub]');
    const banner = rootEl.querySelector('[data-report-banner]');
    const body = rootEl.querySelector('[data-report-body]');
    const meta = (report && report.reportMetadata) || {};
    if (title) title.textContent = meta.name || 'Report';
    if (sub) {
        const format = meta.reportFormat || '';
        sub.textContent = format
            ? `${format} ù saved filters as last run in Salesforce`
            : 'Saved filters as last run in Salesforce';
    }
    if (banner) banner.innerHTML = bannerHtml(savedAt, message);
    if (body) {
        try {
            const table = extractReportTable(report);
            const note = table.note
                ? `<p class="osr-tab-note">${escapeHtml(table.note)}</p>`
                : '';
            body.innerHTML = note + tableHtml(table);
        } catch (error) {
            body.innerHTML = `<p class="osr-tab-empty">${escapeHtml(errorMessage(error))}</p>`;
        }
    }
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
            'SELECT Id, Name, FolderName, LastRunDate, Description FROM Report ORDER BY LastRunDate DESC NULLS LAST, Name ASC LIMIT 200'
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
                    ? 'Showing cached report list.'
                    : errorMessage(error)
                : errorMessage(error)
        });
        if (!catalog.length) {
            const empty = rootEl.querySelector('[data-reports-empty]');
            if (empty) {
                empty.hidden = false;
                empty.textContent = errorMessage(error);
            }
        }
    } finally {
        loadingList = false;
    }
}

export async function openReport(recordId) {
    if (!recordId || !rootEl) return;
    currentReportId = recordId;
    showDetail();
    const title = rootEl.querySelector('[data-report-title]');
    const body = rootEl.querySelector('[data-report-body]');
    const banner = rootEl.querySelector('[data-report-banner]');
    if (title) title.textContent = 'Loading reportù';
    if (body) body.innerHTML = '<p class="osr-tab-empty">Running reportù</p>';
    const cached = await idbGet(reportCacheKey(recordId));
    if (cached && cached.payload) {
        paintReport(cached.payload, { savedAt: cached.savedAt, message: 'Loading latestù' });
    }
    try {
        const report = await sfGet(`/analytics/reports/${encodeURIComponent(recordId)}?includeDetails=true`);
        await idbSet(reportCacheKey(recordId), report);
        paintReport(report, { savedAt: Date.now() });
    } catch (error) {
        if (cached && cached.payload) {
            paintReport(cached.payload, {
                savedAt: cached.savedAt,
                message: isNetworkError(error)
                    ? 'Showing last cached run.'
                    : errorMessage(error)
            });
            return;
        }
        if (banner) banner.innerHTML = bannerHtml(null, errorMessage(error));
        if (title) title.textContent = 'Report unavailable';
        if (body) {
            body.innerHTML = `<p class="osr-tab-empty">${escapeHtml(errorMessage(error))}</p>`;
        }
    }
}

export function mountReportsView(root, options = {}) {
    if (!root) return;
    const remount = rootEl !== root || !root.querySelector('.osr-reports');
    rootEl = root;
    ensureShell(root);
    if (options.recordId) {
        openReport(options.recordId);
        if (!catalog.length) loadCatalog();
        return;
    }
    if (remount || !currentReportId) {
        currentReportId = remount ? null : currentReportId;
        showList();
        loadCatalog();
    }
}
