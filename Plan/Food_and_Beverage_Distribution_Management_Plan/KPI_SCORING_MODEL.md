# KPI Scoring Model — Field Rep Performance

Derived from wireframe: [kpi-weighting-model.png](./wireframes-and-references/kpi-weighting-model.png)

---

## Overall score formula

```
Overall_Performance_Score =
    (0.70 × Sales_Score) +
    (0.30 × Coverage_Score)
```

Both sub-scores are normalized to 0–100 before weighting.

---

## 70% — Total sales versus target per SKU (capped)

**Weight:** 70% of overall score

For each VAMOS SKU in the rep's target list:

```
SKU_Attainment = MIN(Actual_Sales_Qty / Target_Sales_Qty, Cap_Percent) × 100
```

| Rule | Detail |
|------|--------|
| **Cap** | Attainment is **capped** at 100% (or configurable cap, e.g. 110%) — over-achievement does not inflate score beyond cap |
| **Aggregation** | Average SKU attainments, or weighted by SKU target volume |
| **Period** | Monthly default; weekly for short cycles |
| **Data source** | `Sales_Order_Line__c` aggregated by Product2 + `Rep_Target__c` |

**Sales_Score** = average of capped SKU attainment percentages across all targeted SKUs.

### Salesforce implementation

| Field / object | Purpose |
|----------------|---------|
| `Rep_Target__c.Target_Type__c` | `SKU_Volume` |
| `Rep_Target__c.Product__c` | Lookup Product2 |
| `Rep_Target__c.Target_Quantity__c` | Target cases/units |
| `Rep_Target__c.Actual_Quantity__c` | Roll-up or formula from order lines |
| `Rep_Target__c.Capped_Attainment_Pct__c` | `MIN(Actual/Target, 1) * 100` |
| `Rep_Target__c.Attainment_Cap__c` | Default 100 |

---

## 30% — Coverage within the list

**Weight:** 30% of overall score

Split into three equal sub-metrics (10% each of overall, or 33.3% each of coverage bucket):

### 1. Coverage for active customers

```
Active_Customer_Coverage = (Visited_Active_Outlets / Total_Active_Outlets_In_List) × 100
```

- **Active outlet:** Account (Outlet RT) with purchase in last N days (e.g. 90) or on rep's assigned list
- **Visited:** At least one completed `Visit__c` in period with outcome ≠ Skipped

### 2. Go-to-market penetration priority list

```
GTM_Penetration = (Visited_Priority_Outlets / Total_Priority_Outlets) × 100
```

- **Priority list:** Accounts flagged `GTM_Priority__c = true` or on `Priority_Outlet_List__c`
- Measures penetration of strategic new accounts

### 3. Strike rate

```
Strike_Rate = (Visits_With_Sale / Total_Completed_Visits) × 100
```

- **Visit with sale:** `Visit__c.Outcome__c = Sale` or linked `Sales_Order__c` exists
- Excludes skipped visits from denominator (configurable)

**Coverage_Score** = average of the three sub-metrics above.

---

## Combined example

| Metric | Raw % | Weight | Contribution |
|--------|-------|--------|--------------|
| Sales (SKU capped) | 85 | 70% | 59.5 |
| Active customer coverage | 90 | 10% | 9.0 |
| GTM priority penetration | 60 | 10% | 6.0 |
| Strike rate | 75 | 10% | 7.5 |
| **Overall** | | | **82.0** |

---

## Where scores appear

| Module | Display |
|--------|---------|
| Field Rep VF Home | Progress rings for sales + coverage + overall |
| Backoffice dashboard | Team leaderboard, distributor comparison |
| Distributor portal | Rep performance for own reps only |
| Reports | `Rep_Performance_Snapshot__c` (optional nightly batch) |

---

## Arabic labels (Custom Labels)

| Key | English | Arabic |
|-----|---------|--------|
| `fb_kpi_sales` | Sales vs Target | المبيعات مقابل الهدف |
| `fb_kpi_coverage` | Coverage | التغطية |
| `fb_kpi_strike_rate` | Strike Rate | معدل النجاح |
| `fb_kpi_overall` | Overall Score | الأداء الإجمالي |
