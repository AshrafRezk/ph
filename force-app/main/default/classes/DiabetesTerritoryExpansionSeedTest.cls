@IsTest
private class DiabetesTerritoryExpansionSeedTest {

    @IsTest
    static void seedDiabetesLinesAndDistricts_isNoOpForChemipharm() {
        Test.startTest();
        DiabetesTerritoryExpansionSeed.SeedResult result =
            DiabetesTerritoryExpansionSeed.seedDiabetesLinesAndDistricts();
        Test.stopTest();

        System.assertEquals(0, result.territoriesCreated);
        System.assertNotEquals(null, result.message);
        System.assert(result.message.contains('Skipped'), result.message);
    }
}
