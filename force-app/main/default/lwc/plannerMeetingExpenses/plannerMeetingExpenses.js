import { LightningElement, api } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import getMeetingExpenses from '@salesforce/apex/MeetingPlannerController.getMeetingExpenses';
import addMeetingExpense from '@salesforce/apex/MeetingPlannerController.addMeetingExpense';

const TYPE_OPTIONS = [
    { label: 'Travel', value: 'Travel' },
    { label: 'Meal', value: 'Meal' },
    { label: 'Venue', value: 'Venue' },
    { label: 'Honoraria', value: 'Honoraria' },
    { label: 'A/V', value: 'AV' },
    { label: 'Materials', value: 'Materials' },
    { label: 'Other', value: 'Other' }
];

export default class PlannerMeetingExpenses extends LightningElement {
    @api meetingId;

    errorMessage;
    expenseType = 'Travel';
    amount;
    comments = '';
    rows = [];
    typeOptions = TYPE_OPTIONS;

    connectedCallback() {
        this.load();
    }

    get hasRows() {
        return (this.rows || []).length > 0;
    }

    get addDisabled() {
        return !this.meetingId || !this.expenseType || !(Number(this.amount) > 0);
    }

    async load() {
        if (!this.meetingId) {
            return;
        }
        try {
            const rows = await getMeetingExpenses({ meetingId: this.meetingId });
            this.rows = (rows || []).map((row) => ({
                ...row,
                amountLabel: row.amount == null ? '—' : Number(row.amount).toFixed(2)
            }));
        } catch (error) {
            this.errorMessage = error?.body?.message || error?.message || 'Unable to load expenses.';
        }
    }

    handleType(event) {
        this.expenseType = event.detail.value;
    }
    handleAmount(event) {
        this.amount = event.detail.value;
    }
    handleComments(event) {
        this.comments = event.detail.value;
    }

    async handleAdd() {
        try {
            await addMeetingExpense({
                meetingId: this.meetingId,
                expenseType: this.expenseType,
                amount: Number(this.amount),
                comments: this.comments
            });
            this.amount = null;
            this.comments = '';
            await this.load();
            this.dispatchEvent(new ShowToastEvent({ title: 'Expense added', variant: 'success' }));
        } catch (error) {
            this.dispatchEvent(
                new ShowToastEvent({
                    title: 'Unable to add expense',
                    message: error?.body?.message || error?.message,
                    variant: 'error'
                })
            );
        }
    }
}