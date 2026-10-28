import { makeDualApex } from './_wireAdapter.js';
import { plannerApiFetch } from './restHelper.js';
import { loadTerritoryProducts } from './getTerritoryProducts.js';

const API_VERSION = 'v62.0';
const FALLBACK_CATEGORIES = [
    'Product Information',
    'Efficacy',
    'Safety',
    'Dosing',
    'Sample Request',
    'Complaint',
    'Adverse Event',
    'General Support',
    'Other'
];

const FALLBACK_ROUTES = [
    { label: 'Service Team', value: 'Service_Team' },
    { label: 'Medical Team', value: 'Medical_Team' },
    { label: 'Manager', value: 'Manager' }
];

function esc(value) {
    return String(value || '').replace(/\\/g, '\\\\').replace(/'/g, "\\'");
}

function apexError(message) {
    const err = new Error(message);
    err.body = { message };
    return err;
}

async function soql(query, options = {}) {
    const path = `/services/data/${API_VERSION}/query?q=${encodeURIComponent(query)}`;
    const result = await plannerApiFetch(path, options.fresh ? { fresh: true } : {});
    return result && Array.isArray(result.records) ? result.records : [];
}

async function loadQuestionCategories() {
    try {
        const describe = await plannerApiFetch(
            `/services/data/${API_VERSION}/sobjects/Case/describe`
        );
        const fields = describe?.fields || [];
        const field =
            fields.find((item) => item.name === 'Service_Category__c') ||
            fields.find((item) => item.name === 'Question_Category__c');
        const values = (field?.picklistValues || [])
            .filter((entry) => entry.active !== false)
            .map((entry) => entry.value)
            .filter(Boolean);
        if (values.length) {
            return values;
        }
    } catch (_err) {
        // Fall through to the metadata defaults.
    }
    return FALLBACK_CATEGORIES;
}

async function loadVisitProducts(visitId) {
    const territoryProducts = await loadTerritoryProducts({ visitId }).catch(() => []);
    if (territoryProducts.length) {
        return territoryProducts.map((row) => ({
            productId: row.productId,
            productName: row.productName
        }));
    }
    const details = await soql(
        'SELECT Product2__c, Product2__r.Name FROM Visit_Product_Detail__c ' +
            `WHERE Visit__c = '${esc(visitId)}' AND Product2__c != null ORDER BY Display_Order__c ASC`
    ).catch(() => []);
    const seen = new Set();
    return details
        .filter((row) => row.Product2__c && !seen.has(row.Product2__c) && seen.add(row.Product2__c))
        .map((row) => ({
            productId: row.Product2__c,
            productName: row.Product2__r?.Name || 'Product'
        }));
}

async function loadExistingInquiries(visitId) {
    const rows = await soql(
        'SELECT Id, CaseNumber, Subject, Status, CreatedDate, Owner.Name, Service_Category__c, Question_Category__c, Product__r.Name ' +
            `FROM Case WHERE Visit__c = '${esc(visitId)}' ORDER BY CreatedDate DESC LIMIT 50`
    ).catch(() =>
        soql(
            'SELECT Id, CaseNumber, Subject, Status, CreatedDate, Question_Category__c, Product__r.Name ' +
                `FROM Case WHERE Visit__c = '${esc(visitId)}' ORDER BY CreatedDate DESC LIMIT 50`
        ).catch(() => [])
    );
    return rows.map((row) => ({
        caseId: row.Id,
        caseNumber: row.CaseNumber,
        subject: row.Subject,
        status: row.Status,
        createdDate: row.CreatedDate,
        questionCategory: row.Service_Category__c || row.Question_Category__c,
        productName: row.Product__r?.Name || null,
        routedTo: row.Owner?.Name || null
    }));
}

async function loadMedicalInquiryContext(params = {}) {
    const visitId = params.visitId || params.Id;
    if (!visitId) {
        throw apexError('Visit Id is required.');
    }
    let visits = await soql(
        'SELECT Id, Name, Status__c, Account__c, Account__r.Name, Assigned_To__r.Name, Assigned_To__r.ManagerId, Assigned_To__r.Manager.Name ' +
            `FROM Visit__c WHERE Id = '${esc(visitId)}' LIMIT 1`
    ).catch(() => []);
    if (!visits.length) {
        visits = await soql(
            'SELECT Id, Name, Status__c, Account__c, Account__r.Name, Assigned_To__r.Name ' +
                `FROM Visit__c WHERE Id = '${esc(visitId)}' LIMIT 1`
        );
    }
    if (!visits.length) {
        throw apexError('Visit not found.');
    }
    const visit = visits[0];
    const inquirerById = new Map();
    if (visit.Account__c) {
        inquirerById.set(visit.Account__c, {
            accountId: visit.Account__c,
            accountName: visit.Account__r?.Name || null,
            role: 'Visit Account',
            isPrimary: true
        });
    }
    const attendees = await soql(
        'SELECT Account__c, Account__r.Name FROM Visit_Attendee__c ' +
            `WHERE Visit__c = '${esc(visit.Id)}' AND Account__c != null ORDER BY Account__r.Name ASC`
    ).catch(() => []);
    attendees.forEach((row) => {
        if (!row.Account__c || inquirerById.has(row.Account__c)) {
            return;
        }
        inquirerById.set(row.Account__c, {
            accountId: row.Account__c,
            accountName: row.Account__r?.Name || null,
            role: 'Attendee',
            isPrimary: false
        });
    });

    const products = await loadVisitProducts(visit.Id);
    const existingInquiries = await loadExistingInquiries(visit.Id);
    const questionCategories = await loadQuestionCategories();
    const status = visit.Status__c || 'Draft';

    return {
        visitId: visit.Id,
        visitName: visit.Name,
        accountName: visit.Account__r?.Name || null,
        assignedToName: visit.Assigned_To__r?.Name || null,
        defaultInquirerAccountId: visit.Account__c || null,
        isLocked: status === 'Completed' || status === 'Cancelled',
        inquirerOptions: [...inquirerById.values()],
        products,
        existingInquiries,
        questionCategories,
        routeOptions: [
            FALLBACK_ROUTES[0],
            FALLBACK_ROUTES[1],
            {
                label: visit.Assigned_To__r?.Manager?.Name
                    ? `Manager (${visit.Assigned_To__r.Manager.Name})`
                    : 'Manager',
                value: 'Manager'
            }
        ]
    };
}

export default makeDualApex(loadMedicalInquiryContext);
