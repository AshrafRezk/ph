# SalesBuzz Feature Mapping

Industry reference mapping — **do not deploy "SalesBuzz" branding** in org metadata.

| SalesBuzz concept | Everbrook module | Implementation | Phase |
|-------------------|------------------|----------------|-------|
| Van sales + mobile invoicing | Field Rep | VF Order + `Sales_Order__c` | 1 |
| Stock management in van | Field Rep + Distributor | `Van_Inventory__c` + inventory log | 1 |
| Route planning + optimization | Field Rep | OSRM + `Daily_Route__c` | 1 |
| GPS tracking | Field Rep → Backoffice | `Rep_Location_Snapshot__c` | 1 |
| Planned vs actual route | Backoffice | Fleet map + `Route_Deviation__c` | 1 |
| Unsuccessful visit reasons | Field Rep | `No_Sale_Reason__c` | 1 |
| Returns | Field Rep | `Product_Return__c` | 1 |
| Target setting / attainment | Field Rep + Backoffice | `Rep_Target__c` + KPI model | 1 |
| Case / issue logging | Field Rep | Standard Case | 1 |
| Supervisor fleet view | Backoffice | `managementFleetMap` | 1 |
| Distributor commerce | Distributor | Order portal | 1 |
| Distributor expenses + ROI | Distributor | Expense + ROI objects | 2 |
| Arabic language | All | Custom Labels + RTL | 1 |
| Promotions / pricing | Field Rep | Price book rules | 2 |
| ERP sync | Cross-cutting | Integration API | 2 |
| Offline mode | Field Rep | Service worker | 3 |

---

## Pharma component equivalents

| SalesBuzz-like capability | Pharma source | Everbrook adaptation |
|---------------------------|---------------|----------------------|
| Daily plan + map | `fieldRepHomeTodayPlan` | VF home + route pages |
| Calendar planner | `fieldRepPlanner` | VF planner + backoffice read-only |
| Call reporting | `visitCallShell` | VF visit page |
| Manager GPS map | `managementFleetMap` | Backoffice fleet tab |
| Team KPIs | `managementTeamKpiDashboard` | Backoffice home |
| Sell-out analytics | `pharmacySalesDashboard` | Van sales dashboard |
| Public mobile VF | `ProductSurvey.page` | Field sales login shell |
| Sample drops | `visitSampleGrid` | N/A — use order lines instead |

---

## Everbrook differentiators

- **Contact-based rep login** (no User license for field)
- **Multi-distributor** model (Juhayna + owned + future)
- **70/30 KPI** with capped SKU attainment
- **Arabic-first** field UX
