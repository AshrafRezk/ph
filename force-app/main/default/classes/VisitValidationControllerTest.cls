@IsTest
private class VisitValidationControllerTest {
    @IsTest
    static void validateUnplannedVisit_rejectsInvalidInput() {
        Boolean threw = false;
        Test.startTest();
        try {
            VisitValidationController.validateUnplannedVisit(null, 'Valid');
        } catch (Exception ex) {
            threw = true;
        }
        System.assertEquals(true, threw, 'Null visit id should throw');

        threw = false;
        try {
            VisitValidationController.validateUnplannedVisit(UserInfo.getUserId(), 'Maybe');
        } catch (Exception ex) {
            threw = true;
        }
        Test.stopTest();
        System.assertEquals(true, threw, 'Invalid validation status should throw');
    }

    @IsTest
    static void validateUnplannedVisit_requiresManager() {
        Account account = new Account(Name = 'Validation Account');
        insert account;
        Visit__c visit = new Visit__c(
            Account__c = account.Id,
            Assigned_To__c = UserInfo.getUserId(),
            Start_Date__c = System.now(),
            End_Date__c = System.now().addHours(1),
            Visit_Date__c = System.now(),
            Status__c = 'Scheduled',
            Visit_Type__c = 'Unplanned'
        );
        insert visit;
        visit.Status__c = 'Completed';
        update visit;

        Boolean threw = false;
        Test.startTest();
        try {
            VisitValidationController.validateUnplannedVisit(visit.Id, 'Valid');
        } catch (Exception ex) {
            threw = true;
        }
        Test.stopTest();
        System.assertEquals(true, threw, 'Non-manager should not validate');
    }

    @IsTest
    static void validateUnplannedVisit_rejectsPlannedVisit() {
        Account account = new Account(Name = 'Planned Validation Account');
        insert account;
        Visit__c visit = new Visit__c(
            Account__c = account.Id,
            Assigned_To__c = UserInfo.getUserId(),
            Start_Date__c = System.now(),
            End_Date__c = System.now().addHours(1),
            Visit_Date__c = System.now(),
            Status__c = 'Completed',
            Visit_Type__c = 'Planned (Automatically)'
        );
        insert visit;

        Boolean threw = false;
        Test.startTest();
        try {
            VisitValidationController.validateUnplannedVisit(visit.Id, 'Valid');
        } catch (Exception ex) {
            threw = true;
        }
        Test.stopTest();
        System.assertEquals(true, threw, 'Planned visits should not use unplanned validation');
    }

    @IsTest
    static void rejectPlanVisit_requiresSubmittedStatus() {
        Account account = new Account(Name = 'Reject Account');
        insert account;
        Visit__c visit = new Visit__c(
            Account__c = account.Id,
            Assigned_To__c = UserInfo.getUserId(),
            Start_Date__c = System.now(),
            End_Date__c = System.now().addHours(1),
            Visit_Date__c = System.now(),
            Status__c = 'Draft',
            Visit_Type__c = 'Planned (Automatically)'
        );
        insert visit;

        Boolean threw = false;
        Test.startTest();
        try {
            VisitValidationController.rejectPlanVisit(visit.Id, 'Needs changes');
        } catch (Exception ex) {
            threw = true;
        }
        Test.stopTest();
        System.assertEquals(true, threw, 'Only submitted visits can be rejected');
    }

    @IsTest
    static void getPendingQueues_returnEmptyWithoutDirectReports() {
        Test.startTest();
        List<VisitValidationController.PlanApprovalRow> plans =
            VisitValidationController.getPendingPlanApprovals();
        List<VisitValidationController.UnplannedReviewRow> reviews =
            VisitValidationController.getPendingUnplannedReviews();
        Test.stopTest();
        System.assertNotEquals(null, plans);
        System.assertNotEquals(null, reviews);
    }

    @IsTest
    static void managerQueues_andValidationActions() {
        PermissionSet ps = [
            SELECT Id
            FROM PermissionSet
            WHERE Name = 'Visit_Lifecycle_Access'
            LIMIT 1
        ];
        System.runAs(new User(Id = UserInfo.getUserId())) {
            insert new PermissionSetAssignment(AssigneeId = UserInfo.getUserId(), PermissionSetId = ps.Id);
        }

        Profile standardProfile = [
            SELECT Id
            FROM Profile
            WHERE Name = 'System Administrator'
            LIMIT 1
        ];
        String suffix = String.valueOf(System.currentTimeMillis());
        User manager = new User(
            FirstName = 'Visit',
            LastName = 'Manager',
            Email = 'visit.manager.' + suffix + '@example.com',
            Username = 'visit.manager.' + suffix + '@example.com',
            Alias = ('vm' + suffix).left(8),
            TimeZoneSidKey = 'America/Los_Angeles',
            LocaleSidKey = 'en_US',
            EmailEncodingKey = 'UTF-8',
            LanguageLocaleKey = 'en_US',
            ProfileId = standardProfile.Id
        );
        insert manager;

        User rep = new User(
            FirstName = 'Visit',
            LastName = 'Rep',
            Email = 'visit.rep.' + suffix + '@example.com',
            Username = 'visit.rep.' + suffix + '@example.com',
            Alias = ('vr' + suffix).left(8),
            TimeZoneSidKey = 'America/Los_Angeles',
            LocaleSidKey = 'en_US',
            EmailEncodingKey = 'UTF-8',
            LanguageLocaleKey = 'en_US',
            ProfileId = standardProfile.Id,
            ManagerId = manager.Id
        );
        insert rep;

        System.runAs(new User(Id = UserInfo.getUserId())) {
            insert new PermissionSetAssignment(AssigneeId = manager.Id, PermissionSetId = ps.Id);
        }

        Account account = new Account(Name = 'Manager Queue Account');
        insert account;

        Date workingDay = WorkingCalendarUtil.addWorkingDays(Date.today(), 1);
        DateTime startDt = DateTime.newInstance(workingDay, Time.newInstance(11, 0, 0, 0));
        Visit__c submitted = new Visit__c(
            Account__c = account.Id,
            Assigned_To__c = rep.Id,
            Start_Date__c = startDt,
            End_Date__c = startDt.addMinutes(30),
            Visit_Date__c = startDt,
            Status__c = 'Submitted',
            Visit_Type__c = 'Planned (Automatically)'
        );
        insert submitted;
        Id submittedVisitId = submitted.Id;

        Visit__c unplanned = new Visit__c(
            Account__c = account.Id,
            Assigned_To__c = rep.Id,
            Start_Date__c = System.now().addHours(-2),
            End_Date__c = System.now().addHours(-1),
            Visit_Date__c = System.now().addHours(-2),
            Status__c = 'Scheduled',
            Visit_Type__c = 'Unplanned'
        );
        insert unplanned;
        VisitValidationControllerTestHelper.seedPendingUnplannedReview(unplanned.Id);
        Id unplannedVisitId = unplanned.Id;

        System.runAs(manager) {
            Test.startTest();
            List<VisitValidationController.PlanApprovalRow> plans =
                VisitValidationController.getPendingPlanApprovals();
            List<VisitValidationController.UnplannedReviewRow> reviews =
                VisitValidationController.getPendingUnplannedReviews();
            VisitValidationController.rejectPlanVisit(submittedVisitId, 'Needs more detail');
            VisitValidationController.validateUnplannedVisit(unplannedVisitId, 'Valid');
            Test.stopTest();

            System.assertEquals(1, plans.size());
            System.assertEquals(1, reviews.size());
        }

        System.assertEquals(
            'Draft',
            [SELECT Status__c FROM Visit__c WHERE Id = :submittedVisitId].Status__c
        );
    }

    private static User makeUser(String alias, Id managerId) {
        User u = new User(
            FirstName = 'Wave',
            LastName = alias,
            Email = alias + '@example.com',
            Username = alias + '.' + System.currentTimeMillis() + '@example.com',
            Alias = alias,
            TimeZoneSidKey = UserInfo.getTimeZone().getID(),
            LocaleSidKey = 'en_US',
            EmailEncodingKey = 'UTF-8',
            LanguageLocaleKey = 'en_US',
            ProfileId = UserInfo.getProfileId(),
            ManagerId = managerId
        );
        insert u;
        return u;
    }

    @IsTest
    static void completingAnUnplannedVisitQueuesItForTheDmWithin24Hours() {
        User rep = makeUser('wvrep', UserInfo.getUserId());
        Account account = new Account(Name = 'Unplanned Queue Account');
        insert account;
        Visit__c visit = new Visit__c(
            Account__c = account.Id,
            Assigned_To__c = rep.Id,
            Start_Date__c = System.now(),
            End_Date__c = System.now().addHours(1),
            Visit_Date__c = System.now(),
            Status__c = 'Scheduled',
            Visit_Type__c = 'Unplanned'
        );
        insert visit;

        Test.startTest();
        DateTime before = System.now();
        visit.Status__c = 'Completed';
        update visit;
        Test.stopTest();

        Visit__c saved = [
            SELECT Validation_Status__c, Validation_Due_At__c, Validation_Due_Date__c
            FROM Visit__c
            WHERE Id = :visit.Id
            WITH SYSTEM_MODE
        ];
        System.assertEquals('Pending', saved.Validation_Status__c);
        System.assertNotEquals(null, saved.Validation_Due_At__c);
        Long hours = (saved.Validation_Due_At__c.getTime() - before.getTime()) / (1000L * 60 * 60);
        System.assert(hours >= 23 && hours <= 24, 'Due in 24 hours, got ' + hours);
        System.assertEquals(saved.Validation_Due_At__c.date(), saved.Validation_Due_Date__c);

        List<VisitValidationController.UnplannedReviewRow> rows =
            VisitValidationController.loadPendingUnplannedReviews();
        System.assertEquals(1, rows.size(), 'DM sees the completed unplanned visit');
        System.assertEquals(false, rows[0].isOverdue);
        System.assertEquals(saved.Validation_Due_At__c, rows[0].validationDueAt);
    }

    @IsTest
    static void overdueReviewsAreFlaggedAndPlannedVisitsAreNotQueued() {
        User rep = makeUser('wvrep2', UserInfo.getUserId());
        Account account = new Account(Name = 'Overdue Queue Account');
        insert account;
        Visit__c unplanned = new Visit__c(
            Account__c = account.Id,
            Assigned_To__c = rep.Id,
            Start_Date__c = System.now(),
            End_Date__c = System.now().addHours(1),
            Visit_Date__c = System.now(),
            Status__c = 'Scheduled',
            Visit_Type__c = 'Unplanned'
        );
        Visit__c planned = unplanned.clone(false, true);
        planned.Visit_Type__c = 'Planned (Automatically)';
        insert new List<Visit__c>{ unplanned, planned };
        unplanned.Status__c = 'Completed';
        planned.Status__c = 'Completed';
        update new List<Visit__c>{ unplanned, planned };

        unplanned.Validation_Due_At__c = System.now().addHours(-2);
        update as system unplanned;

        Test.startTest();
        List<VisitValidationController.UnplannedReviewRow> rows =
            VisitValidationController.loadPendingUnplannedReviews();
        List<VisitValidationController.PlanApprovalRow> plans =
            VisitValidationController.loadPendingPlanApprovals();
        Test.stopTest();

        System.assertEquals(1, rows.size());
        System.assertEquals(unplanned.Id, rows[0].visitId);
        System.assertEquals(true, rows[0].isOverdue);
        System.assertEquals(
            null,
            [SELECT Validation_Status__c FROM Visit__c WHERE Id = :planned.Id WITH SYSTEM_MODE].Validation_Status__c
        );
        System.assertNotEquals(null, plans);
    }
}
