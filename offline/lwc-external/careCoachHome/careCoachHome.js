import { LightningElement } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';
import getContext from '@salesforce/apex/CareCoachAccess.getContext';
import getHomeData from '@salesforce/apex/CareCoachHomeController.getHomeData';
import getFilterOptions from '@salesforce/apex/CareCoachPatientService.getFilterOptions';
import {
    STATUS_META,
    CALL_STATUS_COLORS,
    PRODUCT_COLORS,
    statusStyle,
    riskClass,
    formatTime,
    formatDateTime,
    reduceError,
    getStoredMode,
    storeMode,
    onModeChange,
    getStoredScope,
    storeScope,
    initialsAvatar
} from 'c/careCoachUtils';

const KPI_META = {
    ongoing: { color: '#2e844a', icon: 'utility:heart', status: 'Ongoing' },
    pending: { color: '#dd7a01', icon: 'utility:clock', status: 'Pending' },
    dropped: { color: '#ba0517', icon: 'utility:ban', status: '' },
    unknown: { color: '#706e6b', icon: 'utility:call', status: 'Unknown (Failed calls)' }
};

export default class CareCoachHome extends NavigationMixin(LightningElement) {
    context;
    data;
    coaches = [];
    mode = 'psp';
    scope = 'mine';
    coachId = '';
    isLoading = true;
    error;
    unsubscribe;

    connectedCallback() {
        this.mode = getStoredMode();
        this.unsubscribe = onModeChange((mode) => {
            if (mode !== this.mode) {
                this.mode = mode;
                this.load();
            }
        });
        this.init();
    }

    disconnectedCallback() {
        if (this.unsubscribe) this.unsubscribe();
    }

    async init() {
        try {
            this.context = await getContext();
            this.scope = getStoredScope(this.context.defaultScope);
            if (!this.context.isSupervisor && this.context.hasFullAccess) this.scope = 'mine';
            if (!this.context.hasFullAccess) this.scope = 'all';
            const opts = await getFilterOptions();
            this.coaches = opts.coaches || [];
        } catch (e) {
            this.error = reduceError(e);
        }
        this.load();
    }

    async load() {
        this.isLoading = true;
        this.error = undefined;
        try {
            this.data = await getHomeData({ mode: this.mode, scope: this.scope, coachId: this.coachId || null });
        } catch (e) {
            this.error = reduceError(e);
        } finally {
            this.isLoading = false;
        }
    }

    // ---------------------------------------------------------------- header

    get greeting() {
        const h = new Date().getHours();
        const part = h < 12 ? 'Good morning' : h < 17 ? 'Good afternoon' : 'Good evening';
        const name = this.context && this.context.firstName ? `, ${this.context.firstName}` : '';
        return `${part}${name}`;
    }

    get subtitle() {
        if (!this.context) return 'Care Coach Co-pilot';
        if (!this.context.hasFullAccess) return 'Programme performance across all care coaches (de-identified)';
        return this.scope === 'mine'
            ? 'Your patients, calls and follow-ups for today'
            : 'Programme performance across all care coaches';
    }

    get masked() {
        return this.data ? this.data.masked : this.mode === 'company';
    }

    handleModeChange(event) {
        storeMode(event.detail);
    }

    handleScopeChange(event) {
        this.scope = event.detail;
        storeScope(this.scope);
        if (this.scope === 'mine') this.coachId = '';
        this.load();
    }

    handleCoachChange(event) {
        this.coachId = event.detail;
        this.load();
    }

    handleRefresh() {
        this.load();
    }

    // ---------------------------------------------------------------- KPIs

    get kpiCards() {
        if (!this.data) return [];
        return this.data.kpis.map((k) => {
            const meta = KPI_META[k.id] || KPI_META.unknown;
            const share = this.data.totalPatients ? Math.round((k.value * 100) / this.data.totalPatients) : 0;
            const changeLabel =
                k.id === 'dropped'
                    ? `${k.changeThisMonth || 0} changed this month`
                    : `+${k.changeThisMonth || 0} new this month`;
            return {
                ...k,
                style: `--kpi-color:${meta.color};`,
                icon: meta.icon,
                share: `${share}% of patients`,
                changeLabel,
                hasReport: !!(this.data.reportIds && this.data.reportIds[k.reportName])
            };
        });
    }

    get stats() {
        if (!this.data) return [];
        const d = this.data;
        const delta = d.newLastMonth ? Math.round(((d.newThisMonth - d.newLastMonth) * 100) / d.newLastMonth) : null;
        return [
            { id: 'total', label: 'Total patients', value: d.totalPatients.toLocaleString() },
            {
                id: 'new',
                label: 'New this month',
                value: d.newThisMonth.toLocaleString(),
                sub: delta === null ? `${d.newLastMonth} last month` : `${delta >= 0 ? '+' : ''}${delta}% vs last month`
            },
            { id: 'retention', label: 'Retention', value: d.retentionRate == null ? '—' : `${d.retentionRate}%`, sub: 'Ongoing vs dropped' },
            { id: 'reach', label: 'Reach rate (30d)', value: d.reachRate == null ? '—' : `${d.reachRate}%`, sub: 'Reached / attempted calls' }
        ];
    }

    handleKpiReport(event) {
        const name = event.currentTarget.dataset.report;
        const id = this.data.reportIds[name];
        if (id) this.navigateToRecord(id, 'Report');
    }

    handleKpiDrill(event) {
        const id = event.currentTarget.dataset.status;
        const group = { ongoing: 'Ongoing', pending: 'Pending', dropped: 'Dropped', unknown: 'Unknown' }[id];
        this.goToPatients({ c__group: group });
    }

    handleDashboard() {
        if (this.data && this.data.dashboardId) this.navigateToRecord(this.data.dashboardId, 'Dashboard');
    }

    get hasDashboard() {
        return this.data && this.data.dashboardId;
    }

    // ---------------------------------------------------------------- Board

    get boardColumns() {
        if (!this.data) return [];
        return this.data.board.map((col) => {
            const meta = STATUS_META[col.status] || STATUS_META['Unknown (Failed calls)'];
            return {
                ...col,
                label: meta.short,
                style: statusStyle(col.status),
                hasMore: col.count > col.patients.length,
                patients: col.patients.map((p) => ({
                    ...p,
                    avatar: initialsAvatar(p.displayName),
                    avatarClass: p.masked ? 'cc-avatar cc-avatar_masked' : 'cc-avatar',
                    sub: [p.productName, p.masked ? `${p.gender || ''} ${p.age != null ? p.age + 'y' : ''}`.trim() : p.mobile || p.phone]
                        .filter(Boolean)
                        .join(' · '),
                    riskClass: riskClass(p.adherence),
                    riskLabel: p.adherence ? p.adherence.replace(' risk', '') : ''
                }))
            };
        });
    }

    get boardTitle() {
        return this.scope === 'mine' ? 'My patients by status' : 'Patients by status';
    }

    handleColumnOpen(event) {
        this.goToPatients({ c__status: event.currentTarget.dataset.status });
    }

    // ---------------------------------------------------------------- Calls chart

    get callRows() {
        if (!this.data || !this.data.calls.length) return [];
        const byDirection = {};
        this.data.calls.forEach((c) => {
            (byDirection[c.direction] = byDirection[c.direction] || []).push(c);
        });
        const maxTotal = Math.max(...Object.values(this.data.callTotals));
        return Object.keys(byDirection)
            .sort()
            .map((dir) => {
                const total = this.data.callTotals[dir];
                const segs = byDirection[dir]
                    .sort((a, b) => b.count - a.count)
                    .map((c) => ({
                        key: `${dir}-${c.status}`,
                        style: `width:${(c.count * 100) / total}%;background:${CALL_STATUS_COLORS[c.status] || '#999'};`,
                        title: `${dir} · ${c.status}: ${c.count} (${c.pctOfDirection}% of ${total} ${dir.toLowerCase()})`,
                        showLabel: (c.count * 100) / total > 9,
                        count: c.count
                    }));
                return {
                    direction: dir,
                    total,
                    trackStyle: `width:${Math.max(18, (total * 100) / maxTotal)}%;`,
                    segments: segs,
                    breakdown: byDirection[dir].map((c) => ({
                        key: `${dir}-${c.status}-legend`,
                        status: c.status,
                        count: c.count,
                        pct: `${c.pctOfDirection}%`,
                        dot: `background:${CALL_STATUS_COLORS[c.status] || '#999'};`
                    }))
                };
            });
    }

    get hasCalls() {
        return this.callRows.length > 0;
    }

    handleCallsReport() {
        const id = this.data.reportIds.PSP_Calls_by_Direction_Status;
        if (id) this.navigateToRecord(id, 'Report');
    }

    // ---------------------------------------------------------------- Monthly chart

    get monthBars() {
        if (!this.data) return [];
        const max = Math.max(1, ...this.data.months.map((m) => m.total));
        return this.data.months.map((m) => ({
            key: m.monthKey,
            label: m.label,
            total: m.total,
            columnStyle: `height:${(m.total * 100) / max}%;`,
            segments: this.data.products
                .filter((p) => m.byProduct[p])
                .map((p) => ({
                    key: `${m.monthKey}-${p}`,
                    style: `flex-grow:${m.byProduct[p]};background:${this.productColor(p)};`,
                    title: `${m.label} · ${p}: ${m.byProduct[p]} new patients`
                }))
        }));
    }

    get productLegend() {
        if (!this.data) return [];
        return this.data.products.map((p) => ({ name: p, dot: `background:${this.productColor(p)};` }));
    }

    productColor(name) {
        const idx = this.data.products.indexOf(name);
        return PRODUCT_COLORS[idx % PRODUCT_COLORS.length];
    }

    handleTrendReport() {
        const id = this.data.reportIds.PSP_New_Patients_by_Product;
        if (id) this.navigateToRecord(id, 'Report');
    }

    // ---------------------------------------------------------------- Work lists

    decorateWork(list, withTime) {
        return (list || []).map((w) => ({
            ...w,
            when: withTime ? formatTime(w.startTime) : formatDateTime(w.startTime),
            avatar: initialsAvatar(w.patientName),
            avatarClass: this.masked ? 'cc-avatar cc-avatar_masked' : 'cc-avatar',
            riskClass: riskClass(w.risk),
            sub: [w.reason, w.productName].filter(Boolean).join(' · ')
        }));
    }

    get todayItems() {
        return this.decorateWork(this.data && this.data.today, true);
    }

    get overdueItems() {
        return this.decorateWork(this.data && this.data.overdue, false);
    }

    get alertItems() {
        return this.decorateWork(this.data && this.data.aiAlerts, false);
    }

    get todayCount() {
        return this.todayItems.length;
    }

    get overdueCount() {
        return this.overdueItems.length;
    }

    get alertCount() {
        return this.alertItems.length;
    }

    get noToday() {
        return this.todayCount === 0;
    }

    get noOverdue() {
        return this.overdueCount === 0;
    }

    get noAlerts() {
        return this.alertCount === 0;
    }

    handleOpenPatient(event) {
        this.goToPatients({ c__patientId: event.currentTarget.dataset.id });
    }

    handleOpenPlanner() {
        this[NavigationMixin.Navigate]({ type: 'standard__navItemPage', attributes: { apiName: 'Care_Coach_Planner' } });
    }

    // ---------------------------------------------------------------- Coaches

    get coachRows() {
        if (!this.data || !this.data.coaches) return [];
        return [...this.data.coaches]
            .sort((a, b) => b.ongoing - a.ongoing)
            .map((c, i) => ({
                ...c,
                rank: i + 1,
                retention: c.ongoing + c.dropped ? `${Math.round((c.ongoing * 100) / (c.ongoing + c.dropped))}%` : '—',
                barOngoing: `width:${c.total ? (c.ongoing * 100) / c.total : 0}%;`,
                barPending: `width:${c.total ? (c.pending * 100) / c.total : 0}%;`,
                barDropped: `width:${c.total ? (c.dropped * 100) / c.total : 0}%;`,
                barUnknown: `width:${c.total ? (c.unknown * 100) / c.total : 0}%;`
            }));
    }

    get showCoaches() {
        return this.coachRows.length > 0;
    }

    handleCoachRow(event) {
        this.coachId = event.currentTarget.dataset.id;
        this.load();
    }

    // ---------------------------------------------------------------- navigation

    goToPatients(state) {
        const clean = {};
        Object.keys(state || {}).forEach((k) => {
            if (state[k]) clean[k] = state[k];
        });
        this[NavigationMixin.Navigate]({
            type: 'standard__navItemPage',
            attributes: { apiName: 'Care_Coach_Patients' },
            state: clean
        });
    }

    navigateToRecord(recordId, objectApiName) {
        this[NavigationMixin.Navigate]({
            type: 'standard__recordPage',
            attributes: { recordId, objectApiName, actionName: 'view' }
        });
    }
}