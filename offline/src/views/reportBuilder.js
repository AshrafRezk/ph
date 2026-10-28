import { idbGet, idbSet } from './tabCache.js';
import {
    analyticsOffline,
    describeReport,
    describeReportType,
    listFolders,
    runReportWithMetadata,
    runSavedReport,
    saveReport,
    saveReportAs
} from './analyticsApi.js';
import {
    AGGREGATE_KINDS,
    CHART_TYPES,
    DATE_TYPES,
    FORMATS,
    NUMERIC_TYPES,
    addColumn,
    addFilter,
    addGrouping,
    aggregateLabel,
    aggregateParts,
    buildFieldCatalog,
    chartTypeByKind,
    cloneMeta,
    durationLabel,
    durationRange,
    fieldLabel,
    maxGroupings,
    metaSignature,
    moveTo,
    operatorLabel,
    operatorsFor,
    removeColumn,
    removeFilter,
    removeGrouping,
    setBooleanFilter,
    setChart,
    setDateFilter,
    setFormat,
    toggleAggregate,
    updateFilter,
    updateGrouping,
    validateMeta
} from './reportMetadata.js';
import { buildReportModel, defaultGridView, modelToCsv, reportGridHtml, summaryStripHtml } from './reportGrid.js';
import { summarizeReportResult } from '../analyticsBrief.js';
import { publishAnalyticsSnapshot } from '../analyticsContext.js';
import { chartHtml, installChartTooltips, normalizeChartKind } from './reportCharts.js';
import { ICONS, confirmModal, downloadText, iconBtn, openModal, safeFileName, toast } from './analyticsUi.js';
import { escapeHtml, errorMessage, formatSynced, isNetworkError } from './viewUtils.js';

const RESULT_PREFIX = 'report.';
const DESCRIBE_PREFIX = 'reportdesc.';
const DATE_LITERALS = [
    'TODAY',
    'YESTERDAY',
    'THIS_WEEK',
    'LAST_WEEK',
    'THIS_MONTH',
    'LAST_MONTH',
    'THIS_QUARTER',
    'THIS_YEAR',
    'LAST_N_DAYS:30',
    'LAST_N_DAYS:90'
];

const CHART_GLYPHS = {
    vbar: '<path d="M4 16V9M8 16V5M12 16v-6M16 16V7"/>',
    hbar: '<path d="M4 4h9M4 8h12M4 12h6M4 16h10"/>',
    'vbar-stacked': '<path d="M5 16V8M10 16V4M15 16v-6"/><path d="M5 12v4M10 10v6M15 13v3" stroke-opacity=".45"/>',
    'hbar-stacked': '<path d="M4 5h8M4 10h12M4 15h6"/><path d="M8 5h4M11 10h5M4 15h3" stroke-opacity=".45"/>',
    'vbar-stack100': '<path d="M5 16V4M10 16V4M15 16V4"/><path d="M5 10v6M10 8v8M15 12v4" stroke-opacity=".45"/>',
    'hbar-stack100': '<path d="M4 5h12M4 10h12M4 15h12"/><path d="M4 5h6M4 10h9M4 15h4" stroke-opacity=".45"/>',
    'vbar-grouped': '<path d="M4 16V8M7 16V5M12 16V10M15 16V6"/>',
    'hbar-grouped': '<path d="M4 4h9M4 7h12M4 12h6M4 15h10"/>',
    line: '<path d="M3 14l4-5 4 3 6-7" fill="none"/>',
    donut: '<circle cx="10" cy="10" r="5.5" fill="none" stroke-width="3.2"/>',
    pie: '<path d="M10 4a6 6 0 1 0 6 6h-6z" fill="currentColor" stroke="none"/><path d="M11.5 2.8a6.5 6.5 0 0 1 5.7 5.7h-5.7z" fill="currentColor" stroke="none" opacity=".45"/>',
    funnel: '<path d="M3 4h14M5 8h10M7 12h6M9 16h2"/>',
    scatter: '<circle cx="5" cy="13" r="1.4"/><circle cx="9" cy="8" r="1.4"/><circle cx="13" cy="11" r="1.4"/><circle cx="15" cy="5" r="1.4"/>'
};

function glyph(kind) {
    return `<svg viewBox="0 0 20 20" aria-hidden="true" class="rb-glyph" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round">${CHART_GLYPHS[kind] || CHART_GLYPHS.vbar}</svg>`;
}

function dataSignature(meta) {
    const copy = { ...(meta || {}) };
    delete copy.chart;
    delete copy.name;
    delete copy.description;
    return metaSignature(copy);
}

/**
 * Mounts a Lightning-style report run page + builder in `container`.
 * options: { reportId?, reportType?, typeLabel?, onBack(), onOpenReport(id) }
 */
export function mountReportBuilder(container, options = {}) {
    installChartTooltips();
    const S = {
        id: options.reportId || null,
        isNew: !options.reportId,
        folderName: options.folderName || '',
        listName: options.name || '',
        describe: null,
        catalog: buildFieldCatalog(null),
        saved: null,
        meta: null,
        result: null,
        model: null,
        lastRunSig: '',
        mode: options.reportId ? 'run' : 'edit',
        view: defaultGridView(null),
        running: false,
        runToken: 0,
        runTimer: null,
        savedAt: null,
        message: '',
        messageTone: 'info',
        pendingOffline: false,
        pop: null,
        sideTab: 'outline',
        fieldSearch: '',
        openField: null,
        history: [],
        future: [],
        saving: false,
        destroyed: false
    };

    container.innerHTML = `
        <section class="rb" data-mode="${S.mode}">
            <header class="rb-head" data-rb-head></header>
            <div data-rb-banner></div>
            <div class="rb-filterbar" data-rb-filters></div>
            <div class="rb-body">
                <aside class="rb-side" data-rb-side>
                    <div class="rb-tabs" role="tablist">
                        <button type="button" role="tab" data-rb-tab="outline">Outline</button>
                        <button type="button" role="tab" data-rb-tab="fields">Fields</button>
                    </div>
                    <div class="rb-side-panel" data-rb-panel="outline"></div>
                    <div class="rb-side-panel" data-rb-panel="fields" hidden>
                        <label class="rb-search">${ICONS.search}<input type="search" data-rb-field-search placeholder="Search fields" /></label>
                        <div class="rb-field-list" data-rb-field-list></div>
                    </div>
                </aside>
                <main class="rb-main">
                    <div data-rb-strip></div>
                    <section class="rb-card rb-chart-card" data-rb-chart></section>
                    <section class="rb-card rb-table-card">
                        <div class="rb-card-bar">
                            <label class="rb-search rb-search--sm">${ICONS.search}<input type="search" data-rb-grid-search placeholder="Search results" /></label>
                            <label class="rb-switch" data-rb-details-wrap><input type="checkbox" data-rb-details /><span>Detail rows</span></label>
                            <span class="rb-count" data-rb-count></span>
                        </div>
                        <div class="rb-grid" data-rb-grid></div>
                    </section>
                </main>
            </div>
        </section>`;

    const root = container.querySelector('.rb');
    const $ = (sel) => root.querySelector(sel);

    /* ---------- Derived ---------- */

    const offline = () => analyticsOffline();
    const dirty = () => S.meta && S.saved && metaSignature(S.meta) !== metaSignature(S.saved);
    const groupsDown = () => (S.meta && S.meta.groupingsDown) || [];
    const groupsAcross = () => (S.meta && S.meta.groupingsAcross) || [];

    function setMessage(text, tone = 'info') {
        S.message = text || '';
        S.messageTone = tone;
        renderBanner();
    }

    /* ---------- Rendering ---------- */

    function renderHead() {
        const meta = S.meta || {};
        const format = FORMATS.find((f) => f.value === meta.reportFormat);
        const typeLabel = (meta.reportType && meta.reportType.label) || options.typeLabel || '';
        const eyebrow = ['Report', format && format.label, typeLabel, S.folderName].filter(Boolean).join(' \u00b7 ');
        const isEdit = S.mode === 'edit';
        const isDirty = dirty();
        const saveDisabled = offline() || S.saving || !S.meta || (!isDirty && !S.isNew);
        const title = isEdit
            ? `<input class="rb-name-input" data-rb-name value="${escapeHtml(meta.name || '')}" aria-label="Report name" maxlength="40" />`
            : `<h1 class="rb-name">${escapeHtml(meta.name || 'Report')}</h1>`;
        const status = S.running
            ? '<span class="rb-status is-running"><i></i>Running\u2026</span>'
            : isDirty
              ? '<span class="rb-status is-dirty">Unsaved changes</span>'
              : '';
        const actions = isEdit
            ? `
                ${iconBtn('undo', 'Undo', `data-rb-act="undo"${S.history.length ? '' : ' disabled'}`)}
                ${iconBtn('redo', 'Redo', `data-rb-act="redo"${S.future.length ? '' : ' disabled'}`)}
                <button type="button" class="an-btn" data-rb-act="run"${S.running ? ' disabled' : ''}>${ICONS.refresh}<span>Run</span></button>
                <button type="button" class="an-btn" data-rb-act="saveas"${offline() || !S.meta ? ' disabled' : ''}>Save As</button>
                <button type="button" class="an-btn an-btn--primary" data-rb-act="save"${saveDisabled ? ' disabled' : ''}>${S.saving ? 'Saving\u2026' : 'Save'}</button>
                ${S.isNew ? '' : '<button type="button" class="an-btn an-btn--ghost" data-rb-act="done">Done</button>'}`
            : `
                ${iconBtn('refresh', 'Refresh', `data-rb-act="refresh"${S.running ? ' disabled' : ''}`)}
                ${iconBtn('download', 'Export CSV', 'data-rb-act="export"')}
                ${isDirty ? `<button type="button" class="an-btn" data-rb-act="save"${saveDisabled ? ' disabled' : ''}>${S.saving ? 'Saving\u2026' : 'Save'}</button>` : ''}
                <button type="button" class="an-btn an-btn--primary" data-rb-act="edit">${ICONS.edit}<span>Edit</span></button>`;
        $('[data-rb-head]').innerHTML = `
            ${iconBtn('back', 'Back to reports', 'data-rb-act="back"', 'rb-back')}
            <div class="rb-title">
                <span class="rb-eyebrow">${ICONS.report}${escapeHtml(eyebrow)}</span>
                <div class="rb-title-row">${title}${status}</div>
            </div>
            <div class="rb-actions">${actions}</div>`;
        root.dataset.mode = S.mode;
    }

    function renderBanner() {
        const bits = [];
        if (offline()) {
            bits.push({
                tone: 'offline',
                text: S.pendingOffline
                    ? 'You\u2019re offline. Your changes will run when you reconnect. Saving needs a connection.'
                    : 'You\u2019re offline. Showing the last cached run. Sort, search, and chart changes still work.'
            });
        }
        if (S.message) bits.push({ tone: S.messageTone, text: S.message });
        const synced = S.savedAt ? formatSynced(S.savedAt) : '';
        $('[data-rb-banner]').innerHTML = bits.length
            ? bits
                  .map(
                      (bit) =>
                          `<div class="an-banner an-banner--${bit.tone}" role="status"><span>${escapeHtml(bit.text)}</span>${
                              bit.tone === 'offline' && synced ? `<em>${escapeHtml(synced)}</em>` : ''
                          }</div>`
                  )
                  .join('')
            : '';
    }

    function filterPillLabel(filter) {
        const field = S.catalog.byName.get(filter.column);
        const type = (field && field.dataType) || 'string';
        const op = operatorLabel(S.catalog, type, filter.operator);
        const value = filter.value === '' ? '""' : filter.value;
        return { field: fieldLabel(S.catalog, filter.column), rest: `${op} ${value}` };
    }

    function renderFilters() {
        const meta = S.meta;
        const host = $('[data-rb-filters]');
        if (!meta) {
            host.innerHTML = '';
            return;
        }
        const pills = [];
        const scopes = S.catalog.scopes;
        if (meta.scope && scopes.length) {
            const scope = scopes.find((s) => s.value === meta.scope);
            pills.push(
                `<button type="button" class="rb-pill rb-pill--std" data-rb-pop="scope"><b>Show Me</b><span>${escapeHtml((scope && scope.label) || meta.scope)}</span></button>`
            );
        }
        if (meta.standardDateFilter && meta.standardDateFilter.column) {
            const df = meta.standardDateFilter;
            const customRange = () => {
                if (df.startDate && df.endDate) return `${df.startDate} \u2013 ${df.endDate}`;
                if (df.startDate) return `From ${df.startDate}`;
                if (df.endDate) return `Until ${df.endDate}`;
                return 'All time';
            };
            const range = df.durationValue === 'CUSTOM' ? customRange() : durationLabel(S.catalog, df.durationValue);
            pills.push(
                `<button type="button" class="rb-pill rb-pill--std" data-rb-pop="date"><b>${escapeHtml(fieldLabel(S.catalog, df.column))}</b><span>${escapeHtml(range)}</span></button>`
            );
        }
        (meta.reportFilters || []).forEach((filter, index) => {
            const label = filterPillLabel(filter);
            pills.push(
                `<span class="rb-pill" data-rb-pop="filter" data-index="${index}" role="button" tabindex="0"><i class="rb-pill-num">${index + 1}</i><b>${escapeHtml(label.field)}</b><span>${escapeHtml(label.rest)}</span><button type="button" class="rb-pill-x" data-rb-remove-filter="${index}" aria-label="Remove filter">${ICONS.close}</button></span>`
            );
        });
        if ((meta.reportFilters || []).length > 1 || meta.reportBooleanFilter) {
            pills.push(
                `<button type="button" class="rb-pill rb-pill--logic" data-rb-pop="logic"><b>Logic</b><span>${escapeHtml(meta.reportBooleanFilter || (meta.reportFilters || []).map((_, i) => i + 1).join(' AND '))}</span></button>`
            );
        }
        pills.push(
            `<button type="button" class="rb-pill rb-pill--add" data-rb-pop="add">${ICONS.plus}<span>Add filter</span></button>`
        );
        host.innerHTML = `<span class="rb-filter-icon">${ICONS.filter}</span><div class="rb-pills">${pills.join('')}</div><div class="rb-pop" data-rb-popover hidden></div>`;
        renderPop();
    }

    function fieldOptions(filterFn, selected) {
        return S.catalog.categories
            .map((cat) => {
                const opts = cat.fields
                    .filter(filterFn)
                    .map(
                        (f) =>
                            `<option value="${escapeHtml(f.name)}"${f.name === selected ? ' selected' : ''}>${escapeHtml(f.label)}</option>`
                    )
                    .join('');
                return opts ? `<optgroup label="${escapeHtml(cat.label)}">${opts}</optgroup>` : '';
            })
            .join('');
    }

    function valueEditor(field, operator, value) {
        const values = (field && field.filterValues) || [];
        const type = (field && field.dataType) || 'string';
        if (values.length && values.length <= 60 && (operator === 'equals' || operator === 'notEqual')) {
            const chosen = new Set(String(value || '').split(',').map((v) => v.trim()).filter(Boolean));
            return `<div class="rb-checks">${values
                .map((opt) => {
                    const val = opt.name || opt.label;
                    return `<label><input type="checkbox" name="pv" value="${escapeHtml(val)}"${chosen.has(val) ? ' checked' : ''}/><span>${escapeHtml(opt.label || val)}</span></label>`;
                })
                .join('')}</div>`;
        }
        if (DATE_TYPES.has(type)) {
            return `<input class="an-input" name="value" list="rb-date-literals" value="${escapeHtml(value || '')}" placeholder="YYYY-MM-DD or THIS_MONTH" />
                <datalist id="rb-date-literals">${DATE_LITERALS.map((d) => `<option value="${d}"></option>`).join('')}</datalist>`;
        }
        const inputType = NUMERIC_TYPES.has(type) ? 'text" inputmode="decimal' : 'text';
        return `<input class="an-input" name="value" type="${inputType}" value="${escapeHtml(value || '')}" placeholder="Value (comma-separate multiple)" />`;
    }

    function renderPop() {
        const pop = root.querySelector('[data-rb-popover]');
        if (!pop) return;
        if (!S.pop || !S.meta) {
            pop.hidden = true;
            pop.innerHTML = '';
            return;
        }
        const meta = S.meta;
        let body = '';
        let title = '';
        if (S.pop.type === 'scope') {
            title = 'Show Me';
            body = `<select class="an-input" name="scope">${S.catalog.scopes
                .map((s) => `<option value="${escapeHtml(s.value)}"${s.value === meta.scope ? ' selected' : ''}>${escapeHtml(s.label)}</option>`)
                .join('')}</select>`;
        } else if (S.pop.type === 'date') {
            const df = meta.standardDateFilter || {};
            title = 'Date filter';
            const groups = S.catalog.dateDurations
                .map(
                    (group) =>
                        `<optgroup label="${escapeHtml(group.label || 'Range')}">${(group.standardDateFilterDurations || [])
                            .map((d) => `<option value="${escapeHtml(d.value)}"${d.value === df.durationValue ? ' selected' : ''}>${escapeHtml(d.label)}</option>`)
                            .join('')}</optgroup>`
                )
                .join('');
            body = `
                <label class="an-field"><span>Date field</span><select class="an-input" name="column">${fieldOptions((f) => DATE_TYPES.has(f.dataType), df.column)}</select></label>
                <label class="an-field"><span>Range</span><select class="an-input" name="duration" data-rb-duration>${groups || `<option value="${escapeHtml(df.durationValue || 'CUSTOM')}">${escapeHtml(durationLabel(S.catalog, df.durationValue))}</option>`}</select></label>
                <div class="an-field-row" data-rb-custom ${df.durationValue === 'CUSTOM' ? '' : 'hidden'}>
                    <label class="an-field"><span>From</span><input class="an-input" type="date" name="startDate" value="${escapeHtml(df.startDate || '')}"/></label>
                    <label class="an-field"><span>To</span><input class="an-input" type="date" name="endDate" value="${escapeHtml(df.endDate || '')}"/></label>
                </div>`;
        } else if (S.pop.type === 'logic') {
            title = 'Filter logic';
            body = `<label class="an-field"><span>Combine filters by number, e.g. (1 AND 2) OR 3</span><input class="an-input" name="logic" value="${escapeHtml(meta.reportBooleanFilter || '')}" placeholder="${escapeHtml((meta.reportFilters || []).map((_, i) => i + 1).join(' AND '))}"/></label>`;
        } else {
            const editing = S.pop.type === 'filter' ? (meta.reportFilters || [])[S.pop.index] : null;
            const column = S.pop.column || (editing && editing.column) || '';
            const field = S.catalog.byName.get(column);
            const type = (field && field.dataType) || 'string';
            const ops = operatorsFor(S.catalog, type);
            const operator = S.pop.operator || (editing && editing.operator) || (ops[0] && ops[0].name) || 'equals';
            title = editing ? 'Edit filter' : 'Add filter';
            body = `
                <label class="an-field"><span>Field</span><select class="an-input" name="column" data-rb-filter-field><option value="">Choose a field\u2026</option>${fieldOptions((f) => f.filterable, column)}</select></label>
                ${column ? `
                <label class="an-field"><span>Operator</span><select class="an-input" name="operator" data-rb-filter-op>${ops
                    .map((op) => `<option value="${escapeHtml(op.name)}"${op.name === operator ? ' selected' : ''}>${escapeHtml(op.label)}</option>`)
                    .join('')}</select></label>
                <div class="an-field"><span>Value</span>${valueEditor(field, operator, S.pop.value != null ? S.pop.value : editing ? editing.value : '')}</div>` : ''}`;
        }
        const removable = S.pop.type === 'filter';
        pop.innerHTML = `
            <form class="rb-pop-form" data-rb-pop-form>
                <header><strong>${escapeHtml(title)}</strong>${iconBtn('close', 'Close', 'data-rb-pop-close')}</header>
                <div class="rb-pop-body">${body}</div>
                <footer>
                    ${removable ? `<button type="button" class="an-btn an-btn--ghost an-btn--danger" data-rb-remove-filter="${S.pop.index}">Remove</button>` : '<span></span>'}
                    <div><button type="button" class="an-btn" data-rb-pop-close>Cancel</button><button type="submit" class="an-btn an-btn--primary">Apply</button></div>
                </footer>
            </form>`;
        pop.hidden = false;
        const anchor = S.pop.anchor && root.querySelector(S.pop.anchor);
        const bar = $('[data-rb-filters]');
        if (anchor && bar) {
            const a = anchor.getBoundingClientRect();
            const b = bar.getBoundingClientRect();
            const left = Math.max(0, Math.min(a.left - b.left, b.width - 340));
            pop.style.left = `${left}px`;
        } else {
            pop.style.left = '0px';
        }
    }

    function applyPop(form) {
        const data = new FormData(form);
        const meta = S.meta;
        const pop = S.pop;
        if (!pop) return;
        if (pop.type === 'scope') {
            mutate(() => {
                meta.scope = data.get('scope');
            });
        } else if (pop.type === 'date') {
            const duration = data.get('duration');
            const patch = { column: data.get('column'), durationValue: duration };
            if (duration === 'CUSTOM') {
                patch.startDate = data.get('startDate') || null;
                patch.endDate = data.get('endDate') || null;
            } else {
                const range = durationRange(S.catalog, duration);
                if (range) Object.assign(patch, range);
            }
            mutate(() => setDateFilter(meta, patch));
        } else if (pop.type === 'logic') {
            mutate(() => setBooleanFilter(meta, data.get('logic')));
        } else {
            const column = data.get('column');
            if (!column) return;
            const picks = data.getAll('pv');
            const value = picks.length ? picks.join(',') : String(data.get('value') ?? '');
            const filter = { column, operator: data.get('operator') || 'equals', value };
            if (pop.type === 'filter') mutate(() => updateFilter(meta, pop.index, filter));
            else mutate(() => addFilter(meta, filter));
        }
        S.pop = null;
        renderPop();
    }

    function renderOutline() {
        const host = $('[data-rb-panel="outline"]');
        const meta = S.meta;
        if (!meta) {
            host.innerHTML = '';
            return;
        }
        const format = meta.reportFormat || 'TABULAR';
        const chip = (zone, index, label, controls = '', sub = '') => `
            <li class="rb-chip" draggable="true" data-rb-chip data-zone="${zone}" data-index="${index}">
                <span class="rb-chip-grip">${ICONS.grip}</span>
                <span class="rb-chip-label">${escapeHtml(label)}${sub ? `<small>${escapeHtml(sub)}</small>` : ''}</span>
                <span class="rb-chip-tools">${controls}
                    ${iconBtn('up', 'Move up', `data-rb-shift="-1" data-zone="${zone}" data-index="${index}"`)}
                    ${iconBtn('down', 'Move down', `data-rb-shift="1" data-zone="${zone}" data-index="${index}"`)}
                    ${iconBtn('close', 'Remove', `data-rb-drop-chip data-zone="${zone}" data-index="${index}"`)}
                </span>
            </li>`;
        const groupChip = (axis, group, index) => {
            const field = S.catalog.byName.get(group.name);
            const isDate = field && DATE_TYPES.has(field.dataType);
            const gran = isDate
                ? `<select class="rb-mini-select" data-rb-gran="${axis}" data-name="${escapeHtml(group.name)}" aria-label="Group dates by">${[{ label: 'Day', value: 'Day' }, ...S.catalog.dateGranularities.filter((g) => g.value !== 'Day')]
                      .map((g) => `<option value="${escapeHtml(g.value)}"${(group.dateGranularity === g.value || (group.dateGranularity === 'None' && g.value === 'Day')) ? ' selected' : ''}>${escapeHtml(g.label)}</option>`)
                      .join('')}</select>`
                : '';
            const sort = `<button type="button" class="rb-mini-btn" data-rb-sortgroup="${axis}" data-name="${escapeHtml(group.name)}" title="Sort order">${group.sortOrder === 'Desc' ? 'Z\u2192A' : 'A\u2192Z'}</button>`;
            return chip(axis, index, fieldLabel(S.catalog, group.name), gran + sort);
        };
        const zone = (id, title, items, hint, disabled = false) => `
            <div class="rb-zone${disabled ? ' is-disabled' : ''}" data-rb-zone="${id}">
                <div class="rb-zone-head"><span>${escapeHtml(title)}</span><em>${items.length ? items.length : ''}</em></div>
                <ul class="rb-chips">${items.join('') || `<li class="rb-zone-empty">${escapeHtml(hint)}</li>`}</ul>
            </div>`;
        const down = groupsDown().map((g, i) => groupChip('down', g, i));
        const across = groupsAcross().map((g, i) => groupChip('across', g, i));
        const columns = (meta.detailColumns || []).map((name, i) => {
            const field = S.catalog.byName.get(name);
            const numeric = field && NUMERIC_TYPES.has(field.dataType);
            const summarize = numeric
                ? `<button type="button" class="rb-mini-btn" data-rb-summarize="${escapeHtml(name)}" title="Summarize">\u03a3</button>`
                : '';
            return chip('columns', i, fieldLabel(S.catalog, name), summarize);
        });
        const aggs = (meta.aggregates || [])
            .filter((key) => key !== 'RowCount')
            .map((key) => {
                const index = (meta.aggregates || []).indexOf(key);
                return chip('aggs', index, aggregateLabel(S.catalog, key, S.result && S.result.reportExtendedMetadata));
            });
        const hasCount = meta.hasRecordCount === true;
        host.innerHTML = `
            <div class="rb-format" role="radiogroup" aria-label="Report format">${FORMATS.map(
                (f) => `<button type="button" role="radio" aria-checked="${f.value === format}" class="${f.value === format ? 'is-on' : ''}" data-rb-format="${f.value}">${escapeHtml(f.label)}</button>`
            ).join('')}</div>
            ${format !== 'TABULAR' ? zone('down', 'Group Rows', down, 'Drop a field here to group rows') : ''}
            ${format === 'MATRIX' ? zone('across', 'Group Columns', across, 'Drop a field here to group columns') : ''}
            ${zone('columns', 'Columns', columns, 'Drop fields here to add columns')}
            ${zone('aggs', 'Summaries', aggs, 'Use \u03a3 on a number column, or drop a number field here')}
            <label class="rb-switch rb-switch--row"><input type="checkbox" data-rb-rowcount${hasCount ? ' checked' : ''}/><span>Record count</span></label>
            <p class="rb-hint">Drag fields from the <button type="button" class="rb-link" data-rb-tab="fields">Fields</button> tab, or tap a field to add it.</p>`;
    }

    function renderFields() {
        const host = $('[data-rb-field-list]');
        const term = S.fieldSearch.trim().toLowerCase();
        const meta = S.meta || {};
        const used = new Set([
            ...(meta.detailColumns || []),
            ...groupsDown().map((g) => g.name),
            ...groupsAcross().map((g) => g.name)
        ]);
        const html = S.catalog.categories
            .map((cat) => {
                const fields = cat.fields.filter(
                    (f) => !term || f.label.toLowerCase().includes(term) || f.name.toLowerCase().includes(term)
                );
                if (!fields.length) return '';
                return `<div class="rb-field-cat"><h3>${escapeHtml(cat.label)}</h3><ul>${fields
                    .map((f) => {
                        const open = S.openField === f.name;
                        const numeric = NUMERIC_TYPES.has(f.dataType);
                        const actions = open
                            ? `<div class="rb-field-actions">
                                <button type="button" data-rb-add="columns" data-name="${escapeHtml(f.name)}">Add column</button>
                                <button type="button" data-rb-add="down" data-name="${escapeHtml(f.name)}">Group rows</button>
                                <button type="button" data-rb-add="across" data-name="${escapeHtml(f.name)}">Group columns</button>
                                ${numeric ? AGGREGATE_KINDS.map((k) => `<button type="button" data-rb-add="agg" data-prefix="${k.prefix}" data-name="${escapeHtml(f.name)}">${k.label}</button>`).join('') : ''}
                                ${f.filterable ? `<button type="button" data-rb-add="filter" data-name="${escapeHtml(f.name)}">Filter</button>` : ''}
                              </div>`
                            : '';
                        return `<li class="rb-field${used.has(f.name) ? ' is-used' : ''}${open ? ' is-open' : ''}" draggable="true" data-rb-field="${escapeHtml(f.name)}">
                            <button type="button" class="rb-field-btn" data-rb-field-toggle="${escapeHtml(f.name)}"><span class="rb-type rb-type--${escapeHtml(f.dataType)}">${escapeHtml(typeBadge(f.dataType))}</span><span class="rb-field-label">${escapeHtml(f.label)}</span>${used.has(f.name) ? '<i class="rb-used-dot" title="In report"></i>' : ''}</button>
                            ${actions}
                        </li>`;
                    })
                    .join('')}</ul></div>`;
            })
            .join('');
        host.innerHTML =
            html ||
            `<p class="rb-hint">${S.catalog.categories.length ? 'No fields match.' : 'Field list is available once the report type loads online.'}</p>`;
    }

    function typeBadge(type) {
        return (
            {
                currency: '$',
                double: '#',
                int: '#',
                percent: '%',
                date: 'D',
                datetime: 'D',
                boolean: '\u2713',
                picklist: '\u2261',
                multipicklist: '\u2261',
                id: 'ID',
                reference: '\u2197'
            }[type] || 'Aa'
        );
    }

    function renderStrip() {
        $('[data-rb-strip]').innerHTML = S.model ? summaryStripHtml(S.model) : '';
    }

    function chartValueOptions() {
        const aggs = (S.result && S.result.reportMetadata && S.result.reportMetadata.aggregates) || [];
        const ext = S.result && S.result.reportExtendedMetadata;
        const grand = (((S.result && S.result.factMap) || {})['T!T'] || {}).aggregates || [];
        const list = aggs.map((key, i) => ({ key, index: i, label: aggregateLabel(S.catalog, key, ext) }));
        if (!aggs.includes('RowCount') && grand.length > aggs.length) {
            list.push({ key: 'RowCount', index: aggs.length, label: 'Record Count' });
        }
        return list;
    }

    function chartHostSize(host) {
        const width = Math.max(260, (host && host.clientWidth) || 640);
        const height = window.innerWidth < 720 ? 240 : 300;
        return { width, height };
    }

    function renderChart() {
        const host = $('[data-rb-chart]');
        const meta = S.meta;
        if (!meta || !S.result) {
            host.hidden = true;
            return;
        }
        host.hidden = false;
        const grouped = groupsDown().length > 0;
        if (!grouped) {
            host.innerHTML = `<div class="rb-chart-empty">${ICONS.chart}<div><strong>Charts need a grouping</strong><span>Group rows by a field to chart this report.</span></div>${
                S.mode === 'run' ? '<button type="button" class="an-btn" data-rb-act="edit">Edit report</button>' : ''
            }</div>`;
            return;
        }
        const chart = meta.chart;
        if (!chart) {
            host.innerHTML = `<div class="rb-chart-empty">${ICONS.chart}<div><strong>No chart yet</strong><span>Pick a chart type to visualise this report.</span></div><button type="button" class="an-btn an-btn--primary" data-rb-chart-add>Add chart</button></div>`;
            return;
        }
        const kind = normalizeChartKind(chart.chartType) || 'vbar';
        const multiReady = groupsDown().length > 1 || groupsAcross().length > 0;
        const values = chartValueOptions();
        const summary = (chart.summaries || [])[0];
        let current = values.find((v) => v.key === summary) || values[0];
        const types = CHART_TYPES.map((t) => {
            const disabled = t.multi && !multiReady;
            return `<button type="button" class="rb-type-btn${t.kind === kind ? ' is-on' : ''}" data-rb-chart-type="${t.kind}" title="${escapeHtml(disabled ? `${t.label} needs a second grouping` : t.label)}" aria-label="${escapeHtml(t.label)}"${disabled ? ' disabled' : ''}>${glyph(t.kind)}</button>`;
        }).join('');
        host.innerHTML = `
            <div class="rb-card-bar rb-chart-bar">
                <div class="rb-types" role="toolbar" aria-label="Chart type">${types}</div>
                <div class="rb-chart-opts">
                    ${values.length > 1 ? `<label class="rb-inline"><span>Value</span><select class="an-input an-input--sm" data-rb-chart-value>${values
                        .map((v) => `<option value="${escapeHtml(v.key)}"${current && v.key === current.key ? ' selected' : ''}>${escapeHtml(v.label)}</option>`)
                        .join('')}</select></label>` : ''}
                    <label class="rb-switch"><input type="checkbox" data-rb-chart-values${chart.showChartValues !== false ? ' checked' : ''}/><span>Values</span></label>
                    ${iconBtn('close', 'Remove chart', 'data-rb-chart-remove')}
                </div>
            </div>
            <div class="rb-chart-canvas" data-rb-chart-canvas></div>`;
        const canvas = host.querySelector('[data-rb-chart-canvas]');
        const display = {
            ...S.result,
            reportMetadata: { ...(S.result.reportMetadata || {}), chart }
        };
        const size = chartHostSize(canvas);
        canvas.innerHTML = chartHtml(display, kind, {
            ...size,
            aggIndexes: current ? [current.index] : undefined,
            showValues: chart.showChartValues !== false
        });
    }

    function renderGrid() {
        const gridHost = $('[data-rb-grid]');
        const detailsWrap = $('[data-rb-details-wrap]');
        const count = $('[data-rb-count]');
        if (!S.model) {
            gridHost.innerHTML = S.running
                ? '<div class="rb-skeleton"><i></i><i></i><i></i><i></i><i></i></div>'
                : '<p class="osr-tab-empty rg-pad">Run the report to see results.</p>';
            detailsWrap.hidden = true;
            count.textContent = '';
            return;
        }
        if (S.meta) S.model.showCount = S.meta.hasRecordCount === true || !S.model.aggCols.length;
        detailsWrap.hidden = !(S.model.format === 'SUMMARY' && S.model.hasDetails);
        $('[data-rb-details]').checked = S.view.showDetails;
        count.textContent = `${S.model.totalRows.toLocaleString()} record${S.model.totalRows === 1 ? '' : 's'}`;
        gridHost.innerHTML = reportGridHtml(S.model, S.view);
        gridHost.classList.toggle('is-stale', S.running);
    }

    function renderSideTabs() {
        root.querySelectorAll('[data-rb-tab]').forEach((btn) => {
            if (!btn.closest('.rb-tabs')) return;
            const on = btn.dataset.rbTab === S.sideTab;
            btn.classList.toggle('is-on', on);
            btn.setAttribute('aria-selected', String(on));
        });
        root.querySelectorAll('[data-rb-panel]').forEach((panel) => {
            panel.hidden = panel.dataset.rbPanel !== S.sideTab;
        });
    }

    function reportFilterLines() {
        const meta = S.meta || {};
        return (meta.reportFilters || []).slice(0, 8).map((filter) => {
            const label = fieldLabel(S.catalog, filter.column);
            const value = filter.value == null || filter.value === '' ? '' : String(filter.value);
            const op = String(filter.operator || 'equals').replace(/_/g, ' ').toLowerCase();
            return `${label} ${op}${value ? ` ${value}` : ''}`.trim();
        });
    }

    function publishReportContext() {
        if (S.destroyed) return;
        const meta = S.meta || {};
        if (!S.result) {
            publishAnalyticsSnapshot({
                kind: 'report',
                id: S.id || 'new',
                name: meta.name || S.listName || 'Report',
                folder: S.folderName || '',
                format: meta.reportFormat || '',
                chart: '',
                status: S.running ? 'running' : 'loading',
                totals: [],
                groups: [],
                columns: [],
                filters: reportFilterLines(),
                topRows: [],
                truncated: false,
                rowCount: 0
            });
            return;
        }
        publishAnalyticsSnapshot(
            summarizeReportResult(S.result, {
                id: S.id || 'new',
                name: meta.name || S.listName,
                folder: S.folderName,
                filters: reportFilterLines()
            })
        );
    }

    function renderAll() {
        renderHead();
        renderBanner();
        renderFilters();
        renderSideTabs();
        renderOutline();
        renderFields();
        renderStrip();
        renderChart();
        renderGrid();
        publishReportContext();
    }

    /* ---------- Mutations & running ---------- */

    function snapshot() {
        return cloneMeta(S.meta);
    }

    function mutate(fn, { run = true } = {}) {
        if (!S.meta) return;
        S.history.push(snapshot());
        if (S.history.length > 60) S.history.shift();
        S.future = [];
        fn(S.meta);
        afterChange(run);
    }

    function afterChange(run = true) {
        renderHead();
        renderFilters();
        renderOutline();
        renderFields();
        renderChart();
        if (run) scheduleRun();
        else renderGrid();
    }

    function undo() {
        if (!S.history.length) return;
        S.future.push(snapshot());
        S.meta = S.history.pop();
        afterChange(true);
    }

    function redo() {
        if (!S.future.length) return;
        S.history.push(snapshot());
        S.meta = S.future.pop();
        afterChange(true);
    }

    function scheduleRun({ immediate = false, force = false } = {}) {
        clearTimeout(S.runTimer);
        if (!S.meta) return;
        const problem = validateMeta(S.meta);
        if (problem) {
            setMessage(problem, 'warn');
            return;
        }
        if (S.messageTone === 'warn') setMessage('');
        const sig = dataSignature(S.meta);
        if (!force && sig === S.lastRunSig) return;
        if (offline()) {
            S.pendingOffline = true;
            renderBanner();
            return;
        }
        const delay = immediate || S.mode === 'run' ? 0 : 400;
        S.runTimer = setTimeout(() => runNow(sig), delay);
    }

    async function runNow(sig) {
        const token = ++S.runToken;
        S.running = true;
        renderHead();
        renderGrid();
        try {
            const res = await runReportWithMetadata(S.isNew ? null : S.id, S.meta);
            if (token !== S.runToken || S.destroyed) return;
            applyResult(res);
            S.lastRunSig = sig;
            S.pendingOffline = false;
            S.savedAt = Date.now();
            if (S.message && S.messageTone === 'error') S.message = '';
            if (!dirty() && S.id) await idbSet(RESULT_PREFIX + S.id, res);
        } catch (error) {
            if (token !== S.runToken || S.destroyed) return;
            if (isNetworkError(error) || offline()) {
                S.pendingOffline = true;
                setMessage('');
            } else {
                setMessage(`Salesforce couldn\u2019t run this report: ${errorMessage(error)}`, 'error');
            }
        } finally {
            if (token === S.runToken) {
                S.running = false;
                renderHead();
                renderBanner();
                renderGrid();
            }
        }
    }

    function applyResult(res) {
        const prevFormat = S.model && S.model.format;
        S.result = res;
        S.model = buildReportModel(res);
        if (S.meta) S.model.detailsByDefault = S.meta.hasDetailRows !== false;
        if (!prevFormat || prevFormat !== S.model.format) {
            const keep = S.view.search;
            S.view = defaultGridView(S.model);
            S.view.search = keep;
        }
        renderStrip();
        renderChart();
        renderGrid();
        renderOutline();
        publishReportContext();
    }

    /* ---------- Load ---------- */

    function withSavedFlags(meta) {
        const saved = S.describe && S.describe.reportMetadata;
        if (saved && typeof saved.hasDetailRows === 'boolean') meta.hasDetailRows = saved.hasDetailRows;
        return meta;
    }

    function adoptMeta(meta) {
        meta = withSavedFlags(cloneMeta(meta));
        S.meta = cloneMeta(meta);
        S.saved = cloneMeta(meta);
        S.history = [];
        S.future = [];
        S.lastRunSig = dataSignature(meta);
    }

    async function loadExisting() {
        const [cachedRun, cachedDesc] = await Promise.all([
            idbGet(RESULT_PREFIX + S.id),
            idbGet(DESCRIBE_PREFIX + S.id)
        ]);
        if (cachedDesc && cachedDesc.payload) {
            S.describe = cachedDesc.payload;
            S.catalog = buildFieldCatalog(S.describe);
        }
        if (cachedRun && cachedRun.payload) {
            adoptMeta(cachedRun.payload.reportMetadata || {});
            if (!S.describe) S.catalog = buildFieldCatalog({ reportExtendedMetadata: cachedRun.payload.reportExtendedMetadata });
            S.savedAt = cachedRun.savedAt;
            applyResult(cachedRun.payload);
            renderAll();
        } else {
            S.running = true;
            renderAll();
        }
        const describeTask = describeReport(S.id)
            .then(async (desc) => {
                if (S.destroyed) return;
                S.describe = desc;
                S.catalog = buildFieldCatalog(desc);
                await idbSet(DESCRIBE_PREFIX + S.id, desc);
                if (S.meta && !dirty()) {
                    adoptMeta(S.meta);
                    if (S.model) {
                        S.model.detailsByDefault = S.meta.hasDetailRows !== false;
                        S.view.showDetails = defaultGridView(S.model).showDetails;
                        renderGrid();
                    }
                }
                renderFilters();
                renderOutline();
                renderFields();
            })
            .catch(() => {});
        try {
            const res = await runSavedReport(S.id);
            if (S.destroyed) return;
            if (!dirty()) adoptMeta(res.reportMetadata || {});
            S.savedAt = Date.now();
            if (!S.describe) S.catalog = buildFieldCatalog({ reportExtendedMetadata: res.reportExtendedMetadata });
            applyResult(res);
            await idbSet(RESULT_PREFIX + S.id, res);
            S.running = false;
            renderAll();
        } catch (error) {
            S.running = false;
            if (!S.result) {
                setMessage(errorMessage(error), 'error');
                $('[data-rb-grid]').innerHTML = `<div class="an-empty">${ICONS.report}<strong>Report unavailable</strong><span>${escapeHtml(errorMessage(error))}</span></div>`;
                renderHead();
            } else if (!isNetworkError(error) && !offline()) {
                setMessage(errorMessage(error), 'error');
            }
            renderAll();
        }
        await describeTask;
    }

    async function loadNew() {
        S.running = true;
        renderAll();
        try {
            const desc = await describeReportType(options.reportType);
            if (S.destroyed) return;
            S.describe = desc;
            S.catalog = buildFieldCatalog(desc);
            const meta = cloneMeta(desc.reportMetadata || {});
            meta.name = `New ${options.typeLabel || (meta.reportType && meta.reportType.label) || ''} Report`.replace(/\s+/g, ' ').slice(0, 40);
            if (!(meta.groupingsDown || []).length) {
                meta.reportFormat = 'TABULAR';
                meta.groupingsAcross = [];
                meta.chart = null;
            }
            meta.aggregates = (meta.aggregates || []).includes('RowCount') ? meta.aggregates : [...(meta.aggregates || []), 'RowCount'];
            meta.hasRecordCount = true;
            meta.reportFilters = meta.reportFilters || [];
            delete meta.id;
            adoptMeta(meta);
            S.lastRunSig = '';
            S.saved = cloneMeta(meta);
            S.running = false;
            renderAll();
            scheduleRun({ immediate: true, force: true });
        } catch (error) {
            S.running = false;
            setMessage(`Couldn\u2019t load this report type: ${errorMessage(error)}`, 'error');
            renderAll();
        }
    }

    /* ---------- Save ---------- */

    async function save() {
        if (!S.meta || S.saving) return;
        const problem = validateMeta(S.meta);
        if (problem) {
            setMessage(problem, 'warn');
            return;
        }
        if (S.isNew) {
            await saveAs();
            return;
        }
        S.saving = true;
        renderHead();
        try {
            await saveReport(S.id, S.meta);
            S.saved = cloneMeta(S.meta);
            toast('Report saved');
            setMessage('');
            if (S.result && dataSignature(S.meta) === S.lastRunSig) await idbSet(RESULT_PREFIX + S.id, S.result);
        } catch (error) {
            setMessage(`Save failed: ${errorMessage(error)}`, 'error');
        } finally {
            S.saving = false;
            renderHead();
        }
    }

    async function saveAs() {
        if (!S.meta) return;
        let folders = [];
        try {
            folders = await listFolders('Report');
        } catch (_err) {
            folders = [];
        }
        const current = S.meta.folderId;
        const res = await openModal({
            title: S.isNew ? 'Save report' : 'Save report as',
            body: `
                <label class="an-field"><span>Report name</span><input class="an-input" name="name" required maxlength="40" value="${escapeHtml(S.isNew ? S.meta.name || '' : `Copy of ${S.meta.name || ''}`.slice(0, 40))}"/></label>
                <label class="an-field"><span>Folder</span><select class="an-input" name="folderId">${folders
                    .map((f) => `<option value="${escapeHtml(f.id)}"${f.id === current ? ' selected' : ''}>${escapeHtml(f.name)}</option>`)
                    .join('')}</select></label>`,
            actions: [
                { id: 'cancel', label: 'Cancel' },
                { id: 'save', label: 'Save', primary: true }
            ]
        });
        if (res.action !== 'save') return;
        const name = String(res.form.name || '').trim();
        if (!name) {
            setMessage('Give the report a name to save it.', 'warn');
            return;
        }
        S.saving = true;
        renderHead();
        try {
            const out = await saveReportAs(S.isNew ? null : S.id, S.meta, {
                name,
                folderId: res.form.folderId || current
            });
            const newId = out && out.reportMetadata && out.reportMetadata.id;
            toast('Report saved');
            if (newId && options.onOpenReport) {
                S.destroyed = true;
                options.onOpenReport(newId, { mode: 'run' });
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

    async function leave() {
        if (dirty() || (S.isNew && S.meta)) {
            const ok = await confirmModal(
                'Discard changes?',
                'You have unsaved changes to this report. Leave without saving?'
            );
            if (!ok) return;
        }
        S.destroyed = true;
        cleanup();
        if (options.onBack) options.onBack();
    }

    /* ---------- Field / chip actions ---------- */

    function addField(target, name, extra = {}) {
        const field = S.catalog.byName.get(name);
        if (target === 'columns') {
            mutate((meta) => addColumn(meta, name, extra.index));
        } else if (target === 'down' || target === 'across') {
            const meta = S.meta;
            const list = target === 'across' ? groupsAcross() : groupsDown();
            const limit = maxGroupings(target, target === 'across' ? 'MATRIX' : meta.reportFormat);
            if (list.length >= limit && !list.some((g) => g.name === name)) {
                setMessage(`You can group by up to ${limit} fields here.`, 'warn');
                return;
            }
            mutate((m) => {
                if (target === 'across' && m.reportFormat !== 'MATRIX') {
                    m.reportFormat = 'MATRIX';
                }
                addGrouping(m, target, name, extra.index);
            });
        } else if (target === 'agg') {
            if (!field || !NUMERIC_TYPES.has(field.dataType)) {
                setMessage('Only number, currency, and percent fields can be summarized.', 'warn');
                return;
            }
            const key = `${extra.prefix || 's'}!${name}`;
            if ((S.meta.aggregates || []).includes(key)) return;
            mutate((meta) => toggleAggregate(meta, key));
        } else if (target === 'filter') {
            S.pop = { type: 'add', column: name, anchor: '[data-rb-pop="add"]' };
            renderPop();
            $('[data-rb-filters]').scrollIntoView({ block: 'nearest', behavior: 'smooth' });
        }
    }

    function removeChip(zone, index) {
        const meta = S.meta;
        if (zone === 'columns') mutate((m) => removeColumn(m, (m.detailColumns || [])[index]));
        else if (zone === 'down' || zone === 'across') {
            const list = zone === 'across' ? groupsAcross() : groupsDown();
            const group = list[index];
            if (group) mutate((m) => removeGrouping(m, zone, group.name));
        } else if (zone === 'aggs') {
            const key = (meta.aggregates || [])[index];
            if (key) mutate((m) => toggleAggregate(m, key));
        }
    }

    function listForZone(zone) {
        const meta = S.meta;
        if (zone === 'columns') return meta.detailColumns || [];
        if (zone === 'down') return meta.groupingsDown || [];
        if (zone === 'across') return meta.groupingsAcross || [];
        return meta.aggregates || [];
    }

    function setListForZone(meta, zone, list) {
        if (zone === 'columns') meta.detailColumns = list;
        else if (zone === 'down') meta.groupingsDown = list;
        else if (zone === 'across') meta.groupingsAcross = list;
        else meta.aggregates = list;
    }

    function reorder(zone, from, to) {
        const list = listForZone(zone);
        if (from === to || from < 0 || from >= list.length) return;
        mutate((meta) => setListForZone(meta, zone, moveTo(list, from, to)));
    }

    function nameOf(zone, index) {
        const item = listForZone(zone)[index];
        if (!item) return null;
        if (zone === 'aggs') return aggregateParts(item).field || null;
        return typeof item === 'string' ? item : item.name;
    }

    /* ---------- Drag & drop ---------- */

    let drag = null;

    function dropIndex(zoneEl, clientY) {
        const chips = [...zoneEl.querySelectorAll('[data-rb-chip]')];
        for (let i = 0; i < chips.length; i += 1) {
            const rect = chips[i].getBoundingClientRect();
            if (clientY < rect.top + rect.height / 2) return i;
        }
        return chips.length;
    }

    root.addEventListener('dragstart', (event) => {
        const chip = event.target.closest('[data-rb-chip]');
        const field = event.target.closest('[data-rb-field]');
        if (chip) {
            drag = { kind: 'chip', zone: chip.dataset.zone, index: Number(chip.dataset.index) };
            chip.classList.add('is-dragging');
        } else if (field) {
            drag = { kind: 'field', name: field.dataset.rbField };
        } else return;
        event.dataTransfer.effectAllowed = 'move';
        event.dataTransfer.setData('text/plain', JSON.stringify(drag));
        root.classList.add('is-dragging');
    });

    root.addEventListener('dragend', () => {
        drag = null;
        root.classList.remove('is-dragging');
        root.querySelectorAll('.is-dragging, .is-over').forEach((el) => el.classList.remove('is-dragging', 'is-over'));
    });

    root.addEventListener('dragover', (event) => {
        const zoneEl = event.target.closest('[data-rb-zone]');
        if (!zoneEl || !drag) return;
        event.preventDefault();
        root.querySelectorAll('.rb-zone.is-over').forEach((el) => el !== zoneEl && el.classList.remove('is-over'));
        zoneEl.classList.add('is-over');
    });

    root.addEventListener('dragleave', (event) => {
        const zoneEl = event.target.closest('[data-rb-zone]');
        if (zoneEl && !zoneEl.contains(event.relatedTarget)) zoneEl.classList.remove('is-over');
    });

    root.addEventListener('drop', (event) => {
        const zoneEl = event.target.closest('[data-rb-zone]');
        if (!zoneEl || !drag) return;
        event.preventDefault();
        zoneEl.classList.remove('is-over');
        const zone = zoneEl.dataset.rbZone;
        const index = dropIndex(zoneEl, event.clientY);
        const payload = drag;
        drag = null;
        if (payload.kind === 'chip' && payload.zone === zone) {
            reorder(zone, payload.index, payload.index < index ? index - 1 : index);
            return;
        }
        const name = payload.kind === 'field' ? payload.name : nameOf(payload.zone, payload.index);
        if (!name) return;
        if (payload.kind === 'chip') removeChip(payload.zone, payload.index);
        if (zone === 'aggs') addField('agg', name, { prefix: 's' });
        else addField(zone, name, { index });
    });

    /* ---------- Events ---------- */

    root.addEventListener('click', async (event) => {
        const t = event.target;
        const act = t.closest('[data-rb-act]');
        if (act && !act.disabled) {
            const a = act.dataset.rbAct;
            if (a === 'back') return leave();
            if (a === 'edit') {
                S.mode = 'edit';
                renderAll();
                return;
            }
            if (a === 'done') {
                S.mode = 'run';
                renderAll();
                return;
            }
            if (a === 'refresh' || a === 'run') return scheduleRun({ immediate: true, force: true });
            if (a === 'save') return save();
            if (a === 'saveas') return saveAs();
            if (a === 'undo') return undo();
            if (a === 'redo') return redo();
            if (a === 'export') {
                if (!S.model) return;
                downloadText(`${safeFileName(S.meta && S.meta.name)}.csv`, modelToCsv(S.model));
                return;
            }
        }
        const tab = t.closest('[data-rb-tab]');
        if (tab) {
            S.sideTab = tab.dataset.rbTab;
            renderSideTabs();
            return;
        }
        const removeF = t.closest('[data-rb-remove-filter]');
        if (removeF) {
            event.stopPropagation();
            const index = Number(removeF.dataset.rbRemoveFilter);
            S.pop = null;
            mutate((meta) => removeFilter(meta, index));
            return;
        }
        if (t.closest('[data-rb-pop-close]')) {
            S.pop = null;
            renderPop();
            return;
        }
        const popBtn = t.closest('[data-rb-pop]');
        if (popBtn) {
            const type = popBtn.dataset.rbPop;
            const index = popBtn.dataset.index != null ? Number(popBtn.dataset.index) : null;
            const same = S.pop && S.pop.type === type && S.pop.index === index;
            S.pop = same
                ? null
                : {
                      type,
                      index,
                      anchor: index != null ? `[data-rb-pop="${type}"][data-index="${index}"]` : `[data-rb-pop="${type}"]`
                  };
            renderPop();
            return;
        }
        const format = t.closest('[data-rb-format]');
        if (format) {
            const value = format.dataset.rbFormat;
            if (value === S.meta.reportFormat) return;
            if (value === 'TABULAR' && (groupsDown().length || groupsAcross().length)) {
                const ok = await confirmModal('Switch to tabular?', 'Tabular reports have no groupings, so your row and column groups will be removed.', 'Switch', false);
                if (!ok) return;
            }
            mutate((meta) => setFormat(meta, value));
            return;
        }
        const shift = t.closest('[data-rb-shift]');
        if (shift) {
            const zone = shift.dataset.zone;
            const index = Number(shift.dataset.index);
            reorder(zone, index, index + Number(shift.dataset.rbShift));
            return;
        }
        const dropChip = t.closest('[data-rb-drop-chip]');
        if (dropChip) {
            removeChip(dropChip.dataset.zone, Number(dropChip.dataset.index));
            return;
        }
        const sortGroup = t.closest('[data-rb-sortgroup]');
        if (sortGroup) {
            const axis = sortGroup.dataset.rbSortgroup;
            const name = sortGroup.dataset.name;
            const group = (axis === 'across' ? groupsAcross() : groupsDown()).find((g) => g.name === name);
            mutate((meta) => updateGrouping(meta, axis, name, { sortOrder: group && group.sortOrder === 'Desc' ? 'Asc' : 'Desc' }));
            return;
        }
        const summarize = t.closest('[data-rb-summarize]');
        if (summarize) {
            openSummarize(summarize.dataset.rbSummarize);
            return;
        }
        const toggleField = t.closest('[data-rb-field-toggle]');
        if (toggleField) {
            const name = toggleField.dataset.rbFieldToggle;
            S.openField = S.openField === name ? null : name;
            renderFields();
            return;
        }
        const add = t.closest('[data-rb-add]');
        if (add) {
            addField(add.dataset.rbAdd, add.dataset.name, { prefix: add.dataset.prefix });
            return;
        }
        if (t.closest('[data-rb-chart-add]')) {
            const values = chartValueOptions();
            mutate((meta) => setChart(meta, { chartType: 'Vertical Bar', summaries: [values[0] ? values[0].key : 'RowCount'] }), { run: false });
            return;
        }
        if (t.closest('[data-rb-chart-remove]')) {
            mutate((meta) => setChart(meta, null), { run: false });
            return;
        }
        const chartType = t.closest('[data-rb-chart-type]');
        if (chartType && !chartType.disabled) {
            const type = chartTypeByKind(chartType.dataset.rbChartType);
            if (type) mutate((meta) => setChart(meta, { chartType: type.value }), { run: false });
            return;
        }
        const sortTh = t.closest('[data-rg-sort]');
        if (sortTh) {
            const raw = sortTh.dataset.rgSort;
            const col = raw === 'label' || raw === 'count' ? raw : Number(raw);
            if (S.view.sortCol === col) S.view.sortDir = S.view.sortDir === 'asc' ? 'desc' : 'asc';
            else {
                S.view.sortCol = col;
                S.view.sortDir = typeof col === 'number' || col === 'count' ? 'desc' : 'asc';
            }
            renderGrid();
            return;
        }
        const toggle = t.closest('[data-rg-toggle]');
        if (toggle) {
            const key = toggle.dataset.rgToggle;
            if (toggle.dataset.rgKind === 'group') {
                if (S.view.collapsed.has(key)) S.view.collapsed.delete(key);
                else S.view.collapsed.add(key);
            } else {
                const open = toggle.getAttribute('aria-expanded') === 'true';
                if (open) {
                    S.view.detailOpen.delete(key);
                    if (S.view.showDetails) {
                        S.view.showDetails = false;
                        S.model.nodes.forEach(function walk(node) {
                            if (node.children.length) node.children.forEach(walk);
                            else if (node.key !== key) S.view.detailOpen.add(node.key);
                        });
                    }
                } else S.view.detailOpen.add(key);
            }
            renderGrid();
            return;
        }
        if (S.pop && !t.closest('[data-rb-popover]')) {
            S.pop = null;
            renderPop();
        }
    });

    root.addEventListener('keydown', (event) => {
        const pill = event.target.closest && event.target.closest('span[data-rb-pop]');
        if (pill && (event.key === 'Enter' || event.key === ' ')) {
            event.preventDefault();
            pill.click();
        }
        if ((event.metaKey || event.ctrlKey) && event.key.toLowerCase() === 'z' && S.mode === 'edit' && !event.target.matches('input, textarea')) {
            event.preventDefault();
            if (event.shiftKey) redo();
            else undo();
        }
    });

    root.addEventListener('submit', (event) => {
        const form = event.target.closest('[data-rb-pop-form]');
        if (!form) return;
        event.preventDefault();
        applyPop(form);
    });

    root.addEventListener('input', (event) => {
        const t = event.target;
        if (t.matches('[data-rb-grid-search]')) {
            S.view.search = t.value;
            renderGrid();
        } else if (t.matches('[data-rb-field-search]')) {
            S.fieldSearch = t.value;
            renderFields();
        } else if (t.matches('[data-rb-name]')) {
            const value = t.value;
            if (!S.meta) return;
            if (!S._nameEditing) {
                S.history.push(snapshot());
                S.future = [];
                S._nameEditing = true;
            }
            S.meta.name = value;
            const status = root.querySelector('.rb-status');
            if (!status && dirty()) renderHeadPreservingName();
        }
    });

    function renderHeadPreservingName() {
        const input = root.querySelector('[data-rb-name]');
        const pos = input ? input.selectionStart : null;
        renderHead();
        const next = root.querySelector('[data-rb-name]');
        if (next && pos != null) {
            next.focus();
            next.setSelectionRange(pos, pos);
        }
    }

    root.addEventListener('focusout', (event) => {
        if (event.target.matches && event.target.matches('[data-rb-name]')) {
            S._nameEditing = false;
            renderHead();
        }
    });

    root.addEventListener('change', (event) => {
        const t = event.target;
        if (t.matches('[data-rb-details]')) {
            S.view.showDetails = t.checked;
            S.view.detailOpen = new Set();
            mutate((meta) => {
                meta.hasDetailRows = t.checked;
            }, { run: false });
        } else if (t.matches('[data-rb-rowcount]')) {
            mutate((meta) => {
                meta.hasRecordCount = t.checked;
            }, { run: false });
        } else if (t.matches('[data-rb-gran]')) {
            const axis = t.dataset.rbGran;
            mutate((meta) => updateGrouping(meta, axis, t.dataset.name, { dateGranularity: t.value }));
        } else if (t.matches('[data-rb-chart-value]')) {
            mutate((meta) => setChart(meta, { summaries: [t.value] }), { run: false });
        } else if (t.matches('[data-rb-chart-values]')) {
            mutate((meta) => setChart(meta, { showChartValues: t.checked }), { run: false });
        } else if (t.matches('[data-rb-duration]')) {
            const custom = root.querySelector('[data-rb-custom]');
            if (custom) custom.hidden = t.value !== 'CUSTOM';
        } else if (t.matches('[data-rb-filter-field]')) {
            S.pop = { ...S.pop, column: t.value, operator: null, value: '' };
            renderPop();
        } else if (t.matches('[data-rb-filter-op]')) {
            const form = t.closest('form');
            const current = form && form.querySelector('[name="value"]');
            const picks = form ? [...form.querySelectorAll('[name="pv"]:checked')].map((el) => el.value) : [];
            S.pop = {
                ...S.pop,
                column: form.querySelector('[name="column"]').value,
                operator: t.value,
                value: current ? current.value : picks.join(',')
            };
            renderPop();
        }
    });

    async function openSummarize(name) {
        const current = new Set(S.meta.aggregates || []);
        const res = await openModal({
            title: `Summarize ${fieldLabel(S.catalog, name)}`,
            body: `<div class="rb-checks rb-checks--grid">${AGGREGATE_KINDS.map((k) => {
                const key = `${k.prefix}!${name}`;
                return `<label><input type="checkbox" name="agg" value="${escapeHtml(key)}"${current.has(key) ? ' checked' : ''}/><span>${escapeHtml(k.label)}</span></label>`;
            }).join('')}</div>`,
            actions: [
                { id: 'cancel', label: 'Cancel' },
                { id: 'apply', label: 'Apply', primary: true }
            ],
            onMount(overlay) {
                overlay.querySelector('form').dataset.agg = '1';
            }
        });
        if (res.action !== 'apply') return;
        const chosen = new Set(
            [...res.root.querySelectorAll('input[name="agg"]:checked')].map((el) => el.value)
        );
        mutate((meta) => {
            AGGREGATE_KINDS.forEach((k) => {
                const key = `${k.prefix}!${name}`;
                const has = (meta.aggregates || []).includes(key);
                if (chosen.has(key) !== has) toggleAggregate(meta, key);
            });
        });
    }

    const onOnline = () => {
        renderBanner();
        renderHead();
        if (S.pendingOffline) scheduleRun({ immediate: true, force: true });
    };
    const onOffline = () => {
        renderBanner();
        renderHead();
    };
    window.addEventListener('online', onOnline);
    window.addEventListener('offline', onOffline);

    let resizeFrame = 0;
    const ro =
        typeof ResizeObserver !== 'undefined'
            ? new ResizeObserver(() => {
                  cancelAnimationFrame(resizeFrame);
                  resizeFrame = requestAnimationFrame(() => {
                      if (!S.destroyed) renderChart();
                  });
              })
            : null;
    if (ro) ro.observe($('[data-rb-chart]'));

    function cleanup() {
        clearTimeout(S.runTimer);
        window.removeEventListener('online', onOnline);
        window.removeEventListener('offline', onOffline);
        if (ro) ro.disconnect();
    }

    if (S.isNew) loadNew();
    else loadExisting();

    return {
        destroy() {
            S.destroyed = true;
            cleanup();
        },
        isDirty: () => dirty(),
        get id() {
            return S.id;
        }
    };
}
