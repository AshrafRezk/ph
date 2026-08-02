# Distributor Portal Requirements — Module 3

**Platform:** Lightning app or Experience Cloud site  
**Audience:** Distribution partner companies (e.g. **Juhayna**, Vamos owned distribution)  
**Scope:** Each distributor sees **only their own** reps, orders, inventory, expenses, ROI

---

## Business context

Field reps are Contacts linked to `Employer_Distributor__c`. Distributor staff are Salesforce Users with Account linkage to their distributor record. During migration from Juhayna-only to multi/owned distribution, this portal gives partners visibility while Everbrook retains global oversight in Module 2.

---

## Sub-modules

### 1. Commerce (IMP-FB-011)

| ID | Requirement |
|----|-------------|
| R-COMMERCE-01 | Orders from own reps only |
| R-COMMERCE-02 | Detail: outlet, rep, SKU lines, amounts, visit |
| R-COMMERCE-03 | Filter: date, rep, outlet, SKU |
| R-COMMERCE-04 | CSV export for ERP |
| R-COMMERCE-05 | Credit hold visible on orders |

**UI tabs:** Commerce list, order detail, outlet history

---

### 2. Expenses and Inventory Logging (IMP-FB-012)

| ID | Requirement |
|----|-------------|
| R-DIST-OPS-01 | Expense categories: Fuel, Maintenance, Warehousing, Labor, Marketing, Other |
| R-DIST-OPS-02 | Receipt attachment |
| R-DIST-OPS-03 | Inventory log: Receipt, Load_Out, Load_In, Adjustment, Write_Off |
| R-DIST-OPS-04 | Van inventory reconciliation |
| R-DIST-OPS-05 | Approval: distributor manager → optional Everbrook review |

**Objects:** `Distributor_Expense__c`, `Distributor_Inventory_Log__c`

---

### 3. ROI Visibility (IMP-FB-013)

| ID | Requirement |
|----|-------------|
| R-ROI-01 | ROI = (Net Revenue - Total Expenses) / Total Expenses × 100 |
| R-ROI-02 | Breakdown by SKU, rep, region, period |
| R-ROI-03 | Compare vs target/benchmark |
| R-ROI-04 | Monthly trend (12 months) |
| R-ROI-05 | Everbrook sees all; distributor sees own only |

**Optional object:** `Distributor_ROI_Snapshot__c` for nightly batch

---

## Portal tabs

| Tab | Purpose |
|-----|---------|
| Home | KPI summary, ROI snapshot, alerts |
| My Reps | Contacts where `Employer_Distributor__c` = my account |
| Commerce | Orders and returns |
| Inventory | Warehouse + van stock |
| Expenses | Expense log |
| ROI Dashboard | Charts |
| Cases | Cases from own reps |

---

## Security / data isolation (IMP-FB-015)

| Rule | Implementation |
|------|----------------|
| Distributor user | `User.Contact.AccountId` or custom `Distributor_Account__c` on User |
| SOQL filter | `WHERE Distributor__c = :myDistributorId` |
| Sharing | Criteria-based rules on `Sales_Order__c`, `Visit__c`, etc. |
| Field rep | Session scoped — cannot access portal |

---

## User stories

- As Juhayna manager, I see all orders my reps placed today.
- As distributor ops, I log fuel expenses and attach receipts.
- As distributor finance, I view ROI dashboard for last quarter.
- As distributor supervisor, I see my reps' visit completion and strike rates.

---

## MVP vs full

| Feature | MVP | Full |
|---------|-----|------|
| Commerce read-only | Yes | — |
| Order export CSV | Yes | — |
| Expense logging | — | Yes |
| ROI dashboard | Stub | Yes |
| Experience Cloud | — | Optional |

---

## Acceptance criteria

- [ ] Juhayna user cannot see another distributor's orders
- [ ] ROI matches manual calculation for test period
- [ ] Expense approval workflow notifies Everbrook when configured
