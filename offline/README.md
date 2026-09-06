# Pharma Field PWA (Zeta offline shell)

Vite + Capacitor app that compiles Salesforce LWCs from `../force-app/main/default/lwc`
and runs them as a Progressive Web App / native shell.

This replaces the older Lit-based `offline-runtime/` shell for Netlify hosting once
you switch the Netlify **base directory** to `offline`. Keep `offline-runtime/` in git
until cutover is verified.

## Live target

- Custom domain: https://www.salesforceoffline.com
- Netlify site: https://osr-salesforce-offline.netlify.app
- Admin: https://app.netlify.com/projects/osr-salesforce-offline

## Local development

```bash
cd offline
cp .env.example .env   # fill VITE_SF_CLIENT_ID at minimum
npm install
npm run dev
```

Open `https://localhost:5173` (Vite uses basic SSL). The login card defaults
**Company login page** to the My Domain label from `VITE_SF_INSTANCE_URL`
(e.g. `zetapharma`).

Local stubs for `/.netlify/functions/sf-token` and `sf-api` are built into Vite
so OAuth + REST work without the Netlify CLI.

## Netlify cutover checklist

### 1. Site settings

- **Base directory:** `offline` (was `offline-runtime`)
- **Build command / publish:** from [`netlify.toml`](netlify.toml) (`npm run build` ? `dist`)
- **Functions directory:** `netlify/functions` (`sf-token`, `sf-api`)

### 2. Environment variables (build-time `VITE_*`)

| Variable | Value | Notes |
|----------|--------|--------|
| `VITE_SF_INSTANCE_URL` | `https://zetapharma.my.salesforce.com` | **Omar’s var** — proxy default + login prefill |
| `VITE_SF_CLIENT_ID` | Connected App consumer key | Keep from existing OSR site |
| `VITE_SF_LOGIN_URL` | `https://login.salesforce.com` | Form can override via My Domain |
| `VITE_SF_WEB_REDIRECT_URI` | `https://www.salesforceoffline.com/oauth/callback` | Must match Connected App |
| `VITE_SF_REDIRECT_URI` | `com.zetapharma.fieldpwa://oauth/callback` | Native Capacitor |

**Do not set**

- `VITE_SF_ACCESS_TOKEN` — real OAuth login is restored
- Any `VITE_*` client secret — would be baked into the JS bundle

Optional function-only (not `VITE_`): `SF_CLIENT_SECRET` only if PKCE-without-secret fails.
Prefer the existing OSR Connected App with consumer secret optional + PKCE.

### 3. Salesforce Connected App callbacks

Add (or confirm):

- `https://www.salesforceoffline.com/oauth/callback`
- `https://salesforceoffline.com/oauth/callback`
- `https://osr-salesforce-offline.netlify.app/oauth/callback`
- `https://localhost:5173/oauth/callback` (local HTTPS Vite)
- `com.zetapharma.fieldpwa://oauth/callback` (Capacitor)

Remove when done: `https://omarikas.github.io/Zeta` and the Vercel token proxy.

### 4. Security (do first)

Omar’s original PWA committed a Connected App **client secret** in JS. That secret must be
**rotated in Salesforce**. This repo’s `offline/src` uses PKCE only and exchanges tokens
via `/.netlify/functions/sf-token` with **no browser secret**.

### 5. Apex / org deploy for the PWA

The PWA calls REST facades:

- `/services/apexrest/planner/v1/*` ? `PlannerMobileRestService`
- `/services/apexrest/clm/v1/*` ? `ClmMobileRestService`

Deploy the new/updated classes (and `Meeting__c`, visit `Submitted` status, etc.) to the
target org, then assign permission set `Planner_Mobile_API`.

## Architecture

```
Browser / Capacitor
  ? Login card (Live / Practice / Company My Domain)
  ? Salesforce OAuth PKCE
  ? Netlify sf-token (token exchange / refresh)
  ? SPA + compiled LWCs
  ? Netlify sf-api (CORS proxy to Salesforce REST)
```

## Android

```bash
npm run build
npx cap sync android
```

APK download link for the web menu is served from `public/downloads/`
(`osr-offline-latest.apk` + `apk-latest.json`).
