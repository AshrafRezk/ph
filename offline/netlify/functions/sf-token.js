/**
 * Proxies Salesforce OAuth token exchange / refresh to avoid browser CORS.
 * POST JSON:
 *   authorization_code: { tokenUrl, grant_type, client_id, redirect_uri, code, code_verifier }
 *   refresh_token:      { tokenUrl, grant_type, client_id, refresh_token }
 *
 * Optional Netlify env: SF_CLIENT_SECRET (only if Connected App requires it).
 * Prefer PKCE public clients with isConsumerSecretOptional=true — do not put secrets in VITE_*.
 */
exports.handler = async function (event) {
  if (event.httpMethod === 'OPTIONS') {
    return {
      statusCode: 204,
      headers: corsHeaders(),
      body: ''
    };
  }
  if (event.httpMethod !== 'POST') {
    return { statusCode: 405, headers: corsHeaders(), body: 'Method Not Allowed' };
  }
  try {
    const body = JSON.parse(event.body || '{}');
    const grantType = body.grant_type || 'authorization_code';
    const tokenUrl = body.tokenUrl || 'https://login.salesforce.com/services/oauth2/token';
    const params = new URLSearchParams({
      grant_type: grantType,
      client_id: body.client_id || ''
    });

    if (grantType === 'refresh_token') {
      params.set('refresh_token', body.refresh_token || '');
    } else {
      params.set('redirect_uri', body.redirect_uri || '');
      params.set('code', body.code || '');
      params.set('code_verifier', body.code_verifier || '');
    }

    // Server-side secret only — never accept client_secret from the browser body.
    const serverSecret = process.env.SF_CLIENT_SECRET;
    if (serverSecret) {
      params.set('client_secret', serverSecret);
    }

    const res = await fetch(tokenUrl, {
      method: 'POST',
      headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
      body: params
    });
    const text = await res.text();
    return {
      statusCode: res.status,
      headers: {
        ...corsHeaders(),
        'Content-Type': 'application/json'
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

function corsHeaders() {
  return {
    'Access-Control-Allow-Origin': '*',
    'Access-Control-Allow-Headers': 'Content-Type',
    'Access-Control-Allow-Methods': 'POST, OPTIONS'
  };
}
