@IsTest
private class VisitConflictServiceTest {
    @IsTest
    static void blocksNonWorkingDay() {
        Account account = new Account(Name = 'Conflict Account');
        insert account;
        DateTime thursdayStart = DateTime.newInstance(Date.newInstance(2026, 8, 27), Time.newInstance(10, 0, 0, 0));
        DateTime thursdayEnd = thursdayStart.addHours(1);
        Boolean threw = false;
        Test.startTest();
        try {
            VisitConflictService.assertNoConflicts(UserInfo.getUserId(), thursdayStart, thursdayEnd, null);
        } catch (Exception ex) {
            threw = true;
        }
        Test.stopTest();
        System.assertEquals(true, threw, 'Expected non-working day block');
    }

    @IsTest
    static void blocksVisitOverlap() {
        Account account = new Account(Name = 'Overlap Account');
        insert account;
        DateTime startDt = DateTime.newInstance(Date.newInstance(2026, 8, 24), Time.newInstance(10, 0, 0, 0));
        DateTime endDt = startDt.addHours(1);
        Visit__c existing = new Visit__c(
            Account__c = account.Id,
            Assigned_To__c = UserInfo.getUserId(),
            Start_Date__c = startDt,
            End_Date__c = endDt,
            Visit_Date__c = startDt,
            Status__c = 'Scheduled',
            Visit_Type__c = 'Planned (Automatically)'
        );
        insert existing;

        Boolean threw = false;
        Test.startTest();
        try {
            VisitConflictService.assertNoConflicts(
                UserInfo.getUserId(),
                startDt.addMinutes(30),
                endDt.addMinutes(30),
                null
            );
        } catch (Exception ex) {
            threw = true;
        }
        Test.stopTest();
        System.assertEquals(true, threw, 'Expected visit overlap block');
    }

    @IsTest
    static void blocksTotOverlap() {
        Account account = new Account(Name = 'TOT Account');
        insert account;
        DateTime startDt = DateTime.newInstance(Date.newInstance(2026, 8, 24), Time.newInstance(10, 0, 0, 0));
        DateTime endDt = startDt.addHours(1);
        insert new Time_Off_Request__c(
            Type__c = 'Holiday',
            Span_Type__c = 'Full_Day',
            Start_Date_Time__c = startDt.addMinutes(-30),
            End_Date_Time__c = endDt.addMinutes(30),
            Span_Duration__c = 1,
            Stage__c = 'Draft'
        );
        Time_Off_Request__c tot = [
            SELECT Id
            FROM Time_Off_Request__c
            WHERE Type__c = 'Holiday'
            LIMIT 1
        ];
        tot.Stage__c = 'Approved';
        update tot;

        Boolean threw = false;
        Test.startTest();
        try {
            VisitConflictService.assertNoConflicts(UserInfo.getUserId(), startDt, endDt, null);
        } catch (Exception ex) {
            threw = true;
        }
        Test.stopTest();
        System.assertEquals(true, threw, 'Expected TOT overlap block');
    }

    @IsTest
    static void blocksDraftTotOverlapLikeThePlannerShowsIt() {
        Account account = new Account(Name = 'Draft TOT Account');
        insert account;
        DateTime startDt = DateTime.newInstance(Date.newInstance(2026, 8, 24), Time.newInstance(10, 0, 0, 0));
        DateTime endDt = startDt.addHours(1);
        insert new Time_Off_Request__c(
            Type__c = 'Holiday',
            Span_Type__c = 'Full_Day',
            Start_Date_Time__c = startDt.addHours(-2),
            End_Date_Time__c = endDt.addHours(2),
            Span_Duration__c = 1,
            Stage__c = 'Draft'
        );
        Visit__c candidate = new Visit__c(
            Account__c = account.Id,
            Assigned_To__c = UserInfo.getUserId(),
            Start_Date__c = startDt,
            End_Date__c = endDt,
            Visit_Date__c = startDt,
            Status__c = 'Draft',
            Visit_Type__c = 'Planned (Automatically)'
        );

        Boolean threw = false;
        Test.startTest();
        try {
            VisitConflictService.assertNoConflicts(UserInfo.getUserId(), startDt, endDt, null);
        } catch (Exception ex) {
            threw = true;
        }
        insert candidate;
        Map<Id, String> weekMessages = VisitConflictService.findConflictMessages(new List<Visit__c>{ candidate });
        Test.stopTest();

        System.assertEquals(true, threw, 'Draft time off on the calendar should block a visit in that slot.');
        System.assert(weekMessages.containsKey(candidate.Id), 'Week submit should flag the same draft time off overlap.');
    }

    @IsTest
    static void allowsSameVisitWhenExcluded() {
        Account account = new Account(Name = 'Exclude Account');
        insert account;
        DateTime startDt = DateTime.newInstance(Date.newInstance(2026, 8, 24), Time.newInstance(10, 0, 0, 0));
        DateTime endDt = startDt.addHours(1);
        Visit__c existing = new Visit__c(
            Account__c = account.Id,
            Assigned_To__c = UserInfo.getUserId(),
            Start_Date__c = startDt,
            End_Date__c = endDt,
            Visit_Date__c = startDt,
            Status__c = 'Scheduled',
            Visit_Type__c = 'Planned (Automatically)'
        );
        insert existing;

        Test.startTest();
        VisitConflictService.assertNoConflicts(
            UserInfo.getUserId(),
            startDt.addMinutes(15),
            endDt.addMinutes(15),
            existing.Id
        );
        Test.stopTest();
        System.assert(true);
    }

    @IsTest
    static void findConflictMessages_flagsOverlapAndSkipsClearSlot() {
        Account account = new Account(Name = 'Bulk Conflict Account');
        insert account;
        DateTime startDt = DateTime.newInstance(Date.newInstance(2026, 8, 24), Time.newInstance(10, 0, 0, 0));
        Visit__c existing = new Visit__c(
            Account__c = account.Id,
            Assigned_To__c = UserInfo.getUserId(),
            Start_Date__c = startDt,
            End_Date__c = startDt.addHours(1),
            Visit_Date__c = startDt,
            Status__c = 'Scheduled',
            Visit_Type__c = 'Planned (Automatically)'
        );
        Visit__c clearSlot = new Visit__c(
            Account__c = account.Id,
            Assigned_To__c = UserInfo.getUserId(),
            Start_Date__c = startDt.addHours(3),
            End_Date__c = startDt.addHours(4),
            Visit_Date__c = startDt.addHours(3),
            Status__c = 'Draft',
            Visit_Type__c = 'Planned (Automatically)'
        );
        Visit__c overlapping = new Visit__c(
            Account__c = account.Id,
            Assigned_To__c = UserInfo.getUserId(),
            Start_Date__c = startDt.addMinutes(15),
            End_Date__c = startDt.addMinutes(75),
            Visit_Date__c = startDt.addMinutes(15),
            Status__c = 'Draft',
            Visit_Type__c = 'Planned (Automatically)'
        );
        insert new List<Visit__c>{ existing, clearSlot };

        Test.startTest();
        Map<Id, String> clearMessages = VisitConflictService.findConflictMessages(
            new List<Visit__c>{ clearSlot, existing }
        );
        insert overlapping;
        Map<Id, String> overlapMessages = VisitConflictService.findConflictMessages(
            new List<Visit__c>{ overlapping }
        );
        Test.stopTest();

        System.assert(overlapMessages.containsKey(overlapping.Id), 'Expected the overlapping visit to be flagged.');
        System.assert(!clearMessages.containsKey(clearSlot.Id), 'A later slot should not conflict.');
        System.assert(
            !clearMessages.containsKey(existing.Id),
            'A visit must not conflict with itself.'
        );
    }

    @IsTest
    static void usesTheAssignedRepsWorkingDaysNotTheRunningUsers() {
        User rep = new User(
            FirstName = 'Conflict',
            LastName = 'Rep',
            Email = 'conflict.rep@example.com',
            Username = 'conflict.rep.' + System.currentTimeMillis() + '@example.com',
            Alias = 'cfrep',
            TimeZoneSidKey = UserInfo.getTimeZone().getID(),
            LocaleSidKey = 'en_US',
            EmailEncodingKey = 'UTF-8',
            LanguageLocaleKey = 'en_US',
            ProfileId = UserInfo.getProfileId()
        );
        insert rep;
        PlannerRulesService.Rule input = new PlannerRulesService.Rule();
        input.workingDays = 'SUN,MON,TUE,WED,THU';
        input.visitTotOverlap = PlannerRulesService.BLOCK;
        input.visitVisitOverlap = PlannerRulesService.BLOCK;
        input.visitMeetingOverlap = PlannerRulesService.WARN;
        input.totMeetingOverlap = PlannerRulesService.WARN;
        input.visitHolidayOverlap = PlannerRulesService.BLOCK;
        input.meetingHolidayOverlap = PlannerRulesService.WARN;
        input.weekendPlanning = PlannerRulesService.BLOCK;
        PlannerRulesService.saveRuleForScope(input, 'User', String.valueOf(rep.Id));
        PlannerRulesService.clearCache();

        // Thursday: a working day for the rep (Sun-Thu), a weekend for the running user (Sat-Wed).
        DateTime thursdayStart = DateTime.newInstance(Date.newInstance(2026, 8, 27), Time.newInstance(10, 0, 0, 0));
        Test.startTest();
        VisitConflictService.assertNoConflicts(rep.Id, thursdayStart, thursdayStart.addHours(1), null);
        Boolean selfBlocked = false;
        try {
            VisitConflictService.assertNoConflicts(UserInfo.getUserId(), thursdayStart, thursdayStart.addHours(1), null);
        } catch (Exception ex) {
            selfBlocked = true;
        }
        Test.stopTest();
        System.assertEquals(true, selfBlocked, 'Running user keeps their own Sat-Wed rule');
    }
}
