/**
 * Care Coach home news: competitor coverage, Egypt shelf prices, FAERS reactions,
 * and guideline headlines for the programme products.
 *
 * Shelf prices come from public listings:
 *   - El Ezaby (elezabypharmacy.com public search)
 *   - Seif Pharmacies (seif-online.com customer search)
 *   - Chefaa (public storefront search)
 * Prices are what those sites show at fetch time. They are not a quote for a patient.
 */

import { faviconForUrl, fetchFeed, googleNewsUrl, hostnameFromUrl } from './rssAggregator.js';

const CACHE_TTL_MS = 15 * 60 * 1000;
const FETCH_TIMEOUT_MS = 8000;
const BROWSER_UA =
    'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/128.0.0.0 Safari/537.36';

const DEFAULT_PRODUCTS = ['Erbitux', 'Rebif', 'Mavenclad', 'Saizen'];

/** Brand knowledge so searches stay on the medicine, not a fuzzy lookalike. */
const KNOWN = {
    erbitux: {
        inn: 'cetuximab',
        competitors: ['Vectibix', 'panitumumab']
    },
    rebif: {
        inn: 'interferon beta-1a',
        competitors: ['Avonex', 'Plegridy', 'Kesimpta']
    },
    mavenclad: {
        inn: 'cladribine',
        competitors: ['Ocrevus', 'Kesimpta', 'Gilenya']
    },
    saizen: {
        inn: 'somatropin',
        competitors: ['Norditropin', 'Genotropin', 'Omnitrope']
    }
};

/** FAERS terms that are the disease or a data-entry label, not a reaction. */
const AE_SKIP = new Set(
    [
        'off label use',
        'product use issue',
        'drug ineffective',
        'multiple sclerosis',
        'multiple sclerosis relapse',
        'growth hormone deficiency',
        'condition aggravated',
        'no adverse event',
        'intentional product use issue',
        'therapy non-responder',
        'product dose omission',
        'wrong technique in product usage process',
        'expired product administered',
        'therapeutic response unexpected',
        'disease progression',
        'malignant neoplasm progression',
        'colorectal cancer',
        'head and neck cancer'
    ].map((s) => s.toLowerCase())
);

/** @type {Map<string, { at: number, payload: object }>} */
const cacheByKey = new Map();

function hashId(parts) {
    const raw = parts.join('|');
    let h = 0;
    for (let i = 0; i < raw.length; i += 1) {
        h = (h << 5) - h + raw.charCodeAt(i);
        h |= 0;
    }
    return `ccn-${Math.abs(h).toString(36)}`;
}

function escapeRe(value) {
    return String(value).replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
}

function hasToken(text, token) {
    if (!text || !token || String(token).length < 4) return false;
    return new RegExp(`(?:^|[^A-Za-z0-9])${escapeRe(token)}(?:[^A-Za-z0-9]|$)`, 'i').test(text);
}

function parseProductList(raw) {
    const seen = new Set();
    const out = [];
    const parts = Array.isArray(raw) ? raw : String(raw || '').split(',');
    for (const part of parts) {
        const name = String(part || '').trim().replace(/\s+/g, ' ').slice(0, 80);
        if (name.length < 2) continue;
        const key = name.toLowerCase();
        if (seen.has(key)) continue;
        seen.add(key);
        out.push(name);
        if (out.length >= 6) break;
    }
    return out.length ? out : DEFAULT_PRODUCTS.slice();
}

function describeProduct(name) {
    const known = KNOWN[name.toLowerCase()] || {};
    return {
        brand: name,
        inn: known.inn || '',
        competitors: known.competitors || []
    };
}

async function fetchText(url, { timeout = FETCH_TIMEOUT_MS, headers = {}, json = false } = {}) {
    const controller = new AbortController();
    const timer = setTimeout(() => controller.abort(), timeout);
    try {
        const res = await fetch(url, {
            method: 'GET',
            signal: controller.signal,
            headers: {
                Accept: json ? 'application/json' : '*/*',
                'User-Agent': BROWSER_UA,
                ...headers
            }
        });
        if (!res.ok) return null;
        return json ? res.json() : res.text();
    } catch (_err) {
        return null;
    } finally {
        clearTimeout(timer);
    }
}

async function fetchJson(url, { method = 'GET', body, headers = {} } = {}) {
    const controller = new AbortController();
    const timer = setTimeout(() => controller.abort(), FETCH_TIMEOUT_MS);
    try {
        const res = await fetch(url, {
            method,
            signal: controller.signal,
            headers: {
                Accept: 'application/json',
                'User-Agent': BROWSER_UA,
                ...headers
            },
            body
        });
        if (!res.ok) return null;
        return res.json();
    } catch (_err) {
        return null;
    } finally {
        clearTimeout(timer);
    }
}

function egp(value) {
    const num = Number(value);
    if (!Number.isFinite(num) || num <= 0) return '';
    const rounded = Math.round(num * 100) / 100;
    const text = rounded.toLocaleString('en-US', {
        minimumFractionDigits: rounded % 1 ? 2 : 0,
        maximumFractionDigits: 2
    });
    return `EGP ${text}`;
}

function cleanOfferName(name) {
    return String(name || '')
        .replace(/\s+/g, ' ')
        .trim();
}

function isSpecialListing(name) {
    return /\(xx\)/i.test(name);
}

function keepOffers(offers) {
    const standard = offers.filter((o) => !isSpecialListing(o.name));
    const pool = standard.length ? standard : offers;
    const seen = new Set();
    const out = [];
    for (const offer of pool.sort((a, b) => a.price - b.price)) {
        const key = offer.name.toLowerCase();
        if (seen.has(key)) continue;
        seen.add(key);
        out.push(offer);
        if (out.length >= 3) break;
    }
    return out;
}

function offerFrom(source, token, row) {
    const name = cleanOfferName(row.name);
    const price = Number(row.price);
    if (!name || !hasToken(name, token) || !Number.isFinite(price) || price <= 0) return null;
    return {
        source,
        token,
        name,
        price,
        priceLabel: egp(price),
        url: row.url,
        special: isSpecialListing(name)
    };
}

async function searchSeif(token) {
    const data = await fetchJson(
        `https://seif-online.com/api/customer/products/search?q=${encodeURIComponent(token)}`
    );
    const products = data && data.data && Array.isArray(data.data.products) ? data.data.products : [];
    return keepOffers(
        products
            .map((p) =>
                offerFrom('Seif Pharmacies', token, {
                    name: p.name_en || p.name,
                    price: p.discount_price || p.price,
                    url:
                        (p.share_link && /^https?:/i.test(p.share_link) && p.share_link) ||
                        (p.slug ? `https://seif-online.com/en/product/${p.slug}` : 'https://seif-online.com/en')
                })
            )
            .filter(Boolean)
    );
}

let chefaaConfigPromise = null;

async function chefaaConfig() {
    if (!chefaaConfigPromise) {
        chefaaConfigPromise = (async () => {
            const html = await fetchText('https://chefaa.com/eg-en');
            if (!html) return null;
            const key = html.match(/searchKey\s*=\s*"([a-f0-9]{16,})"/i);
            const host = html.match(/searchHost\s*=\s*"(https:\/\/[^"]+)"/i);
            const index = html.match(/INDEX_NAME\s*=\s*"([a-z0-9_]+)"/i);
            if (!key || !host || !index) return null;
            return { key: key[1], host: host[1], index: index[1] };
        })().catch(() => null);
    }
    return chefaaConfigPromise;
}

async function searchChefaa(token) {
    const cfg = await chefaaConfig();
    if (!cfg) return [];
    const data = await fetchJson(`${cfg.host}/indexes/${cfg.index}/search`, {
        method: 'POST',
        headers: {
            Authorization: `Bearer ${cfg.key}`,
            'Content-Type': 'application/json'
        },
        body: JSON.stringify({ q: token, limit: 8 })
    });
    const hits = data && Array.isArray(data.hits) ? data.hits : [];
    return keepOffers(
        hits
            .map((h) =>
                offerFrom('Chefaa', token, {
                    name: h.title_en || h.title_ar,
                    price: h.final_price || h.price,
                    url: h.full_url || 'https://chefaa.com/eg-en'
                })
            )
            .filter(Boolean)
    );
}

/**
 * El Ezaby's public site is a corporate WordPress install. It has no shelf-price
 * catalog today; we still search it so a listing shows up if they publish one.
 */
async function searchEzaby(token) {
    const html = await fetchText(
        `https://elezabypharmacy.com/?s=${encodeURIComponent(token)}&post_type=product`
    );
    if (!html || /can(?:&#039;|')t find what you(?:&#039;|')re looking for/i.test(html)) {
        return [];
    }
    const blocks = html.match(/<li[^>]*class="[^"]*product[^"]*"[\s\S]*?<\/li>/gi) || [];
    const offers = [];
    for (const block of blocks) {
        const title = (block.match(/<h[12][^>]*>([\s\S]*?)<\/h[12]>/i) || [])[1] || '';
        const name = title.replace(/<[^>]+>/g, ' ').replace(/\s+/g, ' ').trim();
        const amount = (block.match(/woocommerce-Price-amount[\s\S]*?([\d,.]+)/i) || [])[1];
        const href = (block.match(/href="(https?:\/\/[^"]+)"/i) || [])[1] || 'https://elezabypharmacy.com/';
        const price = amount ? Number(amount.replace(/,/g, '')) : NaN;
        const offer = offerFrom('El Ezaby', token, { name, price, url: href });
        if (offer) offers.push(offer);
    }
    return keepOffers(offers);
}

function linesFor(source, offers, emptyLabel) {
    if (!offers.length) return [`${source} — ${emptyLabel}`];
    return offers.map((o) => {
        const note = o.special ? ' (special listing)' : '';
        return `${source} — ${o.name} — ${o.priceLabel}${note}`;
    });
}

async function priceArticle(product) {
    const ownToken = product.brand;
    const competitorTokens = product.competitors.slice(0, 2);
    const [ezabyOwn, seifOwn, chefaaOwn, seifComp, chefaaComp] = await Promise.all([
        searchEzaby(ownToken),
        searchSeif(ownToken),
        searchChefaa(ownToken),
        Promise.all(competitorTokens.map((token) => searchSeif(token))).then((lists) => lists.flat()),
        Promise.all(competitorTokens.map((token) => searchChefaa(token))).then((lists) => lists.flat())
    ]);

    const own = [...ezabyOwn, ...seifOwn, ...chefaaOwn];
    const competitors = [...seifComp, ...chefaaComp].filter((o) => !hasToken(o.name, ownToken));

    const lines = [
        ...linesFor('El Ezaby', ezabyOwn, 'no shelf price on the public website'),
        ...linesFor('Seif Pharmacies', seifOwn, 'not listed'),
        ...linesFor('Chefaa', chefaaOwn, 'not listed')
    ];
    if (!own.length) {
        lines.push('No retail shelf price was listed. Hospital-only packs are often absent from pharmacy websites.');
    }
    if (competitors.length) {
        lines.push('Competitor shelf prices');
        for (const offer of competitors.slice(0, 4)) {
            lines.push(`${offer.source} — ${offer.name} — ${offer.priceLabel}`);
        }
    }
    lines.push('Public listing at fetch time. Confirm with the pharmacy before quoting a patient.');

    const link = own[0] ||
        competitors[0] || {
            url: `https://elezabypharmacy.com/?s=${encodeURIComponent(product.brand)}&post_type=product`
        };
    const checked = ['El Ezaby', 'Seif Pharmacies', 'Chefaa'].filter((name) => {
        if (name === 'El Ezaby') return true;
        if (name === 'Seif Pharmacies') return seifOwn.length || seifComp.length;
        return chefaaOwn.length || chefaaComp.length;
    });

    return {
        id: hashId(['Prices', product.brand, lines[0]]),
        category: 'Prices',
        title: `${product.brand} — Egypt market prices`,
        summary: lines.join('\n'),
        source: checked.join(' · '),
        publishedAt: new Date().toISOString(),
        url: link.url,
        domain: hostnameFromUrl(link.url),
        faviconUrl: faviconForUrl(link.url),
        linkLabel: 'Open listing'
    };
}

async function adverseArticle(product) {
    const query = product.inn
        ? `patient.drug.openfda.generic_name:"${product.inn}"`
        : `patient.drug.medicinalproduct:"${product.brand}"`;
    const data = await fetchJson(
        `https://api.fda.gov/drug/event.json?search=${encodeURIComponent(query)}&count=patient.reaction.reactionmeddrapt.exact&limit=14`
    );
    const rows = (data && Array.isArray(data.results) ? data.results : []).filter(
        (row) => row && row.term && !AE_SKIP.has(String(row.term).toLowerCase())
    );
    const isDevice = (term) => /device|dose omission/i.test(term);
    let reactions = rows.slice(0, 5);
    if (reactions.length && reactions.every((row) => isDevice(row.term))) {
        const clinical = rows.filter((row) => !isDevice(row.term)).slice(0, 2);
        reactions = [...reactions.slice(0, 3), ...clinical];
    }
    if (!reactions.length) return null;

    const updated = (data.meta && data.meta.last_updated) || '';
    const who = product.inn ? `${product.brand} (${product.inn})` : product.brand;
    const lines = reactions.map(
        (row, i) => `${i + 1}. ${titleCase(row.term)} — ${Number(row.count).toLocaleString('en-US')} reports`
    );
    lines.push(
        'FDA FAERS spontaneous reports, including international reports sent to FDA. These are not incidence rates and are not a substitute for the product label.'
    );
    if (updated) lines.push(`FAERS extract updated ${updated}.`);

    return {
        id: hashId(['Adverse events', product.brand, reactions[0].term]),
        category: 'Adverse events',
        title: `${who} — frequently reported reactions`,
        summary: lines.join('\n'),
        source: 'FDA FAERS',
        publishedAt: updated ? `${updated}T00:00:00Z` : new Date().toISOString(),
        url: 'https://www.fda.gov/drugs/questions-and-answers-fdas-adverse-event-reporting-system-faers/fda-adverse-event-reporting-system-faers-public-dashboard',
        domain: 'fda.gov',
        faviconUrl: faviconForUrl('https://www.fda.gov/'),
        linkLabel: 'Open FAERS dashboard'
    };
}

function titleCase(value) {
    return String(value || '')
        .toLowerCase()
        .replace(/\b[a-z]/g, (c) => c.toUpperCase());
}

function newsFeeds(product) {
    const brand = product.brand;
    const inn = product.inn;
    const identity = inn ? `"${brand}" OR "${inn}"` : `"${brand}"`;
    const rivals = product.competitors.map((name) => `"${name}"`).join(' OR ');
    const feeds = [];
    if (rivals) {
        feeds.push({
            category: 'Competitors',
            source: brand,
            url: googleNewsUrl(`(${rivals}) (approval OR launch OR "market share" OR competitor OR biosimilar OR price) when:180d`)
        });
    }
    feeds.push({
        category: 'Prices',
        source: `${brand} · market`,
        url: googleNewsUrl(
            `(${identity}) (price OR shortage OR "price increase" OR pricing) (Egypt OR pharmacy OR Ezaby OR Seif OR Chefaa)`,
            { hl: 'en-EG', gl: 'EG', ceid: 'EG:en' }
        )
    });
    feeds.push({
        category: 'Adverse events',
        source: `${brand} · safety`,
        url: googleNewsUrl(
            `(${identity}) ("adverse event" OR "side effect" OR "safety signal" OR FAERS OR PRAC OR "black box") when:180d`
        )
    });
    feeds.push({
        category: 'Recommendations',
        source: `${brand} · guidelines`,
        url: googleNewsUrl(
            `(${identity}) (guideline OR "treatment recommendation" OR "standard of care" OR consensus OR NICE OR ESMO OR ECTRIMS OR "Endocrine Society") when:365d`
        )
    });
    return feeds;
}

function mentions(blob, token) {
    if (!token) return false;
    if (token.includes(' ')) return blob.toLowerCase().includes(token.toLowerCase());
    return hasToken(blob, token);
}

function onLabel(blob, product) {
    return mentions(blob, product.brand) || mentions(blob, product.inn);
}

function tagNews(items, product, category, limit) {
    const medical =
        /\b(drug|medicine|pharma|inject|tablet|sclerosis|cancer|tumou?r|hormone|therapy|patient|dose|clinical|fda|ema|biosimilar|recall|growth|colorectal|oncolog)/i;
    const accepted = items.filter((item) => {
        const blob = `${item.title || ''} ${item.summary || ''}`;
        if (category === 'Competitors') {
            return product.competitors.some((name) => mentions(blob, name));
        }
        if (!onLabel(blob, product)) return false;
        if (category === 'Prices') return /price|cost|shortage|pricing/i.test(blob);
        if (product.inn && mentions(blob, product.inn)) return true;
        return medical.test(blob);
    });
    return accepted.slice(0, limit).map((item) => ({
        ...item,
        summary: item.summary || item.title,
        linkLabel: 'Open full article',
        source: item.source && item.source !== 'Google News' ? item.source : product.brand
    }));
}

/**
 * @param {{ products?: string|string[] }} [options]
 */
export async function aggregateCareCoachNews(options = {}) {
    const names = parseProductList(options.products);
    const key = names.map((n) => n.toLowerCase()).sort().join('|');
    const now = Date.now();
    const hit = cacheByKey.get(key);
    if (hit && now - hit.at < CACHE_TTL_MS) {
        return hit.payload;
    }

    const products = names.map(describeProduct);
    const [priceAndSafety, newsBatches] = await Promise.all([
        Promise.all(
            products.map(async (product) => {
                const [price, adverse] = await Promise.all([priceArticle(product), adverseArticle(product)]);
                return [price, adverse].filter(Boolean);
            })
        ),
        Promise.all(
            products.map(async (product) => {
                const feeds = newsFeeds(product);
                const batches = await Promise.all(feeds.map((feed) => fetchFeed(feed)));
                const grouped = { Competitors: [], Prices: [], 'Adverse events': [], Recommendations: [] };
                batches.forEach((items, index) => {
                    const category = feeds[index].category;
                    grouped[category].push(...items);
                });
                return [
                    ...tagNews(grouped.Competitors, product, 'Competitors', 2),
                    ...tagNews(grouped.Prices, product, 'Prices', 1),
                    ...tagNews(grouped['Adverse events'], product, 'Adverse events', 1),
                    ...tagNews(grouped.Recommendations, product, 'Recommendations', 2)
                ];
            })
        )
    ]);

    const articles = [];
    priceAndSafety.forEach((rows) => articles.push(...rows));
    newsBatches.forEach((rows) => articles.push(...rows));

    const seen = new Set();
    const unique = [];
    for (const article of articles) {
        const dedupe = `${article.category}|${(article.url || '').split('?')[0].toLowerCase()}|${article.title}`;
        if (seen.has(dedupe)) continue;
        seen.add(dedupe);
        unique.push(article);
    }

    const payload = {
        articles: unique.slice(0, 36),
        fetchedAt: new Date().toISOString(),
        categories: [...new Set(unique.map((a) => a.category))],
        products: names
    };
    cacheByKey.set(key, { at: now, payload });
    return payload;
}
