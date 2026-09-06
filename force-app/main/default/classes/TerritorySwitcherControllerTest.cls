@IsTest
private class TerritorySwitcherControllerTest {
    @IsTest
    static void getContext_returnsTreeForAssignedUser() {
        Test.startTest();
        TerritoryContextService.SwitcherContext context = TerritorySwitcherController.getContext();
        Test.stopTest();

        System.assertNotEquals(null, context);
        System.assertNotEquals(null, context.tree);
        System.assertEquals(true, context.usingAllAssigned);
        System.assertEquals(null, TerritoryContextService.getSelectedTerritoryId());
        System.assertNotEquals(null, TerritoryContextService.getAssignedTerritoryIds(UserInfo.getUserId()));
        System.assertNotEquals(null, TerritoryContextService.getEffectiveTerritoryIds(UserInfo.getUserId()));
    }

    @IsTest
    static void setSelectedTerritory_rejectsUnknownId() {
        Boolean caught = false;
        try {
            TerritorySwitcherController.setSelectedTerritory(UserInfo.getUserId());
        } catch (AuraHandledException e) {
            caught = true;
        }
        System.assert(caught, 'Expected unknown territory to be rejected');
    }

    @IsTest
    static void setSelectedTerritory_acceptsAssignedOrClears() {
        List<Territory2> territories = [
            SELECT Id
            FROM Territory2
            WITH SYSTEM_MODE
            LIMIT 1
        ];
        if (territories.isEmpty()) {
            TerritoryContextService.SwitcherContext cleared =
                TerritorySwitcherController.setSelectedTerritory(null);
            System.assertEquals(true, cleared.usingAllAssigned);
            return;
        }

        Id territoryId = territories[0].Id;
        List<UserTerritory2Association> existing = [
            SELECT Id
            FROM UserTerritory2Association
            WHERE UserId = :UserInfo.getUserId() AND Territory2Id = :territoryId
            WITH SYSTEM_MODE
            LIMIT 1
        ];
        if (existing.isEmpty()) {
            insert new UserTerritory2Association(
                UserId = UserInfo.getUserId(),
                Territory2Id = territoryId
            );
        }

        Test.startTest();
        TerritoryContextService.SwitcherContext selected =
            TerritorySwitcherController.setSelectedTerritory(territoryId);
        System.assertEquals(true, TerritoryContextService.hasSelectedTerritory());
        Set<Id> effective = TerritoryContextService.getEffectiveTerritoryIds(UserInfo.getUserId());
        TerritoryContextService.SwitcherContext cleared =
            TerritorySwitcherController.setSelectedTerritory(null);
        Test.stopTest();

        System.assertEquals(territoryId, selected.selectedTerritoryId);
        System.assertEquals(1, effective.size());
        System.assertEquals(true, effective.contains(territoryId));
        System.assertEquals(true, cleared.usingAllAssigned);
        System.assertEquals(null, TerritoryContextService.getSelectedTerritoryId());
        System.assertEquals(false, TerritoryContextService.hasSelectedTerritory());
    }

    @IsTest
    static void getSwitchableTerritoryIds_returnsSet() {
        Set<Id> switchable = TerritoryContextService.getSwitchableTerritoryIds(UserInfo.getUserId());
        System.assertNotEquals(null, switchable);
    }
}
