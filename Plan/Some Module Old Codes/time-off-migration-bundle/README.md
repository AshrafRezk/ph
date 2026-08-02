# Time Off Module Migration Package

Self-contained Salesforce metadata for deploying the **Time Off Request** module (`Time_Off_Request__c`) to a non-IDH org.

## Contents

### Data model
- Custom object `Time_Off_Request__c` with 18 fields, 10 validation rules, 4 list views
- English translations (`Time_Off_Request__c-en_US`)

### Automation
- 8 record-triggered and screen flows (approve, reject, bulk actions, overlap validation, manager assignment, TOT recalc)
- 8 Apex classes + 4 test classes
- `EmployeeTimeCardFlowHelper` for TOT rollup integration

### UI
- Lightning record pages (`Time_Off_Request_Record_Page1` is the active page)
- Page layout, custom tab, path assistants, animation rule
- 6 quick actions (Submit, Recall, Approve, Reject, Bulk Approve, Bulk Reject)

### Access
- `Time_Off_Request_User` — full access for requestors (CRUD, all FLS, tab, Apex, flows)
- `Time_Off_Request_Manager` — same as User plus View All Records (for managers with Private OWD)

### Notifications
- Custom notification type `Time_Off_Submitted_To_Manager`

### Excluded (IDH-specific)
- `Update_Visits_of_Time_off_days` flow (depends on `Visit__c`)
- Profiles and `IDH_Sales` app (use permission sets and add the tab to your own app)

## Deploy

### 1. Time Off module (required)

```bash
cd time-off-migration-bundle
sf project deploy start --manifest manifest/package.xml --target-org <alias>
```

### 2. Time Card TOT dependency (optional — deploy before main package if needed)

Deploy this **first** if the target org does not already have Employee Time Card objects and you need TOT rollup on day entries when time off is approved.

```bash
sf project deploy start --manifest manifest/package-timecard-tot.xml --target-org <alias>
```

Alternatively, deploy the full [`generic-employee-timecard-migration`](../generic-employee-timecard-migration/) package instead.

## Post-deploy checklist

1. **Activate flows** — confirm all 8 Time Off flows are Active (Setup → Flows).
2. **Assign permission sets**
   - `Time_Off_Request_User` — all employees who submit time off
   - `Time_Off_Request_Manager` — managers who approve/reject (needed because OWD is Private)
3. **Add tab to a Lightning app** — add `Time Off Request` to your target app's navigation.
4. **User ManagerId** — ensure users have `Manager` populated for approval routing and notifications.
5. **Notifications** — enable desktop notifications for `Time Off Submitted To Manager` if desired.
6. **TOT integration** — if using time cards, deploy `package-timecard-tot.xml` or the full time card module, then verify approved time off updates `TOT_Days__c` on day entries.
7. **Smoke test**
   - Create a Draft request → Submit for Approval
   - Manager approves or rejects (rejection requires reason)
   - Requestor recalls while Submitted for Approval
   - Verify overlap validation blocks conflicting dates
   - Confirm path assistant shows stage progression

## Module features

| Feature | Component |
|---------|-----------|
| Request types | Holiday, Sick Leave, Training, Event, Travelling |
| Stages | Draft → Submitted for Approval → Approved / Rejected |
| Overlap check | Before-save flow + validation rule |
| Manager approval | Screen flows + quick actions |
| Bulk approve/reject | List view quick actions + screen flows |
| TOT rollup | Updates Employee Time Card day entries on approve/delete |
| Path | Stage path assistant with animation |

## Portable adaptations in this bundle

- `UserID__c` formula uses `CreatedBy.Username` (source org used `CreatedBy.External_Id__c`)
- Single path assistant (`Time_off`) — Salesforce allows one path per object/record type
- `FlowDefinition` metadata excluded — flows auto-register on deploy
- Required fields (`Type__c`, `Start_Date_Time__c`) are not in permission set FLS (inherit from object CRUD)

## Zip artifact

The repo root contains `time-off-module.zip` — extract and deploy using the commands above.
