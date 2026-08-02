@IsTest
private class TerritoryManagementControllerTest {

    @IsTest
    static void getTerritoryTree_returnsHierarchy() {
        Territory2 territory = getOrCreateTestTerritory('TERR_TEST_MGMT');
        User runUser = [SELECT Id FROM User WHERE Id = :UserInfo.getUserId()];

        insert new UserTerritory2Association(
            UserId = runUser.Id,
            Territory2Id = territory.Id,
            RoleInTerritory2 = 'Medical Rep'
        );

        Test.startTest();
        List<TerritoryManagementController.TerritoryTreeNode> roots =
            TerritoryManagementController.getTerritoryTree();
        Test.stopTest();

        System.assert(!roots.isEmpty(), 'Expected at least one root territory.');
        Boolean found = false;
        for (TerritoryManagementController.TerritoryTreeNode root : roots) {
            found = found || containsTerritory(root, territory.Id);
        }
        System.assert(found, 'Expected seeded test territory in tree.');
    }

    @IsTest
    static void getAssignableUsers_returnsPharmaUsers() {
        Test.startTest();
        List<TerritoryManagementController.UserOption> users =
            TerritoryManagementController.getAssignableUsers(null);
        Test.stopTest();

        System.assert(!users.isEmpty(), 'Expected at least one assignable user.');
        TerritoryManagementController.UserOption firstUser = users[0];
        System.assertNotEquals(null, firstUser.label, 'Expected display label on user option.');
        System.assert(firstUser.label.contains('·'), 'Expected enriched label with separators.');
    }

    @IsTest
    static void assignUserToTerritory_createsAssignment() {
        Territory2 territory = getOrCreateTestTerritory('TERR_TEST_ASSIGN');
        User runUser = [SELECT Id FROM User WHERE Id = :UserInfo.getUserId()];

        Test.startTest();
        TerritoryManagementController.assignUserToTerritory(territory.Id, runUser.Id, 'Medical Rep');
        Test.stopTest();

        Integer assignedCount = [
            SELECT COUNT()
            FROM UserTerritory2Association
            WHERE Territory2Id = :territory.Id AND UserId = :runUser.Id
        ];
        System.assertEquals(1, assignedCount);
    }

    @IsTest
    static void clearTerritoryAssignments_removesAssignments() {
        Territory2 territory = getOrCreateTestTerritory('TERR_TEST_CLEAR');
        User runUser = [SELECT Id FROM User WHERE Id = :UserInfo.getUserId()];
        insert new UserTerritory2Association(
            UserId = runUser.Id,
            Territory2Id = territory.Id,
            RoleInTerritory2 = 'Medical Rep'
        );

        Test.startTest();
        TerritoryManagementController.clearTerritoryAssignments(territory.Id);
        Test.stopTest();

        Integer assignedCount = [
            SELECT COUNT()
            FROM UserTerritory2Association
            WHERE Territory2Id = :territory.Id
        ];
        System.assertEquals(0, assignedCount);
    }

    private static Boolean containsTerritory(
        TerritoryManagementController.TerritoryTreeNode node,
        Id territoryId
    ) {
        if (node == null) {
            return false;
        }
        if (node.id == territoryId) {
            return true;
        }
        if (node.children == null) {
            return false;
        }
        for (TerritoryManagementController.TerritoryTreeNode child : node.children) {
            if (containsTerritory(child, territoryId)) {
                return true;
            }
        }
        return false;
    }

    private static Territory2 getOrCreateTestTerritory(String externalId) {
        List<Territory2> existing = [
            SELECT Id
            FROM Territory2
            WHERE External_ID__c = :externalId
            LIMIT 1
        ];
        if (!existing.isEmpty()) {
            return existing[0];
        }

        List<Territory2Type> types = [SELECT Id FROM Territory2Type LIMIT 1];
        if (types.isEmpty()) {
            return null;
        }

        List<Territory2Model> models = [
            SELECT Id
            FROM Territory2Model
            WHERE DeveloperName = 'Current_FY'
            LIMIT 1
        ];
        if (models.isEmpty()) {
            return null;
        }

        Territory2 territory = new Territory2(
            Name = 'Territory Mgmt Test',
            DeveloperName = 'Territory_Mgmt_Test',
            Territory2ModelId = models[0].Id,
            Territory2TypeId = types[0].Id,
            External_ID__c = externalId
        );
        insert territory;
        return territory;
    }
}
