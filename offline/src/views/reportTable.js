function columnLabel(extended, apiName) {
    const info =
        (extended && extended.detailColumnInfo && extended.detailColumnInfo[apiName]) ||
        (extended && extended.aggregateColumnInfo && extended.aggregateColumnInfo[apiName]);
    return (info && info.label) || apiName || '';
}

function cellLabel(cell) {
    if (cell == null) return '';
    if (typeof cell === 'string' || typeof cell === 'number') return String(cell);
    if (cell.label != null && cell.label !== '') return String(cell.label);
    if (cell.value != null) return String(cell.value);
    return '';
}

function numericValue(cell) {
    if (cell == null) return 0;
    if (typeof cell === 'number') return cell;
    const raw = cell.value != null ? cell.value : cell.label;
    const n = Number(String(raw).replace(/[^0-9.-]/g, ''));
    return Number.isFinite(n) ? n : 0;
}

function walkGroupings(groupings, path = []) {
    const out = [];
    (groupings || []).forEach((group) => {
        const next = [...path, group];
        out.push(next);
        if (group && group.groupings && group.groupings.length) {
            out.push(...walkGroupings(group.groupings, next));
        }
    });
    return out;
}

export function extractReportTable(report) {
    const meta = (report && report.reportMetadata) || {};
    const extended = (report && report.reportExtendedMetadata) || {};
    const factMap = (report && report.factMap) || {};
    const format = String(meta.reportFormat || 'TABULAR').toUpperCase();
    const detailColumns = meta.detailColumns || [];
    const aggregates = meta.aggregates || [];
    const groupingDown = ((report.groupingsDown && report.groupingsDown.groupings) || []);
    const groupingAcross = ((report.groupingsAcross && report.groupingsAcross.groupings) || []);

    const note =
        format === 'TABULAR'
            ? null
            : 'Summary layout flattened for offline viewing — not Lightning Report Builder.';

    if (format === 'TABULAR' || (!groupingDown.length && !groupingAcross.length)) {
        const block = factMap['T!T'] || {};
        const columns = detailColumns.length
            ? detailColumns.map((name) => columnLabel(extended, name))
            : aggregates.map((name) => columnLabel(extended, name));
        const rows = (block.rows || []).map((row) => (row.dataCells || []).map(cellLabel));
        if (!rows.length && (block.aggregates || []).length) {
            return {
                columns: aggregates.map((name) => columnLabel(extended, name)),
                rows: [(block.aggregates || []).map(cellLabel)],
                note
            };
        }
        return { columns, rows, note: format === 'TABULAR' ? null : note };
    }

    const aggLabels = aggregates.map((name) => columnLabel(extended, name));
    const downDepth = Math.max(1, (meta.groupingsDown || []).length);
    const downHeaders = Array.from({ length: downDepth }, (_, i) => `Group ${i + 1}`);
    const acrossPaths = groupingAcross.length ? walkGroupings(groupingAcross) : [[]];
    const acrossLabels = acrossPaths.map((path) =>
        path.length ? path.map((g) => g.label || g.value || '').join(' / ') : 'Total'
    );

    const columns = [
        ...downHeaders,
        ...(acrossPaths.length > 1
            ? acrossLabels.flatMap((label) => aggLabels.map((agg) => (label ? `${label} — ${agg}` : agg)))
            : aggLabels),
        ...detailColumns.map((name) => columnLabel(extended, name))
    ];

    const rows = [];
    const downPaths = groupingDown.length ? walkGroupings(groupingDown) : [[]];
    downPaths.forEach((path) => {
        const downKey = path.length ? path[path.length - 1].key : 'T';
        const downLabels = path.map((g) => g.label || g.value || '');
        while (downLabels.length < downDepth) downLabels.push('');

        const aggCells = [];
        acrossPaths.forEach((acrossPath) => {
            const acrossKey = acrossPath.length ? acrossPath[acrossPath.length - 1].key : 'T';
            const fact = factMap[`${downKey}!${acrossKey}`] || {};
            const values = (fact.aggregates || []).map(cellLabel);
            while (values.length < aggLabels.length) values.push('');
            aggCells.push(...values.slice(0, aggLabels.length));
        });

        const leaf = !path.length || !(path[path.length - 1].groupings || []).length;
        const fact = factMap[`${downKey}!T`] || {};
        const detailRows = leaf ? fact.rows || [] : [];
        if (detailRows.length) {
            detailRows.forEach((row) => {
                rows.push([...downLabels, ...aggCells, ...(row.dataCells || []).map(cellLabel)]);
            });
        } else {
            rows.push([...downLabels, ...aggCells]);
        }
    });

    const grand = factMap['T!T'];
    if (grand && (grand.aggregates || []).length) {
        const totalRow = ['Grand Total', ...Array(Math.max(0, downDepth - 1)).fill('')];
        acrossPaths.forEach((acrossPath) => {
            const acrossKey = acrossPath.length ? acrossPath[acrossPath.length - 1].key : 'T';
            const fact = factMap[`T!${acrossKey}`] || grand;
            const values = (fact.aggregates || []).map(cellLabel);
            while (values.length < aggLabels.length) values.push('');
            totalRow.push(...values.slice(0, aggLabels.length));
        });
        rows.push(totalRow);
    }

    return { columns, rows, note };
}

export function extractChartSeries(report) {
    const factMap = (report && report.factMap) || {};
    const groupings = (report && report.groupingsDown && report.groupingsDown.groupings) || [];
    const items = groupings.map((group) => {
        const fact = factMap[`${group.key}!T`] || {};
        const agg = (fact.aggregates || [])[0];
        return {
            label: group.label || group.value || 'Group',
            value: numericValue(agg),
            display: cellLabel(agg)
        };
    });
    if (items.length) return items;
    const grand = factMap['T!T'];
    if (grand && (grand.aggregates || []).length) {
        return (grand.aggregates || []).map((agg, i) => ({
            label: `Total ${i + 1}`,
            value: numericValue(agg),
            display: cellLabel(agg)
        }));
    }
    return [];
}

export function extractMetric(report) {
    const factMap = (report && report.factMap) || {};
    const grand = factMap['T!T'] || {};
    const agg = (grand.aggregates || [])[0];
    if (agg) {
        return { value: cellLabel(agg), numeric: numericValue(agg) };
    }
    const rows = grand.rows || [];
    if (rows.length && rows[0].dataCells && rows[0].dataCells.length) {
        const cell = rows[0].dataCells[rows[0].dataCells.length - 1];
        return { value: cellLabel(cell), numeric: numericValue(cell) };
    }
    return { value: '—', numeric: 0 };
}

export function tableHtml(table) {
    if (!table || !table.columns || !table.columns.length) {
        return '<p class="osr-tab-empty">No rows to display.</p>';
    }
    const head = table.columns
        .map((col) => `<th scope="col">${escapeAttr(col)}</th>`)
        .join('');
    const body =
        table.rows && table.rows.length
            ? table.rows
                  .map(
                      (row) =>
                          `<tr>${table.columns
                              .map((_, i) => `<td>${escapeAttr(row[i] == null ? '' : row[i])}</td>`)
                              .join('')}</tr>`
                  )
                  .join('')
            : `<tr><td colspan="${table.columns.length}">No rows to display.</td></tr>`;
    return `<div class="osr-table-wrap"><table class="osr-table"><thead><tr>${head}</tr></thead><tbody>${body}</tbody></table></div>`;
}

function escapeAttr(str) {
    return String(str ?? '')
        .replace(/&/g, '&amp;')
        .replace(/</g, '&lt;')
        .replace(/>/g, '&gt;')
        .replace(/"/g, '&quot;');
}

export function barChartHtml(series) {
    if (!series || !series.length) {
        return '<p class="osr-tab-empty">No chart data.</p>';
    }
    const max = Math.max(1, ...series.map((item) => Math.abs(item.value) || 0));
    return `<div class="osr-bars">${series
        .map((item) => {
            const pct = Math.min(100, Math.round((Math.abs(item.value) / max) * 100));
            return `<div class="osr-bar-row">
                <span class="osr-bar-label">${escapeAttr(item.label)}</span>
                <div class="osr-bar-track"><div class="osr-bar-fill" style="width:${pct}%"></div></div>
                <span class="osr-bar-value">${escapeAttr(item.display || item.value)}</span>
            </div>`;
        })
        .join('')}</div>`;
}
