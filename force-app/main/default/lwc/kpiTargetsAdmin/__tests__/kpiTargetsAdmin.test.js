import { createElement } from 'lwc';
import KpiTargetsAdmin from 'c/kpiTargetsAdmin';
import resetToFrameworkDefaults from '@salesforce/apex/KpiTargetService.resetToFrameworkDefaults';

jest.mock(
    '@salesforce/apex/KpiTargetService.getCatalog',
    () => ({
        default: jest.fn(() =>
            Promise.resolve({ rows: [], countSources: [], metricPresets: [], roleKeys: [], needsSeed: false })
        )
    }),
    { virtual: true }
);
jest.mock('@salesforce/apex/KpiTargetService.saveTargets', () => ({ default: jest.fn() }), { virtual: true });
jest.mock(
    '@salesforce/apex/KpiTargetService.resetToFrameworkDefaults',
    () => ({ default: jest.fn(() => Promise.resolve([])) }),
    { virtual: true }
);
jest.mock('@salesforce/apex/KpiTargetService.seedFrameworkDefaults', () => ({ default: jest.fn() }), { virtual: true });
jest.mock('@salesforce/apex/KpiTargetService.addTarget', () => ({ default: jest.fn() }), { virtual: true });
jest.mock('@salesforce/apex/KpiTargetService.deleteTarget', () => ({ default: jest.fn() }), { virtual: true });

// eslint-disable-next-line @lwc/lwc/no-async-operation
const flushPromises = () => new Promise((resolve) => jest.requireActual('timers').setImmediate(resolve));

async function mount() {
    const element = createElement('c-kpi-targets-admin', { is: KpiTargetsAdmin });
    document.body.appendChild(element);
    await flushPromises();
    return element;
}

async function click(element, selector) {
    element.shadowRoot.querySelector(selector).click();
    await flushPromises();
}

describe('c-kpi-targets-admin reset to framework', () => {
    let confirmSpy;

    beforeEach(() => {
        jest.clearAllMocks();
        confirmSpy = jest.spyOn(window, 'confirm').mockReturnValue(true);
    });

    afterEach(() => {
        confirmSpy.mockRestore();
        while (document.body.firstChild) document.body.removeChild(document.body.firstChild);
    });

    it('shows an in-page confirmation instead of window.confirm and does not reset yet', async () => {
        const element = await mount();
        expect(element.shadowRoot.querySelector('.reset-confirm')).toBeNull();
        await click(element, '.reset-btn');
        expect(element.shadowRoot.querySelector('.reset-confirm').textContent).toContain('custom metrics are removed');
        expect(confirmSpy).not.toHaveBeenCalled();
        expect(resetToFrameworkDefaults).not.toHaveBeenCalled();
    });

    it('does not reset on Cancel', async () => {
        const element = await mount();
        await click(element, '.reset-btn');
        await click(element, '.reset-cancel-btn');
        expect(element.shadowRoot.querySelector('.reset-confirm')).toBeNull();
        expect(resetToFrameworkDefaults).not.toHaveBeenCalled();
    });

    it('resets once after confirming', async () => {
        const element = await mount();
        await click(element, '.reset-btn');
        await click(element, '.reset-confirm-btn');
        expect(resetToFrameworkDefaults).toHaveBeenCalledTimes(1);
        expect(element.shadowRoot.querySelector('.reset-confirm')).toBeNull();
    });
});
