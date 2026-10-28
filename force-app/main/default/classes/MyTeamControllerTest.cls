@IsTest
private class MyTeamControllerTest {
    @IsTest
    static void getMyTeamTree_returnsSubordinateTerritoryAndUser() {
        Territory2 district = createTerritory('My Team District', 'District', null);
        Territory2 position = district == null
            ? null
            : createTerritory('My Team Position', 'Position', district.Id);
        if (district == null || position == null) {
            System.assertNotEquals(null, MyTeamController.getMyTeamTree());
            return;
        }

        insert new UserTerritory2Association(
            UserId = UserInfo.getUserId(),
            Territory2Id = district.Id,
            RoleInTerritory2 = 'District Manager'
        );
        User rep = createRep();
        insert new UserTerritory2Association(
            UserId = rep.Id,
            Territory2Id = position.Id,
            RoleInTerritory2 = 'Medical Rep'
        );

        Test.startTest();
        List<MyTeamController.TeamNode> roots = MyTeamController.getMyTeamTree();
        Test.stopTest();

        MyTeamController.TeamNode districtNode = findNode(roots, district.Id);
        System.assertNotEquals(null, districtNode, 'The manager territory should be a root or ancestor.');
        MyTeamController.TeamNode positionNode = findNode(new List<MyTeamController.TeamNode>{ districtNode }, position.Id);
        System.assertNotEquals(null, positionNode, 'The child territory should appear under the manager territory.');
        Boolean foundRep = false;
        for (MyTeamController.TeamUser person : positionNode.users) {
            if (person.userId == rep.Id) {
                foundRep = true;
                System.assertEquals('Medical Rep', person.role);
            }
        }
        System.assert(foundRep, 'The assigned rep should appear on the child territory.');
    }

    private static MyTeamController.TeamNode findNode(List<MyTeamController.TeamNode> nodes, Id territoryId) {
        if (nodes == null) {
            return null;
        }
        for (MyTeamController.TeamNode node : nodes) {
            if (node.territoryId == territoryId) {
                return node;
            }
            MyTeamController.TeamNode child = findNode(node.children, territoryId);
            if (child != null) {
                return child;
            }
        }
        return null;
    }

    private static Territory2 createTerritory(String name, String territoryType, Id parentId) {
        List<Territory2Type> types = [SELECT Id FROM Territory2Type LIMIT 1];
        List<Territory2Model> models = [
            SELECT Id
            FROM Territory2Model
            WHERE DeveloperName = 'Current_FY'
            LIMIT 1
        ];
        if (types.isEmpty() || models.isEmpty()) {
            return null;
        }
        String suffix = String.valueOf(Math.abs(Crypto.getRandomInteger()));
        Territory2 territory = new Territory2(
            Name = name,
            DeveloperName = 'MyTeam_' + suffix,
            Territory2ModelId = models[0].Id,
            Territory2TypeId = types[0].Id,
            External_ID__c = 'TERR_MY_TEAM_' + suffix,
            ParentTerritory2Id = parentId
        );
        if (Schema.SObjectType.Territory2.fields.getMap().containsKey('Territory_Type__c')) {
            territory.put('Territory_Type__c', territoryType);
        }
        insert territory;
        return territory;
    }

    private static User createRep() {
        Profile profile = [SELECT Id FROM Profile WHERE Name = 'System Administrator' LIMIT 1];
        String uniq = 'myteamrep' + String.valueOf(Datetime.now().getTime());
        User rep = new User(
            Alias = 'mytrep',
            Email = uniq + '@example.com.invalid',
            EmailEncodingKey = 'UTF-8',
            LastName = 'My Team Rep',
            LanguageLocaleKey = 'en_US',
            LocaleSidKey = 'en_US',
            ProfileId = profile.Id,
            TimeZoneSidKey = 'Africa/Cairo',
            Username = uniq + '@example.com.invalid'
        );
        insert rep;
        return rep;
    }
}