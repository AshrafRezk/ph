import { makeDualApex } from './_wireAdapter.js';
import { plannerApiFetch } from './restHelper.js';

const DISPLAY_CURRENCY = 'EGP';
const MONTH_LABELS = ['JAN', 'FEB', 'MAR', 'APR', 'MAY', 'JUN', 'JUL', 'AUG', 'SEP', 'OCT', 'NOV', 'DEC'];
const API = 'v62.0';

function escapeSoql(value) {
    return String(value || '').replace(/\\/g, '\\\\').replace(/'/g, "\\'");
}

function nullToZero(value) {
    const n = Number(value);
    return Number.isFinite(n) ? n : 0;
}

function moneyScale(value) {
    return Math.round(nullToZero(value) * 100) / 100;
}

function quoteIds(ids) {
    return [...new Set((ids || []).filter(Boolean).map((id) => String(id)))].map((id) => `'${escapeSoql(id)}'`).join(',');
}

function toSalesforceId(value) {
    const raw = String(value || '').trim();
    if (raw.length < 15) return null;
    return raw;
}

function id15(value) {
    const raw = String(value || '').trim();
    return raw.length >= 15 ? raw.slice(0, 15) : raw;
}

function productFromMap(map, productId) {
    if (!productId || !map) return null;
    return map.get(productId) || map.get(id15(productId)) || null;
}

function putProduct(map, product) {
    if (!product?.Id) return;
    map.set(product.Id, product);
    map.set(id15(product.Id), product);
    if (product.External_ID__c) {
        map.set(product.External_ID__c, product);
    }
}

function isoDate(date) {
    const y = date.getFullYear();
    const m = String(date.getMonth() + 1).padStart(2, '0');
    const d = String(date.getDate()).padStart(2, '0');
    return `${y}-${m}-${d}`;
}

function monthStartMonthsAgo(monthsAgo) {
    const d = new Date();
    d.setDate(1);
    d.setHours(0, 0, 0, 0);
    d.setMonth(d.getMonth() - monthsAgo);
    return d;
}

function monthKey(date) {
    return `${date.getFullYear()}-${String(date.getMonth() + 1).padStart(2, '0')}`;
}

function emptyMonthTrend(fromDate) {
    const start = fromDate || monthStartMonthsAgo(11);
    return Array.from({ length: 12 }, (_unused, index) => {
        const month = new Date(start.getFullYear(), start.getMonth() + index, 1);
        return {
            monthKey: monthKey(month),
            monthLabel: MONTH_LABELS[month.getMonth()],
            value: null,
            classification: null
        };
    });
}

function formatSpendDate(value) {
    if (!value) return '';
    return new Date(value).toLocaleDateString(undefined, { month: 'short', day: 'numeric' });
}

function formatMoney(value) {
    const n = Math.round(nullToZero(value));
    return `${DISPLAY_CURRENCY} ${Math.abs(n).toLocaleString('en-US')}`;
}

function emptyPayload(accountId, accountName = '') {
    return {
        accountId: accountId || null,
        accountName,
        selectedProductId: null,
        selectedProductName: null,
        totalSpendYtd: 0,
        speakerSpendYtd: 0,
        samplesSpendYtd: 0,
        brochuresSpendYtd: 0,
        writtenValue: 0,
        potentialValue: 0,
        gapValue: 0,
        roiMultiple: null,
        callToAction: '',
        orgRank: null,
        orgTotal: null,
        timelineYear: new Date().getFullYear(),
        currencyIsoCode: DISPLAY_CURRENCY,
        productRanks: [],
        spendBreakdown: [],
        spendEvents: [],
        salesTrend: emptyMonthTrend(),
        ratingTrend: emptyMonthTrend(),
        hasProducts: false
    };
}

async function queryRecords(soql) {
    const data = await plannerApiFetch(
        `/services/data/${API}/query?q=${encodeURIComponent(soql)}`
    );
    return Array.isArray(data?.records) ? data.records : [];
}

async function queryFirstWorking(queries) {
    let lastError = null;
    for (const soql of queries) {
        try {
            return await queryRecords(soql);
        } catch (err) {
            lastError = err;
        }
    }
    if (lastError) {
        console.warn('[APM] query failed', lastError);
    }
    return [];
}

function penetrationFromRow(row) {
    let penetration = nullToZero(row.Penetration__c);
    if (penetration <= 0 && row.Rx_Per_Week__c != null) {
        penetration = nullToZero(row.Rx_Per_Week__c) * 52;
    }
    if (penetration <= 0 && row.Adoption__c != null) {
        const letter = String(row.Adoption__c).trim().toUpperCase();
        penetration = letter === 'A' ? 3 : letter === 'B' ? 2 : letter === 'C' ? 1 : nullToZero(row.Adoption__c);
    }
    return penetration;
}

function potentialFromRow(row, penetration) {
    let potential = nullToZero(row.Potential__c);
    if (potential <= 0) {
        potential = penetration > 0 ? penetration * 1.25 : 0;
    }
    return potential;
}

async function loadProducts(productIds) {
    if (!productIds.length) return new Map();
    const idList = quoteIds(productIds);
    let records = await queryFirstWorking([
        `SELECT Id, Name, Family, External_ID__c, Product_Image_URL__c FROM Product2 WHERE Id IN (${idList})`,
        `SELECT Id, Name, Family, External_ID__c FROM Product2 WHERE Id IN (${idList})`
    ]);
    if (!records.length) {
        records = await queryFirstWorking([
            `SELECT Id, Name, Family, External_ID__c, Product_Image_URL__c FROM Product2 WHERE External_ID__c IN (${idList})`,
            `SELECT Id, Name, Family, External_ID__c FROM Product2 WHERE External_ID__c IN (${idList})`
        ]);
    }
    const map = new Map();
    records.forEach((row) => putProduct(map, row));
    return map;
}

async function loadPrices(productIds) {
    const prices = new Map();
    if (!productIds.length) return prices;
    const idList = quoteIds(productIds);
    const rows = await queryFirstWorking([
        `SELECT Product2Id, UnitPrice FROM PricebookEntry
         WHERE Pricebook2.IsStandard = true AND Product2Id IN (${idList}) AND IsActive = true`,
        `SELECT Product2Id, UnitPrice FROM PricebookEntry
         WHERE Product2Id IN (${idList}) AND IsActive = true`
    ]);
    rows.forEach((row) => {
        if (row.Product2Id && !prices.has(row.Product2Id)) {
            prices.set(row.Product2Id, nullToZero(row.UnitPrice));
        }
    });
    return prices;
}

async function loadAtpfRows(accountId) {
    const id = escapeSoql(accountId);
    const rows = await queryFirstWorking([
        `SELECT Id, Product2_Id__c, Penetration__c, Potential__c, Rx_Per_Week__c,
                Adoption__c, Loyalty__c, Product_Matrix_Rating__c, Is_Active__c
         FROM Account_Territory_Product_Fields__c
         WHERE Account__c = '${id}' AND Is_Active__c = true AND Product2_Id__c != null
         ORDER BY LastModifiedDate DESC
         LIMIT 200`,
        `SELECT Id, Product2_Id__c, Rx_Per_Week__c, Adoption__c, Loyalty__c,
                Product_Matrix_Rating__c, Is_Active__c
         FROM Account_Territory_Product_Fields__c
         WHERE Account__c = '${id}' AND Is_Active__c = true AND Product2_Id__c != null
         ORDER BY LastModifiedDate DESC
         LIMIT 200`,
        `SELECT Id, Product2_Id__c, Rx_Per_Week__c, Adoption__c, Loyalty__c, Is_Active__c
         FROM Account_Territory_Product_Fields__c
         WHERE Account__c = '${id}' AND Product2_Id__c != null
         ORDER BY LastModifiedDate DESC
         LIMIT 200`
    ]);
    return rows;
}

async function affiliatedPharmacyIds(accountId) {
    const id = escapeSoql(accountId);
    const rows = await queryFirstWorking([
        `SELECT Primary_Account__c, Related_Account__c,
                Primary_Account__r.RecordType.DeveloperName,
                Related_Account__r.RecordType.DeveloperName
         FROM Account_Affiliation__c
         WHERE Is_Active__c = true
           AND (Primary_Account__c = '${id}' OR Related_Account__c = '${id}')
         LIMIT 200`
    ]);
    const pharmacyIds = new Set();
    rows.forEach((aff) => {
        const primaryRt = aff.Primary_Account__r?.RecordType?.DeveloperName || '';
        const relatedRt = aff.Related_Account__r?.RecordType?.DeveloperName || '';
        if (aff.Primary_Account__c !== accountId && /pharmacy/i.test(primaryRt)) {
            pharmacyIds.add(aff.Primary_Account__c);
        }
        if (aff.Related_Account__c !== accountId && /pharmacy/i.test(relatedRt)) {
            pharmacyIds.add(aff.Related_Account__c);
        }
    });
    if (!pharmacyIds.size) {
        rows.forEach((aff) => {
            if (aff.Primary_Account__c && aff.Primary_Account__c !== accountId) {
                pharmacyIds.add(aff.Primary_Account__c);
            }
            if (aff.Related_Account__c && aff.Related_Account__c !== accountId) {
                pharmacyIds.add(aff.Related_Account__c);
            }
        });
    }
    return [...pharmacyIds];
}

async function mergeWithdrawalRanks(accountId, isPharmacyAccount, productsById, prices, bestByProduct) {
    let pharmacyIds = await affiliatedPharmacyIds(accountId);
    if (isPharmacyAccount || !pharmacyIds.length) {
        pharmacyIds = [...new Set([...pharmacyIds, accountId])];
    }
    const start = isoDate(monthStartMonthsAgo(11));
    const idList = quoteIds(pharmacyIds);
    const rows = await queryFirstWorking([
        `SELECT Product2_Id__c, Quantity_Withdrawn__c, Revenue__c, Unit_Price__c
         FROM Pharmacy_Sales_Withdrawal__c
         WHERE Pharmacy_Account__c IN (${idList})
           AND Report_Month__c >= ${start}
           AND Product2_Id__c != null
         LIMIT 2000`
    ]);
    const qtyByProduct = new Map();
    rows.forEach((row) => {
        const pid = toSalesforceId(row.Product2_Id__c) || row.Product2_Id__c;
        if (!pid) return;
        qtyByProduct.set(pid, (qtyByProduct.get(pid) || 0) + nullToZero(row.Quantity_Withdrawn__c));
    });
    const missing = [...qtyByProduct.keys()].filter((pid) => !productFromMap(productsById, pid));
    if (missing.length) {
        const extra = await loadProducts(missing);
        extra.forEach((product) => putProduct(productsById, product));
        const extraPrices = await loadPrices(
            [...extra.values()].map((product) => product.Id).filter(Boolean)
        );
        extraPrices.forEach((price, pid) => prices.set(pid, price));
    }
    qtyByProduct.forEach((qty, pid) => {
        const product = productFromMap(productsById, pid);
        if (!product || bestByProduct.has(product.Id) || bestByProduct.has(id15(product.Id)) || qty <= 0) {
            return;
        }
        bestByProduct.set(product.Id, {
            productId: product.Id,
            penetration: qty,
            potential: Math.round(qty * 1.25),
            classification: null,
            matrix: null
        });
    });
}

async function computeOrgRanks(productIds) {
    const result = new Map();
    if (!productIds.length) return result;
    productIds.forEach((pid) => result.set(pid, { byAccount: new Map(), total: 0 }));
    const idList = quoteIds(productIds);
    const rows = await queryFirstWorking([
        `SELECT Account__c, Product2_Id__c, Penetration__c, Rx_Per_Week__c
         FROM Account_Territory_Product_Fields__c
         WHERE Product2_Id__c IN (${idList}) AND Is_Active__c = true
         LIMIT 2000`,
        `SELECT Account__c, Product2_Id__c, Rx_Per_Week__c
         FROM Account_Territory_Product_Fields__c
         WHERE Product2_Id__c IN (${idList}) AND Is_Active__c = true
         LIMIT 2000`
    ]);
    rows.forEach((row) => {
        const pid = toSalesforceId(row.Product2_Id__c) || row.Product2_Id__c;
        const org = result.get(pid) || result.get(toSalesforceId(pid));
        if (!org || !row.Account__c) return;
        const penetration = penetrationFromRow(row);
        const existing = org.byAccount.get(row.Account__c);
        if (existing == null || penetration > existing) {
            org.byAccount.set(row.Account__c, penetration);
        }
    });
    result.forEach((org) => {
        org.total = org.byAccount.size;
    });
    return result;
}

function rankFor(org, penetration) {
    let rank = 1;
    org.byAccount.forEach((value) => {
        if (value > penetration) rank += 1;
    });
    return rank;
}

function buildCta(payload) {
    if (!payload.productRanks?.length) {
        return 'Rate products on this account to unlock APM opportunity insights.';
    }
    const spendText = formatMoney(payload.totalSpendYtd);
    const writtenText = formatMoney(payload.writtenValue);
    const potentialText = formatMoney(payload.potentialValue);
    if (payload.gapValue > 0) {
        return `We spent ${spendText} this year on this doctor. They wrote ${writtenText} and could write ${potentialText} - visit more to close the gap.`;
    }
    return `We spent ${spendText} this year on this doctor and they wrote ${writtenText}.`;
}

function preferDividoOrTop(ranks) {
    const divido = ranks.find(
        (row) => /divido/i.test(row.productName || '') || /divido/i.test(row.productFamily || '')
    );
    return divido?.productId || ranks[0]?.productId || null;
}

async function loadSpend(accountId, selectedId, year) {
    const id = escapeSoql(accountId);
    const yearStart = `${year}-01-01`;
    const spends = await queryFirstWorking([
        `SELECT Id, Spend_Type__c, Amount__c, Spend_Date__c, Product__c,
                Product__r.Name, Product__r.Family, Product__r.Product_Image_URL__c
         FROM HCP_Engagement_Spend__c
         WHERE Account__c = '${id}' AND Spend_Date__c >= ${yearStart}
         ORDER BY Spend_Date__c ASC, Amount__c DESC
         LIMIT 200`,
        `SELECT Id, Spend_Type__c, Amount__c, Spend_Date__c, Product__c,
                Product__r.Name, Product__r.Family
         FROM HCP_Engagement_Spend__c
         WHERE Account__c = '${id}' AND Spend_Date__c >= ${yearStart}
         ORDER BY Spend_Date__c ASC, Amount__c DESC
         LIMIT 200`
    ]);
    const byType = { 'Speaker Meeting': 0, Samples: 0, Brochures: 0 };
    let totalSpend = 0;
    const spendEvents = [];
    const yearStartDate = new Date(year, 0, 1);
    spends.forEach((spend) => {
        const amount = nullToZero(spend.Amount__c);
        totalSpend += amount;
        const spendType = spend.Spend_Type__c || 'Samples';
        byType[spendType] = (byType[spendType] || 0) + amount;
        let positionPercent = 0;
        if (spend.Spend_Date__c) {
            const offset = Math.round((new Date(spend.Spend_Date__c) - yearStartDate) / 86400000);
            positionPercent = Math.max(0, Math.min(100, (offset / 365) * 100));
        }
        spendEvents.push({
            spendId: spend.Id,
            spendDate: spend.Spend_Date__c,
            spendDateLabel: formatSpendDate(spend.Spend_Date__c),
            spendType,
            amount: moneyScale(amount),
            productId: spend.Product__c,
            productName: spend.Product__r?.Name || null,
            productFamily: spend.Product__r?.Family || null,
            imageUrl: spend.Product__r?.Product_Image_URL__c || null,
            matchesSelectedProduct: Boolean(selectedId && spend.Product__c === selectedId),
            positionPercent: Math.round(positionPercent * 100) / 100
        });
    });
    return {
        totalSpendYtd: moneyScale(totalSpend),
        speakerSpendYtd: moneyScale(byType['Speaker Meeting']),
        samplesSpendYtd: moneyScale(byType.Samples),
        brochuresSpendYtd: moneyScale(byType.Brochures),
        spendBreakdown: ['Speaker Meeting', 'Samples', 'Brochures'].map((spendType) => ({
            spendType,
            amount: moneyScale(byType[spendType] || 0)
        })),
        spendEvents
    };
}

async function buildSalesTrend(accountId, selectedId, isPharmacyAccount) {
    const points = emptyMonthTrend();
    if (!selectedId) return points;
    let pharmacyIds = await affiliatedPharmacyIds(accountId);
    if (isPharmacyAccount || !pharmacyIds.length) {
        pharmacyIds = [...new Set([...pharmacyIds, accountId])];
    }
    const start = isoDate(monthStartMonthsAgo(11));
    const rows = await queryFirstWorking([
        `SELECT Report_Month__c, Quantity_Withdrawn__c, Unit_Price__c, Revenue__c, Product2_Id__c
         FROM Pharmacy_Sales_Withdrawal__c
         WHERE Pharmacy_Account__c IN (${quoteIds(pharmacyIds)})
           AND Report_Month__c >= ${start}
           AND Product2_Id__c = '${escapeSoql(selectedId)}'
         LIMIT 2000`
    ]);
    const revenueByMonth = new Map();
    rows.forEach((row) => {
        if (!row.Report_Month__c) return;
        const key = String(row.Report_Month__c).slice(0, 7);
        const revenue =
            row.Revenue__c != null
                ? nullToZero(row.Revenue__c)
                : nullToZero(row.Quantity_Withdrawn__c) * nullToZero(row.Unit_Price__c);
        revenueByMonth.set(key, (revenueByMonth.get(key) || 0) + revenue);
    });
    return points.map((point) => ({
        ...point,
        value: revenueByMonth.has(point.monthKey) ? moneyScale(revenueByMonth.get(point.monthKey)) : 0
    }));
}

async function buildRatingTrend(accountId, selectedId, currentStats) {
    const points = emptyMonthTrend();
    if (!selectedId) return points;
    const start = isoDate(monthStartMonthsAgo(11));
    const rows = await queryFirstWorking([
        `SELECT Snapshot_Month__c, Classification__c, Classification_Score__c, Penetration__c
         FROM HCP_Product_Rating_Snapshot__c
         WHERE Account__c = '${escapeSoql(accountId)}'
           AND Product__c = '${escapeSoql(selectedId)}'
           AND Snapshot_Month__c >= ${start}
         ORDER BY Snapshot_Month__c ASC
         LIMIT 200`
    ]);
    const byMonth = new Map();
    rows.forEach((row) => {
        if (row.Snapshot_Month__c) {
            byMonth.set(String(row.Snapshot_Month__c).slice(0, 7), row);
        }
    });
    const currentMonth = monthKey(new Date());
    return points.map((point) => {
        const snap = byMonth.get(point.monthKey);
        if (snap) {
            return {
                ...point,
                value: snap.Classification_Score__c != null ? nullToZero(snap.Classification_Score__c) : null,
                classification: snap.Classification__c || null
            };
        }
        if (point.monthKey === currentMonth && currentStats) {
            return {
                ...point,
                value: currentStats.penetration || null,
                classification: currentStats.classification || currentStats.matrix || null
            };
        }
        return point;
    });
}

export default makeDualApex(async (params = {}) => {
    const accountId = params.accountId;
    const requestedProductId = params.productId || null;
    if (!accountId) {
        return emptyPayload(null);
    }
    try {
        const acct = await queryFirstWorking([
            `SELECT Id, Name, IsPersonAccount, RecordType.DeveloperName FROM Account WHERE Id = '${escapeSoql(accountId)}' LIMIT 1`
        ]);
        const account = acct[0];
        if (!account) {
            return emptyPayload(accountId);
        }
        const isPharmacyAccount =
            account.IsPersonAccount === false &&
            (/pharmacy/i.test(account.RecordType?.DeveloperName || '') || /pharmacy/i.test(account.Name || ''));

        const atpfRows = await loadAtpfRows(accountId);
        const bestByProduct = new Map();
        atpfRows.forEach((row) => {
            const pid = toSalesforceId(row.Product2_Id__c) || row.Product2_Id__c;
            if (!pid) return;
            const key = id15(pid) || pid;
            const penetration = penetrationFromRow(row);
            const potential = potentialFromRow(row, penetration);
            const prev = bestByProduct.get(key);
            if (!prev || penetration > prev.penetration) {
                bestByProduct.set(key, {
                    productId: pid,
                    penetration,
                    potential: potential > 0 ? potential : penetration > 0 ? penetration * 1.25 : 1,
                    classification: row.Product_Matrix_Rating__c || null,
                    matrix: row.Product_Matrix_Rating__c || null
                });
            }
        });

        const productsById = await loadProducts([...bestByProduct.keys()]);
        const prices = await loadPrices(
            [...new Set([...productsById.values()].map((product) => product.Id).filter(Boolean))]
        );

        const hasResolvedProducts = [...bestByProduct.keys()].some((pid) => productFromMap(productsById, pid));
        if (!hasResolvedProducts || isPharmacyAccount) {
            await mergeWithdrawalRanks(accountId, isPharmacyAccount, productsById, prices, bestByProduct);
        }

        const resolvedIds = [...bestByProduct.keys()]
            .map((pid) => productFromMap(productsById, pid)?.Id)
            .filter(Boolean);
        const orgRanks = await computeOrgRanks([...new Set(resolvedIds)]);

        const ranks = [];
        bestByProduct.forEach((stats, pid) => {
            const product = productFromMap(productsById, pid);
            if (!product) return;
            const productId = product.Id;
            let unitPrice = prices.get(productId);
            if (unitPrice == null || unitPrice <= 0) unitPrice = 50;
            const writtenValue = moneyScale(stats.penetration * unitPrice);
            const potentialValue = moneyScale(stats.potential * unitPrice);
            const gapValue = moneyScale(potentialValue - writtenValue);
            const org = orgRanks.get(productId);
            const orgTotal = org?.total || 1;
            const orgRank = org ? rankFor(org, stats.penetration) : 1;
            ranks.push({
                productId,
                productName: product.Name,
                productFamily: product.Family || null,
                imageUrl: product.Product_Image_URL__c || null,
                penetration: stats.penetration,
                potential: stats.potential,
                unitPrice,
                writtenValue,
                potentialValue,
                gapValue,
                gapPercent: potentialValue > 0 ? Math.round((gapValue / potentialValue) * 1000) / 10 : 0,
                orgRank,
                orgTotal,
                percentile: orgTotal > 0 ? Math.round(((orgTotal - orgRank + 1) / orgTotal) * 1000) / 10 : 100,
                isSelected: false
            });
        });
        ranks.sort((a, b) => (b.writtenValue || 0) - (a.writtenValue || 0));

        let selectedId = requestedProductId;
        if (!selectedId && ranks.length) {
            selectedId = preferDividoOrTop(ranks);
        }
        let selected = null;
        ranks.forEach((row) => {
            row.isSelected = row.productId === selectedId;
            if (row.isSelected) selected = row;
        });

        const year = new Date().getFullYear();
        const spend = await loadSpend(accountId, selectedId, year);
        const payload = {
            accountId,
            accountName: account.Name || '',
            selectedProductId: selectedId,
            selectedProductName: selected?.productName || null,
            ...spend,
            writtenValue: selected?.writtenValue || 0,
            potentialValue: selected?.potentialValue || 0,
            gapValue: selected?.gapValue || 0,
            roiMultiple:
                spend.totalSpendYtd > 0 && selected?.writtenValue != null
                    ? Math.round((selected.writtenValue / spend.totalSpendYtd) * 10) / 10
                    : null,
            callToAction: '',
            orgRank: selected?.orgRank ?? null,
            orgTotal: selected?.orgTotal ?? null,
            timelineYear: year,
            currencyIsoCode: DISPLAY_CURRENCY,
            productRanks: ranks,
            salesTrend: await buildSalesTrend(accountId, selectedId, isPharmacyAccount),
            ratingTrend: await buildRatingTrend(accountId, selectedId, selectedId ? bestByProduct.get(selectedId) : null),
            hasProducts: ranks.length > 0
        };
        payload.callToAction = buildCta(payload);
        return payload;
    } catch (error) {
        console.warn('[APM] getAccountRoi failed', error);
        return emptyPayload(accountId);
    }
});
