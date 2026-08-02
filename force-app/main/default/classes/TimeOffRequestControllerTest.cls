@IsTest
private class TimeOffRequestControllerTest {

    @IsTest
    static void getMyRequests_returnsCurrentUserRecords() {
        Datetime startDt = System.now().addDays(7);
        Time_Off_Request__c request = new Time_Off_Request__c(
            Type__c = 'Holiday',
            Start_Date_Time__c = startDt,
            Span_Type__c = 'Hours',
            Span_Duration_Select__c = '4',
            Stage__c = 'Draft'
        );
        insert request;

        Test.startTest();
        List<TimeOffRequestController.RequestSummary> results =
            TimeOffRequestController.getMyRequests(5);
        Test.stopTest();

        System.assert(!results.isEmpty(), 'Expected at least one request');
        System.assertEquals(request.Id, results[0].id);
        System.assertEquals('Holiday', results[0].typeLabel);
        System.assertEquals('Draft', results[0].stage);
    }

    @IsTest
    static void getMyRequests_respectsLimit() {
        Datetime startDt = System.now().addDays(14);
        insert new List<Time_Off_Request__c>{
            new Time_Off_Request__c(
                Type__c = 'Holiday',
                Start_Date_Time__c = startDt,
                Span_Type__c = 'Hours',
                Span_Duration_Select__c = '2',
                Stage__c = 'Draft'
            ),
            new Time_Off_Request__c(
                Type__c = 'Sick Leave',
                Start_Date_Time__c = startDt.addDays(1),
                Span_Type__c = 'Hours',
                Span_Duration_Select__c = '3',
                Stage__c = 'Draft'
            )
        };

        List<TimeOffRequestController.RequestSummary> results =
            TimeOffRequestController.getMyRequests(1);

        System.assertEquals(1, results.size());
    }
}
