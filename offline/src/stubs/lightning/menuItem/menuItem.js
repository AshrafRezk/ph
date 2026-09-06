import { LightningElement, api } from 'lwc';

export default class MenuItem extends LightningElement {
    @api value = '';
    @api label = '';
    @api disabled = false;
    @api prefixIconName = '';

    handleClick(event) {
        if (this.disabled) {
            event.preventDefault();
            return;
        }
        this.dispatchEvent(
            new CustomEvent('select', {
                detail: { value: this.value },
                bubbles: true,
                composed: true
            })
        );
    }
}
