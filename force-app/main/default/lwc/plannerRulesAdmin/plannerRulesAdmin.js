import { LightningElement, track } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import getRuleForScope from '@salesforce/apex/PlannerRulesService.getRuleForScope';
import saveRuleForScope from '@salesforce/apex/PlannerRulesService.saveRuleForScope';
import saveRuleForScopes from '@salesforce/apex/PlannerRulesService.saveRuleForScopes';
import listScopedRules from '@salesforce/apex/PlannerRulesService.listScopedRules';
import listLineOptions from '@salesforce/apex/PlannerRulesService.listLineOptions';
import listTitleOptions from '@salesforce/apex/PlannerRulesService.listTitleOptions';
import listProfileOptions from '@salesforce/apex/PlannerRulesService.listProfileOptions';
import searchUsersForException from '@salesforce/apex/PlannerRulesService.searchUsersForException';
import deleteScopedRule from '@salesforce/apex/PlannerRulesService.deleteScopedRule';

const AXES = [
    { id: 'visit', label: 'Visit' },
    { id: 'tot', label: 'TOT' },
    { id: 'meeting', label: 'Meeting' },
    { id: 'holiday', label: 'Holiday' }
];

const PAIR_KEYS = {
    'visit|visit': { key: 'visitVisitOverlap', help: 'Two visits for the same rep overlap in time.' },
    'visit|tot': { key: 'visitTotOverlap', help: 'Rep schedules a visit during approved or submitted time off.' },
    'visit|meeting': { key: 'visitMeetingOverlap', help: 'Visit overlaps a meeting the rep owns or attends.' },
    'visit|holiday': { key: 'visitHolidayOverlap', help: 'Visit lands on a company holiday.' },
    'tot|meeting': { key: 'totMeetingOverlap', help: 'Time off overlaps a planned meeting.' },
    'meeting|holiday': { key: 'meetingHolidayOverlap', help: 'Meeting starts on a company holiday.' }
};

/** Same cap as PlannerRulesService.MAX_SCOPE_KEYS_PER_SAVE. */
const MAX_POSITIONS_PER_SAVE = 25;

const SHORT_POLICY_OPTIONS = [
    { label: 'Allow', value: 'Allow' },
    { label: 'Warn', value: 'Warn' },
    { label: 'Block', value: 'Block' }
];

const DEFAULT_POLICIES = {
    visitTotOverlap: 'Block',
    visitVisitOverlap: 'Block',
    visitMeetingOverlap: 'Block',
    totMeetingOverlap: 'Warn',
    visitHolidayOverlap: 'Block',
    meetingHolidayOverlap: 'Warn',
    weekendPlanning: 'Block'
};

function pairLookup(a, b) {
    return PAIR_KEYS[`${a}|${b}`] || PAIR_KEYS[`${b}|${a}`] || null;
}

export default class PlannerRulesAdmin extends LightningElement {
    loading = true;
    saving = false;
    @track dayOptions = [];
    @track policies = { ...DEFAULT_POLICIES };
    @track lineOptions = [];
    @track titleOptions = [];
    @track profileOptions = [];
    @track userOptions = [];
    @track exceptionRows = [];
    workingDays = 'SAT,SUN,MON,TUE,WED';
    shortPolicyOptions = SHORT_POLICY_OPTIONS;
    scopeLevel = 'Org';
    scopeKey = 'ORG';
    scopeLabel = 'Org-wide (everyone)';
    inheritedFrom;
    selectedLine;
    @track selectedLines = [];
    selectedTitle;
    @track selectedTitles = [];
    selectedProfile;
    @track selectedProfiles = [];
    selectedUser;
    @track selectedUsers = [];
    /** Labels of picked users, so they stay in the picker when a new search replaces the results. */
    pickedUserLabels = {};
    userSearch = '';
    ruleId;

    get scopeTabs() {
        return [
            {
                key: 'Org',
                label: 'Org-wide',
                className: this.scopeLevel === 'Org' ? 'scope-tab is-active' : 'scope-tab'
            },
            {
                key: 'Line',
                label: 'Line',
                className: this.scopeLevel === 'Line' ? 'scope-tab is-active' : 'scope-tab'
            },
            {
                key: 'Line_Title',
                label: 'Line + Title',
                className: this.scopeLevel === 'Line_Title' ? 'scope-tab is-active' : 'scope-tab'
            },
            {
                key: 'Title',
                label: 'Title',
                className: this.scopeLevel === 'Title' ? 'scope-tab is-active' : 'scope-tab'
            },
            {
                key: 'Profile',
                label: 'Profile',
                className: this.scopeLevel === 'Profile' ? 'scope-tab is-active' : 'scope-tab'
            },
            {
                key: 'User',
                label: 'User',
                className: this.scopeLevel === 'User' ? 'scope-tab is-active' : 'scope-tab'
            }
        ];
    }

    get isOrgScope() {
        return this.scopeLevel === 'Org';
    }

    get isLineScope() {
        return this.scopeLevel === 'Line';
    }

    get isLineTitleScope() {
        return this.scopeLevel === 'Line_Title';
    }

    get isTitleScope() {
        return this.scopeLevel === 'Title';
    }

    get lineTitleScopeKey() {
        if (!this.selectedLine || !this.selectedTitle) {
            return null;
        }
        return `${this.selectedLine}||${this.selectedTitle}`;
    }

    /**
     * Every scope key the current picks cover. Line, Line+Title, Title, Profile and User all take
     * several picks, and one save applies the same settings to each of them.
     */
    get scopeKeys() {
        switch (this.scopeLevel) {
            case 'Org':
                return ['ORG'];
            case 'Line':
                return [...(this.selectedLines || [])];
            case 'Line_Title': {
                const keys = [];
                (this.selectedLines || []).forEach((line) =>
                    (this.selectedTitles || []).forEach((title) => keys.push(`${line}||${title}`))
                );
                return keys;
            }
            case 'Title':
                return [...(this.selectedTitles || [])];
            case 'Profile':
                return [...(this.selectedProfiles || [])];
            case 'User':
                return [...(this.selectedUsers || [])];
            default:
                return [];
        }
    }

    /** The first pick: its saved rule is what the screen shows. */
    get primaryKey() {
        return this.scopeKeys[0] || null;
    }

    get selectedPositionCount() {
        return this.scopeKeys.length;
    }

    get hasMultiplePositions() {
        return !this.isOrgScope && this.selectedPositionCount > 1;
    }

    get targetNoun() {
        if (this.isLineScope) return 'lines';
        if (this.isLineTitleScope) return 'line + title pairs';
        if (this.isProfileScope) return 'profiles';
        if (this.isUserScope) return 'users';
        return 'positions';
    }

    get primaryLabel() {
        if (this.isLineTitleScope) return `${this.selectedLine} · ${this.selectedTitle}`;
        if (this.isLineScope) return this.selectedLine;
        if (this.isProfileScope) return this.optionLabel(this.profileOptions, this.selectedProfile);
        if (this.isUserScope) return this.pickedUserLabels[this.selectedUser] || this.selectedUser;
        return this.selectedTitle;
    }

    get multiPositionNote() {
        if (!this.hasMultiplePositions) {
            return '';
        }
        const n = this.selectedPositionCount;
        const cap = n > MAX_POSITIONS_PER_SAVE ? ` That is over the limit of ${MAX_POSITIONS_PER_SAVE} per save.` : '';
        return `${n} ${this.targetNoun} selected. The settings below show ${this.primaryLabel}; saving applies them to all ${n}.${cap}`;
    }

    get pickedUserOptions() {
        const picked = (this.selectedUsers || []).map((id) => ({ value: id, label: this.pickedUserLabels[id] || id }));
        const pickedIds = new Set(this.selectedUsers || []);
        return [...picked, ...(this.userOptions || []).filter((u) => !pickedIds.has(u.value))];
    }

    get isProfileScope() {
        return this.scopeLevel === 'Profile';
    }

    get isUserScope() {
        return this.scopeLevel === 'User';
    }

    get canEditMatrix() {
        return this.isOrgScope || !!this.primaryKey;
    }

    get saveLabel() {
        if (this.hasMultiplePositions) return `Save for ${this.selectedPositionCount} ${this.targetNoun}`;
        if (this.isLineScope) return 'Save line rule';
        if (this.isLineTitleScope) return 'Save line+title rule';
        if (this.isTitleScope) return 'Save title rule';
        if (this.isProfileScope) return 'Save profile rule';
        if (this.isUserScope) return 'Save user exception';
        return 'Save org-wide rules';
    }

    get cascadeHint() {
        if (this.isUserScope) {
            return 'Cascade: User → Line+Title → Title → Profile → Line → BU → Org. The most specific match wins.';
        }
        if (this.isLineTitleScope) {
            return 'Line+Title applies only to that title on that line (e.g. Medical Rep on CHC), unless a User exception exists.';
        }
        if (this.isTitleScope) {
            return 'Title rules apply to everyone with that job title unless a User or Line+Title exception exists.';
        }
        if (this.isProfileScope) {
            return 'Profile rules apply to that Salesforce profile unless Title, Line+Title, or User overrides.';
        }
        if (this.isLineScope) {
            return 'Line rule overrides Org-wide for everyone seated on that line (unless Title/Profile/User overrides).';
        }
        return 'Org-wide rules apply unless Line, Line+Title, Profile, Title, or User overrides them.';
    }

    get weekendPreview() {
        const on = (this.dayOptions || []).filter((d) => d.selected).map((d) => d.label);
        const off = (this.dayOptions || []).filter((d) => !d.selected).map((d) => d.label);
        if (!on.length) return 'Select at least one working day.';
        return `Working: ${on.join(', ')}. Weekend / closed: ${off.join(', ') || 'none'}.`;
    }

    get weekendPlanning() {
        return this.policies.weekendPlanning || 'Block';
    }

    get columnHeaders() {
        return AXES.map((axis) => ({ id: axis.id, label: axis.label }));
    }

    get matrixRows() {
        const policies = this.policies || {};
        return AXES.map((rowAxis) => ({
            id: rowAxis.id,
            label: rowAxis.label,
            cells: AXES.map((colAxis) => {
                const pair = pairLookup(rowAxis.id, colAxis.id);
                if (!pair) {
                    return {
                        id: `${rowAxis.id}-${colAxis.id}`,
                        editable: false,
                        key: null,
                        value: null,
                        help: 'No overlap rule for this pair.',
                        toneClass: 'matrix-cell matrix-cell--empty'
                    };
                }
                const value = policies[pair.key] || 'Block';
                return {
                    id: `${rowAxis.id}-${colAxis.id}`,
                    editable: true,
                    key: pair.key,
                    value,
                    help: pair.help,
                    toneClass: `matrix-cell matrix-cell--${(value || 'block').toLowerCase()}`
                };
            })
        }));
    }

    get hasExceptions() {
        return (this.exceptionRows || []).length > 0;
    }

    get showInheritedBanner() {
        return !!this.inheritedFrom;
    }

    connectedCallback() {
        this.bootstrap();
    }

    async bootstrap() {
        this.loading = true;
        try {
            const [lines, titles, profiles] = await Promise.all([
                listLineOptions(),
                listTitleOptions(),
                listProfileOptions()
            ]);
            this.lineOptions = lines || [];
            this.titleOptions = titles || [];
            this.profileOptions = profiles || [];
            await Promise.all([this.loadCurrentScope(), this.refreshExceptionList()]);
        } catch (error) {
            this.toast('Could not load planner rules', this.errorMessage(error), 'error');
        } finally {
            this.loading = false;
        }
    }

    async loadCurrentScope() {
        const key = this.primaryKey;
        if (this.scopeLevel !== 'Org' && !key) {
            this.apply(null);
            this.inheritedFrom = 'Pick a line, line+title, title, profile, or user to edit their override.';
            return;
        }
        const rule = await getRuleForScope({ scopeLevel: this.scopeLevel, scopeKey: key });
        this.apply(rule);
    }

    async refreshExceptionList() {
        const rows = await listScopedRules({ scopeLevel: 'All' });
        this.exceptionRows = (rows || []).map((r) => ({
            ...r,
            key: r.id,
            meta: `${r.workingDays || '—'} · weekend ${r.weekendPlanning || '—'}`
        }));
    }

    apply(rule) {
        if (!rule) {
            this.ruleId = null;
            this.workingDays = 'SAT,SUN,MON,TUE,WED';
            this.dayOptions = [
                { value: 'SAT', label: 'Saturday', selected: true },
                { value: 'SUN', label: 'Sunday', selected: true },
                { value: 'MON', label: 'Monday', selected: true },
                { value: 'TUE', label: 'Tuesday', selected: true },
                { value: 'WED', label: 'Wednesday', selected: true },
                { value: 'THU', label: 'Thursday', selected: false },
                { value: 'FRI', label: 'Friday', selected: false }
            ];
            this.policies = { ...DEFAULT_POLICIES };
            this.scopeLabel = '';
            return;
        }
        this.ruleId = rule.id;
        this.workingDays = rule.workingDays || 'SAT,SUN,MON,TUE,WED';
        this.dayOptions = (rule.dayOptions || []).map((d) => ({ ...d }));
        this.policies = {
            visitTotOverlap: rule.visitTotOverlap || DEFAULT_POLICIES.visitTotOverlap,
            visitVisitOverlap: rule.visitVisitOverlap || DEFAULT_POLICIES.visitVisitOverlap,
            visitMeetingOverlap: rule.visitMeetingOverlap || DEFAULT_POLICIES.visitMeetingOverlap,
            totMeetingOverlap: rule.totMeetingOverlap || DEFAULT_POLICIES.totMeetingOverlap,
            visitHolidayOverlap: rule.visitHolidayOverlap || DEFAULT_POLICIES.visitHolidayOverlap,
            meetingHolidayOverlap: rule.meetingHolidayOverlap || DEFAULT_POLICIES.meetingHolidayOverlap,
            weekendPlanning: rule.weekendPlanning || DEFAULT_POLICIES.weekendPlanning
        };
        this.scopeLabel = rule.scopeLabel;
        this.inheritedFrom = rule.inheritedFrom;
    }

    async handleScopeTab(event) {
        this.scopeLevel = event.currentTarget.dataset.scope;
        this.scopeKey = this.scopeLevel === 'Org' ? 'ORG' : '';
        await this.loadCurrentScope();
    }

    async handleLineChange(event) {
        this.setSelectedLines(event.detail.value);
        this.scopeKey = this.primaryKey || '';
        await this.loadCurrentScope();
    }

    async handleLineTitleLineChange(event) {
        this.setSelectedLines(event.detail.value);
        this.scopeKey = this.primaryKey || '';
        await this.loadCurrentScope();
    }

    toList(values) {
        return Array.isArray(values) ? values.filter(Boolean) : values ? [values] : [];
    }

    setSelectedLines(values) {
        this.selectedLines = this.toList(values);
        this.selectedLine = this.selectedLines[0];
    }

    setSelectedTitles(values) {
        const list = this.toList(values);
        this.selectedTitles = list;
        this.selectedTitle = list.length ? list[0] : undefined;
    }

    setSelectedProfiles(values) {
        this.selectedProfiles = this.toList(values);
        this.selectedProfile = this.selectedProfiles[0];
    }

    setSelectedUsers(values) {
        this.selectedUsers = this.toList(values);
        this.selectedUser = this.selectedUsers[0];
    }

    optionLabel(options, value) {
        const match = (options || []).find((o) => o.value === value);
        return match ? match.label : value;
    }

    async handleLineTitleTitleChange(event) {
        this.setSelectedTitles(event.detail.value);
        this.scopeKey = this.lineTitleScopeKey || '';
        await this.loadCurrentScope();
    }

    async handleTitleChange(event) {
        this.setSelectedTitles(event.detail.value);
        this.scopeKey = this.selectedTitle;
        await this.loadCurrentScope();
    }

    async handleProfileChange(event) {
        this.setSelectedProfiles(event.detail.value);
        this.scopeKey = this.primaryKey || '';
        await this.loadCurrentScope();
    }

    async handleUserSearch(event) {
        this.userSearch = event.target.value;
        try {
            this.userOptions = await searchUsersForException({ searchTerm: this.userSearch });
        } catch (error) {
            this.toast('User search failed', this.errorMessage(error), 'error');
        }
    }

    async handleUserChange(event) {
        const labels = { ...this.pickedUserLabels };
        this.pickedUserOptions.forEach((u) => {
            labels[u.value] = u.label;
        });
        this.setSelectedUsers(event.detail.value);
        this.pickedUserLabels = labels;
        this.scopeKey = this.primaryKey || '';
        await this.loadCurrentScope();
    }

    async handleOpenException(event) {
        const level = event.currentTarget.dataset.level;
        const key = event.currentTarget.dataset.key;
        this.scopeLevel = level;
        if (level === 'Line') this.setSelectedLines([key]);
        if (level === 'Line_Title') {
            const sep = key.indexOf('||');
            if (sep >= 0) {
                this.setSelectedLines([key.substring(0, sep)]);
                this.setSelectedTitles([key.substring(sep + 2)]);
            }
        }
        if (level === 'Title') this.setSelectedTitles([key]);
        if (level === 'Profile') this.setSelectedProfiles([key]);
        if (level === 'User') {
            this.pickedUserLabels = {
                ...this.pickedUserLabels,
                [key]: this.pickedUserLabels[key] || event.currentTarget.dataset.label || key
            };
            this.setSelectedUsers([key]);
        }
        await this.loadCurrentScope();
    }

    handleDayToggle(event) {
        const token = event.target.dataset.value;
        const checked = event.target.checked;
        this.dayOptions = this.dayOptions.map((d) =>
            d.value === token ? { ...d, selected: checked } : d
        );
        this.workingDays = this.dayOptions.filter((d) => d.selected).map((d) => d.value).join(',');
    }

    handleWeekendPreset(event) {
        const preset = event.currentTarget.dataset.preset;
        const working =
            preset === 'FRI_SAT'
                ? ['SUN', 'MON', 'TUE', 'WED', 'THU']
                : ['SAT', 'SUN', 'MON', 'TUE', 'WED'];
        this.dayOptions = this.dayOptions.map((d) => ({ ...d, selected: working.includes(d.value) }));
        this.workingDays = this.dayOptions.filter((d) => d.selected).map((d) => d.value).join(',');
    }

    handleMatrixPolicy(event) {
        const key = event.target.dataset.key;
        if (!key) return;
        this.policies = { ...this.policies, [key]: event.detail.value };
    }

    handleWeekendPolicy(event) {
        this.policies = { ...this.policies, weekendPlanning: event.detail.value };
    }

    async handleSave() {
        if (!this.canEditMatrix) {
            this.toast('Pick a target', 'Choose at least one line, title, profile or user before saving.', 'error');
            return;
        }
        if (!this.workingDays) {
            this.toast('Working days', 'Select at least one working day.', 'error');
            return;
        }
        if (this.hasMultiplePositions && this.selectedPositionCount > MAX_POSITIONS_PER_SAVE) {
            this.toast(
                `Too many ${this.targetNoun}`,
                `Pick up to ${MAX_POSITIONS_PER_SAVE} ${this.targetNoun} at a time.`,
                'error'
            );
            return;
        }
        this.saving = true;
        try {
            const multiple = this.hasMultiplePositions;
            const count = this.selectedPositionCount;
            const noun = this.targetNoun;
            const key = this.primaryKey;
            const input = {
                workingDays: this.workingDays,
                visitTotOverlap: this.policies.visitTotOverlap,
                visitVisitOverlap: this.policies.visitVisitOverlap,
                visitMeetingOverlap: this.policies.visitMeetingOverlap,
                totMeetingOverlap: this.policies.totMeetingOverlap,
                visitHolidayOverlap: this.policies.visitHolidayOverlap,
                meetingHolidayOverlap: this.policies.meetingHolidayOverlap,
                weekendPlanning: this.policies.weekendPlanning
            };
            const rule = multiple
                ? await saveRuleForScopes({ input, scopeLevel: this.scopeLevel, scopeKeys: this.scopeKeys })
                : await saveRuleForScope({ input, scopeLevel: this.scopeLevel, scopeKey: key });
            this.apply(rule);
            await this.refreshExceptionList();
            this.toast(
                'Saved',
                multiple
                    ? `Planner rules are live for ${count} ${noun}.`
                    : `${rule.scopeLabel} planner rules are live.`,
                'success'
            );
        } catch (error) {
            this.toast('Save failed', this.errorMessage(error), 'error');
        } finally {
            this.saving = false;
        }
    }

    async handleDeleteException(event) {
        const id = event.currentTarget.dataset.id;
        // eslint-disable-next-line no-alert
        if (!window.confirm('Delete this line/user exception? Affected people fall back to the next cascade level.')) {
            return;
        }
        this.saving = true;
        try {
            await deleteScopedRule({ ruleId: id });
            if (this.ruleId === id) {
                this.ruleId = null;
                this.inheritedFrom = 'Deleted — now showing org default until you save again.';
            }
            await this.refreshExceptionList();
            await this.loadCurrentScope();
            this.toast('Exception removed', 'Cascade updated.', 'success');
        } catch (error) {
            this.toast('Delete failed', this.errorMessage(error), 'error');
        } finally {
            this.saving = false;
        }
    }

    toast(title, message, variant) {
        this.dispatchEvent(new ShowToastEvent({ title, message, variant }));
    }

    errorMessage(error) {
        return error?.body?.message || error?.message || 'Unknown error';
    }
}
