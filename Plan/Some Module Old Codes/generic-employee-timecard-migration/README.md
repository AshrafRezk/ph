# Generic Employee Time Card Migration Package

Self-contained Salesforce metadata for migrating the **Employee Time Card** working-days module and a **generic walk-in pace dashboard** to a non-IDH org.

## Contents

### Working days module
- Custom objects: `Employee_Time_Card__c`, `Employee_Time_Card_Day_Entry__c`
- Supporting objects: `Visit__c`, `Time_Off_Request__c`, `Weekend_Definition__c`
- Flows: monthly card creation, activity counts, TOT update
- Report type and **Working Days Analysis** report
- MASS scheduler metadata for monthly automation
- Apex helpers: `EmployeeTimeCardFlowHelper`, day-definition and activity-count batches, TOT recalc

### Pace dashboard (walk-in only)
- LWC: `employeePaceDashboard` (revenue + visits targets vs achievement)
- Apex: `EmployeeTimeCardPaceService`, `EmployeeTimeCardPaceController`, team query, CSV export
- `EmployeeTimeCardAchievementService` + record-triggered flow for achievement %
- Permission sets: `Employee_Time_Card_Module`, `Employee_Pace_Dashboard`

### Excluded (IDH-specific)
- Al Mokhtabar / Al Borg / Borg Scan fields and branding
- `AssignedUserTargetRevenue__c` and commission/scoring stack
- Target planning LWCs and admin consoles

## Deploy

```bash
cd generic-employee-timecard-migration
sf project deploy start --manifest manifest/package.xml
```

**Note:** MASS scheduler OAuth policies (`extlClntAppOauth*`) are not included because they are org-specific. After deploy, complete OAuth wiring for `Mass_Action_Scheduler` in the target org, or schedule the monthly flows via another tool.

**Note:** Validate/deploy against an org that already has a different `Employee_Time_Card_Day_Entry__c` relationship may fail on the custom report type. Use a fresh scratch org or align the lookup field before deploying reports.

## Post-deploy checklist

1. Review `docs/config/employee_time_card_module_config.yaml` and adapt activity object field mappings if your target org differs from `Visit__c`.
2. Activate flows if not already active after deploy.
3. Configure **Mass Action Scheduler** for monthly `Employee_time_tracking_Monthly_Time_Card_Creation` and `Employee_time_tracking_Activity_Counts`.
4. Assign permission sets:
   - `Employee_Time_Card_Module` — all users who need time cards and reports
   - `Employee_Pace_Dashboard` — managers who need team pace view and CSV export
5. Add **Employee Pace Dashboard** LWC to a Home page, App page, or Tab.
6. Define how `Walk_in_Revenue__c` and `Walk_in_Visits__c` actuals are populated in the target org (integration, manual entry, or rollup). Targets can be set directly on `Employee_Time_Card__c`.
7. Run **Working Days Analysis** report and confirm totals match day-entry data.
8. Seed a test time card with walk-in targets/actuals; confirm achievement % and pace UI.

## Walk-in achievement

`Employee_Time_Card_Recalculate_Walk_in_Achievements` flow calls `EmployeeTimeCardAchievementService` when walk-in actuals or targets change:

- `Walk_in_Revenue_Ach__c = (Walk_in_Revenue__c / Walk_in_Revenue_Target__c) * 100`
- `Walk_in_Visits_Ach__c = (Walk_in_Visits__c / Walk_in_Visits_Target__c) * 100`

## Documentation

- [Migration Guide](docs/Employee_Time_Card_Working_Days_Migration_Guide.md)
- [Concept](docs/Employee_Time_Card_Working_Days_Concept.md)
- [Adaptation config](docs/config/employee_time_card_module_config.yaml)
