import { createElement } from 'lwc';
import PublicHolidaysManager from 'c/publicHolidaysManager';
import listHolidays from '@salesforce/apex/PublicHolidayService.listHolidays';
import saveHolidayFields from '@salesforce/apex/PublicHolidayService.saveHolidayFields';
import loadEgypt2026Holidays from '@salesforce/apex/PublicHolidayService.loadEgypt2026Holidays';
import previewEgypt2026Holidays from '@salesforce/apex/PublicHolidayService.previewEgypt2026Holidays';
import LightningConfirm from 'lightning/confirm';

jest.mock('@salesforce/apex/PublicHolidayService.listHolidays', () => ({ default: jest.fn() }), { virtual: true });
jest.mock('@salesforce/apex/PublicHolidayService.saveHolidayFields', () => ({ default: jest.fn() }), {
    virtual: true
});
jest.mock('@salesforce/apex/PublicHolidayService.deleteHoliday', () => ({ default: jest.fn() }), { virtual: true });
jest.mock('@salesforce/apex/PublicHolidayService.loadEgypt2026Holidays', () => ({ default: jest.fn() }), {
    virtual: true
});
jest.mock('@salesforce/apex/PublicHolidayService.previewEgypt2026Holidays', () => ({ default: jest.fn() }), {
    virtual: true
});
jest.mock('lightning/confirm', () => ({ __esModule: true, default: { open: jest.fn() } }), { virtual: true });

// eslint-disable-next-line @lwc/lwc/no-async-operation
const flushPromises = () => new Promise((resolve) => jest.requireActual('timers').setImmediate(resolve));

const EID = { id: 'a1g000000000001', name: 'Eid al-Fitr (approx)', holidayDate: '2026-03-20', recursYearly: false, isActive: true };

async function mount() {
    const element = createElement('c-public-holidays-manager', { is: PublicHolidaysManager });
    document.body.appendChild(element);
    await flushPromises();
    return element;
}

function buttonByLabel(element, label) {
    return Array.from(element.shadowRoot.querySelectorAll('lightning-button')).find((b) => b.label === label);
}

function input(element, field) {
    return element.shadowRoot.querySelector(`lightning-input[data-field="${field}"]`);
}

describe('c-public-holidays-manager', () => {
    beforeEach(() => {
        jest.clearAllMocks();
        listHolidays.mockResolvedValue([EID]);
        saveHolidayFields.mockResolvedValue({});
    });

    afterEach(() => {
        while (document.body.firstChild) document.body.removeChild(document.body.firstChild);
    });

    it('saves a new holiday with the name and date on screen, even without change events', async () => {
        const element = await mount();
        buttonByLabel(element, 'New Holiday').click();
        await flushPromises();

        input(element, 'name').value = 'Coptic Christmas';
        input(element, 'holidayDate').value = '2027-01-07';
        buttonByLabel(element, 'Save').click();
        await flushPromises();

        expect(saveHolidayFields).toHaveBeenCalledTimes(1);
        expect(saveHolidayFields).toHaveBeenCalledWith({
            holidayId: null,
            name: 'Coptic Christmas',
            holidayDate: '2027-01-07',
            recursYearly: false,
            isActive: true
        });
        expect(element.shadowRoot.querySelector('.form-panel')).toBeNull();
    });

    it('says which field is missing and does not call the server', async () => {
        const element = await mount();
        buttonByLabel(element, 'New Holiday').click();
        await flushPromises();
        input(element, 'name').value = 'Coptic Christmas';
        buttonByLabel(element, 'Save').click();
        await flushPromises();

        expect(saveHolidayFields).not.toHaveBeenCalled();
        expect(element.shadowRoot.querySelector('.form-error').textContent).toBe(
            'Pick the holiday date from the calendar.'
        );
    });

    it('saves only once on a double click', async () => {
        let resolveSave;
        saveHolidayFields.mockImplementation(() => new Promise((resolve) => (resolveSave = resolve)));
        const element = await mount();
        buttonByLabel(element, 'New Holiday').click();
        await flushPromises();
        input(element, 'name').value = 'Coptic Christmas';
        input(element, 'holidayDate').value = '2027-01-07';
        const save = buttonByLabel(element, 'Save');
        save.click();
        save.click();
        resolveSave({});
        await flushPromises();

        expect(saveHolidayFields).toHaveBeenCalledTimes(1);
    });

    it('edits an existing holiday by id and shows the duplicate refusal on the form', async () => {
        saveHolidayFields.mockRejectedValue({ body: { message: 'Coptic Christmas is already set for that date.' } });
        const element = await mount();
        element.shadowRoot.querySelector('lightning-button[data-id="a1g000000000001"]').click();
        await flushPromises();
        input(element, 'name').value = 'Eid al-Fitr';
        input(element, 'holidayDate').value = '2027-01-07';
        buttonByLabel(element, 'Save').click();
        await flushPromises();

        expect(saveHolidayFields).toHaveBeenCalledWith(
            expect.objectContaining({ holidayId: 'a1g000000000001', name: 'Eid al-Fitr', holidayDate: '2027-01-07' })
        );
        expect(element.shadowRoot.querySelector('.form-error').textContent).toBe(
            'Coptic Christmas is already set for that date.'
        );
    });

    it('explains Load 2026 on screen and asks before adding anything', async () => {
        previewEgypt2026Holidays.mockResolvedValue([{ name: 'Christmas Eve', holidayDate: '2026-12-24' }]);
        LightningConfirm.open.mockResolvedValue(false);
        const element = await mount();
        const load = buttonByLabel(element, 'Load 2026 holidays');
        expect(load.title).toContain('Coptic Christmas');
        expect(load.title).toContain('Christmas Eve (24 Dec)');
        expect(element.shadowRoot.querySelector('.load-help').textContent).toContain('one-off 2026 date');

        load.click();
        await flushPromises();

        expect(LightningConfirm.open).toHaveBeenCalledTimes(1);
        expect(LightningConfirm.open.mock.calls[0][0].message).toContain('Christmas Eve');
        expect(loadEgypt2026Holidays).not.toHaveBeenCalled();
    });
});
