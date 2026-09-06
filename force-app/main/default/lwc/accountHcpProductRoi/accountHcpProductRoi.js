import { LightningElement, api, wire } from 'lwc';
import { refreshApex } from '@salesforce/apex';
import getAccountRoi from '@salesforce/apex/HcpProductRoiController.getAccountRoi';

const MONTH_LABELS = ['JAN', 'FEB', 'MAR', 'APR', 'MAY', 'JUN', 'JUL', 'AUG', 'SEP', 'OCT', 'NOV', 'DEC'];
const LANE_META = [
    { key: 'Speaker Meeting', label: 'Speaker / RTD', tone: 'speaker' },
    { key: 'Samples', label: 'Samples', tone: 'samples' },
    { key: 'Brochures', label: 'Brochures', tone: 'brochures' }
];

function money(value) {
    if (value == null || value === '') {
        return '$0';
    }
    return new Intl.NumberFormat('en-US', {
        style: 'currency',
        currency: 'USD',
        maximumFractionDigits: 0
    }).format(Number(value));
}

function buildLineChart(points, color) {
    const series = points || [];
    const width = 640;
    const height = 180;
    const padLeft = 36;
    const padRight = 16;
    const padTop = 16;
    const padBottom = 28;
    const plotW = width - padLeft - padRight;
    const plotH = height - padTop - padBottom;

    const numeric = series.map((p) => {
        if (p == null || p.value == null || p.value === '') {
            return null;
        }
        const n = Number(p.value);
        return Number.isNaN(n) ? null : n;
    });
    const present = numeric.filter((v) => v != null);
    if (!present.length) {
        return {
            hasData: false,
            viewBox: `0 0 ${width} ${height}`,
            path: '',
            dots: [],
            labels: [],
            color
        };
    }

    const min = Math.min(...present);
    const max = Math.max(...present);
    const span = max - min || 1;
    const count = Math.max(series.length, 1);
    const xStep = count > 1 ? plotW / (count - 1) : 0;

    const dots = [];
    const pathParts = [];
    const labels = [];
    series.forEach((point, index) => {
        const x = padLeft + index * xStep;
        const value = numeric[index];
        labels.push({
            key: point.monthKey || `m-${index}`,
            x,
            label: point.monthLabel || ''
        });
        if (value == null) {
            return;
        }
        const y = padTop + plotH - ((value - min) / span) * plotH;
        dots.push({
            key: point.monthKey || `d-${index}`,
            cx: x,
            cy: y,
            title: `${point.monthLabel || ''}: ${value}${point.classification ? ` (${point.classification})` : ''}`
        });
        pathParts.push(`${pathParts.length ? 'L' : 'M'} ${x} ${y}`);
    });

    return {
        hasData: pathParts.length > 1,
        viewBox: `0 0 ${width} ${height}`,
        path: pathParts.join(' '),
        dots,
        labels: labels.filter((_, idx) => idx % 2 === 0 || idx === labels.length - 1),
        color
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
    selectedProductId = null;
    wiredResult;
    payload;
    errorMessage;
    isLoading = true;

    @wire(getAccountRoi, { accountId: '$recordId', productId: '$selectedProductId' })
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
                'Unable to load HCP product ROI.';
            this.payload = null;
            return;
        }
        if (result.data === undefined) {
            this.isLoading = true;
            return;
        }
        this.errorMessage = null;
        this.payload = result.data;
        if (result.data?.selectedProductId && this.selectedProductId == null) {
            this.selectedProductId = result.data.selectedProductId;
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

    get ctaText() {
        return this.payload?.callToAction || '';
    }

    get kpiCards() {
        const data = this.payload;
        if (!data) {
            return [];
        }
        return [
            { id: 'spend', label: 'Spend YTD', value: money(data.totalSpendYtd), hint: 'Speaker + samples + brochures' },
            { id: 'written', label: 'Written value', value: money(data.writtenValue), hint: 'Penetration � list price' },
            { id: 'potential', label: 'Potential', value: money(data.potentialValue), hint: 'Could write if fully penetrated' },
            {
                id: 'gap',
                label: 'Opportunity gap',
                value: money(data.gapValue),
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
        return (this.payload?.productRanks || []).map((row, index) => ({
            ...row,
            key: row.productId || `row-${index}`,
            writtenDisplay: money(row.writtenValue),
            potentialDisplay: money(row.potentialValue),
            gapDisplay: money(row.gapValue),
            rankDisplay: row.orgRank != null ? `#${row.orgRank} / ${row.orgTotal}` : '�',
            gapPercentDisplay: row.gapPercent != null ? `${row.gapPercent}%` : '�',
            rowClass: row.isSelected ? 'product-row selected' : 'product-row',
            hasImage: Boolean(row.imageUrl)
        }));
    }

    get spendRows() {
        return (this.payload?.spendBreakdown || []).map((row, index) => ({
            key: row.spendType || `spend-${index}`,
            spendType: row.spendType,
            amountDisplay: money(row.amount)
        }));
    }

    get timelineYear() {
        return this.payload?.timelineYear || new Date().getFullYear();
    }

    get timelineTitle() {
        return `Engagement spend timeline � ${this.timelineYear}`;
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
        const points = (this.payload?.ratingTrend || []).filter((p) => p && p.classification);
        if (points.length < 1) {
            return { hasData: false, segments: [], path: '', dots: [] };
        }

        const width = 1000;
        const height = 56;
        const padY = 10;
        const plotH = height - padY * 2;
        const values = points.map((p) => Number(p.value) || 0);
        const min = Math.min(...values, 0);
        const max = Math.max(...values, 1);
        const span = max - min || 1;

        const pathParts = [];
        const dots = [];
        const segments = [];
        points.forEach((point, index) => {
            const x = (index / Math.max(points.length - 1, 1)) * width;
            const y = padY + plotH - ((Number(point.value) - min) / span) * plotH;
            pathParts.push(`${index === 0 ? 'M' : 'L'} ${x} ${y}`);
            dots.push({
                key: `cls-${point.monthKey || index}`,
                cx: x,
                cy: y,
                title: `${point.monthLabel || ''}: ${point.classification || point.value}`
            });
            if (index < points.length - 1) {
                const nextX = ((index + 1) / Math.max(points.length - 1, 1)) * width;
                segments.push({
                    key: `seg-${point.monthKey || index}`,
                    style: `left: ${(x / width) * 100}%; width: ${((nextX - x) / width) * 100}%`,
                    label: point.classification || ''
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
                        amountDisplay: money(evt.amount),
                        title: `${evt.spendDateLabel || ''} � ${evt.spendType} � ${money(evt.amount)}${
                            evt.productName ? ` � ${evt.productName}` : ''
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

    get salesChart() {
        return buildLineChart(this.payload?.salesTrend || [], '#0176d3');
    }

    get ratingChart() {
        return buildLineChart(this.payload?.ratingTrend || [], '#2e844a');
    }

    handleProductChange(event) {
        this.selectedProductId = event.detail.value;
        this.isLoading = true;
    }

    async handleRefresh() {
        this.isLoading = true;
        if (this.wiredResult) {
            await refreshApex(this.wiredResult);
        }
        this.isLoading = false;
    }
}
