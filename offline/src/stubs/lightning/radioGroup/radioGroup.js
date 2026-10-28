import { LightningElement, api } from 'lwc';

export default class RadioGroup extends LightningElement {
    @api label = '';
    @api name = 'radiogroup';
    @api value = '';
    @api options = [];
    @api disabled = false;
    @api type = 'radio';

    get computedOptions() {
        return (this.options || []).map((o) => ({
            label: o.label,
            value: o.value,
            checked: String(o.value) === String(this.value)
        }));
    }

    handleChange(event) {
        event.stopPropagation();
        this.value = event.target.value;
        this.dispatchEvent(
            new CustomEvent('change', {
                bubbles: true,
                composed: true,
                detail: { value: this.value }
            })
        );
    }
}
