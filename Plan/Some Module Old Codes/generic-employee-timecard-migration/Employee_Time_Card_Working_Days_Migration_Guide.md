# Employee Time Card Working Days Migration Guide

This guide migrates the Employee Time Card + Working Days Analysis module to a new org without rebuilding from scratch.

Baseline package:
- `manifest/package-timecard-migration.xml`

Adaptation config:
- `docs/config/employee_time_card_module_config.yaml`

## 1) Migration model

1. Deploy the baseline SFDX package.
2. Let Cursor ask adaptation questions from the YAML file.
3. Apply mapping updates for source activity object, MASS source, and calendar logic.
4. Activate flows and validate report outputs.

## 2) Metadata inventory (module scope)

### Reports and report type
- Report type:
  - `force-app/main/default/reportTypes/Employee_Time_Card_Day_Entries_with_Time_Card.reportType-meta.xml`
- Reports:
  - `force-app/main/default/reports/WorkingDaysAnalysis/Working_Days_Analysis_Czl.report-meta.xml`
  - `force-app/main/default/reports/Visits/Working_Days_Analysis_Czl.report-meta.xml`
- Report folders:
  - `force-app/main/default/reports/WorkingDaysAnalysis.reportFolder-meta.xml`
  - `force-app/main/default/reports/Visits.reportFolder-meta.xml`

### Flows filling time card data
- `force-app/main/default/flows/Employee_time_tracking_Monthly_Time_Card_Creation.flow-meta.xml`
  - Creates monthly `Employee_Time_Card__c`
  - Creates `Employee_Time_Card_Day_Entry__c` records for each day
  - Uses `Weekend_Definition__c` for weekend identification
- `force-app/main/default/flows/Employee_time_tracking_Activity_Counts.flow-meta.xml`
  - Reads `Visit__c` and `Time_Off_Request__c`
  - Updates daily planned/unplanned AM/PM/coaching counts
- `force-app/main/default/flows/Time_Off_Request_Update_Time_Card_TOT.flow-meta.xml`
  - Supports TOT-related synchronization

### Core objects
- `force-app/main/default/objects/Employee_Time_Card__c/Employee_Time_Card__c.object-meta.xml`
- `force-app/main/default/objects/Employee_Time_Card_Day_Entry__c/Employee_Time_Card_Day_Entry__c.object-meta.xml`
- Source/supporting objects used by flow logic:
  - `force-app/main/default/objects/Visit__c/Visit__c.object-meta.xml`
  - `force-app/main/default/objects/Time_Off_Request__c/Time_Off_Request__c.object-meta.xml`
  - `force-app/main/default/objects/Weekend_Definition__c/Weekend_Definition__c.object-meta.xml`
  - Standard `Holiday` object

### All fields: Employee_Time_Card__c
- `Company_Name__c`
- `Unique_Identifier__c`
- `Time_Card_Month_Start_Date__c`
- `Employee__c`
- `Time_Card_Month_End_Date__c`
- `Target_Daily_Visits__c`
- `Territory__c`
- `Employee_Profile__c`
- `Employee_isactive__c`
- `Employee_Manager__c`
- `Active_Time_Card__c`
- `Country_Team_Territory_Employee__c`
- `Company__c`

### All fields: Employee_Time_Card_Day_Entry__c
- `Time_off_Days__c`
- `Unplanned_PM_Visits__c`
- `TOT_Days_Excluding_Weekends__c`
- `TOT_Days__c`
- `Unplanned_Coaching_Visits__c`
- `Planned_Coaching_Visits__c`
- `Total_Visits__c`
- `Unplanned_AM_Visits__c`
- `Employee_Time_Card__c`
- `Date__c`
- `Planned_PM_Visits__c`
- `Day_Definition__c`
- `Days_with_Activities__c`
- `Planned_AM_Visits__c`
- `Calendar_Working_Days__c`
- `Holiday_Days__c`
- `Completed_Meetings__c`
- `Coaching_Visits_Count__c`
- `PM_Visits__c`
- `AM_Visits__c`
- `Unplanned_Visits__c`
- `Planned_Visits__c`
- `Submitted_Calls__c`
- `No_Activity_Days__c`

### Layouts
- `force-app/main/default/layouts/Employee_Time_Card__c-Employee Time Card Layout.layout-meta.xml`
- `force-app/main/default/layouts/Employee_Time_Card_Day_Entry__c-Employee Time Card Day Entry Layout.layout-meta.xml`

### Tabs / app context
- There are no dedicated tabs for `Employee_Time_Card__c` or `Employee_Time_Card_Day_Entry__c` in `force-app/main/default/tabs`.
- Existing related tab:
  - `force-app/main/default/tabs/Visit__c.tab-meta.xml`

### Mass Action Scheduler components
- `force-app/main/default/externalClientApps/Mass_Action_Scheduler.eca-meta.xml`
- `force-app/main/default/extlClntAppPolicies/Mass_Action_Scheduler_plcy.ecaPlcy-meta.xml`
- `force-app/main/default/extlClntAppGlobalOauthSets/Mass_Action_Scheduler_glbloauth.ecaGlblOauth-meta.xml`
- `force-app/main/default/extlClntAppOauthPolicies/Mass_Action_Scheduler_oauthPlcy.ecaOauthPlcy-meta.xml`
- `force-app/main/default/extlClntAppOauthSettings/Mass_Action_Scheduler_oauth.ecaOauth-meta.xml`
- `force-app/main/default/authproviders/Mass_Action.authprovider-meta.xml`
- `force-app/main/default/namedCredentials/Mass_Action.namedCredential-meta.xml`
- `force-app/main/default/oauthcustomscopes/Mass_Action.oauthcustomscope-meta.xml`

### Permission sets (relevant in current org)
- `force-app/main/default/permissionsets/Sales_Rep_IDH.permissionset-meta.xml`
- `force-app/main/default/permissionsets/Sales_Rep_Al_Borg.permissionset-meta.xml`
- `force-app/main/default/permissionsets/Sales_Rep_Al_Borg_Scan.permissionset-meta.xml`
- `force-app/main/default/permissionsets/Sales_Rep_Al_Mokhtabar.permissionset-meta.xml`
- `force-app/main/default/permissionsets/Territory_Account_Manager.permissionset-meta.xml`

Note:
- No dedicated permission set for `Employee_Time_Card__c` and `Employee_Time_Card_Day_Entry__c` was found in `force-app/main/default/permissionsets`.
- These objects appear in profile metadata. In target org, create or assign a dedicated permission set if needed.

## 3) Deploy baseline package

Deploy:

```bash
sf project deploy start --manifest manifest/package-timecard-migration.xml --target-org <alias>
```

Validate deployment:

```bash
sf project deploy report --target-org <alias> --use-most-recent
```

## 4) Cursor-guided adaptation workflow

Before activating flows, Cursor should ask and record answers to the questionnaire in:
- `docs/config/employee_time_card_module_config.yaml` under `cursor_adaptation_questionnaire`

Required questions:
1. Activity source object API name
2. Activity date/datetime field
3. Employee assignment field
4. Completed status field/value
5. Planned vs unplanned logic
6. AM/PM mapping logic
7. Coaching logic fields
8. Weekend definition source
9. Holiday source
10. MASS record source criteria
11. Report folder override decision

Apply answers into:
- `activity_source_object_mapping`
- `calendar_mapping`
- `mass_action.record_source`
- `reports.folder_mapping`

## 5) MASS activation sequence

1. Configure MASS record source (recommended: `User` with active-user filter).
2. Create action for flow `Employee_time_tracking_Monthly_Time_Card_Creation`.
3. Create action for flow `Employee_time_tracking_Activity_Counts`.
4. Schedule the second run after the first run completes.
5. Add TOT flow action (`Time_Off_Request_Update_Time_Card_TOT`) when TOT is enabled in target org.

## 6) Validation checklist

### Data creation checks
- One `Employee_Time_Card__c` per employee/month.
- One `Employee_Time_Card_Day_Entry__c` per day in target month.
- `Calendar_Working_Days__c` and `Day_Definition__c` correctly populated from weekend/holiday source.

### Activity mapping checks
- Planned/unplanned counts match source object mapping.
- AM/PM counts match mapped logic.
- Coaching counts match mapped coaching rule.

### Reporting checks
- Report type is accessible.
- `Working_Days_Analysis_Czl` executes in both `WorkingDaysAnalysis` and `Visits` folders.
- Report summaries match day-entry records for a sample user/month.

### Security checks
- Assigned users can run both flows and view related reports.
- Object and field permissions exist for time-card objects, even if delivered via profile in source org.

## 7) Handover to developer

Share these two files with the developer and ask Cursor to use them as migration inputs:
- `manifest/package-timecard-migration.xml`
- `docs/config/employee_time_card_module_config.yaml`

Then run:
1. Baseline deploy from package manifest.
2. Cursor question flow from YAML.
3. Mapping updates and MASS activation.
4. Validation checklist execution.
