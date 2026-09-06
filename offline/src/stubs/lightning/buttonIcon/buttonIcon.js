import { LightningElement, api } from 'lwc';
import { svgForIcon } from '../iconSvgs.js';

export default class ButtonIcon extends LightningElement {
    @api iconName = '';
    @api alternativeText = '';
    @api title = '';
    @api variant = 'border';
    @api size = 'medium';
    @api disabled = false;

    renderedCallback() {
        const host = this.template.querySelector('.slds-icon-svg');
        if (!host) return;
        const next = svgForIcon(this.iconName);
        if (host.dataset.svg === next) return;
        host.dataset.svg = next;
        host.innerHTML = next;
    }

    get computedClass() {
        const parts = ['slds-button', 'slds-button_icon'];
        if (this.variant === 'border' || this.variant === 'border-filled') {
            parts.push('slds-button_icon-border');
        }
        if (this.variant === 'bare') {
            parts.push('slds-button_icon-bare');
        }
        if (this.size === 'small') {
            parts.push('slds-button_icon-small');
        }
        return parts.join(' ');
    }
}
