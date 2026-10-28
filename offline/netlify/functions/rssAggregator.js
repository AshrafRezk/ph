/**
 * Shared RSS fetch + parse for Be in the Know.
 * Used by the Netlify rss-feeds function and the Vite local middleware.
 *
 * Supports optional personalization via:
 *   specialties=Cardiology,Diabetes
 *   products=BrandA,BrandB
 */

const CACHE_TTL_MS = 15 * 60 * 1000;
const FETCH_TIMEOUT_MS = 8000;
const MAX_PER_FEED = 6;
const MAX_TOTAL = 30;
const MAX_DYNAMIC = 3;

const BASE_FEEDS = [
    {
        category: 'Pharma',
        source: 'Google News',
        url:
            'https://news.google.com/rss/search?q=pharmaceuticals%20OR%20%22life%20sciences%22%20OR%20biotech&hl=en-US&gl=US&ceid=US:en'
    },
    {
        category: 'Pharma',
        source: 'FDA',
        url: 'https://www.fda.gov/about-fda/contact-fda/stay-informed/rss-feeds/press-releases/rss.xml'
    },
    {
        category: 'Egypt',
        source: 'Google News',
        url:
            'https://news.google.com/rss/search?q=pharmaceuticals%20OR%20pharmacy%20OR%20drug%20OR%20medicine%20when%3A30d&hl=en-EG&gl=EG&ceid=EG:en'
    },
    {
        category: 'Egypt',
        source: 'Google News',
        url:
            'https://news.google.com/rss/search?q=%22Egypt%22%20(pharmaceutical%20OR%20pharma%20OR%20pharmacy%20OR%20medicine%20OR%20drug)&hl=en-EG&gl=EG&ceid=EG:en'
    },
    {
        category: 'Salesforce',
        source: 'Salesforce Blog',
        url: 'https://www.salesforce.com/blog/feed/'
    },
    {
        category: 'Salesforce',
        source: 'Google News',
        url: 'https://news.google.com/rss/search?q=Salesforce&hl=en-US&gl=US&ceid=US:en'
    },
    {
        category: 'Zeta',
        source: 'Google News',
        url:
            'https://news.google.com/rss/search?q=%22Zeta%20Pharma%22%20OR%20Zetapharma%20OR%20%22zeta%20pharmaceuticals%22&hl=en-US&gl=US&ceid=US:en'
    }
];

/** @type {Map<string, { at: number, payload: object }>} */
const cacheByKey = new Map();

function stripHtml(value) {
    if (!value) return '';
    return String(value)
        .replace(/<!\[CDATA\[([\s\S]*?)\]\]>/gi, '$1')
        .replace(/<[^>]+>/g, ' ')
        .replace(/&nbsp;/gi, ' ')
        .replace(/&amp;/gi, '&')
        .replace(/&lt;/gi, '<')
        .replace(/&gt;/gi, '>')
        .replace(/&quot;/gi, '"')
        .replace(/&#39;/gi, "'")
        .replace(/\s+/g, ' ')
        .trim();
}

function decodeXmlEntities(value) {
    if (!value) return '';
    return String(value)
        .replace(/<!\[CDATA\[([\s\S]*?)\]\]>/gi, '$1')
        .replace(/&amp;/gi, '&')
        .replace(/&lt;/gi, '<')
        .replace(/&gt;/gi, '>')
        .replace(/&quot;/gi, '"')
        .replace(/&#39;/gi, "'")
        .replace(/&#(\d+);/g, (_, n) => String.fromCharCode(Number(n)))
        .trim();
}

function tagText(block, tagName) {
    const re = new RegExp(
        `<${tagName}(?:\\s[^>]*)?>([\\s\\S]*?)<\\/${tagName}>`,
        'i'
    );
    const match = block.match(re);
    if (!match) return '';
    return decodeXmlEntities(match[1]);
}

function linkFromItem(block) {
    const atomLink = block.match(/<link[^>]*href=["']([^"']+)["'][^>]*\/?>/i);
    if (atomLink) return decodeXmlEntities(atomLink[1]);
    const rssLink = tagText(block, 'link');
    if (rssLink) return rssLink;
    const guid = tagText(block, 'guid');
    if (guid && /^https?:\/\//i.test(guid)) return guid;
    return '';
}

function hashId(parts) {
    const raw = parts.join('|');
    let h = 0;
    for (let i = 0; i < raw.length; i += 1) {
        h = (h << 5) - h + raw.charCodeAt(i);
        h |= 0;
    }
    return `rss-${Math.abs(h).toString(36)}`;
}

export function hostnameFromUrl(articleUrl) {
    try {
        return new URL(articleUrl).hostname.replace(/^www\./i, '');
    } catch (_err) {
        return '';
    }
}

export function faviconForUrl(articleUrl) {
    const host = hostnameFromUrl(articleUrl);
    if (!host) return '';
    return `https://www.google.com/s2/favicons?domain=${encodeURIComponent(host)}&sz=64`;
}

function parseCsvList(raw, max) {
    if (!raw) return [];
    const seen = new Set();
    const out = [];
    for (const part of String(raw).split(',')) {
        const cleaned = part.trim().replace(/\s+/g, ' ');
        if (!cleaned || cleaned.length < 2) continue;
        const key = cleaned.toLowerCase();
        if (seen.has(key)) continue;
        // Skip generic “All …” filter placeholders
        if (/^all\b/i.test(cleaned)) continue;
        seen.add(key);
        out.push(cleaned.slice(0, 80));
        if (out.length >= max) break;
    }
    return out;
}

export function googleNewsUrl(query, { hl = 'en-US', gl = 'US', ceid = 'US:en' } = {}) {
    const q = encodeURIComponent(query);
    return `https://news.google.com/rss/search?q=${q}&hl=${hl}&gl=${gl}&ceid=${encodeURIComponent(ceid)}`;
}

function buildFeeds(specialties, products) {
    const feeds = [...BASE_FEEDS];
    for (const specialty of specialties.slice(0, MAX_DYNAMIC)) {
        feeds.push({
            category: 'Specialty',
            source: specialty,
            url: googleNewsUrl(
                `"${specialty}" (pharmaceutical OR drug OR therapy OR treatment OR breakthrough OR clinical) when:60d`
            )
        });
        feeds.push({
            category: 'Specialty',
            source: `${specialty} · Egypt`,
            url: googleNewsUrl(
                `"${specialty}" (Egypt OR Egyptian) (pharma OR pharmaceutical OR medicine OR treatment)`,
                { hl: 'en-EG', gl: 'EG', ceid: 'EG:en' }
            )
        });
    }
    for (const product of products.slice(0, MAX_DYNAMIC)) {
        feeds.push({
            category: 'My Products',
            source: product,
            url: googleNewsUrl(
                `"${product}" (drug OR pharmaceutical OR medicine OR therapy OR clinical OR FDA) when:90d`
            )
        });
    }
    return feeds;
}

function parseItems(xml, category, defaultSource) {
    if (!xml || typeof xml !== 'string') return [];
    const items = [];
    const itemBlocks = xml.match(/<item[\s>][\s\S]*?<\/item>/gi) || [];
    const entryBlocks = xml.match(/<entry[\s>][\s\S]*?<\/entry>/gi) || [];
    const blocks = itemBlocks.length ? itemBlocks : entryBlocks;

    for (const block of blocks.slice(0, MAX_PER_FEED)) {
        const title = stripHtml(tagText(block, 'title'));
        const url = linkFromItem(block);
        if (!title || !url) continue;

        const summary = stripHtml(
            tagText(block, 'description') ||
                tagText(block, 'summary') ||
                tagText(block, 'content') ||
                tagText(block, 'content:encoded')
        ).slice(0, 800);

        const publishedAt =
            tagText(block, 'pubDate') ||
            tagText(block, 'published') ||
            tagText(block, 'updated') ||
            tagText(block, 'dc:date') ||
            null;

        const sourceName =
            stripHtml(tagText(block, 'source')) ||
            defaultSource ||
            'News';

        items.push({
            id: hashId([category, url, title]),
            category,
            title,
            summary,
            source: sourceName,
            publishedAt,
            url,
            faviconUrl: faviconForUrl(url),
            domain: hostnameFromUrl(url)
        });
    }
    return items;
}

export async function fetchFeed(feed) {
    const controller = new AbortController();
    const timer = setTimeout(() => controller.abort(), FETCH_TIMEOUT_MS);
    try {
        const res = await fetch(feed.url, {
            method: 'GET',
            signal: controller.signal,
            headers: {
                Accept: 'application/rss+xml, application/atom+xml, application/xml, text/xml, */*',
                'User-Agent': 'ZetaFieldPWA-StayInTheKnow/1.0'
            }
        });
        if (!res.ok) {
            return [];
        }
        const xml = await res.text();
        return parseItems(xml, feed.category, feed.source);
    } catch (_err) {
        return [];
    } finally {
        clearTimeout(timer);
    }
}

function sortByDateDesc(a, b) {
    const ta = a.publishedAt ? Date.parse(a.publishedAt) : 0;
    const tb = b.publishedAt ? Date.parse(b.publishedAt) : 0;
    return (Number.isNaN(tb) ? 0 : tb) - (Number.isNaN(ta) ? 0 : ta);
}

function dedupeByUrl(items) {
    const seen = new Set();
    const out = [];
    for (const item of items) {
        const key = (item.url || '').split('?')[0].toLowerCase();
        if (!key || seen.has(key)) continue;
        seen.add(key);
        out.push(item);
    }
    return out;
}

function cacheKey(specialties, products) {
    return JSON.stringify({
        s: specialties.map((x) => x.toLowerCase()).sort(),
        p: products.map((x) => x.toLowerCase()).sort()
    });
}

/**
 * @param {{ specialties?: string|string[], products?: string|string[] }} [options]
 */
export async function aggregateStayInTheKnow(options = {}) {
    const specialties = Array.isArray(options.specialties)
        ? parseCsvList(options.specialties.join(','), MAX_DYNAMIC)
        : parseCsvList(options.specialties, MAX_DYNAMIC);
    const products = Array.isArray(options.products)
        ? parseCsvList(options.products.join(','), MAX_DYNAMIC)
        : parseCsvList(options.products, MAX_DYNAMIC);

    const key = cacheKey(specialties, products);
    const now = Date.now();
    const hit = cacheByKey.get(key);
    if (hit && now - hit.at < CACHE_TTL_MS) {
        return hit.payload;
    }

    const feeds = buildFeeds(specialties, products);
    const batches = await Promise.all(feeds.map((feed) => fetchFeed(feed)));
    const merged = dedupeByUrl(batches.flat()).sort(sortByDateDesc).slice(0, MAX_TOTAL);

    const categories = [...new Set(merged.map((a) => a.category))];
    const payload = {
        articles: merged,
        fetchedAt: new Date().toISOString(),
        categories,
        specialties,
        products
    };

    cacheByKey.set(key, { at: now, payload });
    return payload;
}

export function rssCorsHeaders() {
    return {
        'Access-Control-Allow-Origin': '*',
        'Access-Control-Allow-Headers': 'Content-Type',
        'Access-Control-Allow-Methods': 'GET, OPTIONS',
        'Cache-Control': 'public, max-age=900'
    };
}

export { CACHE_TTL_MS };
