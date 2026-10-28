import { LightningElement, wire } from 'lwc';
import { CurrentPageReference } from 'lightning/navigation';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import getContext from '@salesforce/apex/CareCoachAccess.getContext';
import getScripts from '@salesforce/apex/CareCoachCatalogController.getScripts';
import getScript from '@salesforce/apex/CareCoachCatalogController.getScript';
import markHelpful from '@salesforce/apex/CareCoachCatalogController.markHelpful';
import getFilterOptions from '@salesforce/apex/CareCoachPatientService.getFilterOptions';
import { formatDate, formatDateTime, reduceError, getStoredMode, storeMode, onModeChange } from 'c/careCoachUtils';

const CATEGORIES = ['Disease education', 'Administration', 'Side effects', 'Adherence', 'Storage & handling', 'Access & reimbursement'];

export default class CareCoachKnowledge extends LightningElement {
    context;
    mode = 'psp';
    scripts = [];
    products = [];
    productId = '';
    category = '';
    search = '';
    publishedOnly = true;
    selected;
    isLoading = true;
    isLoadingArticle = false;
    error;
    voted = {};
    searchTimer;
    unsubscribe;
    initialized = false;
    pendingScriptId;

    @wire(CurrentPageReference)
    handlePageRef(ref) {
        const state = (ref && ref.state) || {};
        if (state.c__scriptId) this.pendingScriptId = state.c__scriptId;
        const productId = state.c__productId;
        const productChanged = productId !== undefined && productId !== this.productId;
        if (productChanged) this.productId = productId || '';
        if (!this.initialized) return;
        if (productChanged) {
            this.load();
            return;
        }
        if (state.c__scriptId) {
            const id = this.pendingScriptId;
            this.pendingScriptId = undefined;
            this.openScript(id);
        }
    }

    connectedCallback() {
        this.mode = getStoredMode();
        this.unsubscribe = onModeChange((mode) => {
            this.mode = mode;
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
            this.products = opts.products;
        } catch (e) {
            this.error = reduceError(e);
        }
        this.initialized = true;
        this.load();
    }

    async load() {
        this.isLoading = true;
        this.error = undefined;
        try {
            this.scripts = await getScripts({
                search: this.search || null,
                productId: this.productId || null,
                category: this.category || null,
                publishedOnly: this.publishedOnly
            });
            if (this.pendingScriptId) {
                const id = this.pendingScriptId;
                this.pendingScriptId = undefined;
                this.openScript(id);
            } else if (this.scripts.length && (!this.selected || !this.scripts.find((s) => s.id === this.selected.id))) {
                this.openScript(this.scripts[0].id);
            } else if (!this.scripts.length) {
                this.selected = undefined;
            }
        } catch (e) {
            this.error = reduceError(e);
        } finally {
            this.isLoading = false;
        }
    }

    async openScript(id) {
        this.isLoadingArticle = true;
        try {
            this.selected = await getScript({ scriptId: id });
        } catch (e) {
            this.error = reduceError(e);
        } finally {
            this.isLoadingArticle = false;
        }
    }

    handleModeChange(event) {
        storeMode(event.detail);
    }

    get productOptions() {
        return [{ label: 'All products', value: '' }, ...this.products];
    }

    get categoryOptions() {
        return [{ label: 'All categories', value: '' }, ...CATEGORIES.map((c) => ({ label: c, value: c }))];
    }

    handleSearch(event) {
        const value = event.target.value;
        clearTimeout(this.searchTimer);
        // eslint-disable-next-line @lwc/lwc/no-async-operation
        this.searchTimer = setTimeout(() => {
            this.search = value;
            this.load();
        }, 300);
    }

    handleProduct(event) {
        this.productId = event.detail.value;
        this.load();
    }

    handleCategory(event) {
        this.category = event.detail.value;
        this.load();
    }

    handlePublished(event) {
        this.publishedOnly = event.target.checked;
        this.load();
    }

    get rows() {
        return this.scripts.map((s) => ({
            ...s,
            cls: this.selected && this.selected.id === s.id ? 'script is-active' : 'script',
            validClass: s.validationStatus === 'Validated' ? 'cc-pill cc-pill_positive' : 'cc-pill',
            meta: [s.productName, s.category, s.language].filter(Boolean).join(' · ')
        }));
    }

    get countLabel() {
        return `${this.scripts.length} ${this.scripts.length === 1 ? 'script' : 'scripts'}`;
    }

    get isEmpty() {
        return !this.isLoading && this.scripts.length === 0;
    }

    handleOpen(event) {
        this.openScript(event.currentTarget.dataset.id);
    }

    get article() {
        if (!this.selected) return null;
        const s = this.selected;
        return {
            ...s,
            details: [
                { key: 'num', label: 'Script number', value: s.scriptNumber },
                { key: 'pub', label: 'Publication status', value: s.publicationStatus },
                { key: 'val', label: 'Validation status', value: s.validationStatus },
                { key: 'lang', label: 'Language', value: s.language },
                { key: 'prod', label: 'Product', value: s.productName },
                { key: 'ta', label: 'Therapy area', value: s.therapyArea },
                { key: 'pdate', label: 'Published', value: formatDate(s.publishedDate) },
                { key: 'mod', label: 'Last modified', value: formatDateTime(s.lastModified) }
            ].filter((d) => d.value),
            hasVoted: !!this.voted[s.id]
        };
    }

    get canVote() {
        return this.context && this.context.hasFullAccess && this.article && !this.article.hasVoted;
    }

    async handleHelpful() {
        const id = this.selected.id;
        try {
            const count = await markHelpful({ scriptId: id });
            this.voted = { ...this.voted, [id]: true };
            this.selected = { ...this.selected, helpful: count };
            this.dispatchEvent(new ShowToastEvent({ title: 'Thanks for the feedback', variant: 'success' }));
        } catch (e) {
            this.dispatchEvent(new ShowToastEvent({ title: 'Could not save feedback', message: reduceError(e), variant: 'error' }));
        }
    }
}