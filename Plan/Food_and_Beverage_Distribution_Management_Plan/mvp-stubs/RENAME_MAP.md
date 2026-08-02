# Field rename map — Pharma → Everbrook

Apply when copying components into the target org.

## Object / field renames

| Pharma | Everbrook |
|--------|-----------|
| `User__c` on Rep_Location_Snapshot | `Contact__c` |
| `Assigned_To__c` on Visit | `Contact__c` |
| `Employee_Time_Card__c` | `Daily_Route__c` (conceptual — different model) |
| HCP / Pharmacy Account RT | `Outlet` Account RT |
| — | `Distributor` Account RT (new) |
| `Visit__c` (pharma) | Reuse object; change fields/picklists for F&B |

## New fields to add

| Object | Field |
|--------|-------|
| Rep_Location_Snapshot__c | `Contact__c`, `Van__c`, `Distributor__c` |
| Visit__c | `Outcome__c`, `No_Sale_Reason__c`, `Distributor__c` |
| Sales_Order__c | `Distributor__c`, `Van__c` |
| Contact | `Mobile_Username__c`, `Mobile_Password_Hash__c`, `Employer_Distributor__c` |

## Apex class renames (suggested)

| Pharma | Everbrook |
|--------|-----------|
| ManagerFleetMapController | FbManagerFleetMapController |
| FieldPlannerController | FbFieldPlannerController |
| FieldRepHomeController | FbFieldRepHomeController |
| ManagementKpiController | FbManagementKpiController |
| ProductSurveyController | FbFieldSalesController (new logic) |

## LWC renames (optional)

| Pharma | Everbrook |
|--------|-----------|
| managementFleetMap | fbManagementFleetMap |
| fieldRepPlanner | fbFieldRepPlanner |
| pharmacySalesDashboard | fbVanSalesDashboard |

## Labels to replace in UI

| Remove | Replace with |
|--------|--------------|
| HCP | Outlet |
| Pharmacy | Outlet |
| Call / CLM | Visit / Order |
| Sample | Product |
| Medical Professional | Field Rep |

## Dependencies to deploy with fleet map

- `TerritoryHierarchyService` — replace with simple Distributor filter for MVP
- `leaflet` static resource — copy from pharma org
- CSP trusted sites for OSM + OSRM
