import { makeDualApex } from './_wireAdapter.js';
import { idbGet, idbSet } from '../views/tabCache.js';
import getPlannerAccountFilterOptions from './getPlannerAccountFilterOptions.js';
import { plannerApiFetch } from './restHelper.js';

const CACHE_KEY = 'stayInTheKnow.articles';
const DEFAULT_LIMIT = 28;
const PROD_FALLBACK = 'https://www.salesforceoffline.com/.netlify/functions/rss-feeds';
const API_VERSION = 'v62.0';

function rssFeedsUrl(specialties, products) {
    let base;
    if (typeof window === 'undefined') {
        base = PROD_FALLBACK;
    } else {
        const origin = window.location && window.location.origin ? window.location.origin : '';
        if (
            origin.includes('localhost') ||
            origin.includes('127.0.0.1') ||
            origin.includes('salesforceoffline.com') ||
            origin.includes('netlify.app')
        ) {
            base = `${origin}/.netlify/functions/rss-feeds`;
        } else {
            base = PROD_FALLBACK;
        }
    }
    const qs = new URLSearchParams();
    if (specialties.length) qs.set('specialties', specialties.join(','));
    if (products.length) qs.set('products', products.join(','));
    const suffix = qs.toString();
    return suffix ? `${base}?${suffix}` : base;
}

function faviconForUrl(articleUrl, domain) {
    const host = (domain || '').trim() || (() => {
        try {
            return new URL(articleUrl).hostname.replace(/^www\./i, '');
        } catch (_err) {
            return '';
        }
    })();
    if (!host) return '';
    return `https://www.google.com/s2/favicons?domain=${encodeURIComponent(host)}&sz=64`;
}

function normalizeArticle(raw) {
    if (!raw || typeof raw !== 'object') {
        return null;
    }
    const title = (raw.title || '').trim();
    const url = (raw.url || '').trim();
    if (!title || !url) {
        return null;
    }
    const domain = (raw.domain || '').trim();
    return {
        id: String(raw.id || `${url}|${title}`),
        category: (raw.category || 'News').trim(),
        title,
        summary: (raw.summary || '').trim(),
        source: (raw.source || '').trim(),
        publishedAt: raw.publishedAt || null,
        url,
        domain,
        faviconUrl: (raw.faviconUrl || '').trim() || faviconForUrl(url, domain)
    };
}

async function loadSpecialties() {
    try {
        const filters = await getPlannerAccountFilterOptions({});
        const options = (filters && filters.specialtyOptions) || [];
        return options
            .map((o) => (o && (o.label || o.value) ? String(o.label || o.value).trim() : ''))
            .filter((v) => v && !/^all\b/i.test(v))
            .slice(0, 3);
    } catch (_err) {
        return [];
    }
}

async function loadProducts() {
    try {
        const path =
            `/services/data/${API_VERSION}/query?q=` +
            encodeURIComponent(
                'SELECT Product2_Id__c FROM Product_Territory_Alignment__c ' +
                    'WHERE Product2_Id__c != null LIMIT 40'
            );
        const result = await plannerApiFetch(path);
        const records = result && Array.isArray(result.records) ? result.records : [];
        const ids = [
            ...new Set(
                records
                    .map((r) => r && r.Product2_Id__c)
                    .filter((id) => id && String(id).length >= 15)
            )
        ].slice(0, 12);
        if (!ids.length) return [];
        const inList = ids.map((id) => `'${String(id).replace(/'/g, "\\'")}'`).join(',');
        const productsPath =
            `/services/data/${API_VERSION}/query?q=` +
            encodeURIComponent(
                `SELECT Name FROM Product2 WHERE Id IN (${inList}) AND IsActive = true LIMIT 8`
            );
        const products = await plannerApiFetch(productsPath);
        const names = (products && Array.isArray(products.records) ? products.records : [])
            .map((r) => (r && r.Name ? String(r.Name).trim() : ''))
            .filter(Boolean);
        return [...new Set(names)].slice(0, 3);
    } catch (_err) {
        return [];
    }
}

async function fetchLive(rowLimit, specialties, products) {
    const res = await fetch(rssFeedsUrl(specialties, products), {
        method: 'GET',
        headers: { Accept: 'application/json' }
    });
    if (!res.ok) {
        throw new Error(`rss-feeds ${res.status}`);
    }
    const payload = await res.json();
    const list = Array.isArray(payload && payload.articles) ? payload.articles : [];
    return list.map(normalizeArticle).filter(Boolean).slice(0, rowLimit);
}

async function loadStayInTheKnowArticles(params) {
    const requested = params && params.limitSize ? Number(params.limitSize) : DEFAULT_LIMIT;
    const rowLimit = Math.min(Math.max(requested || DEFAULT_LIMIT, 1), 40);

    const [specialties, products] = await Promise.all([loadSpecialties(), loadProducts()]);

    try {
        const live = await fetchLive(rowLimit, specialties, products);
        if (live.length) {
            await idbSet(CACHE_KEY, live);
            return live;
        }
    } catch (_err) {
        /* fall through to cache */
    }

    const cached = await idbGet(CACHE_KEY);
    const payload = cached && cached.payload != null ? cached.payload : cached;
    if (Array.isArray(payload) && payload.length) {
        return payload.map(normalizeArticle).filter(Boolean).slice(0, rowLimit);
    }
    return [];
}

export default makeDualApex(loadStayInTheKnowArticles);
