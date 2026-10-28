import { createElement } from 'lwc';
import SfeApproverAdmin from 'c/sfeApproverAdmin';
import getSetup from '@salesforce/apex/SfeApproverAdminController.getSetup';
import saveRows from '@salesforce/apex/SfeApproverAdminController.saveRows';

jest.mock(
    '@salesforce/apex/SfeApproverAdminController.getSetup',
    () => ({ default: jest.fn() }),
    { virtual: true }
);
jest.mock(
    '@salesforce/apex/SfeApproverAdminController.newRow',
    () => ({ default: jest.fn() }),
    { virtual: true }
);
jest.mock(
    '@salesforce/apex/SfeApproverAdminController.saveRows',
    () => ({ default: jest.fn() }),
    { virtual: true }
);

const UNITS = ['CHC', 'Cluster', 'Diabetes', 'GIT', 'Training'];

const row = (overrides) => ({
    id: 'a0X000000000001',
    approverId: '005000000000001',
    approverName: 'Hamsa DiaaElDin',
    approverTitle: 'SFE',
    allLines: false,
    lines: ['Diabetes', 'GIT'],
    classification: true,
    newAccounts: true,
    isActive: true,
    ...overrides
});

const flush = () => Promise.resolve().then(() => Promise.resolve());

async function mount() {
    const element = createElement('c-sfe-approver-admin', { is: SfeApproverAdmin });
    document.body.appendChild(element);
    await flush();
    return element;
}

function button(element, label) {
    return [...element.shadowRoot.querySelectorAll('lightning-button')].find((b) => b.label === label);
}

function lineBoxes(element, rowIndex) {
    const tr = element.shadowRoot.querySelectorAll('tbody tr')[rowIndex];
    return Array.from(tr.querySelectorAll('input[data-line]'));
}

describe('c-sfe-approver-admin', () => {
    afterEach(() => {
        while (document.body.firstChild) {
            document.body.removeChild(document.body.firstChild);
        }
        jest.clearAllMocks();
    });

    it('checks the business units each approver covers', async () => {
        getSetup.mockResolvedValue({ canEdit: true, businessUnits: UNITS, rows: [row()] });
        const element = await mount();

        const headers = Array.from(element.shadowRoot.querySelectorAll('thead th')).map((th) =>
            th.textContent.trim()
        );
        expect(headers).toEqual(expect.arrayContaining(['SFE', 'All lines', ...UNITS, 'Class Engine']));

        const checked = lineBoxes(element, 0)
            .filter((input) => input.checked)
            .map((input) => input.dataset.line);
        expect(checked).toEqual(['Diabetes', 'GIT']);
    });

    it('locks every business unit on for an All lines approver', async () => {
        getSetup.mockResolvedValue({
            canEdit: true,
            businessUnits: UNITS,
            rows: [row({ approverName: 'Aya Adel', allLines: true, lines: [] })]
        });
        const element = await mount();

        const boxes = lineBoxes(element, 0);
        expect(boxes).toHaveLength(UNITS.length);
        expect(boxes.every((input) => input.checked && input.disabled)).toBe(true);
    });

    it('saves the edited lines as one row per approver', async () => {
        getSetup.mockResolvedValue({ canEdit: true, businessUnits: UNITS, rows: [row()] });
        saveRows.mockImplementation(({ rowsJson }) =>
            Promise.resolve({ canEdit: true, businessUnits: UNITS, rows: JSON.parse(rowsJson) })
        );
        const element = await mount();

        expect(button(element, 'Saved').disabled).toBe(true);

        const git = lineBoxes(element, 0).find((input) => input.dataset.line === 'GIT');
        git.checked = false;
        git.dispatchEvent(new CustomEvent('change'));
        await flush();

        const save = button(element, 'Save changes');
        expect(save.disabled).toBe(false);
        save.click();
        await flush();

        expect(saveRows).toHaveBeenCalledTimes(1);
        const sent = JSON.parse(saveRows.mock.calls[0][0].rowsJson);
        expect(sent).toEqual([
            {
                id: 'a0X000000000001',
                approverId: '005000000000001',
                allLines: false,
                lines: ['Diabetes'],
                classification: true,
                newAccounts: true,
                isActive: true
            }
        ]);
    });

    it('is read-only without edit access', async () => {
        getSetup.mockResolvedValue({ canEdit: false, businessUnits: UNITS, rows: [row()] });
        const element = await mount();

        expect(element.shadowRoot.querySelector('lightning-record-picker')).toBeNull();
        expect(element.shadowRoot.querySelector('lightning-button')).toBeNull();
        const inputs = Array.from(element.shadowRoot.querySelectorAll('tbody input'));
        expect(inputs.length).toBeGreaterThan(0);
        expect(inputs.every((input) => input.disabled)).toBe(true);
    });

    it('shows the load error instead of the empty message', async () => {
        getSetup.mockRejectedValue({ body: { message: 'Boom' } });
        const element = await mount();

        expect(element.shadowRoot.querySelector('[role="alert"]').textContent).toBe('Boom');
        expect(element.shadowRoot.textContent).not.toContain('No SFE approvers yet');
    });
});
