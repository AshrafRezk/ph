# Notion resolution notes (fill when signed in)

Columns to use: **Resolution Description** (Text), **Resolution Screenshots** (Files & media).

| Ref | Status to set | Resolution Description |
|----:|---------------|------------------------|
| 21 | Fixed | Visit Tabs config now runs in SYSTEM_MODE so admins without object CRUD still load/save tab sets. Deployed VisitTabConfigService to ZetaPharma. |
| 22 | Fixed | Coaching template FlexiPage wired; coaching event create no longer blank when template JSON is valid. Deployed Coaching_Template_Record_Page + related LWC. |
| 25 | Fixed | Login As any user enabled in Security settings for Cloudastick admin. Ahmed seated on Head_Office with admin-equivalent PSA. |
| 26 | Fixed | Visit date/time locked in visitCallShell for submitted/synced visits (PWA + SF). Live on https://www.salesforceoffline.com. |
| 27 | Fixed | LMS Admin Console cards restored; upload entry points visible under LMS section. |
| 8 | Fixed | Marketing Services request types seeded via ServiceRequestTypeService.ensureDefaults / seed. |
| 1–4 | Fixed | EPDA / POS / IBNSINA parsers and customer batches hardened; deploy of distributor import classes completed. Re-run Oct pack after datapack card. |
| 7 / 9 / 10 | Fixed | Product catalog delete/bulk-remove fixes deployed. Standard mirrors applied 2026-10-24: CHC_Sales +148, GIT-SALES +34, CVM-I/II +70. Alignment sync batches `LineProductAlignmentSyncBatch` enqueued (deploy `0Afiv0000005a9JCAQ`). |
| 18 / 20 | Fixed | Accounts Active + targets + Class Engine deployed. Root cause of blank specialties: person-type PersonAccount RT lacked Specialty_1..4 values (business RT had them). Deployed PersonAccount.PersonAccount + bulk load 24,549/24,549 (`750iv0000023iOLAAY`). Filled 14,105 → 38,654; 865 null remain (no source in pending CSV). |
| 6 | Closed | CLM is supported on the Offline Field app (salesforceoffline.com). Lightning shows a banner and redirects there — do not present from Lightning. Field Co-pilot includes the CLM Presentations tab. Co Q10 verified on offline. |
| 47 | Fixed | Planner outbox now accepts SAVE_CALL_REPORT and related actions; RestSafeError avoids AuraHandledException LimitException in REST. PWA outbox recovery + stats chip live on Netlify (2026-10-24 deploy). CAPTURE_CONSENT still needs Visit_Consent__c object if that action is required. |
| 33 | In Progress | Notion #33 is sales sheets walkthrough — dictionary at `ph/Plan/Sales_Sheets_Data_Dictionary.md` awaiting Ahmed sign-off. Service-request BRD is a separate chat item (also tracked as row 33 in intake doc). |
| 13 | Partial | Remapped 12 NS products, retired 57 stale districts/positions, seated 4 Diabetes BMs, BU renames Cluster/GIT/Diabetes. Still blocked: 9 NS products + 3 same-name district pairs (CHC DM DELTA, NS DM CAIRO, NS DM GIZA-UE). See `ph/Plan/NEUROSCIENCE_Retire_Blocker.md`. |
| 16 | Fixed | Call_Rate_Rule object + resolver live (territory→Line→BU→Org→12). No rules seeded yet — fallback 12 until Admin seeds. |
| 17 | Fixed | SalesPolicyService / KpiTargetService reads are no-DML; seed via explicit `seedOrgPolicy` / `seedFrameworkDefaults`. |
| 23 | Fixed | Single pro-rated target; recalc on time-off approval. Weekends from Planner Rules (Thu/Fri default). |
| 29 | Partial | Real PharmacySalesDataAdminController + SalesDigestionExampleService deployed (stub replaced). Ceiling/brick-share/item-target fields added. Ahmed is SysAdmin + Pharma_SFE_App — Login-As verify still pending. |
| 5 | Fixed | Export month Admin Console card (XLSX with product + revenue via Unit_Price). Consolidated Pharmacy Sales report type. Product__c on sales lines; backfill batch started. |
| 11 | Fixed | Users Title filter debounced; title options no longer collapse to selection. |
| 12 | Fixed | Business Unit dropdown uses organogram BUs (CHC/Cluster/Diabetes/GIT/Training). |
| 14 | Fixed | Hire / Resignation / Last Work Day on Users; HR backfill 772 matched users. |
| 19 | Fixed | Planner Rules Line+Title scope (e.g. CHC\|\|Medical Rep). |
| 24 | Fixed | IBNSINA rematch via AccountCognitiveSearch + brick; Egypt map bounds; Re-match unmapped button. |
| 28 | Closed (leave) | Notion #28 is Product activation by date per line (already Closed). Sellout rematch belongs on #24 (IBNSINA sellout mapping). |
| 30 | Fixed | Classification SFE approver routing (Territory2.SFE_Approver__c + ClassificationApprovalRouter). |
| 15 | Partial | Count_Source catalog on KPI targets live. Full recipe builder remains Notion #36. |

## Rows still to add (chat intake)

See `ph/Plan/Notion_Issues_33_to_47.md`. Board currently shows issue 33 as sales sheets only; add 34–47 if missing after login.
