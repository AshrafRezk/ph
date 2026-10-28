import { LightningElement, api } from 'lwc';

export default class VisitFieldOrders extends LightningElement {
    @api visitId;
    @api accountId;
    @api accountName;
    @api disabled = false;
}
