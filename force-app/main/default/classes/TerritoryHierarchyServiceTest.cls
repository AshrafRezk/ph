@IsTest
private class TerritoryHierarchyServiceTest {

    @IsTest
    static void resolveHierarchyLabels_skipsHeadOfficeForBusinessUnit() {
        List<Territory2Type> types = [SELECT Id FROM Territory2Type LIMIT 1];
        if (types.isEmpty()) {
            return;
        }

        TerritoryModuleSeed.SeedResult seedResult = TerritoryModuleSeed.seedTerritoriesAndUsers();
        User diabetesMr = [
            SELECT Id
            FROM User
            WHERE Username = 'diabetes.mr@pharma.demo'
            LIMIT 1
        ];

        Map<Id, TerritoryHierarchyService.HierarchyLabels> labelsByUser =
            TerritoryHierarchyService.resolveHierarchyLabelsForEmployees(new Set<Id>{ diabetesMr.Id });
        TerritoryHierarchyService.HierarchyLabels labels = labelsByUser.get(diabetesMr.Id);

        System.assertNotEquals(null, labels, 'Expected hierarchy labels for diabetes MR');
        System.assertEquals('Diabetes', labels.businessUnit);
        System.assertEquals('DIAB III', labels.line);
        System.assertEquals(seedResult.territoryIdsByExtId.get('TERR_DIABETES'), labels.buTerritoryId);
        System.assertEquals(seedResult.territoryIdsByExtId.get('TERR_DIABETES_DM_1'), labels.lineTerritoryId);
    }
}
