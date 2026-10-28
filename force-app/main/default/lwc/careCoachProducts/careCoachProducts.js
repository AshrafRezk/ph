import { LightningElement } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';
import getContext from '@salesforce/apex/CareCoachAccess.getContext';
import getProducts from '@salesforce/apex/CareCoachCatalogController.getProducts';
import { PRODUCT_COLORS, reduceError, getStoredMode, storeMode, onModeChange, getStoredScope, storeScope } from 'c/careCoachUtils';

const THERAPY_ICONS = {
    Neurology: 'utility:knowledge_base',
    Oncology: 'utility:shield',
    Endocrinology: 'utility:trending'
};

export default class CareCoachProducts extends NavigationMixin(LightningElement) {
    context;
    mode = 'psp';
    scope = 'all';
    groups = [];
    isLoading = true;
    error;
    unsubscribe;

    connectedCallback() {
        this.mode = getStoredMode();
        this.unsubscribe = onModeChange((mode) => {
            this.mode = mode;
        });
        this.init();
    }

    disconnectedCallback() {
        if (this.unsubscribe) this.unsubscribe();
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
            this.groups = await getProducts({ scope: this.scope });
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

    get subtitle() {
        return this.scope === 'mine'
            ? 'Programme products and your patients on each therapy'
            : 'Programme products, patient mix and orders this month';
    }

    get summary() {
        let products = 0;
        let patients = 0;
        let fresh = 0;
        let units = 0;
        this.groups.forEach((g) =>
            g.products.forEach((p) => {
                products += 1;
                patients += p.totalPatients;
                fresh += p.newThisMonth;
                units += p.unitsThisMonth;
            })
        );
        return [
            { key: 'ta', label: 'Therapy areas', value: this.groups.length },
            { key: 'prod', label: 'Products', value: products },
            { key: 'pat', label: 'Patients', value: patients.toLocaleString() },
            { key: 'new', label: 'New this month', value: fresh.toLocaleString() },
            { key: 'units', label: 'Units ordered (MTD)', value: units.toLocaleString() }
        ];
    }

    get decoratedGroups() {
        let colorIdx = 0;
        return this.groups.map((g) => ({
            ...g,
            icon: THERAPY_ICONS[g.therapyArea] || 'utility:product',
            count: g.products.length,
            products: g.products.map((p) => {
                const color = PRODUCT_COLORS[colorIdx++ % PRODUCT_COLORS.length];
                const total = p.totalPatients || 1;
                return {
                    ...p,
                    hasImage: !!p.imageUrl,
                    monogram: (p.name || '?').substring(0, 2).toUpperCase(),
                    heroStyle: `--product-color:${color};`,
                    ongoingStyle: `width:${(p.ongoing * 100) / total}%;`,
                    pendingStyle: `width:${(p.pending * 100) / total}%;`,
                    droppedStyle: `width:${(p.dropped * 100) / total}%;`,
                    retention: p.ongoing + p.dropped ? `${Math.round((p.ongoing * 100) / (p.ongoing + p.dropped))}%` : '—'
                };
            })
        }));
    }

    get isEmpty() {
        return !this.isLoading && this.groups.length === 0;
    }

    handlePatients(event) {
        this[NavigationMixin.Navigate]({
            type: 'standard__navItemPage',
            attributes: { apiName: 'Care_Coach_Patients' },
            state: { c__productId: event.currentTarget.dataset.id }
        });
    }

    handleScripts(event) {
        this[NavigationMixin.Navigate]({
            type: 'standard__navItemPage',
            attributes: { apiName: 'Care_Coach_Knowledge' },
            state: { c__productId: event.currentTarget.dataset.id }
        });
    }
}