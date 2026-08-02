# SOURCE_MANIFEST — field-planner

## Purpose
Weekly calendar planner: drag accounts to create visits, map route, OSRM optimization.

## Original pharma paths

| File | Source |
|------|--------|
| lwc/fieldRepPlanner | `force-app/main/default/lwc/fieldRepPlanner/` |
| lwc/plannerAccountCollections | `force-app/main/default/lwc/plannerAccountCollections/` |
| classes/FieldPlannerController.cls | `force-app/main/default/classes/FieldPlannerController.cls` |
| flexipages/Field_Rep_Planner.flexipage-meta.xml | `force-app/main/default/flexipages/` |
| tabs/Field_Rep_Planner.tab-meta.xml | `force-app/main/default/tabs/` |
| field_planner_module_config.yaml | `Plan/field_planner_module_config.yaml` |

## Everbrook adaptations

1. Account sidebar = Outlets in rep territory (not HCPs)
2. Visit create → `Visit__c` + `Daily_Route_Stop__c`
3. Add/remove stop with reason → `Daily_Route_Stop__c.Removal_Reason__c`
4. Port planner map to VF `FieldSalesPlanner.page` for Contact-based reps
5. Manager read-only view: filter by `Distributor__c`

## Dependencies
- map-stack (plannerMapUtils, plannerMapPins)
- leaflet static resource
- CSP trusted sites
