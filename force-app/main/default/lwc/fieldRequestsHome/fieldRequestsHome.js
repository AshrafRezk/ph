import { LightningElement, api, track } from 'lwc';
import getMyOpenRequests from '@salesforce/apex/FieldRequestService.getMyOpenRequests';
import getRequestsForAccount from '@salesforce/apex/FieldRequestService.getRequestsForAccount';
import { isFieldFeatureEnabled, loadFieldFeatures } from 'c/fieldFeatureFlags';

const FILTERS = [
    { value: 'all', label: 'All' },
    { value: 'sample', label: 'Samples' },
    { value: 'medical', label: 'Medical' },
    { value: 'needs', label: 'Needs you' }
];

export default class FieldRequestsHome extends LightningElement {
    @track rows = [];
    isLoading = true;
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
        return this._booted && !this.featureEnabled;
    }

    get medicalFilterEnabled() {
        return isFieldFeatureEnabled('requests.medical');
    }

    get heroTitle() {
        return this.isAccountScope ? this.accountName || 'This account' : 'What an account needs';
    }

    get heroText() {
        return this.isAccountScope
            ? 'Same request types as the Requests tab. This account is already filled in.'
            : 'Ask for a sample, a device, or a medical answer.';
    }

    get searchPlaceholder() {
        return this.isAccountScope ? 'Search a request' : 'Search an account or a request';
    }

    get sheetSource() {
        return this.isAccountScope ? 'Visit' : 'Home';
    }

    get filters() {
        return FILTERS.filter((item) => item.value !== 'medical' || this.medicalFilterEnabled).map((item) => ({
            ...item,
            count: this.rows.filter((row) => matchesFilter(row, item.value)).length,
            selected: this.filter === item.value ? 'true' : 'false',
            className: `filter${this.filter === item.value ? ' is-on' : ''}`
        }));
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
            return `${row.accountName} ${row.summary} ${row.requestType}`.toLowerCase().includes(term);
        });
    }

    get hasVisible() {
        return !this.isLoading && this.visibleRows.length > 0;
    }

    get showEmpty() {
        return !this.isLoading && this.visibleRows.length === 0;
    }

    get emptyTitle() {
        return this.rows.length ? 'Nothing in this view' : 'No open requests';
    }

    get emptyText() {
        if (this.rows.length) {
            return 'Try another filter, or clear the search.';
        }
        return this.isAccountScope
            ? 'Start one for this account. The account stays filled in.'
            : 'Start one when an account needs a sample or an answer.';
    }

    async bootstrap() {
        await loadFieldFeatures();
        this.featureEnabled = isFieldFeatureEnabled('requests.enabled');
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
        try {
            const data = accountId
                ? await getRequestsForAccount({ accountId })
                : await getMyOpenRequests();
            if (this._requestId !== requestId) {
                return;
            }
            this.rows = (data || []).map((row) => ({
                ...row,
                summaryPreview: truncate(row.summary, 110),
                statusClass: statusClassFor(row),
                waitingText: waitingText(row)
            }));
        } catch (_error) {
            if (this._requestId !== requestId) {
                return;
            }
            this.rows = [];
        } finally {
            if (this._requestId !== requestId) {
                return;
            }
            this.isLoading = false;
            if (accountId) {
                this.dispatchEvent(
                    new CustomEvent('countchange', {
                        bubbles: true,
                        composed: true,
                        detail: { count: this.rows.length }
                    })
                );
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
        this.template.querySelector('c-field-request-sheet')?.openSheet({
            source: this.sheetSource,
            accountId: this._accountId,
            visitId: this.visitId
        });
    }

    handleCreated() {
        void this.refresh();
    }

    handleSheetClose() {
        // The sheet closes itself.
    }
}

function matchesFilter(row, filter) {
    if (filter === 'sample') {
        return row.requestType === 'Sample';
    }
    if (filter === 'medical') {
        return row.kind === 'Medical' || row.status === 'With Medical';
    }
    if (filter === 'needs') {
        return row.status === 'Needs You' || row.isLate;
    }
    return true;
}

function truncate(value, max) {
    const text = (value || '').trim();
    if (text.length <= max) {
        return text;
    }
    return `${text.slice(0, max - 1)}…`;
}

function statusClassFor(row) {
    let cls = 'pill';
    if (row.isLate || row.status === 'Needs You') {
        cls += ' is-bad';
    } else if (row.status === 'With Medical') {
        cls += ' is-live';
    }
    return cls;
}

function waitingText(row) {
    if (row.status === 'Needs You') {
        return 'Waiting for you';
    }
    if (row.status === 'With Medical' || row.kind === 'Medical') {
        return 'With medical';
    }
    if (row.requestType === 'Sample') {
        return 'Sample request, with your manager';
    }
    return 'With your manager';
}
