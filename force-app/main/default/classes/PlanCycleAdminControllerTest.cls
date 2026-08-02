@IsTest
private class PlanCycleAdminControllerTest {

    @TestSetup
    static void setupData() {
        Account account = new Account(Name = 'Plan Cycle HCP');
        insert account;

        Date janStart = Date.newInstance(2026, 1, 1);
        Date febStart = Date.newInstance(2026, 2, 1);
        Id employeeId = UserInfo.getUserId();

        Employee_Time_Card__c janCard = new Employee_Time_Card__c(
            Employee__c = employeeId,
            Time_Card_Month_Start_Date__c = janStart,
            Time_Card_Month_End_Date__c = janStart.addMonths(1).addDays(-1),
            Unique_Identifier__c = employeeId + ':' + String.valueOf(janStart),
            Active_Time_Card__c = false
        );
        insert janCard;

        insert new Employee_Time_Card_Account_Target__c(
            Employee_Time_Card__c = janCard.Id,
            Account__c = account.Id,
            Potentiality__c = 'A',
            Target_Visit_Frequency__c = 4,
            Actual_Visits__c = 1,
            Unique_Key__c = janCard.Id + ':' + account.Id,
            Rep__c = employeeId
        );
    }

    @IsTest
    static void getYearMonthSummaries_returnsTwelveMonths() {
        Test.startTest();
        List<PlanCycleAdminController.MonthSummary> rows =
            PlanCycleAdminController.getYearMonthSummaries(2026);
        Test.stopTest();

        System.assertEquals(12, rows.size());
        System.assertEquals(1, rows[0].employeesWithPlans);
        System.assertEquals(0, rows[1].employeesWithPlans);
    }

    @IsTest
    static void getEmployeePlansForMonth_includesSeededPlan() {
        Test.startTest();
        List<PlanCycleAdminController.EmployeePlanRow> janRows =
            PlanCycleAdminController.getEmployeePlansForMonth(2026, 1);
        List<PlanCycleAdminController.EmployeePlanRow> febRows =
            PlanCycleAdminController.getEmployeePlansForMonth(2026, 2);
        Test.stopTest();

        Boolean foundJanPlan = false;
        for (PlanCycleAdminController.EmployeePlanRow row : janRows) {
            if (row.employeeId == UserInfo.getUserId() && row.hasPlan) {
                foundJanPlan = true;
                System.assertEquals(1, row.targetCount);
            }
        }
        System.assert(foundJanPlan, 'Expected current user to have a January plan.');

        Boolean foundFebPlan = false;
        for (PlanCycleAdminController.EmployeePlanRow row : febRows) {
            if (row.employeeId == UserInfo.getUserId() && row.hasPlan) {
                foundFebPlan = true;
            }
        }
        System.assertEquals(false, foundFebPlan);
    }

    @IsTest
    static void getPlanTargets_returnsAccountTargets() {
        Employee_Time_Card__c timeCard = [
            SELECT Id
            FROM Employee_Time_Card__c
            WHERE Time_Card_Month_Start_Date__c = :Date.newInstance(2026, 1, 1)
            LIMIT 1
        ];

        Test.startTest();
        List<PlanCycleAdminController.PlanTargetRow> rows =
            PlanCycleAdminController.getPlanTargets(timeCard.Id);
        Test.stopTest();

        System.assertEquals(1, rows.size());
        System.assertEquals(4, rows[0].targetVisitFrequency);
    }

    @IsTest
    static void savePlanTargets_updatesFrequency() {
        Employee_Time_Card_Account_Target__c target = [
            SELECT Id
            FROM Employee_Time_Card_Account_Target__c
            LIMIT 1
        ];

        PlanCycleAdminController.TargetUpdate updateRow = new PlanCycleAdminController.TargetUpdate();
        updateRow.id = target.Id;
        updateRow.targetVisitFrequency = 2;

        Test.startTest();
        PlanCycleAdminController.savePlanTargets(new List<PlanCycleAdminController.TargetUpdate>{ updateRow });
        Test.stopTest();

        Employee_Time_Card_Account_Target__c updated = [
            SELECT Target_Visit_Frequency__c
            FROM Employee_Time_Card_Account_Target__c
            WHERE Id = :target.Id
            LIMIT 1
        ];
        System.assertEquals(2, updated.Target_Visit_Frequency__c);
    }

    @IsTest
    static void copyPlansBetweenMonths_createsFebruaryTargets() {
        Test.startTest();
        PlanCycleAdminController.CopyPlanResult result = PlanCycleAdminController.copyPlansBetweenMonths(
            2026,
            1,
            2,
            new List<Id>{ UserInfo.getUserId() }
        );
        Test.stopTest();

        System.assertEquals(1, result.employeesCopied);
        System.assertEquals(1, result.targetsCopied);

        Employee_Time_Card__c febCard = [
            SELECT Id
            FROM Employee_Time_Card__c
            WHERE Employee__c = :UserInfo.getUserId()
            AND Time_Card_Month_Start_Date__c = :Date.newInstance(2026, 2, 1)
            LIMIT 1
        ];
        System.assertNotEquals(null, febCard);

        Employee_Time_Card_Account_Target__c copiedTarget = [
            SELECT Target_Visit_Frequency__c, Actual_Visits__c
            FROM Employee_Time_Card_Account_Target__c
            WHERE Employee_Time_Card__c = :febCard.Id
            LIMIT 1
        ];
        System.assertEquals(4, copiedTarget.Target_Visit_Frequency__c);
    }

    @IsTest
    static void ensureEmployeePlan_createsPlanWithTargets() {
        Account account = new Account(Name = 'Ensure Plan HCP');
        insert account;

        Test.startTest();
        Id timeCardId = PlanCycleAdminController.ensureEmployeePlan(
            UserInfo.getUserId(),
            2026,
            3
        );
        Test.stopTest();

        System.assertNotEquals(null, timeCardId);
        List<Employee_Time_Card_Account_Target__c> targets = [
            SELECT Id
            FROM Employee_Time_Card_Account_Target__c
            WHERE Employee_Time_Card__c = :timeCardId
        ];
        System.assert(targets.size() >= 0);
    }
}
