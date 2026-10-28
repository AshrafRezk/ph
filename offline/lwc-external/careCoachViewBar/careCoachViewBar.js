import { LightningElement, api } from 'lwc';

export default class CareCoachViewBar extends LightningElement {
    @api title;
    @api subtitle;
    @api iconName = 'standard:care_request_reviewer';
    @api context;
    @api mode = 'psp';
    @api scope = 'mine';
    @api coachId;
    @api coaches = [];
    @api hideScope = false;
    @api compact = false;

    get barClass() {
        return this.compact ? 'bar bar_compact' : 'bar';
    }

    get canPreview() {
        return this.context && this.context.hasFullAccess;
    }

    get isCompanyViewer() {
        return this.context && !this.context.hasFullAccess;
    }

    get isMasked() {
        return this.mode === 'company' || this.isCompanyViewer;
    }

    get showScopeToggle() {
        return !this.hideScope && this.context && this.context.hasFullAccess && this.context.isSupervisor;
    }

    get showCoachPicker() {
        if (this.hideScope || !this.context) return false;
        const wide = this.context.isSupervisor || !this.context.hasFullAccess;
        return wide && this.scope === 'all' && this.coaches && this.coaches.length > 0;
    }

    get coachOptions() {
        return [{ label: 'All care coaches', value: '' }, ...(this.coaches || [])];
    }

    get mineClass() {
        return this.scope === 'mine' ? 'is-active' : '';
    }

    get allClass() {
        return this.scope === 'all' ? 'is-active' : '';
    }

    get pspClass() {
        return this.mode !== 'company' ? 'is-active' : '';
    }

    get companyClass() {
        return this.mode === 'company' ? 'is-active' : '';
    }

    handleScope(event) {
        this.dispatchEvent(new CustomEvent('scopechange', { detail: event.currentTarget.dataset.scope }));
    }

    handleMode(event) {
        this.dispatchEvent(new CustomEvent('modechange', { detail: event.currentTarget.dataset.mode }));
    }

    handleCoach(event) {
        this.dispatchEvent(new CustomEvent('coachchange', { detail: event.detail.value }));
    }
}