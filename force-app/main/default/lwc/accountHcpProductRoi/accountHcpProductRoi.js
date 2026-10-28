import { LightningElement, api, wire } from 'lwc';
import { refreshApex } from '@salesforce/apex';
import getAccountRoi from '@salesforce/apex/HcpProductRoiController.getAccountRoi';

const MONTH_LABELS = ['JAN', 'FEB', 'MAR', 'APR', 'MAY', 'JUN', 'JUL', 'AUG', 'SEP', 'OCT', 'NOV', 'DEC'];
const LANE_META = [
    { key: 'Speaker Meeting', label: 'Speaker / RTD', tone: 'speaker' },
    { key: 'Samples', label: 'Samples', tone: 'samples' },
    { key: 'Brochures', label: 'Brochures', tone: 'brochures' },
    { key: 'Visits', label: 'Visits', tone: 'visits' },
    { key: 'Meetings', label: 'Meetings (past & planned)', tone: 'meetings' }
];

const SALES_COLOR = '#0176d3';
const RATING_COLOR = '#2e844a';
const CLASS_LADDER = ['C3', 'C2', 'C1', 'B3', 'B2', 'B1', 'A3', 'A2', 'A1'];
const CLASS_SCORE = {
    C3: 1,
    C2: 2,
    C1: 3,
    B3: 4,
    B2: 5,
    B1: 6,
    A3: 7,
    A2: 8,
    A1: 9,
    C: 2,
    B: 5,
    A: 8
};
const CLASS_MIN = 1;
const CLASS_MAX = 9;
const CLASS_DOMAIN = { min: CLASS_MIN, max: CLASS_MAX, has: true, span: CLASS_MAX - CLASS_MIN };

const DISPLAY_CURRENCY = 'EGP';

function resolveCurrency(_code) {
    return DISPLAY_CURRENCY;
}

function moneyPrefix(_currency) {
    return `${DISPLAY_CURRENCY} `;
}

function money(value, currency) {
    const n = value == null || value === '' ? 0 : Number(value);
    const code = resolveCurrency(currency);
    try {
        return new Intl.NumberFormat('en-US', {
            style: 'currency',
            currency: code,
            maximumFractionDigits: 0
        }).format(Number.isNaN(n) ? 0 : n);
    } catch (e) {
        return `${moneyPrefix(code)}${Math.round(Number.isNaN(n) ? 0 : n).toLocaleString('en-US')}`;
    }
}

function compactMoney(value, currency) {
    const n = Number(value) || 0;
    const abs = Math.abs(n);
    const sign = n < 0 ? '-' : '';
    const prefix = moneyPrefix(currency);
    if (abs >= 1000000) {
        const compact = abs / 1000000;
        return `${sign}${prefix}${Number(compact.toFixed(compact >= 10 ? 0 : 1))}M`;
    }
    if (abs >= 1000) {
        const compact = abs / 1000;
        return `${sign}${prefix}${Number(compact.toFixed(compact >= 10 ? 0 : 1))}k`;
    }
    if (abs === 0 || abs >= 10 || Number.isInteger(n)) {
        return `${sign}${prefix}${Math.round(abs)}`;
    }
    return `${sign}${prefix}${Number(abs.toFixed(1))}`;
}

function toNumber(value) {
    if (value == null || value === '') {
        return null;
    }
    const n = Number(value);
    return Number.isNaN(n) ? null : n;
}

function normalizeClass(value) {
    if (!value) {
        return '';
    }
    const compact = String(value).trim().toUpperCase().replace(/[^A-C0-9]/g, '');
    if (/^[ABC][123]$/.test(compact) || /^[ABC]$/.test(compact)) {
        return compact;
    }
    return '';
}

function classLabelFromScore(score) {
    const rounded = Math.round(Number(score));
    return CLASS_LADDER[rounded - CLASS_MIN] || '';
}

function classScoreFromPoint(point) {
    const fromLabel = CLASS_SCORE[normalizeClass(point?.classification)];
    if (fromLabel != null) {
        return fromLabel;
    }
    const n = toNumber(point?.value);
    if (n == null) {
        return null;
    }
    return Math.min(CLASS_MAX, Math.max(CLASS_MIN, n));
}

function classLabelFromPoint(point) {
    return normalizeClass(point?.classification) || classLabelFromScore(point?.value) || '';
}

function niceCeil(max) {
    if (!(max > 0)) {
        return 0;
    }
    const exp = Math.floor(Math.log10(max));
    const pow = 10 ** exp;
    const frac = max / pow;
    const nice = frac <= 1 ? 1 : frac <= 2 ? 2 : frac <= 5 ? 5 : 10;
    return nice * pow;
}

function moneyDomain(values) {
    const present = values.filter((v) => v != null);
    const max = present.length ? Math.max(0, ...present) : 0;
    const niceMax = niceCeil(max);
    return {
        min: 0,
        max: niceMax,
        has: present.length > 0,
        span: niceMax || 1
    };
}

function scaleY(value, domain, padTop, plotH) {
    return padTop + plotH - ((value - domain.min) / domain.span) * plotH;
}

function buildSeriesGeometry(points, domain, padLeft, padTop, plotH, xStep, color, prefix, currency) {
    const dots = [];
    const pathParts = [];
    const coords = [];
    (points || []).forEach((point, index) => {
        const value = prefix === 'rating' ? classScoreFromPoint(point) : toNumber(point?.value);
        if (value == null) {
            coords.push(null);
            return;
        }
        const x = padLeft + index * xStep;
        const y = scaleY(value, domain, padTop, plotH);
        coords.push({ x, y, value, point });
        const classLabel = classLabelFromPoint(point);
        dots.push({
            key: `${prefix}-${point.monthKey || index}`,
            cx: x,
            cy: y,
            color,
            title:
                prefix === 'sales'
                    ? `${point.monthLabel || ''}: ${money(value, currency)}`
                    : `${point.monthLabel || ''}: ${classLabel || value}`
        });
        pathParts.push(`${pathParts.length ? 'L' : 'M'} ${x} ${y}`);
    });
    return {
        path: pathParts.join(' '),
        dots,
        coords,
        hasPath: pathParts.length > 0
    };
}

function buildGapPath(salesCoords, ratingCoords) {
    const pairs = [];
    const count = Math.max(salesCoords.length, ratingCoords.length);
    for (let i = 0; i < count; i += 1) {
        const sales = salesCoords[i];
        const rating = ratingCoords[i];
        if (sales && rating) {
            pairs.push({ sales, rating });
        }
    }
    if (pairs.length < 2) {
        return '';
    }
    const top = pairs.map((p) => `${p.sales.x} ${p.sales.y}`);
    const bottom = pairs
        .slice()
        .reverse()
        .map((p) => `${p.rating.x} ${p.rating.y}`);
    return `M ${top.join(' L ')} L ${bottom.join(' L ')} Z`;
}

function alignTrendMonths(salesTrend, ratingTrend) {
    const byKey = new Map();
    const order = [];
    function ingest(points, bucket) {
        (points || []).forEach((point) => {
            const key = point?.monthKey || point?.monthLabel;
            if (!key) {
                return;
            }
            if (!byKey.has(key)) {
                byKey.set(key, { monthKey: key, monthLabel: point.monthLabel || key });
                order.push(key);
            }
            const row = byKey.get(key);
            row.monthLabel = point.monthLabel || row.monthLabel;
            row[bucket] = point;
        });
    }
    ingest(salesTrend, 'sales');
    ingest(ratingTrend, 'rating');
    return order.map((key) => {
        const row = byKey.get(key);
        return {
            monthKey: row.monthKey,
            monthLabel: row.monthLabel,
            sales: row.sales || { monthKey: key, monthLabel: row.monthLabel, value: null },
            rating: row.rating || { monthKey: key, monthLabel: row.monthLabel, value: null }
        };
    });
}

function buildCombinedChart(salesTrend, ratingTrend, currency) {
    const width = 720;
    const height = 280;
    const padLeft = 78;
    const padRight = 40;
    const padTop = 14;
    const padBottom = 32;
    const plotW = width - padLeft - padRight;
    const plotH = height - padTop - padBottom;
    const months = alignTrendMonths(salesTrend, ratingTrend);
    const salesPoints = months.map((m) => m.sales);
    const ratingPoints = months.map((m) => m.rating);
    const salesValues = salesPoints.map((p) => toNumber(p.value));
    const salesScale = moneyDomain(salesValues);
    const ratingHasData = ratingPoints.some((p) => classScoreFromPoint(p) != null);
    const count = Math.max(months.length, 1);
    const xStep = count > 1 ? plotW / (count - 1) : 0;

    const salesGeo = buildSeriesGeometry(
        salesPoints,
        salesScale,
        padLeft,
        padTop,
        plotH,
        xStep,
        SALES_COLOR,
        'sales',
        currency
    );
    const ratingGeo = buildSeriesGeometry(
        ratingPoints,
        CLASS_DOMAIN,
        padLeft,
        padTop,
        plotH,
        xStep,
        RATING_COLOR,
        'rating',
        currency
    );

    const labels = months
        .map((month, index) => ({
            key: `lbl-${month.monthKey}`,
            x: padLeft + index * xStep,
            y: height - 10,
            label: month.monthLabel
        }))
        .filter((_, idx, arr) => idx % 2 === 0 || idx === arr.length - 1);

    let previousMoneyLabel = '';
    const yTicks = CLASS_LADDER.map((classLabel) => {
        const score = CLASS_SCORE[classLabel];
        const pct = (score - CLASS_MIN) / CLASS_DOMAIN.span;
        const y = padTop + plotH - pct * plotH;
        const salesValue = salesScale.max * pct;
        const moneyLabel = compactMoney(salesValue, currency);
        const showMoney = salesScale.has && moneyLabel !== previousMoneyLabel;
        if (showMoney) {
            previousMoneyLabel = moneyLabel;
        }
        return {
            key: `yt-${classLabel}`,
            lineKey: `yt-line-${classLabel}`,
            leftKey: `yt-left-${classLabel}`,
            rightKey: `yt-right-${classLabel}`,
            y,
            x1: padLeft,
            x2: padLeft + plotW,
            leftX: padLeft - 6,
            rightX: padLeft + plotW + 6,
            leftLabel: showMoney ? moneyLabel : '',
            rightLabel: ratingHasData ? classLabel : '',
            leftClass: 'axis-label axis-tick sellout',
            rightClass: 'axis-label axis-tick classification'
        };
    });

    return {
        hasData: salesGeo.hasPath || ratingGeo.hasPath,
        viewBox: `0 0 ${width} ${height}`,
        gapPath: buildGapPath(salesGeo.coords, ratingGeo.coords),
        salesPath: salesGeo.path,
        ratingPath: ratingGeo.path,
        salesDots: salesGeo.dots,
        ratingDots: ratingGeo.dots,
        labels,
        yTicks,
        salesColor: SALES_COLOR,
        ratingColor: RATING_COLOR,
        scaleNote: `${resolveCurrency(currency)} sell-out and classification share the same height — 0 / C3 at the bottom, peak sell-out / A1 at the top.`
    };
}

function firstAndLast(values) {
    const present = values.filter((v) => v != null);
    if (!present.length) {
        return { first: null, last: null, count: 0 };
    }
    return { first: present[0], last: present[present.length - 1], count: present.length };
}

function directionOf(first, last, flatRatio) {
    if (first == null || last == null) {
        return 0;
    }
    const delta = last - first;
    const basis = Math.max(Math.abs(first), 1);
    if (Math.abs(delta) <= Math.max(basis * flatRatio, 0.01)) {
        return 0;
    }
    return delta > 0 ? 1 : -1;
}

function isMostlyZero(values) {
    const present = values.filter((v) => v != null);
    if (!present.length) {
        return true;
    }
    const total = present.reduce((sum, value) => sum + value, 0);
    return total === 0;
}

function hasPurchasingSpike(values) {
    const present = values.filter((v) => v != null);
    if (present.length < 4) {
        return false;
    }
    const sorted = [...present].sort((a, b) => a - b);
    const median = sorted[Math.floor(sorted.length / 2)];
    const max = Math.max(...present);
    const total = present.reduce((sum, value) => sum + value, 0);
    if (total > 0 && max / total >= 0.55) {
        return true;
    }
    if (median <= 0) {
        return max > 0 && present.filter((v) => v === 0).length >= present.length * 0.6;
    }
    return max > median * 3;
}

function coefficientOfVariation(values) {
    const xs = values.filter((v) => v != null && v > 0);
    if (xs.length < 3) {
        return 0;
    }
    const mean = xs.reduce((sum, value) => sum + value, 0) / xs.length;
    if (!mean) {
        return 0;
    }
    const variance = xs.reduce((sum, value) => sum + (value - mean) ** 2, 0) / xs.length;
    return Math.sqrt(variance) / mean;
}

function lastClassification(ratingTrend) {
    const points = (ratingTrend || []).filter((p) => classScoreFromPoint(p) != null);
    if (!points.length) {
        return { label: null, score: null };
    }
    const last = points[points.length - 1];
    return {
        label: classLabelFromPoint(last) || null,
        score: classScoreFromPoint(last)
    };
}

function firstAndLastClass(ratingTrend) {
    const labels = (ratingTrend || []).map((p) => classLabelFromPoint(p)).filter(Boolean);
    if (!labels.length) {
        return { first: null, last: null, count: 0 };
    }
    return { first: labels[0], last: labels[labels.length - 1], count: labels.length };
}

function analyzeDivergence(payload, currency) {
    const salesValues = (payload?.salesTrend || []).map((p) => toNumber(p.value));
    const ratingValues = (payload?.ratingTrend || []).map((p) => classScoreFromPoint(p));
    const salesEnds = firstAndLast(salesValues);
    const ratingEnds = firstAndLast(ratingValues);
    const classEnds = firstAndLastClass(payload?.ratingTrend);
    const salesDir = directionOf(salesEnds.first, salesEnds.last, 0.08);
    const ratingDir = directionOf(ratingEnds.first, ratingEnds.last, 0.12);
    const salesMissing = isMostlyZero(salesValues);
    const selected =
        (payload?.productRanks || []).find((row) => row.productId === payload?.selectedProductId) ||
        (payload?.productRanks || []).find((row) => row.isSelected) ||
        {};
    const gapPercent = toNumber(selected.gapPercent) || 0;
    const classInfo = lastClassification(payload?.ratingTrend);
    const zeroMoney = money(0, currency);
    const reasons = [];

    if (salesMissing && ratingEnds.count > 0) {
        reasons.push({
            key: 'missing-sales',
            title: 'Missing sales data',
            detail: `Rep classification is moving, but affiliated pharmacy sell-out is flat at ${zeroMoney}. Withdrawals may not be loaded for this product, this account may lack pharmacy affiliations, or sell-out is being reported under a different product/pharmacy.`,
            tone: 'warning'
        });
    } else if (!salesMissing && ratingDir > 0 && salesDir <= 0) {
        reasons.push({
            key: 'class-ahead',
            title: 'Classification is not confirmed by sell-out',
            detail: `Classification ${
                classInfo.label ? `(${classInfo.label}) ` : ''
            }is rising while pharmacy sell-out is ${
                salesDir < 0 ? 'falling' : 'flat'
            }. The rating may be ahead of true demand, or sell-out is landing outside affiliated pharmacies.`,
            tone: 'warning'
        });
    } else if (!salesMissing && salesDir > 0 && ratingDir <= 0 && ratingEnds.count > 0) {
        reasons.push({
            key: 'class-lag',
            title: 'Classification lag',
            detail:
                'Pharmacy sell-out is growing faster than the rep classification. The snapshot may be stale, or neighbouring-pharmacy purchases are inflating sell-out beyond this account’s written potential.',
            tone: 'info'
        });
    }

    if (gapPercent >= 15 && (classInfo.score == null || classInfo.score >= 5 || (classInfo.label || '').startsWith('A') || (classInfo.label || '').startsWith('B'))) {
        reasons.push({
            key: 'potential-penetration',
            title: 'Untruthful potential vs penetration',
            detail: `Written value is ${
                selected.writtenValue != null ? money(selected.writtenValue, currency) : 'below potential'
            } against ${
                selected.potentialValue != null ? money(selected.potentialValue, currency) : 'stated potential'
            } (${gapPercent}% gap)${
                classInfo.label ? `, while classification is ${classInfo.label}` : ''
            }. Potential may be overstated, or penetration is understated relative to how this account is classified.`,
            tone: 'error'
        });
    }

    if (!salesMissing && (hasPurchasingSpike(salesValues) || coefficientOfVariation(salesValues) >= 0.85)) {
        reasons.push({
            key: 'purchasing-anomaly',
            title: 'Purchasing anomalies',
            detail:
                'Sell-out is lumpy — a few months dominate, or month-to-month swings are extreme. That pattern often means stockpiling, delayed distributor reporting, tender/bulk buys, or one-off pharmacy purchases rather than steady HCP demand.',
            tone: 'warning'
        });
    } else if (salesMissing && ratingDir > 0) {
        reasons.push({
            key: 'purchasing-anomaly',
            title: 'Purchasing anomalies',
            detail:
                'Classification improved without any captured sell-out. Purchases may be happening at non-affiliated pharmacies, through another product SKU, or via distributor paths that are not in Pharmacy Sales Withdrawal.',
            tone: 'warning'
        });
    }

    if (!reasons.length && (salesEnds.count || ratingEnds.count)) {
        reasons.push({
            key: 'aligned',
            title: 'Trends are aligned',
            detail:
                'Sell-out and classification are moving in the same direction. No material reporting gap, potential mismatch, or purchasing anomaly stands out for the selected product.',
            tone: 'success'
        });
    }

    let headline = 'Sell-out vs classification';
    let summary = 'Compare affiliated pharmacy sell-out with how the rep classified this account.';
    if (salesMissing && ratingDir > 0) {
        headline = 'Classification rose, sell-out did not follow';
        summary = `Classification moved from ${classEnds.first || classInfo.label} to ${
            classEnds.last || classInfo.label
        }, while affiliated pharmacy sell-out stayed at ${zeroMoney}.`;
    } else if (!salesMissing && ratingDir > 0 && salesDir <= 0) {
        headline = 'Classification is ahead of sell-out';
        summary = `Sell-out went from ${compactMoney(salesEnds.first, currency)} to ${compactMoney(
            salesEnds.last,
            currency
        )}, while classification went from ${classEnds.first} to ${classEnds.last}.`;
    } else if (!salesMissing && salesDir > 0 && ratingDir <= 0 && ratingEnds.count) {
        headline = 'Sell-out is running ahead of classification';
        summary = `Sell-out grew from ${compactMoney(salesEnds.first, currency)} to ${compactMoney(
            salesEnds.last,
            currency
        )}, but classification stayed ${ratingDir < 0 ? 'lower' : 'flat'} (${classEnds.first} → ${
            classEnds.last
        }).`;
    } else if (reasons.some((r) => r.key === 'aligned')) {
        headline = 'Sell-out and classification are aligned';
        summary = 'The two series move together for the selected product over the last 12 months.';
    }

    return {
        hasHeadline: reasons.length > 0,
        headline,
        summary,
        bannerClass: `divergence-banner ${reasons[0]?.tone || 'info'}`,
        reasons: reasons.map((reason) => ({
            ...reason,
            itemClass: `reason-item ${reason.tone}`
        }))
    };
}

function dayOfYearPercent(dateValue, year) {
    if (!dateValue) {
        return 0;
    }
    const d = new Date(dateValue);
    const start = new Date(year, 0, 1);
    const end = new Date(year, 11, 31);
    const span = end.getTime() - start.getTime() || 1;
    const pct = ((d.getTime() - start.getTime()) / span) * 100;
    return Math.max(0, Math.min(100, pct));
}

export default class AccountHcpProductRoi extends LightningElement {
    @api recordId;

    // Must be null (not undefined) or the wire never provisions Apex.
    selectedProductIds = null;
    wiredResult;
    payload;
    errorMessage;
    isLoading = true;
    _selectionInitialized = false;

    @wire(getAccountRoi, { accountId: '$recordId', productIds: '$selectedProductIds' })
    wiredRoi(result) {
        this.wiredResult = result;
        if (!this.recordId) {
            this.isLoading = true;
            this.payload = null;
            this.errorMessage = null;
            return;
        }
        this.isLoading = false;
        if (result.error) {
            this.errorMessage =
                result.error.body?.message ||
                result.error.body?.pageErrors?.[0]?.message ||
                result.error.message ||
                'Unable to load APM.';
            this.payload = null;
            return;
        }
        if (result.data === undefined) {
            this.isLoading = true;
            return;
        }
        this.errorMessage = null;
        this.payload = result.data;
        if (
            !this._selectionInitialized &&
            Array.isArray(result.data?.selectedProductIds) &&
            result.data.selectedProductIds.length > 0
        ) {
            this._selectionInitialized = true;
            this.selectedProductIds = [...result.data.selectedProductIds];
        }
    }

    get hasPayload() {
        return !!this.payload;
    }

    get productOptions() {
        return (this.payload?.productRanks || []).map((row) => ({
            label: row.productName,
            value: row.productId
        }));
    }

    get hasProducts() {
        return this.productOptions.length > 0;
    }

    get primaryProductHint() {
        const name = this.payload?.selectedProductName;
        if (!name) {
            return null;
        }
        const count = (this.selectedProductIds || this.payload?.selectedProductIds || []).length;
        if (count > 1) {
            return `Primary KPIs & rating: ${name}. Sell-out chart sums all selected products.`;
        }
        return `Primary product: ${name}`;
    }

    get ctaText() {
        return this.payload?.callToAction || '';
    }

    get currencyCode() {
        return resolveCurrency(this.payload?.currencyIsoCode);
    }

    get kpiCards() {
        const data = this.payload;
        if (!data) {
            return [];
        }
        const currency = this.currencyCode;
        return [
            { id: 'spend', label: 'Spend YTD', value: money(data.totalSpendYtd, currency), hint: 'Speaker + samples + brochures; visits & meetings on timeline' },
            { id: 'written', label: 'Written value', value: money(data.writtenValue, currency), hint: 'Penetration × list price' },
            { id: 'potential', label: 'Potential', value: money(data.potentialValue, currency), hint: 'Could write if fully penetrated' },
            {
                id: 'gap',
                label: 'Opportunity gap',
                value: money(data.gapValue, currency),
                hint: data.orgRank != null ? `Org rank #${data.orgRank} of ${data.orgTotal}` : 'Close with more visits'
            }
        ];
    }

    get roiMultipleLabel() {
        if (this.payload?.roiMultiple == null) {
            return null;
        }
        return `${this.payload.roiMultiple}x ROI`;
    }

    get productRows() {
        const currency = this.currencyCode;
        return (this.payload?.productRanks || []).map((row, index) => ({
            ...row,
            key: row.productId || `row-${index}`,
            writtenDisplay: money(row.writtenValue, currency),
            potentialDisplay: money(row.potentialValue, currency),
            gapDisplay: money(row.gapValue, currency),
            rankDisplay: row.orgRank != null ? `#${row.orgRank} / ${row.orgTotal}` : '—',
            gapPercentDisplay: row.gapPercent != null ? `${row.gapPercent}%` : '—',
            rowClass: row.isSelected ? 'product-row selected' : 'product-row',
            hasImage: Boolean(row.imageUrl)
        }));
    }

    get spendRows() {
        const currency = this.currencyCode;
        return (this.payload?.spendBreakdown || []).map((row, index) => ({
            key: row.spendType || `spend-${index}`,
            spendType: row.spendType,
            amountDisplay: money(row.amount, currency)
        }));
    }

    get timelineYear() {
        return this.payload?.timelineYear || new Date().getFullYear();
    }

    get timelineTitle() {
        return `Engagement spend timeline — ${this.timelineYear}`;
    }

    get hasSpendTimeline() {
        return (this.payload?.spendEvents || []).length > 0;
    }

    get monthMarkers() {
        return MONTH_LABELS.map((label, index) => ({
            key: `m-${index}`,
            label,
            style: `left: ${(index / 12) * 100}%; width: ${100 / 12}%`
        }));
    }

    get dayMarkers() {
        const markers = [];
        for (let month = 0; month < 12; month += 1) {
            [1, 10, 20].forEach((day) => {
                const date = new Date(this.timelineYear, month, day);
                markers.push({
                    key: `d-${month}-${day}`,
                    label: String(day),
                    style: `left: ${dayOfYearPercent(date, this.timelineYear)}%`
                });
            });
        }
        return markers;
    }

    get todayMarkerStyle() {
        const today = new Date();
        const year = this.timelineYear;
        if (today.getFullYear() !== year) {
            return 'display: none;';
        }
        return `left: ${dayOfYearPercent(today, year)}%`;
    }

    get classificationBand() {
        const points = (this.payload?.ratingTrend || []).filter((p) => classScoreFromPoint(p) != null);
        if (points.length < 1) {
            return { hasData: false, segments: [], path: '', dots: [] };
        }

        const width = 1000;
        const height = 56;
        const padY = 10;
        const plotH = height - padY * 2;

        const pathParts = [];
        const dots = [];
        const segments = [];
        points.forEach((point, index) => {
            const x = (index / Math.max(points.length - 1, 1)) * width;
            const y = scaleY(classScoreFromPoint(point), CLASS_DOMAIN, padY, plotH);
            pathParts.push(`${index === 0 ? 'M' : 'L'} ${x} ${y}`);
            dots.push({
                key: `cls-${point.monthKey || index}`,
                cx: x,
                cy: y,
                title: `${point.monthLabel || ''}: ${classLabelFromPoint(point) || point.value}`
            });
            if (index < points.length - 1) {
                const nextX = ((index + 1) / Math.max(points.length - 1, 1)) * width;
                segments.push({
                    key: `seg-${point.monthKey || index}`,
                    style: `left: ${(x / width) * 100}%; width: ${((nextX - x) / width) * 100}%`,
                    label: classLabelFromPoint(point)
                });
            }
        });

        return {
            hasData: true,
            viewBox: `0 0 ${width} ${height}`,
            path: pathParts.join(' '),
            dots,
            segments
        };
    }

    get spendLanes() {
        const events = this.payload?.spendEvents || [];
        const currency = this.currencyCode;
        return LANE_META.map((lane) => {
            const laneEvents = events
                .filter((evt) => evt.spendType === lane.key)
                .map((evt, index) => {
                    const left = evt.positionPercent != null
                        ? Number(evt.positionPercent)
                        : dayOfYearPercent(evt.spendDate, this.timelineYear);
                    return {
                        key: evt.spendId || `${lane.key}-${index}`,
                        style: `left: ${left}%`,
                        amountDisplay: money(evt.amount, currency),
                        title: `${evt.spendDateLabel || ''} — ${evt.spendType} — ${money(evt.amount, currency)}${
                            evt.productName ? ` — ${evt.productName}` : ''
                        }`,
                        productName: evt.productName,
                        imageUrl: evt.imageUrl,
                        hasImage: Boolean(evt.imageUrl),
                        markerClass: evt.matchesSelectedProduct
                            ? `event-marker ${lane.tone} selected`
                            : `event-marker ${lane.tone}`
                    };
                });
            return {
                key: lane.key,
                label: lane.label,
                tone: lane.tone,
                trackClass: `lane-track ${lane.tone}`,
                events: laneEvents,
                hasEvents: laneEvents.length > 0
            };
        });
    }

    get combinedChart() {
        return buildCombinedChart(
            this.payload?.salesTrend || [],
            this.payload?.ratingTrend || [],
            this.currencyCode
        );
    }

    get divergenceAnalysis() {
        if (!this.payload) {
            return { hasHeadline: false, reasons: [] };
        }
        return analyzeDivergence(this.payload, this.currencyCode);
    }

    get hasClassificationBand() {
        return this.classificationBand?.hasData === true;
    }

    get hasCombinedChart() {
        return this.combinedChart?.hasData === true;
    }

    get hasDivergenceHeadline() {
        return this.divergenceAnalysis?.hasHeadline === true;
    }

    handleProductChange(event) {
        const values = event.detail.value || [];
        this._selectionInitialized = true;
        this.selectedProductIds = values.length > 0 ? [...values] : null;
        this.isLoading = true;
    }

    @api
    async handleRefresh() {
        this.isLoading = true;
        if (this.wiredResult) {
            await refreshApex(this.wiredResult);
        }
        this.isLoading = false;
    }
}