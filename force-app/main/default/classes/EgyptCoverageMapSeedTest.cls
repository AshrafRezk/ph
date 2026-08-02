@IsTest
private class EgyptCoverageMapSeedTest {

    @IsTest
    static void seedCoverageMapData_returnsResult() {
        Test.startTest();
        EgyptCoverageMapSeed.SeedResult result = EgyptCoverageMapSeed.seedCoverageMapData();
        Test.stopTest();

        System.assertNotEquals(null, result);
        System.assert(String.isNotBlank(result.message));
    }
}
