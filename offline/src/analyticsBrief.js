import { buildReportModel } from './views/reportGrid.js';

function text(value) {
    return value == null ? '' : String(value);
}

function folderCounts(rows, folderKey, fallback) {
    const counts = new Map();
    (rows || []).forEach((row) => {
        const name = text(row[folderKey]) || fallback;
        counts.set(name, (counts.get(name) || 0) + 1);
    });
    return [...counts.entries()]
        .map(([name, count]) => ({ name, count }))
        .sort((a, b) => b.count - a.count || a.name.localeCompare(b.name));
}

export function summarizeReportCatalog(rows) {
    const list = Array.isArray(rows) ? rows : [];
    const items = list.map((row) => ({
        id: row.Id,
        name: row.Name || 'Untitled report',
        folder: row.FolderName || 'Private Reports',
        format: row.Format || 'Tabular',
        description: row.Description || '',
        lastRun: row.LastRunDate || ''
    }));
    return {
        kind: 'report-list',
        total: items.length,
        recent: items.filter((row) => row.lastRun).slice(0, 8),
        folders: folderCounts(list, 'FolderName', 'Private Reports').slice(0, 12),
        items
    };
}

export function summarizeDashboardCatalog(rows) {
    const list = Array.isArray(rows) ? rows : [];
    const items = list.map((row) => ({
        id: row.Id,
        name: row.Title || 'Untitled dashboard',
        folder: row.FolderName || 'Private Dashboards',
        description: row.Description || '',
        lastViewed: row.LastViewedDate || ''
    }));
    return {
        kind: 'dashboard-list',
        total: items.length,
        recent: items.filter((row) => row.lastViewed).slice(0, 8),
        folders: folderCounts(list, 'FolderName', 'Private Dashboards').slice(0, 12),
        items
    };
}

function metricLines(model, cells) {
    return (model.aggCols || [])
        .slice(0, 4)
        .map((col) => {
            const cell = cells && cells[col.index];
            const value = cell && cell.label;
            return value ? { label: col.label, value } : null;
        })
        .filter(Boolean);
}

export function summarizeReportResult(result, extra = {}) {
    const model = buildReportModel(result);
    const meta = (result && result.reportMetadata) || {};
    const chart = meta.chart && meta.chart.chartType && String(meta.chart.chartType).toLowerCase() !== 'none'
        ? String(meta.chart.chartType)
        : '';
    const groups = (model.nodes || []).slice(0, 8).map((node) => ({
        label: node.label,
        count: node.count,
        metrics: metricLines(model, node.aggs)
    }));
    const columns = (model.format === 'TABULAR' ? model.detailCols : [...model.groupCols, ...model.aggCols])
        .slice(0, 8)
        .map((col) => col.label)
        .filter(Boolean);
    const topRows = model.format === 'TABULAR'
        ? (model.rows || []).slice(0, 6).map((row) =>
              row
                  .map((cell) => cell.label)
                  .filter(Boolean)
                  .slice(0, 4)
                  .join(' · ')
          ).filter(Boolean)
        : [];
    return {
        kind: 'report',
        id: extra.id || meta.id || 'new',
        name: extra.name || meta.name || 'Report',
        folder: extra.folder || '',
        format: model.format || meta.reportFormat || 'TABULAR',
        chart,
        status: 'ready',
        totals: [{ label: 'Records', value: String(model.totalRows) }, ...metricLines(model, model.grand)],
        groups,
        columns,
        filters: Array.isArray(extra.filters) ? extra.filters : [],
        topRows,
        truncated: Boolean(model.truncated),
        rowCount: model.totalRows
    };
}
