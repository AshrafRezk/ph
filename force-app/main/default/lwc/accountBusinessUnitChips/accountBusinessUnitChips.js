import { LightningElement, api, wire } from 'lwc';
import listForAccount from '@salesforce/apex/AccountBusinessUnitService.listForAccount';

export default class AccountBusinessUnitChips extends LightningElement {
    @api recordId;

    links = [];
    errorMessage;

    @wire(listForAccount, { accountId: '$recordId', includeInactive: false })
    wiredLinks({ data, error }) {
        if (data) {
            this.links = data;
            this.errorMessage = null;
        } else if (error) {
            this.links = [];
            this.errorMessage = this.reduceError(error);
        }
    }

    get hasLinks() {
        return this.links.length > 0;
    }

    get displayLinks() {
        return this.links.map((link) => ({
            ...link,
            key: link.id || link.uniqueKey
        }));
    }

    reduceError(error) {
        if (!error) {
            return 'Unable to load Business Units.';
        }
        if (typeof error === 'string') {
            return error;
        }
        if (error.body?.message) {
            return error.body.message;
        }
        return error.message || 'Unable to load Business Units.';
    }
}