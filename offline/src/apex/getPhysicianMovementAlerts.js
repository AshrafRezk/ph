import { plannerApiFetch, isOffline } from './restHelper.js';
import getBrickGrowthAlerts from './getBrickGrowthAlerts.js';

const API = 'v62.0';

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

function monthKey(value) {
    return String(value || '').slice(0, 7);
}

function classScore(classification, score) {
    if (score != null && Number.isFinite(Number(score))) {
        return Number(score);
    }
    const raw = String(classification || '')
        .trim()
        .toUpperCase();
    if (raw.length < 2) return null;
    const letter = raw[0];
    const digit = Number(raw[1]);
    const base = letter === 'A' ? 7 : letter === 'B' ? 4 : letter === 'C' ? 1 : null;
    if (base == null) return null;
    return base + (3 - Math.min(3, Number.isFinite(digit) ? digit : 1));
}

async function queryRecords(soql) {
    const data = await plannerApiFetch(`/services/data/${API}/query?q=${encodeURIComponent(soql)}`);
    return Array.isArray(data?.records) ? data.records : [];
}

function buildSnapshotMovers(rows) {
    const byPair = new Map();
    (rows || []).forEach((row) => {
        const accountId = row.Account__c;
        const productId = row.Product__c;
        if (!accountId) return;
        const key = `${accountId}:${productId || 'none'}`;
        const list = byPair.get(key) || [];
        list.push({
            monthKey: monthKey(row.Snapshot_Month__c),
            classification: row.Classification__c || null,
            score: classScore(row.Classification__c, row.Classification_Score__c),
            accountId,
            accountName: (row.Account__r && row.Account__r.Name) || 'Physician',
            productName: (row.Product__r && row.Product__r.Name) || 'Product'
        });
        byPair.set(key, list);
    });

    const movers = [];
    byPair.forEach((list) => {
        list.sort((a, b) => String(a.monthKey).localeCompare(String(b.monthKey)));
        const withClass = list.filter((point) => point.classification || point.score != null);
        if (withClass.length < 2) return;
        const from = withClass[withClass.length - 2];
        const to = withClass[withClass.length - 1];
        if (!from || !to || from.monthKey === to.monthKey) return;
        const fromScore = from.score;
        const toScore = to.score;
        const classChanged = (from.classification || '') !== (to.classification || '');
        const scoreChanged = fromScore != null && toScore != null && fromScore !== toScore;
        if (!classChanged && !scoreChanged) return;
        const delta = (toScore ?? 0) - (fromScore ?? 0);
        const direction = delta > 0 ? 'up' : delta < 0 ? 'down' : 'changed';
        const verb = direction === 'up' ? 'upgraded' : direction === 'down' ? 'downgraded' : 'changed';
        movers.push({
            type: 'classification',
            accountId: to.accountId,
            accountName: to.accountName,
            productName: to.productName,
            fromClass: from.classification || '�',
            toClass: to.classification || '�',
            direction,
            delta,
            title: `${to.accountName}: ${from.classification || '�'} ? ${to.classification || '�'}`,
            detail: `${to.accountName} ${verb} on ${to.productName} (${from.classification || '�'} ? ${to.classification || '�'}).`
        });
    });
    movers.sort((a, b) => Math.abs(b.delta) - Math.abs(a.delta) || a.accountName.localeCompare(b.accountName));
    return movers.slice(0, 8);
}

function brickInsightLines(alerts) {
    return (alerts || []).slice(0, 4).map((alert) => {
        const doctors = Array.isArray(alert.doctors) ? alert.doctors : [];
        const names = doctors
            .map((row) => row.accountName)
            .filter(Boolean)
            .slice(0, 3);
        const focus = names.length ? ` Focus ${names.join(', ')}.` : '';
        return {
            type: 'brick',
            accountId: doctors[0] && doctors[0].accountId,
            accountName: doctors[0] && doctors[0].accountName,
            title: `${alert.brickName || 'Brick'} sell-out +${alert.growthPercent || 0}%`,
            detail: `${alert.brickName || 'Brick'} sell-out is up ${alert.growthPercent || 0}% month-over-month.${focus}`
        };
    });
}

export default async function getPhysicianMovementAlerts() {
    if (isOffline()) {
        return {
            movers: [],
            brickAlerts: [],
            items: [],
            insights: ['Reconnect to load physician movement alerts from sales data.']
        };
    }

    const start = isoDate(monthStartMonthsAgo(2));
    const snapshotQueries = [
        `SELECT Account__c, Account__r.Name, Product__c, Product__r.Name, Snapshot_Month__c, Classification__c, Classification_Score__c
         FROM HCP_Product_Rating_Snapshot__c
         WHERE Snapshot_Month__c >= ${start}
         ORDER BY Snapshot_Month__c ASC
         LIMIT 2000`,
        `SELECT Account__c, Product__c, Snapshot_Month__c, Classification__c, Classification_Score__c
         FROM HCP_Product_Rating_Snapshot__c
         WHERE Snapshot_Month__c >= ${start}
         ORDER BY Snapshot_Month__c ASC
         LIMIT 2000`
    ];

    const [brickResult, snapshotResult] = await Promise.allSettled([
        getBrickGrowthAlerts({}),
        (async () => {
            let lastError = null;
            for (const soql of snapshotQueries) {
                try {
                    return await queryRecords(soql);
                } catch (error) {
                    lastError = error;
                }
            }
            if (lastError) throw lastError;
            return [];
        })()
    ]);

    const brickAlerts = brickResult.status === 'fulfilled' && Array.isArray(brickResult.value) ? brickResult.value : [];
    const snapshotRows = snapshotResult.status === 'fulfilled' ? snapshotResult.value : [];
    if (!brickAlerts.length && snapshotResult.status === 'rejected' && brickResult.status === 'rejected') {
        throw snapshotResult.reason || brickResult.reason;
    }
    const movers = buildSnapshotMovers(snapshotRows);
    const brickItems = brickInsightLines(brickAlerts);
    const items = [...brickItems, ...movers].slice(0, 10);
    const insights = items.map((row) => row.detail);
    if (!insights.length) {
        insights.push('No physician movement or brick sales alerts in the last two months.');
    }
    return { movers, brickAlerts, items, insights };
}
