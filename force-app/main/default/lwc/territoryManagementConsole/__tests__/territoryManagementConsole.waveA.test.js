import { createElement } from 'lwc';
import TerritoryManagementConsole from 'c/territoryManagementConsole';
import queryManagedUsers from '@salesforce/apex/TerritoryManagementController.queryManagedUsersJson';

jest.mock(
    '@salesforce/apex/TerritoryManagementController.queryManagedUsersJson',
    () => ({ default: jest.fn() }),
    { virtual: true }
);

// eslint-disable-next-line @lwc/lwc/no-async-operation
const flushPromises = () => new Promise((resolve) => jest.requireActual('timers').setImmediate(resolve));

function page(users, extra = {}) {
    return {
        users,
        totalCount: extra.totalCount == null ? users.length : extra.totalCount,
        activeCount: users.length,
        inactiveCount: 0,
        hasMore: extra.hasMore === true,
        pageNumber: extra.pageNumber || 1,
        pageSize: extra.pageSize || 25,
        titleOptions: [],
        lineOptions: [],
        appliedSearchTerm: '',
        canManageUsers: extra.canManageUsers,
        teamScoped: extra.teamScoped
    };
}

async function mount() {
    const element = createElement('c-territory-management-console', { is: TerritoryManagementConsole });
    const toasts = [];
    element.addEventListener('lightning__showtoast', (event) => toasts.push(event.detail));
    document.body.appendChild(element);
    await flushPromises();
    return { element, toasts };
}

function buttonByLabel(element, label) {
    return [...element.shadowRoot.querySelectorAll('lightning-button')].find((b) => b.label === label);
}

describe('c-territory-management-console wave A fixes', () => {
    let createObjectURL;
    let revokeObjectURL;
    let clickedDownloads;

    beforeEach(() => {
        queryManagedUsers.mockReset();
        createObjectURL = jest.fn(() => 'blob:zeta');
        revokeObjectURL = jest.fn();
        global.URL.createObjectURL = createObjectURL;
        global.URL.revokeObjectURL = revokeObjectURL;
        clickedDownloads = [];
        jest.spyOn(HTMLAnchorElement.prototype, 'click').mockImplementation(function click() {
            clickedDownloads.push({ download: this.download, attached: document.body.contains(this) });
        });
    });

    afterEach(() => {
        jest.restoreAllMocks();
        while (document.body.firstChild) document.body.removeChild(document.body.firstChild);
    });

    it('downloads every user across pages with the current filters', async () => {
        queryManagedUsers.mockResolvedValueOnce(page([{ id: '005A', name: 'Rep A', isActive: true }]));
        const { element, toasts } = await mount();

        queryManagedUsers
            .mockResolvedValueOnce(
                page([{ id: '005A', name: 'Rep A', username: 'a@zetapharma.net', isActive: true }], {
                    hasMore: true,
                    pageNumber: 1,
                    pageSize: 500
                })
            )
            .mockResolvedValueOnce(
                page([{ id: '005B', name: 'Rep, B', username: 'b@zetapharma.net', isActive: false }], {
                    hasMore: false,
                    pageNumber: 2,
                    pageSize: 500
                })
            );
        buttonByLabel(element, 'Download Users').click();
        await flushPromises();
        await flushPromises();

        const exportCalls = queryManagedUsers.mock.calls.slice(1).map((call) => JSON.parse(call[0].requestJson));
        expect(exportCalls.map((request) => request.pageNumber)).toEqual([1, 2]);
        expect(exportCalls.every((request) => request.pageSize === 500)).toBe(true);
        expect(createObjectURL).toHaveBeenCalledTimes(1);
        expect(clickedDownloads).toHaveLength(1);
        expect(clickedDownloads[0].download).toMatch(/^zeta-users-\d{4}-\d{2}-\d{2}\.csv$/);
        expect(clickedDownloads[0].attached).toBe(true);
        expect(toasts.at(-1).title).toBe('Users downloaded');
        expect(toasts.at(-1).message).toContain('2 users');
    });

    it('refuses Set OTP up front for a manager without Manage Users', async () => {
        queryManagedUsers.mockResolvedValue(
            page([{ id: '005R', name: 'Team Rep', isActive: true }], { canManageUsers: false, teamScoped: true })
        );
        const { element, toasts } = await mount();
        expect(element.shadowRoot.textContent).toContain('Showing your own team only.');

        const menu = element.shadowRoot.querySelector('lightning-button-menu[data-id="005R"]');
        expect(menu).not.toBeNull();
        menu.dispatchEvent(new CustomEvent('select', { detail: { value: 'otp' } }));
        await flushPromises();

        expect(toasts.at(-1).message).toBe('You need the Manage Users permission to change user logins.');
        expect(element.shadowRoot.querySelector('[aria-label="Set one-time password"]')).toBeNull();
    });

    it('still opens Set OTP for SFE users', async () => {
        queryManagedUsers.mockResolvedValue(page([{ id: '005S', name: 'Any Rep', isActive: true }], { canManageUsers: true }));
        const { element } = await mount();
        const menu = element.shadowRoot.querySelector('lightning-button-menu[data-id="005S"]');
        menu.dispatchEvent(new CustomEvent('select', { detail: { value: 'otp' } }));
        await flushPromises();
        expect(element.shadowRoot.querySelector('[aria-label="Set one-time password"]')).not.toBeNull();
    });

    it('Download organogram saves a file from an attached link', async () => {
        queryManagedUsers.mockResolvedValue(page([]));
        const { element, toasts } = await mount();
        buttonByLabel(element, 'Download organogram').click();
        await flushPromises();
        expect(clickedDownloads).toHaveLength(1);
        expect(clickedDownloads[0].download).toMatch(/^zeta-organogram-/);
        expect(clickedDownloads[0].attached).toBe(true);
        expect(toasts.at(-1).title).toBe('Organogram downloaded');
    });
});
