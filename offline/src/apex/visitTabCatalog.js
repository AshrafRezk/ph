export const TAB_ORDER = [
    'details',
    'affiliations',
    'attendees',
    'products',
    'samples',
    'storeCheck',
    'order',
    'presentations',
    'orders',
    'requests'
];

export const TAB_LABELS = {
    details: 'Details',
    affiliations: 'Affiliations',
    attendees: 'Attendees',
    products: 'Products',
    samples: 'Dispense',
    storeCheck: 'Store Check',
    order: 'Make an Order',
    presentations: 'Presentations',
    orders: 'Orders',
    requests: 'Requests'
};

const STANDARD_TABS = [
    'details',
    'affiliations',
    'attendees',
    'products',
    'samples',
    'presentations',
    'orders',
    'requests'
];

const PHARMACY_TABS = ['details', 'storeCheck', 'order', 'presentations', 'orders', 'requests'];

export function defaultVisitTabs(developerName, recordTypeName) {
    const pharmacy =
        developerName === 'Pharmacy' || String(recordTypeName || '').toLowerCase() === 'pharmacy';
    return pharmacy ? [...PHARMACY_TABS] : [...STANDARD_TABS];
}

export function orderTabKeys(keys) {
    const enabled = new Set(keys || []);
    enabled.add('details');
    return TAB_ORDER.filter((key) => enabled.has(key));
}

export function parseTabKeys(raw) {
    if (!raw) {
        return [];
    }
    return String(raw)
        .split(',')
        .map((part) => part.trim())
        .filter((key) => TAB_LABELS[key]);
}

export function featureKeyFor(developerName) {
    return `visitTabs.${developerName}`;
}
