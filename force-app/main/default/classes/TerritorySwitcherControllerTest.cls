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

    @IsTest
    static void getSelectedTerritoryId_ignoresOrgDefaultAndUsesUserRow() {
        Id userId = UserInfo.getUserId();
        // Org-level hierarchy default must not leak into the running user's selection.
        User_Territory_Context__c orgDefault = User_Territory_Context__c.getOrgDefaults();
        if (orgDefault == null) {
            orgDefault = new User_Territory_Context__c(SetupOwnerId = UserInfo.getOrganizationId());
        }
        orgDefault.Territory2_Id__c = String.valueOf(userId);
        Database.upsert(orgDefault, AccessLevel.SYSTEM_MODE);

        System.assertEquals(
            null,
            TerritoryContextService.getSelectedTerritoryId(),
            'Org/profile defaults must not count as the user selection'
        );

        List<Territory2> territories = [
            SELECT Id
            FROM Territory2
            WITH SYSTEM_MODE
            LIMIT 1
        ];
        if (territories.isEmpty()) {
            return;
        }
        Id territoryId = territories[0].Id;
        List<UserTerritory2Association> existing = [
            SELECT Id
            FROM UserTerritory2Association
            WHERE UserId = :userId AND Territory2Id = :territoryId
            WITH SYSTEM_MODE
            LIMIT 1
        ];
        if (existing.isEmpty()) {
            insert new UserTerritory2Association(UserId = userId, Territory2Id = territoryId);
        }

        Test.startTest();
        TerritoryContextService.SwitcherContext selected =
            TerritorySwitcherController.setSelectedTerritory(territoryId);
        Id storedId = TerritoryContextService.getSelectedTerritoryId();
        TerritoryContextService.SwitcherContext cleared =
            TerritorySwitcherController.setSelectedTerritory(null);
        Test.stopTest();

        System.assertEquals(territoryId, selected.selectedTerritoryId);
        System.assertEquals(territoryId, storedId);
        System.assertEquals(true, cleared.usingAllAssigned);
        System.assertEquals(null, TerritoryContextService.getSelectedTerritoryId());

        List<User_Territory_Context__c> userRows = [
            SELECT Id, Territory2_Id__c
            FROM User_Territory_Context__c
            WHERE SetupOwnerId = :userId
            WITH SYSTEM_MODE
            LIMIT 1
        ];
        System.assertEquals(1, userRows.size(), 'Switch must persist a user-owned hierarchy row');
        System.assertEquals(null, userRows[0].Territory2_Id__c, 'Clear must blank the user row');
    }

    @IsTest
    static void isAlignedOnRepTerritory_falseWhenAssignedToParentTerritory() {
        List<Territory2> parents = [
            SELECT Id, ParentTerritory2Id
            FROM Territory2
            WHERE ParentTerritory2Id != NULL
            WITH SYSTEM_MODE
            LIMIT 1
        ];
        if (parents.isEmpty()) {
            return;
        }
        Id parentId = parents[0].ParentTerritory2Id;
        List<Territory2> children = [
            SELECT Id
            FROM Territory2
            WHERE ParentTerritory2Id = :parentId
            WITH SYSTEM_MODE
            LIMIT 1
        ];
        if (children.isEmpty()) {
            return;
        }

        Id userId = UserInfo.getUserId();
        List<UserTerritory2Association> existingParent = [
            SELECT Id
            FROM UserTerritory2Association
            WHERE UserId = :userId AND Territory2Id = :parentId
            WITH SYSTEM_MODE
            LIMIT 1
        ];
        if (existingParent.isEmpty()) {
            insert new UserTerritory2Association(
                UserId = userId,
                Territory2Id = parentId,
                RoleInTerritory2 = 'District Manager'
            );
        }

        TerritorySwitcherController.setSelectedTerritory(children[0].Id);
        Test.startTest();
        Boolean aligned = TerritoryContextService.isAlignedOnRepTerritory();
        TerritorySwitcherController.setSelectedTerritory(null);
        Test.stopTest();

        System.assertEquals(
            false,
            aligned,
            'Managers must keep Coach visible even after selecting a leaf territory'
        );
        System.assertEquals(
            true,
            TerritoryContextService.hasSubordinateTerritories(userId),
            'A parent assignment is a manager with subordinate territories'
        );
        System.assertEquals(false, TerritoryContextService.hasSubordinateTerritories(null));
    }

    @IsTest
    static void getEffectiveTerritoryIds_coversOtherUserAndInvalidSelection() {
        Id userId = UserInfo.getUserId();
        Set<Id> forOther = TerritoryContextService.getEffectiveTerritoryIds(null);
        System.assertNotEquals(null, forOther);

        // Fake "other user" path ignores selection.
        Set<Id> assigned = TerritoryContextService.getAssignedTerritoryIds(userId);
        Set<Id> asOther = TerritoryContextService.getEffectiveTerritoryIds(
            UserInfo.getProfileId()
        );
        System.assertNotEquals(null, asOther);

        // Stale user-row pointing at a non-switchable Id should auto-clear.
        User_Territory_Context__c row = new User_Territory_Context__c(
            SetupOwnerId = userId,
            Territory2_Id__c = String.valueOf(userId)
        );
        Database.upsert(row, AccessLevel.SYSTEM_MODE);

        Test.startTest();
        Set<Id> effective = TerritoryContextService.getEffectiveTerritoryIds(userId);
        TerritoryContextService.SwitcherContext context = TerritoryContextService.getSwitcherContext();
        Boolean aligned = TerritoryContextService.isAlignedOnRepTerritory();
        Test.stopTest();

        System.assertEquals(assigned, effective);
        System.assertEquals(true, context.usingAllAssigned);
        System.assertEquals(null, TerritoryContextService.getSelectedTerritoryId());
        System.assertNotEquals(null, aligned);
        System.assertEquals(false, TerritoryContextService.hasSelectedTerritory());
    }

    @IsTest
    static void getSwitcherContext_buildsTreeAndLevels() {
        List<Territory2> territories = [
            SELECT Id, Name, ParentTerritory2Id, External_ID__c
            FROM Territory2
            WITH SYSTEM_MODE
            ORDER BY Name
            LIMIT 5
        ];
        Id userId = UserInfo.getUserId();
        for (Territory2 territory : territories) {
            List<UserTerritory2Association> existing = [
                SELECT Id
                FROM UserTerritory2Association
                WHERE UserId = :userId AND Territory2Id = :territory.Id
                WITH SYSTEM_MODE
                LIMIT 1
            ];
            if (existing.isEmpty()) {
                insert new UserTerritory2Association(
                    UserId = userId,
                    Territory2Id = territory.Id,
                    RoleInTerritory2 = 'Medical Rep'
                );
            }
        }

        Test.startTest();
        TerritoryContextService.SwitcherContext context = TerritorySwitcherController.getContext();
        Set<Id> switchable = TerritoryContextService.getSwitchableTerritoryIds(userId);
        if (!switchable.isEmpty()) {
            Id pick = new List<Id>(switchable)[0];
            TerritoryContextService.SwitcherContext selected =
                TerritorySwitcherController.setSelectedTerritory(pick);
            System.assertEquals(pick, selected.selectedTerritoryId);
            System.assertNotEquals(null, selected.selectedTerritoryName);
            Boolean aligned = TerritoryContextService.isAlignedOnRepTerritory();
            System.assertNotEquals(null, aligned);
            TerritorySwitcherController.setSelectedTerritory(null);
        }
        Test.stopTest();

        System.assertNotEquals(null, context);
        System.assertNotEquals(null, context.tree);
        System.assertEquals(true, !territories.isEmpty() ? context.hasAssignment : context.hasAssignment != null);
    }
}