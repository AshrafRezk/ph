# SOURCE_MANIFEST — field-rep-home

## Purpose
Field rep home dashboard: KPI metrics, today's plan map, next best customer.

## Original pharma paths

| File | Source |
|------|--------|
| lwc/fieldRepHomeTodayPlan | `force-app/main/default/lwc/fieldRepHomeTodayPlan/` |
| lwc/fieldRepHomeMetrics | `force-app/main/default/lwc/fieldRepHomeMetrics/` |
| lwc/fieldRepHomeNextBestCustomer | `force-app/main/default/lwc/fieldRepHomeNextBestCustomer/` |
| lwc/fieldRepHomeClmPrefetch | `force-app/main/default/lwc/fieldRepHomeClmPrefetch/` (skip CLM for F&B) |
| classes/FieldRepHomeController.cls | `force-app/main/default/classes/FieldRepHomeController.cls` |
| flexipages/Field_Rep_Home*.xml | `force-app/main/default/flexipages/` |
| field_rep_home_module_config.yaml | `Plan/field_rep_home_module_config.yaml` |

## Everbrook adaptations

1. Replace User-scoped SOQL with `Contact__c` where applicable
2. Swap HCP coverage metrics for van sales KPIs (see KPI_SCORING_MODEL.md)
3. Remove or hide `fieldRepHomeClmPrefetch` — not needed for VAMOS
4. Port `fieldRepHomeTodayPlan` map JS to VF static resources for guest site
5. Use `Daily_Route__c` instead of pharma visit/time-card model

## MVP usage
- **Backoffice:** optional if managers use Lightning only
- **Field Rep VF:** port today-plan map pattern to `FieldSalesHome.page`
