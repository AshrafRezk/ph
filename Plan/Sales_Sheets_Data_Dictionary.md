# Sales sheets data dictionary (Notion #33 / chat #38)

For Ahmed Abdallah sign-off. Source files under `Zeta Provided Data/Sales Data/`. Spec: `reference/Automated Sales Calculations SOP 2025.docx`. Acceptance reference: `CRM Sales reference June.xlsx`.

## What counts as sales
Only customer-level invoice / return / tender rows. **Exclude:** bonus quantities, internal transfers, stock, purchasing, and summary/total sheets (use totals only to reconcile).

## EgyDrug (8 sheets in one workbook)
| Sheet | Counts as sales? | Notes |
|-------|------------------|-------|
| Branches Sales | Yes | Branch → customer (pharmacy / private hospital). Exclude status بونص بيع (bonus). |
| Pharmacy Sales | Yes | EgyDrug's ~81 retail pharmacies → consumer. Assign by pharmacy location. |
| Branch Sales Return | Yes (negative) | Customer returns. |
| Transfer / Transfer Return | **No** | Branch → own pharmacies; would double-count Pharmacy Sales. |
| Monthly Stocks | No | Inventory. |
| Total Monthly Entity Item Trans | No | Reconciliation only. |
| Total Monthly Item Transaction | No | Per-item totals incl. tender; reconciliation. |

Weekly file: same logic with "Total Daily …" sheets.

## IBNSINA
- **Sales by client:** Yes. Exclude Free Unit (bonus). Brick is IBNSINA numeric code → map to 702 bricks.
- **Tender (TN):** Yes, flag IsTender / IsUPA.
- **Weekly:** part of month. **Daily stock:** not sales.

## Pharma Overseas (POS)
- **Customer sales:** Yes. Credit notes = returns; offer invoices = IsOffer. Exclude B. Qty bonus.
- **Tender sales:** Yes (hospital deliveries/returns).
- **Purchasing / stock:** No.

## Sofico
- **Sales CUST:** Yes. Use IQVIA brick code. Exclude BOUNSQTY. Map customer groups → MainType/SubType.
- **Stock:** No.

## Elezaby
- Sales-out by branch: Yes. Geographic by branch. If month missing → SOP cumulative average per branch.

## EPDA (Ebda)
- Only the tabular customer-sales `.xlsx` in the zip: Yes.
- Crystal reports / empty stub: No.

## Direct / subagents
- Appear in Solution Max output (Direct_Zeta_Pharma, Yodawy, etc.). No June sample file in the pack — need from Zeta.

## Reference files (not monthly sales)
- **Zeta Product Mapping:** 186 products + 859 distributor item codes.
- **Chains Distributor Codes:** 22 chains × distributor customer codes.
- **Items Ceiling Roles 2026:** 155 ceilings by item × subtype (SubAgent / Stores / Private).
- **ZETA TOTAL TARGET 2026:** Original + Buffer, position × item, annual qty + monthly phasing.

## Engine routing (SOP)
1. Geographic: street / direct / accounts / stores under ceiling / Ezzaby branches → brick → territory → position.
2. Fixed %: chains (except Ezzaby) → bricks per line.
3. Bulk pool: stores above ceiling + blacklisted + subagents (confirm vs chat: retail above ceiling) → variable monthly %.

## Open decisions for Ahmed
1. Bulk definition: all subagent sales, or only above SubAgent ceiling?
2. Exact bulk variable-% formula (image in SOP).
3. Will UCP monthly files be provided?
4. Confirm this dictionary matches how Solution Max treated June.
