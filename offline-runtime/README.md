# Offline Salesforce Runtime

Capacitor + TypeScript monorepo that runs Salesforce-like UX fully offline and syncs via a custom **Sync Pack** (no Briefcase).

## Layout

```
offline-runtime/
  apps/shell/           Capacitor + Vite + Lit UI
  packages/db/          SQLite schema + repos (memory fallback)
  packages/sync/        OAuth PKCE + SyncEngine + mock client
  packages/ui-runtime/  Tabs, layouts, FlexiPages, LWC host, journey ports
  packages/validation/  Formula subset + validation rules
  docs/ARCHITECTURE.md
salesforce/sync-pack/   Apex REST APIs + CMDT + tombstones
```

## Live demo (web)

- **Custom domain:** https://www.salesforceoffline.com (also https://salesforceoffline.com)
- Netlify subdomain: https://osr-salesforce-offline.netlify.app
- Admin: https://app.netlify.com/projects/osr-salesforce-offline

**Continuous deploy:** Netlify is connected to GitHub [`AshrafRezk/ph`](https://github.com/AshrafRezk/ph) with base directory `offline-runtime`. Pushes to `main` that change files under `offline-runtime/` trigger production builds (static shell + `sf-token` OAuth proxy function). Manual CLI deploys are no longer required.

Emergency manual deploy (if needed):

```bash
cd offline-runtime
npm run build -w @osr/shell
npx netlify deploy --prod --no-build --dir apps/shell/dist --functions netlify/functions
```
## Quick start (local web)

```bash
cd offline-runtime
npm install
npm run dev
```

Open the app → **Prime mock org** → work offline (airplane mode) → edit/save → Sync.

## Sync Pack (Salesforce)

Deployed to default org alias `pharma-prod` (`admin@pharma.eg`).

```bash
sf project deploy start --source-dir salesforce/sync-pack/main/default --target-org pharma-prod
sf org assign permset --name OSR_Sync_Pack_User --target-org pharma-prod
```

Smoke check: Apex REST `GET /services/apexrest/osr/v1/hello`

Connected App (OAuth PKCE) still needed before real org login from the client.

## Android APK (Capacitor)

Debug APK path after build:

`offline-runtime/dist-android/osr-offline-debug.apk`

Rebuild:

```bash
export JAVA_HOME="/opt/homebrew/opt/openjdk@17/libexec/openjdk.jdk/Contents/Home"
export ANDROID_HOME="/opt/homebrew/share/android-commandlinetools"
cd offline-runtime/apps/shell
npm run build
npx cap sync android
cd android
./gradlew assembleDebug
cp app/build/outputs/apk/debug/app-debug.apk ../../dist-android/osr-offline-debug.apk
```

Install on a device/emulator:

```bash
adb install -r offline-runtime/dist-android/osr-offline-debug.apk
```

## Tests

```bash
cd offline-runtime
npm test
```
