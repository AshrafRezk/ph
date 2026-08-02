# Pharmacy Sales CSV Import — Data Loader Mapping

Use this mapping when loading `Pharmacy_Sales_Withdrawal__c` records via Admin Console CSV import or Salesforce Data Loader.

## CSV columns

| CSV column | Salesforce field | Object | Required | Notes |
|------------|------------------|--------|----------|-------|
| `data_source` | `Data_Source__c` | Pharmacy_Sales_Withdrawal__c | Yes | `IbnSina` or `Pharmaoverseas` |
| `report_month` | `Report_Month__c` | Pharmacy_Sales_Withdrawal__c | Yes | `YYYY-MM` or `YYYY-MM-01` (first day of month) |
| `pharmacy_external_id` | Lookup via `Account.External_ID__c` | Account (Pharmacy RT) | Yes | Must exist before import |
| `product_external_id` | Resolved to `Product2_Id__c` | Product2 | Yes | Uses `Product2.External_ID__c` |
| `quantity_withdrawn` | `Quantity_Withdrawn__c` | Pharmacy_Sales_Withdrawal__c | Yes | Positive number |
| `unit_price` | `Unit_Price__c` | Pharmacy_Sales_Withdrawal__c | No | Defaults to Standard Price Book entry |
| `external_id` | `External_ID__c` | Pharmacy_Sales_Withdrawal__c | No | Optional idempotent row key |

## Upsert keys

- Primary upsert during Admin import: `Unique_Key__c` (auto-composed as `{Data_Source}_{YYYY-MM}_{PharmacyId}_{Product2Id}`)
- Optional row upsert: `External_ID__c`

## Brick assignment

`Brick__c` on withdrawal rows is populated automatically from active `Brick_Pharmacy__c` membership for the pharmacy account.

## Example row

```csv
data_source,report_month,pharmacy_external_id,product_external_id,quantity_withdrawn,unit_price,external_id
IbnSina,2026-01,PHARM_EL_EZABY_MAADI,ZETA_EMPACOZA_10MG,120,180,
Pharmaoverseas,2026-02,PHARM_SEIF,ZETA_DOZOVA_NAD_300,80,320,
```

## Demo seed

Run in Anonymous Apex after deploying metadata:

```apex
PharmacySalesDataSeed.seedDemoData();
```

Or use **Seed Demo Data** in Admin Console → Sales Data.
