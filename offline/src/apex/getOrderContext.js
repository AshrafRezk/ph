import { makeDualApex } from './_wireAdapter.js';
import { soql, soqlOne, esc, apexError } from './learningShared.js';
import { loadTerritoryProducts } from './getTerritoryProducts.js';

function isPharmacyVisit(visit) {
    const recordType = visit?.Account__r?.RecordType || {};
    const developerName = recordType.DeveloperName || '';
    const recordTypeName = recordType.Name || '';
    return developerName === 'Pharmacy' || recordTypeName.toLowerCase() === 'pharmacy';
}

export async function loadOrderPayload(visitId) {
    const headers = await soql(
        `SELECT Id, Name, Status__c, Notes__c FROM Visit_Order__c WHERE Visit__c = '${esc(visitId)}' ORDER BY CreatedDate DESC LIMIT 1`
    );
    if (!headers.length) {
        return { status: 'Draft', notes: '', lines: [] };
    }
    const header = headers[0];
    const lines = await soql(
        'SELECT Id, Product2__c, Product2__r.Name, Quantity__c, Notes__c, Display_Order__c ' +
            `FROM Visit_Order_Line__c WHERE Visit_Order__c = '${esc(header.Id)}' ` +
            'ORDER BY Display_Order__c ASC NULLS LAST, CreatedDate ASC'
    );
    return {
        id: header.Id,
        name: header.Name,
        status: header.Status__c || 'Draft',
        notes: header.Notes__c || '',
        lines: lines.map((line) => ({
            id: line.Id,
            productId: line.Product2__c,
            productName: line.Product2__r?.Name || null,
            quantity: line.Quantity__c,
            notes: line.Notes__c || '',
            displayOrder: line.Display_Order__c == null ? null : Number(line.Display_Order__c)
        }))
    };
}

async function getOrderContext(params = {}) {
    const visitId = params.visitId;
    if (!visitId) {
        throw apexError('Visit is required.');
    }
    const visit = await soqlOne(
        'SELECT Id, Status__c, Account__r.RecordType.DeveloperName, Account__r.RecordType.Name ' +
            `FROM Visit__c WHERE Id = '${esc(visitId)}' LIMIT 1`,
        { fresh: true }
    );
    if (!visit) {
        throw apexError('Visit not found.');
    }
    const products = await loadTerritoryProducts({ visitId }).catch(() => []);
    const order = await loadOrderPayload(visitId);
    const context = {
        isPharmacy: isPharmacyVisit(visit),
        isLocked: visit.Status__c === 'Completed' || visit.Status__c === 'Cancelled',
        products: (products || []).map((row) => ({
            productId: row.productId,
            productName: row.productName
        })),
        order,
        emptyReason: ''
    };
    if (!context.products.length) {
        context.emptyReason =
            'No products are aligned to your territory. Ask your manager to review Product Territory Alignment.';
    }
    return context;
}

export default makeDualApex(getOrderContext);
