import { createElement } from 'lwc';
import VisitPlanApprovalQueue from 'c/visitPlanApprovalQueue';
import loadPendingPlanApprovals from '@salesforce/apex/VisitValidationController.loadPendingPlanApprovals';
import approvePlanVisit from '@salesforce/apex/FieldPlannerController.approvePlanVisit';

jest.mock(
    '@salesforce/apex/VisitValidationController.loadPendingPlanApprovals',
    () => ({ default: jest.fn() }),
    { virtual: true }
);
jest.mock(
    '@salesforce/apex/FieldPlannerController.approvePlanVisit',
    () => ({ default: jest.fn(() => Promise.resolve({})) }),
    { virtual: true }
);
jest.mock(
    '@salesforce/apex/VisitValidationController.rejectPlanVisit',
    () => ({ default: jest.fn(() => Promise.resolve()) }),
    { virtual: true }
);

// eslint-disable-next-line @lwc/lwc/no-async-operation
const flushPromises = () => new Promise((resolve) => jest.requireActual('timers').setImmediate(resolve));

describe('c-visit-plan-approval-queue', () => {
    afterEach(() => {
        while (document.body.firstChild) {
            document.body.removeChild(document.body.firstChild);
        }
        jest.clearAllMocks();
    });

    it('loads on open and reloads after approving', async () => {
        loadPendingPlanApprovals
            .mockResolvedValueOnce([
                { visitId: 'a0V000000000003', visitName: 'V-3', repName: 'Rep', startDateTime: '2026-10-28T08:00:00.000Z' }
            ])
            .mockResolvedValueOnce([]);
        const element = createElement('c-visit-plan-approval-queue', { is: VisitPlanApprovalQueue });
        document.body.appendChild(element);
        await flushPromises();
        expect(loadPendingPlanApprovals).toHaveBeenCalledTimes(1);

        const approve = Array.from(element.shadowRoot.querySelectorAll('lightning-button')).find(
            (button) => button.label === 'Approve'
        );
        approve.click();
        await flushPromises();

        expect(approvePlanVisit).toHaveBeenCalledWith({ visitId: 'a0V000000000003' });
        expect(loadPendingPlanApprovals).toHaveBeenCalledTimes(2);
    });
});
