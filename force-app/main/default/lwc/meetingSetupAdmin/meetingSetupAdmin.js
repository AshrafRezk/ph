import { LightningElement } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import getSetup from '@salesforce/apex/MeetingSetupController.getSetup';
import saveType from '@salesforce/apex/MeetingSetupController.saveType';
import saveLevel from '@salesforce/apex/MeetingSetupController.saveLevel';
import deleteLevel from '@salesforce/apex/MeetingSetupController.deleteLevel';
import loadDefaults from '@salesforce/apex/MeetingSetupController.loadDefaults';
import preview from '@salesforce/apex/MeetingSetupController.preview';

const SOURCES = ['Chain Role', 'Title', 'Manager', 'Manager Of Previous', 'Specific User'];
const SOURCE_HELP = {
    'Chain Role': "First person in the requester's manager chain whose title matches, then the territory role above them.",
    Title: 'First person with a matching title in the manager chain, then anyone in the company with that title.',
    Manager: "The requester's direct manager.",
    'Manager Of Previous': "The manager of the previous step's approver.",
    'Specific User': 'Always the named person.'
};
const DEFAULT_CHAIN = '__default';

export default class MeetingSetupAdmin extends LightningElement {
    setup;
    loading = true;
    busy = false;
    error;

    editType;
    territoryFilter = '';

    department = 'Sales';
    chainFor = DEFAULT_CHAIN;
    editLevel;

    previewUserId;
    previewDepartment = 'Sales';
    previewType = '';
    previewAmount = 10000;
    previewResult;

    connectedCallback() {
        this.refresh();
    }

    async refresh() {
        this.loading = true;
        try {
            this.setup = await getSetup();
            this.error = null;
        } catch (e) {
            this.error = message(e);
        } finally {
            this.loading = false;
        }
    }

    get canEdit() {
        return this.setup && this.setup.canEdit;
    }
    get readOnly() {
        return !this.canEdit;
    }
    get isSetUp() {
        return this.setup && this.setup.types.some((t) => t.configured);
    }
    get hasUnconfigured() {
        return this.setup && this.setup.types.some((t) => !t.configured);
    }

    // ---------------------------------------------------------------- types

    get typeRows() {
        return ((this.setup && this.setup.types) || []).map((t) => ({
            ...t,
            key: t.activityType,
            name: t.label || t.activityType,
            stateLabel: !t.configured ? 'Not set up' : t.isActive ? 'Active' : 'Off',
            stateCls: `slds-badge ${!t.configured ? '' : t.isActive ? 'slds-theme_success' : 'slds-theme_warning'}`,
            departmentsText: (t.departments || []).join(', ') || 'Any',
            territoriesText: (t.territories || []).join(', ') || 'All territories',
            creatorsText: [...(t.creatorTitles || []), ...(t.creatorPermissionSets || [])].join(', ') || 'Anyone',
            sections: sectionPills(t)
        }));
    }

    handleEditType(event) {
        const type = this.setup.types.find((t) => t.activityType === event.currentTarget.dataset.type);
        this.editType = JSON.parse(JSON.stringify(type));
        if (!this.editType.configured) {
            Object.assign(this.editType, {
                isActive: true,
                departments: this.editType.departments.length ? this.editType.departments : ['Marketing', 'Medical', 'Sales'],
                recordType: this.editType.recordType || 'Promotional_Activity'
            });
        }
        if (!this.editType.workspaceTabs || !this.editType.workspaceTabs.length) {
            this.editType.workspaceTabs = buildDefaultTabs(this.editType);
        }
        this.territoryFilter = '';
    }

    get tabOverview() {
        return this.hasTab('overview');
    }
    get tabPlan() {
        return this.hasTab('plan');
    }
    get tabPeople() {
        return this.hasTab('people');
    }
    get tabCost() {
        return this.hasTab('cost');
    }
    get tabInvites() {
        return this.hasTab('invites');
    }
    get tabHistory() {
        return this.hasTab('history');
    }
    get tabApm() {
        return this.hasTab('apm');
    }

    hasTab(key) {
        return this.editType && (this.editType.workspaceTabs || []).includes(key);
    }

    handleWorkspaceTab(event) {
        const key = event.target.dataset.tab;
        const on = event.target.checked;
        const current = new Set(this.editType.workspaceTabs || []);
        if (on) {
            current.add(key);
        } else {
            current.delete(key);
        }
        const order = ['overview', 'plan', 'people', 'cost', 'invites', 'history', 'apm'];
        const workspaceTabs = order.filter((k) => current.has(k));
        this.editType = {
            ...this.editType,
            workspaceTabs,
            showSuggestions: workspaceTabs.includes('plan'),
            showInvitations: workspaceTabs.includes('invites')
        };
    }

    handleCancelType() {
        this.editType = null;
    }

    handleTypeField(event) {
        const field = event.target.dataset.field;
        let value = event.detail && event.detail.value !== undefined ? event.detail.value : event.target.value;
        if (event.target.type === 'toggle' || event.target.type === 'checkbox') {
            value = event.target.checked;
        }
        if (event.target.type === 'number') {
            value = value === '' || value === null ? null : Number(value);
        }
        this.editType = { ...this.editType, [field]: value };
    }

    handleTerritoryFilter(event) {
        this.territoryFilter = event.target.value || '';
    }

    get editTitle() {
        return this.editType ? `${this.editType.label || this.editType.activityType}` : '';
    }
    get recordTypeOptions() {
        return ((this.setup && this.setup.recordTypes) || []).map((c) => ({ label: `${c.label} (${c.value})`, value: c.value }));
    }
    get departmentOptions() {
        return ((this.setup && this.setup.departments) || []).map((d) => ({ label: d, value: d }));
    }
    get titleOptions() {
        const values = new Set(((this.setup && this.setup.titles) || []).map((c) => c.value));
        const extra = ((this.editType && this.editType.creatorTitles) || []).filter((t) => !values.has(t)).map((t) => ({ label: t, value: t }));
        return [...((this.setup && this.setup.titles) || []), ...extra];
    }
    get permissionSetOptions() {
        return ((this.setup && this.setup.permissionSets) || []).map((c) => ({ label: `${c.label} (${c.value})`, value: c.value }));
    }
    get territoryOptions() {
        const term = this.territoryFilter.trim().toLowerCase();
        const selected = new Set((this.editType && this.editType.territories) || []);
        return ((this.setup && this.setup.territories) || [])
            .filter((c) => !term || selected.has(c.value) || c.label.toLowerCase().includes(term))
            .slice(0, 400);
    }

    async handleSaveType() {
        await this.run(async () => {
            this.setup = await saveType({ payload: JSON.stringify(this.editType) });
            this.editType = null;
        }, 'Meeting type saved');
    }

    async handleLoadDefaults() {
        await this.run(async () => {
            this.setup = await loadDefaults();
        }, 'BRD defaults loaded');
    }

    // ---------------------------------------------------------------- approval levels

    get departmentTabs() {
        return ((this.setup && this.setup.departments) || []).map((d) => ({
            label: d,
            value: d,
            variant: d === this.department ? 'brand' : 'neutral'
        }));
    }

    handleDepartment(event) {
        this.department = event.currentTarget.dataset.value;
        this.chainFor = DEFAULT_CHAIN;
        this.editLevel = null;
    }

    get chainOptions() {
        const types = ((this.setup && this.setup.types) || []).map((t) => ({ label: `${t.label || t.activityType} only`, value: t.activityType }));
        return [{ label: `Default ${this.department} chain (all types)`, value: DEFAULT_CHAIN }, ...types];
    }

    handleChainFor(event) {
        this.chainFor = event.detail.value;
        this.editLevel = null;
    }

    get departmentLevels() {
        return ((this.setup && this.setup.levels) || []).filter((l) => l.department === this.department);
    }

    get ownLevels() {
        return this.departmentLevels
            .filter((l) =>
                this.chainFor === DEFAULT_CHAIN ? !(l.activityTypes || []).length : (l.activityTypes || []).includes(this.chainFor)
            )
            .sort((a, b) => (a.stepOrder || 0) - (b.stepOrder || 0));
    }

    get levelRows() {
        const own = this.ownLevels;
        const inherited = this.chainFor !== DEFAULT_CHAIN && own.length === 0;
        const rows = inherited
            ? this.departmentLevels.filter((l) => !(l.activityTypes || []).length).sort((a, b) => (a.stepOrder || 0) - (b.stepOrder || 0))
            : own;
        return rows.map((l) => ({
            ...l,
            key: l.id || `${l.department}-${l.stepOrder}-${l.roleLabel}`,
            who: l.approverSource === 'Specific User' ? l.approverName || 'Named user' : `${l.approverSource}: ${l.roleValues || l.roleLabel}`,
            whenText: l.minAmount === null || l.minAmount === undefined
                ? 'Always'
                : `${l.strictlyGreater ? 'Above' : 'From'} ${Number(l.minAmount).toLocaleString()}`,
            sharedText: (l.activityTypes || []).length ? (l.activityTypes || []).join(', ') : '',
            inactive: !l.isActive,
            editable: !inherited && this.canEdit
        }));
    }

    get hasLevelRows() {
        return this.levelRows.length > 0;
    }

    get inheritsDefault() {
        return this.chainFor !== DEFAULT_CHAIN && this.ownLevels.length === 0;
    }

    get chainCaption() {
        if (this.chainFor === DEFAULT_CHAIN) {
            return `Used by every ${this.department} meeting unless its type has its own chain.`;
        }
        return this.inheritsDefault
            ? `${this.chainFor} uses the default ${this.department} chain below. Add a step to give it its own chain.`
            : `${this.department} meetings of type ${this.chainFor} use only these steps.`;
    }

    get sourceOptions() {
        return SOURCES.map((s) => ({ label: s, value: s }));
    }
    get sourceHelp() {
        return this.editLevel ? SOURCE_HELP[this.editLevel.approverSource] : '';
    }
    get isSpecificUser() {
        return this.editLevel && this.editLevel.approverSource === 'Specific User';
    }

    handleAddLevel() {
        const last = this.ownLevels[this.ownLevels.length - 1];
        this.editLevel = {
            id: null,
            department: this.department,
            activityTypes: this.chainFor === DEFAULT_CHAIN ? [] : [this.chainFor],
            stepOrder: last ? (last.stepOrder || 0) + 1 : 1,
            roleLabel: '',
            roleValues: '',
            approverSource: 'Chain Role',
            approverId: null,
            minAmount: null,
            strictlyGreater: false,
            isActive: true
        };
    }

    handleEditLevel(event) {
        const level = this.setup.levels.find((l) => l.id === event.currentTarget.dataset.id);
        this.editLevel = { ...level };
    }

    handleLevelField(event) {
        const field = event.target.dataset.field;
        let value = event.detail && event.detail.value !== undefined ? event.detail.value : event.target.value;
        if (event.target.type === 'checkbox' || event.target.type === 'toggle') {
            value = event.target.checked;
        }
        if (event.target.type === 'number') {
            value = value === '' || value === null ? null : Number(value);
        }
        this.editLevel = { ...this.editLevel, [field]: value };
    }

    handleApproverPick(event) {
        this.editLevel = { ...this.editLevel, approverId: event.detail.recordId || null };
    }

    handleCancelLevel() {
        this.editLevel = null;
    }

    async handleSaveLevel() {
        await this.run(async () => {
            this.setup = await saveLevel({ payload: JSON.stringify(this.editLevel) });
            this.editLevel = null;
        }, 'Approval step saved');
    }

    async handleDeleteLevel(event) {
        const levelId = event.currentTarget.dataset.id;
        await this.run(async () => {
            this.setup = await deleteLevel({ levelId });
        }, 'Approval step removed');
    }

    // ---------------------------------------------------------------- preview

    get previewTypeOptions() {
        return [{ label: 'Any type', value: '' }, ...((this.setup && this.setup.types) || []).map((t) => ({ label: t.label || t.activityType, value: t.activityType }))];
    }

    handlePreviewUser(event) {
        this.previewUserId = event.detail.recordId || null;
    }

    handlePreviewField(event) {
        this[event.target.dataset.field] = event.detail && event.detail.value !== undefined ? event.detail.value : event.target.value;
    }

    get previewDisabled() {
        return !this.previewUserId || this.busy;
    }

    async handlePreview() {
        await this.run(async () => {
            this.previewResult = await preview({
                userId: this.previewUserId,
                department: this.previewDepartment,
                activityType: this.previewType || null,
                amount: this.previewAmount === '' || this.previewAmount === null ? 0 : Number(this.previewAmount)
            });
        });
    }

    get previewUserLine() {
        const u = this.previewResult && this.previewResult.user;
        if (!u) {
            return '';
        }
        const territories = (u.territoryNames || []).join(', ') || 'no territory';
        return `${u.name} · ${u.title || 'no title'} · ${territories}`;
    }
    get previewPath() {
        const u = this.previewResult && this.previewResult.user;
        return u && u.territoryPath && u.territoryPath.length ? `Territory path: ${u.territoryPath.join(' → ')}` : '';
    }
    get previewTypes() {
        return ((this.previewResult && this.previewResult.types) || []).map((t) => ({
            key: t.config.activityType,
            name: t.config.label || t.config.activityType,
            allowed: t.allowed,
            icon: t.allowed ? 'utility:success' : 'utility:ban',
            variant: t.allowed ? 'success' : 'error',
            reason: t.allowed ? `Can plan · ${(t.config.departments || []).join(', ') || 'any department'}` : t.reason
        }));
    }
    get previewSteps() {
        return ((this.previewResult && this.previewResult.steps) || []).map((s) => ({
            ...s,
            key: `${s.stepNumber}`,
            who: s.approverName || 'No approver found',
            cls: s.status === 'Skipped' ? 'slds-text-color_weak' : ''
        }));
    }
    get hasPreviewSteps() {
        return this.previewSteps.length > 0;
    }

    // ---------------------------------------------------------------- helpers

    async run(work, success) {
        this.busy = true;
        try {
            await work();
            if (success) {
                this.dispatchEvent(new ShowToastEvent({ title: success, variant: 'success' }));
            }
        } catch (e) {
            this.dispatchEvent(new ShowToastEvent({ title: 'Could not save', message: message(e), variant: 'error' }));
        } finally {
            this.busy = false;
        }
    }
}

function buildDefaultTabs(t) {
    const tabs = ['overview'];
    if (t.showSuggestions !== false) tabs.push('plan');
    tabs.push('people', 'cost');
    if (t.showInvitations !== false) tabs.push('invites');
    tabs.push('history', 'apm');
    return tabs;
}

function sectionPills(t) {
    const pills = [];
    if (t.allowHcps) pills.push(t.requireTargetHcps ? 'Target-list HCPs' : 'HCPs');
    if (t.minHcps > 0) pills.push(`Min ${t.minHcps} HCP`);
    if (t.allowColleagues) pills.push('Colleagues');
    if (t.allowGuests) pills.push('Guests');
    const tabs = t.workspaceTabs && t.workspaceTabs.length ? t.workspaceTabs : buildDefaultTabs(t);
    tabs.forEach((key) => pills.push(`Tab:${key}`));
    if (t.allowDoorScan) pills.push('Door scan');
    if (t.allowDeposit) pills.push('Deposit');
    if (t.requireInvoice) pills.push('Invoice required');
    if (t.requireBrand) pills.push('Brand required');
    if (t.minAttendancePct !== null && t.minAttendancePct !== undefined) pills.push(`Attendance ${t.minAttendancePct}%`);
    return pills.map((label) => ({ key: label, label }));
}

function message(e) {
    return (e && e.body && e.body.message) || (e && e.message) || 'Something went wrong.';
}