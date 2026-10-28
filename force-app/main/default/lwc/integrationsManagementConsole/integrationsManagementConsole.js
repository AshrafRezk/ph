import { LightningElement, wire } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';
import MENDIX_LOGO from '@salesforce/resourceUrl/Mendix_Logo';
import getStatuses from '@salesforce/apex/IntegrationsStatusService.getStatuses';

const BASE_INTEGRATIONS = [
    {
        id: 'ims-health',
        name: 'IQVIA IMS Health',
        category: 'Market Data',
        description:
            'Brick-level sell-out, market share, and geographic alignment for territory planning.',
        icon: 'utility:chart',
        actionLabel: 'Manage Bricks',
        actionType: 'admin',
        adminComponent: 'bricksManagementConsole'
    },
    {
        id: 'onekey',
        name: 'OneKey Database',
        category: 'HCP / HCO Master',
        description:
            'Validate and enrich HCP and HCO records with OneKey identifiers and affiliations.',
        icon: 'utility:contact',
        actionLabel: null,
        actionType: null
    },
    {
        id: 'maps',
        name: 'Maps',
        category: 'Field Planning',
        description:
            'OpenStreetMap routing and territory visualization in the Field Rep Planner.',
        icon: 'utility:location',
        actionLabel: null,
        actionType: null
    },
    {
        id: 'mendix',
        name: 'Mendix',
        category: 'Low-Code Apps',
        description:
            'Bi-directional sync with Mendix apps for promo budgets, project management, and cross-dept workflows.',
        icon: 'utility:link',
        logoUrl: MENDIX_LOGO,
        actionLabel: 'Open Mendix Hub',
        actionType: 'tab',
        tabApiName: 'Mendix_Integration'
    },
    {
        id: 'ibnsina-pharmaoverseas',
        name: 'Wholesaler Feeds (IbnSina / Pharmaoverseas)',
        category: 'Sell-Out Data',
        description:
            'Load distributor sell-out from the monthly data pack, then export the consolidated month.',
        icon: 'utility:upload',
        actionLabel: 'Monthly data pack',
        actionType: 'admin',
        adminComponent: 'monthlyDataPack'
    },
    {
        id: 'veeva-network',
        name: 'Veeva Network',
        category: 'HCP / HCO Master',
        description:
            'Enterprise customer master data management and affiliation hierarchy.',
        icon: 'utility:database',
        actionLabel: null,
        actionType: null
    },
    {
        id: 'outlook',
        name: 'Microsoft Outlook / Exchange',
        category: 'Productivity',
        description:
            'Calendar sync for visit scheduling, coaching events, and field rep availability.',
        icon: 'utility:event',
        actionLabel: null,
        actionType: null
    },
    {
        id: 'sap-erp',
        name: 'SAP / ERP',
        category: 'Finance & Supply',
        description:
            'Order-to-cash, inventory, and financial reconciliation for sample and promo spend.',
        icon: 'utility:money',
        actionLabel: null,
        actionType: null
    }
];

const FALLBACK_STATUS = {
    status: 'Unknown',
    statusTone: 'planned',
    metaLabel: 'Data status',
    metaValue: '—',
    detail: null
};

function withStatus(base, statusRow) {
    const tone = (statusRow && statusRow.statusTone) || FALLBACK_STATUS.statusTone;
    return {
        ...base,
        status: (statusRow && statusRow.status) || FALLBACK_STATUS.status,
        statusClass: `status-pill status-pill--${tone}`,
        metaLabel: (statusRow && statusRow.metaLabel) || FALLBACK_STATUS.metaLabel,
        metaValue: (statusRow && statusRow.metaValue) || FALLBACK_STATUS.metaValue,
        detail: (statusRow && statusRow.detail) || null
    };
}

export default class IntegrationsManagementConsole extends NavigationMixin(LightningElement) {
    mendixLogoUrl = MENDIX_LOGO;
    statusById = {};
    loadError = null;

    @wire(getStatuses)
    wiredStatuses({ data, error }) {
        if (data) {
            const map = {};
            data.forEach((row) => {
                map[row.id] = row;
            });
            this.statusById = map;
            this.loadError = null;
        } else if (error) {
            this.loadError = error.body?.message || 'Unable to load integration status.';
            this.statusById = {};
        }
    }

    get integrations() {
        return BASE_INTEGRATIONS.map((item) => withStatus(item, this.statusById[item.id]));
    }

    get primaryIntegrations() {
        return this.integrations.filter((item) =>
            ['ims-health', 'onekey', 'maps', 'mendix'].includes(item.id)
        );
    }

    get additionalIntegrations() {
        return this.integrations.filter(
            (item) => !['ims-health', 'onekey', 'maps', 'mendix'].includes(item.id)
        );
    }

    handleAction(event) {
        const integrationId = event.currentTarget.dataset.integrationId;
        const integration = this.integrations.find((item) => item.id === integrationId);
        if (!integration || !integration.actionType) {
            return;
        }

        if (integration.actionType === 'tab') {
            this[NavigationMixin.Navigate]({
                type: 'standard__navItemPage',
                attributes: { apiName: integration.tabApiName }
            });
            return;
        }

        if (integration.actionType === 'admin') {
            this.dispatchEvent(
                new CustomEvent('openadminmodule', {
                    detail: {
                        componentName: integration.adminComponent,
                        title: integration.actionLabel
                    },
                    bubbles: true,
                    composed: true
                })
            );
        }
    }
}
