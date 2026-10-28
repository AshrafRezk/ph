import { createElement } from 'lwc';
import VisitTabAdmin from 'c/visitTabAdmin';
import getMatrix from '@salesforce/apex/VisitTabConfigController.getMatrix';

jest.mock(
    '@salesforce/apex/VisitTabConfigController.getMatrix',
    () => ({ default: jest.fn() }),
    { virtual: true }
);
jest.mock(
    '@salesforce/apex/VisitTabConfigController.saveMatrix',
    () => ({ default: jest.fn() }),
    { virtual: true }
);

const COLUMNS = [
    { key: 'details', label: 'Details', locked: true },
    { key: 'orders', label: 'Orders', locked: false }
];

const cells = (orders) => [
    { key: 'details', enabled: true, locked: true },
    { key: 'orders', enabled: orders, locked: false }
];

const flush = () => Promise.resolve().then(() => Promise.resolve());

async function mount() {
    const element = createElement('c-visit-tab-admin', { is: VisitTabAdmin });
    document.body.appendChild(element);
    await flush();
    return element;
}

describe('c-visit-tab-admin', () => {
    afterEach(() => {
        while (document.body.firstChild) {
            document.body.removeChild(document.body.firstChild);
        }
        jest.clearAllMocks();
    });

    it('renders one row per record type Id even when developer names collide', async () => {
        getMatrix.mockResolvedValue({
            columns: COLUMNS,
            rows: [
                { recordTypeId: '012A', developerName: 'PersonAccount', label: 'Person Account', cells: cells(true) },
                { recordTypeId: '012B', developerName: 'PersonAccount', label: 'Person Account', cells: cells(true) }
            ]
        });
        const element = await mount();
        expect(element.shadowRoot.querySelectorAll('tbody tr').length).toBe(2);
    });

    it('shows the empty message only when there is no error', async () => {
        getMatrix.mockResolvedValue({ columns: COLUMNS, rows: [] });
        let element = await mount();
        expect(element.shadowRoot.textContent).toContain('No active account record types');
        document.body.removeChild(element);

        getMatrix.mockRejectedValue({ body: { message: 'Boom' } });
        element = await mount();
        expect(element.shadowRoot.querySelector('[role="alert"]').textContent).toBe('Boom');
        expect(element.shadowRoot.textContent).not.toContain('No active account record types');
    });
});
