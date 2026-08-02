# Business Requirements Document (BRD)

**Project:** Everbrook / VAMOS BY Mahou — Food & Beverage Distribution Management  
**Status:** Planning package  
**Last updated:** July 2026

---

## Document purpose

Defines business requirements for three Salesforce application modules. Each implementation has an ID, module assignment, and acceptance criteria.

**Related documents:**

- [DEVELOPER_QUICKSTART.md](./DEVELOPER_QUICKSTART.md)
- [KPI_SCORING_MODEL.md](./KPI_SCORING_MODEL.md)
- [general-rules.md](./general-rules.md)
- Wireframes: [wireframes-and-references/](./wireframes-and-references/)

---

## Implementation index

| ID | Module | Implementation | Priority |
|----|--------|----------------|----------|
| IMP-FB-001 | Field Rep | Targets (Arabic/English) | High |
| IMP-FB-002 | Field Rep | Route Viewing (OpenMaps) | High |
| IMP-FB-003 | Field Rep | Planner (add/remove/optimize) | High |
| IMP-FB-004 | Field Rep | GPS Tracking + deviation | High |
| IMP-FB-005 | Field Rep | Visit Management | High |
| IMP-FB-006 | Field Rep | Order Management (VAMOS SKUs) | High |
| IMP-FB-007 | Field Rep | Case Logging | Medium |
| IMP-FB-008 | Backoffice | Target Setting | High |
| IMP-FB-009 | Backoffice | GPS View of All Vans | High |
| IMP-FB-010 | Backoffice | Reports and Dashboards | High |
| IMP-FB-011 | Distributor | Commerce | High |
| IMP-FB-012 | Distributor | Expenses and Inventory Logging | Medium |
| IMP-FB-013 | Distributor | ROI Visibility | Medium |
| IMP-FB-014 | Cross-cutting | Arabic i18n + RTL | High |
| IMP-FB-015 | Cross-cutting | Distributor data isolation | High |
| IMP-FB-016 | Cross-cutting | ERP integration | Low (future) |

---

## IMP-FB-001: Targets (Arabic/English)

### Business context

Reps must see personal performance vs targets using the 70/30 KPI model (sales vs SKU target capped + coverage).

### Requirements

| # | Requirement |
|---|-------------|
| R1 | Display overall score, sales score (70%), coverage score (30%) on VF home |
| R2 | SKU-level breakdown for 4 VAMOS products |
| R3 | Arabic default; English toggle |
| R4 | Progress rings with color thresholds (red/amber/green) |

### Acceptance criteria

- [ ] Scores match KPI_SCORING_MODEL.md formulas
- [ ] Arabic RTL renders correctly on mobile

---

## IMP-FB-002: Route Viewing

### Requirements

| # | Requirement |
|---|-------------|
| R1 | Read-only map of today's stops on OpenStreetMap |
| R2 | Stop list with sequence, outlet, status |
| R3 | OSRM distance/ETA to next stop |

### Acceptance criteria

- [ ] Map loads < 3s on 4G
- [ ] Only rep's own route visible

---

## IMP-FB-003: Planner

### Requirements

| # | Requirement |
|---|-------------|
| R1 | Add outlet to today's route from territory search |
| R2 | Remove unvisited stop with mandatory reason |
| R3 | Reorder stops; optimize via OSRM |
| R4 | Weekly calendar view (adapt from pharma `fieldRepPlanner`) |

### Acceptance criteria

- [ ] Route changes persist to `Daily_Route_Stop__c`
- [ ] Removed stops retain audit reason

---

## IMP-FB-004: GPS Tracking

### Requirements

| # | Requirement |
|---|-------------|
| R1 | Publish location every 60s while route active |
| R2 | Deviation prompt when >500m off route >5 min |
| R3 | Mandatory deviation reason stored on `Route_Deviation__c` |

### Acceptance criteria

- [ ] Backoffice fleet map shows updated pin within 2 min

---

## IMP-FB-005: Visit Management

### Requirements

| # | Requirement |
|---|-------------|
| R1 | Check-in with GPS stamp |
| R2 | Outcome: Sale, No Sale, Return Only, Skipped |
| R3 | Mandatory no-sale reason for No Sale / Skipped |

### Acceptance criteria

- [ ] Cannot complete visit without reason when required

---

## IMP-FB-006: Order Management

### Requirements

| # | Requirement |
|---|-------------|
| R1 | Sell 4 VAMOS SKUs from van inventory |
| R2 | Enforce stock and credit hold |
| R3 | Mobile receipt in active language |
| R4 | Product returns with reason per line |

### Acceptance criteria

- [ ] Inventory decrements on submit
- [ ] Order linked to visit and distributor

---

## IMP-FB-007: Case Logging

### Requirements

| # | Requirement |
|---|-------------|
| R1 | Create Case from visit or standalone |
| R2 | Types: Delivery, Quality, Equipment, Complaint, Credit, Other |
| R3 | Visible to Everbrook and owning distributor |

---

## IMP-FB-008: Target Setting

### Requirements

| # | Requirement |
|---|-------------|
| R1 | Set targets by rep, distributor, region, SKU |
| R2 | Periods: weekly, monthly, quarterly |
| R3 | Bulk CSV import |
| R4 | Attainment visible on backoffice and field rep home |

---

## IMP-FB-009: GPS View of All Vans

### Requirements

| # | Requirement |
|---|-------------|
| R1 | All reps/vans on one map across distributors |
| R2 | Online/stale/offline status |
| R3 | Planned route polyline + click-through to rep detail |
| R4 | Filter by distributor, region, date |

### Technical approach

Adapt `managementFleetMap` LWC + `ManagerFleetMapController` — replace User with Contact.

---

## IMP-FB-010: Reports and Dashboards

### Requirements

| # | Requirement |
|---|-------------|
| R1 | Sales today/yesterday/week |
| R2 | Visit completion, no-sale reasons, strike rate |
| R3 | Distributor comparison |
| R4 | SKU performance for 4 VAMOS variants |

---

## IMP-FB-011: Commerce (Distributor)

### Requirements

| # | Requirement |
|---|-------------|
| R1 | Distributor sees orders from own reps only |
| R2 | Filter by date, rep, outlet, SKU |
| R3 | CSV export for ERP |

---

## IMP-FB-012: Expenses and Inventory Logging

### Requirements

| # | Requirement |
|---|-------------|
| R1 | Log expenses by category |
| R2 | Inventory receipts, load in/out, adjustments |
| R3 | Approval workflow |

---

## IMP-FB-013: ROI Visibility

### Requirements

| # | Requirement |
|---|-------------|
| R1 | ROI = (Net Revenue - Expenses) / Expenses |
| R2 | Trend charts, SKU breakdown |
| R3 | Everbrook sees all; distributor sees own |

---

## IMP-FB-014: Arabic i18n + RTL

### Requirements

| # | Requirement |
|---|-------------|
| R1 | Custom Labels for all field UI strings |
| R2 | RTL layout when Arabic selected |
| R3 | Arabic picklist values |

---

## IMP-FB-015: Distributor data isolation

### Requirements

| # | Requirement |
|---|-------------|
| R1 | `Distributor__c` on all transactional objects |
| R2 | Sharing prevents cross-distributor access |
| R3 | Guest site scoped to session rep only |

---

## IMP-FB-016: ERP integration (future)

### Requirements

| # | Requirement |
|---|-------------|
| R1 | Export orders to ERP |
| R2 | Import stock receipts |
| R3 | Egypt e-invoicing compliance |

---

## Appendix A — Wireframes

| File | ID |
|------|-----|
| vamos-everbrook-overview.png | WF-FB-001 |
| everbrook-egypt-distribution.png | WF-FB-002 |
| kpi-weighting-model.png | WF-FB-003 |
