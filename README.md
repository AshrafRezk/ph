# Pharmaceuticals

This repository is split into two parts:

## 1. Salesforce (Pharmaceuticals org)

Salesforce DX project for the Pharmaceuticals org — Apex, LWC, Aura, metadata, manifests, and related scripts.

| Path | What’s here |
|------|-------------|
| `force-app/` | Deployable Salesforce metadata |
| `manifest/` | Package manifests for retrieve/deploy |
| `scripts/` | Apex/Python helpers for seeding, CLMs, ops |
| `Plan/` | BRDs, scoping docs, catalogs, planning notes |
| `config/`, `sfdx-project.json` | Salesforce DX project config |

Target org alias used in npm scripts: `pharma-prod`.

## 2. Offline runtime (Vite + Capacitor stack)

Modern JS stack for the Salesforce offline runtime — Vite-based UI/shell components for pharma field use, packaged with Capacitor (no Briefcase).

| Path | What’s here |
|------|-------------|
| `offline-runtime/` | Monorepo root (`offline-salesforce-runtime`) |
| `offline-runtime/apps/` | App shell (Vite) |
| `offline-runtime/packages/` | Shared packages (DB, sync, validation, UI runtime) |

```bash
# Salesforce (repo root)
npm install
sf project retrieve start --manifest manifest/package.xml --target-org pharma-prod

# Offline runtime
cd offline-runtime
npm install
npm run dev
```
