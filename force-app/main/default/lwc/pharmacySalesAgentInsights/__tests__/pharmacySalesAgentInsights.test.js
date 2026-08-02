import { createElement } from 'lwc';
import PharmacySalesAgentInsights from 'c/pharmacySalesAgentInsights';
import getInsightsContext from '@salesforce/apex/PharmacySalesInsightsController.getInsightsContext';
import generateInsights from '@salesforce/apex/PharmacySalesInsightsController.generateInsights';

jest.mock(
    '@salesforce/apex/PharmacySalesInsightsController.getInsightsContext',
    () => ({ default: jest.fn() }),
    { virtual: true }
);
jest.mock(
    '@salesforce/apex/PharmacySalesInsightsController.generateInsights',
    () => ({ default: jest.fn() }),
    { virtual: true }
);
jest.mock(
    '@salesforce/apex/PharmacySalesInsightsController.updateRecommendation',
    () => ({ default: jest.fn() }),
    { virtual: true }
);
jest.mock(
    '@salesforce/apex/PharmacySalesInsightsController.applyAcceptedRecommendations',
    () => ({ default: jest.fn() }),
    { virtual: true }
);
jest.mock(
    '@salesforce/apex/PharmacySalesInsightsController.saveVision',
    () => ({ default: jest.fn() }),
    { virtual: true }
);

describe('c-pharmacy-sales-agent-insights', () => {
    afterEach(() => {
        while (document.body.firstChild) {
            document.body.removeChild(document.body.firstChild);
        }
        jest.clearAllMocks();
    });

    async function flushPromises() {
        return Promise.resolve();
    }

    async function openModal(element) {
        const openButton = element.shadowRoot.querySelector('.agent-open-btn');
        openButton.click();
        await flushPromises();
    }

    it('keeps insights collapsed in a compact strip by default', async () => {
        getInsightsContext.mockResolvedValue({
            reps: [{ value: '005000000000001AAA', label: 'Demo Rep', territoryName: 'Cairo' }],
            territories: [],
            vision: {}
        });
        generateInsights.mockResolvedValue({
            sessionId: 'a0B000000000001AAA',
            headline: 'Pharmacy sell-out is accelerating in Maadi',
            marketSummary: 'Market up 12%',
            brandSummary: 'Empacoza leads',
            planSummary: 'Plan gap next month',
            marketTrends: [],
            brandTrends: [],
            recommendations: []
        });

        const element = createElement('c-pharmacy-sales-agent-insights', {
            is: PharmacySalesAgentInsights
        });
        document.body.appendChild(element);

        await flushPromises();
        await flushPromises();

        expect(element.shadowRoot.querySelector('.agent-strip')).not.toBeNull();
        expect(element.shadowRoot.querySelector('.agent-modal')).toBeNull();
        expect(element.shadowRoot.querySelector('.agent-headline')).toBeNull();
    });

    it('opens modal with headline and prioritized recommendation cards', async () => {
        getInsightsContext.mockResolvedValue({
            reps: [{ value: '005000000000001AAA', label: 'Demo Rep', territoryName: 'Cairo' }],
            territories: [],
            vision: { visionSummary: 'Focus diabetes growth' }
        });
        generateInsights.mockResolvedValue({
            sessionId: 'a0B000000000001AAA',
            headline: 'Pharmacy sell-out is accelerating in Maadi',
            marketSummary: 'Market up 12%',
            brandSummary: 'Empacoza leads',
            planSummary: 'Plan gap next month',
            marketTrends: [],
            brandTrends: [],
            recommendations: [
                {
                    recordId: 'a0C000000000002AAA',
                    title: 'Ensure next plan',
                    description: 'Create missing plan',
                    recommendationType: 'EnsurePlan',
                    sortOrder: 2,
                    selected: true,
                    status: 'Proposed'
                },
                {
                    recordId: 'a0C000000000001AAA',
                    title: 'Increase visits',
                    description: 'Add one visit for A-class accounts',
                    recommendationType: 'UpdatePlanTarget',
                    sortOrder: 1,
                    selected: true,
                    status: 'Proposed'
                }
            ]
        });

        const element = createElement('c-pharmacy-sales-agent-insights', {
            is: PharmacySalesAgentInsights
        });
        document.body.appendChild(element);

        await flushPromises();
        await flushPromises();
        await openModal(element);

        const headline = element.shadowRoot.querySelector('.agent-headline');
        expect(headline.textContent).toBe('Pharmacy sell-out is accelerating in Maadi');

        const priorityBadges = element.shadowRoot.querySelectorAll('.rec-priority-badge');
        expect(priorityBadges[0].textContent).toBe('P1');
    });

    it('disables apply when no recommendations are selected', async () => {
        getInsightsContext.mockResolvedValue({
            reps: [{ value: '005000000000001AAA', label: 'Demo Rep', territoryName: 'Cairo' }],
            territories: [],
            vision: {}
        });
        generateInsights.mockResolvedValue({
            sessionId: 'a0B000000000001AAA',
            headline: 'Stable trends',
            marketSummary: 'Flat',
            brandSummary: 'Flat',
            planSummary: 'On track',
            marketTrends: [],
            brandTrends: [],
            recommendations: []
        });

        const element = createElement('c-pharmacy-sales-agent-insights', {
            is: PharmacySalesAgentInsights
        });
        document.body.appendChild(element);

        await flushPromises();
        await flushPromises();
        await openModal(element);

        const footerButtons = element.shadowRoot.querySelectorAll('.agent-modal-footer lightning-button');
        const applyButton = footerButtons[footerButtons.length - 1];
        expect(applyButton.label).toBe('Apply recommendations');
    });
});
