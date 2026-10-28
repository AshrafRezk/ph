import { LightningElement, api } from 'lwc';

export default class Card extends LightningElement {
    @api title = '';
    @api iconName = '';

    get hasHeader() {
        return Boolean(this.title) || Boolean(this.iconName);
    }

    get hasIcon() {
        return Boolean(this.iconName);
    }
}
