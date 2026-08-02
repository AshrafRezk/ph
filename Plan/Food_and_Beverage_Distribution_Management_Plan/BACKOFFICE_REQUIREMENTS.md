# Backoffice Requirements — Module 2 (Everbrook Management)

**Platform:** Lightning Experience app  
**Audience:** Everbrook internal users (management, dispatch, sales ops, IT)

---

## Lightning app

| Setting | Value |
|---------|-------|
| App name | Everbrook Management |
| Form factors | Large, Medium |
| Primary color | VAMOS brand cyan (#00D4FF suggested) |

---

## Sub-modules

### 1. Target Setting (IMP-FB-008)

| ID | Requirement |
|----|-------------|
| R-TARGET-MGT-01 | Targets at rep, distributor, region, SKU level |
| R-TARGET-MGT-02 | Periods: weekly, monthly, quarterly |
| R-TARGET-MGT-03 | Types: revenue (EGP), visit count, order count, SKU volume |
| R-TARGET-MGT-04 | Bulk CSV import |
| R-TARGET-MGT-05 | Actuals from orders and visits |
| R-TARGET-MGT-06 | Attainment on dashboard + pushed to field rep |

**UI:** Tab "Target Management" — list view + upload + heatmap (adapt `managementTeamKpiDashboard`)

---

### 2. GPS View of All Vans (IMP-FB-009)

| ID | Requirement |
|----|-------------|
| R-FLEET-01 | All vans/reps on OpenStreetMap |
| R-FLEET-02 | Status: online (<2 min), stale (2–15 min), offline (>15 min) |
| R-FLEET-03 | Today's planned route polyline per rep |
| R-FLEET-04 | Filter: distributor, region, route date |
| R-FLEET-05 | Click rep → detail: visits, sales, deviations |
| R-FLEET-06 | Planned vs actual GPS trail comparison |

**Source components:** `management-fleet-tracking/` — adapt `User__c` → `Contact__c`, add `Distributor__c` filter

---

### 3. Reports and Dashboards (IMP-FB-010)

| ID | Requirement |
|----|-------------|
| R-RPT-01 | Sales: today, yesterday, week, month |
| R-RPT-02 | Visit completion rate |
| R-RPT-03 | No-sale reason breakdown |
| R-RPT-04 | Strike rate by rep/distributor |
| R-RPT-05 | SKU performance (4 VAMOS) |
| R-RPT-06 | Distributor comparison |
| R-RPT-07 | Export CSV |

**Source components:** `management-kpi-dashboard/` — adapt `pharmacySalesDashboard` → van sales dashboard

---

## App tabs

| Tab | Component / page |
|-----|------------------|
| Home | `managementTeamKpiDashboard` (adapted) |
| Fleet Tracking | `managementFleetMap` |
| Target Management | Custom LWC or standard list + import |
| Sales Performance | Van sales dashboard LWC |
| Visits | Visit__c list view |
| Distributors | Account list (Distributor RT) |
| Cases | Case list (field-logged) |
| Reports | Standard Reports folder |

---

## User stories

- As Everbrook management, I set monthly targets per distributor and rep.
- As Everbrook management, I see all vans from all distributors on one map.
- As Everbrook management, I compare planned vs actual routes for any rep/date.
- As Everbrook management, I run sales and visit reports by distributor.
- As Everbrook management, I see which distributors meet ROI expectations.

---

## Permission sets

| Permission set | Audience |
|----------------|----------|
| `Everbrook_Management_App` | App access |
| `Everbrook_Fleet_Module` | Fleet map |
| `Everbrook_Target_Admin` | Target CRUD + import |
| `Everbrook_Reports` | Dashboards and reports |

---

## KPI display

Backoffice home shows team rollup of [KPI_SCORING_MODEL.md](./KPI_SCORING_MODEL.md):
- 70% sales vs SKU target (capped)
- 30% coverage (active customers + GTM priority + strike rate)

---

## Acceptance criteria

- [ ] Fleet map loads all distributors in < 5s
- [ ] Target import processes 500 rows without error
- [ ] Reports respect Everbrook view-all access
- [ ] No pharma-specific labels (HCP, CLM) in deployed metadata
