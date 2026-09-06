/**
 * Proxies authenticated Salesforce REST/content requests (CORS-safe for web shell).
 * POST JSON: { url, method, authorization, body?, headers? }
 */
exports.handler = async function (event) {
  if (event.httpMethod === 'OPTIONS') {
    return { statusCode: 204, headers: corsHeaders(), body: '' };
  }
  if (event.httpMethod !== 'POST') {
    return { statusCode: 405, headers: corsHeaders(), body: 'Method Not Allowed' };
  }
  try {
    const payload = JSON.parse(event.body || '{}');
    const targetUrl = String(payload.url || '');
    if (!targetUrl.startsWith('https://')) {
      return {
        statusCode: 400,
        headers: corsHeaders(),
        body: JSON.stringify({ error: 'HTTPS URL required' })
      };
    }
    const host = new URL(targetUrl).hostname.toLowerCase();
    const allowed =
      host === 'login.salesforce.com' ||
      host === 'test.salesforce.com' ||
      host.endsWith('.salesforce.com') ||
      host.endsWith('.force.com') ||
      host.endsWith('.site.com') ||
      host.endsWith('.salesforce-sites.com');
    if (!allowed) {
      return {
        statusCode: 400,
        headers: corsHeaders(),
        body: JSON.stringify({ error: 'URL host is not an allowed Salesforce endpoint' })
      };
    }
    const method = String(payload.method || 'GET').toUpperCase();
    const headers = { ...(payload.headers || {}) };
    if (payload.authorization) headers.Authorization = payload.authorization;
    let body;
    if (payload.body != null && method !== 'GET' && method !== 'DELETE') {
      body = typeof payload.body === 'string' ? payload.body : JSON.stringify(payload.body);
      headers['Content-Type'] = headers['Content-Type'] || 'application/json';
    }
    const upstream = await fetch(targetUrl, { method, headers, body });
    const contentType = upstream.headers.get('content-type') || 'application/octet-stream';
    const buf = Buffer.from(await upstream.arrayBuffer());
    return {
      statusCode: upstream.status,
      headers: {
        ...corsHeaders(),
        'Content-Type': contentType
      },
      isBase64Encoded: true,
      body: buf.toString('base64')
    };
  } catch (e) {
    return {
      statusCode: 500,
      headers: corsHeaders(),
      body: JSON.stringify({ error: e instanceof Error ? e.message : String(e) })
    };
  }
};

function corsHeaders() {
  return {
    'Access-Control-Allow-Origin': '*',
    'Access-Control-Allow-Headers': 'Content-Type, Authorization',
    'Access-Control-Allow-Methods': 'POST, OPTIONS'
  };
}
