@IsTest
private class AccountAffiliationModuleSeedTest {

    @IsTest
    static void seedDemoData_createsSampleAccountsWhenTerritoriesExist() {
        List<Territory2Type> types = [SELECT Id FROM Territory2Type LIMIT 1];
        if (types.isEmpty()) {
            return;
        }

        List<Territory2> existingTerritories = [
            SELECT Id
            FROM Territory2
            WHERE External_ID__c = 'TERR_GIT_DM_1_MR_1'
            LIMIT 1
        ];
        if (existingTerritories.isEmpty()) {
            Territory2Model model = [
                SELECT Id
                FROM Territory2Model
                WHERE DeveloperName = 'Current_FY'
                LIMIT 1
            ];
            insert new Territory2(
                Name = 'Test MR Territory',
                DeveloperName = 'Test_MR_Territory',
                Territory2ModelId = model.Id,
                Territory2TypeId = types[0].Id,
                External_ID__c = 'TERR_GIT_DM_1_MR_1'
            );
        }

        Test.startTest();
        AccountAffiliationModuleSeed.SeedResult result = AccountAffiliationModuleSeed.seedDemoData();
        Test.stopTest();

        System.assertNotEquals(null, result.message);
        Integer demoAccounts = [
            SELECT COUNT()
            FROM Account
            WHERE External_ID__c LIKE 'DEMO_%'
        ];
        System.assert(demoAccounts > 0, 'Expected demo accounts to be created');
    }
}
