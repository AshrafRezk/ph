/**
 * Proxies Salesforce OAuth token exchange to avoid browser CORS.
 * POST JSON: { tokenUrl, grant_type, client_id, redirect_uri, code, code_verifier }
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
    const tokenUrl = body.tokenUrl || 'https://login.salesforce.com/services/oauth2/token';
    const params = new URLSearchParams({
      grant_type: body.grant_type || 'authorization_code',
      client_id: body.client_id || '',
      redirect_uri: body.redirect_uri || '',
      code: body.code || '',
      code_verifier: body.code_verifier || ''
    });
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
