const NUMERIC = new Set(['currency', 'double', 'int', 'percent']);

function esc(str) {
    return String(str ?? '')
        .replace(/&/g, '&amp;')
        .replace(/</g, '&lt;')
        .replace(/>/g, '&gt;')
        .replace(/"/g, '&quot;');
}

function toCell(raw) {
    if (raw == null) return { label: '', value: null };
    if (typeof raw !== 'object') return { label: String(raw), value: raw };
    const label = raw.label != null && raw.label !== '' ? String(raw.label) : raw.value != null ? String(raw.value) : '';
    return { label, value: raw.value != null ? raw.value : raw.label, recordId: raw.recordId || null };
}

function sortValue(cell) {
    if (!cell) return '';
    const v = cell.value;
    if (typeof v === 'number') return v;
    if (v && typeof v === 'object' && v.amount != null) return Number(v.amount);
    const n = Number(String(cell.label).replace(/[^0-9.-]/g, ''));
    if (cell.label !== '' && Number.isFinite(n) && /^[\s\-$€£%0-9.,A-Z]*$/i.test(cell.label) && /\d/.test(cell.label)) {
        return n;
    }
    return String(cell.label || '').toLowerCase();
}

function compare(a, b) {
    if (typeof a === 'number' && typeof b === 'number') return a - b;
    return String(a).localeCompare(String(b), undefined, { numeric: true });
}

function aggInfo(ext, key) {
    if (key === 'RowCount') return { label: 'Record Count', dataType: 'int' };
    const info = ext.aggregateColumnInfo && ext.aggregateColumnInfo[key];
    return {
        label: (info && info.label) || String(key).split('.').pop(),
        dataType: String((info && info.dataType) || 'double').toLowerCase()
    };
}

function detailInfo(ext, key) {
    const info = ext.detailColumnInfo && ext.detailColumnInfo[key];
    return {
        label: (info && info.label) || String(key).split('.').pop(),
        dataType: String((info && info.dataType) || 'string').toLowerCase()
    };
}

function groupInfo(ext, name, fallback) {
    const info = ext.groupingColumnInfo && ext.groupingColumnInfo[name];
    return (info && info.label) || fallback;
}

export function buildReportModel(report) {
    const meta = (report && report.reportMetadata) || {};
    const ext = (report && report.reportExtendedMetadata) || {};
    const factMap = (report && report.factMap) || {};
    const downDefs = meta.groupingsDown || [];
    const acrossDefs = meta.groupingsAcross || [];
    const downTree = (report && report.groupingsDown && report.groupingsDown.groupings) || [];
    const acrossTree = (report && report.groupingsAcross && report.groupingsAcross.groupings) || [];
    let format = String(meta.reportFormat || 'TABULAR').toUpperCase();
    if (format === 'MATRIX' && !acrossTree.length && !acrossDefs.length) format = 'SUMMARY';
    if (format !== 'TABULAR' && !downTree.length && !downDefs.length && !acrossTree.length) format = 'TABULAR';

    const aggKeys = meta.aggregates || [];
    const grandCount = ((factMap['T!T'] || {}).aggregates || []).length;
    let countIndex = aggKeys.indexOf('RowCount');
    if (countIndex < 0 && grandCount > aggKeys.length) countIndex = aggKeys.length;
    const aggCols = aggKeys
        .map((key, index) => ({ key, index, ...aggInfo(ext, key) }))
        .filter((col) => col.key !== 'RowCount');
    const detailCols = (meta.detailColumns || []).map((key) => ({ key, ...detailInfo(ext, key) }));
    const groupCols = downDefs.map((g, i) => ({ key: g.name, label: groupInfo(ext, g.name, `Group ${i + 1}`) }));
    const acrossCols = acrossDefs.map((g, i) => ({ key: g.name, label: groupInfo(ext, g.name, `Column ${i + 1}`) }));
    const hasDetails = report && report.hasDetailRows !== false && detailCols.length > 0;

    const aggsAt = (downKey, acrossKey = 'T') =>
        ((factMap[`${downKey}!${acrossKey}`] || {}).aggregates || []).map(toCell);
    const rowsAt = (downKey, acrossKey = 'T') =>
        ((factMap[`${downKey}!${acrossKey}`] || {}).rows || []).map((row) =>
            (row.dataCells || []).map(toCell)
        );
    const countFrom = (aggs) => {
        const cell = countIndex >= 0 ? aggs[countIndex] : null;
        const n = cell ? Number(cell.value) : NaN;
        return Number.isFinite(n) ? n : null;
    };

    const model = {
        format,
        aggCols,
        detailCols,
        groupCols,
        acrossCols,
        hasDetails,
        countIndex,
        detailsByDefault: meta.hasDetailRows !== false,
        showCount: meta.hasRecordCount === true || !aggCols.length,
        nodes: [],
        rows: [],
        grand: aggsAt('T'),
        totalRows: 0,
        truncated: Boolean(report && (report.allData === false || report.hasExceededTabularRowLimit))
    };

    if (format === 'TABULAR') {
        model.rows = rowsAt('T');
        model.totalRows = countFrom(model.grand) ?? model.rows.length;
        return model;
    }

    const buildNode = (group, depth) => {
        const children = (group.groupings || []).map((child) => buildNode(child, depth + 1));
        const rows = !children.length && hasDetails ? rowsAt(group.key) : [];
        const aggs = aggsAt(group.key);
        const count = countFrom(aggs) ?? (children.length
            ? children.reduce((sum, child) => sum + child.count, 0)
            : rows.length);
        return {
            key: group.key,
            label: group.label != null && group.label !== '' ? String(group.label) : String(group.value ?? '-'),
            depth,
            aggs,
            rows,
            children,
            count
        };
    };
    model.nodes = downTree.map((group) => buildNode(group, 0));
    model.totalRows = countFrom(model.grand) ?? model.nodes.reduce((sum, node) => sum + node.count, 0);

    if (format === 'MATRIX') {
        const leafPaths = [];
        const walk = (groups, path) => {
            groups.forEach((group) => {
                const next = [...path, group];
                if ((group.groupings || []).length) walk(group.groupings, next);
                else leafPaths.push(next);
            });
        };
        walk(acrossTree, []);
        model.acrossPaths = leafPaths.map((path) => ({
            key: path[path.length - 1].key,
            label: path.map((g) => (g.label != null && g.label !== '' ? g.label : g.value ?? '-')).join(' / ')
        }));
        model.matrixAt = (downKey, acrossKey) => aggsAt(downKey, acrossKey);
    }
    return model;
}

/* ---------- View state helpers ---------- */

export function defaultGridView(model) {
    return {
        sortCol: null,
        sortDir: 'asc',
        search: '',
        collapsed: new Set(),
        detailOpen: new Set(),
        showDetails: model ? model.hasDetails && model.detailsByDefault && model.totalRows <= 150 : false
    };
}

function rowMatches(row, term) {
    return row.some((cell) => String(cell.label).toLowerCase().includes(term));
}

function filterNodes(nodes, term) {
    if (!term) return nodes;
    const out = [];
    nodes.forEach((node) => {
        const selfHit = node.label.toLowerCase().includes(term);
        if (selfHit) {
            out.push(node);
            return;
        }
        const children = filterNodes(node.children, term);
        const rows = node.rows.filter((row) => rowMatches(row, term));
        if (children.length || rows.length) out.push({ ...node, children, rows, forceOpen: true });
    });
    return out;
}

function sortNodes(nodes, view) {
    if (view.sortCol == null) return nodes;
    const dir = view.sortDir === 'desc' ? -1 : 1;
    const pick = (node) =>
        view.sortCol === 'label'
            ? node.label.toLowerCase()
            : view.sortCol === 'count'
              ? node.count
              : sortValue(node.aggs[view.sortCol]);
    return nodes
        .slice()
        .sort((a, b) => dir * compare(pick(a), pick(b)))
        .map((node) => ({ ...node, children: sortNodes(node.children, view) }));
}

function sortRows(rows, view) {
    if (view.sortCol == null || typeof view.sortCol !== 'number') return rows;
    const dir = view.sortDir === 'desc' ? -1 : 1;
    return rows.slice().sort((a, b) => dir * compare(sortValue(a[view.sortCol]), sortValue(b[view.sortCol])));
}

function thSort(label, col, view, extra = '') {
    const active = view.sortCol === col;
    const arrow = active ? (view.sortDir === 'desc' ? '\u2193' : '\u2191') : '';
    return `<th scope="col" class="rg-th${active ? ' is-sorted' : ''}${extra}" data-rg-sort="${esc(col)}"><span>${esc(label)}</span><i aria-hidden="true">${arrow}</i></th>`;
}

function numClass(dataType) {
    return NUMERIC.has(dataType) ? ' rg-num' : '';
}

function cellHtml(cell, dataType) {
    return `<td class="rg-td${numClass(dataType)}">${esc(cell ? cell.label : '')}</td>`;
}

/* ---------- Renderers ---------- */

function tabularHtml(model, view) {
    const term = view.search.trim().toLowerCase();
    let rows = term ? model.rows.filter((row) => rowMatches(row, term)) : model.rows;
    rows = sortRows(rows, view);
    const head = model.detailCols.map((col, i) => thSort(col.label, i, view, numClass(col.dataType))).join('');
    const body = rows.length
        ? rows
              .map(
                  (row) =>
                      `<tr>${model.detailCols.map((col, i) => cellHtml(row[i], col.dataType)).join('')}</tr>`
              )
              .join('')
        : `<tr><td class="rg-empty" colspan="${Math.max(1, model.detailCols.length)}">No rows match.</td></tr>`;
    const chips = model.aggCols.map(
        (col) => `<span class="rg-chip"><b>${esc(col.label)}</b> ${esc(model.grand[col.index] ? model.grand[col.index].label : '')}</span>`
    );
    if (model.showCount) chips.unshift(`<span class="rg-chip"><b>Records</b> ${esc(model.totalRows.toLocaleString())}</span>`);
    const foot = chips.length
        ? `<tfoot><tr><td class="rg-td" colspan="${Math.max(1, model.detailCols.length)}">${chips.join('')}</td></tr></tfoot>`
        : '';
    return `<table class="rg-table"><thead><tr>${head}</tr></thead><tbody>${body}</tbody>${foot}</table>`;
}

function detailTableHtml(model, rows) {
    const head = model.detailCols
        .map((col) => `<th scope="col" class="rg-th${numClass(col.dataType)}">${esc(col.label)}</th>`)
        .join('');
    const body = rows
        .map((row) => `<tr>${model.detailCols.map((col, i) => cellHtml(row[i], col.dataType)).join('')}</tr>`)
        .join('');
    return `<table class="rg-table rg-table--detail"><thead><tr>${head}</tr></thead><tbody>${body}</tbody></table>`;
}

function summaryHtml(model, view) {
    const term = view.search.trim().toLowerCase();
    const nodes = sortNodes(filterNodes(model.nodes, term), view);
    const groupLabel = model.groupCols.map((col) => col.label).join(' \u203a ') || 'Group';
    const showCount = model.showCount;
    const colCount = 1 + (showCount ? 1 : 0) + model.aggCols.length;
    const head = [
        thSort(groupLabel, 'label', view, ' rg-th--group'),
        showCount ? thSort('Records', 'count', view, ' rg-num rg-th--count') : '',
        ...model.aggCols.map((col) => thSort(col.label, col.index, view, numClass(col.dataType)))
    ].join('');
    const out = [];
    const renderNode = (node) => {
        const hasKids = node.children.length > 0;
        const canDetail = !hasKids && node.rows.length > 0;
        const open = hasKids
            ? node.forceOpen || !view.collapsed.has(node.key)
            : canDetail && (node.forceOpen || view.showDetails || view.detailOpen.has(node.key));
        const toggle =
            hasKids || canDetail
                ? `<button type="button" class="rg-toggle${open ? ' is-open' : ''}" data-rg-toggle="${esc(node.key)}" data-rg-kind="${hasKids ? 'group' : 'detail'}" aria-expanded="${open}" aria-label="${open ? 'Collapse' : 'Expand'} ${esc(node.label)}"></button>`
                : '<span class="rg-toggle-spacer"></span>';
        out.push(
            `<tr class="rg-group rg-depth-${node.depth}${hasKids ? ' rg-group--parent' : ''}">
                <td class="rg-td rg-td--group" style="--rg-depth:${node.depth}">${toggle}<span class="rg-group-label">${esc(node.label)}</span></td>
                ${showCount ? `<td class="rg-td rg-num rg-td--count">${node.count ? node.count.toLocaleString() : ''}</td>` : ''}
                ${model.aggCols.map((col) => cellHtml(node.aggs[col.index], col.dataType)).join('')}
            </tr>`
        );
        if (!open) return;
        if (hasKids) node.children.forEach(renderNode);
        else if (canDetail) {
            out.push(
                `<tr class="rg-detail-row"><td colspan="${colCount}" style="--rg-depth:${node.depth + 1}"><div class="rg-detail">${detailTableHtml(model, node.rows)}</div></td></tr>`
            );
        }
    };
    nodes.forEach(renderNode);
    if (!nodes.length) {
        out.push(`<tr><td class="rg-empty" colspan="${colCount}">No groups match.</td></tr>`);
    }
    const grand = model.grand.length
        ? `<tfoot><tr class="rg-total"><td class="rg-td">Grand Total</td>${showCount ? `<td class="rg-td rg-num">${model.totalRows ? model.totalRows.toLocaleString() : ''}</td>` : ''}${model.aggCols
              .map((col) => cellHtml(model.grand[col.index], col.dataType))
              .join('')}</tr></tfoot>`
        : '';
    return `<table class="rg-table rg-table--summary"><thead><tr>${head}</tr></thead><tbody>${out.join('')}</tbody>${grand}</table>`;
}

function matrixAggs(model) {
    const cols = model.aggCols.slice();
    if ((model.showCount || !cols.length) && model.countIndex >= 0) {
        cols.unshift({ key: 'RowCount', index: model.countIndex, label: 'Record Count', dataType: 'int' });
    }
    return cols;
}

function matrixHtml(model, view) {
    const term = view.search.trim().toLowerCase();
    const nodes = sortNodes(filterNodes(model.nodes, term), view);
    const aggs = matrixAggs(model);
    const paths = [...(model.acrossPaths || []), { key: 'T', label: 'Total' }];
    const multi = aggs.length > 1;
    const groupLabel = model.groupCols.map((col) => col.label).join(' \u203a ') || 'Group';
    const acrossLabel = model.acrossCols.map((col) => col.label).join(' \u203a ');
    const top = [
        `<th scope="col" class="rg-th rg-th--group" rowspan="${multi ? 2 : 1}" data-rg-sort="label"><span>${esc(groupLabel)}${acrossLabel ? ` <em>by ${esc(acrossLabel)}</em>` : ''}</span></th>`,
        ...paths.map(
            (path) =>
                `<th scope="colgroup" class="rg-th rg-th--across${path.key === 'T' ? ' rg-th--total' : ''}" colspan="${aggs.length}">${esc(path.label)}</th>`
        )
    ].join('');
    const second = multi
        ? `<tr>${paths
              .map(() => aggs.map((col) => `<th scope="col" class="rg-th rg-num rg-th--sub">${esc(col.label)}</th>`).join(''))
              .join('')}</tr>`
        : '';
    const out = [];
    const renderNode = (node) => {
        const hasKids = node.children.length > 0;
        const open = hasKids && (node.forceOpen || !view.collapsed.has(node.key));
        const toggle = hasKids
            ? `<button type="button" class="rg-toggle${open ? ' is-open' : ''}" data-rg-toggle="${esc(node.key)}" data-rg-kind="group" aria-expanded="${open}"></button>`
            : '<span class="rg-toggle-spacer"></span>';
        const cells = paths
            .map((path) => {
                const values = model.matrixAt(node.key, path.key);
                return aggs
                    .map((col) => `<td class="rg-td rg-num${path.key === 'T' ? ' rg-td--total' : ''}">${esc(values[col.index] ? values[col.index].label : '')}</td>`)
                    .join('');
            })
            .join('');
        out.push(
            `<tr class="rg-group rg-depth-${node.depth}${hasKids ? ' rg-group--parent' : ''}"><td class="rg-td rg-td--group" style="--rg-depth:${node.depth}">${toggle}<span class="rg-group-label">${esc(node.label)}</span></td>${cells}</tr>`
        );
        if (open) node.children.forEach(renderNode);
    };
    nodes.forEach(renderNode);
    const grandCells = paths
        .map((path) => {
            const values = model.matrixAt('T', path.key);
            return aggs.map((col) => `<td class="rg-td rg-num">${esc(values[col.index] ? values[col.index].label : '')}</td>`).join('');
        })
        .join('');
    return `<table class="rg-table rg-table--matrix"><thead><tr>${top}</tr>${second}</thead><tbody>${out.join('')}</tbody><tfoot><tr class="rg-total"><td class="rg-td">Grand Total</td>${grandCells}</tr></tfoot></table>`;
}

export function reportGridHtml(model, view) {
    if (!model) return '<p class="osr-tab-empty">No rows to display.</p>';
    let table;
    if (model.format === 'MATRIX') table = matrixHtml(model, view);
    else if (model.format === 'SUMMARY') table = summaryHtml(model, view);
    else if (!model.detailCols.length) table = '<p class="osr-tab-empty rg-pad">Add columns to see rows.</p>';
    else table = tabularHtml(model, view);
    const note = model.truncated
        ? '<p class="rg-note">Salesforce returned the first 2,000 rows. Add filters to narrow the results.</p>'
        : '';
    return `<div class="rg-wrap">${table}</div>${note}`;
}

export function summaryStripHtml(model) {
    if (!model) return '';
    const tiles = [
        { label: 'Total Records', value: model.totalRows.toLocaleString() }
    ];
    model.aggCols.forEach((col) => {
        const cell = model.grand[col.index];
        if (cell && cell.label !== '') tiles.push({ label: col.label, value: cell.label });
    });
    return `<div class="rg-strip">${tiles
        .slice(0, 6)
        .map((tile) => `<div class="rg-stat"><span>${esc(tile.label)}</span><strong>${esc(tile.value)}</strong></div>`)
        .join('')}</div>`;
}

/* ---------- CSV ---------- */

function csvCell(value) {
    const text = String(value ?? '');
    return /[",\n]/.test(text) ? `"${text.replace(/"/g, '""')}"` : text;
}

export function modelToCsv(model) {
    const lines = [];
    if (!model) return '';
    if (model.format === 'TABULAR') {
        lines.push(model.detailCols.map((col) => col.label));
        model.rows.forEach((row) => lines.push(row.map((cell) => cell.label)));
    } else if (model.format === 'MATRIX') {
        const paths = [...(model.acrossPaths || []), { key: 'T', label: 'Total' }];
        const aggs = matrixAggs(model);
        lines.push([
            model.groupCols.map((c) => c.label).join(' / ') || 'Group',
            ...paths.flatMap((p) => aggs.map((a) => `${p.label} - ${a.label}`))
        ]);
        const walk = (nodes) =>
            nodes.forEach((node) => {
                lines.push([
                    `${'  '.repeat(node.depth)}${node.label}`,
                    ...paths.flatMap((p) => aggs.map((col) => (model.matrixAt(node.key, p.key)[col.index] || {}).label || ''))
                ]);
                walk(node.children);
            });
        walk(model.nodes);
    } else {
        const detail = model.hasDetails;
        lines.push([
            ...model.groupCols.map((c) => c.label),
            'Records',
            ...model.aggCols.map((c) => c.label),
            ...(detail ? model.detailCols.map((c) => c.label) : [])
        ]);
        const depth = Math.max(1, model.groupCols.length);
        const walk = (nodes, path) =>
            nodes.forEach((node) => {
                const labels = [...path, node.label];
                const pad = Array(depth - labels.length).fill('');
                lines.push([...labels, ...pad, node.count, ...model.aggCols.map((col) => (node.aggs[col.index] || {}).label || '')]);
                if (detail) {
                    node.rows.forEach((row) => {
                        lines.push([
                            ...labels,
                            ...pad,
                            '',
                            ...model.aggCols.map(() => ''),
                            ...row.map((c) => c.label)
                        ]);
                    });
                }
                walk(node.children, labels);
            });
        walk(model.nodes, []);
    }
    return lines.map((line) => line.map(csvCell).join(',')).join('\n');
}
