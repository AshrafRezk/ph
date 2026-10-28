import { makeDualApex } from './_wireAdapter.js';
import { plannerApiFetch } from './restHelper.js';
import { readCachedFieldFeatures } from './getEnabledFeatureMap.js';
import { iconForRecordType, toHit } from '../accountLookupSearch.js';

function esc(value) {
    return String(value || '').replace(/\\/g, '\\\\').replace(/'/g, "\\'");
}

async function soql(query) {
    const data = await plannerApiFetch(
        `/services/data/v62.0/query?q=${encodeURIComponent(query)}`
    );
    return data?.records || [];
}

async function getCreateContext(params = {}) {
    if (import.meta.env.DEV && globalThis.__ZETA_LOOKUP_PREVIEW__?.orderContext) {
        return globalThis.__ZETA_LOOKUP_PREVIEW__.orderContext(params);
    }
    const features = readCachedFieldFeatures();
    const accountId = params.accountId || null;
    const visitId = params.visitId || null;
    const ctx = {
        ordersEnabled: features.orders !== false,
        defaultAccountId: accountId,
        defaultVisitId: visitId,
        defaultAccountName: null,
        defaultRecordTypeLabel: null,
        defaultIconName: null,
        productOptions: [],
        accountHints: [],
        distributorOptions: [
            'Ibn Sina',
            'Sofico',
            'EPDA',
            'Egydrug',
            'Elezaby',
            'Pharmaoverseas',
            'Other'
        ].map((value) => ({ label: value, value }))
    };

    if (visitId) {
        const visits = await soql(
            `SELECT Id, Account__c, Account__r.Name, Account__r.RecordType.Name, Account__r.RecordType.DeveloperName FROM Visit__c WHERE Id = '${esc(visitId)}' LIMIT 1`
        );
        if (visits[0]) {
            ctx.defaultVisitId = visits[0].Id;
            ctx.defaultAccountId = visits[0].Account__c || accountId;
            ctx.defaultAccountName = visits[0].Account__r?.Name || null;
            ctx.defaultRecordTypeLabel = visits[0].Account__r?.RecordType?.Name || null;
            ctx.defaultIconName = iconForRecordType(visits[0].Account__r?.RecordType?.DeveloperName);
        }
    } else if (accountId) {
        const accounts = await soql(
            `SELECT Id, Name, RecordType.Name, RecordType.DeveloperName FROM Account WHERE Id = '${esc(accountId)}' LIMIT 1`
        );
        ctx.defaultAccountName = accounts[0]?.Name || null;
        ctx.defaultRecordTypeLabel = accounts[0]?.RecordType?.Name || null;
        ctx.defaultIconName = iconForRecordType(accounts[0]?.RecordType?.DeveloperName);
    }

    try {
        const products = await soql(
            'SELECT Id, Name, Product_Type__c, Product_Image_URL__c FROM Product2 WHERE IsActive = true ORDER BY Name LIMIT 50'
        );
        ctx.productOptions = products.map((row) => ({
            label: row.Name,
            value: row.Id,
            iconName: productIcon(row.Product_Type__c),
            imageUrl: row.Product_Image_URL__c || null,
            hint: row.Product_Type__c || null
        }));
    } catch (_err) {
        ctx.productOptions = [];
    }

    if (!ctx.defaultAccountId) {
        try {
            const identity = await plannerApiFetch('/services/oauth2/userinfo');
            const userId = identity?.user_id;
            if (userId) {
                const visits = await soql(
                    `SELECT Id, Name, Account__c, Account__r.Name, Account__r.RecordType.Name, Account__r.RecordType.DeveloperName, Start_Date__c FROM Visit__c WHERE Assigned_To__c = '${esc(userId)}' AND Account__c != null ORDER BY Start_Date__c DESC LIMIT 20`
                );
                const seen = new Set();
                const todayStart = new Date();
                todayStart.setHours(0, 0, 0, 0);
                const tomorrow = todayStart.getTime() + 86400000;
                ctx.accountHints = visits
                    .filter((row) => row.Account__c && !seen.has(row.Account__c) && seen.add(row.Account__c))
                    .slice(0, 8)
                    .map((row) => {
                        const when = row.Start_Date__c ? new Date(row.Start_Date__c).getTime() : 0;
                        const reason = when >= todayStart.getTime() && when < tomorrow ? 'Today' : 'Recent';
                        return toHit(
                            {
                                Id: row.Account__c,
                                Name: row.Account__r?.Name,
                                RecordType: row.Account__r?.RecordType,
                                visitId: row.Id,
                                visitLabel: row.Name
                            },
                            reason
                        );
                    });
            }
        } catch (_err) {
            ctx.accountHints = [];
        }
    }

    return ctx;
}

function productIcon(productType) {
    if (productType === 'Sample') return 'standard:medication';
    if (productType === 'Detail') return 'standard:article';
    if (productType === 'Brand Reminder') return 'standard:reward';
    return 'standard:product';
}

export default makeDualApex(getCreateContext);
