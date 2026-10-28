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

const DEFAULT_MEDICAL_TYPES = [
    'Efficacy',
    'Safety',
    'Dosing',
    'Adverse Event',
    'Administration',
    'Contraindications',
    'Drug Interactions',
    'Pregnancy/Lactation',
    'Off-label'
];
const DEFAULT_FIELD_TYPES = {
    Device: 'requests.type.device',
    'Scientific Material': 'requests.type.material',
    'Follow-up': 'requests.type.followUp',
    Sample: 'requests.type.sample',
    Other: 'requests.type.other'
};
const SERVICE_SUBTYPE = 'Service';

/**
 * Read admin-configured request types over REST (same rules as ServiceRequestTypeService.typesForCurrentUser).
 * Returns null when the object is unreadable so callers fall back to the built-in lists.
 */
async function loadConfiguredTypes() {
    try {
        const identity = await plannerApiFetch('/services/oauth2/userinfo');
        let title = '';
        if (identity?.user_id) {
            const users = await soql(
                `SELECT Title FROM User WHERE Id = '${esc(identity.user_id)}' LIMIT 1`
            );
            title = String(users[0]?.Title || '').trim().toLowerCase();
        }
        const rows = await soql(
            'SELECT Id, Name, Category__c, Subtype__c, Creator_Titles__c FROM Service_Request_Type__c ' +
                'WHERE Is_Active__c = TRUE ORDER BY Category__c, Name LIMIT 500'
        );
        const allowed = rows.filter((row) => {
            const titles = String(row.Creator_Titles__c || '').trim();
            if (!titles) return true;
            return titles
                .split(';')
                .some((part) => part.trim().toLowerCase() === title);
        });
        const byCategory = (category) =>
            allowed.filter((row) => row.Category__c === category);
        return {
            medical: byCategory('Medical')
                .filter((row) => row.Subtype__c !== SERVICE_SUBTYPE)
                .map((row) => row.Name),
            field: byCategory('Field').map((row) => row.Name),
            marketing: byCategory('Marketing').map((row) => row.Name)
        };
    } catch (_err) {
        return null;
    }
}

async function getCreateContext(params = {}) {
    if (import.meta.env.DEV && globalThis.__ZETA_LOOKUP_PREVIEW__?.requestContext) {
        return globalThis.__ZETA_LOOKUP_PREVIEW__.requestContext(params);
    }
    const features = readCachedFieldFeatures();
    const accountId = params.accountId || null;
    const visitId = params.visitId || null;
    const ctx = {
        requestsEnabled: features['requests.enabled'] !== false,
        medicalEnabled: features['requests.medical'] !== false,
        medicalTypes: DEFAULT_MEDICAL_TYPES.map((value) => ({ label: value, value })),
        fieldTypes: [],
        marketingEnabled: features['requests.marketing'] !== false,
        marketingTypes: [],
        productOptions: [],
        accountHints: [],
        defaultAccountId: accountId,
        defaultVisitId: visitId,
        defaultAccountName: null,
        defaultRecordTypeLabel: null,
        defaultIconName: null
    };
    const configured = await loadConfiguredTypes();
    if (configured?.medical?.length) {
        ctx.medicalTypes = configured.medical.map((value) => ({ label: value, value }));
    }
    const fieldNames = configured?.field?.length
        ? configured.field
        : Object.keys(DEFAULT_FIELD_TYPES);
    for (const label of fieldNames) {
        const key = DEFAULT_FIELD_TYPES[label];
        if (!key || features[key] !== false) {
            ctx.fieldTypes.push({ label, value: label });
        }
    }
    if (ctx.marketingEnabled && configured?.marketing?.length) {
        ctx.marketingTypes = configured.marketing.map((value) => ({ label: value, value }));
    }

    if (visitId) {
        const visits = await soql(
            `SELECT Id, Name, Account__c, Account__r.Name, Account__r.RecordType.Name, Account__r.RecordType.DeveloperName FROM Visit__c WHERE Id = '${esc(visitId)}' LIMIT 1`
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
            'SELECT Id, Name, Product_Type__c, Product_Image_URL__c FROM Product2 WHERE IsActive = true ORDER BY Name LIMIT 40'
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
        ctx.accountHints = await loadVisitHints(soql);
    }
    return ctx;
}

function productIcon(productType) {
    if (productType === 'Sample') return 'standard:medication';
    if (productType === 'Detail') return 'standard:article';
    if (productType === 'Brand Reminder') return 'standard:reward';
    return 'standard:product';
}

async function loadVisitHints(soql) {
    try {
        const identity = await plannerApiFetch('/services/oauth2/userinfo');
        const userId = identity?.user_id;
        if (!userId) return [];
        const visits = await soql(
            `SELECT Id, Name, Account__c, Account__r.Name, Account__r.RecordType.Name, Account__r.RecordType.DeveloperName, Start_Date__c FROM Visit__c WHERE Assigned_To__c = '${esc(userId)}' AND Account__c != null ORDER BY Start_Date__c DESC LIMIT 20`
        );
        const seen = new Set();
        const todayStart = new Date();
        todayStart.setHours(0, 0, 0, 0);
        const tomorrow = todayStart.getTime() + 86400000;
        return visits
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
    } catch (_err) {
        return [];
    }
}

export default makeDualApex(getCreateContext);
