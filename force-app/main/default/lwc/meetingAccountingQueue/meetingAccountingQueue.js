import { LightningElement, api } from 'lwc';
import getAccountingQueue from '@salesforce/apex/MeetingLifecycleController.getAccountingQueue';
import { dateLabel, dayParts, errorMessage, money, pillClass } from 'c/meetingUtils';

const FILTERS = [
    { value: 'topay', label: 'To pay', statuses: ['In Accounting', 'Partial Paid'] },
    { value: 'returned', label: 'Sent back', statuses: ['Returned to Business'] },
    { value: 'paid', label: 'Paid', statuses: ['Paid'] }
];

export default class MeetingAccountingQueue extends LightningElement {
    @api currencyCode = 'EGP';
    @api embedded = false;

    rows = [];
    loading = true;
    error;
    filter = 'topay';
    term = '';
    openId;

    connectedCallback() {
        this.load();
    }

    @api
    async refresh() {
        await this.load();
    }

    async load() {
        this.error = null;
        try {
            this.rows = (await getAccountingQueue()) || [];
        } catch (e) {
            this.error = errorMessage(e);
        } finally {
            this.loading = false;
        }
    }

    get showSpinner() {
        return this.loading && !this.rows.length;
    }

    get filters() {
        return FILTERS.map((f) => ({
            ...f,
            count: this.rows.filter((r) => f.statuses.includes(r.paymentStatus)).length,
            cls: `mx-chip ${f.value === this.filter ? 'mx-chip_active' : ''}`
        }));
    }

    get toPay() {
        return this.rows.filter((r) => ['In Accounting', 'Partial Paid'].includes(r.paymentStatus));
    }

    get kpis() {
        const outstanding = this.toPay.reduce((sum, r) => sum + Number(r.remainingAmount || 0), 0);
        return [
            { key: 'count', label: 'Waiting for payment', value: String(this.toPay.length) },
            { key: 'outstanding', label: 'Outstanding', value: money(outstanding, this.currencyCode) },
            {
                key: 'partial',
                label: 'Partly paid',
                value: String(this.rows.filter((r) => r.paymentStatus === 'Partial Paid').length)
            },
            {
                key: 'returned',
                label: 'Sent back',
                value: String(this.rows.filter((r) => r.paymentStatus === 'Returned to Business').length)
            }
        ];
    }

    get visibleRows() {
        const active = FILTERS.find((f) => f.value === this.filter);
        const term = (this.term || '').toLowerCase();
        return this.rows
            .filter((r) => active.statuses.includes(r.paymentStatus))
            .filter(
                (r) =>
                    !term ||
                    [r.title, r.ownerName, r.name, r.department, r.venue].some((v) => v && v.toLowerCase().includes(term))
            )
            .map((r) => {
                const isActual = r.actualCost !== null && r.actualCost !== undefined;
                const due = isActual ? r.actualCost : r.depositAmount;
                const paidPct = due ? Math.min(100, Math.round(((r.paidAmount || 0) / due) * 100)) : 0;
                const day = dayParts(r.startDateTime);
                return {
                    ...r,
                    key: r.id,
                    day: day.day,
                    month: day.month,
                    dateText: dateLabel(r.startDateTime),
                    dueLabel: isActual ? 'Actual cost' : 'Deposit',
                    dueText: money(due, this.currencyCode),
                    paidText: money(r.paidAmount || 0, this.currencyCode),
                    remainingText: money(r.remainingAmount || 0, this.currencyCode),
                    pill: pillClass(r.paymentStatus),
                    barStyle: `width:${paidPct}%`
                };
            });
    }

    get hasRows() {
        return this.visibleRows.length > 0;
    }

    get showEmpty() {
        return !this.loading && !this.error && !this.hasRows;
    }

    get showHero() {
        return !this.embedded;
    }

    get isOpen() {
        return !!this.openId;
    }

    handleFilter(event) {
        this.filter = event.currentTarget.dataset.value;
    }

    handleSearch(event) {
        this.term = event.target.value;
    }

    handleOpen(event) {
        this.openId = event.currentTarget.dataset.id;
    }

    handleClose() {
        this.openId = null;
        this.load();
    }

    handleChanged() {
        this.load();
        this.dispatchEvent(new CustomEvent('changed'));
    }
}
