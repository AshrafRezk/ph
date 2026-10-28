import { LightningElement } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import loadPendingUnplannedReviews from '@salesforce/apex/VisitValidationController.loadPendingUnplannedReviews';
import validateUnplannedVisit from '@salesforce/apex/VisitValidationController.validateUnplannedVisit';

const DATE_TIME_FORMAT = { month: 'short', day: 'numeric', hour: '2-digit', minute: '2-digit' };

export default class VisitUnplannedValidationQueue extends LightningElement {
    rows = [];
    isLoading = false;

    connectedCallback() {
        this.loadRows();
    }

    // Imperative, non-cacheable load: a cached wire would keep showing an empty queue
    // after reps complete new unplanned visits.
    async loadRows() {
        this.isLoading = true;
        try {
            const data = await loadPendingUnplannedReviews();
            this.rows = (data || []).map((row) => this.decorate(row));
        } catch (error) {
            this.rows = [];
            this.showToast('Could not load the queue', this.reduceError(error), 'error');
        } finally {
            this.isLoading = false;
        }
    }

    decorate(row) {
        let dueLabel = '—';
        if (row.validationDueAt) {
            dueLabel = new Date(row.validationDueAt).toLocaleString([], DATE_TIME_FORMAT);
        } else if (row.validationDueDate) {
            dueLabel = new Date(row.validationDueDate).toLocaleDateString([], {
                month: 'short',
                day: 'numeric',
                year: 'numeric'
            });
        }
        return {
            ...row,
            completedLabel: row.completedAt ? new Date(row.completedAt).toLocaleString([], DATE_TIME_FORMAT) : '—',
            dueLabel,
            dueClass: row.isOverdue ? 'queue-row-due queue-row-due_overdue' : 'queue-row-due'
        };
    }

    get hasRows() {
        return this.rows.length > 0;
    }

    get overdueCount() {
        return this.rows.filter((row) => row.isOverdue).length;
    }

    get hasOverdue() {
        return this.overdueCount > 0;
    }

    handleRefresh() {
        this.loadRows();
    }

    async handleValidate(event) {
        const visitId = event.target.dataset.visitId;
        const validationStatus = event.target.dataset.status;
        try {
            await validateUnplannedVisit({ visitId, validationStatus });
            this.showToast(
                validationStatus === 'Valid' ? 'Marked valid' : 'Marked invalid',
                'Unplanned visit validation updated.',
                'success'
            );
            await this.loadRows();
        } catch (error) {
            this.showToast('Validation failed', this.reduceError(error), 'error');
        }
    }

    showToast(title, message, variant) {
        this.dispatchEvent(new ShowToastEvent({ title, message, variant }));
    }

    reduceError(error) {
        return error?.body?.message || error?.message || 'Unexpected error';
    }
}
