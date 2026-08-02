import { LightningElement, track } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';

import getNextBestCustomers from '@salesforce/apex/FieldRepHomeController.getNextBestCustomers';
import upsertVisit from '@salesforce/apex/FieldPlannerController.upsertVisit';

const RANK_META = [
    { iconName: 'utility:ribbon', iconClass: 'rank-icon rank-icon--first', label: '1st place' },
    { iconName: 'utility:diamond', iconClass: 'rank-icon rank-icon--second', label: '2nd place' },
    { iconName: 'utility:favorite', iconClass: 'rank-icon rank-icon--third', label: '3rd place' },
    { iconName: 'utility:like', iconClass: 'rank-icon rank-icon--fourth', label: '4th place' },
    { iconName: 'utility:bookmark', iconClass: 'rank-icon rank-icon--fifth', label: '5th place' }
];

const DAY_START_HOUR = 6;
const DAY_END_HOUR = 20;
const SLOT_MINUTES = 30;

function ceilToNextSlot(date) {
    const d = new Date(date);
    const minutes = d.getMinutes();
    const add = minutes % SLOT_MINUTES === 0 ? SLOT_MINUTES : SLOT_MINUTES - (minutes % SLOT_MINUTES);
    d.setMinutes(minutes + add);
    d.setSeconds(0, 0);
    return d;
}

function clampToWorkingHours(date) {
    const d = new Date(date);
    if (d.getHours() < DAY_START_HOUR) {
        d.setHours(DAY_START_HOUR, 0, 0, 0);
    }
    if (d.getHours() >= DAY_END_HOUR) {
        d.setDate(d.getDate() + 1);
        d.setHours(DAY_START_HOUR, 0, 0, 0);
    }
    return d;
}

export default class FieldRepHomeNextBestCustomer extends NavigationMixin(LightningElement) {
    @track isLoading = true;
    @track rows = [];

    connectedCallback() {
        this.init();
    }

    get hasRows() {
        return (this.rows || []).length > 0;
    }

    async init() {
        this.isLoading = true;
        try {
            const nbc = await getNextBestCustomers({ contextUserId: null, limitSize: 5 });
            this.rows = (nbc || []).map((r, index) => {
                const rankMeta = RANK_META[Math.min(index, RANK_META.length - 1)];
                return {
                    ...r,
                    callPlanLabel: `${Math.round(r.actualVisits || 0)}/${Math.round(r.targetVisits || 0)}`,
                    plannedLabel: r.planned ? 'Yes' : 'No',
                    scoreDisplay: Math.round(r.score || 0),
                    rankIconName: rankMeta.iconName,
                    rankIconClass: rankMeta.iconClass,
                    rankLabel: rankMeta.label
                };
            });
        } catch (e) {
            this.rows = [];
            this.showErrorToast(e, 'Unable to load next best customers.');
        } finally {
            this.isLoading = false;
        }
    }

    handleOpenAccount(event) {
        const accountId = event?.currentTarget?.dataset?.accountId;
        if (!accountId) {
            return;
        }
        this[NavigationMixin.Navigate]({
            type: 'standard__recordPage',
            attributes: { recordId: accountId, objectApiName: 'Account', actionName: 'view' }
        });
    }

    async handleCall(event) {
        const accountId = event?.currentTarget?.dataset?.accountId;
        if (!accountId) {
            return;
        }

        try {
            const start = clampToWorkingHours(ceilToNextSlot(new Date()));
            const end = new Date(start.getTime() + 60 * 60000);

            const created = await upsertVisit({
                visitId: null,
                accountId,
                startDateTime: start.toISOString(),
                endDateTime: end.toISOString(),
                status: 'Draft',
                visitType: 'Planned (Automatically)',
                cancellationReason: null
            });

            this.showToast('Draft created', 'Opening draft call for your next best customer.', 'success');
            this[NavigationMixin.Navigate]({
                type: 'standard__recordPage',
                attributes: { recordId: created.id, objectApiName: 'Visit__c', actionName: 'view' }
            });
        } catch (e) {
            this.showErrorToast(e, 'Unable to create a draft visit.');
        }
    }

    showToast(title, message, variant) {
        this.dispatchEvent(new ShowToastEvent({ title, message, variant }));
    }

    showErrorToast(error, fallbackMessage) {
        const message = this.reduceError(error) || fallbackMessage;
        this.dispatchEvent(new ShowToastEvent({ title: 'Error', message, variant: 'error' }));
    }

    reduceError(error) {
        if (!error) {
            return null;
        }
        if (typeof error === 'string') {
            return error;
        }
        return error?.body?.message || error?.message || null;
    }
}
