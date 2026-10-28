export const NUMERIC_TYPES = new Set(['currency', 'double', 'int', 'percent']);
export const DATE_TYPES = new Set(['date', 'datetime']);

export const AGGREGATE_KINDS = [
    { prefix: 's', label: 'Sum' },
    { prefix: 'a', label: 'Average' },
    { prefix: 'mx', label: 'Max' },
    { prefix: 'm', label: 'Min' }
];

const AGG_LABEL = { s: 'Sum of', a: 'Average', mx: 'Largest', m: 'Smallest', u: 'Unique' };

export const FORMATS = [
    { value: 'TABULAR', label: 'Tabular' },
    { value: 'SUMMARY', label: 'Summary' },
    { value: 'MATRIX', label: 'Matrix' }
];

export const CHART_TYPES = [
    { value: 'Vertical Bar', kind: 'vbar', label: 'Column' },
    { value: 'Horizontal Bar', kind: 'hbar', label: 'Bar' },
    { value: 'Vertical Bar Stacked', kind: 'vbar-stacked', label: 'Stacked column', multi: true },
    { value: 'Horizontal Bar Stacked', kind: 'hbar-stacked', label: 'Stacked bar', multi: true },
    {
        value: 'Vertical Bar Stacked to 100%',
        kind: 'vbar-stack100',
        label: 'Column 100%',
        multi: true
    },
    {
        value: 'Horizontal Bar Stacked to 100%',
        kind: 'hbar-stack100',
        label: 'Bar 100%',
        multi: true
    },
    { value: 'Vertical Bar Grouped', kind: 'vbar-grouped', label: 'Grouped column', multi: true },
    { value: 'Horizontal Bar Grouped', kind: 'hbar-grouped', label: 'Grouped bar', multi: true },
    { value: 'Line', kind: 'line', label: 'Line' },
    { value: 'Donut', kind: 'donut', label: 'Donut' },
    { value: 'Pie', kind: 'pie', label: 'Pie' },
    { value: 'Funnel', kind: 'funnel', label: 'Funnel' },
    { value: 'Scatter', kind: 'scatter', label: 'Scatter' }
];

export function chartTypeByKind(kind) {
    return CHART_TYPES.find((item) => item.kind === kind) || null;
}

export function cloneMeta(meta) {
    return JSON.parse(JSON.stringify(meta || {}));
}

/* ---------- Field catalog ---------- */

export function buildFieldCatalog(describe) {
    const typeMeta = (describe && describe.reportTypeMetadata) || {};
    const ext = (describe && describe.reportExtendedMetadata) || {};
    const byName = new Map();
    const categories = [];
    (typeMeta.categories || []).forEach((category) => {
        const fields = [];
        Object.entries(category.columns || {}).forEach(([name, info]) => {
            const field = {
                name,
                label: info.label || name,
                dataType: String(info.dataType || 'string').toLowerCase(),
                filterable: info.filterable !== false,
                filterValues: info.filterValues || [],
                category: category.label || ''
            };
            byName.set(name, field);
            fields.push(field);
        });
        fields.sort((a, b) => a.label.localeCompare(b.label));
        categories.push({ label: category.label || 'Fields', fields });
    });
    ['detailColumnInfo', 'groupingColumnInfo'].forEach((key) => {
        Object.entries(ext[key] || {}).forEach(([name, info]) => {
            if (byName.has(name)) return;
            byName.set(name, {
                name,
                label: info.label || name,
                dataType: String(info.dataType || 'string').toLowerCase(),
                filterable: info.filterable !== false,
                filterValues: info.filterValues || [],
                category: ''
            });
        });
    });
    return {
        categories,
        byName,
        operators: typeMeta.dataTypeFilterOperatorMap || {},
        dateGranularities: typeMeta.dateGranularityInfos || [],
        dateDurations: typeMeta.standardDateFilterDurationGroups || [],
        scopes: (typeMeta.scopeInfo && typeMeta.scopeInfo.values) || []
    };
}

export function fieldLabel(catalog, name) {
    const field = catalog && catalog.byName.get(name);
    return (field && field.label) || String(name || '').split('.').pop();
}

export function aggregateParts(key) {
    const text = String(key || '');
    if (text === 'RowCount') return { prefix: '', field: '' };
    const bang = text.indexOf('!');
    if (bang < 0) return { prefix: '', field: text };
    return { prefix: text.slice(0, bang), field: text.slice(bang + 1) };
}

export function aggregateLabel(catalog, key, extended) {
    if (key === 'RowCount') return 'Record Count';
    const info = extended && extended.aggregateColumnInfo && extended.aggregateColumnInfo[key];
    if (info && info.label) return info.label;
    const { prefix, field } = aggregateParts(key);
    const base = fieldLabel(catalog, field);
    return AGG_LABEL[prefix] ? `${AGG_LABEL[prefix]} ${base}` : base;
}

export function operatorsFor(catalog, dataType) {
    const map = (catalog && catalog.operators) || {};
    return map[dataType] || map.string || [
        { name: 'equals', label: 'equals' },
        { name: 'notEqual', label: 'not equal to' },
        { name: 'contains', label: 'contains' }
    ];
}

export function operatorLabel(catalog, dataType, name) {
    const hit = operatorsFor(catalog, dataType).find((op) => op.name === name);
    return (hit && hit.label) || name;
}

/* ---------- Structure edits ---------- */

function move(list, index, delta) {
    const target = index + delta;
    if (target < 0 || target >= list.length) return list;
    const next = list.slice();
    const [item] = next.splice(index, 1);
    next.splice(target, 0, item);
    return next;
}

export function moveTo(list, from, to) {
    if (from === to || from < 0 || from >= list.length) return list;
    const next = list.slice();
    const [item] = next.splice(from, 1);
    next.splice(Math.max(0, Math.min(to, next.length)), 0, item);
    return next;
}

export function addColumn(meta, name, index) {
    const cols = (meta.detailColumns || []).filter((col) => col !== name);
    cols.splice(index == null ? cols.length : index, 0, name);
    meta.detailColumns = cols;
}

export function removeColumn(meta, name) {
    meta.detailColumns = (meta.detailColumns || []).filter((col) => col !== name);
}

export function shiftColumn(meta, index, delta) {
    meta.detailColumns = move(meta.detailColumns || [], index, delta);
}

function groupKey(axis) {
    return axis === 'across' ? 'groupingsAcross' : 'groupingsDown';
}

export function maxGroupings(axis, format) {
    if (axis === 'across') return 2;
    return format === 'MATRIX' ? 2 : 3;
}

export function addGrouping(meta, axis, name, index) {
    const key = groupKey(axis);
    const list = (meta[key] || []).filter((group) => group.name !== name);
    if (list.length >= maxGroupings(axis, axis === 'across' ? 'MATRIX' : meta.reportFormat)) {
        return false;
    }
    list.splice(index == null ? list.length : index, 0, {
        name,
        sortOrder: 'Asc',
        dateGranularity: 'None',
        sortAggregate: null
    });
    meta[key] = list;
    syncFormat(meta);
    return true;
}

export function removeGrouping(meta, axis, name) {
    const key = groupKey(axis);
    meta[key] = (meta[key] || []).filter((group) => group.name !== name);
    syncFormat(meta);
}

export function shiftGrouping(meta, axis, index, delta) {
    const key = groupKey(axis);
    meta[key] = move(meta[key] || [], index, delta);
}

export function updateGrouping(meta, axis, name, patch) {
    const key = groupKey(axis);
    meta[key] = (meta[key] || []).map((group) =>
        group.name === name ? { ...group, ...patch } : group
    );
}

function syncFormat(meta) {
    const down = (meta.groupingsDown || []).length;
    const across = (meta.groupingsAcross || []).length;
    if (across && down) meta.reportFormat = 'MATRIX';
    else if (across && !down) {
        meta.groupingsDown = meta.groupingsAcross;
        meta.groupingsAcross = [];
        meta.reportFormat = 'SUMMARY';
    } else if (down) meta.reportFormat = meta.reportFormat === 'MATRIX' ? 'MATRIX' : 'SUMMARY';
    else meta.reportFormat = 'TABULAR';
    if (meta.reportFormat === 'TABULAR') meta.chart = null;
    ensureChartGroupings(meta);
}

export function setFormat(meta, format) {
    if (format === 'TABULAR') {
        meta.groupingsDown = [];
        meta.groupingsAcross = [];
        meta.chart = null;
    } else if (format === 'SUMMARY') {
        meta.groupingsAcross = [];
    }
    meta.reportFormat = format;
    ensureChartGroupings(meta);
}

export function toggleAggregate(meta, key) {
    const list = meta.aggregates || [];
    if (list.includes(key)) {
        meta.aggregates = list.filter((item) => item !== key);
    } else {
        meta.aggregates = [...list, key];
    }
    if (meta.chart && Array.isArray(meta.chart.summaries)) {
        const valid = meta.chart.summaries.filter(
            (item) => item === 'RowCount' || meta.aggregates.includes(item)
        );
        meta.chart.summaries = valid.length ? valid : ['RowCount'];
    }
}

export function shiftAggregate(meta, index, delta) {
    meta.aggregates = move(meta.aggregates || [], index, delta);
}

/* ---------- Filters ---------- */

export function addFilter(meta, filter) {
    meta.reportFilters = [...(meta.reportFilters || []), cleanFilter(filter)];
}

export function updateFilter(meta, index, filter) {
    const list = (meta.reportFilters || []).slice();
    list[index] = cleanFilter(filter);
    meta.reportFilters = list;
}

export function removeFilter(meta, index) {
    const list = (meta.reportFilters || []).slice();
    list.splice(index, 1);
    meta.reportFilters = list;
    if (!list.length) meta.reportBooleanFilter = null;
}

function cleanFilter(filter) {
    return {
        column: filter.column,
        operator: filter.operator || 'equals',
        value: filter.value == null ? '' : String(filter.value)
    };
}

export function setBooleanFilter(meta, logic) {
    const text = String(logic || '').trim();
    meta.reportBooleanFilter = text || null;
}

export function setDateFilter(meta, patch) {
    meta.standardDateFilter = { ...(meta.standardDateFilter || {}), ...patch };
}

export function durationLabel(catalog, value) {
    for (const group of (catalog && catalog.dateDurations) || []) {
        for (const item of group.standardDateFilterDurations || []) {
            if (item.value === value) return item.label;
        }
    }
    return value === 'CUSTOM' ? 'Custom' : value || 'All time';
}

export function durationRange(catalog, value) {
    for (const group of (catalog && catalog.dateDurations) || []) {
        for (const item of group.standardDateFilterDurations || []) {
            if (item.value === value) return { startDate: item.startDate, endDate: item.endDate };
        }
    }
    return null;
}

/* ---------- Chart ---------- */

function ensureChartGroupings(meta) {
    if (!meta.chart) return;
    const down = (meta.groupingsDown || []).map((g) => g.name);
    const across = (meta.groupingsAcross || []).map((g) => g.name);
    if (!down.length) {
        meta.chart = null;
        return;
    }
    const wanted = [down[0]];
    const multi = chartTypeIsMulti(meta.chart.chartType);
    if (multi && (across[0] || down[1])) wanted.push(across[0] || down[1]);
    meta.chart.groupings = wanted;
}

function chartTypeIsMulti(chartType) {
    const hit = CHART_TYPES.find((item) => item.value === chartType);
    return Boolean(hit && hit.multi);
}

export function setChart(meta, patch) {
    if (patch === null) {
        meta.chart = null;
        return;
    }
    const current = meta.chart || {
        chartType: 'Vertical Bar',
        groupings: [],
        summaries: [(meta.aggregates || [])[0] || 'RowCount'],
        hasLegend: false,
        showChartValues: true,
        summaryAxisLocations: ['Y'],
        title: null
    };
    meta.chart = { ...current, ...patch };
    if (!meta.chart.summaries || !meta.chart.summaries.length) {
        meta.chart.summaries = [(meta.aggregates || [])[0] || 'RowCount'];
    }
    meta.chart.summaryAxisLocations = meta.chart.summaries.map(() => 'Y');
    meta.chart.hasLegend = chartTypeIsMulti(meta.chart.chartType) || /pie|donut/i.test(meta.chart.chartType);
    ensureChartGroupings(meta);
}

/* ---------- Validation ---------- */

export function validateMeta(meta) {
    const format = meta.reportFormat;
    if (format === 'SUMMARY' && !(meta.groupingsDown || []).length) {
        return 'Summary reports need at least one row grouping.';
    }
    if (format === 'MATRIX') {
        if (!(meta.groupingsDown || []).length || !(meta.groupingsAcross || []).length) {
            return 'Matrix reports need a row grouping and a column grouping.';
        }
    }
    if (format === 'TABULAR' && !(meta.detailColumns || []).length) {
        return 'Add at least one column.';
    }
    if (meta.reportBooleanFilter) {
        const count = (meta.reportFilters || []).length;
        const nums = String(meta.reportBooleanFilter).match(/\d+/g) || [];
        if (nums.some((n) => Number(n) < 1 || Number(n) > count)) {
            return `Filter logic can only reference filters 1 to ${count}.`;
        }
    }
    return '';
}

export function metaSignature(meta) {
    try {
        return JSON.stringify(meta);
    } catch (_err) {
        return String(Math.random());
    }
}
