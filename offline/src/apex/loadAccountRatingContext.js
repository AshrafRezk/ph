import { makeDualApex } from './_wireAdapter.js';
import { plannerApiFetch, isOffline } from './restHelper.js';
import { getStoredTerritoryContext } from 'c/territoryContextClient';

function escapeSoql(value) {
    return String(value || '').replace(/\\/g, '\\\\').replace(/'/g, "\\'");
}

const LAYOUT_CACHE_PREFIX = 'pwa_cache_rating_layout.';
const VALUES_CACHE_PREFIX = 'pwa_cache_rating_values.';
const PRODUCTS_CACHE_PREFIX = 'pwa_cache_rating_products.';

function territoryIdVariants(territory2Id) {
    const full = String(territory2Id || '').trim();
    if (!full) return [];
    const variants = [full];
    if (full.length >= 15) {
        variants.push(full.substring(0, 15));
    }
    return [...new Set(variants)];
}

function soqlIdList(territory2Id) {
    return territoryIdVariants(territory2Id)
        .map((value) => `'${escapeSoql(value)}'`)
        .join(',');
}

function cacheKey(prefix, key) {
    return `${prefix}${String(key || '')}`;
}

function readCache(key) {
    try {
        const raw = localStorage.getItem(key);
        if (!raw) return null;
        return JSON.parse(raw);
    } catch (_err) {
        return null;
    }
}

function writeCache(key, payload) {
    try {
        localStorage.setItem(key, JSON.stringify({ savedAt: Date.now(), payload }));
    } catch (_err) {
        /* storage full */
    }
}

function resolveLayoutVariant(fieldsJson) {
    try {
        const parsed = JSON.parse(fieldsJson || '{}');
        const variant = String(parsed?.accountVariant || '').toUpperCase();
        if (variant === 'HCO' || variant === 'HCP') return variant;
    } catch (_err) {
        /* ignore */
    }
    return 'HCP';
}

function emptyContext(variant = 'HCP') {
    return {
        layoutId: null,
        layoutJson: null,
        accountVariant: variant,
        territory2Id: null,
        territoryName: null,
        alignedProducts: [],
        valuesJson: '{}'
    };
}

async function resolveTerritory(accountId) {
    const stored = getStoredTerritoryContext?.() || {};
    if (stored.territoryId || stored.territory2Id || stored.activeTerritory2Id) {
        return {
            territory2Id: stored.territoryId || stored.territory2Id || stored.activeTerritory2Id,
            territoryName: stored.territoryName || stored.activeTerritoryName || null
        };
    }
    try {
        const userId = (localStorage.getItem('zeta.pwa.sfUserId') || '').trim();
        if (userId) {
            const uta = await plannerApiFetch(
                `/services/data/v62.0/query?q=${encodeURIComponent(
                    `SELECT Territory2Id, Territory2.Name FROM UserTerritory2Association WHERE UserId = '${escapeSoql(userId)}' LIMIT 5`
                )}`
            );
            const row = uta?.records?.[0];
            if (row?.Territory2Id) {
                return { territory2Id: row.Territory2Id, territoryName: row.Territory2?.Name || null };
            }
        }
    } catch (_err) {
        /* optional */
    }
    if (!accountId) {
        return { territory2Id: null, territoryName: null };
    }
    try {
        const atf = await plannerApiFetch(
            `/services/data/v62.0/query?q=${encodeURIComponent(
                `SELECT Territory2_Id__c FROM Account_Territory_Fields__c
                 WHERE Account__c = '${escapeSoql(accountId)}' AND Is_Active__c = true
                 ORDER BY LastModifiedDate DESC LIMIT 1`
            )}`
        );
        const territory2Id = atf?.records?.[0]?.Territory2_Id__c || null;
        return { territory2Id, territoryName: null };
    } catch (_err) {
        return { territory2Id: null, territoryName: null };
    }
}

async function loadDeployedLayouts(variant) {
    const cacheKeyName = cacheKey(LAYOUT_CACHE_PREFIX, variant || 'ALL');
    if (isOffline()) {
        const cached = readCache(cacheKeyName);
        if (cached?.payload) return cached.payload;
    }
    const layouts = await plannerApiFetch(
        `/services/data/v62.0/query?q=${encodeURIComponent(
            `SELECT Id, Name, Fields_JSON__c, Status__c, LastModifiedDate
             FROM CLM_Rating_Layout__c
             WHERE Status__c = 'Deployed'
             ORDER BY LastModifiedDate DESC
             LIMIT 20`
        )}`
    );
    const records = layouts?.records || [];
    writeCache(cacheKeyName, records);
    writeCache(cacheKey(LAYOUT_CACHE_PREFIX, 'ALL'), records);
    return records;
}

function pickLayout(records, variant) {
    const matched = records.find((row) => resolveLayoutVariant(row.Fields_JSON__c) === variant);
    return matched || records[0] || null;
}

const HCP_CLASSIFICATION_OPTIONS = ['A1', 'A2', 'A3', 'B1', 'B2', 'B3', 'C1', 'C2', 'C3'].map(
    (value) => ({ label: value, value })
);

function productNumberField(fieldApiName, label, order) {
    return {
        objectApiName: 'Account_Territory_Product_Fields__c',
        fieldApiName,
        label,
        widget: 'numberDonut',
        order
    };
}

function ensureProductPotentialPenetrationFields(parsed) {
    const sections = parsed?.sections;
    if (!sections) return parsed;
    const fields = Array.isArray(sections.accountTerritoryProduct)
        ? [...sections.accountTerritoryProduct]
        : [];
    const indexOf = (apiName) => fields.findIndex((field) => field.fieldApiName === apiName);
    let potentialIndex = indexOf('Potential__c');
    if (potentialIndex < 0) {
        fields.unshift(productNumberField('Potential__c', 'Potentiality', 5));
        potentialIndex = 0;
    } else if (fields[potentialIndex]) {
        fields[potentialIndex] = { ...fields[potentialIndex], widget: 'numberDonut' };
    }
    const penetrationIndex = indexOf('Penetration__c');
    if (penetrationIndex < 0) {
        fields.splice(potentialIndex + 1, 0, productNumberField('Penetration__c', 'Penetration', 8));
    } else if (fields[penetrationIndex]) {
        fields[penetrationIndex] = { ...fields[penetrationIndex], widget: 'numberDonut' };
    }
    const ensurePicklist = (apiName, label, order, options) => {
        const idx = indexOf(apiName);
        if (idx < 0) {
            fields.push({
                objectApiName: 'Account_Territory_Product_Fields__c',
                fieldApiName: apiName,
                label,
                widget: 'picklist',
                order,
                options
            });
        }
    };
    const ensureNumber = (apiName, label, order) => {
        if (indexOf(apiName) < 0) {
            fields.push(productNumberField(apiName, label, order));
        }
    };
    ensurePicklist('UOM__c', 'UOM', 30, [
        { label: 'Box', value: 'Box' },
        { label: 'Pack', value: 'Pack' },
        { label: 'Bottle', value: 'Bottle' },
        { label: 'Unit', value: 'Unit' }
    ]);
    ensureNumber('Average_Market_UOM_Cost__c', 'Avg market cost / UOM (EGP)', 40);
    ensureNumber('Total_Volume_UOM__c', 'Total volume (UOM)', 50);
    ensureNumber('Sales_Order_Volume_UOM__c', 'Sales order volume (UOM)', 60);
    ensureNumber('Geo_Share_Volume_UOM__c', 'Target geo share (UOM)', 70);
    sections.accountTerritoryProduct = fields;
    return parsed;
}

function patchLayoutJson(fieldsJson) {
    if (!fieldsJson) return fieldsJson;
    try {
        const parsed = typeof fieldsJson === 'string' ? JSON.parse(fieldsJson) : fieldsJson;
        const sections = parsed?.sections || {};
        Object.values(sections).forEach((fields) => {
            if (!Array.isArray(fields)) return;
            fields.forEach((field) => {
                if (field?.fieldApiName !== 'HCP_Classification__c') return;
                field.label = 'Classification';
                field.widget = 'picklist';
                if (!Array.isArray(field.options) || field.options.length === 0) {
                    field.options = HCP_CLASSIFICATION_OPTIONS;
                }
            });
        });
        ensureProductPotentialPenetrationFields(parsed);
        return JSON.stringify(parsed);
    } catch (_err) {
        return fieldsJson;
    }
}

function atpfValuesFromRow(row) {
    if (!row) return {};
    return {
        Potential__c: row.Potential__c,
        Penetration__c: row.Penetration__c,
        Rx_Per_Week__c: row.Rx_Per_Week__c,
        Adoption__c: row.Adoption__c,
        Loyalty__c: row.Loyalty__c,
        Product_Matrix_Rating__c: row.Product_Matrix_Rating__c,
        Target_Visit_Frequency__c: row.Target_Visit_Frequency__c,
        Notes__c: row.Notes__c
    };
}

async function loadAlignedProducts(accountId, territory2Id) {
    const productsCache = cacheKey(PRODUCTS_CACHE_PREFIX, `${accountId}.${territory2Id || 'none'}`);
    if (isOffline()) {
        const cached = readCache(productsCache);
        if (Array.isArray(cached?.payload)) return cached.payload;
    }
    if (!accountId || !territory2Id) {
        return [];
    }
    const territoryList = soqlIdList(territory2Id);
    const productIds = new Set();
    const atpfByProduct = new Map();
    try {
        const pta = await plannerApiFetch(
            `/services/data/v62.0/query?q=${encodeURIComponent(
                `SELECT Product2_Id__c
                 FROM Product_Territory_Alignment__c
                 WHERE Territory2_Id__c IN (${territoryList})
                   AND Product2_Id__c != null
                   AND Is_Active__c = true
                 LIMIT 200`
            )}`
        );
        (pta?.records || []).forEach((row) => {
            if (row.Product2_Id__c) productIds.add(row.Product2_Id__c);
        });
    } catch (_err) {
        /* PTA is optional */
    }
    try {
        const atpf = await plannerApiFetch(
            `/services/data/v62.0/query?q=${encodeURIComponent(
                `SELECT Product2_Id__c, Potential__c, Penetration__c, Rx_Per_Week__c,
                        Adoption__c, Loyalty__c, Product_Matrix_Rating__c,
                        Target_Visit_Frequency__c, Notes__c
                 FROM Account_Territory_Product_Fields__c
                 WHERE Account__c = '${escapeSoql(accountId)}'
                   AND Territory2_Id__c IN (${territoryList})
                   AND Is_Active__c = true
                   AND Product2_Id__c != null
                 LIMIT 200`
            )}`
        );
        (atpf?.records || []).forEach((row) => {
            if (!row.Product2_Id__c) return;
            productIds.add(row.Product2_Id__c);
            if (!atpfByProduct.has(row.Product2_Id__c)) {
                atpfByProduct.set(row.Product2_Id__c, row);
            }
        });
    } catch (_err) {
        /* ATPF optional */
    }
    if (!productIds.size) {
        writeCache(productsCache, []);
        return [];
    }
    const idList = [...productIds].map((id) => `'${escapeSoql(id)}'`).join(',');
    let products = [];
    try {
        const result = await plannerApiFetch(
            `/services/data/v62.0/query?q=${encodeURIComponent(
                `SELECT Id, Name, Product_Image_URL__c
                 FROM Product2
                 WHERE Id IN (${idList}) AND IsActive = true
                 ORDER BY Name ASC`
            )}`
        );
        products = result?.records || [];
    } catch (_err) {
        try {
            const result = await plannerApiFetch(
                `/services/data/v62.0/query?q=${encodeURIComponent(
                    `SELECT Id, Name
                     FROM Product2
                     WHERE Id IN (${idList}) AND IsActive = true
                     ORDER BY Name ASC`
                )}`
            );
            products = result?.records || [];
        } catch (_inner) {
            return [];
        }
    }
    const pending = readCache(cacheKey(VALUES_CACHE_PREFIX, `pending.${accountId}`));
    const pendingValues = pending?.payload && typeof pending.payload === 'object' ? pending.payload : {};
    const aligned = products.map((product) => {
        const values = atpfValuesFromRow(atpfByProduct.get(product.Id));
        Object.keys(pendingValues).forEach((key) => {
            if (key.startsWith(`${product.Id}.`)) {
                values[key.slice(product.Id.length + 1)] = pendingValues[key];
            }
        });
        return {
            product2Id: product.Id,
            productName: product.Name,
            imageUrl: product.Product_Image_URL__c || null,
            valuesJson: JSON.stringify(values)
        };
    });
    writeCache(productsCache, aligned);
    return aligned;
}

async function loadValues(accountId, territory2Id) {
    const values = {};
    const valuesCache = cacheKey(VALUES_CACHE_PREFIX, `${accountId}.${territory2Id || 'none'}`);
    if (isOffline()) {
        const cached = readCache(valuesCache);
        if (cached?.payload) return cached.payload;
    }
    try {
        const acct = await plannerApiFetch(
            `/services/data/v62.0/query?q=${encodeURIComponent(
                `SELECT Rating, AnnualRevenue, NumberOfEmployees
                 FROM Account WHERE Id = '${escapeSoql(accountId)}' LIMIT 1`
            )}`
        );
        const row = acct?.records?.[0];
        if (row) {
            values.Rating = row.Rating;
            values.AnnualRevenue = row.AnnualRevenue;
            values.NumberOfEmployees = row.NumberOfEmployees;
        }
    } catch (_err) {
        /* optional account fields */
    }
    if (territory2Id) {
        try {
            const atf = await plannerApiFetch(
                `/services/data/v62.0/query?q=${encodeURIComponent(
                    `SELECT Id, Is_KOL__c, KOL_In_What__c, Has_KOLs__c, KOL_Profile__c,
                            Is_Speaker__c, HCP_Classification__c,
                            Potential__c, Penetration__c, Matrix_Rating__c, Classification__c
                     FROM Account_Territory_Fields__c
                     WHERE Account__c = '${escapeSoql(accountId)}'
                       AND Territory2_Id__c IN (${soqlIdList(territory2Id)})
                     ORDER BY LastModifiedDate DESC
                     LIMIT 1`
                )}`
            );
            const atfRow = atf?.records?.[0];
            if (atfRow) {
                Object.assign(values, {
                    Is_KOL__c: atfRow.Is_KOL__c,
                    KOL_In_What__c: atfRow.KOL_In_What__c,
                    Has_KOLs__c: atfRow.Has_KOLs__c,
                    KOL_Profile__c: atfRow.KOL_Profile__c,
                    Is_Speaker__c: atfRow.Is_Speaker__c,
                    HCP_Classification__c: atfRow.HCP_Classification__c,
                    Potential__c: atfRow.Potential__c,
                    Penetration__c: atfRow.Penetration__c,
                    Matrix_Rating__c: atfRow.Matrix_Rating__c,
                    Classification__c: atfRow.Classification__c
                });
            }
        } catch (_err) {
            /* optional */
        }
    }
    const pending = readCache(cacheKey(VALUES_CACHE_PREFIX, `pending.${accountId}`));
    if (pending?.payload && typeof pending.payload === 'object') {
        Object.assign(values, pending.payload);
    }
    writeCache(valuesCache, values);
    return values;
}

export default makeDualApex(async (params = {}) => {
    const accountId = params.accountId;
    if (!accountId) {
        return emptyContext();
    }
    const id = escapeSoql(accountId);
    try {
        const acct = await plannerApiFetch(
            `/services/data/v62.0/query?q=${encodeURIComponent(
                `SELECT Id, Name, RecordType.DeveloperName, IsPersonAccount FROM Account WHERE Id = '${id}' LIMIT 1`
            )}`
        );
        const row = acct?.records?.[0];
        const developerName = row?.RecordType?.DeveloperName || '';
        const isHco = /hco|institution|pharmacy/i.test(developerName) || row?.IsPersonAccount === false;
        const variant = isHco ? 'HCO' : 'HCP';
        const { territory2Id, territoryName } = await resolveTerritory(accountId);

        let layout = null;
        try {
            const records = await loadDeployedLayouts(variant);
            layout = pickLayout(records, variant);
            if (layout?.Fields_JSON__c) {
                writeCache(cacheKey(LAYOUT_CACHE_PREFIX, layout.Id), {
                    layoutId: layout.Id,
                    layoutJson: patchLayoutJson(layout.Fields_JSON__c),
                    accountVariant: variant
                });
            }
        } catch (_layoutError) {
            const cached = readCache(cacheKey(LAYOUT_CACHE_PREFIX, variant)) || readCache(cacheKey(LAYOUT_CACHE_PREFIX, 'ALL'));
            const records = cached?.payload || [];
            layout = pickLayout(Array.isArray(records) ? records : [], variant);
        }

        const values = await loadValues(accountId, territory2Id);
        const alignedProducts = await loadAlignedProducts(accountId, territory2Id);
        return {
            layoutId: layout?.Id || null,
            layoutJson: patchLayoutJson(layout?.Fields_JSON__c) || null,
            accountVariant: variant,
            territory2Id,
            territoryName,
            valuesJson: JSON.stringify(values),
            alignedProducts
        };
    } catch (_error) {
        const cachedLayout = readCache(cacheKey(LAYOUT_CACHE_PREFIX, 'HCP'));
        const records = Array.isArray(cachedLayout?.payload) ? cachedLayout.payload : [];
        const layout = pickLayout(records, 'HCP');
        const cachedValues = readCache(cacheKey(VALUES_CACHE_PREFIX, `${accountId}.none`));
        const cachedProducts = readCache(cacheKey(PRODUCTS_CACHE_PREFIX, `${accountId}.none`));
        return {
            layoutId: layout?.Id || null,
            layoutJson: patchLayoutJson(layout?.Fields_JSON__c) || null,
            accountVariant: 'HCP',
            territory2Id: null,
            territoryName: null,
            valuesJson: JSON.stringify(cachedValues?.payload || {}),
            alignedProducts: Array.isArray(cachedProducts?.payload) ? cachedProducts.payload : []
        };
    }
});
