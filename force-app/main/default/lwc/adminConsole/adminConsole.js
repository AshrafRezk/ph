import { LightningElement, track, wire } from 'lwc';
import { NavigationMixin, CurrentPageReference } from 'lightning/navigation';
import { buildSearchTokens, matchesQuery } from './moduleSearch';

/** Display order for gallery sections (related tiles sit together). */
const GROUP_ORDER = [
    { id: 'apps', label: 'Apps & navigation' },
    { id: 'content', label: 'Content & coaching' },
    { id: 'geography', label: 'Territory, products & plans' },
    { id: 'performance', label: 'Performance & targets' },
    { id: 'sales', label: 'Sales & accounts' },
    { id: 'planner', label: 'Planner, holidays & meetings' },
    { id: 'platform', label: 'Integrations, tools & help' }
];

const GROUP_LABEL = GROUP_ORDER.reduce((acc, g) => ({ ...acc, [g.id]: g.label }), {});

/** URL state key so a module can be linked to directly: /lightning/n/Admin_Console?c__module=plan-manager */
const MODULE_STATE_KEY = 'c__module';

export default class AdminConsole extends NavigationMixin(LightningElement) {
    @track showModal = false;
    @track modalTitle = '';
    @track selectedComponent = '';
    @track searchTerm = '';
    @track collapsedGroups = [];

    selectedCardId = '';
    focusCloseOnRender = false;
    deepLinkHandled = false;

    adminCards = [
        {
            id: 'field-app-manager',
            group: 'apps',
            accent: 'indigo',
            title: 'Field App Manager',
            description:
                'Choose what every field user sees on Home and Planner, and turn Field AI, Class Engine, and request types on or off.',
            icon: 'utility:phone_portrait',
            componentName: 'fieldAppManager',
            titleAr: 'مدير تطبيق الميدان',
            keywords: ['home', 'widgets', 'features', 'flags', 'field ai', 'requests', 'apk', 'offline']
        },
        {
            id: 'hcp-portal',
            group: 'apps',
            accent: 'teal',
            title: 'HCP Portal',
            description:
                'Choose which tabs guests see on the meeting invite app. Entry pass and live QR stay on.',
            icon: 'utility:world',
            componentName: 'hcpPortalManager',
            titleAr: 'بوابة مقدم الرعاية',
            keywords: ['guests', 'invite', 'qr', 'doctor portal', 'meetings']
        },
        {
            id: 'copilot-tabs',
            group: 'apps',
            accent: 'indigo',
            title: 'Co-pilot app tabs',
            description:
                'Choose which tabs appear in Field, Lead, Force, and Care Coach. Meetings is not its own app.',
            icon: 'utility:apps',
            componentName: 'copilotAppNavAdmin',
            titleAr: 'تبويبات مساعد الطيار',
            keywords: ['navigation', 'menu', 'apps', 'lead', 'field', 'force']
        },
        {
            id: 'visit-tabs',
            group: 'apps',
            accent: 'teal',
            title: 'Visit Tabs',
            description:
                'Choose which sections a visit shows for each account type. Orders and Requests start on. Details stays on.',
            icon: 'utility:tabset',
            componentName: 'visitTabAdmin',
            titleAr: 'تبويبات الزيارة',
            keywords: ['visit', 'call', 'sections', 'orders', 'requests', 'account type']
        },
        {
            id: 'clm',
            group: 'content',
            accent: 'pink',
            title: 'CLM',
            description: 'Upload presentations, manage slides, and choose which territories can open each deck.',
            icon: 'utility:screen',
            componentName: 'clmAdminConsole',
            titleAr: 'إدارة العروض',
            keywords: ['presentations', 'e-detailing', 'decks', 'slides', 'content', 'pdf', 'html', 'targeting']
        },
        {
            id: 'rating-layouts',
            group: 'content',
            accent: 'orange',
            title: 'Rating Layouts',
            description: 'Design account, territory, and product rating forms, and preview them the way a rep sees them.',
            icon: 'utility:rating',
            componentName: 'clmRatingLayoutEditor',
            titleAr: 'تخطيطات التقييم',
            keywords: ['ratings', 'forms', 'questions', 'profiling', 'segmentation', 'potential', 'penetration']
        },
        {
            id: 'learning-module-management',
            group: 'content',
            accent: 'indigo',
            title: 'Learning Module Management',
            description: 'Create learning materials and courses, then assign them to people.',
            icon: 'utility:knowledge_base',
            componentName: 'learningModuleManager',
            titleAr: 'إدارة وحدات التعلم',
            keywords: ['lms', 'courses', 'videos', 'training', 'materials', 'assign']
        },
        {
            id: 'quiz-management',
            group: 'content',
            accent: 'orange',
            title: 'Quiz Management',
            description: 'Build quizzes and keep the question bank those quizzes use.',
            icon: 'utility:question',
            componentName: 'quizManager',
            titleAr: 'إدارة الاختبارات',
            keywords: ['exams', 'tests', 'questions', 'assessment']
        },
        {
            id: 'coaching-management',
            group: 'content',
            accent: 'teal',
            title: 'Coaching Management',
            description: 'Search coaching templates, create one, and open it in the editor.',
            icon: 'utility:education',
            componentName: 'coachingTemplateManager',
            titleAr: 'إدارة التدريب الميداني',
            keywords: ['double visit', 'templates', 'evaluation', 'coaching event', 'skills']
        },
        {
            id: 'territory-management',
            group: 'geography',
            accent: 'indigo',
            title: 'Territory Management',
            description: 'Manage product lines, the territory tree, and the people seated on each territory.',
            icon: 'utility:target',
            componentName: 'territoryManagementConsole',
            titleAr: 'إدارة الأقاليم',
            keywords: ['users', 'people', 'reps', 'hierarchy', 'positions', 'assign', 'seats', 'lines', 'vacant']
        },
        {
            id: 'sfe-approvers',
            group: 'geography',
            accent: 'teal',
            title: 'SFE Approvers',
            description:
                'Choose who approves Class Engine cycles and new accounts for each business unit.',
            icon: 'utility:approval',
            componentName: 'sfeApproverAdmin',
            titleAr: 'معتمدو SFE',
            keywords: ['approval', 'approvers', 'new accounts', 'class engine', 'business unit']
        },
        {
            id: 'bricks-management',
            group: 'geography',
            accent: 'purple',
            title: 'Bricks Manager',
            description:
                'Draw and name 148 and 702 brick regions on the map. Distributor sales sit in the brick that holds the pharmacy location.',
            icon: 'utility:location',
            componentName: 'bricksManagementConsole',
            titleAr: 'مدير الطوب الجغرافي',
            keywords: ['iqvia', 'ims', 'map', 'geography', '148', '702', 'pharmacies']
        },
        {
            id: 'products-manager',
            group: 'geography',
            accent: 'green',
            title: 'Products Manager',
            description: 'Add or edit products and prices, and align each product to territories.',
            icon: 'utility:product',
            componentName: 'productTerritoryManager',
            titleAr: 'مدير المنتجات',
            keywords: ['brands', 'catalog', 'sku', 'alignment', 'brand reminder']
        },
        {
            id: 'promo-grid',
            group: 'geography',
            accent: 'orange',
            title: 'Promo Grid Management',
            description:
                'Set product weights, specialty focus, and class targeting for each line. Product weights should total 100%.',
            icon: 'utility:table',
            componentName: 'promoGridManager',
            titleAr: 'إدارة شبكة الترويج',
            keywords: ['weights', 'class', 'specialty', 'targeting', 'frequency', 'class engine']
        },
        {
            id: 'sample-logistics',
            group: 'geography',
            accent: 'orange',
            title: 'Sample Logistics',
            description:
                'Take sample and brand-reminder requests, allocate lots to reps, and record transfers and returns.',
            icon: 'utility:package',
            componentName: 'sampleLogisticsConsole',
            titleAr: 'لوجستيات العينات',
            keywords: ['lots', 'expiry', 'inventory', 'brand reminder', 'allocation', 'transfers', 'returns', 'supply chain']
        },
        {
            id: 'plan-manager',
            group: 'geography',
            accent: 'teal',
            title: 'Plan Manager',
            description: 'Review monthly employee plans, edit account visit targets, and copy a plan to another month.',
            icon: 'utility:chart',
            componentName: 'planCycleManager',
            titleAr: 'مدير الخطط',
            keywords: ['plan cycle', 'targets', 'frequency', 'copy plan', 'monthly plan', 'coverage']
        },
        {
            id: 'call-target-rules',
            group: 'performance',
            accent: 'teal',
            title: 'Call Target Rules',
            description:
                'Lower the monthly call target after approved time off, office work, and meetings.',
            icon: 'utility:metrics',
            componentName: 'callTargetRuleManager',
            titleAr: 'قواعد هدف المكالمات',
            keywords: ['tot', 'time off', 'leave', 'working days', 'target reduction', 'office work']
        },
        {
            id: 'kpi-targets',
            group: 'performance',
            accent: 'indigo',
            title: 'KPI Targets',
            description:
                'Set scorecard targets by role, including what each metric counts. Field and Lead read these values live.',
            icon: 'utility:trending',
            componentName: 'kpiTargetsAdmin',
            titleAr: 'أهداف مؤشرات الأداء',
            keywords: ['scorecard', 'metrics', 'coverage', 'call rate', 'right frequency', 'roles']
        },
        {
            id: 'sales-policy',
            group: 'sales',
            accent: 'indigo',
            title: 'Sales Policy',
            description:
                'Set the distribution ceiling, share split, tender exclusion, public-price math, and Colest exceptions.',
            icon: 'utility:moneybag',
            componentName: 'salesPolicyAdmin',
            titleAr: 'سياسة المبيعات',
            keywords: ['pricing', 'distribution', 'tender', 'share', 'colest']
        },
        {
            id: 'monthly-data-pack',
            group: 'sales',
            accent: 'green',
            title: 'Monthly data pack',
            description:
                'Drop the month zip to preview and import sales, leave, time off territory, and historical visits.',
            icon: 'utility:archive',
            componentName: 'monthlyDataPack',
            titleAr: 'حزمة بيانات الشهر',
            keywords: ['import', 'upload', 'zip', 'leave', 'visits', 'sales', 'tot']
        },
        {
            id: 'sales-export-month',
            group: 'sales',
            accent: 'green',
            title: 'Export month',
            description:
                'Download one month of pharmacy sales (all distributors consolidated), with product, quantity, and revenue, as Excel.',
            icon: 'utility:download',
            componentName: 'salesExportMonth',
            titleAr: 'تصدير الشهر',
            keywords: [
                'excel', 'download', 'export', 'sales', 'revenue', 'consolidated', 'pharmacy', 'pharmacies',
                'sales data', 'sell-out', 'sellout', 'distributor', 'withdrawal', 'مبيعات', 'صيدليات'
            ]
        },
        {
            id: 'distributors-management',
            group: 'sales',
            accent: 'blue',
            title: 'Distributors Management',
            description:
                'Import distributor Excel, match pharmacies and products, and confirm the nearby order share.',
            icon: 'utility:retail_execution',
            componentName: 'distributorsManagement',
            titleAr: 'إدارة الموزعين',
            keywords: ['sell-out', 'sellout', 'ibnsina', 'ibn sina', 'pharmaoverseas', 'mapping', 'import', 'unmatched', 'branches']
        },
        {
            id: 'target-governance',
            group: 'sales',
            accent: 'orange',
            title: 'Target Governance',
            description:
                'Set the frequency and list-change alarms, and work the end-of-month out-of-target queue.',
            icon: 'utility:alert',
            componentName: 'targetGovernanceAdmin',
            titleAr: 'حوكمة الأهداف',
            keywords: ['frequency', 'out-of-target', 'alarms', 'queue', 'end of month']
        },
        {
            id: 'account-management',
            group: 'sales',
            accent: 'teal',
            title: 'Account Management',
            description:
                'Load, modify, or export accounts and affiliations, link business units, and review duplicates. Wipe is a full reset.',
            icon: 'utility:people',
            componentName: 'accountManagementConsole',
            titleAr: 'إدارة الحسابات',
            keywords: ['hcp', 'hco', 'pharmacy', 'master data', 'import', 'export', 'affiliations', 'business unit', 'duplicates', 'wipe', 'doctors', 'hospitals']
        },
        {
            id: 'account-data-quality',
            group: 'sales',
            accent: 'purple',
            title: 'Account data quality',
            description:
                'Scan accounts for name duplicates, merge doctors entered twice with different specialties, and fill missing Places or Vezeeta fields after you approve the rows.',
            icon: 'utility:filterList',
            componentName: 'accountDataQualityConsole',
            titleAr: 'جودة بيانات الحسابات',
            keywords: ['duplicates', 'places', 'vezeeta', 'clean', 'missing data', 'gps', 'merge', 'specialty', 'doctor merger']
        },
        {
            id: 'target-master-lists',
            group: 'sales',
            accent: 'indigo',
            title: 'Target & Master Lists',
            description:
                'Import or export the organization master list and the all-team target list. This updates rows and does not wipe.',
            icon: 'utility:file',
            componentName: 'targetMasterListAdmin',
            titleAr: 'قوائم الهدف والمستر',
            keywords: ['target list', 'master list', 'frequency', 'class', 'organizations']
        },
        {
            id: 'public-holidays',
            group: 'planner',
            accent: 'slate',
            title: 'Public Holidays',
            description:
                'Add company holidays that close the planner and reduce Class Engine capacity. Personal time off is separate.',
            icon: 'utility:holiday_operating_hours',
            componentName: 'publicHolidaysManager',
            titleAr: 'العطلات الرسمية',
            keywords: ['holidays', 'calendar', 'closed days', 'eid']
        },
        {
            id: 'planner-rules',
            group: 'planner',
            accent: 'teal',
            title: 'Planner Rules',
            description:
                'Set working days, and whether a visit, meeting, time off, or holiday overlap is allowed, warned, or blocked.',
            icon: 'utility:date_time',
            componentName: 'plannerRulesAdmin',
            titleAr: 'قواعد المخطط',
            keywords: ['working days', 'weekend', 'overlap', 'tot', 'calendar', 'allow', 'warn', 'block']
        },
        {
            id: 'meetings-setup',
            group: 'planner',
            accent: 'slate',
            title: 'Meetings Setup',
            description:
                'Set meeting types, who can create them, which tabs the screen shows, and the approval sequence.',
            icon: 'utility:event',
            componentName: 'meetingSetupAdmin',
            titleAr: 'إعداد الاجتماعات',
            keywords: ['approvals', 'events', 'rtd', 'speaker', 'webinar', 'promotional activities', 'workflow']
        },
        {
            id: 'service-request-types',
            group: 'planner',
            accent: 'purple',
            title: 'Service Request Types',
            description: 'Set request types and subtypes, and which job titles can create each one.',
            icon: 'utility:case',
            componentName: 'serviceRequestTypesAdmin',
            titleAr: 'أنواع طلبات الخدمة',
            keywords: ['requests', 'cases', 'types', 'subtypes', 'job titles']
        },
        {
            id: 'integrations-management',
            group: 'platform',
            accent: 'slate',
            title: 'Integrations Management',
            description:
                'See which connectors are configured in this org, and open the module that owns each one.',
            icon: 'utility:link',
            componentName: 'integrationsManagementConsole',
            titleAr: 'إدارة التكاملات',
            keywords: ['mendix', 'ims', 'onekey', 'maps', 'api', 'connectors', 'status']
        },
        {
            id: 'chrome-data-tools',
            group: 'platform',
            accent: 'blue',
            title: 'Chrome and Data Tools',
            description:
                'Chrome helpers and read-only query recipes for checking accounts, users, territories, and ratings.',
            icon: 'utility:trail',
            componentName: 'adminChromeDataTools',
            titleAr: 'إضافات كروم وأدوات البيانات',
            keywords: ['soql', 'inspector', 'queries', 'extensions']
        },
        {
            id: 'trailhead-learning',
            group: 'platform',
            accent: 'green',
            title: 'Trailhead Learning',
            description:
                'Suggested Trailhead modules and trails on reports, dashboards, and Salesforce administration.',
            icon: 'utility:knowledge_base',
            componentName: 'adminTrailheadLearning',
            titleAr: 'التعلم على تريلهيد',
            keywords: ['trailhead', 'training', 'reports', 'dashboards', 'admin', 'learn', 'courses', 'badges']
        },
        {
            id: 'help',
            group: 'platform',
            accent: 'teal',
            title: 'Help',
            description: 'Search English or Arabic steps for the module you want, then open it from here.',
            icon: 'utility:info',
            componentName: 'adminConsoleHelp',
            titleAr: 'مساعدة',
            keywords: ['guide', 'how to', 'arabic', 'walkthrough', 'steps']
        }
    ];

    get moduleCount() {
        return this.adminCards.length;
    }

    get isSearching() {
        return (this.searchTerm || '').trim().length > 0;
    }

    get moduleTotalLabel() {
        const total = this.adminCards.length;
        if (!this.isSearching) {
            return `${total} modules`;
        }
        const shown = this.filteredCards.length;
        return `${shown} of ${total} modules match “${this.searchTerm.trim()}”`;
    }

    get searchIndex() {
        if (!this._searchIndex) {
            this._searchIndex = new Map(
                this.adminCards.map((card) => [card.id, buildSearchTokens(card, GROUP_LABEL[card.group] || '')])
            );
        }
        return this._searchIndex;
    }

    get filteredCards() {
        const list = this.isSearching
            ? this.adminCards.filter((card) => matchesQuery(this.searchIndex.get(card.id), this.searchTerm))
            : this.adminCards;
        return list.map((card) => ({
            ...card,
            cardClass: `admin-card admin-card--${card.accent}`,
            ariaLabel: `${card.title}. ${card.description}`
        }));
    }

    get sectionsView() {
        const byGroup = new Map();
        for (const card of this.filteredCards) {
            const key = card.group || 'platform';
            if (!byGroup.has(key)) {
                byGroup.set(key, []);
            }
            byGroup.get(key).push(card);
        }
        return GROUP_ORDER.filter((g) => byGroup.has(g.id)).map((g) => {
            const cards = byGroup.get(g.id);
            const expanded = this.isSearching || !this.collapsedGroups.includes(g.id);
            return {
                id: g.id,
                labelId: `admin-group-${g.id}`,
                gridId: `admin-grid-${g.id}`,
                label: g.label,
                countLabel: `${cards.length} module${cards.length === 1 ? '' : 's'}`,
                expanded,
                ariaExpanded: expanded ? 'true' : 'false',
                chevronIcon: expanded ? 'utility:chevrondown' : 'utility:chevronright',
                toggleLabel: `${expanded ? 'Collapse' : 'Expand'} ${g.label}`,
                cards
            };
        });
    }

    get hasResults() {
        return this.filteredCards.length > 0;
    }

    get isFieldAppManager() {
        return this.selectedComponent === 'fieldAppManager';
    }

    get isHcpPortalManager() {
        return this.selectedComponent === 'hcpPortalManager';
    }

    get isCopilotTabs() {
        return this.selectedComponent === 'copilotAppNavAdmin';
    }

    get isVisitTabs() {
        return this.selectedComponent === 'visitTabAdmin';
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

    get isSfeApprovers() {
        return this.selectedComponent === 'sfeApproverAdmin';
    }

    get isBricksManagement() {
        return this.selectedComponent === 'bricksManagementConsole';
    }

    get modalClass() {
        return (
            'slds-modal slds-fade-in-open slds-modal_large admin-console-modal' +
            (this.isBricksManagement ? ' admin-console-modal_map' : '')
        );
    }

    get isProductsManager() {
        return this.selectedComponent === 'productTerritoryManager';
    }

    get isSampleLogistics() {
        return this.selectedComponent === 'sampleLogisticsConsole';
    }

    get isPlanManager() {
        return this.selectedComponent === 'planCycleManager';
    }

    get isCallTargetRules() {
        return this.selectedComponent === 'callTargetRuleManager';
    }

    get isSalesPolicyAdmin() {
        return this.selectedComponent === 'salesPolicyAdmin';
    }

    get isMonthlyDataPack() {
        return this.selectedComponent === 'monthlyDataPack';
    }

    get isSalesExportMonth() {
        return this.selectedComponent === 'salesExportMonth';
    }

    get isDistributorsManagement() {
        return this.selectedComponent === 'distributorsManagement';
    }

    get isTargetGovernanceAdmin() {
        return this.selectedComponent === 'targetGovernanceAdmin';
    }

    get isAccountManagement() {
        return this.selectedComponent === 'accountManagementConsole';
    }

    get isAccountDataQuality() {
        return this.selectedComponent === 'accountDataQualityConsole';
    }

    get isTargetMasterLists() {
        return this.selectedComponent === 'targetMasterListAdmin';
    }

    get isIntegrationsManagement() {
        return this.selectedComponent === 'integrationsManagementConsole';
    }

    get isPromoGridManagement() {
        return this.selectedComponent === 'promoGridManager';
    }

    get isPublicHolidaysManagement() {
        return this.selectedComponent === 'publicHolidaysManager';
    }

    get isPlannerRulesAdmin() {
        return this.selectedComponent === 'plannerRulesAdmin';
    }

    get isLearningModuleManagement() {
        return this.selectedComponent === 'learningModuleManager';
    }

    get isMeetingsSetup() {
        return this.selectedComponent === 'meetingSetupAdmin';
    }

    get isServiceRequestTypesAdmin() {
        return this.selectedComponent === 'serviceRequestTypesAdmin';
    }

    get isQuizManagement() {
        return this.selectedComponent === 'quizManager';
    }

    get isKpiTargetsAdmin() {
        return this.selectedComponent === 'kpiTargetsAdmin';
    }

    get isChromeDataTools() {
        return this.selectedComponent === 'adminChromeDataTools';
    }

    get isTrailheadLearning() {
        return this.selectedComponent === 'adminTrailheadLearning';
    }

    get isAdminConsoleHelp() {
        return this.selectedComponent === 'adminConsoleHelp';
    }

    @wire(CurrentPageReference)
    handlePageReference(pageRef) {
        const cardId = pageRef && pageRef.state ? pageRef.state[MODULE_STATE_KEY] : null;
        if (cardId && !this.deepLinkHandled) {
            this.deepLinkHandled = true;
            this.openCard(cardId);
        }
    }

    renderedCallback() {
        if (this.focusCloseOnRender && this.showModal) {
            const closeButton = this.template.querySelector('.slds-modal__close');
            if (closeButton) {
                this.focusCloseOnRender = false;
                closeButton.focus();
            }
        }
    }

    handleSearch(event) {
        this.searchTerm = event.target.value || '';
    }

    handleToggleGroup(event) {
        const groupId = event.currentTarget.dataset.groupId;
        if (!groupId || this.isSearching) {
            return;
        }
        this.collapsedGroups = this.collapsedGroups.includes(groupId)
            ? this.collapsedGroups.filter((id) => id !== groupId)
            : [...this.collapsedGroups, groupId];
    }

    handleCardClick(event) {
        if (event.key && event.key !== 'Enter' && event.key !== ' ') {
            return;
        }
        if (event.key) {
            event.preventDefault();
        }
        this.openCard(event.currentTarget.dataset.cardId);
    }

    openCard(cardId) {
        const card = this.adminCards.find((item) => item.id === cardId);
        if (!card) {
            return false;
        }
        this.selectedCardId = card.id;
        this.selectedComponent = card.componentName;
        this.modalTitle = card.title;
        this.showModal = true;
        this.focusCloseOnRender = true;
        return true;
    }

    navigateToTab(apiName) {
        this[NavigationMixin.Navigate]({
            type: 'standard__navItemPage',
            attributes: { apiName }
        });
    }

    handleModalKeydown(event) {
        if (event.key !== 'Escape' && event.key !== 'Esc') {
            return;
        }
        // Leave Escape to an open dropdown, combobox, or menu inside the module.
        const path = typeof event.composedPath === 'function' ? event.composedPath() : [];
        const insideOpenPopup = path.some(
            (el) => el && el.getAttribute && el.getAttribute('aria-expanded') === 'true'
        );
        if (event.defaultPrevented || insideOpenPopup) {
            return;
        }
        event.stopPropagation();
        this.closeModal();
    }

    closeModal() {
        const returnTo = this.selectedCardId;
        this.showModal = false;
        this.selectedComponent = '';
        this.modalTitle = '';
        this.selectedCardId = '';
        if (returnTo) {
            // Put keyboard focus back on the card that opened the module.
            // eslint-disable-next-line @lwc/lwc/no-async-operation
            setTimeout(() => {
                const card = this.template.querySelector(`[data-card-id="${returnTo}"]`);
                if (card) {
                    card.focus();
                }
            }, 0);
        }
    }

    handleOpenAdminModule(event) {
        const { componentName, title, cardId } = event.detail || {};
        if (cardId && this.openCard(cardId)) {
            return;
        }
        const card =
            this.adminCards.find((item) => componentName && item.componentName === componentName) ||
            this.adminCards.find((item) => title && item.title === title);
        if (card) {
            this.openCard(card.id);
            return;
        }
        if (!componentName) {
            return;
        }
        this.selectedComponent = componentName;
        this.modalTitle = title || 'Admin Module';
    }
}
