import { LightningElement } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import getRule from '@salesforce/apex/CallTargetAdjustmentService.getRule';
import saveRule from '@salesforce/apex/CallTargetAdjustmentService.saveRule';

export default class CallTargetRuleManager extends LightningElement {
    loading = true;
    saving = false;
    enabled = true;
    thresholdDays = 7;
    stepSize = 1;
    minimumTarget = 0;
    longTermDays = 40;
    zeroOnLongTerm = false;
    typeOptions = [];
    selectedTypes = [];
    countAllTypes = true;

    connectedCallback() {
        this.load();
    }

    get typeChoices() {
        return this.typeOptions.map((value) => ({
            value,
            checked: this.countAllTypes || this.selectedTypes.includes(value)
        }));
    }

    get previewText() {
        if (!this.enabled) {
            return 'Adjustment is off. Monthly target calls stay at the class frequency.';
        }
        const threshold = this.numberValue(this.thresholdDays, 7);
        const floor = this.numberValue(this.minimumTarget, 0);
        const workingDays = 20;
        const prorated = (base) =>
            Math.max(Math.min(floor, base), Math.round((base * (workingDays - threshold)) / workingDays));
        let text = `Once counted time off reaches ${threshold} days, each target is pro-rated: target x (working days - counted days) / working days. With ${workingDays} working days, a target of 3 becomes ${prorated(3)}, 2 becomes ${prorated(2)}, and 1 becomes ${prorated(1)}.`;
        if (this.zeroOnLongTerm) {
            text += ` After ${this.numberValue(this.longTermDays, 40)} days the target goes to ${floor}.`;
        }
        text += ' Call rate uses the pro-rated target and is recalculated when time off is approved.';
        return text;
    }

    async load() {
        this.loading = true;
        try {
            const rule = await getRule();
            this.applyRule(rule);
        } catch (error) {
            this.toast('Could not load the rule', this.errorMessage(error), 'error');
        } finally {
            this.loading = false;
        }
    }

    applyRule(rule) {
        this.enabled = rule.enabled !== false;
        this.thresholdDays = rule.thresholdDays;
        this.stepSize = rule.stepSize;
        this.minimumTarget = rule.minimumTarget;
        this.longTermDays = rule.longTermDays;
        this.zeroOnLongTerm = rule.zeroOnLongTerm === true;
        this.typeOptions = rule.typeOptions || [];
        const saved = (rule.countedTypes || '')
            .split(/[\n;,]/)
            .map((value) => value.trim())
            .filter((value) => value);
        this.countAllTypes = saved.length === 0;
        this.selectedTypes = this.countAllTypes ? [...this.typeOptions] : saved;
    }

    handleEnabled(event) {
        this.enabled = event.target.checked;
    }

    handleThreshold(event) {
        this.thresholdDays = event.target.value;
    }

    handleStep(event) {
        this.stepSize = event.target.value;
    }

    handleMinimum(event) {
        this.minimumTarget = event.target.value;
    }

    handleLongTerm(event) {
        this.longTermDays = event.target.value;
    }

    handleZero(event) {
        this.zeroOnLongTerm = event.target.checked;
    }

    handleType(event) {
        const value = event.target.dataset.value;
        const checked = event.target.checked;
        const current = new Set(this.countAllTypes ? this.typeOptions : this.selectedTypes);
        if (checked) {
            current.add(value);
        } else {
            current.delete(value);
        }
        this.selectedTypes = [...current];
        this.countAllTypes = this.typeOptions.length > 0 && this.selectedTypes.length === this.typeOptions.length;
    }

    async handleSave() {
        if (!this.countAllTypes && (!this.selectedTypes || this.selectedTypes.length === 0)) {
            // An empty list is read by the server as "count every type", the opposite of what it looks like.
            this.toast(
                'Choose at least one time-off type',
                'Tick the types that count, or choose to count all types.',
                'warning'
            );
            return;
        }
        this.saving = true;
        try {
            const countedTypes = this.countAllTypes ? null : this.selectedTypes.join('\n');
            const saved = await saveRule({
                input: {
                    enabled: this.enabled,
                    thresholdDays: this.numberValue(this.thresholdDays, 7),
                    stepSize: this.numberValue(this.stepSize, 1),
                    minimumTarget: this.numberValue(this.minimumTarget, 0),
                    longTermDays: this.numberValue(this.longTermDays, 40),
                    zeroOnLongTerm: this.zeroOnLongTerm,
                    countedTypes
                }
            });
            this.applyRule(saved);
            this.toast(
                'Call target rule saved',
                'This month’s target calls and call rate are recalculating.',
                'success'
            );
        } catch (error) {
            this.toast('Could not save the rule', this.errorMessage(error), 'error');
        } finally {
            this.saving = false;
        }
    }

    numberValue(value, fallback) {
        if (value === '' || value === null || value === undefined) {
            return fallback;
        }
        const parsed = Number(value);
        return Number.isFinite(parsed) ? parsed : fallback;
    }

    errorMessage(error) {
        return error?.body?.message || error?.message || 'Something went wrong.';
    }

    toast(title, message, variant) {
        this.dispatchEvent(new ShowToastEvent({ title, message, variant }));
    }
}
