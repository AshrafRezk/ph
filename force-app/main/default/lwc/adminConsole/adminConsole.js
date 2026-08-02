import { LightningElement, track } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';

export default class AdminConsole extends NavigationMixin(LightningElement) {
    @track showModal = false;
    @track modalTitle = '';
    @track selectedComponent = '';
    @track searchTerm = '';

    adminCards = [
        {
            id: 'clm',
            accent: 'pink',
            title: 'CLM',
            description: 'Upload presentations, manage slides, and configure territory targeting.',
            icon: 'utility:screen',
            componentName: 'clmAdminConsole'
        },
        {
            id: 'rating-layouts',
            accent: 'orange',
            title: 'Rating Layouts',
            description: 'Design account, territory, and product rating forms with live preview.',
            icon: 'utility:rating',
            componentName: 'clmRatingLayoutEditor'
        },
        {
            id: 'coaching-management',
            accent: 'teal',
            title: 'Coaching Management',
            description: 'Browse coaching templates, create new templates, and open the template editor.',
            icon: 'utility:education',
            componentName: 'coachingTemplateManager'
        },
        {
            id: 'territory-management',
            accent: 'indigo',
            title: 'Territory Management',
            description: 'Manage product lines, edit territories, assign users, and create demo field force accounts.',
            icon: 'utility:target',
            componentName: 'territoryManagementConsole'
        },
        {
            id: 'bricks-management',
            accent: 'purple',
            title: 'Bricks Management',
            description: 'Define IQVIA IMS bricks, align them to territories, and manage pharmacy account membership.',
            icon: 'utility:location',
            componentName: 'bricksManagementConsole'
        },
        {
            id: 'products-manager',
            accent: 'green',
            title: 'Products Manager',
            description: 'Browse the product catalog by brand and align products to territory hierarchies.',
            icon: 'utility:product',
            componentName: 'productTerritoryManager'
        },
        {
            id: 'plan-manager',
            accent: 'teal',
            title: 'Plan Manager',
            description: 'Manage monthly plan cycles, review employee coverage, and copy plans between months.',
            icon: 'utility:chart',
            componentName: 'planCycleManager'
        },
        {
            id: 'sales-data',
            accent: 'blue',
            title: 'Sales Data',
            description: 'Import IbnSina / Pharmaoverseas withdrawal CSVs and review loaded sell-out data.',
            icon: 'utility:upload',
            componentName: 'pharmacySalesDataAdmin'
        },
        {
            id: 'integrations-management',
            accent: 'slate',
            title: 'Integrations Management',
            description: 'Monitor IMS Health, OneKey, Maps, Mendix, and other external platform connectors.',
            icon: 'utility:link',
            componentName: 'integrationsManagementConsole'
        }
    ];

    get moduleCount() {
        return this.adminCards.length;
    }

    get cardsView() {
        const term = (this.searchTerm || '').trim().toLowerCase();
        const filtered = term
            ? this.adminCards.filter(
                  (card) =>
                      card.title.toLowerCase().includes(term) ||
                      card.description.toLowerCase().includes(term)
              )
            : this.adminCards;
        return filtered.map((card) => ({
            ...card,
            cardClass: `admin-card admin-card--${card.accent}`,
            ariaLabel: `${card.title}. ${card.description}`
        }));
    }

    get hasResults() {
        return this.cardsView.length > 0;
    }

    get isClmAdmin() {
        return this.selectedComponent === 'clmAdminConsole';
    }

    get isRatingLayouts() {
        return this.selectedComponent === 'clmRatingLayoutEditor';
    }

    get isCoachingManagement() {
        return this.selectedComponent === 'coachingTemplateManager';
    }

    get isTerritoryManagement() {
        return this.selectedComponent === 'territoryManagementConsole';
    }

    get isBricksManagement() {
        return this.selectedComponent === 'bricksManagementConsole';
    }

    get isProductsManager() {
        return this.selectedComponent === 'productTerritoryManager';
    }

    get isPlanManager() {
        return this.selectedComponent === 'planCycleManager';
    }

    get isSalesData() {
        return this.selectedComponent === 'pharmacySalesDataAdmin';
    }

    get isIntegrationsManagement() {
        return this.selectedComponent === 'integrationsManagementConsole';
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
        const card = this.adminCards.find((item) => item.id === cardId);
        if (!card) {
            return;
        }

        this.selectedComponent = card.componentName;
        this.modalTitle = card.title;
        this.showModal = true;
    }

    navigateToTab(apiName) {
        this[NavigationMixin.Navigate]({
            type: 'standard__navItemPage',
            attributes: { apiName }
        });
    }

    closeModal() {
        this.showModal = false;
        this.selectedComponent = '';
        this.modalTitle = '';
    }

    handleOpenAdminModule(event) {
        const { componentName, title } = event.detail || {};
        if (!componentName) {
            return;
        }
        this.selectedComponent = componentName;
        this.modalTitle = title || 'Admin Module';
    }
}
