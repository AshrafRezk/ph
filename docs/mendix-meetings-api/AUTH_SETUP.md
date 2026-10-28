# Auth setup notes (Salesforce admin)

## What was provisioned

1. **Integration user:** `mendix.api@zetapharma.com`  
   - Profile: Salesforce API Only System Integrations  
   - Password set (see `AUTH_CREDENTIALS.local.md`)  
   - Permsets: `Meeting_Mendix_API`, `Meeting_User`

2. **External Client App:** **Mendix Integration API** (`Mendix_Meetings_API`)  
   - Shared OAuth client for **Meetings and Time Off (TOT)**  
   - Client Credentials flow enabled  
   - Run-as user: `mendix.api@zetapharma.com`  
   - Consumer Key retrieved into credentials file  

3. **Meetings REST** smoke-tested with a Salesforce session token (list + detail + base64).

## One manual step you must do before sharing with Mendix

Salesforce **does not expose Consumer Secret via API**. Reveal it in Setup and put it in:

- Postman `consumer_secret` variable  
- Secure share to Mendix (1Password / encrypted note — not a long-lived email thread)

Then run the Postman **Get Access Token** request to prove client-credentials works end-to-end as the Mendix user.

## Share pack for Mendix

| File | Share? |
|------|--------|
| `EMAIL_BODY.txt` | Yes |
| `API_CONTRACT.md` | Yes |
| `Mendix_Meetings_API.postman_collection.json` | Yes (Consumer Key is in variables; leave secret empty for them to fill) |
| `AUTH_CREDENTIALS.local.md` | **No — private.** Send Key+Secret via secure channel only |
