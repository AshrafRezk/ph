import { makeDualApex } from './_wireAdapter.js';
import { plannerApiFetch } from './restHelper.js';

const API_VERSION = 'v62.0';
const SERVICE_RECORD_TYPE = 'Service_Request';
const MEDICAL_RECORD_TYPE = 'Medical_Inquiry';
const SERVICE_QUEUE = 'Service_Team';
const MEDICAL_QUEUE = 'Medical_Affairs';

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

async function resolveRecordTypeId(developerName) {
    const rows = await soql(
        'SELECT Id FROM RecordType ' +
            `WHERE SobjectType = 'Case' AND DeveloperName = '${developerName}' LIMIT 1`
    );
    return rows[0]?.Id || null;
}

async function resolveQueueId(developerName) {
    const rows = await soql(
        `SELECT Id FROM Group WHERE Type = 'Queue' AND DeveloperName = '${developerName}' LIMIT 1`
    );
    return rows[0]?.Id || null;
}

async function resolveOwnerId(routeTo, visit) {
    const destination = routeTo || 'Service_Team';
    if (destination === 'Medical_Team') {
        const queueId = await resolveQueueId(MEDICAL_QUEUE);
        if (!queueId) {
            throw apexError('Medical Team queue is not configured.');
        }
        return queueId;
    }
    if (destination === 'Manager') {
        const managerId = visit.Assigned_To__r?.ManagerId;
        if (!managerId) {
            throw apexError('No manager is assigned for this visit.');
        }
        return managerId;
    }
    const queueId = await resolveQueueId(SERVICE_QUEUE);
    if (!queueId) {
        throw apexError('Service Team queue is not configured.');
    }
    return queueId;
}

async function resolveProductName(productId) {
    if (!productId) {
        return 'Product';
    }
    const rows = await soql(`SELECT Name FROM Product2 WHERE Id = '${esc(productId)}' LIMIT 1`);
    return rows[0]?.Name || 'Product';
}

async function createMedicalInquiry(params = {}) {
    const request = params.request || params;
    const visitId = request.visitId;
    const inquirerAccountId = request.inquirerAccountId;
    const productId = request.productId;
    const questionCategory = request.questionCategory;
    const questionText = String(request.questionText || '').trim();
    const routeTo = request.routeTo || 'Service_Team';

    if (!visitId) {
        throw apexError('Visit Id is required.');
    }
    if (!inquirerAccountId) {
        throw apexError('Select an inquirer.');
    }
    if (!productId) {
        throw apexError('Select a product.');
    }
    if (!questionCategory) {
        throw apexError('Select a service category.');
    }
    if (!questionText) {
        throw apexError('Enter the request details.');
    }

    let visits = await soql(
        'SELECT Id, Status__c, Account__c, Assigned_To__c, Assigned_To__r.ManagerId ' +
            `FROM Visit__c WHERE Id = '${esc(visitId)}' LIMIT 1`,
        { fresh: true }
    ).catch(() => []);
    if (!visits.length) {
        visits = await soql(
            `SELECT Id, Status__c, Account__c FROM Visit__c WHERE Id = '${esc(visitId)}' LIMIT 1`,
            { fresh: true }
        );
    }
    if (!visits.length) {
        throw apexError('Visit not found.');
    }
    const visit = visits[0];
    const status = visit.Status__c || '';
    if (status === 'Completed' || status === 'Cancelled') {
        throw apexError('Completed or cancelled visits cannot record new requests.');
    }
    if (inquirerAccountId !== visit.Account__c) {
        const matches = await soql(
            'SELECT Id FROM Visit_Attendee__c ' +
                `WHERE Visit__c = '${esc(visit.Id)}' AND Account__c = '${esc(inquirerAccountId)}' LIMIT 1`
        );
        if (!matches.length) {
            throw apexError('Select an inquirer from this visit.');
        }
    }

    const [serviceRecordTypeId, medicalRecordTypeId, ownerId, productName] = await Promise.all([
        resolveRecordTypeId(SERVICE_RECORD_TYPE),
        resolveRecordTypeId(MEDICAL_RECORD_TYPE),
        resolveOwnerId(routeTo, visit).catch(() => null),
        resolveProductName(productId)
    ]);
    const recordTypeId = serviceRecordTypeId || medicalRecordTypeId;
    if (!recordTypeId) {
        throw apexError('Request record type is not configured.');
    }
    const payload = {
        RecordTypeId: recordTypeId,
        AccountId: visit.Account__c,
        Visit__c: visit.Id,
        Product__c: productId,
        Inquirer_Account__c: inquirerAccountId,
        Service_Category__c: questionCategory,
        Subject: `Service Request - ${questionCategory} - ${productName}`,
        Description: questionText,
        Origin: 'Web',
        Status: 'New',
        Priority: 'Medium'
    };
    if (ownerId) {
        payload.OwnerId = ownerId;
    }
    let created;
    try {
        created = await plannerApiFetch(`/services/data/${API_VERSION}/sobjects/Case`, {
            method: 'POST',
            body: JSON.stringify(payload)
        });
    } catch (error) {
        const fallback = { ...payload };
        delete fallback.Service_Category__c;
        fallback.Question_Category__c = questionCategory;
        if (!serviceRecordTypeId && medicalRecordTypeId) {
            fallback.RecordTypeId = medicalRecordTypeId;
        }
        try {
            created = await plannerApiFetch(`/services/data/${API_VERSION}/sobjects/Case`, {
                method: 'POST',
                body: JSON.stringify(fallback)
            });
        } catch (_retryError) {
            delete fallback.OwnerId;
            created = await plannerApiFetch(`/services/data/${API_VERSION}/sobjects/Case`, {
                method: 'POST',
                body: JSON.stringify(fallback)
            }).catch(() => {
                throw error;
            });
        }
    }
    const caseId = created?.id;
    if (!caseId) {
        throw apexError('Unable to create the request.');
    }
    const createdRows = await soql(
        `SELECT Id, CaseNumber FROM Case WHERE Id = '${esc(caseId)}' LIMIT 1`,
        { fresh: true }
    );
    return {
        caseId,
        caseNumber: createdRows[0]?.CaseNumber || 'New'
    };
}

export default makeDualApex(createMedicalInquiry);
