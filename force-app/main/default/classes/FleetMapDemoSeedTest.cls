@IsTest
private class FleetMapDemoSeedTest {
    @IsTest
    static void seedTodayForDefaultReps_returnsMessageWhenNoDemoUsers() {
        Test.startTest();
        FleetMapDemoSeed.SeedResult result = FleetMapDemoSeed.seedTodayForDefaultReps();
        Test.stopTest();

        System.assertNotEquals(null, result.message);
    }
}
