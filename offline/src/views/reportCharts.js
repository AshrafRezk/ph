import { extractChartData, extractMetric, reportChartType } from './reportTable.js';

export const PALETTE = [
    '#52b7d8',
    '#e16032',
    '#ffb03b',
    '#54a77b',
    '#4fd2d2',
    '#e287b2',
    '#8fa8c8',
    '#b6a3e0',
    '#f0a7a0',
    '#107cad',
    '#d4b45f',
    '#6a8d4e'
];

const MAX_CATEGORIES = 30;
const FONT = 11;

function escapeXml(str) {
    return String(str ?? '')
        .replace(/&/g, '&amp;')
        .replace(/</g, '&lt;')
        .replace(/>/g, '&gt;')
        .replace(/"/g, '&quot;');
}

function clip(text, maxPx) {
    const s = String(text ?? '');
    const n = Math.max(3, Math.floor(maxPx / (FONT * 0.58)));
    return s.length > n ? `${s.slice(0, n - 1)}\u2026` : s;
}

function color(i) {
    return PALETTE[i % PALETTE.length];
}

function compact(raw) {
    return String(raw || '')
        .toLowerCase()
        .replace(/[\s_-]+/g, '');
}

export function normalizeChartKind(raw) {
    const s = compact(raw);
    if (!s || s === 'none') return '';
    if (/(visualforce|scontrol|\bimage\b|lightningcomponent|\blwc\b|richtext|filterpanel)/.test(s)) {
        return 'unsupported';
    }
    if (s.includes('flextable') || s === 'table' || s.endsWith('table')) return 'table';
    if (s.includes('metric') && !s.includes('chart')) return 'metric';
    if (s.includes('gauge')) return 'gauge';
    if (s.includes('funnel') || s.includes('pyramid')) return 'funnel';
    if (s.includes('donut') || s.includes('doughnut')) return 'donut';
    if (s.includes('pie')) return 'pie';
    if (s.includes('scatter') || s.includes('bubble')) return 'scatter';
    if (s.includes('combo') || s.includes('columnline') || s.includes('barline')) return 'combo';
    if (s.includes('line')) return 'line';
    const vertical = s.includes('vbar') || s.includes('column') || s.includes('vertical');
    if (s.includes('waterfall')) return 'vbar-stacked';
    if (s.includes('stack') && (s.includes('100') || s.includes('percent'))) {
        return vertical ? 'vbar-stack100' : 'hbar-stack100';
    }
    if (s.includes('stack')) return vertical ? 'vbar-stacked' : 'hbar-stacked';
    if (s.includes('group')) return vertical ? 'vbar-grouped' : 'hbar-grouped';
    if (vertical) return 'vbar';
    if (s === 'bar' || s.includes('hbar') || s.includes('horizontal') || s.includes('bar')) return 'hbar';
    if (s === 'chart' || s === 'reportchart' || s === 'reportchartcomponent') return 'chart';
    return '';
}

export function resolveChartKind(component, report) {
    const props = (component && (component.properties || component.attributes)) || {};
    if (props.useReportChart && reportChartType(report)) {
        const fromReport = normalizeChartKind(reportChartType(report));
        if (fromReport && fromReport !== 'chart') return fromReport;
    }
    const hints = [
        props.visualizationType,
        props.chartType,
        component && component.visualizationType,
        component && component.chartType,
        component && (component.type || component.componentType),
        reportChartType(report)
    ];
    let generic = false;
    for (const hint of hints) {
        const kind = normalizeChartKind(hint);
        if (kind === 'chart') {
            generic = true;
            continue;
        }
        if (kind) return kind;
    }
    if (generic) return reportChartType(report) ? normalizeChartKind(reportChartType(report)) || 'vbar' : 'vbar';
    return '';
}

export function isWideChart(kind) {
    return /^(hbar|vbar|line|combo|scatter|funnel)/.test(String(kind || ''));
}

function trimData(data, max = MAX_CATEGORIES) {
    if (data.categories.length <= max) return { ...data, truncated: false };
    return {
        categories: data.categories.slice(0, max),
        series: data.series.map((series) => ({
            ...series,
            values: series.values.slice(0, max),
            displays: series.displays.slice(0, max)
        })),
        truncated: true
    };
}

function toPercent(data) {
    const totals = data.categories.map(
        (_, i) => data.series.reduce((sum, series) => sum + Math.abs(series.values[i] || 0), 0) || 1
    );
    return {
        ...data,
        series: data.series.map((series) => ({
            ...series,
            values: series.values.map((value, i) => (Math.abs(value) / totals[i]) * 100),
            displays: series.values.map((value, i) => `${Math.round((Math.abs(value) / totals[i]) * 100)}%`)
        }))
    };
}

/* ---------- Scales ---------- */

function niceStep(range, count) {
    const raw = range / Math.max(1, count);
    const mag = 10 ** Math.floor(Math.log10(raw || 1));
    const norm = raw / mag;
    const step = norm >= 5 ? 10 : norm >= 2 ? 5 : norm >= 1 ? 2 : 1;
    return step * mag;
}

function scaleFor(values, { stacked = false, ticks = 4, pct = false } = {}) {
    const max = pct ? 100 : Math.max(0, ...values);
    const min = pct ? 0 : Math.min(0, ...values);
    if (max === min) return { min: 0, max: max || 1, ticks: [0, max || 1] };
    const step = niceStep(max - min, ticks);
    const lo = Math.floor(min / step) * step;
    const hi = Math.ceil(max / step) * step;
    const list = [];
    for (let v = lo; v <= hi + step / 2; v += step) list.push(Number(v.toFixed(10)));
    return { min: lo, max: hi, ticks: list, stacked };
}

export function shortNumber(value) {
    const n = Number(value);
    if (!Number.isFinite(n)) return String(value ?? '');
    const abs = Math.abs(n);
    if (abs >= 1e9) return `${(n / 1e9).toFixed(abs >= 1e10 ? 0 : 1)}B`;
    if (abs >= 1e6) return `${(n / 1e6).toFixed(abs >= 1e7 ? 0 : 1)}M`;
    if (abs >= 1e3) return `${(n / 1e3).toFixed(abs >= 1e4 ? 0 : 1)}K`;
    return String(Math.round(n * 100) / 100);
}

function tipAttr(parts) {
    return `data-tip="${escapeXml(parts.filter(Boolean).join('\n'))}"`;
}

function svgOpen(w, h, extra = '') {
    return `<svg class="osr-chart-svg${extra}" viewBox="0 0 ${w} ${h}" width="${w}" height="${h}" role="img" preserveAspectRatio="xMidYMid meet">`;
}

function stackTotals(data) {
    return data.categories.map((_, i) =>
        data.series.reduce((sum, series) => sum + Math.max(0, series.values[i] || 0), 0)
    );
}

/* ---------- Vertical bars / line / combo ---------- */

function cartesian(data, opts) {
    const { w, h, mode, showValues } = opts;
    const stacked = mode === 'stacked' || mode === 'stack100';
    const pct = mode === 'stack100';
    const src = pct ? toPercent(data) : data;
    const values = stacked ? stackTotals(src) : src.series.flatMap((s) => s.values);
    const scale = scaleFor(values, { pct });
    const n = src.categories.length;
    const tickW = Math.max(...scale.ticks.map((t) => shortNumber(t).length)) * 6.5 + 10;
    let left = Math.max(28, tickW);
    const right = 10;
    const top = showValues ? 18 : 10;
    let slot = (w - left - right) / Math.max(1, n);
    const rotate = slot < 56 && n > 3;
    const longest = Math.max(...src.categories.map((c) => String(c).length));
    const bottom = rotate ? Math.min(78, 22 + Math.min(14, longest) * 4.2) : 26;
    if (rotate && n) {
        const firstLabelW = Math.min(bottom * 1.35, String(src.categories[0]).length * 5.6) * Math.cos((38 * Math.PI) / 180);
        left = Math.max(left, Math.min(w * 0.22, firstLabelW - slot / 2 + 4));
        slot = (w - left - right) / n;
    }
    const plotH = Math.max(40, h - top - bottom);
    const plotW = w - left - right;
    const y = (v) => top + plotH - ((v - scale.min) / (scale.max - scale.min || 1)) * plotH;
    const parts = [];
    scale.ticks.forEach((t) => {
        const ty = y(t);
        parts.push(`<line x1="${left}" x2="${w - right}" y1="${ty.toFixed(1)}" y2="${ty.toFixed(1)}" class="osr-chart-grid${t === 0 ? ' is-zero' : ''}"/>`);
        parts.push(`<text x="${left - 6}" y="${ty.toFixed(1)}" text-anchor="end" dominant-baseline="middle" class="osr-chart-tick">${escapeXml(pct ? `${t}%` : shortNumber(t))}</text>`);
    });
    src.categories.forEach((label, i) => {
        const cx = left + slot * i + slot / 2;
        if (rotate) {
            parts.push(`<text transform="translate(${cx.toFixed(1)},${top + plotH + 10}) rotate(-38)" text-anchor="end" class="osr-chart-label">${escapeXml(clip(label, bottom * 1.35))}</text>`);
        } else {
            parts.push(`<text x="${cx.toFixed(1)}" y="${top + plotH + 16}" text-anchor="middle" class="osr-chart-label">${escapeXml(clip(label, slot - 4))}</text>`);
        }
    });
    const barSeries = mode === 'line' ? [] : mode === 'combo' ? src.series.slice(0, 1) : src.series;
    const lineSeries = mode === 'line' ? src.series : mode === 'combo' ? src.series.slice(1) : [];
    const zeroY = y(Math.max(scale.min, 0));
    src.categories.forEach((label, i) => {
        const gx = left + slot * i;
        const pad = Math.min(14, slot * 0.18);
        if (stacked) {
            let acc = 0;
            const bw = Math.max(3, Math.min(64, slot - pad * 2));
            const bx = gx + (slot - bw) / 2;
            barSeries.forEach((series, si) => {
                const v = Math.max(0, series.values[i] || 0);
                if (!v) return;
                const y1 = y(acc + v);
                const y0 = y(acc);
                acc += v;
                parts.push(`<rect class="osr-chart-mark" x="${bx.toFixed(1)}" y="${y1.toFixed(1)}" width="${bw.toFixed(1)}" height="${Math.max(1, y0 - y1).toFixed(1)}" fill="${color(si)}" ${tipAttr([label, `${series.name}: ${series.displays[i] || series.values[i]}`])}/>`);
            });
            if (showValues && !pct && shortNumber(acc).length * 5.6 <= slot - 2) {
                parts.push(`<text x="${(bx + bw / 2).toFixed(1)}" y="${(y(acc) - 5).toFixed(1)}" text-anchor="middle" class="osr-chart-value">${escapeXml(shortNumber(acc))}</text>`);
            }
            return;
        }
        if (!barSeries.length) return;
        const count = barSeries.length;
        const inner = Math.max(3, slot - pad * 2);
        const bw = Math.max(3, Math.min(count === 1 ? 72 : 36, inner / count - (count > 1 ? 2 : 0)));
        const total = bw * count + (count - 1) * 2;
        let bx = gx + (slot - total) / 2;
        barSeries.forEach((series, si) => {
            const v = series.values[i] || 0;
            const yv = y(v);
            const ry = Math.min(yv, zeroY);
            const hh = Math.max(1, Math.abs(zeroY - yv));
            parts.push(`<rect class="osr-chart-mark" x="${bx.toFixed(1)}" y="${ry.toFixed(1)}" width="${bw.toFixed(1)}" height="${hh.toFixed(1)}" rx="2" fill="${color(si)}" ${tipAttr([label, `${series.name}: ${series.displays[i] || series.values[i]}`])}/>`);
            const valueText = series.displays[i] || shortNumber(v);
            const room = count === 1 ? slot - 2 : bw + 2;
            if (showValues && String(valueText).length * 5.6 <= room) {
                parts.push(`<text x="${(bx + bw / 2).toFixed(1)}" y="${(ry - 5).toFixed(1)}" text-anchor="middle" class="osr-chart-value">${escapeXml(valueText)}</text>`);
            }
            bx += bw + 2;
        });
    });
    lineSeries.forEach((series, li) => {
        const si = mode === 'combo' ? li + 1 : li;
        const pts = src.categories.map((_, i) => ({
            x: left + slot * i + slot / 2,
            y: y(series.values[i] || 0)
        }));
        if (mode === 'line' && src.series.length === 1 && pts.length > 1) {
            const area = `M ${pts[0].x.toFixed(1)} ${zeroY.toFixed(1)} ${pts.map((p) => `L ${p.x.toFixed(1)} ${p.y.toFixed(1)}`).join(' ')} L ${pts[pts.length - 1].x.toFixed(1)} ${zeroY.toFixed(1)} Z`;
            parts.push(`<path d="${area}" fill="${color(si)}" opacity="0.14"/>`);
        }
        parts.push(`<polyline points="${pts.map((p) => `${p.x.toFixed(1)},${p.y.toFixed(1)}`).join(' ')}" fill="none" stroke="${color(si)}" stroke-width="2.5" stroke-linejoin="round" stroke-linecap="round"/>`);
        pts.forEach((p, i) => {
            parts.push(`<circle class="osr-chart-mark" cx="${p.x.toFixed(1)}" cy="${p.y.toFixed(1)}" r="4" fill="#fff" stroke="${color(si)}" stroke-width="2" ${tipAttr([src.categories[i], `${series.name}: ${series.displays[i] || series.values[i]}`])}/>`);
            if (showValues && lineSeries.length === 1 && n <= 16) {
                parts.push(`<text x="${p.x.toFixed(1)}" y="${(p.y - 9).toFixed(1)}" text-anchor="middle" class="osr-chart-value">${escapeXml(series.displays[i] || shortNumber(series.values[i]))}</text>`);
            }
        });
    });
    return `${svgOpen(w, h)}${parts.join('')}</svg>`;
}

/* ---------- Horizontal bars ---------- */

function horizontal(data, opts) {
    const { w, mode, showValues } = opts;
    const stacked = mode === 'stacked' || mode === 'stack100';
    const pct = mode === 'stack100';
    const src = pct ? toPercent(data) : data;
    const count = stacked ? 1 : src.series.length;
    const n = src.categories.length;
    const rowH = Math.max(22, Math.min(40, count > 1 ? 10 * count + 12 : 30));
    const labelW = Math.min(Math.max(70, w * 0.3), 9 + 6.4 * Math.max(...src.categories.map((c) => String(c).length)));
    const left = Math.min(labelW, w * 0.38);
    const right = showValues ? 48 : 14;
    const top = 6;
    const bottom = 22;
    const h = Math.max(opts.h || 0, top + n * rowH + bottom);
    const rowSlot = (h - top - bottom) / Math.max(1, n);
    const values = stacked ? stackTotals(src) : src.series.flatMap((s) => s.values);
    const scale = scaleFor(values, { pct, ticks: Math.max(2, Math.floor((w - left - right) / 90)) });
    const plotW = w - left - right;
    const x = (v) => left + ((v - scale.min) / (scale.max - scale.min || 1)) * plotW;
    const parts = [];
    scale.ticks.forEach((t) => {
        const tx = x(t);
        parts.push(`<line x1="${tx.toFixed(1)}" x2="${tx.toFixed(1)}" y1="${top}" y2="${h - bottom}" class="osr-chart-grid${t === 0 ? ' is-zero' : ''}"/>`);
        parts.push(`<text x="${tx.toFixed(1)}" y="${h - 6}" text-anchor="middle" class="osr-chart-tick">${escapeXml(pct ? `${t}%` : shortNumber(t))}</text>`);
    });
    const zeroX = x(Math.max(scale.min, 0));
    src.categories.forEach((label, i) => {
        const y0 = top + rowSlot * i;
        parts.push(`<text x="${left - 8}" y="${(y0 + rowSlot / 2).toFixed(1)}" text-anchor="end" dominant-baseline="middle" class="osr-chart-label">${escapeXml(clip(label, left - 12))}</text>`);
        const pad = Math.max(3, rowSlot * 0.16);
        if (stacked) {
            let acc = 0;
            src.series.forEach((series, si) => {
                const v = Math.max(0, series.values[i] || 0);
                if (!v) return;
                const x0 = x(acc);
                acc += v;
                parts.push(`<rect class="osr-chart-mark" x="${x0.toFixed(1)}" y="${(y0 + pad).toFixed(1)}" width="${Math.max(1, x(acc) - x0).toFixed(1)}" height="${(rowSlot - pad * 2).toFixed(1)}" fill="${color(si)}" ${tipAttr([label, `${series.name}: ${series.displays[i] || series.values[i]}`])}/>`);
            });
            if (showValues && !pct) {
                parts.push(`<text x="${(x(acc) + 6).toFixed(1)}" y="${(y0 + rowSlot / 2).toFixed(1)}" dominant-baseline="middle" class="osr-chart-value">${escapeXml(shortNumber(acc))}</text>`);
            }
            return;
        }
        const bh = Math.max(3, (rowSlot - pad * 2 - (count - 1) * 2) / count);
        src.series.forEach((series, si) => {
            const v = series.values[i] || 0;
            const xv = x(v);
            const bx = Math.min(xv, zeroX);
            const by = y0 + pad + si * (bh + 2);
            parts.push(`<rect class="osr-chart-mark" x="${bx.toFixed(1)}" y="${by.toFixed(1)}" width="${Math.max(1, Math.abs(xv - zeroX)).toFixed(1)}" height="${bh.toFixed(1)}" rx="2" fill="${color(si)}" ${tipAttr([label, `${series.name}: ${series.displays[i] || series.values[i]}`])}/>`);
            if (showValues && (count === 1 || bh >= 10)) {
                parts.push(`<text x="${(Math.max(xv, zeroX) + 5).toFixed(1)}" y="${(by + bh / 2).toFixed(1)}" dominant-baseline="middle" class="osr-chart-value">${escapeXml(series.displays[i] || shortNumber(v))}</text>`);
            }
        });
    });
    return `${svgOpen(w, h)}${parts.join('')}</svg>`;
}

/* ---------- Pie / donut ---------- */

function polar(cx, cy, r, deg) {
    const rad = (deg * Math.PI) / 180;
    return [cx + r * Math.cos(rad), cy + r * Math.sin(rad)];
}

function arcPath(cx, cy, r, inner, start, end) {
    const large = end - start > 180 ? 1 : 0;
    const [x1, y1] = polar(cx, cy, r, start);
    const [x2, y2] = polar(cx, cy, r, end);
    if (!inner) return `M ${cx} ${cy} L ${x1} ${y1} A ${r} ${r} 0 ${large} 1 ${x2} ${y2} Z`;
    const [x3, y3] = polar(cx, cy, inner, end);
    const [x4, y4] = polar(cx, cy, inner, start);
    return `M ${x1} ${y1} A ${r} ${r} 0 ${large} 1 ${x2} ${y2} L ${x3} ${y3} A ${inner} ${inner} 0 ${large} 0 ${x4} ${y4} Z`;
}

function pieHtml(data, opts) {
    const { w, h, donut } = opts;
    const series = data.series[0];
    const slices = data.categories
        .map((label, i) => ({ label, value: Math.abs(series.values[i] || 0), display: series.displays[i], i }))
        .filter((slice) => slice.value > 0);
    const total = slices.reduce((sum, slice) => sum + slice.value, 0) || 1;
    const side = w >= 420;
    const size = Math.max(120, Math.min(side ? w * 0.45 : w, h - (side ? 8 : 70), 260));
    const cx = size / 2;
    const cy = size / 2;
    const r = size / 2 - 4;
    const inner = donut ? r * 0.6 : 0;
    let angle = -90;
    const parts = [];
    slices.forEach((slice) => {
        const sweep = (slice.value / total) * 360;
        const end = angle + Math.min(sweep, 359.99);
        const pctText = `${Math.round((slice.value / total) * 1000) / 10}%`;
        parts.push(`<path class="osr-chart-mark" d="${arcPath(cx, cy, r, inner, angle, end)}" fill="${color(slice.i)}" stroke="#fff" stroke-width="1.5" ${tipAttr([slice.label, `${slice.display || slice.value} (${pctText})`])}/>`);
        if (sweep > 22) {
            const [lx, ly] = polar(cx, cy, donut ? (r + inner) / 2 : r * 0.64, angle + sweep / 2);
            parts.push(`<text x="${lx.toFixed(1)}" y="${ly.toFixed(1)}" text-anchor="middle" dominant-baseline="middle" class="osr-chart-slice">${escapeXml(pctText)}</text>`);
        }
        angle += sweep;
    });
    if (donut) {
        const totalLabel = shortNumber(slices.reduce((sum, s) => sum + s.value, 0));
        parts.push(`<text x="${cx}" y="${cy - 6}" text-anchor="middle" class="osr-chart-donut-total">${escapeXml(totalLabel)}</text>`);
        parts.push(`<text x="${cx}" y="${cy + 14}" text-anchor="middle" class="osr-chart-tick">Total</text>`);
    }
    const legend = slices
        .map(
            (slice) =>
                `<li ${tipAttr([slice.label, slice.display || slice.value])}><span class="osr-chart-swatch" style="background:${color(slice.i)}"></span><span class="osr-chart-legend-label">${escapeXml(slice.label)}</span><b>${escapeXml(slice.display || slice.value)}</b></li>`
        )
        .join('');
    return `<div class="osr-chart-pie${side ? ' is-side' : ''}">${svgOpen(size, size, ' osr-chart-svg--pie')}${parts.join('')}</svg><ul class="osr-chart-legend osr-chart-legend--list">${legend}</ul></div>`;
}

/* ---------- Funnel / scatter ---------- */

function funnelSvg(data, opts) {
    const { w } = opts;
    const rows = data.categories.map((label, i) => {
        const value = Math.abs(data.series.reduce((sum, series) => sum + (series.values[i] || 0), 0));
        return {
            label,
            value,
            display: data.series.length === 1 ? data.series[0].displays[i] : shortNumber(value)
        };
    });
    const max = Math.max(1, ...rows.map((row) => row.value));
    const rowH = Math.max(26, Math.min(44, ((opts.h || 240) - 8) / Math.max(1, rows.length)));
    const h = rows.length * rowH + 4;
    const minW = w * 0.18;
    const parts = [];
    rows.forEach((row, i) => {
        const next = rows[i + 1] || row;
        const y = 2 + i * rowH;
        const w1 = minW + (row.value / max) * (w - minW - 8);
        const w2 = minW + (next.value / max) * (w - minW - 8);
        const x1 = (w - w1) / 2;
        const x2 = (w - w2) / 2;
        parts.push(`<polygon class="osr-chart-mark" points="${x1.toFixed(1)},${y} ${(x1 + w1).toFixed(1)},${y} ${(x2 + w2).toFixed(1)},${y + rowH - 3} ${x2.toFixed(1)},${y + rowH - 3}" fill="${color(i)}" ${tipAttr([row.label, row.display])}/>`);
        parts.push(`<text x="${w / 2}" y="${(y + rowH / 2).toFixed(1)}" text-anchor="middle" dominant-baseline="middle" class="osr-chart-funnel-label">${escapeXml(clip(`${row.label} \u00b7 ${row.display}`, Math.max(80, w2)))}</text>`);
    });
    return `${svgOpen(w, h)}${parts.join('')}</svg>`;
}

function scatterSvg(data, opts) {
    const { w, h } = opts;
    const values = data.series.flatMap((s) => s.values);
    const scale = scaleFor(values);
    const left = 40;
    const right = 12;
    const top = 10;
    const bottom = 26;
    const plotW = w - left - right;
    const plotH = h - top - bottom;
    const n = data.categories.length;
    const y = (v) => top + plotH - ((v - scale.min) / (scale.max - scale.min || 1)) * plotH;
    const x = (i) => left + (n === 1 ? plotW / 2 : (i / (n - 1)) * plotW);
    const parts = [];
    scale.ticks.forEach((t) => {
        parts.push(`<line x1="${left}" x2="${w - right}" y1="${y(t).toFixed(1)}" y2="${y(t).toFixed(1)}" class="osr-chart-grid"/>`);
        parts.push(`<text x="${left - 6}" y="${y(t).toFixed(1)}" text-anchor="end" dominant-baseline="middle" class="osr-chart-tick">${escapeXml(shortNumber(t))}</text>`);
    });
    const every = Math.max(1, Math.ceil(n / Math.max(1, plotW / 70)));
    data.categories.forEach((label, i) => {
        if (i % every === 0) {
            parts.push(`<text x="${x(i).toFixed(1)}" y="${h - 8}" text-anchor="middle" class="osr-chart-label">${escapeXml(clip(label, 70))}</text>`);
        }
        data.series.forEach((series, si) => {
            parts.push(`<circle class="osr-chart-mark" cx="${x(i).toFixed(1)}" cy="${y(series.values[i] || 0).toFixed(1)}" r="5.5" fill="${color(si)}" fill-opacity="0.85" stroke="#fff" ${tipAttr([label, `${series.name}: ${series.displays[i] || series.values[i]}`])}/>`);
        });
    });
    return `${svgOpen(w, h)}${parts.join('')}</svg>`;
}

/* ---------- Metric / gauge ---------- */

function breakColor(value, breakPoints, min, max) {
    const bp = Array.isArray(breakPoints) && breakPoints[0];
    const breaks = (bp && bp.breaks) || [];
    if (!breaks.length) return null;
    for (const item of breaks) {
        const lo = item.lowerBound == null ? -Infinity : Number(item.lowerBound);
        const hi = item.upperBound == null ? Infinity : Number(item.upperBound);
        if (value >= lo && value < hi && (item.lowerBound != null || item.upperBound != null)) {
            return `#${String(item.color || '').replace('#', '')}`;
        }
    }
    return null;
}

export function metricHtml(metric, options = {}) {
    const tone = breakColor(Number(metric.numeric) || 0, options.breakPoints) || '';
    const label = options.label ? `<span class="osr-metric-label">${escapeXml(options.label)}</span>` : '';
    return `<div class="osr-metric-tile"${tone ? ` style="--metric-tone:${tone}"` : ''}><p class="osr-metric${tone ? ' has-tone' : ''}">${escapeXml(metric.value)}</p>${label}</div>`;
}

export function gaugeHtml(metric, options = {}) {
    const min = Number.isFinite(Number(options.min)) ? Number(options.min) : 0;
    const rawMax = Number(options.max);
    const value = Number(metric.numeric) || 0;
    const max = Number.isFinite(rawMax) && rawMax > min ? rawMax : Math.max(100, Math.ceil(value * 1.2) || 1);
    const pct = Math.max(0, Math.min(1, (value - min) / (max - min || 1)));
    const cx = 120;
    const cy = 112;
    const r = 92;
    const width = 20;
    const arc = (a, b, stroke) => {
        const [x1, y1] = polar(cx, cy, r, 180 + a * 180);
        const [x2, y2] = polar(cx, cy, r, 180 + b * 180);
        return `<path d="M ${x1.toFixed(1)} ${y1.toFixed(1)} A ${r} ${r} 0 0 1 ${x2.toFixed(1)} ${y2.toFixed(1)}" fill="none" stroke="${stroke}" stroke-width="${width}"/>`;
    };
    const bp = Array.isArray(options.breakPoints) && options.breakPoints[0];
    const breaks = ((bp && bp.breaks) || []).filter((b) => b.lowerBound != null || b.upperBound != null);
    const bands = [];
    if (breaks.length) {
        breaks.forEach((item) => {
            const lo = item.lowerBound == null ? min : Number(item.lowerBound);
            const hi = item.upperBound == null ? max : Number(item.upperBound);
            const a = Math.max(0, Math.min(1, (lo - min) / (max - min || 1)));
            const b = Math.max(0, Math.min(1, (hi - min) / (max - min || 1)));
            if (b > a) bands.push(arc(a, b, `#${String(item.color || 'c9c9c9').replace('#', '')}`));
        });
    } else {
        bands.push(arc(0, 1, '#e5eaf0'));
        if (pct > 0) bands.push(arc(0, pct, PALETTE[0]));
    }
    const [nx, ny] = polar(cx, cy, r - 6, 180 + pct * 180);
    return `<div class="osr-chart osr-chart--gauge">
        ${svgOpen(240, 150, ' osr-chart-svg--gauge')}
            ${bands.join('')}
            <line x1="${cx}" y1="${cy}" x2="${nx.toFixed(1)}" y2="${ny.toFixed(1)}" stroke="#032d60" stroke-width="3" stroke-linecap="round"/>
            <circle cx="${cx}" cy="${cy}" r="6" fill="#032d60"/>
            <text x="${cx - r}" y="${cy + 22}" text-anchor="middle" class="osr-chart-tick">${escapeXml(shortNumber(min))}</text>
            <text x="${cx + r}" y="${cy + 22}" text-anchor="middle" class="osr-chart-tick">${escapeXml(shortNumber(max))}</text>
            <text x="${cx}" y="${cy + 30}" text-anchor="middle" class="osr-chart-gauge-value">${escapeXml(metric.value)}</text>
        </svg>
    </div>`;
}

/* ---------- Public ---------- */

function legendHtml(series) {
    if (!series || series.length < 2) return '';
    return `<ul class="osr-chart-legend">${series
        .map(
            (item, i) =>
                `<li><span class="osr-chart-swatch" style="background:${color(i)}"></span>${escapeXml(item.name)}</li>`
        )
        .join('')}</ul>`;
}

function renderKind(kind, data, opts) {
    const multi = data.series.length > 1;
    switch (kind) {
        case 'hbar-stack100':
            return horizontal(data, { ...opts, mode: 'stack100' });
        case 'vbar-stack100':
            return cartesian(data, { ...opts, mode: 'stack100' });
        case 'hbar-stacked':
            return horizontal(data, { ...opts, mode: 'stacked' });
        case 'vbar-stacked':
            return cartesian(data, { ...opts, mode: 'stacked' });
        case 'hbar':
        case 'hbar-grouped':
            return horizontal(data, { ...opts, mode: 'grouped' });
        case 'combo':
            return cartesian(data, { ...opts, mode: multi ? 'combo' : 'grouped' });
        case 'line':
            return cartesian(data, { ...opts, mode: 'line' });
        case 'funnel':
            return funnelSvg(data, opts);
        case 'scatter':
            return scatterSvg(data, opts);
        default:
            return cartesian(data, { ...opts, mode: 'grouped' });
    }
}

export function chartHtml(report, typeHint, options = {}) {
    const kind = normalizeChartKind(typeHint) || resolveChartKind(null, report) || 'vbar';
    if (kind === 'metric') {
        return metricHtml(extractMetric(report), options);
    }
    if (kind === 'gauge') {
        return gaugeHtml(extractMetric(report), options);
    }
    if (kind === 'table' || kind === 'unsupported') return '';
    const groupDefs = ((report && report.reportMetadata && report.reportMetadata.groupingsDown) || []).length;
    const groupRows = ((report && report.groupingsDown && report.groupingsDown.groupings) || []).length;
    if (groupDefs && !groupRows) {
        return '<p class="osr-chart-empty">No records match this report\u2019s filters.</p>';
    }
    const data = trimData(extractChartData(report, options.aggIndexes));
    if (!data.categories.length || !data.series.length) {
        return '<p class="osr-chart-empty">No chart data for this result.</p>';
    }
    const opts = {
        w: Math.max(200, Math.round(options.width || 560)),
        h: Math.max(140, Math.round(options.height || 280)),
        showValues: options.showValues !== false
    };
    const resolved = kind === 'chart' ? 'vbar' : kind;
    const note = data.truncated
        ? `<p class="osr-chart-note">Showing the first ${MAX_CATEGORIES} groups.</p>`
        : '';
    if (resolved === 'pie' || resolved === 'donut') {
        return `<div class="osr-chart">${pieHtml(data, { ...opts, donut: resolved === 'donut' })}${note}</div>`;
    }
    const legend = options.legend === false ? '' : legendHtml(data.series);
    const legendH = legend ? 26 : 0;
    const svg = renderKind(resolved, data, { ...opts, h: opts.h - legendH });
    return `<div class="osr-chart">${legend}${svg}${note}</div>`;
}

export function gaugeOptionsFrom(component) {
    const props = (component && (component.properties || component.attributes)) || {};
    const vis = props.visualizationProperties || {};
    const num = (...vals) => {
        for (const value of vals) {
            if (value === null || value === undefined || value === '') continue;
            const n = Number(value);
            if (Number.isFinite(n)) return n;
        }
        return undefined;
    };
    const bp = Array.isArray(vis.breakPoints) ? vis.breakPoints : [];
    const bounds = bp.flatMap((item) => (item.breaks || []).flatMap((b) => [b.lowerBound, b.upperBound]));
    const numeric = bounds.map(Number).filter((n) => Number.isFinite(n));
    return {
        min: num(props.min, props.gaugeMin, component && component.gaugeMin, numeric.length ? Math.min(...numeric) : undefined) ?? 0,
        max: num(props.max, props.gaugeMax, component && component.gaugeMax, numeric.length ? Math.max(...numeric) : undefined),
        breakPoints: bp,
        showValues: vis.showValues !== false,
        label: vis.metricLabel || null
    };
}

let tooltipInstalled = false;

export function installChartTooltips() {
    if (tooltipInstalled || typeof document === 'undefined') return;
    tooltipInstalled = true;
    const tip = document.createElement('div');
    tip.className = 'osr-chart-tooltip';
    tip.hidden = true;
    document.body.appendChild(tip);
    const place = (event) => {
        const pad = 14;
        const rect = tip.getBoundingClientRect();
        let x = event.clientX + pad;
        let y = event.clientY + pad;
        if (x + rect.width > window.innerWidth - 8) x = event.clientX - rect.width - pad;
        if (y + rect.height > window.innerHeight - 8) y = event.clientY - rect.height - pad;
        tip.style.transform = `translate(${Math.max(4, x)}px, ${Math.max(4, y)}px)`;
    };
    document.addEventListener('pointerover', (event) => {
        const target = event.target && event.target.closest && event.target.closest('[data-tip]');
        if (!target) return;
        const lines = String(target.getAttribute('data-tip') || '').split('\n');
        tip.innerHTML = lines
            .map((line, i) => (i === 0 ? `<strong>${escapeXml(line)}</strong>` : `<span>${escapeXml(line)}</span>`))
            .join('');
        tip.hidden = false;
        place(event);
    });
    document.addEventListener('pointermove', (event) => {
        if (tip.hidden) return;
        if (!(event.target && event.target.closest && event.target.closest('[data-tip]'))) {
            tip.hidden = true;
            return;
        }
        place(event);
    });
    document.addEventListener('pointerout', (event) => {
        const to = event.relatedTarget;
        if (!(to && to.closest && to.closest('[data-tip]'))) tip.hidden = true;
    });
    window.addEventListener('scroll', () => {
        tip.hidden = true;
    }, true);
}
