@IsTest(SeeAllData=false)
private class CaseSlaServiceTest {
    @IsTest
    static void applyStageTiming_setsStartAndDue() {
        Case caseRecord = new Case(
            Subject = 'SLA Test',
            Status = 'New'
        );

        Test.startTest();
        CaseSlaService.applyStageTiming(caseRecord);
        Test.stopTest();

        System.assertNotEquals(null, caseRecord.Stage_Start_Time__c);
        System.assertNotEquals(null, caseRecord.Stage_Due__c);
        System.assertEquals(
            caseRecord.Stage_Start_Time__c.addHours(CaseSlaService.DEFAULT_SLA_HOURS),
            caseRecord.Stage_Due__c
        );
    }

    @IsTest
    static void trigger_setsSlaOnInsertAndStatusChange() {
        Case createdCase = new Case(
            Subject = 'SLA Trigger Test',
            Status = 'New'
        );
        insert createdCase;

        createdCase = [
            SELECT Id, Stage_Start_Time__c, Stage_Due__c, Status
            FROM Case
            WHERE Id = :createdCase.Id
        ];
        System.assertNotEquals(null, createdCase.Stage_Start_Time__c);
        System.assertNotEquals(null, createdCase.Stage_Due__c);

        Datetime previousStart = createdCase.Stage_Start_Time__c;
        createdCase.Status = 'In Progress';
        update createdCase;

        createdCase = [
            SELECT Id, Stage_Start_Time__c, Stage_Due__c
            FROM Case
            WHERE Id = :createdCase.Id
        ];
        System.assert(createdCase.Stage_Start_Time__c >= previousStart);
    }

    @IsTest
    static void buildMilestoneView_handlesMissingAndClosedStates() {
        CaseSlaService.SlaMilestoneView missing = CaseSlaService.buildMilestoneView(null, null, false);
        System.assertEquals('NOT STARTED', missing.statusLabel);

        Datetime start = System.now().addHours(-1);
        Datetime due = System.now().addMinutes(10);
        CaseSlaService.SlaMilestoneView atRisk = CaseSlaService.buildMilestoneView(start, due, false);
        System.assertEquals('AT RISK', atRisk.statusLabel);
        System.assertEquals('warning', atRisk.statusVariant);

        CaseSlaService.SlaMilestoneView completed = CaseSlaService.buildMilestoneView(start, due, true);
        System.assertEquals('COMPLETED', completed.statusLabel);
        System.assertEquals(null, completed.dueInLabel);
    }

    @IsTest
    static void applyStageTiming_skipsClosedCases() {
        Case closedCase = new Case(
            Subject = 'Closed SLA Test',
            Status = 'Closed'
        );
        insert closedCase;

        Test.startTest();
        CaseSlaService.applyStageTiming(closedCase);
        Test.stopTest();

        System.assertEquals(null, closedCase.Stage_Start_Time__c);
    }

    @IsTest
    static void buildMilestoneView_onTrackAndViolated() {
        Datetime start = System.now().addHours(-2);
        Datetime due = System.now().addHours(22);

        CaseSlaService.SlaMilestoneView onTrack = CaseSlaService.buildMilestoneView(start, due, false);
        System.assertEquals('ON TRACK', onTrack.statusLabel);
        System.assertEquals('success', onTrack.statusVariant);
        System.assert(onTrack.elapsedLabel.contains('h'));
        System.assert(onTrack.dueInLabel.startsWith('Due in:'));

        CaseSlaService.SlaMilestoneView violated = CaseSlaService.buildMilestoneView(
            System.now().addHours(-30),
            System.now().addHours(-1),
            false
        );
        System.assertEquals('VIOLATED', violated.statusLabel);
        System.assertEquals('error', violated.statusVariant);
    }

    @IsTest
    static void controller_returnsMilestoneView() {
        Case createdCase = new Case(
            Subject = 'SLA Controller Test',
            Status = 'New'
        );
        insert createdCase;

        CaseSlaService.SlaMilestoneView view = CaseSlaController.getSlaMilestone(createdCase.Id);
        System.assertEquals('ON TRACK', view.statusLabel);
        System.assertNotEquals(null, view.elapsedLabel);
    }
}