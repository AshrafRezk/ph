# OSR Sync Pack

Deployable Apex REST APIs that replace Briefcase for Offline Salesforce Runtime.

## Endpoints

| Method | Path | Purpose |
|--------|------|---------|
| GET | `/services/apexrest/osr/v1/hello` | Health / org+user |
| GET | `/services/apexrest/osr/v1/profile` | Sync profile from CMDT |
| POST | `/services/apexrest/osr/v1/metadata` | Describes, layouts (+ related lists), FlexiPages (DF/visibility/FormFactor), tabs, apps, batched VRs, list views (+ columns/filters), actions, compact layouts |
| POST | `/services/apexrest/osr/v1/data` | Cursor SOQL pages + tombstones |
| POST | `/services/apexrest/osr/v1/sharing` | Pre-authorized ID sets |
| POST | `/services/apexrest/osr/v1/files` | ContentVersion manifest |
| POST | `/services/apexrest/osr/v1/lwc` | LWC static-resource bundles |
| POST | `/services/apexrest/osr/v1/outbox` | Idempotent DML / named actions |
| GET / POST | `/services/apexrest/osr/v1/prefs` | Per-user list-view favourites / pin / calendar field |

## Deploy

```bash
sf project deploy start --source-dir salesforce/sync-pack/main/default
sf org assign permset --name OSR_Sync_Pack_User
```
