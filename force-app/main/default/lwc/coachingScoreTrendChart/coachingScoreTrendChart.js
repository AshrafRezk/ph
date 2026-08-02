import { LightningElement, api, track } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';
import getCoachingMonthDrillDown from '@salesforce/apex/ManagementKpiController.getCoachingMonthDrillDown';

const LINE_COLORS = [
    '#0176d3', '#9050e9', '#2e844a', '#fe9339', '#ea001e', '#06a59a',
    '#032d60', '#b65c02', '#5867dd', '#8b5cf6', '#14b8a6', '#f59e0b'
];

function scoreDisplay(value) {
    if (value == null || value === '') {
        return '—';
    }
    return `${Number(value).toFixed(1)}%`;
}

function deltaDisplay(delta) {
    if (delta == null || delta === '') {
        return '';
    }
    const sign = Number(delta) > 0 ? '+' : '';
    return `${sign}${Number(delta).toFixed(1)}%`;
}

function trendArrow(trend) {
    if (trend === 'growing') return '▲';
    if (trend === 'declining') return '▼';
    if (trend === 'flat') return '■';
    return '';
}

function trendClass(trend) {
    if (trend === 'growing') return 'cst-trend-up';
    if (trend === 'declining') return 'cst-trend-down';
    if (trend === 'flat') return 'cst-trend-flat';
    return 'cst-trend-none';
}

function mapSection(section) {
    const shortName =
        section.sectionName === 'Core Values' ? 'Core'
            : section.sectionName === 'Selling Skills' ? 'Selling'
                : section.sectionName;
    return {
        ...section,
        key: section.sectionName,
        shortName,
        latestDisplay: scoreDisplay(section.latestScore),
        deltaDisplay: deltaDisplay(section.delta),
        arrow: trendArrow(section.trend),
        trendClass: trendClass(section.trend)
    };
}

function buildChartModel(reps) {
    const monthTemplate = (reps[0]?.monthlyScores || []).map((point, index) => ({
        monthKey: point.monthKey || `month-${index}`,
        monthLabel: point.monthLabel || '',
        monthYearLabel: point.monthYearLabel || point.monthLabel || ''
    }));

    if (!monthTemplate.length) {
        return { hasLines: false, viewBox: '0 0 640 248', monthSnapshots: [], lines: [], legend: [] };
    }

    const width = 640;
    const height = 248;
    const padLeft = 40;
    const padRight = 20;
    const padTop = 18;
    const padBottom = 34;
    const plotW = width - padLeft - padRight;
    const plotH = height - padTop - padBottom;
    const monthCount = Math.max(monthTemplate.length, 1);
    const xStep = monthCount > 1 ? plotW / (monthCount - 1) : 0;
    const bandHalf = monthCount > 1 ? xStep / 2 : plotW / 2;

    const repColorById = {};
    const lines = (reps || []).map((rep, repIndex) => {
        const color = LINE_COLORS[repIndex % LINE_COLORS.length];
        repColorById[rep.repId] = color;
        const monthlyScores = rep.monthlyScores || [];
        const dots = monthlyScores.map((point, index) => {
            const score = Number(point.avgScore) || 0;
            const x = padLeft + index * xStep;
            const y = padTop + plotH - (score / 100) * plotH;
            return {
                key: `${rep.repId}-${point.monthKey || index}`,
                repId: rep.repId,
                monthIndex: index,
                monthKey: point.monthKey,
                x,
                y,
                score,
                hasData: score > 0,
                monthLabel: point.monthLabel
            };
        }).filter((d) => d.hasData);

        if (!dots.length) {
            return null;
        }

        return {
            key: rep.repId,
            repId: rep.repId,
            repName: rep.repName,
            color,
            lineStyle: `stroke: ${color}; fill: ${color};`,
            polyline: dots.map((d) => `${d.x},${d.y}`).join(' '),
            dots,
            swatchStyle: `background-color: ${color};`
        };
    }).filter(Boolean);

    const monthSnapshots = monthTemplate.map((month, index) => {
        const x = padLeft + index * xStep;
        const repRows = [];
        let scoreSum = 0;
        let scoreCount = 0;
        let deltaSum = 0;
        let deltaCount = 0;

        (reps || []).forEach((rep) => {
            const point = (rep.monthlyScores || [])[index];
            const score = Number(point?.avgScore) || 0;
            if (score <= 0) {
                return;
            }
            const priorPoint = index > 0 ? (rep.monthlyScores || [])[index - 1] : null;
            const priorScore = priorPoint ? Number(priorPoint.avgScore) || 0 : 0;
            const delta = priorScore > 0 ? score - priorScore : null;
            const trendLabel = delta == null ? 'none' : (delta > 0.5 ? 'growing' : delta < -0.5 ? 'declining' : 'flat');

            repRows.push({
                key: `${rep.repId}-${month.monthKey}`,
                repId: rep.repId,
                repName: rep.repName,
                score,
                scoreDisplay: scoreDisplay(score),
                delta,
                deltaDisplay: deltaDisplay(delta),
                trend: trendLabel,
                trendClass: trendClass(trendLabel),
                deltaPillClass: `cst-delta-pill cst-delta-pill-${trendLabel}`,
                arrow: trendArrow(trendLabel),
                isTopRank: false,
                color: repColorById[rep.repId],
                swatchStyle: `background-color: ${repColorById[rep.repId]};`
            });
            scoreSum += score;
            scoreCount++;
            if (delta != null) {
                deltaSum += delta;
                deltaCount++;
            }
        });

        repRows.sort((a, b) => b.score - a.score);
        repRows.forEach((row, rank) => {
            row.rank = rank + 1;
            row.isTopRank = rank === 0;
            row.rankClass = rank === 0 ? 'cst-tooltip-rank cst-tooltip-rank-top' : 'cst-tooltip-rank';
            row.rowClass = rank === 0 ? 'cst-tooltip-row cst-tooltip-row-top' : 'cst-tooltip-row';
        });

        const teamAvg = scoreCount > 0 ? scoreSum / scoreCount : 0;
        const teamDelta = deltaCount > 0 ? deltaSum / deltaCount : null;

        return {
            key: month.monthKey,
            monthIndex: index,
            monthKey: month.monthKey,
            monthLabel: month.monthLabel,
            monthYearLabel: month.monthYearLabel,
            x,
            crosshairX: x,
            bandX: x - bandHalf,
            bandWidth: bandHalf * 2,
            bandY: padTop,
            bandHeight: plotH,
            teamAvgScore: teamAvg,
            teamAvgDisplay: scoreDisplay(teamAvg),
            teamDelta,
            teamDeltaDisplay: deltaDisplay(teamDelta),
            teamTrendClass: trendClass(
                teamDelta == null ? 'none' : (teamDelta > 0.5 ? 'growing' : teamDelta < -0.5 ? 'declining' : 'flat')
            ),
            teamDeltaPillClass: `cst-delta-pill cst-delta-pill-${
                teamDelta == null ? 'none' : (teamDelta > 0.5 ? 'growing' : teamDelta < -0.5 ? 'declining' : 'flat')
            }`,
            repRows,
            hasReps: repRows.length > 0
        };
    });

    return {
        width,
        height,
        viewBox: `0 0 ${width} ${height}`,
        plot: { x: padLeft, y: padTop, width: plotW, height: plotH },
        gridLines: [0, 50, 100].map((pct) => ({
            key: `grid-${pct}`,
            y: padTop + plotH - (pct / 100) * plotH,
            x1: padLeft,
            x2: padLeft + plotW,
            label: `${pct}%`
        })),
        monthLabels: monthTemplate.map((month, index) => ({
            key: month.monthKey,
            x: padLeft + index * xStep,
            y: height - 10,
            label: month.monthLabel
        })),
        monthSnapshots,
        lines,
        legend: lines,
        hasLines: lines.length > 0
    };
}

export default class CoachingScoreTrendChart extends NavigationMixin(LightningElement) {
    @api repTrends = [];
    @api teamScoreDelta;
    @api buTerritoryId;
    @api lineTerritoryId;
    @api districtTerritoryId;

    @track hoveredMonthIndex = null;
    @track hoveredRepId = null;
    @track focusedRepId = null;
    @track keyboardMonthIndex = null;
    @track inspectorOpen = false;
    @track inspectorLoading = false;
    @track inspectorData = null;
    @track expandedRepId = null;
    @track tooltipLeft = 0;
    @track tooltipTop = 0;
    @track ariaLiveMessage = '';

    _chartAreaRect = null;

    get hasChart() {
        return this.chartModel.hasLines;
    }

    get chartModel() {
        return buildChartModel(this.repTrends || []);
    }

    get teamCoachingDeltaDisplay() {
        return deltaDisplay(this.teamScoreDelta);
    }

    get teamCoachingTrendClass() {
        const delta = Number(this.teamScoreDelta) || 0;
        if (delta > 0.5) return 'cst-team-badge-delta cst-trend-up';
        if (delta < -0.5) return 'cst-team-badge-delta cst-trend-down';
        return 'cst-team-badge-delta cst-trend-flat';
    }

    get activeMonthIndex() {
        if (this.hoveredMonthIndex != null) {
            return this.hoveredMonthIndex;
        }
        if (this.keyboardMonthIndex != null) {
            return this.keyboardMonthIndex;
        }
        return null;
    }

    get activeMonthSnapshot() {
        const idx = this.activeMonthIndex;
        if (idx == null) {
            return null;
        }
        return this.chartModel.monthSnapshots[idx] || null;
    }

    get showCrosshair() {
        return this.activeMonthIndex != null && this.activeMonthSnapshot;
    }

    get crosshairX() {
        return this.activeMonthSnapshot?.crosshairX ?? 0;
    }

    get crosshairY1() {
        return this.chartModel.plot?.y ?? 0;
    }

    get crosshairY2() {
        const plot = this.chartModel.plot;
        return plot ? plot.y + plot.height : 0;
    }

    get activeMonthHighlight() {
        const snap = this.activeMonthSnapshot;
        if (!snap) {
            return null;
        }
        const plot = this.chartModel.plot;
        return {
            x: snap.bandX,
            y: plot?.y ?? 0,
            width: snap.bandWidth,
            height: plot?.height ?? 0
        };
    }

    get displayMonthLabels() {
        const activeIdx = this.activeMonthIndex;
        return (this.chartModel.monthLabels || []).map((month, index) => ({
            ...month,
            labelClass: activeIdx === index ? 'cst-axis-label cst-axis-x cst-axis-x-active' : 'cst-axis-label cst-axis-x'
        }));
    }

    get showTooltip() {
        return this.showCrosshair && this.activeMonthSnapshot?.hasReps;
    }

    get tooltipStyle() {
        return `left: ${this.tooltipLeft}px; top: ${this.tooltipTop}px;`;
    }

    get displayLines() {
        const focusId = this.focusedRepId || this.hoveredRepId;
        return (this.chartModel.lines || []).map((line) => {
            const dimmed = focusId && focusId !== line.repId;
            const emphasized = focusId === line.repId;
            return {
                ...line,
                lineClass: `cst-trend-line${dimmed ? ' cst-line-dimmed' : ''}${emphasized ? ' cst-line-emphasis' : ''}`,
                dots: line.dots.map((dot) => {
                    const emphasized = focusId === line.repId;
                    return {
                        ...dot,
                        dotClass: `cst-trend-dot${dimmed ? ' cst-dot-dimmed' : ''}${emphasized ? ' cst-dot-emphasis' : ''}`,
                        hitClass: 'cst-dot-hit',
                        dotRadius: emphasized ? 5.5 : 3.5
                    };
                })
            };
        });
    }

    get displayLegend() {
        const focusId = this.focusedRepId || this.hoveredRepId;
        return (this.chartModel.legend || []).map((item) => ({
            ...item,
            legendClass: `cst-legend-item${focusId === item.repId ? ' cst-legend-active' : ''}${focusId && focusId !== item.repId ? ' cst-legend-dimmed' : ''}`
        }));
    }

    get inspectorRows() {
        return (this.inspectorData?.repRows || []).map((row, index) => {
            const sections = (row.sectionTrends || []).map(mapSection);
            return {
                ...row,
                key: row.repId,
                rank: index + 1,
                scoreDisplay: scoreDisplay(row.score),
                deltaDisplay: deltaDisplay(row.scoreDelta),
                trendClass: trendClass(row.trend),
                arrow: trendArrow(row.trend),
                isExpanded: this.expandedRepId === row.repId,
                rowClass: `cst-inspector-row${this.expandedRepId === row.repId ? ' cst-inspector-row-expanded' : ''}`,
                sections,
                hasSections: sections.length > 0,
                hasEvent: Boolean(row.eventId)
            };
        });
    }

    get hasInspectorRows() {
        return this.inspectorRows.length > 0;
    }

    get inspectorTeamDeltaDisplay() {
        return deltaDisplay(this.inspectorData?.teamScoreDelta);
    }

    get inspectorTeamTrendClass() {
        return trendClass(this.inspectorData?.teamTrend);
    }

    get inspectorTitle() {
        return this.inspectorData?.monthYearLabel || 'Loading…';
    }

    get inspectorTeamAvgDisplay() {
        return scoreDisplay(this.inspectorData?.teamAvgScore);
    }

    renderedCallback() {
        this._chartAreaRect = this.template.querySelector('.cst-chart-area')?.getBoundingClientRect();
        if (this.showTooltip && this.activeMonthSnapshot) {
            this.positionTooltip(this.activeMonthSnapshot.crosshairX);
        }
    }

    positionTooltip(svgX) {
        const area = this.template.querySelector('.cst-chart-area');
        const svg = this.template.querySelector('.cst-line-chart');
        const tooltip = this.template.querySelector('.cst-tooltip');
        if (!area || !svg || !tooltip) {
            return;
        }
        const areaRect = area.getBoundingClientRect();
        const svgRect = svg.getBoundingClientRect();
        const viewBoxWidth = this.chartModel.width || 640;
        const scale = svgRect.width / viewBoxWidth;
        const pixelX = svgRect.left - areaRect.left + svgX * scale;
        const tooltipWidth = tooltip.offsetWidth || 220;
        let left = pixelX + 12;
        if (left + tooltipWidth > areaRect.width - 8) {
            left = pixelX - tooltipWidth - 12;
        }
        left = Math.max(8, left);
        this.tooltipLeft = left;
        this.tooltipTop = 8;
    }

    handleMonthEnter(event) {
        const index = Number.parseInt(event.currentTarget.dataset.monthIndex, 10);
        if (Number.isNaN(index)) {
            return;
        }
        this.hoveredMonthIndex = index;
        this.hoveredRepId = null;
        const snap = this.chartModel.monthSnapshots[index];
        if (snap) {
            this.ariaLiveMessage = `${snap.monthYearLabel}: team average ${snap.teamAvgDisplay}, ${snap.repRows.length} reps`;
        }
    }

    handleMonthMove(event) {
        this.handleMonthEnter(event);
    }

    handleMonthLeave() {
        this.hoveredMonthIndex = null;
    }

    handleDotEnter(event) {
        const repId = event.currentTarget.dataset.repId;
        const monthIndex = Number.parseInt(event.currentTarget.dataset.monthIndex, 10);
        this.hoveredRepId = repId;
        this.hoveredMonthIndex = monthIndex;
        const line = (this.chartModel.lines || []).find((l) => l.repId === repId);
        const dot = line?.dots?.find((d) => d.monthIndex === monthIndex);
        if (line && dot) {
            this.ariaLiveMessage = `${line.repName}, ${dot.monthLabel}: ${scoreDisplay(dot.score)}`;
        }
    }

    handleDotLeave() {
        this.hoveredRepId = null;
    }

    handleLegendEnter(event) {
        this.hoveredRepId = event.currentTarget.dataset.repId;
    }

    handleLegendLeave() {
        if (!this.focusedRepId) {
            this.hoveredRepId = null;
        }
    }

    handleLegendClick(event) {
        const repId = event.currentTarget.dataset.repId;
        this.focusedRepId = this.focusedRepId === repId ? null : repId;
        this.hoveredRepId = this.focusedRepId;
    }

    async handleMonthClick(event) {
        const monthIndex = Number.parseInt(event.currentTarget.dataset.monthIndex, 10);
        const monthKey = event.currentTarget.dataset.monthKey;
        if (Number.isNaN(monthIndex) || !monthKey) {
            return;
        }
        await this.openInspector(monthKey, monthIndex);
    }

    async handleDotClick(event) {
        event.stopPropagation();
        const monthKey = event.currentTarget.dataset.monthKey;
        const monthIndex = Number.parseInt(event.currentTarget.dataset.monthIndex, 10);
        const repId = event.currentTarget.dataset.repId;
        if (!monthKey) {
            return;
        }
        await this.openInspector(monthKey, monthIndex, repId);
    }

    async openInspector(monthKey, monthIndex, expandRepId) {
        this.inspectorOpen = true;
        this.inspectorLoading = true;
        this.inspectorData = null;
        this.expandedRepId = expandRepId || null;
        this.keyboardMonthIndex = monthIndex;

        try {
            const data = await getCoachingMonthDrillDown({
                monthKey,
                buTerritoryId: this.buTerritoryId,
                lineTerritoryId: this.lineTerritoryId,
                districtTerritoryId: this.districtTerritoryId
            });
            this.inspectorData = data;
            if (expandRepId) {
                this.expandedRepId = expandRepId;
            }
        } catch (e) {
            this.inspectorData = {
                monthYearLabel: monthKey,
                repRows: [],
                teamAvgScore: 0,
                teamScoreDelta: 0,
                teamTrend: 'none'
            };
        } finally {
            this.inspectorLoading = false;
        }
    }

    handleInspectorRowClick(event) {
        const repId = event.currentTarget.dataset.repId;
        this.expandedRepId = this.expandedRepId === repId ? null : repId;
    }

    handleViewEvent(event) {
        event.stopPropagation();
        const eventId = event.currentTarget.dataset.eventId;
        if (!eventId) {
            return;
        }
        this[NavigationMixin.Navigate]({
            type: 'standard__recordPage',
            attributes: {
                recordId: eventId,
                objectApiName: 'Coaching_Event__c',
                actionName: 'view'
            }
        });
    }

    handleCloseInspector() {
        this.inspectorOpen = false;
        this.inspectorData = null;
        this.expandedRepId = null;
        this.keyboardMonthIndex = null;
    }

    handleChartKeyDown(event) {
        const snapshots = this.chartModel.monthSnapshots || [];
        if (!snapshots.length) {
            return;
        }
        let idx = this.keyboardMonthIndex ?? this.hoveredMonthIndex ?? 0;

        if (event.key === 'ArrowRight') {
            event.preventDefault();
            idx = Math.min(idx + 1, snapshots.length - 1);
            this.keyboardMonthIndex = idx;
            this.hoveredMonthIndex = idx;
            const snap = snapshots[idx];
            this.ariaLiveMessage = `${snap.monthYearLabel}: team average ${snap.teamAvgDisplay}`;
        } else if (event.key === 'ArrowLeft') {
            event.preventDefault();
            idx = Math.max(idx - 1, 0);
            this.keyboardMonthIndex = idx;
            this.hoveredMonthIndex = idx;
            const snap = snapshots[idx];
            this.ariaLiveMessage = `${snap.monthYearLabel}: team average ${snap.teamAvgDisplay}`;
        } else if (event.key === 'Enter') {
            event.preventDefault();
            const snap = snapshots[idx];
            if (snap) {
                this.openInspector(snap.monthKey, idx);
            }
        } else if (event.key === 'Escape') {
            event.preventDefault();
            this.handleCloseInspector();
            this.hoveredMonthIndex = null;
            this.keyboardMonthIndex = null;
            this.focusedRepId = null;
            this.hoveredRepId = null;
        }
    }
}
