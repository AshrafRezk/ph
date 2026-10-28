import { LightningElement, api } from 'lwc';

export default class VisitFieldRequests extends LightningElement {
    @api visitId;
    @api accountId;
    @api accountName;
    @api disabled = false;

    handleCountChange(event) {
        this.dispatchEvent(
            new CustomEvent('countchange', {
                detail: { count: event.detail?.count || 0 }
            })
        );
    }
}
