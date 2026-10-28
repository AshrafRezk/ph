import { LightningElement, track } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import getCatalogByCategories from '@salesforce/apex/FieldAppFeatureController.getCatalogByCategories';
import saveFeatureMap from '@salesforce/apex/FieldAppFeatureController.saveFeatureMap';

const SECTIONS = [
    {
        id: 'home',
        title: 'Home',
        description: 'Widgets on the field home page.',
        categories: ['Home'],
        keys: [
            'home.officeMessages',
            'home.beInTheKnow',
            'home.accountsNurturing',
            'home.yourPerformance',
            'home.todayPlan',
            'home.nextBestCustomer',
            'home.reports'
        ]
    },
    {
        id: 'performance',
        title: 'Your performance',
        description: 'Which measuring rings appear when Your performance is on. Keep at least one on.',
        categories: ['Performance'],
        keys: [
            'metric.visit',
            'metric.customer',
            'metric.rf',
            'metric.remaining',
            'metric.am',
            'metric.pm'
        ],
        nestedUnder: 'home.yourPerformance'
    },
    {
        id: 'planner',
        title: 'Planner',
        description: 'Optional planner tools. Submit week and drag-to-plan stay available.',
        categories: ['Planner'],
        keys: [
            'planner.mapRoute',
            'planner.copyPrevious',
            'planner.addMeeting',
            'planner.timeOff',
            'meetingExpenses'
        ]
    },
    {
        id: 'field-ai',
        title: 'Field AI',
        description: 'The assistant on Home and Planner for all users.',
        categories: ['Field AI'],
        keys: ['agentforce']
    },
    {
        id: 'class-engine',
        title: 'Class Engine',
        description: 'Master switch for Class Engine across Lightning, Salesforce mobile, and the APK.',
        categories: ['Class Engine'],
        keys: ['classEngine']
    },
    {
        id: 'requests',
        title: 'Requests',
        description: 'Medical and field requests. Orders stay on their own visit section.',
        categories: ['Requests'],
        keys: [
            'requests.enabled',
            'requests.medical',
            'requests.type.sample',
            'requests.type.device',
            'requests.type.material',
            'requests.type.followUp',
            'requests.type.other'
        ]
    }
];

export default class FieldAppManager extends LightningElement {
    @track sections = [];
    isLoading = true;
    errorMessage;
    _byKey = new Map();
    _dirty = new Map();

    connectedCallback() {
        this.loadCatalog();
    }

    async loadCatalog() {
        this.isLoading = true;
        this.errorMessage = undefined;
        try {
            const categories = [
                'Home',
                'Performance',
                'Planner',
                'Field AI',
                'Class Engine',
                'Requests'
            ];
            const rows = await getCatalogByCategories({ categories });
            this._byKey = new Map((rows || []).map((row) => [row.key, { ...row }]));
            this._dirty = new Map();
            this.rebuildSections();
        } catch (error) {
            this.errorMessage =
                error?.body?.message || error?.message || 'Unable to load Field App Manager.';
            this.sections = [];
        } finally {
            this.isLoading = false;
        }
    }

    rebuildSections() {
        const performanceParentOn = this.enabledOf('home.yourPerformance') === true;
        const requestsOn = this.enabledOf('requests.enabled') === true;
        this.sections = SECTIONS.map((section) => {
            const features = section.keys
                .map((key) => this._byKey.get(key))
                .filter(Boolean)
                .map((row) => {
                    let disabled = false;
                    let rowClass = 'fam-row';
                    if (section.id === 'performance') {
                        disabled = !performanceParentOn;
                        rowClass += ' fam-row--nested';
                    }
                    if (
                        section.id === 'requests' &&
                        row.key !== 'requests.enabled' &&
                        !requestsOn
                    ) {
                        disabled = true;
                    }
                    if (section.id === 'requests' && row.key !== 'requests.enabled') {
                        rowClass += ' fam-row--nested';
                    }
                    if (disabled) {
                        rowClass += ' fam-row--disabled';
                    }
                    return {
                        ...row,
                        enabled: this.enabledOf(row.key),
                        disabled,
                        rowClass,
                        toggleLabel: this.enabledOf(row.key) ? 'On' : 'Off'
                    };
                });
            const dirtyCount = section.keys.filter((key) => this._dirty.has(key)).length;
            return {
                ...section,
                features,
                saveLabel: dirtyCount ? `Save (${dirtyCount})` : 'Save',
                saveDisabled: dirtyCount === 0
            };
        });
    }

    enabledOf(key) {
        if (this._dirty.has(key)) {
            return this._dirty.get(key) === true;
        }
        return this._byKey.get(key)?.enabled === true;
    }

    handleToggle(event) {
        const key = event.currentTarget.dataset.key;
        const enabled = event.detail.checked === true;
        this._dirty.set(key, enabled);
        if (key === 'home.yourPerformance' && !enabled) {
            // Leave metric keys as-is; UI disables them while parent is off.
        }
        this.rebuildSections();
    }

    async handleSaveSection(event) {
        const sectionId = event.currentTarget.dataset.section;
        const section = SECTIONS.find((item) => item.id === sectionId);
        if (!section) {
            return;
        }
        const updates = {};
        section.keys.forEach((key) => {
            if (this._dirty.has(key)) {
                updates[key] = this._dirty.get(key);
            }
        });
        if (!Object.keys(updates).length) {
            return;
        }
        try {
            const saved = (await saveFeatureMap({ updates })) || [];
            const savedKeys = new Set(saved.map((row) => row.key));
            const missed = [];
            Object.keys(updates).forEach((key) => {
                if (!savedKeys.has(key)) {
                    missed.push(this._byKey.get(key)?.label || key);
                    return; // stays unsaved so the admin can see it did not stick
                }
                const row = this._byKey.get(key);
                if (row) {
                    row.enabled = updates[key] === true;
                }
                this._dirty.delete(key);
            });
            this.rebuildSections();
            this.dispatchEvent(
                new ShowToastEvent(
                    missed.length
                        ? {
                              title: 'Some settings were not saved',
                              message: `Not saved: ${missed.join(', ')}. Ask an administrator to check the feature records.`,
                              variant: 'warning'
                          }
                        : {
                              title: 'Saved',
                              message: `${section.title} settings apply to all field users.`,
                              variant: 'success'
                          }
                )
            );
        } catch (error) {
            this.dispatchEvent(
                new ShowToastEvent({
                    title: 'Could not save',
                    message: error?.body?.message || error?.message || 'Unable to save.',
                    variant: 'error'
                })
            );
            // Reload this section from the server but keep unsaved edits in the other sections.
            const keepOther = new Map(
                [...this._dirty.entries()].filter(([key]) => !section.keys.includes(key))
            );
            await this.loadCatalog();
            keepOther.forEach((value, key) => this._dirty.set(key, value));
            this.rebuildSections();
        }
    }
}