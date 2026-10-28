import { makeDualApex } from './_wireAdapter.js';
import { plannerApiFetch, isNetworkError, isOffline } from './restHelper.js';
import { queueOfflineAction } from 'c/clmOfflineSync';
import loadAccountRatingContext from './loadAccountRatingContext.js';

function escapeSoql(value) {
    return String(value || '').replace(/\\/g, '\\\\').replace(/'/g, "\\'");
}

const CALCULATED_ATF = new Set(['Matrix_Rating__c', 'Classification__c']);
const CALCULATED_ATPF = new Set(['Product_Matrix_Rating__c']);
const VALUES_CACHE_PREFIX = 'pwa_cache_rating_values.';

function writeCache(key, payload) {
    try {
        localStorage.setItem(key, JSON.stringify({ savedAt: Date.now(), payload }));
    } catch (_err) {
        /* ignore */
    }
}

function parseJsonList(raw) {
    if (!raw) return [];
    try {
        const parsed = JSON.parse(raw);
        return Array.isArray(parsed) ? parsed : [];
    } catch (_err) {
        return [];
    }
}

function parseValueJson(valueJson) {
    if (valueJson == null || valueJson === '') return null;
    try {
        return JSON.parse(valueJson);
    } catch (_err) {
        return valueJson;
    }
}

function classifyMatrix(matrixKey) {
    if (!matrixKey) return null;
    const key = String(matrixKey).toUpperCase();
    if (['A1', 'A2', 'B1'].includes(key)) return 'A';
    if (['A3', 'B2', 'C1'].includes(key)) return 'B';
    if (['B3', 'C2', 'C3'].includes(key)) return 'C';
    return null;
}

function applyAtfCalculations(atfValues) {
    const potential = atfValues.Potential__c;
    const penetration = atfValues.Penetration__c;
    if (potential == null || penetration == null || potential === '' || penetration === '') {
        return;
    }
    const matrixKey = `${potential}${penetration}`.toUpperCase();
    atfValues.Matrix_Rating__c = matrixKey.toLowerCase();
    atfValues.Classification__c = classifyMatrix(matrixKey);
}

async function findOrCreateAtf(accountId, territory2Id) {
    const existing = await plannerApiFetch(
        `/services/data/v62.0/query?q=${encodeURIComponent(
            `SELECT Id FROM Account_Territory_Fields__c
             WHERE Account__c = '${escapeSoql(accountId)}'
               AND Territory2_Id__c = '${escapeSoql(territory2Id)}'
             ORDER BY LastModifiedDate DESC LIMIT 1`
        )}`
    );
    const row = existing?.records?.[0];
    if (row?.Id) return row.Id;
    const created = await plannerApiFetch('/services/data/v62.0/sobjects/Account_Territory_Fields__c', {
        method: 'POST',
        body: JSON.stringify({
            Account__c: accountId,
            Territory2_Id__c: String(territory2Id),
            Is_Active__c: true
        })
    });
    return created?.id || null;
}

async function findOrCreateAtpf(accountId, territory2Id, product2Id) {
    const existing = await plannerApiFetch(
        `/services/data/v62.0/query?q=${encodeURIComponent(
            `SELECT Id FROM Account_Territory_Product_Fields__c
             WHERE Account__c = '${escapeSoql(accountId)}'
               AND Territory2_Id__c = '${escapeSoql(territory2Id)}'
               AND Product2_Id__c = '${escapeSoql(product2Id)}'
             ORDER BY LastModifiedDate DESC LIMIT 1`
        )}`
    );
    const row = existing?.records?.[0];
    if (row?.Id) return row.Id;
    const created = await plannerApiFetch('/services/data/v62.0/sobjects/Account_Territory_Product_Fields__c', {
        method: 'POST',
        body: JSON.stringify({
            Account__c: accountId,
            Territory2_Id__c: String(territory2Id),
            Product2_Id__c: String(product2Id),
            Is_Active__c: true
        })
    });
    return created?.id || null;
}

function collectObjectValues(inputs, objectApiName, skipFields) {
    const values = {};
    for (const input of inputs || []) {
        if (!input || input.objectApiName !== objectApiName || !input.fieldApiName) continue;
        if (skipFields?.has(input.fieldApiName)) continue;
        values[input.fieldApiName] = parseValueJson(input.valueJson);
    }
    return values;
}

async function persistOnline(accountId, territory2Id, fieldInputs, productRatings) {
    const accountValues = collectObjectValues(fieldInputs, 'Account');
    const atfValues = collectObjectValues(fieldInputs, 'Account_Territory_Fields__c', CALCULATED_ATF);
    if (Object.keys(accountValues).length) {
        await plannerApiFetch(`/services/data/v62.0/sobjects/Account/${encodeURIComponent(accountId)}`, {
            method: 'PATCH',
            body: JSON.stringify(accountValues)
        });
    }
    if (Object.keys(atfValues).length) {
        if (!territory2Id) {
            throw new Error('Unable to save territory ratings. Confirm this account is aligned to your territory.');
        }
        applyAtfCalculations(atfValues);
        const atfId = await findOrCreateAtf(accountId, territory2Id);
        if (!atfId) {
            throw new Error('Unable to create territory rating row.');
        }
        await plannerApiFetch(`/services/data/v62.0/sobjects/Account_Territory_Fields__c/${encodeURIComponent(atfId)}`, {
            method: 'PATCH',
            body: JSON.stringify(atfValues)
        });
    }
    for (const product of productRatings || []) {
        if (!product?.product2Id || !Array.isArray(product.values)) continue;
        const atpfValues = collectObjectValues(product.values, 'Account_Territory_Product_Fields__c', CALCULATED_ATPF);
        if (!Object.keys(atpfValues).length) continue;
        if (!territory2Id) {
            throw new Error('Unable to save product ratings. Confirm this account is aligned to your territory.');
        }
        const adoption = atpfValues.Adoption__c;
        const loyalty = atpfValues.Loyalty__c;
        if (adoption != null && loyalty != null && adoption !== '' && loyalty !== '') {
            atpfValues.Product_Matrix_Rating__c = `${adoption}${loyalty}`.toLowerCase();
        }
        const atpfId = await findOrCreateAtpf(accountId, territory2Id, product.product2Id);
        if (!atpfId) continue;
        await plannerApiFetch(
            `/services/data/v62.0/sobjects/Account_Territory_Product_Fields__c/${encodeURIComponent(atpfId)}`,
            {
                method: 'PATCH',
                body: JSON.stringify(atpfValues)
            }
        );
    }
}

function mergePendingValues(accountId, fieldInputs, productRatings) {
    const pending = {};
    for (const input of fieldInputs || []) {
        if (!input?.fieldApiName) continue;
        pending[input.fieldApiName] = parseValueJson(input.valueJson);
    }
    applyAtfCalculations(pending);
    for (const product of productRatings || []) {
        for (const input of product?.values || []) {
            if (!input?.fieldApiName) continue;
            pending[`${product.product2Id}.${input.fieldApiName}`] = parseValueJson(input.valueJson);
        }
    }
    writeCache(`${VALUES_CACHE_PREFIX}pending.${accountId}`, pending);
    return pending;
}

export default makeDualApex(async (params = {}) => {
    const accountId = params.accountId;
    const territory2Id = params.territory2Id || null;
    if (!accountId) {
        throw new Error('Account is required to save ratings.');
    }
    const fieldInputs = parseJsonList(params.fieldInputsJson);
    const productRatings = parseJsonList(params.productRatingsJson).map((row) => ({
        product2Id: row.product2Id,
        values: Array.isArray(row.values) ? row.values : parseJsonList(row.valuesJson || row.fieldInputsJson)
    }));
    if (!fieldInputs.length && !productRatings.some((row) => row.values?.length)) {
        throw new Error('No valid rating fields were provided. Refresh the page and try again.');
    }

    const pending = mergePendingValues(accountId, fieldInputs, productRatings);
    try {
        if (isOffline()) {
            throw new Error('offline');
        }
        await persistOnline(accountId, territory2Id, fieldInputs, productRatings);
        writeCache(`${VALUES_CACHE_PREFIX}pending.${accountId}`, null);
        try {
            localStorage.removeItem(`${VALUES_CACHE_PREFIX}pending.${accountId}`);
        } catch (_err) {
            /* ignore */
        }
    } catch (error) {
        if (!isOffline() && !isNetworkError(error) && error?.message !== 'offline') {
            throw error;
        }
        await queueOfflineAction({
            actionType: 'SAVE_ACCOUNT_RATINGS',
            accountId,
            clientActionKey: `ratings_${accountId}_${Date.now()}`,
            payloadJson: JSON.stringify({
                accountId,
                layoutId: params.layoutId || null,
                territory2Id,
                fieldInputsJson: params.fieldInputsJson,
                productRatingsJson: params.productRatingsJson,
                pending
            })
        });
    }
    return loadAccountRatingContext({ accountId });
});
