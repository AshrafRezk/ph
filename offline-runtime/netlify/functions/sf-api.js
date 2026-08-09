/**
 * Proxies Salesforce REST / Apex REST calls from the browser to avoid CORS.
 * Browser ? Netlify ? Salesforce (server-side; no CORS).
 *
 * POST JSON:
 * {
 *   url: "https://….my.salesforce.com/services/…",
 *   method: "GET"|"POST"|"PATCH"|"PUT"|"DELETE",
 *   authorization: "Bearer …",
 *   body: object | string | null,
 *   headers?: Record<string, string>
 * }
 */
exports.handler = async function (event) {
  if (event.httpMethod === 'OPTIONS') {
    return { statusCode: 204, headers: corsHeaders(), body: '' };
  }
  if (event.httpMethod !== 'POST') {
    return { statusCode: 405, headers: corsHeaders(), body: 'Method Not Allowed' };
  }

  try {
    const body = JSON.parse(event.body || '{}');
    const targetUrl = String(body.url || '');
    const method = String(body.method || 'GET').toUpperCase();
    const authorization = body.authorization || body.Authorization || '';

    if (!isAllowedSalesforceUrl(targetUrl)) {
      return {
        statusCode: 400,
        headers: corsHeaders(),
        body: JSON.stringify({ error: 'URL host is not an allowed Salesforce endpoint' })
      };
    }
    if (!['GET', 'POST', 'PATCH', 'PUT', 'DELETE'].includes(method)) {
      return {
        statusCode: 400,
        headers: corsHeaders(),
        body: JSON.stringify({ error: `Unsupported method: ${method}` })
      };
    }

    const headers = {
      Accept: 'application/json',
      ...(body.headers && typeof body.headers === 'object' ? body.headers : {})
    };
    if (authorization) {
      headers.Authorization = authorization;
    }

    let upstreamBody;
    if (body.body != null && method !== 'GET' && method !== 'DELETE') {
      if (typeof body.body === 'string') {
        upstreamBody = body.body;
        if (!headers['Content-Type'] && !headers['content-type']) {
          headers['Content-Type'] = 'application/json';
        }
      } else {
        upstreamBody = JSON.stringify(body.body);
        headers['Content-Type'] = headers['Content-Type'] || 'application/json';
      }
    }

    const res = await fetch(targetUrl, {
      method,
      headers,
      body: upstreamBody
    });
    const text = await res.text();
    const contentType = res.headers.get('content-type') || 'application/json';

    return {
      statusCode: res.status,
      headers: {
        ...corsHeaders(),
        'Content-Type': contentType
      },
      body: text
    };
  } catch (e) {
    return {
      statusCode: 500,
      headers: corsHeaders(),
      body: JSON.stringify({ error: e instanceof Error ? e.message : String(e) })
    };
  }
};

function isAllowedSalesforceUrl(urlStr) {
  try {
    const u = new URL(urlStr);
    if (u.protocol !== 'https:') return false;
    const h = u.hostname.toLowerCase();
    return (
      h === 'login.salesforce.com' ||
      h === 'test.salesforce.com' ||
      h.endsWith('.salesforce.com') ||
      h.endsWith('.force.com') ||
      h.endsWith('.site.com') ||
      h.endsWith('.salesforce-sites.com')
    );
  } catch {
    return false;
  }
}

function corsHeaders() {
  return {
    'Access-Control-Allow-Origin': '*',
    'Access-Control-Allow-Headers': 'Content-Type, Authorization',
    'Access-Control-Allow-Methods': 'POST, OPTIONS'
  };
}
