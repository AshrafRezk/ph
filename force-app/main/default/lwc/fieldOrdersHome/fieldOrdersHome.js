import { LightningElement, api, track } from 'lwc';
import getMyOrders from '@salesforce/apex/FieldOrderService.getMyOrders';
import getOrdersForAccount from '@salesforce/apex/FieldOrderService.getOrdersForAccount';
import { isFieldFeatureEnabled, loadFieldFeatures } from 'c/fieldFeatureFlags';

const FILTERS = [
    { value: 'all', label: 'All' },
    { value: 'draft', label: 'Drafts' },
    { value: 'waiting', label: 'Waiting' },
    { value: 'finance', label: 'Finance' },
    { value: 'done', label: 'Done' }
];

export default class FieldOrdersHome extends LightningElement {
    @track rows = [];
    isLoading = true;
    errorMessage;
    featureEnabled = true;
    filter = 'all';
    search = '';
    _accountId;
    _booted = false;

    @api visitId;
    @api accountName;
    @api disabled = false;

    @api
    get accountId() {
        return this._accountId || null;
    }
    set accountId(value) {
        const next = value || null;
        if (next === this._accountId) {
            return;
        }
        this._accountId = next;
        if (this._booted && this.featureEnabled) {
            void this.refresh();
        }
    }

    connectedCallback() {
        void this.bootstrap();
    }

    get isAccountScope() {
        return Boolean(this._accountId);
    }

    get showFeatureOff() {
        return this._booted && !this.featureEnabled && this.isAccountScope;
    }

    get heroTitle() {
        return this.isAccountScope ? this.accountName || 'This account' : 'Pharmacy orders';
    }

    get heroText() {
        return this.isAccountScope
            ? 'Same order path as the Orders tab. This account is already filled in.'
            : 'Send an order and see who has it.';
    }

    get searchPlaceholder() {
        return this.isAccountScope ? 'Search an order number' : 'Search a pharmacy or an order number';
    }

    get sheetSource() {
        return this.isAccountScope ? 'Visit' : 'Home';
    }

    get filters() {
        return FILTERS.map((item) => {
            const count = this.rows.filter((row) => matchesFilter(row, item.value)).length;
            return {
                ...item,
                count,
                selected: this.filter === item.value ? 'true' : 'false',
                className: `filter${this.filter === item.value ? ' is-on' : ''}`
            };
        });
    }

    get visibleRows() {
        const term = this.search.trim().toLowerCase();
        return this.rows.filter((row) => {
            if (!matchesFilter(row, this.filter)) {
                return false;
            }
            if (!term) {
                return true;
            }
            return `${row.accountName} ${row.name}`.toLowerCase().includes(term);
        });
    }

    get hasVisible() {
        return !this.isLoading && this.visibleRows.length > 0;
    }

    get showEmpty() {
        return !this.isLoading && !this.errorMessage && this.visibleRows.length === 0;
    }

    get emptyTitle() {
        return this.rows.length ? 'Nothing in this view' : 'No orders yet';
    }

    get emptyText() {
        if (this.rows.length) {
            return 'Try another filter, or clear the search.';
        }
        return this.isAccountScope
            ? 'Start an order for this account. The account stays filled in.'
            : 'Start an order for a pharmacy. You can also start one during a visit.';
    }

    async bootstrap() {
        await loadFieldFeatures();
        this.featureEnabled = isFieldFeatureEnabled('orders');
        this._booted = true;
        if (!this.featureEnabled) {
            this.isLoading = false;
            return;
        }
        await this.refresh();
    }

    async refresh() {
        const requestId = (this._requestId || 0) + 1;
        this._requestId = requestId;
        const accountId = this._accountId;
        this.isLoading = true;
        this.errorMessage = undefined;
        try {
            const data = accountId
                ? await getOrdersForAccount({ accountId })
                : await getMyOrders({ limitSize: 50 });
            if (this._requestId !== requestId) {
                return;
            }
            this.rows = (data || []).map(presentOrder);
        } catch (error) {
            if (this._requestId !== requestId) {
                return;
            }
            this.errorMessage = error?.body?.message || error?.message || 'Unable to load orders.';
            this.rows = [];
        } finally {
            if (this._requestId === requestId) {
                this.isLoading = false;
            }
        }
    }

    handleFilter(event) {
        this.filter = event.currentTarget.dataset.value;
    }

    handleSearch(event) {
        this.search = event.target.value || '';
    }

    handleNew() {
        if (this.disabled) {
            return;
        }
        this.template.querySelector('c-field-order-sheet')?.openSheet({
            source: this.sheetSource,
            accountId: this._accountId,
            visitId: this.visitId
        });
    }

    handleCreated() {
        this.refresh();
    }

    handleSheetClose() {
        // The sheet closes itself.
    }
}

const PATH = [
    { key: 'rep', label: 'Rep' },
    { key: 'dm', label: 'Manager' },
    { key: 'nam', label: 'National' },
    { key: 'bu', label: 'Business unit' },
    { key: 'yasser', label: 'Yasser' },
    { key: 'finance', label: 'Finance' },
    { key: 'goods', label: 'Goods' },
    { key: 'collect', label: 'Collection' },
    { key: 'settle', label: 'Settled' }
];

const STATUS_INDEX = {
    Draft: 0,
    'Pending DM': 1,
    'Pending NAM': 2,
    'Pending BU': 3,
    'Pending Yasser': 4,
    'Pending Finance': 5,
    Approved: 6,
    'Goods Issued': 6,
    Collected: 7,
    Settled: 8,
    Rejected: 0
};

function matchesFilter(row, filter) {
    if (filter === 'draft') {
        return row.status === 'Draft';
    }
    if (filter === 'waiting') {
        return ['Pending DM', 'Pending NAM', 'Pending BU', 'Pending Yasser'].includes(row.status);
    }
    if (filter === 'finance') {
        return row.status === 'Pending Finance' || row.status === 'Approved';
    }
    if (filter === 'done') {
        return ['Goods Issued', 'Collected', 'Settled'].includes(row.status);
    }
    return true;
}

function presentOrder(row) {
    const current = row?.skipFullApproval ? 5 : STATUS_INDEX[row?.status] ?? 0;
    return {
        ...row,
        typeText: row.orderType === 'Distributor' ? 'Distributor' : 'Zeta Direct',
        statusText: statusText(row),
        statusClass: `pill ${statusTone(row)}`,
        waitingText: waitingText(row),
        path: PATH.map((step, index) => ({
            ...step,
            className: index < current ? 'step is-done' : index === current ? 'step is-now' : 'step'
        }))
    };
}

function statusText(row) {
    const labels = {
        Draft: 'Draft',
        'Pending DM': 'With your manager',
        'Pending NAM': 'With national',
        'Pending BU': 'With the business unit',
        'Pending Yasser': 'With Yasser',
        'Pending Finance': 'With finance',
        Approved: 'Approved',
        'Goods Issued': 'Goods sent',
        Collected: 'Collected',
        Settled: 'Settled',
        Rejected: 'Returned'
    };
    return labels[row?.status] || row?.statusLabel || 'Sent';
}

function statusTone(row) {
    if (row?.status === 'Rejected') {
        return 'is-bad';
    }
    if (row?.status === 'Settled' || row?.status === 'Collected' || row?.status === 'Goods Issued') {
        return 'is-good';
    }
    if (row?.status === 'Draft') {
        return 'is-quiet';
    }
    return 'is-live';
}

function waitingText(row) {
    if (row?.status === 'Draft') {
        return 'Not sent yet';
    }
    if (row?.status === 'Rejected') {
        return 'Sent back to you';
    }
    if (row?.skipFullApproval) {
        return '10 units or fewer. Finance is reviewing this.';
    }
    const waiting = {
        'Pending DM': 'Waiting for your manager',
        'Pending NAM': 'Waiting for the national manager',
        'Pending BU': 'Waiting for the business unit',
        'Pending Yasser': 'Waiting for Yasser',
        'Pending Finance': 'Waiting for finance',
        Approved: 'Approved. Goods come next.',
        'Goods Issued': 'Goods have been sent',
        Collected: 'Payment collected',
        Settled: 'Settled'
    };
    return waiting[row?.status] || 'In progress';
}
