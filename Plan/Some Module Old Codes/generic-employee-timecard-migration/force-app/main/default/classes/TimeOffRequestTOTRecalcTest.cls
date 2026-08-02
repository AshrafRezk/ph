@IsTest
private class TimeOffRequestTOTRecalcTest {
    @IsTest
    static void recalcTOTForTimeOffRequest_invocable_runs() {
        Profile admin = [SELECT Id FROM Profile WHERE Name = 'System Administrator' LIMIT 1];
        String suffix = String.valueOf(Crypto.getRandomInteger());
        User u = new User(
            Alias = 'trec',
            Email = 'trec' + suffix + '@example.com',
            EmailEncodingKey = 'UTF-8',
            LastName = 'TRec',
            LanguageLocaleKey = 'en_US',
            LocaleSidKey = 'en_US',
            TimeZoneSidKey = 'America/Los_Angeles',
            UserName = 'trec' + suffix + '@example.com.test',
            ProfileId = admin.Id
        );
        insert u;
        Time_Off_Request__c tor;
        System.runAs(u) {
            Datetime startDt = Datetime.newInstance(2026, 6, 10, 9, 0, 0);
            tor = new Time_Off_Request__c(
                Type__c = 'Holiday',
                Start_Date_Time__c = startDt,
                Span_Type__c = 'Hours',
                Span_Duration__c = 2,
                Stage__c = 'Draft'
            );
            insert tor;
        }
        TimeOffRequestTOTRecalc.RecalcTOTRequest in0 = new TimeOffRequestTOTRecalc.RecalcTOTRequest();
        in0.timeOffRequestId = tor.Id;
        Test.startTest();
        TimeOffRequestTOTRecalc.recalcTOTForTimeOffRequest(new List<TimeOffRequestTOTRecalc.RecalcTOTRequest>{ in0 });
        Test.stopTest();
    }

    @IsTest
    static void recalcTOTForDateRange_invocable_runs() {
        TimeOffRequestTOTRecalcByRange.RecalcTOTByRangeRequest in0 = new TimeOffRequestTOTRecalcByRange.RecalcTOTByRangeRequest();
        in0.userId = UserInfo.getUserId();
        in0.startDateTime = Datetime.newInstance(2026, 6, 1, 0, 0, 0);
        in0.endDateTime = Datetime.newInstance(2026, 6, 5, 0, 0, 0);
        Test.startTest();
        TimeOffRequestTOTRecalcByRange.recalcTOTForDateRange(
            new List<TimeOffRequestTOTRecalcByRange.RecalcTOTByRangeRequest>{ in0 }
        );
        Test.stopTest();
    }
}