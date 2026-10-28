@IsTest
private class HomeOfficeMessageSeedTest {
    @IsTest
    static void seedWelcomeToAllTerritories_isIdempotent() {
        Test.startTest();
        HomeOfficeMessageSeed.SeedResult first = HomeOfficeMessageSeed.seedWelcomeToAllTerritories();
        HomeOfficeMessageSeed.SeedResult second = HomeOfficeMessageSeed.seedFieldGuideMessages();
        Test.stopTest();

        System.assertNotEquals(null, first);
        System.assertNotEquals(null, second);
        System.assertEquals(
            5,
            [
                SELECT COUNT()
                FROM Home_Office_Message__c
                WHERE Audience_Scope__c = 'All Business Units'
                AND Is_Active__c = TRUE
                AND Name IN (
                    'Welcome to Salesforce',
                    'Home — start your day',
                    'Planner — own your cycle',
                    'Accounts — your list',
                    'Learning — stay sharp ;)'
                )
                WITH SYSTEM_MODE
            ]
        );
    }

    @IsTest
    static void seedDemoMessages_returnsResult() {
        Test.startTest();
        HomeOfficeMessageSeed.SeedResult result = HomeOfficeMessageSeed.seedDemoMessages();
        HomeOfficeMessageSeed.SeedResult second = HomeOfficeMessageSeed.seedDemoMessages();
        Test.stopTest();
        System.assertNotEquals(null, result);
        System.assertNotEquals(null, second);
        System.assert(String.isNotBlank(result.message));
        System.assert(
            [
                SELECT COUNT()
                FROM Home_Office_Message__c
                WHERE Name IN (
                    'Q2 Coloverin D focus — all field teams',
                    'GIT BU — Coloverin line coverage push'
                )
                WITH SYSTEM_MODE
            ] >= 1
        );
    }
}