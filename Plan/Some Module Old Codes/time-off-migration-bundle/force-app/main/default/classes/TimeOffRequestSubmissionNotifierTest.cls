@IsTest
private class TimeOffRequestSubmissionNotifierTest {
    @IsTest
    static void notifyManagers_noThrowWhenNoManager() {
        Profile admin = [SELECT Id FROM Profile WHERE Name = 'System Administrator' LIMIT 1];
        String suffix = String.valueOf(Crypto.getRandomInteger());
        User lone = new User(
            Alias = 'tlone',
            Email = 'tlone' + suffix + '@example.com',
            EmailEncodingKey = 'UTF-8',
            LastName = 'Lone',
            LanguageLocaleKey = 'en_US',
            LocaleSidKey = 'en_US',
            TimeZoneSidKey = 'America/Los_Angeles',
            UserName = 'tlone' + suffix + '@example.com.test',
            ProfileId = admin.Id
        );
        insert lone;
        Time_Off_Request__c tor;
        System.runAs(lone) {
            Datetime startDt = System.now();
            tor = new Time_Off_Request__c(
                Type__c = 'Holiday',
                Start_Date_Time__c = startDt,
                Span_Type__c = 'Hours',
                Span_Duration__c = 4,
                Stage__c = 'Draft'
            );
            insert tor;
        }
        TimeOffRequestSubmissionNotifier.Input in0 = new TimeOffRequestSubmissionNotifier.Input();
        in0.timeOffRequestId = tor.Id;
        Test.startTest();
        TimeOffRequestSubmissionNotifier.notifyManagers(new List<TimeOffRequestSubmissionNotifier.Input>{ in0 });
        Test.stopTest();
    }

    @IsTest
    static void notifyManagers_withManager_runs() {
        Profile admin = [SELECT Id FROM Profile WHERE Name = 'System Administrator' LIMIT 1];
        String suffix = String.valueOf(Crypto.getRandomInteger());
        User mgr = new User(
            Alias = 'nmgr',
            Email = 'nmgr' + suffix + '@example.com',
            EmailEncodingKey = 'UTF-8',
            LastName = 'NMgr',
            LanguageLocaleKey = 'en_US',
            LocaleSidKey = 'en_US',
            TimeZoneSidKey = 'America/Los_Angeles',
            UserName = 'nmgr' + suffix + '@example.com.test',
            ProfileId = admin.Id
        );
        insert mgr;
        User sub = new User(
            Alias = 'nsub',
            Email = 'nsub' + suffix + '@example.com',
            EmailEncodingKey = 'UTF-8',
            LastName = 'NSub',
            LanguageLocaleKey = 'en_US',
            LocaleSidKey = 'en_US',
            TimeZoneSidKey = 'America/Los_Angeles',
            UserName = 'nsub' + suffix + '@example.com.test',
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
                Span_Duration__c = 2,
                Stage__c = 'Draft'
            );
            insert tor;
        }
        TimeOffRequestSubmissionNotifier.Input in0 = new TimeOffRequestSubmissionNotifier.Input();
        in0.timeOffRequestId = tor.Id;
        Test.startTest();
        TimeOffRequestSubmissionNotifier.notifyManagers(new List<TimeOffRequestSubmissionNotifier.Input>{ in0 });
        Test.stopTest();
    }
}