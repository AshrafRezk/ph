# Pharma Field Rep Offline — Briefcase activation

## Hybrid model

| Layer | Role |
|-------|------|
| **Briefcase** `Pharma_Field_Rep_Offline` | Salesforce Mobile Offline record sync-down for Visits, Accounts, Coaching Templates/Events, Products |
| **IndexedDB** `pharmaClmOffline` | CLM binary assets, enriched call-report payloads, Home/Planner/Coaching caches, write-ahead action queue |

## Prerequisites

1. Briefcase Builder enabled in the org
2. Field Service / Mobile Offline licensing appropriate for Briefcase priming (verify with Salesforce edition)
3. Deploy metadata via `manifest/offline-package.xml` (or full source deploy)

## Deploy

```bash
sf project deploy start --manifest manifest/offline-package.xml
```

## Activate & assign (Setup)

1. Setup → Briefcase Builder
2. Open **Pharma Field Rep Offline**
3. Confirm rules (assigned visits rolling window, related Account + Coaching_Event__c, active Coaching_Template__c, Product2)
4. Assign to Field Rep users or a Public Group / Permission Set Group
5. Associate with the Salesforce Mobile / Offline apps available in the org
6. Activate if not already active (`isActive=true` in metadata)

## Org limits

- Maximum **5** briefcases per org (installed packages count toward the limit)

## Out of Briefcase (by design)

- CLM deck binaries / ContentVersion blobs → keep IndexedDB `clmContentCache`
- Offline **writes** (call report, planner upsert/reschedule, coaching create/submit, CLM session events) → IndexedDB `actionQueue` → `ClmOfflineSyncController`

## Verify

1. While online: open Field Rep Home (prefetch CLM + today visits + metrics)
2. Airplane mode: open cached Today Plan, Visit Call Report, CLM player, Planner week cache, Coaching modal
3. Reconnect: Field Home prefetch banner shows sync of queued actions
