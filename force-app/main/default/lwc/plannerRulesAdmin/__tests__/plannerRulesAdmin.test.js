import { createElement } from 'lwc';
import PlannerRulesAdmin from 'c/plannerRulesAdmin';
import getRuleForScope from '@salesforce/apex/PlannerRulesService.getRuleForScope';
import saveRuleForScope from '@salesforce/apex/PlannerRulesService.saveRuleForScope';
import saveRuleForScopes from '@salesforce/apex/PlannerRulesService.saveRuleForScopes';
import searchUsersForException from '@salesforce/apex/PlannerRulesService.searchUsersForException';

const RULE = {
    id: null,
    workingDays: 'SUN,MON,TUE,WED,THU',
    dayOptions: [
        { value: 'SAT', label: 'Saturday', selected: false },
        { value: 'SUN', label: 'Sunday', selected: true },
        { value: 'MON', label: 'Monday', selected: true },
        { value: 'TUE', label: 'Tuesday', selected: true },
        { value: 'WED', label: 'Wednesday', selected: true },
        { value: 'THU', label: 'Thursday', selected: true },
        { value: 'FRI', label: 'Friday', selected: false }
    ],
    scopeLabel: 'Title · Medical Representative'
};

jest.mock(
    '@salesforce/apex/PlannerRulesService.getRuleForScope',
    () => ({ default: jest.fn() }),
    { virtual: true }
);
jest.mock('@salesforce/apex/PlannerRulesService.saveRuleForScope', () => ({ default: jest.fn() }), { virtual: true });
jest.mock('@salesforce/apex/PlannerRulesService.saveRuleForScopes', () => ({ default: jest.fn() }), {
    virtual: true
});
jest.mock('@salesforce/apex/PlannerRulesService.listScopedRules', () => ({ default: jest.fn(() => Promise.resolve([])) }), {
    virtual: true
});
jest.mock(
    '@salesforce/apex/PlannerRulesService.listLineOptions',
    () => ({
        default: jest.fn(() =>
            Promise.resolve([
                { label: 'CHC', value: 'CHC' },
                { label: 'PEDIA', value: 'PEDIA' }
            ])
        )
    }),
    { virtual: true }
);
jest.mock(
    '@salesforce/apex/PlannerRulesService.listTitleOptions',
    () => ({
        default: jest.fn(() =>
            Promise.resolve([
                { label: 'Medical Representative', value: 'Medical Representative' },
                { label: 'District Sales Manager', value: 'District Sales Manager' }
            ])
        )
    }),
    { virtual: true }
);
jest.mock(
    '@salesforce/apex/PlannerRulesService.listProfileOptions',
    () => ({
        default: jest.fn(() =>
            Promise.resolve([
                { label: 'Zeta Medical Rep', value: 'p1' },
                { label: 'Zeta District Manager', value: 'p2' }
            ])
        )
    }),
    { virtual: true }
);
jest.mock('@salesforce/apex/PlannerRulesService.searchUsersForException', () => ({ default: jest.fn() }), {
    virtual: true
});
jest.mock('@salesforce/apex/PlannerRulesService.deleteScopedRule', () => ({ default: jest.fn() }), { virtual: true });

// eslint-disable-next-line @lwc/lwc/no-async-operation
const flushPromises = () => new Promise((resolve) => jest.requireActual('timers').setImmediate(resolve));

async function openTab(scope) {
    const element = createElement('c-planner-rules-admin', { is: PlannerRulesAdmin });
    document.body.appendChild(element);
    await flushPromises();
    element.shadowRoot.querySelector(`button[data-scope="${scope}"]`).click();
    await flushPromises();
    return element;
}

const openTitleTab = () => openTab('Title');

async function pick(element, index, value) {
    element.shadowRoot
        .querySelectorAll('lightning-dual-listbox')
        [index].dispatchEvent(new CustomEvent('change', { detail: { value } }));
    await flushPromises();
}

function saveButton(element) {
    return Array.from(element.shadowRoot.querySelectorAll('lightning-button')).find((b) =>
        String(b.label).startsWith('Save')
    );
}

describe('c-planner-rules-admin positions', () => {
    beforeEach(() => {
        jest.clearAllMocks();
        getRuleForScope.mockResolvedValue(RULE);
        saveRuleForScope.mockResolvedValue(RULE);
        saveRuleForScopes.mockResolvedValue(RULE);
    });

    afterEach(() => {
        while (document.body.firstChild) document.body.removeChild(document.body.firstChild);
    });

    it('lets SFE pick several positions and saves one setting for all of them', async () => {
        const element = await openTitleTab();
        const picker = element.shadowRoot.querySelector('lightning-dual-listbox');
        expect(picker).not.toBeNull();
        picker.dispatchEvent(
            new CustomEvent('change', { detail: { value: ['Medical Representative', 'District Sales Manager'] } })
        );
        await flushPromises();

        expect(getRuleForScope).toHaveBeenLastCalledWith({ scopeLevel: 'Title', scopeKey: 'Medical Representative' });
        expect(element.shadowRoot.querySelector('.banner').textContent).toContain('2 positions selected');
        const save = saveButton(element);
        expect(save.label).toBe('Save for 2 positions');
        save.click();
        await flushPromises();

        expect(saveRuleForScope).not.toHaveBeenCalled();
        expect(saveRuleForScopes).toHaveBeenCalledWith(
            expect.objectContaining({
                scopeLevel: 'Title',
                scopeKeys: ['Medical Representative', 'District Sales Manager']
            })
        );
    });

    it('keeps the single-position save when only one is picked', async () => {
        const element = await openTitleTab();
        element.shadowRoot
            .querySelector('lightning-dual-listbox')
            .dispatchEvent(new CustomEvent('change', { detail: { value: ['District Sales Manager'] } }));
        await flushPromises();
        saveButton(element).click();
        await flushPromises();

        expect(saveRuleForScopes).not.toHaveBeenCalled();
        expect(saveRuleForScope).toHaveBeenCalledWith(
            expect.objectContaining({ scopeLevel: 'Title', scopeKey: 'District Sales Manager' })
        );
    });

    it('saves several lines at once', async () => {
        const element = await openTab('Line');
        await pick(element, 0, ['CHC', 'PEDIA']);
        const save = saveButton(element);
        expect(save.label).toBe('Save for 2 lines');
        save.click();
        await flushPromises();
        expect(saveRuleForScopes).toHaveBeenCalledWith(
            expect.objectContaining({ scopeLevel: 'Line', scopeKeys: ['CHC', 'PEDIA'] })
        );
    });

    it('crosses every picked line with every picked title', async () => {
        const element = await openTab('Line_Title');
        await pick(element, 0, ['CHC', 'PEDIA']);
        await pick(element, 1, ['Medical Representative']);
        saveButton(element).click();
        await flushPromises();
        expect(saveRuleForScopes).toHaveBeenCalledWith(
            expect.objectContaining({
                scopeLevel: 'Line_Title',
                scopeKeys: ['CHC||Medical Representative', 'PEDIA||Medical Representative']
            })
        );
    });

    it('saves several profiles at once', async () => {
        const element = await openTab('Profile');
        await pick(element, 0, ['p1', 'p2']);
        expect(element.shadowRoot.querySelector('.banner').textContent).toContain('Zeta Medical Rep');
        saveButton(element).click();
        await flushPromises();
        expect(saveRuleForScopes).toHaveBeenCalledWith(
            expect.objectContaining({ scopeLevel: 'Profile', scopeKeys: ['p1', 'p2'] })
        );
    });

    it('keeps picked users across searches and saves them together', async () => {
        searchUsersForException
            .mockResolvedValueOnce([{ value: 'u1', label: 'Amr' }])
            .mockResolvedValueOnce([{ value: 'u2', label: 'Mona' }]);
        const element = await openTab('User');
        const search = element.shadowRoot.querySelector('lightning-input');
        search.value = 'amr';
        search.dispatchEvent(new CustomEvent('change'));
        await flushPromises();
        await pick(element, 0, ['u1']);
        search.value = 'mona';
        search.dispatchEvent(new CustomEvent('change'));
        await flushPromises();
        const picker = element.shadowRoot.querySelector('lightning-dual-listbox');
        expect(picker.options.map((o) => o.value)).toEqual(['u1', 'u2']);
        await pick(element, 0, ['u1', 'u2']);
        const save = saveButton(element);
        expect(save.label).toBe('Save for 2 users');
        save.click();
        await flushPromises();
        expect(saveRuleForScopes).toHaveBeenCalledWith(
            expect.objectContaining({ scopeLevel: 'User', scopeKeys: ['u1', 'u2'] })
        );
    });
});
