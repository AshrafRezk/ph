@IsTest(isParallel=false)
private class TimeOffRequestServiceTest {
    private static DateTime uniqueStart(Integer dayOffset, Integer hour) {
        // Far-future working Mondays to avoid collision with other test classes.
        Date base = Date.newInstance(2027, 3, 1); // Monday
        return DateTime.newInstance(base.addDays(dayOffset), Time.newInstance(hour, 0, 0, 0));
    }

    @IsTest
    static void applyComputedFields_hoursHalfFullAndDays() {
        Date workingDay = Date.newInstance(2027, 3, 1);

        Time_Off_Request__c hoursReq = new Time_Off_Request__c(
            Type__c = 'Training',
            Span_Type__c = 'Hours',
            Span_Duration_Select__c = '4',
            Start_Date_Time__c = DateTime.newInstance(workingDay, Time.newInstance(9, 0, 0, 0))
        );
        TimeOffRequestService.applyComputedFields(hoursReq);
        Assert.areEqual(4, hoursReq.Span_Duration__c);

        Time_Off_Request__c halfReq = new Time_Off_Request__c(
            Type__c = 'Sick',
            Span_Type__c = 'Half_Day',
            Start_Date_Time__c = DateTime.newInstance(workingDay, Time.newInstance(10, 0, 0, 0))
        );
        TimeOffRequestService.applyComputedFields(halfReq);
        Assert.areEqual(0.5, halfReq.Span_Duration__c);

        Time_Off_Request__c daysReq = new Time_Off_Request__c(
            Type__c = 'Business Trip',
            Span_Type__c = 'Days',
            Span_Duration_Select__c = '2',
            Start_Date_Time__c = DateTime.newInstance(workingDay, Time.newInstance(9, 0, 0, 0))
        );
        TimeOffRequestService.applyComputedFields(daysReq);
        Assert.areEqual(2, daysReq.Span_Duration__c);
        Assert.areEqual(Date.newInstance(2027, 3, 2), daysReq.End_Date_Time__c.date());
    }

    @IsTest
    static void createTimeOff_blocksVisitOverlapOnSubmit() {
        Account account = new Account(Name = 'TOT Visit Block 2027');
        insert account;
        DateTime startDt = uniqueStart(7, 10);
        insert new Visit__c(
            Account__c = account.Id,
            Assigned_To__c = UserInfo.getUserId(),
            Start_Date__c = startDt,
            End_Date__c = startDt.addHours(1),
            Visit_Date__c = startDt,
            Status__c = 'Scheduled',
            Visit_Type__c = 'Planned (Automatically)'
        );

        Boolean threw = false;
        Test.startTest();
        try {
            TimeOffRequestController.createTimeOff(
                'Training',
                'Hours',
                '2',
                startDt,
                'conflict test',
                'Submitted for Approval'
            );
        } catch (Exception ex) {
            threw = true;
        }
        Test.stopTest();
        Assert.isTrue(threw, 'Expected visit conflict when submitting TOT');
    }

    @IsTest
    static void officeWork_doesNotBlockVisits() {
        Account account = new Account(Name = 'Office Work Account 2027');
        insert account;
        DateTime startDt = uniqueStart(14, 10);
        insert new Visit__c(
            Account__c = account.Id,
            Assigned_To__c = UserInfo.getUserId(),
            Start_Date__c = startDt,
            End_Date__c = startDt.addHours(1),
            Visit_Date__c = startDt,
            Status__c = 'Scheduled',
            Visit_Type__c = 'Planned (Automatically)'
        );

        Test.startTest();
        TimeOffRequestController.TimeOffRequestRow created = TimeOffRequestController.createTimeOff(
            'Office Work',
            'Full_Day',
            null,
            startDt,
            'office',
            'Submitted for Approval'
        );
        Test.stopTest();
        Assert.isNotNull(created.id);
        Assert.isFalse(TimeOffTypeCatalog.blocksVisits('Office Work'));
    }

    @IsTest
    static void getMyRequests_returnsRows() {
        DateTime startDt = uniqueStart(21, 9);
        TimeOffRequestController.createTimeOff(
            'Annual Leave',
            'Full_Day',
            null,
            startDt,
            'mine',
            'Draft'
        );
        List<TimeOffRequestController.TimeOffRequestRow> rows = TimeOffRequestController.getMyRequests(5);
        Assert.isTrue(rows.size() >= 1);
        Assert.areEqual('Annual Leave', rows[0].typeLabel);
    }

    @IsTest
    static void mendixClosure_updatesStage() {
        DateTime startDt = uniqueStart(28, 9);
        TimeOffRequestController.TimeOffRequestRow created = TimeOffRequestController.createTimeOff(
            'Speaker',
            'Full_Day',
            null,
            startDt,
            'mx',
            'Submitted for Approval'
        );
        MendixSyncService.ClosurePayload payload = new MendixSyncService.ClosurePayload();
        payload.salesforceId = created.id;
        payload.mendixExternalId = 'MX-TEST-1';
        payload.status = 'approved';
        payload.closureDate = Date.today();

        Test.startTest();
        Time_Off_Request__c updated = MendixSyncService.applyClosure(payload);
        Test.stopTest();

        Assert.areEqual('Approved', updated.Stage__c);
        Assert.areEqual('MX-TEST-1', updated.Mendix_External_Id__c);
    }

    @IsTest
    static void typeCatalog_hasAgreedTypes() {
        Assert.isTrue(TimeOffTypeCatalog.isKnownType('Annual Leave'));
        Assert.isTrue(TimeOffTypeCatalog.isKnownType('Holiday'));
        Assert.isTrue(TimeOffTypeCatalog.isKnownType('Annual Vacation'));
        Assert.areEqual('ANNUAL_LEAVE', TimeOffTypeCatalog.mendixCode('Annual Leave'));
        Assert.areEqual(19, TimeOffTypeCatalog.UI_TYPE_VALUES.size());
    }

    @IsTest
    static void approvalAccess_andRecall_andSyncStatus() {
        DateTime startDt = uniqueStart(35, 9);
        TimeOffRequestController.TimeOffRequestRow created = TimeOffRequestController.createTimeOff(
            'Training',
            'Full_Day',
            null,
            startDt,
            'pending',
            'Submitted for Approval'
        );

        Test.startTest();
        Assert.isNotNull(MendixSyncService.getIntegrationStatus());
        Assert.isNotNull(MendixSyncService.getRecentSyncLogs());
        Assert.isNotNull(TimeOffRequestController.getPendingApprovals());
        Assert.isNotNull(TimeOffRequestApprovalAccess.getPendingApprovals(UserInfo.getUserId()));

        TimeOffRequestTotRecalcAction.recalcForRange(null);
        TimeOffRequestTotRecalcAction.RecalcRequest recalc = new TimeOffRequestTotRecalcAction.RecalcRequest();
        recalc.employeeId = UserInfo.getUserId();
        recalc.startDate = startDt.date();
        recalc.endDate = startDt.date();
        TimeOffRequestTotRecalcAction.recalcForRange(
            new List<TimeOffRequestTotRecalcAction.RecalcRequest>{ recalc }
        );

        Boolean approveBlocked = false;
        try {
            TimeOffRequestController.approveRequest(created.id);
        } catch (Exception ex) {
            approveBlocked = true;
            Assert.isTrue(String.isNotBlank(ex.getMessage()));
        }
        Assert.isTrue(approveBlocked);

        Boolean rejectBlankBlocked = false;
        try {
            TimeOffRequestApprovalAccess.rejectRequest(created.id, UserInfo.getUserId(), '');
        } catch (Exception ex) {
            rejectBlankBlocked = true;
        }
        Assert.isTrue(rejectBlankBlocked);

        Boolean rejectBlocked = false;
        try {
            TimeOffRequestController.rejectRequest(created.id, 'test reject');
        } catch (Exception ex) {
            rejectBlocked = true;
            Assert.isTrue(String.isNotBlank(ex.getMessage()));
        }
        Assert.isTrue(rejectBlocked);

        TimeOffRequestController.recallRequest(created.id);
        Test.stopTest();

        Time_Off_Request__c recalled = [
            SELECT Stage__c
            FROM Time_Off_Request__c
            WHERE Id = :created.id
        ];
        Assert.areEqual('Draft', recalled.Stage__c);
    }

    @IsTest
    static void createTimeOff_validationPaths() {
        DateTime startDt = uniqueStart(56, 9);
        Boolean blankType = false;
        try {
            TimeOffRequestController.createTimeOff(null, 'Full_Day', null, startDt, null, 'Draft');
        } catch (Exception ex) {
            blankType = true;
        }
        Assert.isTrue(blankType);

        Boolean badType = false;
        try {
            TimeOffRequestController.createTimeOff('NotARealType', 'Full_Day', null, startDt, null, 'Draft');
        } catch (Exception ex) {
            badType = true;
        }
        Assert.isTrue(badType);

        Boolean blankSpan = false;
        try {
            TimeOffRequestController.createTimeOff('Training', null, null, startDt, null, 'Draft');
        } catch (Exception ex) {
            blankSpan = true;
        }
        Assert.isTrue(blankSpan);

        Boolean hoursNeedDuration = false;
        try {
            TimeOffRequestController.createTimeOff('Training', 'Hours', null, startDt, null, 'Draft');
        } catch (Exception ex) {
            hoursNeedDuration = true;
        }
        Assert.isTrue(hoursNeedDuration);

        Boolean daysNeedDuration = false;
        try {
            TimeOffRequestController.createTimeOff('Training', 'Days', null, startDt, null, 'Draft');
        } catch (Exception ex) {
            daysNeedDuration = true;
        }
        Assert.isTrue(daysNeedDuration);

        TimeOffRequestController.TimeOffRequestRow halfRow = TimeOffRequestController.createTimeOff(
            'Sick',
            'Half_Day',
            null,
            startDt.addDays(7),
            'half ok',
            'Draft'
        );
        Assert.isNotNull(halfRow.id);
        Assert.areEqual(0.5, halfRow.workingDays);
    }

    @IsTest
    static void managerApproveAndReject_success() {
        Profile adminProfile = [SELECT Id FROM Profile WHERE Id = :UserInfo.getProfileId()];
        String suffix = String.valueOf(Math.abs(Crypto.getRandomInteger()));
        User managerUser = new User(
            Alias = 'tmgr',
            Email = 'tot.mgr.' + suffix + '@example.com',
            EmailEncodingKey = 'UTF-8',
            LastName = 'TotMgr',
            LanguageLocaleKey = 'en_US',
            LocaleSidKey = 'en_US',
            ProfileId = adminProfile.Id,
            TimeZoneSidKey = 'America/Los_Angeles',
            Username = 'tot.mgr.' + suffix + '@example.com'
        );
        insert managerUser;

        User me = [
            SELECT Id, ManagerId
            FROM User
            WHERE Id = :UserInfo.getUserId()
        ];
        Id previousManager = me.ManagerId;
        me.ManagerId = managerUser.Id;
        update me;

        Test.startTest();
        Id approveId = TimeOffRequestController.createTimeOff(
            'Training',
            'Full_Day',
            null,
            uniqueStart(70, 9),
            'approve me',
            'Submitted for Approval'
        ).id;
        Id rejectId = TimeOffRequestController.createTimeOff(
            'Training',
            'Full_Day',
            null,
            uniqueStart(71, 9),
            'reject me',
            'Submitted for Approval'
        ).id;

        List<TimeOffRequestController.ApprovalRow> pending =
            TimeOffRequestApprovalAccess.getPendingApprovals(managerUser.Id);
        Assert.isTrue(pending.size() >= 2);
        TimeOffRequestApprovalAccess.approveRequest(approveId, managerUser.Id);
        TimeOffRequestApprovalAccess.rejectRequest(rejectId, managerUser.Id, 'no balance');
        Test.stopTest();

        Map<Id, Time_Off_Request__c> byId = new Map<Id, Time_Off_Request__c>([
            SELECT Stage__c, Rejection_Reason__c
            FROM Time_Off_Request__c
            WHERE Id IN :new Set<Id>{ approveId, rejectId }
        ]);
        Assert.areEqual('Approved', byId.get(approveId).Stage__c);
        Assert.areEqual('Rejected', byId.get(rejectId).Stage__c);
        Assert.areEqual('no balance', byId.get(rejectId).Rejection_Reason__c);

        me.ManagerId = previousManager;
        update me;
    }

    @IsTest
    static void createHours_partialTot() {
        DateTime startDt = uniqueStart(49, 11);
        try {
            Test.startTest();
            TimeOffRequestController.TimeOffRequestRow created = TimeOffRequestController.createTimeOff(
                'Training',
                'Hours',
                '4',
                startDt,
                'hours ok',
                'Draft'
            );
            Test.stopTest();
            Assert.isNotNull(created.id);
            Assert.areEqual(0.5, created.workingDays);
        } catch (Exception ex) {
            Assert.fail('Hours create failed: ' + ex.getMessage());
        }
    }

    @IsTest
    static void restClosure_rejects() {
        DateTime startDt = uniqueStart(42, 9);
        TimeOffRequestController.TimeOffRequestRow created = TimeOffRequestController.createTimeOff(
            'Sick',
            'Half_Day',
            null,
            startDt,
            'rest',
            'Submitted for Approval'
        );

        MendixSyncService.ClosurePayload payload = new MendixSyncService.ClosurePayload();
        payload.salesforceId = created.id;
        payload.mendixExternalId = 'MX-REST-2';
        payload.status = 'rejected';
        payload.rejectionReason = 'Insufficient balance';
        payload.closureDate = Date.today();

        Test.startTest();
        Time_Off_Request__c updated = MendixSyncService.applyClosure(payload);
        Test.stopTest();

        Assert.areEqual('Rejected', updated.Stage__c);
        Assert.areEqual('Insufficient balance', updated.Rejection_Reason__c);
    }
}