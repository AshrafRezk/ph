# SOURCE_MANIFEST — management-fleet-tracking

## Purpose
Live fleet map: rep locations, today's visit routes, online/stale/offline status.

## Original pharma paths

| File | Source |
|------|--------|
| lwc/managementFleetMap | `force-app/main/default/lwc/managementFleetMap/` |
| lwc/repLocationPublisher | `force-app/main/default/lwc/repLocationPublisher/` |
| classes/ManagerFleetMapController.cls | `force-app/main/default/classes/ManagerFleetMapController.cls` |
| classes/RepLocationService.cls | `force-app/main/default/classes/RepLocationService.cls` |
| objects/Rep_Location_Snapshot__c | `force-app/main/default/objects/Rep_Location_Snapshot__c/` |
| flexipages/Management_Field_Tracking.flexipage-meta.xml | `force-app/main/default/flexipages/` |
| tabs/Field_Tracking.tab-meta.xml | `force-app/main/default/tabs/` |

## Everbrook adaptations

1. **Critical:** `User__c` → `Contact__c` on Rep_Location_Snapshot__c
2. Add `Van__c`, `Distributor__c` fields on snapshot
3. Fleet map filter by Distributor Account (replace TerritoryHierarchyService for MVP)
4. VF field site publishes GPS via Apex REST instead of `repLocationPublisher` LWC
5. Van icon on map pins

## MVP deploy
First backoffice component to deploy — see `mvp-stubs/manifests/mvp-backoffice-package.xml`
