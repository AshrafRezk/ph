/**
 * @description Tests for CRM Hub Home week bounds, scoring, activity buckets, and payload shape.
 */
@IsTest
private class CrmHubHomeStatsServiceTest {
    @IsTest
    static void testSundayOnOrBefore() {
        // 2026-07-22 is a Wednesday → week starts 2026-07-19 (Sunday)
        Date wed = Date.newInstance(2026, 7, 22);
        System.assertEquals(Date.newInstance(2026, 7, 19), CrmHubHomeStatsService.sundayOnOrBefore(wed));
        System.assertEquals(Date.newInstance(2026, 7, 19), CrmHubHomeStatsService.sundayOnOrBefore(Date.newInstance(2026, 7, 19)));
        System.assertEquals(Date.newInstance(2026, 7, 19), CrmHubHomeStatsService.sundayOnOrBefore(Date.newInstance(2026, 7, 25)));
    }

    @IsTest
    static void testWeekWindowSunSat() {
        CrmHubHomeStatsService.todayOverride = Date.newInstance(2026, 7, 22);
        CrmHubHomeStatsService.WeekWindow w = CrmHubHomeStatsService.weekWindowFor(CrmHubHomeStatsService.today());
        System.assertEquals(Date.newInstance(2026, 7, 19), w.weekStart);
        System.assertEquals(Date.newInstance(2026, 7, 25), w.weekEnd);
        CrmHubHomeStatsService.todayOverride = null;
    }

    @IsTest
    static void testBucketTask() {
        System.assertEquals('Call', CrmHubHomeStatsService.bucketTask('Call', null));
        System.assertEquals('Email', CrmHubHomeStatsService.bucketTask('Email', 'Other'));
        System.assertEquals('Email', CrmHubHomeStatsService.bucketTask(null, 'Email'));
        System.assertEquals('Other', CrmHubHomeStatsService.bucketTask('Task', 'Other'));
    }

    @IsTest
    static void testBlankToValue() {
        System.assertEquals(true, CrmHubHomeStatsService.isBlankToValue(null, 'a@b.com'));
        System.assertEquals(true, CrmHubHomeStatsService.isBlankToValue('', '555'));
        System.assertEquals(false, CrmHubHomeStatsService.isBlankToValue('old', 'new'));
        System.assertEquals(false, CrmHubHomeStatsService.isBlankToValue(null, null));
        System.assertEquals(false, CrmHubHomeStatsService.isBlankToValue(null, ''));
    }

    @IsTest
    static void testScoreFormula() {
        CrmHubHomeStatsService.MetricCounts empty = new CrmHubHomeStatsService.MetricCounts();
        System.assertEquals(50, CrmHubHomeStatsService.computeScore(empty, empty, false));

        CrmHubHomeStatsService.MetricCounts busy = new CrmHubHomeStatsService.MetricCounts();
        busy.accountsCreated = 2;
        busy.contactsCreated = 2;
        busy.oppsActedOn = 3;
        busy.activitiesTotal = 5;
        busy.contactImproved = 1;
        Integer score = CrmHubHomeStatsService.computeScore(busy, empty, false);
        System.assert(score > 50, 'Busy week vs empty last week should score above 50, got ' + score);
        System.assert(score <= 100);
    }

    @IsTest
    static void testBuildHomeStatsPartialWithActivity() {
        Account acc = new Account(Name = 'Home Stats Acc');
        insert acc;
        Contact con = new Contact(LastName = 'HomeStatsCon', AccountId = acc.Id, Email = 'home@example.com');
        insert con;
        Opportunity opp = new Opportunity(
            Name = 'Home Stats Opp',
            AccountId = acc.Id,
            StageName = 'Prospecting',
            CloseDate = Date.today().addDays(30),
            Type = 'Existing Business',
            Type_of_Service__c = 'Other'
        );
        insert opp;
        Task callTask = new Task(
            Subject = 'Home call',
            WhatId = opp.Id,
            Status = 'Completed',
            Priority = 'Normal',
            TaskSubtype = 'Call'
        );
        insert callTask;
        Event meeting = new Event(
            Subject = 'Home meet',
            WhatId = opp.Id,
            StartDateTime = Datetime.now(),
            EndDateTime = Datetime.now().addHours(1)
        );
        insert meeting;

        Test.startTest();
        Map<String, Object> res = CrmHubHomeStatsService.buildHomeStats(false);
        Test.stopTest();

        System.assertEquals(true, res.get('success'));
        System.assertEquals(false, res.get('isFullAccess'));
        System.assertNotEquals(null, res.get('weekStart'));
        System.assertNotEquals(null, res.get('weekEnd'));
        Map<String, Object> me = (Map<String, Object>) res.get('me');
        System.assertNotEquals(null, me.get('score'));
        Map<String, Object> tw = (Map<String, Object>) me.get('thisWeek');
        System.assert(crmHubHomeNum(tw.get('accountsCreated')) >= 1);
        System.assert(crmHubHomeNum(tw.get('contactsCreated')) >= 1);
        System.assert(crmHubHomeNum(tw.get('oppsActedOn')) >= 1);
        System.assert(crmHubHomeNum(tw.get('activitiesTotal')) >= 2);
        Map<String, Object> byType = (Map<String, Object>) tw.get('activitiesByType');
        System.assert(crmHubHomeNum(byType.get('Call')) >= 1);
        System.assert(crmHubHomeNum(byType.get('Meeting')) >= 1);
        System.assertEquals(null, tw.get('applicantsNew'), 'Partial should omit HR fields');
        Map<String, Object> company = (Map<String, Object>) res.get('company');
        System.assertNotEquals(null, company.get('thisWeek'));
        List<Object> board = (List<Object>) res.get('leaderboard');
        System.assert(!board.isEmpty(), 'Leaderboard should include current user');
    }

    @IsTest
    static void testBuildHomeStatsFullIncludesHr() {
        Position__c pos = new Position__c(
            Name = 'Home HR Pos',
            Years_Of_Experience__c = 2,
            Max_Pay__c = 9000,
            Min_Pay__c = 7000,
            Status__c = 'New Position'
        );
        insert pos;
        Job_Application__c jaNew = new Job_Application__c(Position__c = pos.Id, Status__c = 'New');
        insert jaNew;
        Job_Application__c jaScreen = new Job_Application__c(
            Position__c = pos.Id,
            Status__c = 'Screening',
            Screening_Date__c = Date.today(),
            InterviewDateTime__c = Datetime.now()
        );
        insert jaScreen;

        Test.startTest();
        Map<String, Object> res = CrmHubHomeStatsService.buildHomeStats(true);
        Test.stopTest();

        System.assertEquals(true, res.get('isFullAccess'));
        Map<String, Object> me = (Map<String, Object>) res.get('me');
        Map<String, Object> tw = (Map<String, Object>) me.get('thisWeek');
        System.assert(tw.containsKey('applicantsNew'));
        System.assert(tw.containsKey('screeningsFinished'));
        System.assert(tw.containsKey('interviewsDone'));
        System.assert(crmHubHomeNum(tw.get('applicantsNew')) >= 1);
    }

    private static Integer crmHubHomeNum(Object o) {
        if (o == null) {
            return 0;
        }
        return Integer.valueOf(String.valueOf(o));
    }
}
