import { LightningElement, api } from 'lwc';

const ZONED_ISO = /^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}(:\d{2}(\.\d+)?)?(Z|[+-]\d{2}:?\d{2})$/;

function pad(n) {
    return String(n).padStart(2, '0');
}

export default class Input extends LightningElement {
    @api label = '';
    @api type = 'text';
    @api value = '';
    @api placeholder = '';
    @api variant = 'standard';
    @api disabled = false;
    @api required = false;
    @api checked = false;
    @api name = '';
    @api min;
    @api max;
    @api step;
    @api messageToggleActive;
    @api messageToggleInactive;

    get showLabel() {
        return this.variant !== 'label-hidden' && !!this.label;
    }

    get isCheckable() {
        return this.type === 'checkbox' || this.type === 'toggle';
    }

    get checkableClass() {
        return this.type === 'toggle' ? 'slds-checkbox_toggle slds-grid' : 'slds-checkbox';
    }

    get actualType() {
        if (this.type === 'datetime' || this.type === 'datetime-local') {
            return 'datetime-local';
        }
        return this.type || 'text';
    }

    // Lightning datetime values are ISO UTC; the native control needs local wall-clock time.
    get displayValue() {
        const raw = this.value;
        if (this.actualType === 'datetime-local' && typeof raw === 'string' && ZONED_ISO.test(raw)) {
            const d = new Date(raw);
            if (!Number.isNaN(d.getTime())) {
                return `${d.getFullYear()}-${pad(d.getMonth() + 1)}-${pad(d.getDate())}T${pad(d.getHours())}:${pad(d.getMinutes())}`;
            }
        }
        return raw;
    }

    handleInput(event) {
        this.value = event.target.value;
        this.dispatchEvent(
            new CustomEvent('change', {
                detail: { value: this.value }
            })
        );
    }

    handleChange(event) {
        this.value = event.target.value;
        this.dispatchEvent(
            new CustomEvent('change', {
                detail: { value: this.value }
            })
        );
    }

    handleCheck(event) {
        this.checked = event.target.checked;
        this.dispatchEvent(
            new CustomEvent('change', {
                detail: { checked: this.checked, value: this.value }
            })
        );
    }
}
