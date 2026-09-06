import { LightningElement, api } from 'lwc';
import { svgForIcon } from '../iconSvgs.js';

export default class Icon extends LightningElement {
    @api iconName = '';
    @api alternativeText = '';
    @api size = 'medium';
    @api variant = '';
    @api title = '';

    renderedCallback() {
        const host = this.template.querySelector('.slds-icon-svg');
        if (!host) return;
        const next = svgForIcon(this.iconName);
        if (host.dataset.svg === next) return;
        host.dataset.svg = next;
        host.innerHTML = next;
    }

    get computedClass() {
        return `slds-icon_container slds-icon-${this.size}`;
    }
}
