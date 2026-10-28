@IsTest
private class MeetingPlannerControllerTest {
    @TestSetup
    static void createDirectReport() {
        Profile adminProfile = [SELECT Id FROM Profile WHERE Name = 'System Administrator' LIMIT 1];
        String uniq = 'meetingrep' + String.valueOf(Datetime.now().getTime());
        insert new User(
            Alias = 'mtgrep',
            Email = 'meeting.rep@example.com.invalid',
            EmailEncodingKey = 'UTF-8',
            LastName = 'Meeting Rep',
            LanguageLocaleKey = 'en_US',
            LocaleSidKey = 'en_US',
            ProfileId = adminProfile.Id,
            TimeZoneSidKey = 'Africa/Cairo',
            Username = uniq + '@example.com.invalid',
            ManagerId = UserInfo.getUserId()
        );
    }

    private static User directReport() {
        return [SELECT Id FROM User WHERE Email = 'meeting.rep@example.com.invalid' LIMIT 1];
    }

    private static String anyRecordType() {
        return MeetingPlannerController.getMeetingRecordTypes()[0].value;
    }

    // Created by the manager and handed over, because a freshly created user holds no
    // field-level security on Meeting__c and so cannot insert one in user mode.
    private static Id pendingMeetingOwnedByReport() {
        Datetime startDt = System.now().addDays(3);
        Id meetingId = MeetingPlannerController.createMeeting(
                anyRecordType(),
                startDt,
                startDt.addHours(2),
                'Report meeting awaiting approval',
                null
            )
            .id;
        update as system new Meeting__c(
            Id = meetingId,
            OwnerId = directReport().Id,
            Status__c = 'PendingApproval'
        );
        return meetingId;
    }

    @IsTest
    static void getPendingMeetingApprovals_listsReportMeeting() {
        Id meetingId = pendingMeetingOwnedByReport();

        Test.startTest();
        List<MeetingApprovalAccess.PendingRow> rows = MeetingPlannerController.getPendingMeetingApprovals();
        Test.stopTest();

        Boolean found = false;
        for (MeetingApprovalAccess.PendingRow row : rows) {
            if (row.meetingId == meetingId) {
                found = true;
            }
        }
        System.assert(found, 'The report meeting should appear in the pending queue.');
    }

    @IsTest
    static void meetingApprovalAccess_coversEmptyAndSelfChecks() {
        System.assertEquals(0, MeetingApprovalAccess.getPendingApprovals(null).size());
        System.assertEquals(false, MeetingApprovalAccess.managesUser(null, UserInfo.getUserId()));
        System.assertEquals(false, MeetingApprovalAccess.managesUser(UserInfo.getUserId(), null));
        System.assertEquals(
            false,
            MeetingApprovalAccess.managesUser(UserInfo.getUserId(), UserInfo.getUserId())
        );
        Id otherId = directReport().Id;
        System.assertEquals(false, MeetingApprovalAccess.managesUser(otherId, UserInfo.getUserId()));
    }

    @IsTest
    static void approveMeetingPlan_approvesReportMeeting() {
        Id meetingId = pendingMeetingOwnedByReport();

        Test.startTest();
        MeetingPlannerController.MeetingSummary approved = MeetingPlannerController.approveMeetingPlan(meetingId);
        Test.stopTest();

        System.assertEquals('Approved', approved.status);
    }

    @IsTest
    static void rejectMeetingPlan_recordsReasonInComments() {
        Id meetingId = pendingMeetingOwnedByReport();

        Test.startTest();
        MeetingPlannerController.MeetingSummary rejected = MeetingPlannerController.rejectMeetingPlan(
            meetingId,
            'Budget not available'
        );
        Test.stopTest();

        System.assertEquals('Rejected', rejected.status);
        System.assert(
            [SELECT Comments__c FROM Meeting__c WHERE Id = :meetingId].Comments__c.contains('Budget not available'),
            'The rejection reason is kept on the meeting.'
        );
    }

    @IsTest
    static void managerActions_rejectInvalidRequests() {
        Id meetingId = pendingMeetingOwnedByReport();
        Integer refused = 0;

        Test.startTest();
        refused += refusedCount(new List<Object>{ 'reject', meetingId, '   ' });
        refused += refusedCount(new List<Object>{ 'approve', null, null });
        refused += refusedCount(new List<Object>{ 'approve', ownMeetingId(), null });
        MeetingPlannerController.approveMeetingPlan(meetingId);
        refused += refusedCount(new List<Object>{ 'approve', meetingId, null });
        Test.stopTest();

        System.assertEquals(4, refused, 'Blank reasons, missing ids, self approval and settled meetings are refused.');
    }

    private static Id ownMeetingId() {
        Datetime startDt = System.now().addDays(5);
        return MeetingPlannerController.createMeeting(
                anyRecordType(),
                startDt,
                startDt.addHours(1),
                'Manager own meeting',
                null
            )
            .id;
    }

    private static Integer refusedCount(List<Object> args) {
        try {
            if (args[0] == 'approve') {
                MeetingPlannerController.approveMeetingPlan((Id) args[1]);
            } else {
                MeetingPlannerController.rejectMeetingPlan((Id) args[1], (String) args[2]);
            }
        } catch (Exception ex) {
            return 1;
        }
        return 0;
    }

    @IsTest
    static void createAndFetchMeeting() {
        List<MeetingPlannerController.RecordTypeOption> types = MeetingPlannerController.getMeetingRecordTypes();
        System.assert(!types.isEmpty(), 'Expected meeting record types');

        String rt = 'Promotional_Activity';
        Boolean found = false;
        for (MeetingPlannerController.RecordTypeOption option : types) {
            if (option.value == rt) {
                found = true;
                break;
            }
        }
        if (!found) {
            rt = types[0].value;
        }

        Datetime startDt = System.now().addDays(1);
        Datetime endDt = startDt.addHours(2);

        Test.startTest();
        MeetingPlannerController.MeetingSummary created = MeetingPlannerController.createMeeting(
            rt,
            startDt,
            endDt,
            'Calendar create test meeting',
            null
        );
        Test.stopTest();

        System.assertNotEquals(null, created.id);
        System.assertEquals('Draft', created.status);
        System.assertEquals('Calendar create test meeting', created.title);

        Date weekStart = Date.today().toStartOfWeek();
        Date weekEnd = weekStart.addDays(14);
        List<MeetingPlannerController.MeetingSummary> meetings = MeetingPlannerController.fetchMeetings(
            weekStart,
            weekEnd,
            UserInfo.getUserId()
        );
        Boolean foundMeeting = false;
        for (MeetingPlannerController.MeetingSummary row : meetings) {
            if (row.id == created.id) {
                foundMeeting = true;
                break;
            }
        }
        System.assert(foundMeeting, 'Created meeting should appear in fetchMeetings');
    }

    @IsTest
    static void meetingExpenses_validatesAndStores() {
        Datetime startDt = System.now().addDays(2);
        Id meetingId = MeetingPlannerController.createMeeting(
                anyRecordType(),
                startDt,
                startDt.addHours(1),
                'Expense meeting',
                null
            )
            .id;
        Integer refused = 0;
        try {
            MeetingPlannerController.getMeetingExpenses(null);
        } catch (Exception ex) {
            refused++;
        }
        try {
            MeetingPlannerController.addMeetingExpense(null, 'Travel', 10, null);
        } catch (Exception ex) {
            refused++;
        }
        try {
            MeetingPlannerController.addMeetingExpense(meetingId, null, 10, null);
        } catch (Exception ex) {
            refused++;
        }
        try {
            MeetingPlannerController.addMeetingExpense(meetingId, 'Travel', 0, null);
        } catch (Exception ex) {
            refused++;
        }

        Test.startTest();
        MeetingPlannerController.ExpenseRow added = MeetingPlannerController.addMeetingExpense(
            meetingId,
            'Travel',
            125,
            'Taxi'
        );
        List<MeetingPlannerController.ExpenseRow> rows = MeetingPlannerController.getMeetingExpenses(meetingId);
        Test.stopTest();

        System.assertEquals(4, refused);
        System.assertNotEquals(null, added);
        System.assertEquals('Travel', added.type);
        System.assertEquals(125, added.amount);
        System.assertEquals(1, rows.size());
    }
}