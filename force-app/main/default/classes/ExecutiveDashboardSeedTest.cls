@IsTest
private class ExecutiveDashboardSeedTest {

    @IsTest
    static void seedCurrentMonthExecutiveMetrics_runsWithoutError() {
        Test.startTest();
        ExecutiveDashboardSeed.SeedResult result = ExecutiveDashboardSeed.seedCurrentMonthExecutiveMetrics();
        Test.stopTest();

        System.assertNotEquals(null, result.message);
    }

    @IsTest
    static void seedDemoVisitProductDetailsForReps_runsWithoutError() {
        Test.startTest();
        ExecutiveDashboardSeed.SeedResult result = ExecutiveDashboardSeed.seedDemoVisitProductDetailsForReps(
            new List<String>{ 'git_mr' }
        );
        Test.stopTest();

        System.assertNotEquals(null, result.message);
    }
}
