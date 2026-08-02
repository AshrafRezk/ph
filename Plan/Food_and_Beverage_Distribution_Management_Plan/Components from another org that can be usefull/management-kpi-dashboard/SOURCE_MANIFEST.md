# SOURCE_MANIFEST — management-kpi-dashboard

## Purpose
Management home: team KPI dashboard, pharmacy/sales analytics pattern.

## Original pharma paths

| File | Source |
|------|--------|
| lwc/managementTeamKpiDashboard | `force-app/main/default/lwc/managementTeamKpiDashboard/` |
| lwc/pharmacySalesDashboard | `force-app/main/default/lwc/pharmacySalesDashboard/` |
| classes/ManagementKpiController.cls | `force-app/main/default/classes/ManagementKpiController.cls` |
| flexipages/Management_Home.flexipage-meta.xml | `force-app/main/default/flexipages/` |
| tabs/Management_Home.tab-meta.xml | `force-app/main/default/tabs/` |

## Everbrook adaptations

1. Rename `pharmacySalesDashboard` → `fbVanSalesDashboard`
2. Data source: `Sales_Order__c` instead of pharmacy withdrawals
3. KPI tiles per KPI_SCORING_MODEL.md (70% sales capped + 30% coverage)
4. Filters: today/yesterday/week, distributor, SKU
5. Remove pharma-specific territory/CLM drill-downs

## MVP usage
Deploy with fleet module for backoffice home tab.
