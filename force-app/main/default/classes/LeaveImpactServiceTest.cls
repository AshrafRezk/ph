@IsTest
private class LeaveImpactServiceTest {
    private static CallTargetAdjustmentService.Rule rule(Decimal threshold) {
        CallTargetAdjustmentService.Rule rule = new CallTargetAdjustmentService.Rule();
        rule.enabled = true;
        rule.thresholdDays = threshold;
        rule.minimumTarget = 0;
        rule.longTermDays = 40;
        rule.zeroOnLongTerm = false;
        return rule;
    }

    @IsTest
    static void computeAdjustedTargetMath() {
        CallTargetAdjustmentService.Rule rule = rule(3);
        // At or past the threshold -> pro-rated by working days.
        System.assertEquals(15, LeaveImpactService.computeAdjustedTarget(20, 20, 5, rule));
        // Below the threshold -> unchanged.
        System.assertEquals(20, LeaveImpactService.computeAdjustedTarget(20, 20, 2, rule));
        // No leave -> unchanged.
        System.assertEquals(20, LeaveImpactService.computeAdjustedTarget(20, 20, 0, rule));
        // Zero/'null' target -> 0.
        System.assertEquals(0, LeaveImpactService.computeAdjustedTarget(0, 20, 5, rule));
        // Leave exceeds working days -> target floors at 0.
        System.assertEquals(0, LeaveImpactService.computeAdjustedTarget(20, 10, 15, rule));
        // Same single formula the per-account targets use.
        System.assertEquals(
            CallTargetAdjustmentService.proRate(20, 5, 20, rule).setScale(0, System.RoundingMode.HALF_UP),
            LeaveImpactService.computeAdjustedTarget(20, 20, 5, rule)
        );
    }

    @IsTest
    static void recalcSetsLeaveDays() {
        Employee_Time_Card__c tc = new Employee_Time_Card__c(Employee__c = UserInfo.getUserId());
        insert tc;
        insert new List<Employee_Time_Card_Day_Entry__c>{
            new Employee_Time_Card_Day_Entry__c(
                Employee_Time_Card__c = tc.Id, Date__c = Date.today(),
                Calendar_Working_Days__c = 20, TOT_Days_Excluding_Weekends__c = 6
            )
        };

        Test.startTest();
        LeaveImpactService.recalcInvocable(new List<Id>{ tc.Id });
        Test.stopTest();

        Employee_Time_Card__c updated = [
            SELECT Approved_Leave_Days__c, Adjusted_Visit_Target__c, Is_Long_Leave__c
            FROM Employee_Time_Card__c WHERE Id = :tc.Id
        ];
        System.assertEquals(6, updated.Approved_Leave_Days__c);
        System.assertEquals(true, updated.Is_Long_Leave__c, 'Leave > 5 flags long leave');
    }

    @IsTest
    static void approvingTimeOffRecalcs() {
        Id me = UserInfo.getUserId();
        Date monthStart = Date.today().toStartOfMonth();
        Date monthEnd = monthStart.addMonths(1).addDays(-1);
        Employee_Time_Card__c tc = new Employee_Time_Card__c(
            Employee__c = me,
            Time_Card_Month_Start_Date__c = monthStart,
            Time_Card_Month_End_Date__c = monthEnd
        );
        insert tc;
        insert new Employee_Time_Card_Day_Entry__c(
            Employee_Time_Card__c = tc.Id, Date__c = monthStart,
            Calendar_Working_Days__c = 20, TOT_Days_Excluding_Weekends__c = 0
        );
        CallTargetAdjustmentService.Rule saved = rule(1);
        CallTargetAdjustmentService.saveRule(saved);

        // Five working days of approved leave inside the month. Weekend days do not count.
        String department = EmployeeTimeCardFlowHelper.getEmployeeDepartment(me);
        Date cursor = monthStart;
        Integer expectedLeave = 0;
        Date firstDay = null;
        while (cursor <= monthEnd && expectedLeave < 5) {
            if (!PlannerRulesService.isWeekendDay(cursor, department)) {
                if (firstDay == null) {
                    firstDay = cursor;
                }
                expectedLeave++;
            }
            cursor = cursor.addDays(1);
        }
        Date lastDay = cursor.addDays(-1);

        Test.startTest();
        insert new Time_Off_Request__c(
            Type__c = 'Sick Leave',
            Span_Type__c = 'Days',
            Stage__c = 'Approved',
            Start_Date_Time__c = DateTime.newInstance(firstDay, Time.newInstance(9, 0, 0, 0)),
            End_Date_Time__c = DateTime.newInstance(lastDay, Time.newInstance(17, 0, 0, 0))
        );
        Test.stopTest();

        Employee_Time_Card__c updated = [
            SELECT Approved_Leave_Days__c FROM Employee_Time_Card__c WHERE Id = :tc.Id
        ];
        System.assertEquals(
            expectedLeave,
            updated.Approved_Leave_Days__c,
            'Approval recalculated the counted leave straight from the approved request'
        );
        System.assertEquals(
            75,
            LeaveImpactService.computeAdjustedTarget(100, 20, updated.Approved_Leave_Days__c, saved),
            'The single pro-rated formula: 100 x (20 - 5) / 20'
        );
    }
}
