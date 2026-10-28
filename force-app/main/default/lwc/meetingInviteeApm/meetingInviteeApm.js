import { LightningElement, api, track } from 'lwc';

/**
 * Slim APM glance per invited HCP on a meeting (sell-out + spend/visits/meetings).
 * Reuses accountHcpProductRoi with the invitee's Account Id.
 */
export default class MeetingInviteeApm extends LightningElement {
    @api invitees = [];
    @track selectedAccountId;

    get rows() {
        const list = Array.isArray(this.invitees) ? this.invitees : [];
        const seen = new Set();
        return list
            .filter((m) => {
                const id = m.accountId || m.customerId || m.Customer__c;
                if (!id || seen.has(id)) {
                    return false;
                }
                seen.add(id);
                return true;
            })
            .map((m) => {
                const accountId = m.accountId || m.customerId || m.Customer__c;
                const name = m.name || m.accountName || m.writeInName || 'HCP';
                const selected = accountId === this.selectedAccountId;
                return {
                    accountId,
                    name,
                    subtitle: m.specialty || m.memberType || m.type || '',
                    btnClass: selected ? 'invitee invitee_active' : 'invitee',
                    selected
                };
            });
    }

    get hasInvitees() {
        return this.rows.length > 0;
    }

    get hasSelection() {
        return !!this.selectedAccountId;
    }

    connectedCallback() {
        if (!this.selectedAccountId && this.rows.length) {
            this.selectedAccountId = this.rows[0].accountId;
        }
    }

    renderedCallback() {
        if (!this.selectedAccountId && this.rows.length) {
            this.selectedAccountId = this.rows[0].accountId;
        }
    }

    handleSelect(event) {
        this.selectedAccountId = event.currentTarget.dataset.id;
    }
}
