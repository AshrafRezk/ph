@IsTest
private class TimeOffRequestBulkApprovalTest {

    @IsTest
    static void bulkApprove_emptyIds_returnsMessage() {
        TimeOffRequestBulkApprove.Input in0 = new TimeOffRequestBulkApprove.Input();
        in0.recordIds = new List<String>();
        List<TimeOffRequestBulkApprove.Output> res = TimeOffRequestBulkApprove.bulkApprove(
            new List<TimeOffRequestBulkApprove.Input>{ in0 }
        );
        System.assertEquals(0, res[0].processedCount);
        System.assertEquals(0, res[0].skippedCount);
        System.assertNotEquals(null, res[0].message);
    }

    @IsTest
    static void bulkApprove_nullInput() {
        List<TimeOffRequestBulkApprove.Output> res = TimeOffRequestBulkApprove.bulkApprove(null);
        System.assertEquals(1, res.size());
        System.assertEquals('No input.', res[0].message);
    }

    @IsTest
    static void bulkReject_blankReason_marksSkipped() {
        TimeOffRequestBulkReject.Input in0 = new TimeOffRequestBulkReject.Input();
        in0.recordIds = new List<String>{ String.valueOf(UserInfo.getUserId()) };
        in0.rejectionReason = '   ';
        List<TimeOffRequestBulkReject.Output> res = TimeOffRequestBulkReject.bulkReject(
            new List<TimeOffRequestBulkReject.Input>{ in0 }
        );
        System.assertEquals(0, res[0].processedCount);
        System.assertEquals(1, res[0].skippedCount);
        System.assert(res[0].message.contains('required'));
    }

    @IsTest
    static void bulkReject_nullInput() {
        List<TimeOffRequestBulkReject.Output> res = TimeOffRequestBulkReject.bulkReject(null);
        System.assertEquals('No input.', res[0].message);
    }

    @IsTest
    static void mergeIdInputs_mergesListAndSingle() {
        String uid = UserInfo.getUserId();
        List<String> a = TimeOffRequestBulkApproval.mergeIdInputs(new List<String>{ uid }, null);
        System.assertEquals(1, a.size());
        List<String> b = TimeOffRequestBulkApproval.mergeIdInputs(null, uid);
        System.assertEquals(1, b.size());
    }

    @IsTest
    static void runApprove_wrongObjectId_noRows() {
        TimeOffRequestBulkApproval.Result r = TimeOffRequestBulkApproval.runApprove(
            new List<String>{ UserInfo.getUserId() }
        );
        System.assertEquals(0, r.processedCount);
        System.assertEquals(0, r.skippedCount);
    }

    @IsTest
    static void runApprove_managerApprovesSubmittedRequest() {
        Profile admin = [SELECT Id FROM Profile WHERE Name = 'System Administrator' LIMIT 1];
        String suffix = String.valueOf(Crypto.getRandomInteger());
        User mgr = new User(
            Alias = 'tmgr',
            Email = 'tmgr' + suffix + '@example.com',
            EmailEncodingKey = 'UTF-8',
            LastName = 'TestMgr',
            LanguageLocaleKey = 'en_US',
            LocaleSidKey = 'en_US',
            TimeZoneSidKey = 'America/Los_Angeles',
            UserName = 'tmgr' + suffix + '@example.com.test',
            ProfileId = admin.Id
        );
        insert mgr;
        User sub = new User(
            Alias = 'tsub',
            Email = 'tsub' + suffix + '@example.com',
            EmailEncodingKey = 'UTF-8',
            LastName = 'TestSub',
            LanguageLocaleKey = 'en_US',
            LocaleSidKey = 'en_US',
            TimeZoneSidKey = 'America/Los_Angeles',
            UserName = 'tsub' + suffix + '@example.com.test',
            ProfileId = admin.Id,
            ManagerId = mgr.Id
        );
        insert sub;
        Time_Off_Request__c tor;
        System.runAs(sub) {
            Datetime startDt = System.now();
            tor = new Time_Off_Request__c(
                Type__c = 'Holiday',
                Start_Date_Time__c = startDt,
                Span_Type__c = 'Hours',
                Span_Duration_Select__c = '4',
                Stage__c = 'Draft'
            );
            insert tor;
            tor.Stage__c = 'Submitted for Approval';
            update tor;
        }
        System.runAs(mgr) {
            TimeOffRequestBulkApproval.Result r = TimeOffRequestBulkApproval.runApprove(
                new List<String>{ tor.Id }
            );
            System.assertEquals(1, r.processedCount, r.message);
            System.assertEquals(0, r.skippedCount, r.message);
        }
        tor = [SELECT Stage__c FROM Time_Off_Request__c WHERE Id = :tor.Id];
        System.assertEquals('Approved', tor.Stage__c);
    }

    @IsTest
    static void runApprove_skipsNonSubmittedStage() {
        Profile admin = [SELECT Id FROM Profile WHERE Name = 'System Administrator' LIMIT 1];
        String suffix = String.valueOf(Crypto.getRandomInteger());
        User mgr = new User(
            Alias = 'tm2',
            Email = 'tm2' + suffix + '@example.com',
            EmailEncodingKey = 'UTF-8',
            LastName = 'TestMgr2',
            LanguageLocaleKey = 'en_US',
            LocaleSidKey = 'en_US',
            TimeZoneSidKey = 'America/Los_Angeles',
            UserName = 'tm2' + suffix + '@example.com.test',
            ProfileId = admin.Id
        );
        insert mgr;
        User sub = new User(
            Alias = 'ts2',
            Email = 'ts2' + suffix + '@example.com',
            EmailEncodingKey = 'UTF-8',
            LastName = 'TestSub2',
            LanguageLocaleKey = 'en_US',
            LocaleSidKey = 'en_US',
            TimeZoneSidKey = 'America/Los_Angeles',
            UserName = 'ts2' + suffix + '@example.com.test',
            ProfileId = admin.Id,
            ManagerId = mgr.Id
        );
        insert sub;
        Time_Off_Request__c tor;
        System.runAs(sub) {
            Datetime startDt = System.now();
            tor = new Time_Off_Request__c(
                Type__c = 'Holiday',
                Start_Date_Time__c = startDt,
                Span_Type__c = 'Hours',
                Span_Duration_Select__c = '4',
                Stage__c = 'Draft'
            );
            insert tor;
        }
        System.runAs(mgr) {
            TimeOffRequestBulkApproval.Result r = TimeOffRequestBulkApproval.runApprove(
                new List<String>{ tor.Id }
            );
            System.assertEquals(0, r.processedCount);
            System.assertEquals(1, r.skippedCount);
        }
    }

    @IsTest
    static void runReject_managerRejectsWithReason() {
        Profile admin = [SELECT Id FROM Profile WHERE Name = 'System Administrator' LIMIT 1];
        String suffix = String.valueOf(Crypto.getRandomInteger());
        User mgr = new User(
            Alias = 'tm3',
            Email = 'tm3' + suffix + '@example.com',
            EmailEncodingKey = 'UTF-8',
            LastName = 'TestMgr3',
            LanguageLocaleKey = 'en_US',
            LocaleSidKey = 'en_US',
            TimeZoneSidKey = 'America/Los_Angeles',
            UserName = 'tm3' + suffix + '@example.com.test',
            ProfileId = admin.Id
        );
        insert mgr;
        User sub = new User(
            Alias = 'ts3',
            Email = 'ts3' + suffix + '@example.com',
            EmailEncodingKey = 'UTF-8',
            LastName = 'TestSub3',
            LanguageLocaleKey = 'en_US',
            LocaleSidKey = 'en_US',
            TimeZoneSidKey = 'America/Los_Angeles',
            UserName = 'ts3' + suffix + '@example.com.test',
            ProfileId = admin.Id,
            ManagerId = mgr.Id
        );
        insert sub;
        Time_Off_Request__c tor;
        System.runAs(sub) {
            Datetime startDt = System.now();
            tor = new Time_Off_Request__c(
                Type__c = 'Holiday',
                Start_Date_Time__c = startDt,
                Span_Type__c = 'Hours',
                Span_Duration_Select__c = '4',
                Stage__c = 'Draft'
            );
            insert tor;
            tor.Stage__c = 'Submitted for Approval';
            update tor;
        }
        System.runAs(mgr) {
            TimeOffRequestBulkApproval.Result r = TimeOffRequestBulkApproval.runReject(
                new List<String>{ tor.Id },
                'Coverage reason'
            );
            System.assertEquals(1, r.processedCount, r.message);
        }
        tor = [SELECT Stage__c, Rejection_Reason__c FROM Time_Off_Request__c WHERE Id = :tor.Id];
        System.assertEquals('Rejected', tor.Stage__c);
        System.assertEquals('Coverage reason', tor.Rejection_Reason__c);
    }
}