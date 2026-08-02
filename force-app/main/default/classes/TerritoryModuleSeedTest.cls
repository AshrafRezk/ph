@IsTest
private class TerritoryModuleSeedTest {

    @IsTest
    static void seedTerritoriesAndUsers_createsHierarchy() {
        List<Territory2Type> types = [SELECT Id FROM Territory2Type LIMIT 1];
        if (types.isEmpty()) {
            return;
        }

        Test.startTest();
        TerritoryModuleSeed.SeedResult result = TerritoryModuleSeed.seedTerritoriesAndUsers();
        Test.stopTest();

        System.assertNotEquals(null, result.modelId);
        System.assert(result.territoryIdsByExtId.containsKey('TERR_HEAD_OFFICE'));
        System.assert(result.territoryIdsByExtId.containsKey('TERR_GIT_DM_1_MR_1'));
    }

    @IsTest
    static void buildUserSpecs_usesZetaDemoNames() {
        ChemipharmDemoDataProfiles.DemoUserProfile profile = ChemipharmDemoDataProfiles.getUserProfile('diabetes_mr');
        System.assertEquals('Fatma', profile.firstName);
        System.assertEquals('Fawzy Mohamed Mahmoud', profile.lastName);
    }
}
