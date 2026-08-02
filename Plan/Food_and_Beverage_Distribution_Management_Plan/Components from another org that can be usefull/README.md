# Components from Pharmaceuticals Org

Reference snapshots copied from `force-app/main/default/` in the **Pharmaceuticals** Salesforce project.  
**Do not deploy as-is** — follow [mvp-stubs/RENAME_MAP.md](../mvp-stubs/RENAME_MAP.md) and each folder's `SOURCE_MANIFEST.md`.

---

## Folder index

| Folder | Use in Everbrook | Module |
|--------|------------------|--------|
| [field-rep-home](./field-rep-home/) | Rep home, today plan, KPI metrics | Field Rep / Backoffice |
| [field-planner](./field-planner/) | Weekly planner, route edit | Field Rep |
| [management-fleet-tracking](./management-fleet-tracking/) | Fleet map, GPS publisher | Backoffice |
| [management-kpi-dashboard](./management-kpi-dashboard/) | Team KPIs, sales dashboard | Backoffice |
| [map-stack](./map-stack/) | OSM + OSRM utilities | All map features |
| [public-vf-site-pattern](./public-vf-site-pattern/) | Mobile VF guest site shell | Field Rep VF |
| [accounts-tab](./accounts-tab/) | Outlet list + map | Field Rep / Backoffice |
| [visit-management](./visit-management/) | Visit call shell patterns | Field Rep |

---

## Quick copy to SFDX project

```bash
# Example: copy fleet LWC into target project
cp -R "field-planner/lwc/fieldRepPlanner" /path/to/everbrook/force-app/main/default/lwc/fbFieldRepPlanner
```

Then apply renames per RENAME_MAP.md.

---

## Also copy from pharma (not in this folder)

| Asset | Pharma path |
|-------|-------------|
| leaflet static resource | `force-app/main/default/staticresources/leaflet` |
| TerritoryHierarchyService | Optional — replace with Distributor filter for MVP |

---

## Module config cross-reference

See [module-configs/](../module-configs/) for YAML deploy sequences per module.
