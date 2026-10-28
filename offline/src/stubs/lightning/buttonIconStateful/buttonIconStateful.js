import { LightningElement, api } from 'lwc';
import { svgForIcon } from '../iconSvgs.js';

export default class ButtonIconStateful extends LightningElement {
    @api iconName = '';
    @api alternativeText = '';
    @api title = '';
    @api variant = 'border';
    @api size = 'medium';
    @api disabled = false;
    @api selected = false;

    renderedCallback() {
        const host = this.template.querySelector('.slds-icon-svg');
        if (!host) return;
        const next = svgForIcon(this.iconName);
        if (host.dataset.svg === next) return;
        host.dataset.svg = next;
        host.innerHTML = next;
    }

    get computedClass() {
        const parts = ['slds-button', 'slds-button_icon', 'slds-button_icon-border'];
        if (this.selected) parts.push('slds-is-selected');
        if (this.size === 'small') parts.push('slds-button_icon-small');
        return parts.join(' ');
    }

    get pressed() {
        return this.selected ? 'true' : 'false';
    }
}
