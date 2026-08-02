import { LightningElement, track } from 'lwc';

export default class AdminConsole extends LightningElement {
    @track showModal = false;
    @track modalTitle = '';
    @track selectedComponent = '';
    @track ordersManagementView = 'menu';
    @track childModalOpen = false;
    @track searchTerm = '';

    adminCards = [
        {
            id: 'pricing-manager',
            accent: 'blue',
            title: 'Pricing Manager',
            description: 'Configure price lists, discount rules, and approval limits.',
            icon: 'utility:money',
            componentName: 'priceListDiscountRuleManager'
        },
        {
            id: 'plan-manager',
            accent: 'teal',
            title: 'Plan Manager',
            description: 'Manage plan cycles, sales targets, and performance periods.',
            icon: 'utility:chart',
            componentName: 'planCycleManager'
        },
        {
            id: 'orders-management',
            accent: 'orange',
            title: 'Orders Management',
            description: 'Import, review, and manage customer orders at scale.',
            icon: 'utility:cart',
            componentName: 'ordersManagement'
        },
        {
            id: 'salary-admin',
            accent: 'indigo',
            title: 'Salary',
            description: 'Manage salary formulas, working hours, and employee rules.',
            icon: 'utility:moneybag',
            componentName: 'salaryAdminManager'
        }
    ];

    get moduleCount() {
        return this.adminCards.length;
    }

    get cardsView() {
        const term = (this.searchTerm || '').trim().toLowerCase();
        const filtered = term
            ? this.adminCards.filter(c =>
                c.title.toLowerCase().includes(term) ||
                c.description.toLowerCase().includes(term))
            : this.adminCards;
        return filtered.map(c => ({
            ...c,
            cardClass: `admin-card admin-card--${c.accent}`,
            ariaLabel: `${c.title}. ${c.description}`
        }));
    }

    get hasResults() {
        return this.cardsView.length > 0;
    }

    handleSearch(event) {
        this.searchTerm = event.target.value || '';
    }

    handleCardClick(event) {
        if (event.key && event.key !== 'Enter' && event.key !== ' ') {
            return;
        }
        if (event.key) {
            event.preventDefault();
        }
        const cardId = event.currentTarget.dataset.cardId;
        const card = this.adminCards.find(c => c.id === cardId);

        if (card) {
            this.selectedComponent = card.componentName;
            this.modalTitle = card.title;
            if (card.id === 'orders-management') {
                this.ordersManagementView = 'menu';
            }
            this.showModal = true;
        }
    }

    closeModal() {
        this.showModal = false;
        this.selectedComponent = '';
        this.modalTitle = '';
        this.ordersManagementView = 'menu';
        this.childModalOpen = false;
    }

    handleChildModalOpen() {
        this.childModalOpen = true;
    }

    handleChildModalClose() {
        this.childModalOpen = false;
    }

    get adminConsoleBackdropClass() {
        const base = 'admin-console-backdrop';
        return this.childModalOpen ? base + ' backdrop-hidden' : base;
    }

    get isPricingManager() {
        return this.selectedComponent === 'priceListDiscountRuleManager';
    }

    get isPlanManager() {
        return this.selectedComponent === 'planCycleManager';
    }

    get isOrdersManagement() {
        return this.selectedComponent === 'ordersManagement';
    }

    get isOrdersManagementMenu() {
        return this.isOrdersManagement && this.ordersManagementView === 'menu';
    }

    get isOrdersManagementMassImport() {
        return this.isOrdersManagement && this.ordersManagementView === 'massImport';
    }

    get isSalaryAdmin() {
        return this.selectedComponent === 'salaryAdminManager';
    }

    handleOrdersManagementItemClick(event) {
        const view = event.currentTarget.dataset.view;
        if (view === 'massImport') {
            this.ordersManagementView = 'massImport';
        }
    }

    handleOrdersManagementBack() {
        this.ordersManagementView = 'menu';
    }
}