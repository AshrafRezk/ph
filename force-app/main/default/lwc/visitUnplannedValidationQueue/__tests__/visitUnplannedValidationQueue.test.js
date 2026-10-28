import { createElement } from 'lwc';
import VisitUnplannedValidationQueue from 'c/visitUnplannedValidationQueue';
import loadPendingUnplannedReviews from '@salesforce/apex/VisitValidationController.loadPendingUnplannedReviews';
import validateUnplannedVisit from '@salesforce/apex/VisitValidationController.validateUnplannedVisit';

jest.mock(
    '@salesforce/apex/VisitValidationController.loadPendingUnplannedReviews',
    () => ({ default: jest.fn() }),
    { virtual: true }
);
jest.mock(
    '@salesforce/apex/VisitValidationController.validateUnplannedVisit',
    () => ({ default: jest.fn(() => Promise.resolve()) }),
    { virtual: true }
);

// eslint-disable-next-line @lwc/lwc/no-async-operation
const flushPromises = () => new Promise((resolve) => jest.requireActual('timers').setImmediate(resolve));

const ROWS = [
    {
        visitId: 'a0V000000000001',
        visitName: 'V-0001',
        repName: 'Rep One',
        accountName: 'Dr Late',
        completedAt: '2026-10-26T08:00:00.000Z',
        validationDueAt: '2026-10-27T08:00:00.000Z',
        isOverdue: true,
        validationStatus: 'Pending'
    },
    {
        visitId: 'a0V000000000002',
        visitName: 'V-0002',
        repName: 'Rep Two',
        accountName: 'Dr Fresh',
        completedAt: '2026-10-27T09:00:00.000Z',
        validationDueAt: '2026-10-28T09:00:00.000Z',
        isOverdue: false,
        validationStatus: 'Pending'
    }
];

describe('c-visit-unplanned-validation-queue', () => {
    afterEach(() => {
        while (document.body.firstChild) {
            document.body.removeChild(document.body.firstChild);
        }
        jest.clearAllMocks();
    });

    it('loads fresh rows on open and flags overdue reviews', async () => {
        loadPendingUnplannedReviews.mockResolvedValue(ROWS);
        const element = createElement('c-visit-unplanned-validation-queue', { is: VisitUnplannedValidationQueue });
        document.body.appendChild(element);
        await flushPromises();

        expect(loadPendingUnplannedReviews).toHaveBeenCalledTimes(1);
        const rows = element.shadowRoot.querySelectorAll('.queue-row');
        expect(rows.length).toBe(2);
        expect(element.shadowRoot.querySelector('.queue-overdue-summary').textContent).toContain('1 overdue');
        const overdue = element.shadowRoot.querySelectorAll('.queue-row-due_overdue');
        expect(overdue.length).toBe(1);
        expect(overdue[0].textContent).toContain('Overdue');
    });

    it('reloads from the server after a decision instead of a cached list', async () => {
        loadPendingUnplannedReviews.mockResolvedValueOnce(ROWS).mockResolvedValueOnce([ROWS[1]]);
        const element = createElement('c-visit-unplanned-validation-queue', { is: VisitUnplannedValidationQueue });
        document.body.appendChild(element);
        await flushPromises();

        const validButton = element.shadowRoot.querySelector('lightning-button[data-status="Valid"]');
        validButton.click();
        await flushPromises();

        expect(validateUnplannedVisit).toHaveBeenCalledWith({
            visitId: 'a0V000000000001',
            validationStatus: 'Valid'
        });
        expect(loadPendingUnplannedReviews).toHaveBeenCalledTimes(2);
        expect(element.shadowRoot.querySelectorAll('.queue-row').length).toBe(1);
    });

    it('shows the empty state when nothing is pending', async () => {
        loadPendingUnplannedReviews.mockResolvedValue([]);
        const element = createElement('c-visit-unplanned-validation-queue', { is: VisitUnplannedValidationQueue });
        document.body.appendChild(element);
        await flushPromises();
        expect(element.shadowRoot.querySelector('.queue-empty')).not.toBeNull();
    });
});
