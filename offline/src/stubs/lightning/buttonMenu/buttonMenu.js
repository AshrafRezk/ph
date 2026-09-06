import { LightningElement, api } from 'lwc';

export default class ButtonMenu extends LightningElement {
    @api alternativeText = 'Show menu';
    @api iconName = 'utility:down';
    @api variant = 'border-filled';
    @api menuAlignment = 'auto';
    @api disabled = false;
    @api title = '';

    open = false;

    get computedClass() {
        return 'slds-dropdown-trigger slds-dropdown-trigger_click' + (this.open ? ' slds-is-open' : '');
    }

    toggle(event) {
        event.stopPropagation();
        if (this.disabled) return;
        this.open = !this.open;
    }
}
