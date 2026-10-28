import { createElement } from 'lwc';
import ProductTerritoryManager from 'c/productTerritoryManager';
import getProductCatalogTree from '@salesforce/apex/ProductCatalogAdminController.getProductCatalogTree';
import getTerritoryTreeForProduct from '@salesforce/apex/ProductCatalogAdminController.getTerritoryTreeForProduct';

jest.mock(
    '@salesforce/apex/ProductCatalogAdminController.getProductCatalogTree',
    () => {
        const { createApexTestWireAdapter } = require('@salesforce/sfdx-lwc-jest');
        return { default: createApexTestWireAdapter(jest.fn()) };
    },
    { virtual: true }
);
jest.mock(
    '@salesforce/apex/ProductCatalogAdminController.getTerritoryTreeForProduct',
    () => ({ default: jest.fn() }),
    { virtual: true }
);
jest.mock(
    '@salesforce/apex/ProductCatalogAdminController.saveProductTerritoryAlignments',
    () => ({ default: jest.fn() }),
    { virtual: true }
);
jest.mock('@salesforce/apex/ProductEditorController.getEditorOptions', () => ({ default: jest.fn() }), {
    virtual: true
});
jest.mock('@salesforce/apex/ProductEditorController.getProduct', () => ({ default: jest.fn() }), {
    virtual: true
});
jest.mock('@salesforce/apex/ProductEditorController.saveProduct', () => ({ default: jest.fn() }), {
    virtual: true
});

const flushPromises = () => new Promise((resolve) => jest.requireActual('timers').setImmediate(resolve));

function product(id, label, productType, extra = {}) {
    return {
        key: id,
        productId: id,
        label,
        productType,
        externalId: id,
        isActive: true,
        children: [],
        ...extra
    };
}

const CATALOG = [
    product('01t000000000001', 'NEXICURE', 'Brand', {
        salesLine: 'GIT-I',
        children: [
            product('01t000000000002', 'NEXICURE 40 MG 20 TAB', 'Detail', { salesLine: 'GIT-SALES' }),
            product('01t000000000003', 'NEXICURE 40 MG 30 TAB', 'Detail', { salesLine: 'GIT-I' })
        ]
    }),
    product('01t000000000004', 'ZETACOLEST', 'Brand', {
        children: [product('01t000000000005', 'Zetacolest 180 mg FCT 5 FCT (FMS)', 'Sample')]
    }),
    product('01t000000000006', 'DEXIGLOFOZINF 5MG 30 TAB', null, { externalId: 'DEX5', isActive: false })
];

function territory(id, name, children = []) {
    return { id, name, hasChildren: children.length > 0, aligned: false, children };
}

const TERRITORIES = [
    territory('0MI000000000001', 'Head Office', [
        territory('0MI000000000002', 'GIT-SALES', [
            territory('0MI000000000003', 'DM CAIRO', [territory('0MI000000000004', 'CAIRO-A')])
        ]),
        territory('0MI000000000005', 'NEUROSCIENCE-II', [
            territory('0MI000000000006', 'NEUROSCIENCE-II DM ALEX', [territory('0MI000000000007', 'NEUROSCIENCE-II ALEX EAST')])
        ])
    ])
];

async function mount() {
    const element = createElement('c-product-territory-manager', { is: ProductTerritoryManager });
    document.body.appendChild(element);
    getProductCatalogTree.emit(CATALOG);
    await flushPromises();
    return element;
}

function productNames(element) {
    return Array.from(element.shadowRoot.querySelectorAll('.product-name')).map((el) => el.textContent);
}

function territoryNames(element) {
    return Array.from(element.shadowRoot.querySelectorAll('.territory-name')).map((el) => el.textContent);
}

async function search(element, label, value) {
    const input = element.shadowRoot.querySelector(`lightning-input[data-search="${label}"]`)
        || Array.from(element.shadowRoot.querySelectorAll('lightning-input')).find((el) => el.label === label);
    input.value = value;
    input.dispatchEvent(new CustomEvent('change'));
    await flushPromises();
}

async function selectProduct(element, productId) {
    element.shadowRoot.querySelector(`.product-select-btn[data-id="${productId}"]`).click();
    await flushPromises();
}

describe('c-product-territory-manager', () => {
    beforeEach(() => {
        jest.clearAllMocks();
        getTerritoryTreeForProduct.mockResolvedValue(TERRITORIES);
    });

    afterEach(() => {
        while (document.body.firstChild) document.body.removeChild(document.body.firstChild);
    });

    it('catalog search on a brand keeps all its details', async () => {
        const element = await mount();
        await search(element, 'Search products', 'NEX');
        const names = productNames(element);
        expect(names).toEqual(['NEXICURE', 'NEXICURE 40 MG 20 TAB', 'NEXICURE 40 MG 30 TAB']);
    });

    it('shows the sales line in each product line', async () => {
        const element = await mount();
        await search(element, 'Search products', 'NEX');
        const metas = Array.from(element.shadowRoot.querySelectorAll('.product-meta')).map((el) => el.textContent);
        expect(metas[1]).toContain('GIT-SALES');
    });

    it('finds inactive products with no type and marks them inactive', async () => {
        const element = await mount();
        await search(element, 'Search products', 'DEX5');
        expect(productNames(element)).toEqual(['DEXIGLOFOZINF 5MG 30 TAB']);
        const meta = element.shadowRoot.querySelector('.product-meta').textContent;
        expect(meta).toContain('No type');
        expect(meta).toContain('Inactive');
        expect(element.shadowRoot.querySelector('li.tree-row--inactive')).not.toBeNull();
    });

    it('sample search shows each sample under its brand', async () => {
        const element = await mount();
        await search(element, 'Search products', 'FMS');
        expect(productNames(element)).toEqual(['ZETACOLEST', 'Zetacolest 180 mg FCT 5 FCT (FMS)']);
    });

    it('says no match instead of asking for a seed when the search finds nothing', async () => {
        const element = await mount();
        await search(element, 'Search products', 'NOPE-XYZ');
        expect(element.shadowRoot.querySelector('.empty-state').textContent).toContain('No products match');
    });

    it('territory search shows each line with its districts, and the arrow opens the positions', async () => {
        const element = await mount();
        await selectProduct(element, '01t000000000002');
        await search(element, 'Search territories', 'GIT-SALES');
        expect(territoryNames(element)).toEqual(['Head Office', 'GIT-SALES', 'DM CAIRO']);

        element.shadowRoot.querySelector('.toggle-btn[data-id="0MI000000000003"]').click();
        await flushPromises();
        expect(territoryNames(element)).toContain('CAIRO-A');

        element.shadowRoot.querySelector('.toggle-btn[data-id="0MI000000000002"]').click();
        await flushPromises();
        expect(territoryNames(element)).toEqual(['Head Office', 'GIT-SALES']);

        await search(element, 'Search territories', 'NEUROSCIENCE-II');
        // Every row matches here (real names carry the line name), so all open; the arrow must still close them.
        expect(territoryNames(element)).toEqual([
            'Head Office',
            'NEUROSCIENCE-II',
            'NEUROSCIENCE-II DM ALEX',
            'NEUROSCIENCE-II ALEX EAST'
        ]);
        element.shadowRoot.querySelector('.toggle-btn[data-id="0MI000000000006"]').click();
        await flushPromises();
        expect(territoryNames(element)).toEqual(['Head Office', 'NEUROSCIENCE-II', 'NEUROSCIENCE-II DM ALEX']);
    });

    it('View Product opens the record in a new browser tab', async () => {
        const openSpy = jest.spyOn(window, 'open').mockReturnValue({});
        const element = await mount();
        await selectProduct(element, '01t000000000002');
        const viewButton = Array.from(element.shadowRoot.querySelectorAll('lightning-button')).find(
            (el) => el.label === 'View Product'
        );
        viewButton.click();
        await flushPromises();
        expect(openSpy).toHaveBeenCalledWith('https://www.example.com', '_blank');
        openSpy.mockRestore();
    });
});
