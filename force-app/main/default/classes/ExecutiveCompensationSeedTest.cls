@IsTest
private class ExecutiveCompensationSeedTest {

    @IsTest
    static void seedCurrentMonthCompensation_runsWithoutError() {
        Test.startTest();
        ExecutiveCompensationSeed.SeedResult result =
            ExecutiveCompensationSeed.seedCurrentMonthCompensation();
        Test.stopTest();

        System.assertNotEquals(null, result.message);
    }

    @IsTest
    static void resolveSalaryForUser_returnsRoleDefaults() {
        System.assertEquals(30000, ExecutiveCompensationSeed.resolveSalaryForUser(UserInfo.getUserId(), 'District Manager'));
        System.assertEquals(18000, ExecutiveCompensationSeed.resolveSalaryForUser(UserInfo.getUserId(), 'Medical Rep'));
    }
}
