import { LightningElement, track } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import getManagerQueue from '@salesforce/apex/FieldRequestService.getManagerQueue';
import approveRequest from '@salesforce/apex/FieldRequestService.approve';
import declineRequest from '@salesforce/apex/FieldRequestService.decline';
import sendToMedical from '@salesforce/apex/FieldRequestService.sendToMedical';
import { isFieldFeatureEnabled, loadFieldFeatures } from 'c/fieldFeatureFlags';

export default class FieldRequestsManagerStrip extends LightningElement {
    @track rows = [];
    featureEnabled = true;
    isBusy = false;

    connectedCallback() {
        void this.bootstrap();
    }

    get showStrip() {
        return this.featureEnabled && (this.rows || []).length > 0;
    }

    async bootstrap() {
        await loadFieldFeatures();
        this.featureEnabled = isFieldFeatureEnabled('requests.enabled');
        if (!this.featureEnabled) {
            return;
        }
        await this.refresh();
    }

    async refresh() {
        try {
            const data = await getManagerQueue();
            this.rows = (data || []).map((row) => ({
                ...row,
                summaryPreview: truncate(row.summary, 110)
            }));
        } catch (error) {
            this.rows = [];
        }
    }

    async handleApprove(event) {
        const id = event.currentTarget.dataset.id;
        this.isBusy = true;
        try {
            await approveRequest({ requestId: id, notes: null });
            this.toast('Approved', 'The rep can see this is done.', 'success');
            await this.refresh();
        } catch (error) {
            this.toast('Could not approve', errMsg(error), 'error');
        } finally {
            this.isBusy = false;
        }
    }

    async handleDecline(event) {
        const id = event.currentTarget.dataset.id;
        const reason =
            typeof window !== 'undefined'
                ? window.prompt('Tell the rep why you are declining.', '')
                : null;
        if (reason === null) {
            return;
        }
        if (!String(reason).trim()) {
            this.toast('Reason needed', 'Add a short reason for the rep.', 'warning');
            return;
        }
        this.isBusy = true;
        try {
            await declineRequest({ requestId: id, reason: String(reason).trim() });
            this.toast('Declined', 'The rep can see your reason.', 'success');
            await this.refresh();
        } catch (error) {
            this.toast('Could not decline', errMsg(error), 'error');
        } finally {
            this.isBusy = false;
        }
    }

    async handleSendMedical(event) {
        const id = event.currentTarget.dataset.id;
        this.isBusy = true;
        try {
            await sendToMedical({ requestId: id, notes: 'Sent to medical by manager.' });
            this.toast('Sent to medical', 'Medical Affairs has this request now.', 'success');
            await this.refresh();
        } catch (error) {
            this.toast('Could not send', errMsg(error), 'error');
        } finally {
            this.isBusy = false;
        }
    }

    toast(title, message, variant) {
        this.dispatchEvent(new ShowToastEvent({ title, message, variant }));
    }
}

function truncate(value, max) {
    const text = (value || '').trim();
    if (text.length <= max) {
        return text;
    }
    return `${text.slice(0, max - 1)}…`;
}

function errMsg(error) {
    return error?.body?.message || error?.message || 'Something went wrong.';
}
