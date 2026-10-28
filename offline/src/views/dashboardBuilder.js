import { cacheRead, idbGet, idbSet } from './tabCache.js';
import { sfSoql } from './sfRest.js';
import {
    analyticsOffline,
    describeDashboard,
    getDashboardResults,
    listFolders,
    refreshDashboard,
    runSavedReport,
    saveDashboard,
    saveDashboardAs
} from './analyticsApi.js';
import { extractMetric } from './reportTable.js';
import {
    chartHtml,
    gaugeHtml,
    gaugeOptionsFrom,
    installChartTooltips,
    metricHtml,
    resolveChartKind
} from './reportCharts.js';
import { buildReportModel, defaultGridView, reportGridHtml } from './reportGrid.js';
import { ICONS, confirmModal, formatAsOf, iconBtn, openModal, toast } from './analyticsUi.js';
import { escapeHtml, errorMessage, formatSynced, isNetworkError } from './viewUtils.js';
import { publishAnalyticsSnapshot } from '../analyticsContext.js';

const RESULT_PREFIX = 'dashboard.';
const DESCRIBE_PREFIX = 'dashdesc.';
const COLS = 12;
const GAP = 12;

const DISPLAY_OPTIONS = [
    { value: 'report', label: 'Use report chart' },
    { value: 'Column', label: 'Vertical bar' },
    { value: 'Bar', label: 'Horizontal bar' },
    { value: 'StackedColumn', label: 'Stacked vertical bar' },
    { value: 'StackedBar', label: 'Stacked horizontal bar' },
    { value: 'Line', label: 'Line' },
    { value: 'Donut', label: 'Donut' },
    { value: 'Pie', label: 'Pie' },
    { value: 'Funnel', label: 'Funnel' },
    { value: 'Scatter', label: 'Scatter' },
    { value: 'Metric', label: 'Metric' },
    { value: 'Gauge', label: 'Gauge' },
    { value: 'Table', label: 'Table' }
];

const FILTER_OPS = [
    ['equals', 'equals'],
    ['notEqual', 'not equal to'],
    ['lessThan', 'less than'],
    ['greaterThan', 'greater than'],
    ['lessOrEqual', 'less or equal'],
    ['greaterOrEqual', 'greater or equal'],
    ['contains', 'contains'],
    ['notContain', 'does not contain'],
    ['startsWith', 'starts with'],
    ['between', 'between']
];

let tmpSeq = 0;

function clone(value) {
    return JSON.parse(JSON.stringify(value ?? null));
}

function compKey(component) {
    if (!component.__key) component.__key = component.id || `new-${(tmpSeq += 1)}`;
    return component.__key;
}

function overlaps(a, b) {
    return (
        a.column < b.column + b.colspan &&
        b.column < a.column + a.colspan &&
        a.row < b.row + b.rowspan &&
        b.row < a.row + a.rowspan
    );
}

function resolveCollisions(cells, movedIndex) {
    const order = cells
        .map((cell, i) => ({ cell, i }))
        .filter((item) => item.i !== movedIndex)
        .sort((a, b) => a.cell.row - b.cell.row || a.cell.column - b.cell.column);
    const placed = [cells[movedIndex]];
    order.forEach(({ cell }) => {
        let guard = 0;
        let hit = placed.find((p) => overlaps(p, cell));
        while (hit && guard < 200) {
            cell.row = hit.row + hit.rowspan;
            hit = placed.find((p) => overlaps(p, cell));
            guard += 1;
        }
        placed.push(cell);
    });
}

function classicLayout(meta) {
    const columns = (meta.layout && meta.layout.columns) || [];
    const components = meta.components || [];
    const cells = components.map(() => null);
    const span = Math.max(3, Math.floor(COLS / Math.max(1, columns.length || 3)));
    if (columns.length) {
        columns.forEach((col, ci) => {
            let row = 0;
            (col.components || []).forEach((index) => {
                if (cells[index]) return;
                cells[index] = { column: ci * span, row, colspan: span, rowspan: 8 };
                row += 8;
            });
        });
    }
    let row = Math.max(0, ...cells.filter(Boolean).map((c) => c.row + c.rowspan));
    return cells.map((cell, i) => {
        if (cell) return cell;
        const c = { column: (i % 3) * 4, row, colspan: 4, rowspan: 8 };
        if (i % 3 === 2) row += 8;
        return c;
    });
}

function normalizeLayout(meta) {
    const layout = meta.layout || {};
    const components = meta.components || [];
    let cells = Array.isArray(layout.components) ? layout.components.map((c) => ({ ...c })) : [];
    const grid = layout.gridLayout !== false && cells.length === components.length;
    if (!grid) cells = classicLayout(meta);
    cells = cells.map((c) => ({
        column: Math.max(0, Math.min(COLS - 1, Number(c.column) || 0)),
        row: Math.max(0, Number(c.row) || 0),
        colspan: Math.max(1, Math.min(COLS, Number(c.colspan) || 4)),
        rowspan: Math.max(2, Number(c.rowspan) || 8)
    }));
    return {
        grid,
        rowHeight: Number(layout.rowHeight) || 36,
        cells
    };
}

function kindOf(component, report) {
    const props = component.properties || {};
    if (props.useReportChart && report) {
        const k = resolveChartKind(component, report);
        if (k) return k;
    }
    return resolveChartKind({ ...component, properties: { ...props, useReportChart: false } }, report) || 'table';
}

function displayValueOf(component) {
    const props = component.properties || {};
    if (props.useReportChart) return 'report';
    const v = String(props.visualizationType || '');
    if (v === 'FlexTable') return 'Table';
    return DISPLAY_OPTIONS.some((o) => o.value === v) ? v : 'Column';
}

function aggregateLabelFor(report, key) {
    if (!key || key === 'RowCount') return 'Record Count';
    const info =
        report &&
        report.reportExtendedMetadata &&
        report.reportExtendedMetadata.aggregateColumnInfo &&
        report.reportExtendedMetadata.aggregateColumnInfo[key];
    return (info && info.label) || String(key).split('.').pop().replace(/__c$/, '').replace(/_/g, ' ');
}

/**
 * options: { dashboardId, folderName?, onBack() }
 */
export function mountDashboardBuilder(container, options = {}) {
    installChartTooltips();
    const S = {
        id: options.dashboardId,
        folderName: options.folderName || '',
        title: options.name || '',
        results: null,
        meta: null,
        saved: null,
        layout: { grid: true, rowHeight: 36, cells: [] },
        dataById: new Map(),
        statusById: new Map(),
        reportCache: new Map(),
        mode: 'view',
        filterSel: [],
        savedAt: null,
        message: '',
        messageTone: 'info',
        loading: true,
        refreshing: false,
        saving: false,
        stacked: false,
        destroyed: false
    };

    container.innerHTML = `
        <section class="db" data-mode="view">
            <header class="db-head" data-db-head></header>
            <div data-db-banner></div>
            <div class="db-filters" data-db-filters></div>
            <div class="db-grid" data-db-grid></div>
        </section>`;
    const root = container.querySelector('.db');
    const $ = (sel) => root.querySelector(sel);
    const grid = $('[data-db-grid]');

    const offline = () => analyticsOffline();
    const signature = () => JSON.stringify(stripForSave(S.meta, S.layout));
    const dirty = () => Boolean(S.meta && S.saved && signature() !== S.saved);

    function setMessage(text, tone = 'info') {
        S.message = text || '';
        S.messageTone = tone;
        renderBanner();
    }

    /* ---------- Data plumbing ---------- */

    function indexResults(payload) {
        S.dataById = new Map();
        S.statusById = new Map();
        ((payload && payload.componentData) || []).forEach((row) => {
            const id = row && (row.componentId || row.id);
            if (!id) return;
            if (row.reportResult || row.report) S.dataById.set(String(id), row.reportResult || row.report);
            if (row.status) S.statusById.set(String(id), row.status);
        });
    }

    function adoptMeta(meta) {
        S.meta = clone(meta);
        (S.meta.components || []).forEach(compKey);
        S.layout = normalizeLayout(S.meta);
        S.saved = signature();
        if (!S.filterSel.length) {
            S.filterSel = (S.meta.filters || []).map((f) => (f.selectedOption && f.selectedOption.id) || f.selectedOption || '');
        }
    }

    function stripForSave(meta, layout) {
        if (!meta) return null;
        const out = clone(meta);
        out.components = (out.components || []).map((c) => {
            const copy = { ...c };
            delete copy.__key;
            delete copy.__preview;
            if (!copy.id) {
                delete copy.componentData;
                delete copy.lastModifiedDate;
            }
            return copy;
        });
        if (layout && layout.grid) {
            out.layout = {
                ...(out.layout || {}),
                gridLayout: true,
                numColumns: COLS,
                rowHeight: layout.rowHeight,
                components: layout.cells.map((c) => ({ ...c }))
            };
        }
        return out;
    }

    function asOf() {
        let latest = 0;
        S.statusById.forEach((status) => {
            const t = Date.parse(String(status.refreshDate || '').replace(/\+0000$/, 'Z'));
            if (Number.isFinite(t) && t > latest) latest = t;
        });
        return latest || null;
    }

    function reportFor(component) {
        if (component.__preview && component.reportId && S.reportCache.has(component.reportId)) {
            return { report: S.reportCache.get(component.reportId), full: true };
        }
        const data = component.id && S.dataById.get(String(component.id));
        if (data) return { report: data, full: false };
        if (component.reportId && S.reportCache.has(component.reportId)) {
            return { report: S.reportCache.get(component.reportId), full: true };
        }
        return { report: null, full: false };
    }

    async function ensureReport(reportId) {
        if (!reportId) return null;
        if (S.reportCache.has(reportId)) return S.reportCache.get(reportId);
        const report = await runSavedReport(reportId);
        S.reportCache.set(reportId, report);
        return report;
    }

    /* ---------- Rendering ---------- */

    function renderHead() {
        const meta = S.meta || {};
        const edit = S.mode === 'edit';
        const time = asOf();
        const sub = [
            time ? `As of ${formatAsOf(time)}` : '',
            meta.runningUser && meta.runningUser.displayName ? `Viewing as ${meta.runningUser.displayName}` : ''
        ]
            .filter(Boolean)
            .join(' \u00b7 ');
        const isDirty = dirty();
        const actions = edit
            ? `
                <button type="button" class="an-btn" data-db-act="add"${offline() ? ' disabled' : ''}>${ICONS.plus}<span>Component</span></button>
                <button type="button" class="an-btn" data-db-act="filters">${ICONS.filter}<span>Filters</span></button>
                <button type="button" class="an-btn" data-db-act="saveas"${offline() || S.saving ? ' disabled' : ''}>Save As</button>
                <button type="button" class="an-btn an-btn--primary" data-db-act="save"${offline() || S.saving || !isDirty ? ' disabled' : ''}>${S.saving ? 'Saving\u2026' : 'Save'}</button>
                <button type="button" class="an-btn an-btn--ghost" data-db-act="done">Done</button>`
            : `
                <button type="button" class="an-btn" data-db-act="refresh"${S.refreshing || offline() ? ' disabled' : ''}>${ICONS.refresh}<span>${S.refreshing ? 'Refreshing\u2026' : 'Refresh'}</span></button>
                <button type="button" class="an-btn an-btn--primary" data-db-act="edit"${S.meta ? '' : ' disabled'}>${ICONS.edit}<span>Edit</span></button>`;
        $('[data-db-head]').innerHTML = `
            ${iconBtn('back', 'Back to dashboards', 'data-db-act="back"', 'rb-back')}
            <div class="rb-title">
                <span class="rb-eyebrow">${ICONS.dashboard}Dashboard${meta.folderName || S.folderName ? ` \u00b7 ${escapeHtml(meta.folderName || S.folderName)}` : ''}</span>
                <div class="rb-title-row">
                    ${edit ? `<input class="rb-name-input" data-db-name value="${escapeHtml(meta.name || '')}" maxlength="80" aria-label="Dashboard name"/>` : `<h1 class="rb-name">${escapeHtml(meta.name || (S.loading ? 'Loading dashboard\u2026' : 'Dashboard'))}</h1>`}
                    ${isDirty ? '<span class="rb-status is-dirty">Unsaved changes</span>' : ''}
                </div>
                ${sub ? `<span class="db-sub">${escapeHtml(sub)}</span>` : ''}
            </div>
            <div class="rb-actions">${actions}</div>`;
        root.dataset.mode = S.mode;
    }

    function renderBanner() {
        const bits = [];
        if (offline()) {
            bits.push({
                tone: 'offline',
                text: `You\u2019re offline. Showing the last cached results${S.savedAt ? ` (${formatSynced(S.savedAt).toLowerCase()})` : ''}. Refresh and Save need a connection.`
            });
        }
        if (S.mode === 'edit' && !S.layout.grid) {
            bits.push({ tone: 'warn', text: 'This is a classic column dashboard. You can edit components here; open it in Lightning to change its layout.' });
        }
        if (S.message) bits.push({ tone: S.messageTone, text: S.message });
        $('[data-db-banner]').innerHTML = bits
            .map((bit) => `<div class="an-banner an-banner--${bit.tone}" role="status"><span>${escapeHtml(bit.text)}</span></div>`)
            .join('');
    }

    function optionLabel(filter, option) {
        if (option.alias) return option.alias;
        const op = (FILTER_OPS.find(([v]) => v === option.operation) || [])[1] || option.operation;
        if (option.operation === 'between') return `${option.startValue || '\u2026'} \u2013 ${option.endValue || '\u2026'}`;
        const value = option.value === '' || option.value == null ? '(blank)' : option.value;
        return op && op !== 'equals' ? `${op} ${value}` : value;
    }

    function renderFilters() {
        const host = $('[data-db-filters]');
        const filters = (S.meta && S.meta.filters) || [];
        if (!filters.length) {
            host.innerHTML = '';
            host.hidden = true;
            return;
        }
        host.hidden = false;
        host.innerHTML = `<span class="rb-filter-icon">${ICONS.filter}</span>${filters
            .map(
                (filter, i) => `
                <label class="db-filter${S.filterSel[i] ? ' is-active' : ''}">
                    <span>${escapeHtml(filter.name)}</span>
                    <select data-db-filter="${i}"${offline() ? ' disabled' : ''}>
                        <option value="">All</option>
                        ${(filter.options || [])
                            .filter((o) => o.id)
                            .map((o) => `<option value="${escapeHtml(o.id)}"${S.filterSel[i] === o.id ? ' selected' : ''}>${escapeHtml(optionLabel(filter, o))}</option>`)
                            .join('')}
                    </select>
                </label>`
            )
            .join('')}${S.filterSel.some(Boolean) ? '<button type="button" class="an-btn an-btn--ghost" data-db-act="clearfilters">Clear</button>' : ''}`;
    }

    function widgetHtml(component, index) {
        const cell = S.layout.cells[index] || { column: 0, row: index * 8, colspan: 4, rowspan: 8 };
        const key = compKey(component);
        const title = component.header || component.title || '';
        const status = component.id && S.statusById.get(String(component.id));
        const refreshed = status && status.refreshDate ? `Refreshed ${formatAsOf(Date.parse(String(status.refreshDate).replace(/\+0000$/, 'Z')))}` : '';
        const { report } = reportFor(component);
        const kind = component.type === 'Report' || component.reportId ? kindOf(component, report) : 'unsupported';
        const tools =
            S.mode === 'edit'
                ? `${iconBtn('edit', 'Edit component', `data-db-edit="${index}"`)}${iconBtn('close', 'Remove component', `data-db-remove="${index}"`)}`
                : component.reportId
                  ? iconBtn('open', 'View report', `data-db-open="${escapeHtml(component.reportId)}"`)
                  : '';
        const style = `--c:${cell.column + 1};--cs:${cell.colspan};--r:${cell.row + 1};--rs:${cell.rowspan};--dbw-h:${Math.max(cell.rowspan <= 4 ? 150 : 260, cell.rowspan * S.layout.rowHeight)}px`;
        return `<article class="dbw dbw--${escapeHtml(kind.split('-')[0])}" data-db-widget="${index}" data-key="${escapeHtml(key)}" style="${style}"${refreshed ? ` title="${escapeHtml(refreshed)}"` : ''}>
            <header class="dbw-head"${S.mode === 'edit' && S.layout.grid ? ' data-db-drag' : ''}>
                ${S.mode === 'edit' && S.layout.grid ? `<span class="dbw-grip">${ICONS.grip}</span>` : ''}
                <h3>${escapeHtml(title || (kind === 'metric' ? '' : 'Untitled component'))}</h3>
                <div class="dbw-tools">${tools}</div>
            </header>
            <div class="dbw-body" data-db-body="${index}">${S.loading && !report ? '<div class="dbw-shimmer"><i></i><i></i><i></i></div>' : ''}</div>
            ${component.footer ? `<footer class="dbw-foot">${escapeHtml(component.footer)}</footer>` : ''}
            ${S.mode === 'edit' && S.layout.grid ? `<span class="dbw-resize" data-db-resize="${index}" aria-hidden="true">${ICONS.resize}</span>` : ''}
        </article>`;
    }

    function paintBody(component, index, body) {
        const { report, full } = reportFor(component);
        const status = component.id && S.statusById.get(String(component.id));
        if (component.type && component.type !== 'Report' && !component.reportId) {
            body.innerHTML = '<div class="dbw-empty">This component type isn\u2019t available offline.</div>';
            return;
        }
        if (!report) {
            if (status && status.errorMessage) {
                body.innerHTML = `<div class="dbw-empty is-error"><strong>Couldn\u2019t load</strong><span>${escapeHtml(status.errorMessage)}</span></div>`;
            } else if (!S.loading) {
                body.innerHTML = `<div class="dbw-empty">${offline() ? 'No cached result for this component yet.' : 'No data. Refresh the dashboard to load this component.'}</div>`;
            }
            return;
        }
        const props = component.properties || {};
        const kind = kindOf(component, report);
        const gauge = gaugeOptionsFrom(component);
        const aggName = props.aggregates && props.aggregates[0] && props.aggregates[0].name;
        let aggIndexes;
        if (full && aggName) {
            const list = (report.reportMetadata && report.reportMetadata.aggregates) || [];
            const idx = list.indexOf(aggName);
            if (idx >= 0) aggIndexes = [idx];
        }
        const rect = body.getBoundingClientRect();
        const width = Math.max(180, rect.width - 8);
        const height = Math.max(120, rect.height - 6);
        if (kind === 'metric') {
            const metric = aggIndexes ? metricAt(report, aggIndexes[0]) : extractMetric(report);
            body.innerHTML = metricHtml(metric, {
                breakPoints: gauge.breakPoints,
                label: gauge.label || aggregateLabelFor(report, aggName)
            });
        } else if (kind === 'gauge') {
            const metric = aggIndexes ? metricAt(report, aggIndexes[0]) : extractMetric(report);
            body.innerHTML = gaugeHtml(metric, gauge);
        } else if (kind === 'table' || kind === 'unsupported') {
            const model = buildReportModel(report);
            const view = defaultGridView(model);
            view.showDetails = false;
            body.innerHTML = `<div class="dbw-table">${reportGridHtml(model, view)}</div>`;
        } else {
            body.innerHTML = chartHtml(report, kind, {
                width,
                height,
                aggIndexes,
                showValues: gauge.showValues,
                legend: true
            });
        }
    }

    function metricAt(report, index) {
        const grand = ((report.factMap || {})['T!T'] || {}).aggregates || [];
        const cell = grand[index];
        if (!cell) return extractMetric(report);
        return { value: cell.label != null ? String(cell.label) : String(cell.value), numeric: Number(cell.value) || 0 };
    }

    function paintBodies() {
        if (!S.meta) return;
        (S.meta.components || []).forEach((component, index) => {
            const body = grid.querySelector(`[data-db-body="${index}"]`);
            if (body) paintBody(component, index, body);
        });
    }

    function renderGrid() {
        if (!S.meta) {
            grid.innerHTML = S.loading
                ? `<div class="db-skeleton">${'<i></i>'.repeat(6)}</div>`
                : `<div class="an-empty">${ICONS.dashboard}<strong>Dashboard unavailable</strong><span>${escapeHtml(S.message || 'Try again when you\u2019re online.')}</span></div>`;
            return;
        }
        const components = S.meta.components || [];
        if (!components.length) {
            grid.innerHTML = `<div class="an-empty">${ICONS.dashboard}<strong>This dashboard is empty</strong><span>${S.mode === 'edit' ? 'Add a component to get started.' : 'Edit the dashboard to add components.'}</span></div>`;
            return;
        }
        grid.style.setProperty('--db-row', `${S.layout.rowHeight}px`);
        grid.style.setProperty('--db-gap', `${GAP}px`);
        const order = components
            .map((c, i) => ({ c, i, cell: S.layout.cells[i] || { row: 0, column: 0 } }))
            .sort((a, b) => a.cell.row - b.cell.row || a.cell.column - b.cell.column);
        grid.innerHTML = order.map(({ c, i }) => widgetHtml(c, i)).join('');
        grid.classList.toggle('is-edit', S.mode === 'edit' && S.layout.grid);
        updateStacked();
        requestAnimationFrame(paintBodies);
    }

    function updateStacked() {
        const stacked = grid.clientWidth > 0 && grid.clientWidth < 720;
        S.stacked = stacked;
        grid.classList.toggle('is-stacked', stacked);
    }

    function publishDashboardContext() {
        if (S.destroyed) return;
        const meta = S.meta || {};
        const components = (meta.components || []).map((component) => {
            const title = component.header || component.title || 'Untitled';
            const reportId = component.reportId || '';
            const { report } = reportFor(component);
            if (!report) {
                const status = component.id && S.statusById.get(String(component.id));
                return { title, kind: 'empty', value: '', note: (status && status.errorMessage) || '', reportId };
            }
            const kind = kindOf(component, report);
            if (kind === 'metric' || kind === 'gauge') {
                const metric = extractMetric(report);
                return { title, kind, value: metric.value === '\u2014' ? '' : metric.value, note: '', reportId };
            }
            const model = buildReportModel(report);
            const grand = (model.aggCols || [])
                .slice(0, 2)
                .map((col) => {
                    const cell = model.grand[col.index];
                    return cell && cell.label ? `${col.label} ${cell.label}` : '';
                })
                .filter(Boolean)
                .join(', ');
            const top = (model.nodes || [])
                .slice(0, 3)
                .map((node) => node.label)
                .filter(Boolean)
                .join(', ');
            return {
                title,
                kind,
                value: grand || (model.totalRows != null ? `${model.totalRows} records` : ''),
                note: top,
                reportId
            };
        });
        const filters = (meta.filters || []).map((filter, index) => {
            const selected = S.filterSel[index];
            const option = (filter.options || []).find((item) => item.id === selected);
            return { name: filter.name, value: option ? optionLabel(filter, option) : 'All' };
        });
        publishAnalyticsSnapshot({
            kind: 'dashboard',
            id: S.id,
            name: meta.name || S.title || 'Dashboard',
            folder: meta.folderName || S.folderName || '',
            status: S.loading && !components.length ? 'loading' : 'ready',
            filters,
            components
        });
    }

    function renderAll() {
        renderHead();
        renderBanner();
        renderFilters();
        renderGrid();
        publishDashboardContext();
    }

    /* ---------- Loading ---------- */

    async function load() {
        const [cachedRes, cachedDesc] = await Promise.all([idbGet(RESULT_PREFIX + S.id), idbGet(DESCRIBE_PREFIX + S.id)]);
        if (cachedRes && cachedRes.payload) {
            S.results = cachedRes.payload;
            S.savedAt = cachedRes.savedAt;
            indexResults(S.results);
            const meta = (cachedDesc && cachedDesc.payload) || S.results.dashboardMetadata;
            if (meta) adoptMeta(meta);
            renderAll();
        } else {
            renderAll();
        }
        try {
            const [desc, results] = await Promise.all([
                describeDashboard(S.id).catch(() => null),
                fetchResults()
            ]);
            if (S.destroyed) return;
            const meta = desc || (results && results.dashboardMetadata);
            if (meta && !dirty()) {
                const keepFilters = S.filterSel.slice();
                adoptMeta(meta);
                if (keepFilters.length) S.filterSel = keepFilters;
            }
            if (desc) await idbSet(DESCRIBE_PREFIX + S.id, desc);
            S.loading = false;
            renderAll();
            const hasComponents = S.meta && (S.meta.components || []).length > 0;
            if (hasComponents && !S.dataById.size && !offline()) refresh();
        } catch (error) {
            S.loading = false;
            if (!S.meta) setMessage(errorMessage(error), 'error');
            else if (!isNetworkError(error) && !offline()) setMessage(errorMessage(error), 'error');
            renderAll();
        }
    }

    async function fetchResults() {
        let payload = await getDashboardResults(S.id, S.filterSel);
        for (let i = 0; i < 6; i += 1) {
            const running = (payload.componentData || []).some((row) =>
                /RUNNING|NEW|PENDING/i.test(String((row.status && row.status.refreshStatus) || row.status || ''))
            );
            if (!running) break;
            await new Promise((resolve) => setTimeout(resolve, 1500));
            payload = await getDashboardResults(S.id, S.filterSel);
        }
        S.results = payload;
        S.savedAt = Date.now();
        indexResults(payload);
        if (!S.filterSel.some(Boolean)) await idbSet(RESULT_PREFIX + S.id, payload);
        return payload;
    }

    async function refresh() {
        if (S.refreshing) return;
        S.refreshing = true;
        renderHead();
        grid.classList.add('is-refreshing');
        try {
            try {
                await refreshDashboard(S.id, S.filterSel);
            } catch (error) {
                if (isNetworkError(error)) throw error;
            }
            await new Promise((resolve) => setTimeout(resolve, 900));
            await fetchResults();
            setMessage('');
            toast('Dashboard refreshed');
        } catch (error) {
            setMessage(errorMessage(error), isNetworkError(error) ? 'offline' : 'error');
        } finally {
            S.refreshing = false;
            grid.classList.remove('is-refreshing');
            renderAll();
        }
    }

    async function applyFilter(index, value) {
        S.filterSel[index] = value;
        renderFilters();
        grid.classList.add('is-refreshing');
        try {
            await fetchResults();
            setMessage('');
        } catch (error) {
            setMessage(`Couldn\u2019t apply the filter: ${errorMessage(error)}`, 'error');
        } finally {
            grid.classList.remove('is-refreshing');
            renderHead();
            renderGrid();
            publishDashboardContext();
        }
    }

    /* ---------- Editing ---------- */

    function mutateMeta(fn) {
        fn(S.meta);
        renderHead();
        renderFilters();
        renderGrid();
    }

    function nextFreeRow() {
        return Math.max(0, ...S.layout.cells.map((c) => c.row + c.rowspan));
    }

    async function reportCatalog() {
        const cached = cacheRead('reports.catalog.v2');
        if (cached && Array.isArray(cached.payload) && cached.payload.length) return cached.payload;
        try {
            return await sfSoql('SELECT Id, Name, FolderName, Format FROM Report ORDER BY LastRunDate DESC NULLS LAST, Name ASC LIMIT 500');
        } catch (_err) {
            return [];
        }
    }

    function componentProps(display, report, previous = {}) {
        const meta = (report && report.reportMetadata) || {};
        const aggs = meta.aggregates || [];
        const aggName = (previous.aggregates && previous.aggregates[0] && previous.aggregates[0].name) || aggs[0] || 'RowCount';
        const grouping = (meta.groupingsDown || [])[0];
        const groupings = grouping
            ? [{ name: grouping.name, sortOrder: display === 'report' ? null : 'Asc', sortAggregate: null, inheritedReportSort: null }]
            : null;
        const base = {
            aggregates: [{ name: aggName }],
            autoSelectColumns: false,
            drillUrl: null,
            filterColumns: previous.filterColumns || [],
            maxRows: null,
            reportFormat: meta.reportFormat || previous.reportFormat || 'SUMMARY',
            sort: null
        };
        if (display === 'Metric') {
            return {
                ...base,
                groupings: null,
                useReportChart: false,
                visualizationType: 'Metric',
                visualizationProperties: { decimalPrecision: null, displayUnits: 'auto', metricLabel: null, showRange: false }
            };
        }
        if (display === 'Gauge') {
            const prevVis = previous.visualizationType === 'Gauge' ? previous.visualizationProperties : null;
            return {
                ...base,
                groupings: null,
                useReportChart: false,
                visualizationType: 'Gauge',
                visualizationProperties: prevVis || {
                    breakPoints: [
                        {
                            aggregateName: aggName,
                            breaks: [
                                { color: 'c23934', lowerBound: 0, upperBound: 33 },
                                { color: 'ffb75d', lowerBound: 33, upperBound: 66 },
                                { color: '00716b', lowerBound: 66, upperBound: 100 }
                            ]
                        }
                    ],
                    decimalPrecision: null,
                    displayUnits: 'auto',
                    showPercentages: false,
                    showRange: true,
                    showTotal: false
                }
            };
        }
        if (display === 'Table') {
            return {
                ...base,
                groupings,
                useReportChart: false,
                visualizationType: 'Table',
                visualizationProperties: {
                    tableColumns: [
                        ...(groupings || []).map((g) => ({ column: g.name, isPercent: false, scale: null, showTotal: false, type: 'grouping' })),
                        { column: aggName, isPercent: false, scale: null, showTotal: false, type: 'aggregate' }
                    ]
                }
            };
        }
        const vis = display === 'report' ? (meta.chart && meta.chart.summaryVisualizationTypes && meta.chart.summaryVisualizationTypes[0]) || 'Column' : display;
        return {
            ...base,
            groupings,
            useReportChart: display === 'report',
            visualizationType: display === 'report' ? previous.visualizationType || vis : display,
            visualizationProperties: {
                aggregateVisualizationInfos: [{ axis: 'Y', visualizationType: /Bar|Column/.test(vis) ? vis.replace('Stacked', '') : 'Column' }],
                axisRange: { max: null, min: null, rangeType: 'auto' },
                decimalPrecision: null,
                displayUnits: 'auto',
                groupByType: 'none',
                legendPosition: null,
                showValues: true
            }
        };
    }

    async function addComponent() {
        const reports = await reportCatalog();
        let chosen = null;
        const res = await openModal({
            title: 'Add component',
            wide: true,
            body: `
                <label class="an-search">${ICONS.search}<input type="search" data-pick-search placeholder="Search reports"/></label>
                <div class="an-pick" data-pick-list></div>
                <div class="an-field-row">
                    <label class="an-field"><span>Title</span><input class="an-input" name="title" maxlength="80" placeholder="Component title"/></label>
                    <label class="an-field"><span>Display as</span><select class="an-input" name="display">${DISPLAY_OPTIONS.map((o) => `<option value="${o.value}"${o.value === 'Column' ? ' selected' : ''}>${escapeHtml(o.label)}</option>`).join('')}</select></label>
                </div>`,
            actions: [
                { id: 'cancel', label: 'Cancel' },
                { id: 'add', label: 'Add', primary: true }
            ],
            onMount(overlay) {
                const list = overlay.querySelector('[data-pick-list]');
                const search = overlay.querySelector('[data-pick-search]');
                const title = overlay.querySelector('[name="title"]');
                const addBtn = overlay.querySelector('[data-modal-action="add"]');
                addBtn.disabled = true;
                const paint = () => {
                    const term = (search.value || '').trim().toLowerCase();
                    const hits = reports
                        .filter((r) => !term || `${r.Name} ${r.FolderName || ''}`.toLowerCase().includes(term))
                        .slice(0, 80);
                    list.innerHTML = hits.length
                        ? hits
                              .map(
                                  (r) =>
                                      `<button type="button" class="an-pick-item${chosen && chosen.Id === r.Id ? ' is-on' : ''}" data-pick="${escapeHtml(r.Id)}">${ICONS.report}<span><strong>${escapeHtml(r.Name)}</strong><em>${escapeHtml(r.FolderName || 'Private Reports')}${r.Format ? ` \u00b7 ${escapeHtml(r.Format)}` : ''}</em></span></button>`
                              )
                              .join('')
                        : '<p class="an-modal-text">No reports match.</p>';
                };
                paint();
                search.addEventListener('input', paint);
                list.addEventListener('click', (event) => {
                    const item = event.target.closest('[data-pick]');
                    if (!item) return;
                    chosen = reports.find((r) => r.Id === item.dataset.pick);
                    if (chosen && !title.value) title.value = chosen.Name;
                    addBtn.disabled = !chosen;
                    paint();
                });
            }
        });
        if (res.action !== 'add' || !chosen) return;
        let report = null;
        try {
            report = await ensureReport(chosen.Id);
        } catch (error) {
            setMessage(`Couldn\u2019t load that report: ${errorMessage(error)}`, 'error');
            return;
        }
        const display = res.form.display || 'Column';
        if (!['Metric', 'Gauge'].includes(display) && !((report.reportMetadata || {}).groupingsDown || []).length) {
            setMessage('That report has no groupings, so it can only be shown as a metric or gauge. Added it as a metric.', 'warn');
        }
        const hasGroups = ((report.reportMetadata || {}).groupingsDown || []).length > 0;
        const finalDisplay = hasGroups ? display : display === 'Gauge' ? 'Gauge' : 'Metric';
        const component = {
            header: String(res.form.title || chosen.Name).slice(0, 80),
            footer: null,
            title: null,
            type: 'Report',
            reportId: chosen.Id,
            properties: componentProps(finalDisplay, report),
            __preview: true
        };
        compKey(component);
        const metricLike = finalDisplay === 'Metric' || finalDisplay === 'Gauge';
        const cell = { column: 0, row: nextFreeRow(), colspan: metricLike ? 3 : 6, rowspan: metricLike ? 4 : 8 };
        mutateMeta((meta) => {
            meta.components = [...(meta.components || []), component];
            S.layout.cells.push(cell);
        });
        const el = grid.querySelector(`[data-key="${CSS.escape(component.__key)}"]`);
        if (el) el.scrollIntoView({ behavior: 'smooth', block: 'center' });
    }

    async function editComponent(index) {
        const component = S.meta.components[index];
        if (!component) return;
        const current = displayValueOf(component);
        const res = await openModal({
            title: 'Edit component',
            body: `
                <label class="an-field"><span>Title</span><input class="an-input" name="header" maxlength="80" value="${escapeHtml(component.header || '')}"/></label>
                <label class="an-field"><span>Footer</span><input class="an-input" name="footer" maxlength="255" value="${escapeHtml(component.footer || '')}"/></label>
                <label class="an-field"><span>Display as</span><select class="an-input" name="display">${DISPLAY_OPTIONS.map((o) => `<option value="${o.value}"${o.value === current ? ' selected' : ''}>${escapeHtml(o.label)}</option>`).join('')}</select></label>`,
            actions: [
                { id: 'cancel', label: 'Cancel' },
                { id: 'apply', label: 'Apply', primary: true }
            ]
        });
        if (res.action !== 'apply') return;
        const display = res.form.display || current;
        let report = null;
        if (display !== current) {
            try {
                report = await ensureReport(component.reportId);
            } catch (error) {
                setMessage(`Couldn\u2019t load the source report: ${errorMessage(error)}`, 'error');
                return;
            }
            if (!['Metric', 'Gauge'].includes(display) && !((report.reportMetadata || {}).groupingsDown || []).length) {
                setMessage('The source report has no groupings, so this component can only be a metric or gauge.', 'warn');
                return;
            }
        }
        mutateMeta(() => {
            component.header = String(res.form.header || '').trim() || null;
            component.footer = String(res.form.footer || '').trim() || null;
            if (display !== current) {
                component.properties = componentProps(display, report, component.properties || {});
                component.__preview = true;
                const cell = S.layout.cells[index];
                if (cell && (display === 'Metric' || display === 'Gauge') && cell.rowspan > 6) cell.rowspan = 4;
                if (cell && !['Metric', 'Gauge'].includes(display) && cell.rowspan < 6) cell.rowspan = 8;
            }
        });
    }

    async function removeComponent(index) {
        const component = S.meta.components[index];
        if (!component) return;
        const ok = await confirmModal('Remove component?', `Remove \u201c${component.header || 'this component'}\u201d from the dashboard? It stays until you save.`, 'Remove');
        if (!ok) return;
        mutateMeta((meta) => {
            meta.components = meta.components.filter((_, i) => i !== index);
            S.layout.cells = S.layout.cells.filter((_, i) => i !== index);
        });
    }

    async function editFilters() {
        const filters = clone((S.meta && S.meta.filters) || []);
        const opSelect = (value) =>
            `<select class="an-input an-input--sm" data-f-op>${FILTER_OPS.map(([v, l]) => `<option value="${v}"${v === value ? ' selected' : ''}>${escapeHtml(l)}</option>`).join('')}</select>`;
        const optionRow = (o) => `
            <div class="db-fopt" data-f-opt data-id="${escapeHtml(o.id || '')}">
                ${opSelect(o.operation || 'equals')}
                <input class="an-input an-input--sm" data-f-value placeholder="Value" value="${escapeHtml(o.operation === 'between' ? `${o.startValue || ''}..${o.endValue || ''}` : o.value || '')}"/>
                <input class="an-input an-input--sm" data-f-alias placeholder="Label (optional)" value="${escapeHtml(o.alias || '')}"/>
                ${iconBtn('close', 'Remove value', 'data-f-remove-opt')}
            </div>`;
        const filterBlock = (f, i) => `
            <fieldset class="db-fblock" data-f-block="${i}">
                <legend><input class="an-input an-input--sm" data-f-name value="${escapeHtml(f.name || '')}" aria-label="Filter label"/></legend>
                <div data-f-opts>${(f.options || []).map(optionRow).join('')}</div>
                <button type="button" class="an-btn an-btn--ghost" data-f-add-opt>${ICONS.plus}<span>Add value</span></button>
            </fieldset>`;
        const res = await openModal({
            title: 'Dashboard filters',
            wide: true,
            body: filters.length
                ? `<p class="an-modal-text">Edit the values people can pick for each filter. Filter fields are set in Lightning.</p>${filters.map(filterBlock).join('')}`
                : '<p class="an-modal-text">This dashboard has no filters. Add a filter field in Lightning Dashboard Builder, then edit its values here.</p>',
            actions: filters.length
                ? [
                      { id: 'cancel', label: 'Cancel' },
                      { id: 'apply', label: 'Apply', primary: true }
                  ]
                : [{ id: 'cancel', label: 'Close' }],
            onMount(overlay) {
                overlay.addEventListener('click', (event) => {
                    const add = event.target.closest('[data-f-add-opt]');
                    if (add) {
                        const opts = add.parentElement.querySelector('[data-f-opts]');
                        opts.insertAdjacentHTML('beforeend', optionRow({ operation: 'equals', value: '' }));
                        return;
                    }
                    const remove = event.target.closest('[data-f-remove-opt]');
                    if (remove) remove.closest('[data-f-opt]').remove();
                });
            }
        });
        if (res.action !== 'apply') return;
        const next = filters.map((f, i) => {
            const block = res.root.querySelector(`[data-f-block="${i}"]`);
            const options = [...block.querySelectorAll('[data-f-opt]')].map((row) => {
                const op = row.querySelector('[data-f-op]').value;
                const raw = row.querySelector('[data-f-value]').value.trim();
                const prev = (f.options || []).find((o) => o.id && o.id === row.dataset.id) || {};
                const [start, end] = op === 'between' ? raw.split('..') : [null, null];
                return {
                    ...prev,
                    id: row.dataset.id || null,
                    operation: op,
                    value: op === 'between' ? null : raw,
                    startValue: op === 'between' ? (start || '').trim() : null,
                    endValue: op === 'between' ? (end || '').trim() : null,
                    alias: row.querySelector('[data-f-alias]').value.trim() || null
                };
            });
            return { ...f, name: block.querySelector('[data-f-name]').value.trim() || f.name, options };
        });
        mutateMeta((meta) => {
            meta.filters = next;
        });
        toast('Filter changes will apply when you save');
    }

    async function save() {
        if (!dirty() || S.saving) return;
        S.saving = true;
        renderHead();
        try {
            await saveDashboard(S.id, stripForSave(S.meta, S.layout));
            toast('Dashboard saved');
            setMessage('');
            S.reportCache.clear();
            const desc = await describeDashboard(S.id).catch(() => null);
            if (desc) {
                await idbSet(DESCRIBE_PREFIX + S.id, desc);
                adoptMeta(desc);
            } else {
                S.saved = signature();
            }
            (S.meta.components || []).forEach((c) => delete c.__preview);
            S.mode = 'view';
            renderAll();
            refresh();
        } catch (error) {
            setMessage(`Save failed: ${errorMessage(error)}`, 'error');
        } finally {
            S.saving = false;
            renderHead();
        }
    }

    async function saveAs() {
        let folders = [];
        try {
            folders = await listFolders('Dashboard');
        } catch (_err) {
            folders = [];
        }
        const res = await openModal({
            title: 'Save dashboard as',
            body: `
                <label class="an-field"><span>Dashboard name</span><input class="an-input" name="name" maxlength="80" value="${escapeHtml(`Copy of ${S.meta.name || ''}`.slice(0, 80))}"/></label>
                <label class="an-field"><span>Folder</span><select class="an-input" name="folderId">${folders
                    .map((f) => `<option value="${escapeHtml(f.id)}"${f.id === S.meta.folderId ? ' selected' : ''}>${escapeHtml(f.name)}</option>`)
                    .join('')}</select></label>`,
            actions: [
                { id: 'cancel', label: 'Cancel' },
                { id: 'save', label: 'Save', primary: true }
            ]
        });
        if (res.action !== 'save') return;
        const name = String(res.form.name || '').trim();
        if (!name) return;
        S.saving = true;
        renderHead();
        try {
            const out = await saveDashboardAs(S.id, stripForSave(S.meta, S.layout), {
                name,
                folderId: res.form.folderId || S.meta.folderId
            });
            toast('Dashboard saved');
            if (out && out.id && options.onOpenDashboard) {
                S.destroyed = true;
                cleanup();
                options.onOpenDashboard(out.id);
                return;
            }
        } catch (error) {
            setMessage(`Save failed: ${errorMessage(error)}`, 'error');
        } finally {
            if (!S.destroyed) {
                S.saving = false;
                renderHead();
            }
        }
    }

    async function leaveEdit() {
        if (dirty()) {
            const ok = await confirmModal('Discard changes?', 'Your dashboard changes haven\u2019t been saved.');
            if (!ok) return;
            const desc = await idbGet(DESCRIBE_PREFIX + S.id);
            const meta = (desc && desc.payload) || (S.results && S.results.dashboardMetadata);
            if (meta) adoptMeta(meta);
        }
        S.mode = 'view';
        setMessage('');
        renderAll();
    }

    async function leave() {
        if (dirty()) {
            const ok = await confirmModal('Discard changes?', 'Your dashboard changes haven\u2019t been saved.');
            if (!ok) return;
        }
        S.destroyed = true;
        cleanup();
        if (options.onBack) options.onBack();
    }

    /* ---------- Drag / resize ---------- */

    let gesture = null;

    function metrics() {
        const width = grid.clientWidth;
        const colW = (width - GAP * (COLS - 1)) / COLS;
        return { stepX: colW + GAP, stepY: S.layout.rowHeight + GAP, colW };
    }

    function showGhost(cell) {
        let ghost = grid.querySelector('.db-ghost');
        if (!ghost) {
            ghost = document.createElement('div');
            ghost.className = 'db-ghost';
            grid.appendChild(ghost);
        }
        ghost.style.cssText = `grid-column:${cell.column + 1} / span ${cell.colspan};grid-row:${cell.row + 1} / span ${cell.rowspan};`;
    }

    grid.addEventListener('pointerdown', (event) => {
        if (S.mode !== 'edit' || !S.layout.grid || S.stacked || event.button !== 0) return;
        const handle = event.target.closest('[data-db-resize]');
        const head = event.target.closest('[data-db-drag]');
        if (!handle && (!head || event.target.closest('button'))) return;
        const el = event.target.closest('[data-db-widget]');
        const index = Number(el.dataset.dbWidget);
        const start = { ...S.layout.cells[index] };
        gesture = { kind: handle ? 'resize' : 'move', index, el, start, x: event.clientX, y: event.clientY, cell: { ...start } };
        try {
            el.setPointerCapture(event.pointerId);
        } catch (_err) {
            /* capture is best-effort */
        }
        el.classList.add('is-moving');
        showGhost(start);
        event.preventDefault();
    });

    grid.addEventListener('pointermove', (event) => {
        if (!gesture) return;
        const { stepX, stepY } = metrics();
        const dx = event.clientX - gesture.x;
        const dy = event.clientY - gesture.y;
        const s = gesture.start;
        if (gesture.kind === 'move') {
            gesture.el.style.transform = `translate(${dx}px, ${dy}px)`;
            gesture.cell = {
                ...s,
                column: Math.max(0, Math.min(COLS - s.colspan, s.column + Math.round(dx / stepX))),
                row: Math.max(0, s.row + Math.round(dy / stepY))
            };
        } else {
            gesture.cell = {
                ...s,
                colspan: Math.max(2, Math.min(COLS - s.column, s.colspan + Math.round(dx / stepX))),
                rowspan: Math.max(3, s.rowspan + Math.round(dy / stepY))
            };
        }
        showGhost(gesture.cell);
    });

    function endGesture(commit) {
        if (!gesture) return;
        const { index, cell, el, start } = gesture;
        gesture = null;
        el.classList.remove('is-moving');
        el.style.transform = '';
        const ghost = grid.querySelector('.db-ghost');
        if (ghost) ghost.remove();
        const changed = ['column', 'row', 'colspan', 'rowspan'].some((k) => cell[k] !== start[k]);
        if (!commit || !changed) return;
        S.layout.cells[index] = cell;
        resolveCollisions(S.layout.cells, index);
        renderHead();
        renderGrid();
    }

    grid.addEventListener('pointerup', () => endGesture(true));
    grid.addEventListener('pointercancel', () => endGesture(false));

    /* ---------- Events ---------- */

    root.addEventListener('click', (event) => {
        const t = event.target;
        const act = t.closest('[data-db-act]');
        if (act && !act.disabled) {
            const a = act.dataset.dbAct;
            if (a === 'back') return leave();
            if (a === 'refresh') return refresh();
            if (a === 'edit') {
                S.mode = 'edit';
                renderAll();
                return;
            }
            if (a === 'done') return leaveEdit();
            if (a === 'add') return addComponent();
            if (a === 'filters') return editFilters();
            if (a === 'save') return save();
            if (a === 'saveas') return saveAs();
            if (a === 'clearfilters') {
                S.filterSel = S.filterSel.map(() => '');
                return applyFilter(0, '');
            }
        }
        const open = t.closest('[data-db-open]');
        if (open) {
            window.dispatchEvent(
                new CustomEvent('zeta-navigate-record', { detail: { recordId: open.dataset.dbOpen, objectApiName: 'Report' } })
            );
            return;
        }
        const edit = t.closest('[data-db-edit]');
        if (edit) return editComponent(Number(edit.dataset.dbEdit));
        const remove = t.closest('[data-db-remove]');
        if (remove) return removeComponent(Number(remove.dataset.dbRemove));
    });

    root.addEventListener('change', (event) => {
        const sel = event.target.closest('[data-db-filter]');
        if (sel) applyFilter(Number(sel.dataset.dbFilter), sel.value);
    });

    root.addEventListener('input', (event) => {
        if (event.target.matches('[data-db-name]') && S.meta) {
            S.meta.name = event.target.value;
            const needs = dirty() !== Boolean(root.querySelector('.rb-status.is-dirty'));
            if (needs) {
                const pos = event.target.selectionStart;
                renderHead();
                const next = root.querySelector('[data-db-name]');
                next.focus();
                next.setSelectionRange(pos, pos);
            }
        }
    });

    const onNet = () => {
        renderHead();
        renderBanner();
        renderFilters();
    };
    window.addEventListener('online', onNet);
    window.addEventListener('offline', onNet);

    let frame = 0;
    let lastWidth = 0;
    const ro =
        typeof ResizeObserver !== 'undefined'
            ? new ResizeObserver(() => {
                  cancelAnimationFrame(frame);
                  frame = requestAnimationFrame(() => {
                      if (S.destroyed || gesture) return;
                      const w = grid.clientWidth;
                      if (Math.abs(w - lastWidth) < 4) return;
                      lastWidth = w;
                      updateStacked();
                      paintBodies();
                  });
              })
            : null;
    if (ro) ro.observe(grid);

    function cleanup() {
        window.removeEventListener('online', onNet);
        window.removeEventListener('offline', onNet);
        if (ro) ro.disconnect();
    }

    load();

    return {
        destroy() {
            S.destroyed = true;
            cleanup();
        },
        isDirty: () => dirty()
    };
}
