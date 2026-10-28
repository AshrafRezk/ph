import { createElement } from 'lwc';
import FieldRequestSheet from 'c/fieldRequestSheet';
import FieldOrderSheet from 'c/fieldOrderSheet';
import FieldOrdersHome from 'c/fieldOrdersHome';
import FieldRequestsHome from 'c/fieldRequestsHome';

const hints = [
    {
        accountId: '001A00000000001',
        accountName: 'عبد الحميد محمد عبد الحميد',
        recordTypeLabel: 'Pharmacy',
        iconName: 'standard:household',
        reason: 'Today',
        visitId: 'a0V000000000001'
    },
    {
        accountId: '001A00000000002',
        accountName: 'احمد ابراهيم التابعى',
        recordTypeLabel: 'HCP',
        iconName: 'standard:person_account',
        reason: 'Recent',
        visitId: 'a0V000000000002'
    },
    {
        accountId: '001A00000000003',
        accountName: 'شركه ليوني وايرنج سيستمز ايجيبت ( Leoni )',
        recordTypeLabel: 'Institution',
        iconName: 'standard:account',
        reason: 'Recent',
        visitId: 'a0V000000000003'
    },
    {
        accountId: '001A00000000004',
        accountName: 'Walid Ghoneim (Pedia)',
        recordTypeLabel: 'HCP',
        iconName: 'standard:person_account',
        reason: 'Today',
        visitId: 'a0V000000000004'
    },
    {
        accountId: '001A00000000005',
        accountName: 'Hossam Shawky (CHC)',
        recordTypeLabel: 'Business Contact',
        iconName: 'standard:contact',
        reason: 'Recent',
        visitId: 'a0V000000000005'
    },
    {
        accountId: '001A00000000006',
        accountName: 'Abdelhamid Lookup QA',
        recordTypeLabel: 'HCP',
        iconName: 'standard:person_account',
        reason: 'Recent',
        visitId: 'a0V000000000006'
    }
];

const types = (values) => values.map((value) => ({ label: value, value }));

globalThis.__ZETA_LOOKUP_PREVIEW__ = {
    requestContext(params = {}) {
        const selected = hints.find((row) => row.accountId === params.accountId);
        return {
            requestsEnabled: true,
            medicalEnabled: true,
            medicalTypes: types(['Efficacy', 'Safety', 'Dosing']),
            fieldTypes: types(['Device', 'Scientific Material', 'Follow-up', 'Sample', 'Other']),
            productOptions: [
                { label: 'Zeta product', value: '01t0', iconName: 'standard:product', hint: 'Brand' },
                { label: 'Zeta sample', value: '01t1', iconName: 'standard:medication', hint: 'Sample' }
            ],
            accountHints: selected ? [] : hints,
            defaultAccountId: selected?.accountId || null,
            defaultAccountName: selected?.accountName || null,
            defaultRecordTypeLabel: selected?.recordTypeLabel || null,
            defaultIconName: selected?.iconName || null,
            defaultVisitId: selected?.visitId || params.visitId || null
        };
    },
    orderContext() {
        return {
            ordersEnabled: true,
            productOptions: [
                { label: 'Zeta product', value: '01t0', iconName: 'standard:product', hint: 'Brand' },
                { label: 'Zeta sample', value: '01t1', iconName: 'standard:medication', hint: 'Sample' }
            ],
            distributorOptions: types(['Ibn Sina', 'Sofico', 'Other']),
            accountHints: hints,
            defaultAccountId: null
        };
    },
    orders: [
        {
            id: 'a0O1',
            name: 'FO-1042',
            accountName: 'صيدلية عبد الحميد',
            orderType: 'Direct',
            status: 'Pending Yasser',
            statusLabel: 'Pending Yasser',
            totalQuantity: 24,
            skipFullApproval: false,
            routingHint: 'Approval: DM → NAM → BU → Yasser → Finance.',
            visitId: null
        },
        {
            id: 'a0O2',
            name: 'FO-1048',
            accountName: 'Leoni Pharmacy',
            orderType: 'Direct',
            status: 'Pending Finance',
            statusLabel: 'Pending Finance',
            totalQuantity: 8,
            skipFullApproval: true,
            routingHint: 'Qty ≤ 10: full cycle skipped; Finance reviews next.',
            visitId: null
        }
    ],
    requests: [
        {
            id: 'a0R1',
            accountName: 'Walid Ghoneim (Pedia)',
            requestType: 'Sample',
            summary: 'FOC sample: Zeta product × 6.',
            status: 'With Manager',
            statusLabel: 'With your manager'
        }
    ],
    search(term) {
        const query = String(term || '').trim().toLowerCase();
        const compact = query.replace(/\s+/g, '');
        const compound =
            compact.startsWith('abdelham') || query.includes('abd elham') || query.includes('عبد');
        return hints
            .filter((row) => {
                const name = row.accountName.toLowerCase();
                if (compound && (name.includes('abdel') || row.accountName.includes('عبد الحميد'))) {
                    return true;
                }
                return name.includes(query) || row.accountName.includes(term);
            })
            .map((row) => ({ ...row, reason: 'Search' }));
    }
};

const requestSheet = createElement('c-field-request-sheet', { is: FieldRequestSheet });
const orderSheet = createElement('c-field-order-sheet', { is: FieldOrderSheet });
const ordersHome = createElement('c-field-orders-home', { is: FieldOrdersHome });
const requestsHome = createElement('c-field-requests-home', { is: FieldRequestsHome });
document.body.append(requestsHome, ordersHome, requestSheet, orderSheet);

document.getElementById('open-request').onclick = () => {
    requestSheet.openSheet({});
};
document.getElementById('open-order').onclick = () => {
    orderSheet.openSheet({});
};
document.getElementById('open-selected').onclick = () => {
    requestSheet.openSheet({ accountId: hints[0].accountId, visitId: hints[0].visitId });
};
