import { LightningElement } from 'lwc';
import getContext from '@salesforce/apex/CareCoachAccess.getContext';
import getOrders from '@salesforce/apex/CareCoachOrderService.getOrders';
import updateOrderStatus from '@salesforce/apex/CareCoachOrderService.updateOrderStatus';
import {
    reduceError,
    getStoredMode,
    storeMode,
    onModeChange,
    getStoredScope,
    storeScope,
    formatDate,
    initialsAvatar
} from 'c/careCoachUtils';

const STATUS_COLORS = {
    Requested: ['#0176d3', '#e5f1fb'],
    Approved: ['#7526e3', '#f1e9fd'],
    Dispatched: ['#dd7a01', '#fef1e2'],
    Delivered: ['#2e844a', '#e8f5ec'],
    Cancelled: ['#747474', '#f1f1f1']
};

const NEXT_STEP = {
    Requested: { label: 'Approve', status: 'Approved', icon: 'utility:check' },
    Approved: { label: 'Dispatch', status: 'Dispatched', icon: 'utility:right' },
    Dispatched: { label: 'Mark delivered', status: 'Delivered', icon: 'utility:success' }
};

const PERIODS = [
    { value: '30', label: 'Last 30 days' },
    { value: '90', label: 'Last 90 days' },
    { value: '365', label: 'Last 12 months' },
    { value: '0', label: 'All time' }
];

const VIEW_KEY = 'cc.orders.view';
const PERIOD_KEY = 'cc.orders.days';

function statusStyle(status) {
    const [color, tint] = STATUS_COLORS[status] || ['#0f7c8c', '#e3f4f6'];
    return `--status-color:${color};--status-tint:${tint};`;
}

function plural(n, word) {
    return `${n} ${word}${n === 1 ? '' : 's'}`;
}

function readSetting(key, fallback) {
    try {
        return window.localStorage.getItem(key) || fallback;
    } catch (e) {
        return fallback;
    }
}

function writeSetting(key, value) {
    try {
        window.localStorage.setItem(key, value);
    } catch (e) {
        // storage unavailable; the choice still applies to this page
    }
}

export default class CareCoachOrders extends LightningElement {
    context;
    mode = 'psp';
    scope = 'all';
    days = '90';
    view = 'board';
    search = '';
    statusFilter = '';
    board;
    isLoading = true;
    error;
    selectedId;
    saving = false;
    actionError;
    trackingDraft = '';
    unsubscribe;
    keyHandler;

    connectedCallback() {
        this.mode = getStoredMode();
        this.view = readSetting(VIEW_KEY, 'board') === 'list' ? 'list' : 'board';
        this.days = readSetting(PERIOD_KEY, '90');
        this.unsubscribe = onModeChange((mode) => {
            this.mode = mode;
            this.load();
        });
        this.keyHandler = (event) => {
            if (event.key === 'Escape' && this.selectedId) this.closeDetail();
        };
        window.addEventListener('keydown', this.keyHandler);
        this.init();
    }

    disconnectedCallback() {
        if (this.unsubscribe) this.unsubscribe();
        window.removeEventListener('keydown', this.keyHandler);
    }

    async init() {
        try {
            this.context = await getContext();
            this.scope = this.context.hasFullAccess ? (this.context.isSupervisor ? getStoredScope('all') : 'mine') : 'all';
        } catch (e) {
            this.error = reduceError(e);
        }
        this.load();
    }

    async load() {
        this.isLoading = true;
        this.error = undefined;
        try {
            this.board = await getOrders({ mode: this.mode, scope: this.scope, days: Number(this.days) || null });
        } catch (e) {
            this.error = reduceError(e);
        } finally {
            this.isLoading = false;
        }
    }

    handleModeChange(event) {
        storeMode(event.detail);
    }

    handleScopeChange(event) {
        this.scope = event.detail;
        storeScope(this.scope);
        this.load();
    }

    handleSearch(event) {
        this.search = event.target.value || '';
    }

    handlePeriod(event) {
        this.days = event.detail.value;
        writeSetting(PERIOD_KEY, this.days);
        this.load();
    }

    handleView(event) {
        this.view = event.currentTarget.dataset.view;
        writeSetting(VIEW_KEY, this.view);
    }

    handleChip(event) {
        const value = event.currentTarget.dataset.value;
        this.statusFilter = this.statusFilter === value ? '' : value;
    }

    handleRefresh() {
        this.load();
    }

    get periodOptions() {
        return PERIODS;
    }

    get isBoard() {
        return this.view === 'board';
    }

    get listBtnClass() {
        return this.view === 'list' ? 'is-active' : '';
    }

    get boardBtnClass() {
        return this.view === 'board' ? 'is-active' : '';
    }

    get masked() {
        return this.board ? this.board.masked : this.mode === 'company';
    }

    get subtitle() {
        return this.masked
            ? 'De-identified order pipeline with line items and delivery promises'
            : 'Every patient order with its line items, promise date and care coach';
    }

    get money() {
        const code = (this.board && this.board.currencyCode) || 'USD';
        let fmt;
        try {
            fmt = new Intl.NumberFormat(undefined, { style: 'currency', currency: code, maximumFractionDigits: 0 });
        } catch (e) {
            fmt = new Intl.NumberFormat(undefined, { maximumFractionDigits: 0 });
        }
        return (value) => (value == null ? '—' : fmt.format(value));
    }

    get totals() {
        return (this.board && this.board.totals) || [];
    }

    get summary() {
        const money = this.money;
        let open = 0;
        let units = 0;
        let value = 0;
        let delivered = 0;
        this.totals.forEach((t) => {
            if (t.status !== 'Delivered' && t.status !== 'Cancelled') open += t.count;
            if (t.status === 'Delivered') delivered = t.count;
            if (t.status !== 'Cancelled') {
                units += t.units || 0;
                value += t.value || 0;
            }
        });
        const overdue = (this.board && this.board.overdueCount) || 0;
        return [
            { key: 'open', label: 'Open orders', value: open.toLocaleString(), cls: 'summary-card' },
            {
                key: 'overdue',
                label: 'Past promise date',
                value: overdue.toLocaleString(),
                cls: overdue ? 'summary-card is-alert' : 'summary-card'
            },
            { key: 'week', label: 'Promised in 7 days', value: ((this.board && this.board.dueThisWeek) || 0).toLocaleString(), cls: 'summary-card' },
            { key: 'delivered', label: 'Delivered', value: delivered.toLocaleString(), cls: 'summary-card' },
            { key: 'units', label: 'Units ordered', value: units.toLocaleString(), cls: 'summary-card' },
            { key: 'value', label: 'Order value', value: money(value), cls: 'summary-card' }
        ];
    }

    get statusChips() {
        const all = this.totals.reduce((sum, t) => sum + t.count, 0);
        const chips = [
            {
                key: 'all',
                value: '',
                label: 'All',
                count: all.toLocaleString(),
                cls: !this.statusFilter ? 'chip is-active' : 'chip',
                style: '--status-color:#0f7c8c;--status-tint:#e3f4f6;'
            }
        ];
        this.totals.forEach((t) => {
            chips.push({
                key: t.status,
                value: t.status,
                label: t.status,
                count: t.count.toLocaleString(),
                cls: this.statusFilter === t.status ? 'chip is-active' : 'chip',
                style: statusStyle(t.status)
            });
        });
        return chips;
    }

    decorate(o) {
        const money = this.money;
        const items = (o.items || []).map((i) => ({
            ...i,
            key: i.id,
            qtyLabel: `${i.quantity} ×`,
            unitLabel: i.unit || '',
            priceLabel: i.unitPrice == null ? '—' : money(i.unitPrice),
            totalLabel: i.lineTotal == null ? '—' : money(i.lineTotal),
            typeClass: `item-type type-${String(i.itemType || 'other').toLowerCase().replace(/\s+/g, '-')}`
        }));
        const preview = items.slice(0, 3);
        const more = items.length - preview.length;
        let promiseLabel = o.promisedDate ? formatDate(o.promisedDate) : 'No promise date';
        let promiseClass = 'promise';
        if (o.daysToPromise != null) {
            if (o.overdue) {
                promiseLabel = `Overdue ${plural(-o.daysToPromise, 'day')}`;
                promiseClass = 'promise is-overdue';
            } else if (o.daysToPromise === 0) {
                promiseLabel = 'Due today';
                promiseClass = 'promise is-soon';
            } else {
                promiseLabel = `Due in ${plural(o.daysToPromise, 'day')}`;
                promiseClass = o.daysToPromise <= 2 ? 'promise is-soon' : 'promise';
            }
        }
        const units = o.totalUnits || 0;
        return {
            ...o,
            items,
            preview,
            hasMoreItems: more > 0,
            moreLabel: more > 0 ? `+${plural(more, 'more item')}` : '',
            hasItems: items.length > 0,
            itemsSummary: items.map((i) => `${i.quantity} × ${i.name}`).join(', '),
            avatar: initialsAvatar(o.patientName),
            avatarClass: this.masked ? 'cc-avatar cc-avatar_masked' : 'cc-avatar',
            coachLabel: o.coachName || 'Unassigned',
            coachAvatar: initialsAvatar(o.coachName || '?'),
            statusStyle: statusStyle(o.status),
            isUrgent: o.priority === 'Urgent',
            orderDateLabel: formatDate(o.orderDate) || '—',
            promisedDateLabel: o.promisedDate ? formatDate(o.promisedDate) : '—',
            deliveredLabel: o.deliveryDate ? formatDate(o.deliveryDate) : '—',
            promiseLabel,
            promiseClass,
            unitsLabel: plural(units, 'unit'),
            linesLabel: plural(o.lineCount || items.length, 'line'),
            totalLabel: money(o.orderTotal),
            channelLabel: o.channel || '—',
            locationLabel: o.channel === 'Home Delivery' ? o.deliveryAddress || 'Home delivery' : o.pharmacy || o.channel || '—',
            rowClass: o.overdue ? 'row-overdue' : ''
        };
    }

    get filteredOrders() {
        const q = this.search.trim().toLowerCase();
        return ((this.board && this.board.orders) || []).filter((o) => {
            if (this.statusFilter && o.status !== this.statusFilter) return false;
            if (!q) return true;
            const haystack = [o.orderNumber, o.patientName, o.patientNumber, o.productName, o.coachName, o.trackingNumber, o.pharmacy]
                .concat((o.items || []).map((i) => i.name))
                .filter(Boolean)
                .join(' ')
                .toLowerCase();
            return haystack.includes(q);
        });
    }

    get rows() {
        return this.filteredOrders.map((o) => this.decorate(o));
    }

    get boardColumns() {
        const rows = this.rows;
        const totals = new Map(this.totals.map((t) => [t.status, t]));
        return Object.keys(STATUS_COLORS)
            .filter((s) => !this.statusFilter || this.statusFilter === s)
            .map((s) => {
                const items = rows.filter((r) => r.status === s);
                const t = totals.get(s);
                const count = t ? t.count : items.length;
                return {
                    status: s,
                    style: statusStyle(s),
                    count: count.toLocaleString(),
                    items,
                    isEmpty: items.length === 0,
                    moreLabel: count > items.length && !this.search ? `Showing ${items.length} of ${count.toLocaleString()}` : ''
                };
            });
    }

    get boardClass() {
        return this.statusFilter ? 'board board-single' : 'board';
    }

    get showEmpty() {
        return !this.isLoading && !this.error && this.rows.length === 0;
    }

    get showCoachColumn() {
        return this.scope === 'all';
    }

    get countLabel() {
        const shown = this.rows.length;
        const total = this.totals.reduce((sum, t) => sum + (!this.statusFilter || t.status === this.statusFilter ? t.count : 0), 0);
        return shown < total ? `Showing ${shown.toLocaleString()} of ${total.toLocaleString()} orders` : plural(shown, 'order');
    }

    // ------------------------------------------------------------ detail

    handleOpen(event) {
        this.selectedId = event.currentTarget.dataset.id;
        this.actionError = undefined;
        this.trackingDraft = '';
    }

    closeDetail() {
        this.selectedId = undefined;
    }

    stop(event) {
        event.stopPropagation();
    }

    get selected() {
        const raw = ((this.board && this.board.orders) || []).find((o) => o.id === this.selectedId);
        return raw ? this.decorate(raw) : null;
    }

    get nextStep() {
        const o = this.selected;
        return o && this.board && this.board.canEdit ? NEXT_STEP[o.status] || null : null;
    }

    get canCancel() {
        const o = this.selected;
        return !!(o && this.board && this.board.canEdit && o.status !== 'Delivered' && o.status !== 'Cancelled');
    }

    get showActions() {
        return !!(this.nextStep || this.canCancel);
    }

    get needsTracking() {
        const step = this.nextStep;
        return !!(step && step.status === 'Dispatched' && this.selected.channel === 'Home Delivery');
    }

    handleTracking(event) {
        this.trackingDraft = event.target.value;
    }

    handleAdvance() {
        this.changeStatus(this.nextStep.status);
    }

    handleCancelOrder() {
        this.changeStatus('Cancelled');
    }

    async changeStatus(status) {
        this.saving = true;
        this.actionError = undefined;
        try {
            const updated = await updateOrderStatus({
                orderId: this.selectedId,
                status,
                trackingNumber: this.trackingDraft || null
            });
            this.applyUpdate(updated);
            this.trackingDraft = '';
        } catch (e) {
            this.actionError = reduceError(e);
        } finally {
            this.saving = false;
        }
    }

    applyUpdate(updated) {
        if (!updated || !this.board) return;
        const before = this.board.orders.find((o) => o.id === updated.id);
        const orders = this.board.orders.map((o) => (o.id === updated.id ? updated : o));
        const totals = this.board.totals.map((t) => {
            if (!before || before.status === updated.status) return t;
            if (t.status === before.status) {
                return { ...t, count: Math.max(0, t.count - 1), units: t.units - (before.totalUnits || 0), value: t.value - (before.orderTotal || 0) };
            }
            if (t.status === updated.status) {
                return { ...t, count: t.count + 1, units: t.units + (updated.totalUnits || 0), value: t.value + (updated.orderTotal || 0) };
            }
            return t;
        });
        let overdueCount = this.board.overdueCount;
        if (before && before.overdue && !updated.overdue) overdueCount = Math.max(0, overdueCount - 1);
        this.board = { ...this.board, orders, totals, overdueCount };
    }
}