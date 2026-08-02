# SOURCE_MANIFEST — accounts-tab

## Purpose
Territory account list with map, search, and filters.

## Original pharma paths

| File | Source |
|------|--------|
| lwc/accountsTab | `force-app/main/default/lwc/accountsTab/` |
| classes/AccountsTabController.cls | `force-app/main/default/classes/AccountsTabController.cls` |

## Everbrook adaptations

1. Accounts = Outlets (Outlet record type)
2. Filter by rep territory or distributor assignment
3. Use for planner sidebar outlet search
4. Optional backoffice outlet management tab

## MVP
Phase 2 — planner outlet search can use simpler SOQL in FieldSalesPlanner controller.
