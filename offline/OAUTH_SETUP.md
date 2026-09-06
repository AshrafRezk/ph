# OAuth setup (Netlify + Capacitor)

See [README.md](./README.md) for the current Netlify + Connected App cutover.

Summary:

- Flow: Authorization Code + **PKCE** (no client secret in the browser); authorize scopes `id api web full refresh_token` (Connected App: Full + Refresh Token, etc.)
- Token proxy: `/.netlify/functions/sf-token` (not Vercel)
- API proxy: `/.netlify/functions/sf-api` (browser CORS)
- Web callback: `https://www.salesforceoffline.com/oauth/callback`
- Native callback: `com.zetapharma.fieldpwa://oauth/callback`
- Local HTTPS: `https://localhost:5173/oauth/callback`

Rotate any Connected App secret that was previously committed in the upstream Zeta repo.
