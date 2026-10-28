@IsTest
private class CallTargetAdjustmentServiceTest {
    @IsTest
    static void adjustTarget_proRatesByWorkingDays() {
        CallTargetAdjustmentService.Rule rule = new CallTargetAdjustmentService.Rule();
        rule.enabled = true;
        rule.thresholdDays = 5;
        rule.stepSize = 1;
        rule.minimumTarget = 0;
        rule.longTermDays = 40;
        rule.zeroOnLongTerm = false;

        // Below the threshold nothing changes.
        Assert.areEqual(3, CallTargetAdjustmentService.adjustTarget(3, 4, 20, rule));
        // 20 working days, 10 counted: half the target, rounded half up.
        Assert.areEqual(2, CallTargetAdjustmentService.adjustTarget(3, 10, 20, rule));
        Assert.areEqual(10, CallTargetAdjustmentService.adjustTarget(20, 10, 20, rule));
        Assert.areEqual(15, CallTargetAdjustmentService.adjustTarget(20, 5, 20, rule));
        // The unrounded formula is base x (working - leave) / working.
        Assert.areEqual(1.5, CallTargetAdjustmentService.proRate(3, 10, 20, rule));
        // More leave than working days floors at the lowest target.
        Assert.areEqual(0, CallTargetAdjustmentService.adjustTarget(3, 30, 20, rule));
        rule.minimumTarget = 1;
        Assert.areEqual(1, CallTargetAdjustmentService.adjustTarget(3, 30, 20, rule));
        // The floor never raises a target that is already below it.
        Assert.areEqual(0, CallTargetAdjustmentService.adjustTarget(0, 30, 20, rule));

        rule.minimumTarget = 0;
        rule.zeroOnLongTerm = true;
        Assert.areEqual(0, CallTargetAdjustmentService.adjustTarget(3, 40, 60, rule));
        Assert.areEqual(1, CallTargetAdjustmentService.adjustTarget(3, 39, 60, rule));

        rule.enabled = false;
        Assert.areEqual(3, CallTargetAdjustmentService.adjustTarget(3, 20, 20, rule));
    }

    @IsTest
    static void adjustTarget_withoutWorkingDays_leavesTargetAlone() {
        CallTargetAdjustmentService.Rule rule = new CallTargetAdjustmentService.Rule();
        rule.enabled = true;
        rule.thresholdDays = 1;
        Assert.areEqual(3, CallTargetAdjustmentService.adjustTarget(3, 10, null, rule));
        Assert.areEqual(3, CallTargetAdjustmentService.adjustTarget(3, 10, 0, rule));
        // Two-arg compatibility overload (no working days) keeps the base target.
        Assert.areEqual(3, CallTargetAdjustmentService.adjustTarget(3, 10));
        Assert.areEqual(0, CallTargetAdjustmentService.adjustTarget(null, 10));
    }

    @IsTest
    static void getRule_returnsPreviewAndTypeOptions() {
        CallTargetAdjustmentService.clearCache();
        CallTargetAdjustmentService.Rule rule = CallTargetAdjustmentService.getRule();
        Assert.isNotNull(rule.preview);
        Assert.isTrue(rule.typeOptions != null && rule.typeOptions.size() > 0);
        Assert.isTrue(rule.enabled);
    }

    @IsTest
    static void qualifyingDays_countsApprovedRequests() {
        CallTargetAdjustmentService.clearCache();
        CallTargetAdjustmentService.Rule rule = CallTargetAdjustmentService.currentRule();
        rule.enabled = true;
        rule.countedTypes = null;
        CallTargetAdjustmentService.saveRule(rule);
        Date monthStart = Date.today().toStartOfMonth();
        Date monthEnd = monthStart.addDays(2);
        // No requests -> zero. Smoke the query path.
        Assert.areEqual(
            0,
            CallTargetAdjustmentService.qualifyingDays(UserInfo.getUserId(), monthStart, monthEnd)
        );
        Assert.areEqual(0, CallTargetAdjustmentService.qualifyingDays(null, monthStart, monthEnd));
        Assert.areEqual(0, CallTargetAdjustmentService.qualifyingDays(UserInfo.getUserId(), monthEnd, monthStart));
        Map<Id, Decimal> empty = CallTargetAdjustmentService.workingDaysByCard(new Set<Id>());
        Assert.areEqual(0, empty.size());
        Map<Id, Decimal> missing = CallTargetAdjustmentService.workingDaysByCard(null);
        Assert.areEqual(0, missing.size());
    }

    @IsTest
    static void saveRule_rejectsBadInput() {
        CallTargetAdjustmentService.Rule rule = new CallTargetAdjustmentService.Rule();
        rule.enabled = true;
        rule.thresholdDays = -1;
        rule.stepSize = 1;
        rule.minimumTarget = 0;
        Boolean rejected = false;
        try {
            CallTargetAdjustmentService.saveRule(rule);
        } catch (AuraHandledException expected) {
            rejected = true;
        }
        Assert.isTrue(rejected);
        Assert.isTrue(CallTargetAdjustmentService.countsType('Anything', new CallTargetAdjustmentService.Rule()));
    }

    @IsTest
    static void countsType_blankMeansEveryType() {
        CallTargetAdjustmentService.Rule rule = new CallTargetAdjustmentService.Rule();
        Assert.isTrue(CallTargetAdjustmentService.countsType('Office Work', rule));
        rule.countedTypes = 'Office Work\nAnnual Vacation';
        Assert.isTrue(CallTargetAdjustmentService.countsType('office work', rule));
        Assert.isFalse(CallTargetAdjustmentService.countsType('Training', rule));
    }

    @IsTest
    static void currentRule_usesDefaultsUntilSaved() {
        CallTargetAdjustmentService.clearCache();
        CallTargetAdjustmentService.Rule rule = CallTargetAdjustmentService.currentRule();
        Assert.areEqual(7, rule.thresholdDays);
        Assert.areEqual(1, rule.stepSize);
        Assert.isTrue(rule.enabled);

        rule.thresholdDays = 5;
        rule.stepSize = 1;
        rule.minimumTarget = 0;
        rule.longTermDays = 40;
        rule.zeroOnLongTerm = false;
        rule.countedTypes = 'Office Work';
        rule.enabled = true;
        CallTargetAdjustmentService.Rule saved = CallTargetAdjustmentService.saveRule(rule);
        Assert.areEqual(5, saved.thresholdDays);
        Assert.isTrue(saved.preview.contains('5'));
        Assert.isTrue(saved.typeOptions.size() > 0);
    }

    @IsTest
    static void batch_reappliesCurrentMonth() {
        Date monthStart = Date.today().toStartOfMonth();
        Employee_Time_Card__c card = new Employee_Time_Card__c(
            Employee__c = UserInfo.getUserId(),
            Time_Card_Month_Start_Date__c = monthStart,
            Time_Card_Month_End_Date__c = monthStart.addMonths(1).addDays(-1),
            Active_Time_Card__c = true,
            Unique_Identifier__c = String.valueOf(UserInfo.getUserId()) + ':calltarget:' + String.valueOf(monthStart)
        );
        insert card;
        Test.startTest();
        Database.executeBatch(new CallTargetAdjustmentBatch(), 10);
        Test.stopTest();
        Assert.areEqual(1, [SELECT COUNT() FROM Employee_Time_Card__c WHERE Id = :card.Id]);
    }
}
