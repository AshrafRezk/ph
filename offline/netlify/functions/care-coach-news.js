/**
 * Care Coach home news.
 * GET /.netlify/functions/care-coach-news?products=Erbitux,Rebif,Mavenclad,Saizen
 */
import { aggregateCareCoachNews } from './careCoachNews.js';
import { rssCorsHeaders } from './rssAggregator.js';

export async function handler(event) {
    if (event.httpMethod === 'OPTIONS') {
        return { statusCode: 204, headers: rssCorsHeaders(), body: '' };
    }
    if (event.httpMethod !== 'GET') {
        return {
            statusCode: 405,
            headers: rssCorsHeaders(),
            body: JSON.stringify({ error: 'Method Not Allowed' })
        };
    }

    try {
        const params = event.queryStringParameters || {};
        const payload = await aggregateCareCoachNews({ products: params.products || '' });
        return {
            statusCode: 200,
            headers: {
                ...rssCorsHeaders(),
                'Content-Type': 'application/json'
            },
            body: JSON.stringify(payload)
        };
    } catch (e) {
        return {
            statusCode: 500,
            headers: rssCorsHeaders(),
            body: JSON.stringify({
                error: e instanceof Error ? e.message : String(e),
                articles: [],
                categories: [],
                fetchedAt: new Date().toISOString()
            })
        };
    }
}
