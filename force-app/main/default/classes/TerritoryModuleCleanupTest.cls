@IsTest
private class TerritoryModuleCleanupTest {

    @IsTest
    static void purgeLegacySdoTerritories_removesNonPharmaTerritories() {
        List<Territory2Type> types = [SELECT Id FROM Territory2Type LIMIT 1];
        if (types.isEmpty()) {
            return;
        }

        List<Territory2Model> models = [
            SELECT Id
            FROM Territory2Model
            WHERE DeveloperName = 'Current_FY'
            LIMIT 1
        ];
        if (models.isEmpty()) {
            return;
        }

        Territory2 legacyRoot = new Territory2(
            Name = 'Legacy AMER Test',
            DeveloperName = 'Legacy_AMER_Test',
            Territory2ModelId = models[0].Id,
            Territory2TypeId = types[0].Id
        );
        Territory2 legacyChild = new Territory2(
            Name = 'Legacy US Test',
            DeveloperName = 'Legacy_US_Test',
            Territory2ModelId = models[0].Id,
            Territory2TypeId = types[0].Id
        );
        insert legacyRoot;
        legacyChild.ParentTerritory2Id = legacyRoot.Id;
        insert legacyChild;

        Territory2 pharmaTerritory = new Territory2(
            Name = 'Pharma Cleanup Test',
            DeveloperName = 'Pharma_Cleanup_Test',
            Territory2ModelId = models[0].Id,
            Territory2TypeId = types[0].Id,
            External_ID__c = 'TERR_CLEANUP_TEST'
        );
        insert pharmaTerritory;

        Test.startTest();
        Integer deleted = TerritoryModuleCleanup.purgeLegacySdoTerritories();
        Test.stopTest();

        System.assert(deleted >= 2, 'Expected legacy territories to be deleted.');
        System.assertEquals(
            1,
            [SELECT COUNT() FROM Territory2 WHERE External_ID__c = 'TERR_CLEANUP_TEST'],
            'Pharma territory should remain after cleanup.'
        );
        System.assertEquals(
            0,
            [SELECT COUNT() FROM Territory2 WHERE DeveloperName = 'Legacy_AMER_Test'],
            'Legacy root territory should be deleted.'
        );
    }
}
