@IsTest
private class CoachingModuleSeedTest {
    @IsTest
    static void testSeedDemoData() {
        Test.startTest();
        CoachingModuleSeed.SeedResult result = CoachingModuleSeed.seedDemoData(null, null);
        Test.stopTest();

        System.assertNotEquals(null, result.templateId);
        System.assertNotEquals(null, result.eventId);

        Coaching_Template__c template = [
            SELECT Questions_JSON__c FROM Coaching_Template__c WHERE Id = :result.templateId
        ];
        System.assert(template.Questions_JSON__c.contains('Enthusiasm'));

        Coaching_Event__c event = [
            SELECT Manager_Total_Score__c, Responses_JSON__c
            FROM Coaching_Event__c
            WHERE Id = :result.eventId
        ];
        System.assertNotEquals(null, event.Responses_JSON__c);
    }
}
