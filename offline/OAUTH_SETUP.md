# OAuth setup (Netlify + Capacitor)

See [README.md](./README.md) for the current Netlify + Connected App cutover.

Summary:

- Flow: Authorization Code + **PKCE** (no client secret in the browser); authorize scopes `id api web full refresh_token` (Connected App: Full + Refresh Token, etc.)
- Token proxy: `/.netlify/functions/sf-token` (not Vercel) — must be **ESM** (`export async function handler`) because `offline/package.json` has `"type": "module"` (CommonJS `exports.handler` returns 502)
- API proxy: `/.netlify/functions/sf-api` (browser CORS; same ESM requirement)
- Web callback: `https://www.salesforceoffline.com/oauth/callback` (exact match in Connected App + `VITE_SF_WEB_REDIRECT_URI`)
- Netlify: `force=true` rewrite of `/oauth/callback` → SPA `index.html` (no static `public/oauth/callback` page — that caused a trailing-slash 301)
- Native callback: `com.zetapharma.fieldpwa://oauth/callback`
- Local HTTPS: `https://localhost:5173/oauth/callback`

## Netlify env (build + functions)

| Variable | Where | Notes |
| --- | --- | --- |
| `VITE_SF_CLIENT_ID` | Build | **Connected App** consumer key (works across orgs). Do **not** use an External Client App key — Salesforce returns `Cross-org OAuth flows are not supported for this external client app`. |
| `VITE_SF_WEB_REDIRECT_URI` | Build | `https://www.salesforceoffline.com/oauth/callback` |
| `VITE_SF_LOGIN_URL` | Build (optional) | Default `https://login.salesforce.com`; login form can override |
| `VITE_SF_REDIRECT_URI` | Build (native) | Capacitor deep link |
| `SF_CLIENT_SECRET` | Functions only (optional) | Only if Connected App still requires a secret; prefer PKCE public client |

Do **not** set `VITE_SF_INSTANCE_URL` on Netlify. That value is a local Vite proxy target only; baking it in sends every user to one org.

## Connected App checklist

This PWA is multi-org. The login client **must** be a classic **Connected App** in App Manager, not an External Client App. Local ECAs cannot authorize users from other Salesforce companies (including My Domain hosts like `cloudastick.my.salesforce.com`).

Use **Pharma Field Offline** (`Pharma_Field_Offline`) in the Pharmaceuticals org (`pharma-prod` / `admin@pharma.eg`). Zeta cannot create new Connected Apps after Spring ’26. Permitted users: all users may self-authorize. PKCE required; consumer secret optional. Set Netlify `VITE_SF_CLIENT_ID` to that app’s consumer key and rebuild.

Add **exactly**:

- `https://www.salesforceoffline.com/oauth/callback`
- `https://localhost:5173/oauth/callback` (local)
- Native scheme(s) as needed

Scopes: Full, Refresh Token, API, Web, and OpenID/`id` as configured for OSR Offline Runtime.

Rotate any Connected App secret that was previously committed in the upstream Zeta repo.
