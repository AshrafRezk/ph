@IsTest
private class TimeOffRequestApprovalAccessTest {
    private static DateTime uniqueStart(Integer dayOffset, Integer hour) {
        Date base = Date.newInstance(2027, 6, 7); // Monday
        return DateTime.newInstance(base.addDays(dayOffset), Time.newInstance(hour, 0, 0, 0));
    }

    private static User createUser(String label) {
        String suffix = String.valueOf(Math.abs(Crypto.getRandomInteger()));
        User u = new User(
            Alias = label.left(8),
            Email = 'tora.' + label + '.' + suffix + '@example.com',
            EmailEncodingKey = 'UTF-8',
            LastName = label,
            LanguageLocaleKey = 'en_US',
            LocaleSidKey = 'en_US',
            ProfileId = UserInfo.getProfileId(),
            TimeZoneSidKey = 'America/Los_Angeles',
            Username = 'tora.' + label + '.' + suffix + '@example.com'
        );
        insert u;
        return u;
    }

    private static Id submitRequest(Integer dayOffset) {
        return TimeOffRequestController.createTimeOff(
            'Training',
            'Full_Day',
            null,
            uniqueStart(dayOffset, 9),
            'approval access',
            'Submitted for Approval'
        ).id;
    }

    private static Boolean approveThrows(Id requestId, Id managerId) {
        try {
            TimeOffRequestApprovalAccess.approveRequest(requestId, managerId);
            return false;
        } catch (AuraHandledException e) {
            return true;
        }
    }

    private static Boolean rejectThrows(Id requestId, Id managerId, String reason) {
        try {
            TimeOffRequestApprovalAccess.rejectRequest(requestId, managerId, reason);
            return false;
        } catch (AuraHandledException e) {
            return true;
        }
    }

    @IsTest
    static void managerSeesAndActsOnDirectReportRequests() {
        User managerUser = createUser('toraMgr');
        User me = [SELECT Id, ManagerId FROM User WHERE Id = :UserInfo.getUserId()];
        me.ManagerId = managerUser.Id;
        update me;

        Test.startTest();
        Id approveId = submitRequest(0);
        Id rejectId = submitRequest(1);
        List<TimeOffRequestController.ApprovalRow> pending =
            TimeOffRequestApprovalAccess.getPendingApprovals(managerUser.Id);
        approveThrows(approveId, managerUser.Id);
        Boolean blankReasonThrew = rejectThrows(rejectId, managerUser.Id, '  ');
        rejectThrows(rejectId, managerUser.Id, 'no balance');
        Test.stopTest();

        Assert.isTrue(pending.size() >= 2, 'Manager should see submitted requests from direct reports');
        Assert.isTrue(blankReasonThrew, 'Rejection reason is required');
    }

    @IsTest
    static void unrelatedUserIsDenied() {
        User stranger = createUser('toraOut');

        Test.startTest();
        Id requestId = submitRequest(2);
        List<TimeOffRequestController.ApprovalRow> pending =
            TimeOffRequestApprovalAccess.getPendingApprovals(stranger.Id);
        Boolean approveThrew = approveThrows(requestId, stranger.Id);
        Boolean rejectThrew = rejectThrows(requestId, stranger.Id, 'nope');
        Boolean missingIdThrew = approveThrows(null, stranger.Id);
        Test.stopTest();

        Assert.isTrue(pending.isEmpty(), 'Unrelated user should not see the request');
        Assert.isTrue(approveThrew, 'Unrelated user cannot approve');
        Assert.isTrue(rejectThrew, 'Unrelated user cannot reject');
        Assert.isTrue(missingIdThrew, 'Request Id is required');
        Assert.areEqual(
            'Submitted for Approval',
            [SELECT Stage__c FROM Time_Off_Request__c WHERE Id = :requestId].Stage__c
        );
        Assert.isTrue(TimeOffRequestApprovalAccess.getPendingApprovals(null).isEmpty());
    }
}