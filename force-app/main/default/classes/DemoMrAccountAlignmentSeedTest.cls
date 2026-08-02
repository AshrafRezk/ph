@IsTest
private class DemoMrAccountAlignmentSeedTest {

    @IsTest
    static void alignAllMrAccounts_returnsResultMessage() {
        Test.startTest();
        DemoMrAccountAlignmentSeed.SeedResult result = DemoMrAccountAlignmentSeed.alignAllMrAccounts();
        Test.stopTest();

        System.assertNotEquals(null, result);
        System.assert(String.isNotBlank(result.message));
    }
}
