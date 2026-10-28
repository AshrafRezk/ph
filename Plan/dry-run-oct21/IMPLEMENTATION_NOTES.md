# Implementation notes — Oct 21 dry-run plan

Shipped 22 Oct 2026 in the Zeta Pharma `force-app/` tree (and Wave 0 files under this folder).

## Wave 0
- Validation checklist, promo-grid template, SFE issue log, Zeta data/decisions request, LMS/teaser inventory.

## Wave 1 — Admin console
- Users: server-side Title / Line / Territory / BU / Status filters, active/inactive/total counts, pagination, no `%pharma%` cap.
- Territories: BU filter, call-rate column, descendant user rollup on Line/BU/District.
- Manage Products: multi-select bulk remove; CHC/GIT/CVM mirror action; Brand Manager seating action.
- Line options: all lines under a BU (removed LIMIT 6).

## Hierarchy
- Area Managers on a line with no National get line scope (`TerritoryHierarchyService.promoteActingNationalScope`).
- `BrandManagerSeatService` seats Brand Managers on Line and Group Brand Leads on BU.

## Direct distribution
- `Sales_Distributor__c` registry (seeds Zeta Direct + existing distributors).
- Direct Excel adapter; sellout paging past 500; confirmed pharmacies kept when a distributor is selected.

## Permissions / Login As
- Territory preview (no password set); OTP labeled as password reset only.
- `Merge_Account_Duplicates` custom permission; SFE-only merge.
- `Field_Territory_Class_Access` permission set for switcher + Class Engine.

## Target governance
- Rep potential/penetration only (Class Engine); DM cannot override class.
- Out-of-target visits count only when `Validation_Status__c = Valid`.
- `TargetGovernanceService` ±10% frequency alarms; DM target-list remove without class change.
- `OutOfTargetQueueService` end-of-month DM → FI → BU queue.

## Sales policy
- `Sales_Policy__c`, `Pharmacy_Chain__c`, `Product_Monthly_Price__c`, `Account.Is_Tender__c`.
- Digestion example reads ceiling/share from org policy; Colest exception brands on policy.

## KPIs
- DSM planned field days = 80% of days after holidays/TOT reductions.
- KPI Period + Scope Level/Key; admin can add a KPI.

## Data repair / remaining admin
- `AccountRetroValidationBatch` (Google Places + OSM).
- `HistoricalVisitTotImportService` for Excel visits/TOT.
- `Service_Request_Type__c` + `ServiceRequestTypeService`.
- Planner rules cascade (User → Title → Profile → Line → Org).

## Gap fixes (22 Oct evening) — deploy `0Afiv0000005PDtCAM`
- `AccountRetroValidationBatch` now persists Maps enrichment (was count-only).
- `OutOfTargetQueueService` only queues DM-validated visits; `OutOfTargetQueueSchedulable` for EOM.
- Planner Rules Admin: Title + Profile scopes; cascade User→Title→Profile→Line→Org.
- New Admin tiles: **Sales Policy**, **Service Request Types**, **Target Governance**.
- `ServiceRequestTypeService.listAllTypes` for admin; `TargetGovernanceService.saveOrgRule`.
- Smoke: `GapFixOct22SmokeTest` (7 tests with DryRun + PlannerRules).

### Fixed in repo, not yet in org (coverage size on large classes)
- `FieldRequestService` → uses `ServiceRequestTypeService` for create types.
- `ClassEngineController` → rep-only potential/penetration gate.
- `TerritoryManagementController` → multi-value `Mirror_Line__c` (CHC→CHC_Sales→CVM).
- Distributors Management **Registry** tab (needs `PharmacyProximityShareService` co-deploy).

## Still blocked on Zeta
- Post-June sales file, KPI PPT numbers, HCO/HCP target lists before wipe, Group Brand Lead names for five BMs, Doaa vs Odoo, Visita credentials if required.
- Pharmacy chain / monthly price CRUD UI and achievement digests still need labeled examples from Zeta.
- Historical TOT Excel mapper remains stub until Diabetes/Neuro files arrive.
