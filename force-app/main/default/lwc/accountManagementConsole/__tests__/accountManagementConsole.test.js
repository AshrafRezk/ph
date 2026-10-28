import { createElement } from 'lwc';
import AccountManagementConsole from 'c/accountManagementConsole';
import getCounts from '@salesforce/apex/AccountManagementController.getCounts';
import startWipe from '@salesforce/apex/AccountManagementController.startWipe';
import getWipeStatus from '@salesforce/apex/AccountManagementController.getWipeStatus';

jest.mock('@salesforce/apex/AccountManagementController.getCounts', () => ({ default: jest.fn(() => Promise.resolve({})) }), { virtual: true });
jest.mock('@salesforce/apex/AccountManagementController.startWipe', () => ({ default: jest.fn(() => Promise.resolve({})) }), { virtual: true });
jest.mock('@salesforce/apex/AccountManagementController.getWipeStatus', () => ({ default: jest.fn(() => Promise.resolve({})) }), { virtual: true });
jest.mock('@salesforce/apex/AccountManagementController.upsertOrganizationChunk', () => ({ default: jest.fn(() => Promise.resolve({})) }), { virtual: true });
jest.mock('@salesforce/apex/AccountManagementController.upsertDoctorChunk', () => ({ default: jest.fn(() => Promise.resolve({})) }), { virtual: true });
jest.mock('@salesforce/apex/AccountManagementController.upsertAffiliationChunk', () => ({ default: jest.fn(() => Promise.resolve({})) }), { virtual: true });
jest.mock('@salesforce/apex/AccountManagementController.exportAccounts', () => ({ default: jest.fn(() => Promise.resolve({})) }), { virtual: true });
jest.mock('@salesforce/apex/AccountManagementController.exportAffiliations', () => ({ default: jest.fn(() => Promise.resolve({})) }), { virtual: true });
jest.mock('@salesforce/apex/AccountBusinessUnitService.deactivateLink', () => ({ default: jest.fn(() => Promise.resolve({})) }), { virtual: true });
jest.mock('@salesforce/apex/AccountBusinessUnitService.exportLinks', () => ({ default: jest.fn(() => Promise.resolve({})) }), { virtual: true });
jest.mock('@salesforce/apex/AccountBusinessUnitService.listBusinessUnitOptions', () => ({ default: jest.fn(() => Promise.resolve({})) }), { virtual: true });
jest.mock('@salesforce/apex/AccountBusinessUnitService.listForAccountLive', () => ({ default: jest.fn(() => Promise.resolve({})) }), { virtual: true });
jest.mock('@salesforce/apex/AccountBusinessUnitService.searchAccounts', () => ({ default: jest.fn(() => Promise.resolve({})) }), { virtual: true });
jest.mock('@salesforce/apex/AccountBusinessUnitService.saveAccountBusinessUnitLink', () => ({ default: jest.fn(() => Promise.resolve({})) }), { virtual: true });
jest.mock('@salesforce/apex/AccountBusinessUnitService.upsertLinks', () => ({ default: jest.fn(() => Promise.resolve({})) }), { virtual: true });

// eslint-disable-next-line @lwc/lwc/no-async-operation
const flushPromises = () => new Promise((resolve) => jest.requireActual('timers').setImmediate(resolve));

const SHEET_ROWS = {
    orgs: [{ 'Organization Type Name': 'Hospital', Name: 'Cairo General', Code: 'O1' }],
    doctors: [{ Code: 'D1', Doctor: 'Dr Test' }]
};

function mount() {
    const element = createElement('c-account-management-console', { is: AccountManagementConsole });
    document.body.appendChild(element);
    return element;
}

function tabButtons(element) {
    return [...element.shadowRoot.querySelectorAll('button.tab-btn')];
}

async function openTab(element, label) {
    tabButtons(element)
        .find((b) => b.textContent.trim() === label)
        .click();
    await flushPromises();
}

async function attach(element, label, kind) {
    window.__sheetKind = kind;
    const input = [...element.shadowRoot.querySelectorAll('lightning-input')].find((i) => i.label === label);
    Object.defineProperty(input, 'files', { value: [new File(['x'], `${kind}.xlsx`)], configurable: true });
    input.dispatchEvent(new CustomEvent('change'));
    // FileReader resolves on a later tick.
    await flushPromises();
    await flushPromises();
    await flushPromises();
}

function button(element, label) {
    return [...element.shadowRoot.querySelectorAll('lightning-button')].find((b) => b.label === label);
}

describe('c-account-management-console safety', () => {
    beforeEach(() => {
        jest.clearAllMocks();
        getCounts.mockResolvedValue({ accountCount: 135183, affiliationCount: 42328 });
        window.XLSX = {
            read: () => ({ SheetNames: ['S'], Sheets: { S: {} } }),
            utils: { sheet_to_json: () => SHEET_ROWS[window.__sheetKind] }
        };
    });

    afterEach(() => {
        delete window.XLSX;
        while (document.body.firstChild) document.body.removeChild(document.body.firstChild);
    });

    it('opens on Export, not Wipe & Load, and lists Wipe & Load last', async () => {
        const element = mount();
        await flushPromises();
        const tabs = tabButtons(element);
        expect(tabs[tabs.length - 1].textContent.trim()).toBe('Wipe & Load');
        expect(element.shadowRoot.querySelector('button.tab-btn--active').textContent.trim()).toBe('Export');
        expect(element.shadowRoot.querySelector('.wipe-btn')).toBeNull();
    });

    it('keeps Import / Modify disabled until a workbook is attached', async () => {
        const element = mount();
        await flushPromises();
        await openTab(element, 'Import / Modify');
        expect(button(element, 'Import / Modify').disabled).toBe(true);

        await attach(element, 'Doctors (optional)', 'doctors');
        expect(button(element, 'Import / Modify').disabled).toBe(false);
    });

    it('enables Wipe & Load only after both files and the typed word WIPE', async () => {
        startWipe.mockResolvedValue({ jobId: '707X' });
        getWipeStatus.mockResolvedValue({ status: 'Completed', accountCount: 0 });
        const element = mount();
        await flushPromises();
        await openTab(element, 'Wipe & Load');
        expect(element.shadowRoot.querySelector('[role="alert"]').textContent).toContain('135183 accounts');

        await attach(element, 'Zeta Organizations.xlsx', 'orgs');
        await attach(element, 'Zeta Doctors.xlsx', 'doctors');
        const wipe = element.shadowRoot.querySelector('.wipe-btn');
        expect(wipe.disabled).toBe(true);

        const confirm = element.shadowRoot.querySelector('.wipe-confirm');
        confirm.dispatchEvent(new CustomEvent('change', { detail: { value: 'wipe' } }));
        await flushPromises();
        expect(wipe.disabled).toBe(true);

        confirm.dispatchEvent(new CustomEvent('change', { detail: { value: 'WIPE' } }));
        await flushPromises();
        expect(wipe.disabled).toBe(false);

        wipe.click();
        await flushPromises();
        expect(startWipe).toHaveBeenCalledTimes(1);
        // The confirmation is single-use.
        expect(element.shadowRoot.querySelector('.wipe-confirm').value).toBe('');
    });

    it('clears a typed confirmation when the admin leaves the tab', async () => {
        const element = mount();
        await flushPromises();
        await openTab(element, 'Wipe & Load');
        element.shadowRoot
            .querySelector('.wipe-confirm')
            .dispatchEvent(new CustomEvent('change', { detail: { value: 'WIPE' } }));
        await flushPromises();
        await openTab(element, 'Export');
        await openTab(element, 'Wipe & Load');
        expect(element.shadowRoot.querySelector('.wipe-confirm').value).toBe('');
        expect(startWipe).not.toHaveBeenCalled();
    });
});
