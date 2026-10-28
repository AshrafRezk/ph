import { createElement } from 'lwc';
import TerritoryManagementConsole from 'c/territoryManagementConsole';
import applyRealignedSalesLines from '@salesforce/apex/CommercialLineAssignmentService.applyRealignedSalesLines';
import seatMarketingOnOrganogram from '@salesforce/apex/BrandManagerSeatService.seatMarketingOnOrganogram';
import mirrorAllPromotedLines from '@salesforce/apex/TerritoryManagementController.mirrorAllPromotedLines';

jest.mock(
    '@salesforce/apex/CommercialLineAssignmentService.applyRealignedSalesLines',
    () => ({ default: jest.fn(() => Promise.resolve({ message: 'ok' })) }),
    { virtual: true }
);
jest.mock(
    '@salesforce/apex/BrandManagerSeatService.seatMarketingOnOrganogram',
    () => ({ default: jest.fn(() => Promise.resolve({ messages: ['ok'] })) }),
    { virtual: true }
);
jest.mock(
    '@salesforce/apex/TerritoryManagementController.mirrorAllPromotedLines',
    () => ({ default: jest.fn(() => Promise.resolve({ updated: 0, failed: 0 })) }),
    { virtual: true }
);

// eslint-disable-next-line @lwc/lwc/no-async-operation
const flushPromises = () => new Promise((resolve) => jest.requireActual('timers').setImmediate(resolve));

const ONE_OFF_LABELS = [
    'Apply October line assignments',
    'Apply CHC / GIT / CVM mirrors',
    'Seat Brand Managers / Group Brand Leads'
];

function buttons(element) {
    return [...element.shadowRoot.querySelectorAll('lightning-button')];
}

function byLabel(element, label) {
    return buttons(element).find((b) => b.label === label);
}

async function mount() {
    const element = createElement('c-territory-management-console', { is: TerritoryManagementConsole });
    document.body.appendChild(element);
    await flushPromises();
    return element;
}

async function openMaintenance(element) {
    element.shadowRoot.querySelector('.maintenance-toggle').click();
    await flushPromises();
}

describe('c-territory-management-console maintenance actions', () => {
    beforeEach(() => jest.clearAllMocks());

    afterEach(() => {
        while (document.body.firstChild) document.body.removeChild(document.body.firstChild);
    });

    it('hides the one-off buttons until Maintenance is expanded', async () => {
        const element = await mount();
        ONE_OFF_LABELS.forEach((label) => expect(byLabel(element, label)).toBeUndefined());

        await openMaintenance(element);
        ONE_OFF_LABELS.forEach((label) => expect(byLabel(element, label)).toBeDefined());
    });

    it('asks for an in-page confirmation and runs nothing on Cancel', async () => {
        const element = await mount();
        await openMaintenance(element);
        byLabel(element, 'Apply October line assignments').click();
        await flushPromises();

        const dialog = element.shadowRoot.querySelector('.maintenance-confirm');
        expect(dialog.textContent).toContain('Apply October line assignments?');
        expect(applyRealignedSalesLines).not.toHaveBeenCalled();

        element.shadowRoot.querySelector('.maintenance-cancel-btn').click();
        await flushPromises();
        expect(element.shadowRoot.querySelector('.maintenance-confirm')).toBeNull();
        expect(applyRealignedSalesLines).not.toHaveBeenCalled();
    });

    it.each([
        ['Apply October line assignments', applyRealignedSalesLines],
        ['Apply CHC / GIT / CVM mirrors', mirrorAllPromotedLines],
        ['Seat Brand Managers / Group Brand Leads', seatMarketingOnOrganogram]
    ])('runs "%s" only after confirming', async (label, apex) => {
        const element = await mount();
        await openMaintenance(element);
        byLabel(element, label).click();
        await flushPromises();
        expect(apex).not.toHaveBeenCalled();

        element.shadowRoot.querySelector('.maintenance-confirm-btn').click();
        await flushPromises();
        expect(apex).toHaveBeenCalledTimes(1);
        expect(element.shadowRoot.querySelector('.maintenance-confirm')).toBeNull();
    });
});
