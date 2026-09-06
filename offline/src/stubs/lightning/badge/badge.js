import { LightningElement, api } from 'lwc';

export default class Badge extends LightningElement {
    @api label = '';
    @api iconName = '';
    @api iconAlternativeText = '';
    @api iconPosition = 'left';

    get computedClass() {
        return 'slds-badge';
    }
}
