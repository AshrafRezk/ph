import { createElement } from 'lwc';
import TerritoryManagementConsole from 'c/territoryManagementConsole';
import queryManagedUsers from '@salesforce/apex/TerritoryManagementController.queryManagedUsersJson';

jest.mock(
    '@salesforce/apex/TerritoryManagementController.queryManagedUsersJson',
    () => ({ default: jest.fn() }),
    { virtual: true }
);

function page(users, titleOptions, extra = {}) {
    return {
        users,
        totalCount: extra.totalCount == null ? users.length : extra.totalCount,
        activeCount: extra.activeCount == null ? users.length : extra.activeCount,
        inactiveCount: extra.inactiveCount || 0,
        hasMore: extra.hasMore === true,
        pageNumber: extra.pageNumber || 1,
        titleOptions,
        lineOptions: extra.lineOptions || [],
        appliedSearchTerm: extra.appliedSearchTerm || '',
    };
}

function deferred() {
    let resolve;
    const promise = new Promise((r) => {
        resolve = r;
    });
    return { promise, resolve };
}

// eslint-disable-next-line @lwc/lwc/no-async-operation
const flushPromises = () => new Promise((resolve) => jest.requireActual('timers').setImmediate(resolve));

async function openUsersTab(element) {
    const tab = [...element.shadowRoot.querySelectorAll('button, [role="tab"]')].find((b) => /users/i.test(b.textContent));
    if (tab) {
        tab.click();
        await flushPromises();
    }
}

describe('c-territory-management-console users filter', () => {
    beforeEach(() => {
        jest.useFakeTimers();
        queryManagedUsers.mockReset();
    });

    afterEach(() => {
        jest.useRealTimers();
        while (document.body.firstChild) document.body.removeChild(document.body.firstChild);
    });

    it('debounces rapid title changes into one request and ignores a stale slow response', async () => {
        const first = deferred();
        queryManagedUsers.mockReturnValueOnce(first.promise); // connectedCallback load (slow)
        const element = createElement('c-territory-management-console', { is: TerritoryManagementConsole });
        document.body.appendChild(element);
        await openUsersTab(element);
        expect(queryManagedUsers).toHaveBeenCalledTimes(1);

        queryManagedUsers.mockResolvedValue(page([{ id: '005B', name: 'Rep B', title: 'Medical Rep', isActive: true }], ['DM', 'Medical Rep']));
        const select = element.shadowRoot.querySelector('lightning-combobox[value="All"], lightning-combobox');
        const titleCombo = [...element.shadowRoot.querySelectorAll('lightning-combobox')].find((c) => String(c.label || '').toLowerCase().includes('title')) || select;
        // Three quick changes: only the last one may reach the server, after the debounce.
        ['DM', 'Medical Rep', 'Medical Rep'].forEach((value) => {
            titleCombo.dispatchEvent(new CustomEvent('change', { detail: { value } }));
        });
        expect(queryManagedUsers).toHaveBeenCalledTimes(1);
        jest.advanceTimersByTime(300);
        await flushPromises();
        expect(queryManagedUsers).toHaveBeenCalledTimes(2);
        expect(JSON.parse(queryManagedUsers.mock.calls[1][0].requestJson).titleFilter).toBe('Medical Rep');
        expect(JSON.parse(queryManagedUsers.mock.calls[1][0].requestJson).pageNumber).toBe(1);

        // Now the slow first response arrives. It is stale and must not replace the newer rows or the options.
        first.resolve(page([{ id: '005A', name: 'Stale Rep', title: 'DM', isActive: true }], ['DM']));
        await flushPromises();
        await flushPromises();
        const text = element.shadowRoot.textContent;
        expect(text).toContain('Rep B');
        expect(text).not.toContain('Stale Rep');
    });

    it('searches as the user types and commits without waiting on the debounce', async () => {
        queryManagedUsers.mockResolvedValue(page([], []));
        const element = createElement('c-territory-management-console', { is: TerritoryManagementConsole });
        document.body.appendChild(element);
        await openUsersTab(element);
        await flushPromises();

        const input = element.shadowRoot.querySelector('[data-filter="user-search"]');
        expect(input).not.toBeNull();
        input.value = 'clou';
        input.dispatchEvent(new CustomEvent('input', { bubbles: true }));
        input.value = 'cloud';
        input.dispatchEvent(new CustomEvent('input', { bubbles: true }));
        input.value = 'cloudastick';
        input.dispatchEvent(new CustomEvent('input', { bubbles: true }));
        expect(queryManagedUsers).toHaveBeenCalledTimes(1);

        queryManagedUsers.mockResolvedValue(
            page(
                [{ id: '005C', name: 'Cloud User', email: 'a@cloudastick.com', username: 'a@cloudastick.com', isActive: true }],
                ['Medical Rep'],
                { totalCount: 1, activeCount: 1, appliedSearchTerm: 'cloudastick' }
            )
        );
        jest.advanceTimersByTime(299);
        expect(queryManagedUsers).toHaveBeenCalledTimes(1);
        jest.advanceTimersByTime(1);
        await flushPromises();
        expect(queryManagedUsers).toHaveBeenCalledTimes(2);
        const searchRequest = JSON.parse(queryManagedUsers.mock.calls[1][0].requestJson);
        expect(searchRequest.searchTerm).toBe('cloudastick');
        expect(searchRequest.pageNumber).toBe(1);
        expect(searchRequest.pageSize).toBe(25);
        expect(element.shadowRoot.textContent).toContain('Cloud User');
        expect(element.shadowRoot.textContent).not.toContain('a@cloudastick.com a@cloudastick.com');

        input.value = 'zeta';
        input.dispatchEvent(new CustomEvent('change', { bubbles: true }));
        await flushPromises();
        expect(queryManagedUsers).toHaveBeenCalledTimes(3);
        expect(JSON.parse(queryManagedUsers.mock.calls[2][0].requestJson).searchTerm).toBe('zeta');
    });

    it('pages forward and disables Next on the last page', async () => {
        queryManagedUsers.mockResolvedValue(
            page([{ id: '005D', name: 'Only User', email: 'only@zeta-pharma.com', isActive: true }], ['Medical Rep'], {
                totalCount: 40,
                activeCount: 40,
                hasMore: true
            })
        );
        const element = createElement('c-territory-management-console', { is: TerritoryManagementConsole });
        document.body.appendChild(element);
        await openUsersTab(element);
        await flushPromises();

        const buttons = () => [...element.shadowRoot.querySelectorAll('lightning-button')];
        const next = () => buttons().find((button) => button.label === 'Next');
        const previous = () => buttons().find((button) => button.label === 'Previous');
        expect(previous().disabled).toBe(true);
        expect(next().disabled).toBe(false);
        expect(element.shadowRoot.textContent).toContain('Showing 1–1 of 40');
        expect(element.shadowRoot.textContent).toContain('Page 1 of 2');

        queryManagedUsers.mockResolvedValue(
            page([{ id: '005E', name: 'Page Two', email: 'two@zeta-pharma.com', isActive: true }], ['Medical Rep'], {
                totalCount: 40,
                activeCount: 40,
                hasMore: false,
                pageNumber: 2
            })
        );
        next().click();
        await flushPromises();
        expect(JSON.parse(queryManagedUsers.mock.calls.at(-1)[0].requestJson).pageNumber).toBe(2);
        expect(element.shadowRoot.textContent).toContain('Page Two');
        expect(next().disabled).toBe(true);
        expect(previous().disabled).toBe(false);
    });
});
