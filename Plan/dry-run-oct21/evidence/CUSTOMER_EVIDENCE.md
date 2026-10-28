# Zeta Pharma — Oct 21 dry-run customer evidence

**Org:** zetapharma.my.salesforce.com  
**Deploy:** `0Afiv0000005NiLCAU` — **Succeeded**  
**Apex tests:** **53 passed / 0 failed**

Open the shareable pack: [`CUSTOMER_EVIDENCE_PACK.html`](./CUSTOMER_EVIDENCE_PACK.html) (screenshots embedded).

| Item title | Item category | What’s needed | What’s done | Screenshot |
|---|---|---|---|---|
| Admin Console home | Platform / Admin | Single SFE admin surface | 25 modules live in Admin Console | `screenshots/evidence-01-admin-console-home.png` |
| Territory product lines | Users & Territories | Line inventory with brand/district/rep counts | Product Lines cards (CHC, CVM, DIAB, …) | `screenshots/evidence-02-territory-management.png` |
| Users filters | Users & Territories | Line / Territory / Title filters; full roster | Users tab filters + live seats | `screenshots/evidence-03-territory-users.png` |
| KPI Targets by role | KPI cascade | Editable role KPIs + working-day cascade | KPI Targets MSR/DSM + calculator deployed | `screenshots/evidence-04-kpi-targets.png` |
| Distributors / Direct | Direct distribution | Registry + Excel import + geocode | Import tab + SalesDistributorRegistry / SalesPolicyService | `screenshots/evidence-05-distributors.png` |
| Planner Rules | Planner | Egypt week + overlap Allow/Warn/Block | Sat–Wed working; Block/Warn matrix | `screenshots/evidence-06-planner-rules.png` |
| Class Engine | Target governance | Capacity; Valid-only unplanned visits | Q4-2026 capacity rings; metrics service deployed | `screenshots/evidence-07-class-engine.png` |

## Test classes that passed
See [`test-results.md`](./test-results.md).
