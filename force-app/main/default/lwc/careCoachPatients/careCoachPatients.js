import { LightningElement, wire } from 'lwc';
import { CurrentPageReference, NavigationMixin } from 'lightning/navigation';
import getContext from '@salesforce/apex/CareCoachAccess.getContext';
import getPatients from '@salesforce/apex/CareCoachPatientService.getPatients';
import getFilterOptions from '@salesforce/apex/CareCoachPatientService.getFilterOptions';
import {
    STATUS_META,
    statusStyle,
    riskClass,
    formatRelative,
    formatDateTime,
    formatDate,
    reduceError,
    getStoredMode,
    storeMode,
    onModeChange,
    getStoredScope,
    storeScope,
    initialsAvatar
} from 'c/careCoachUtils';

const PAGE_SIZE = 50;
const BOARD_SIZE = 200;

export default class CareCoachPatients extends NavigationMixin(LightningElement) {
    context;
    options = { coaches: [], products: [], therapyAreas: [], statuses: [], adherence: [] };
    mode = 'psp';
    scope = 'mine';
    coachId = '';
    productId = '';
    therapyArea = '';
    adherence = '';
    status = '';
    statusGroup = '';
    search = '';
    view = 'list';
    rows = [];
    total = 0;
    statusCounts = {};
    masked = false;
    isLoading = true;
    error;
    selectedPatientId;
    ready = false;
    searchTimer;
    unsubscribe;
    pendingState;

    @wire(CurrentPageReference)
    handlePageRef(ref) {
        const state = (ref && ref.state) || {};
        this.pendingState = state;
        if (this.ready) this.applyState(state, true);
    }

    connectedCallback() {
        this.mode = getStoredMode();
        this.unsubscribe = onModeChange((mode) => {
            if (mode !== this.mode) {
                this.mode = mode;
                this.load(false);
            }
        });
        this.init();
    }

    disconnectedCallback() {
        if (this.unsubscribe) this.unsubscribe();
        clearTimeout(this.searchTimer);
    }

    async init() {
        try {
            const [ctx, opts] = await Promise.all([getContext(), getFilterOptions()]);
            this.context = ctx;
            this.options = opts;
            this.scope = ctx.hasFullAccess ? (ctx.isSupervisor ? getStoredScope(ctx.defaultScope) : 'mine') : 'all';
        } catch (e) {
            this.error = reduceError(e);
        }
        this.ready = true;
        this.applyState(this.pendingState || {}, false);
        this.load(false);
    }

    applyState(state, reload) {
        let changed = false;
        if (state.c__status !== undefined && state.c__status !== this.status) {
            this.status = state.c__status || '';
            this.statusGroup = '';
            changed = true;
        }
        if (state.c__group !== undefined && state.c__group !== this.statusGroup) {
            this.statusGroup = state.c__group || '';
            this.status = '';
            changed = true;
        }
        if (state.c__productId !== undefined && state.c__productId !== this.productId) {
            this.productId = state.c__productId || '';
            changed = true;
        }
        if (state.c__patientId) {
            this.selectedPatientId = state.c__patientId;
        }
        if (reload && changed) this.load(false);
    }

    async load(append) {
        this.isLoading = true;
        this.error = undefined;
        const filters = {
            mode: this.mode,
            scope: this.scope,
            coachId: this.coachId || null,
            productId: this.productId || null,
            therapyArea: this.therapyArea || null,
            adherence: this.adherence || null,
            status: this.status || null,
            statusGroup: this.statusGroup || null,
            search: this.search || null,
            limitSize: this.view === 'board' ? BOARD_SIZE : PAGE_SIZE,
            offsetSize: append ? this.rows.length : 0
        };
        try {
            const page = await getPatients({ filtersJson: JSON.stringify(filters) });
            this.masked = page.masked;
            this.total = page.total;
            this.statusCounts = page.statusCounts || {};
            this.rows = append ? [...this.rows, ...page.rows] : page.rows;
        } catch (e) {
            this.error = reduceError(e);
        } finally {
            this.isLoading = false;
        }
    }

    // ---------------------------------------------------------------- header

    get subtitle() {
        if (this.context && !this.context.hasFullAccess) return 'All programme patients (de-identified)';
        return this.scope === 'mine' ? 'Patients assigned to you' : 'All patients across care coaches';
    }

    handleModeChange(event) {
        storeMode(event.detail);
    }

    handleScopeChange(event) {
        this.scope = event.detail;
        storeScope(this.scope);
        if (this.scope === 'mine') this.coachId = '';
        this.load(false);
    }

    handleCoachChange(event) {
        this.coachId = event.detail;
        this.load(false);
    }

    // ---------------------------------------------------------------- filters

    get productOptions() {
        return [{ label: 'All products', value: '' }, ...this.options.products];
    }

    get therapyOptions() {
        return [{ label: 'All therapy areas', value: '' }, ...this.options.therapyAreas];
    }

    get adherenceOptions() {
        return [{ label: 'Any adherence', value: '' }, ...this.options.adherence];
    }

    get searchPlaceholder() {
        return this.masked ? 'Search by patient number or initials' : 'Search name, phone or patient number';
    }

    handleSearch(event) {
        const value = event.target.value;
        clearTimeout(this.searchTimer);
        // eslint-disable-next-line @lwc/lwc/no-async-operation
        this.searchTimer = setTimeout(() => {
            this.search = value;
            this.load(false);
        }, 350);
    }

    handleFilter(event) {
        const field = event.target.dataset.field;
        this[field] = event.detail.value;
        this.load(false);
    }

    handleClearFilters() {
        this.productId = '';
        this.therapyArea = '';
        this.adherence = '';
        this.status = '';
        this.statusGroup = '';
        this.search = '';
        const input = this.template.querySelector('lightning-input.search');
        if (input) input.value = '';
        this.load(false);
    }

    get statusChips() {
        const all = Object.values(this.statusCounts).reduce((a, b) => a + b, 0);
        const chips = [
            {
                key: 'all',
                value: '',
                label: 'All',
                count: all,
                cls: !this.status && !this.statusGroup ? 'chip is-active' : 'chip',
                style: '--status-color:#0f7c8c;--status-tint:#e3f4f6;'
            }
        ];
        Object.keys(STATUS_META).forEach((s) => {
            const inGroup = this.statusGroup && (this.statusGroup === 'Dropped' ? s.startsWith('Dropped') : s.startsWith(this.statusGroup));
            chips.push({
                key: s,
                value: s,
                label: s,
                count: this.statusCounts[s] || 0,
                cls: this.status === s || inGroup ? 'chip is-active' : 'chip',
                style: statusStyle(s)
            });
        });
        return chips;
    }

    handleChip(event) {
        this.status = event.currentTarget.dataset.value;
        this.statusGroup = '';
        this.load(false);
    }

    // ---------------------------------------------------------------- view

    get isList() {
        return this.view === 'list';
    }

    get listBtnClass() {
        return this.view === 'list' ? 'is-active' : '';
    }

    get boardBtnClass() {
        return this.view === 'board' ? 'is-active' : '';
    }

    handleView(event) {
        const next = event.currentTarget.dataset.view;
        if (next !== this.view) {
            this.view = next;
            this.load(false);
        }
    }

    get showCoachColumn() {
        return this.scope === 'all';
    }

    get showContactColumn() {
        return !this.masked;
    }

    get decoratedRows() {
        return this.rows.map((p) => ({
            ...p,
            avatar: initialsAvatar(p.displayName),
            avatarClass: p.masked ? 'cc-avatar cc-avatar_masked' : 'cc-avatar',
            demo: [p.gender, p.age != null ? `${p.age} y` : null].filter(Boolean).join(' · '),
            statusStyle: statusStyle(p.status),
            riskClass: riskClass(p.adherence),
            riskLabel: p.adherence || '—',
            scoreLabel: p.riskScore != null ? p.riskScore : '—',
            lastCall: formatRelative(p.lastCallDate),
            lastCallTitle: formatDateTime(p.lastCallDate),
            nextCall: p.nextCallDate ? formatDateTime(p.nextCallDate) : '—',
            enrolled: formatDate(p.enrollmentDate),
            contact: p.mobile || p.phone || ''
        }));
    }

    get boardColumns() {
        const rows = this.decoratedRows;
        return Object.keys(STATUS_META).map((s) => {
            const items = rows.filter((r) => r.status === s);
            return {
                status: s,
                style: statusStyle(s),
                count: this.statusCounts[s] || 0,
                shown: items.length,
                items
            };
        });
    }

    get hasRows() {
        return this.rows.length > 0;
    }

    get showEmpty() {
        return !this.isLoading && !this.hasRows;
    }

    get hasMore() {
        return this.isList && this.rows.length < this.total;
    }

    get countLabel() {
        return `${this.rows.length.toLocaleString()} of ${this.total.toLocaleString()} patients`;
    }

    handleLoadMore() {
        this.load(true);
    }

    // ---------------------------------------------------------------- 360

    handleOpen(event) {
        this.selectedPatientId = event.currentTarget.dataset.id;
    }

    handleClose360() {
        this.selectedPatientId = undefined;
        this[NavigationMixin.Navigate](
            { type: 'standard__navItemPage', attributes: { apiName: 'Care_Coach_Patients' }, state: {} },
            true
        );
    }

    handleChanged() {
        this.load(false);
    }
}