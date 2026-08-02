@IsTest
private class EmployeeTimeCardAchievementServiceTest {

    @IsTest
    static void recalculateAchievements_setsPercentFields() {
        Employee_Time_Card__c card = new Employee_Time_Card__c(
            Walk_in_Revenue__c = 5000,
            Walk_in_Revenue_Target__c = 10000,
            Walk_in_Visits__c = 30,
            Walk_in_Visits_Target__c = 60
        );
        insert card;

        Test.startTest();
        EmployeeTimeCardAchievementService.recalculateAchievements(new Set<Id>{ card.Id });
        Test.stopTest();

        card = [
            SELECT Walk_in_Revenue_Ach__c, Walk_in_Visits_Ach__c
            FROM Employee_Time_Card__c
            WHERE Id = :card.Id
        ];
        System.assertEquals(50, card.Walk_in_Revenue_Ach__c);
        System.assertEquals(50, card.Walk_in_Visits_Ach__c);
    }

    @IsTest
    static void invocableProcessesRequests() {
        Employee_Time_Card__c card = new Employee_Time_Card__c(
            Walk_in_Revenue__c = 100,
            Walk_in_Revenue_Target__c = 200,
            Walk_in_Visits__c = 10,
            Walk_in_Visits_Target__c = 20
        );
        insert card;

        EmployeeTimeCardAchievementService.Request req = new EmployeeTimeCardAchievementService.Request();
        req.employeeTimeCardId = card.Id;

        Test.startTest();
        EmployeeTimeCardAchievementService.recalculateAchievementsInvocable(
            new List<EmployeeTimeCardAchievementService.Request>{ req }
        );
        Test.stopTest();

        card = [
            SELECT Walk_in_Revenue_Ach__c, Walk_in_Visits_Ach__c
            FROM Employee_Time_Card__c
            WHERE Id = :card.Id
        ];
        System.assertEquals(50, card.Walk_in_Revenue_Ach__c);
        System.assertEquals(50, card.Walk_in_Visits_Ach__c);
    }
}
