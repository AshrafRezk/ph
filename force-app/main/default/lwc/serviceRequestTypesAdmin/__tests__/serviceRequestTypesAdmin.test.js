import { createElement } from 'lwc';
import ServiceRequestTypesAdmin from 'c/serviceRequestTypesAdmin';
import seedDefaults from '@salesforce/apex/ServiceRequestTypeService.seedDefaults';

jest.mock(
    '@salesforce/apex/ServiceRequestTypeService.listAllTypes',
    () => ({ default: jest.fn(() => Promise.resolve([])) }),
    { virtual: true }
);
jest.mock('@salesforce/apex/ServiceRequestTypeService.saveType', () => ({ default: jest.fn() }), { virtual: true });
jest.mock(
    '@salesforce/apex/ServiceRequestTypeService.seedDefaults',
    () => ({
        default: jest.fn(() => Promise.resolve({ marketingInserted: 0, medicalInserted: 0, skipped: 12 }))
    }),
    { virtual: true }
);

// eslint-disable-next-line @lwc/lwc/no-async-operation
const flushPromises = () => new Promise((resolve) => jest.requireActual('timers').setImmediate(resolve));

const SEED_LABEL = 'Load Marketing and Medical services';

async function mount() {
    const element = createElement('c-service-request-types-admin', { is: ServiceRequestTypesAdmin });
    document.body.appendChild(element);
    await flushPromises();
    return element;
}

function byLabel(element, label) {
    return [...element.shadowRoot.querySelectorAll('lightning-button')].find((b) => b.label === label);
}

async function click(element, selector) {
    element.shadowRoot.querySelector(selector).click();
    await flushPromises();
}

describe('c-service-request-types-admin seed guard', () => {
    beforeEach(() => jest.clearAllMocks());

    afterEach(() => {
        while (document.body.firstChild) document.body.removeChild(document.body.firstChild);
    });

    it('hides the seed button until Maintenance is expanded', async () => {
        const element = await mount();
        expect(byLabel(element, SEED_LABEL)).toBeUndefined();
        await click(element, '.maintenance-toggle');
        expect(byLabel(element, SEED_LABEL)).toBeDefined();
    });

    it('does not seed on Cancel', async () => {
        const element = await mount();
        await click(element, '.maintenance-toggle');
        await click(element, '.seed-btn');
        expect(element.shadowRoot.querySelector('.maintenance-confirm')).not.toBeNull();
        await click(element, '.seed-cancel-btn');
        expect(element.shadowRoot.querySelector('.maintenance-confirm')).toBeNull();
        expect(seedDefaults).not.toHaveBeenCalled();
    });

    it('seeds only after confirming', async () => {
        const element = await mount();
        await click(element, '.maintenance-toggle');
        await click(element, '.seed-btn');
        expect(seedDefaults).not.toHaveBeenCalled();
        await click(element, '.seed-confirm-btn');
        expect(seedDefaults).toHaveBeenCalledTimes(1);
    });
});
