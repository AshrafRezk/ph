@IsTest
private class TerritoryConsoleScopeTest {
    private class Fixture {
        Territory2 line;
        Territory2 myDistrict;
        Territory2 myPosition;
        Territory2 otherDistrict;
        Territory2 otherPosition;
        User manager;
        User myRep;
        User otherRep;
    }

    private static Territory2 node(String name, String externalId, String level, Id parentId, Id modelId, Id typeId) {
        return new Territory2(
            Name = name,
            DeveloperName = 'Scope_' + String.valueOf(Math.abs(Crypto.getRandomInteger())),
            Territory2ModelId = modelId,
            Territory2TypeId = typeId,
            ParentTerritory2Id = parentId,
            External_ID__c = externalId,
            Territory_Type__c = level
        );
    }

    private static User makeUser(String alias, String title) {
        Profile p = [SELECT Id FROM Profile WHERE Name = 'Standard User' LIMIT 1];
        String uniq = String.valueOf(Math.abs(Crypto.getRandomInteger()));
        return new User(
            Alias = alias,
            Email = alias + uniq + '@zetapharma.net',
            Username = alias + uniq + '@zetapharma.net.scopetest',
            LastName = 'Scope ' + alias,
            Title = title,
            TimeZoneSidKey = 'Africa/Cairo',
            LocaleSidKey = 'en_US',
            EmailEncodingKey = 'UTF-8',
            LanguageLocaleKey = 'en_US',
            ProfileId = p.Id
        );
    }

    private static Fixture build() {
        Fixture f = new Fixture();
        Id modelId = [SELECT Id FROM Territory2Model ORDER BY CreatedDate LIMIT 1].Id;
        Id typeId = [SELECT Id FROM Territory2Type LIMIT 1].Id;
        f.line = node('SCOPE LINE', 'TERR_LINE_SCOPETEST', 'Line', null, modelId, typeId);
        insert f.line;
        f.myDistrict = node('SCOPE DM MINE', 'TERR_DM_SCOPETEST_A', 'District', f.line.Id, modelId, typeId);
        f.otherDistrict = node('SCOPE DM OTHER', 'TERR_DM_SCOPETEST_B', 'District', f.line.Id, modelId, typeId);
        insert new List<Territory2>{ f.myDistrict, f.otherDistrict };
        f.myPosition = node('SCOPE POS MINE', 'TERR_POS_SCOPETEST_A', 'Position', f.myDistrict.Id, modelId, typeId);
        f.otherPosition = node('SCOPE POS OTHER', 'TERR_POS_SCOPETEST_B', 'Position', f.otherDistrict.Id, modelId, typeId);
        insert new List<Territory2>{ f.myPosition, f.otherPosition };

        f.manager = makeUser('scdm', 'District Manager');
        f.myRep = makeUser('scr1', 'Medical Rep');
        f.otherRep = makeUser('scr2', 'Medical Rep');
        insert new List<User>{ f.manager, f.myRep, f.otherRep };
        insert new List<UserTerritory2Association>{
            new UserTerritory2Association(UserId = f.manager.Id, Territory2Id = f.myDistrict.Id, RoleInTerritory2 = 'District Manager'),
            new UserTerritory2Association(UserId = f.myRep.Id, Territory2Id = f.myPosition.Id, RoleInTerritory2 = 'Medical Rep'),
            new UserTerritory2Association(UserId = f.otherRep.Id, Territory2Id = f.otherPosition.Id, RoleInTerritory2 = 'Medical Rep')
        };
        return f;
    }

    private static TerritoryManagementController.TerritoryTreeNode find(
        List<TerritoryManagementController.TerritoryTreeNode> nodes,
        Id territoryId
    ) {
        if (nodes == null) {
            return null;
        }
        for (TerritoryManagementController.TerritoryTreeNode n : nodes) {
            if (n.id == territoryId) {
                return n;
            }
            TerritoryManagementController.TerritoryTreeNode hit = find(n.children, territoryId);
            if (hit != null) {
                return hit;
            }
        }
        return null;
    }

    @IsTest
    static void adminHasFullScope() {
        System.assertEquals(true, TerritoryConsoleScope.hasFullScope(), 'the test runner is a System Administrator');
        System.assertEquals(null, TerritoryConsoleScope.getScopedTerritoryIds());
        System.assertEquals(null, TerritoryConsoleScope.getScopedLineIds());
        System.assertEquals(null, TerritoryConsoleScope.getScopedUserIds());
        System.assertEquals(true, TerritoryConsoleScope.isInScope(null));
        System.assertEquals(true, TerritoryConsoleScope.isUserInScope(UserInfo.getUserId()));
    }

    @IsTest
    static void districtManagerSeesOnlyOwnDistrict() {
        Fixture f = build();
        System.runAs(f.manager) {
            Test.startTest();
            Set<Id> scope = TerritoryConsoleScope.getScopedTerritoryIds();
            Set<Id> lines = TerritoryConsoleScope.getScopedLineIds();
            Set<Id> users = TerritoryConsoleScope.getScopedUserIds();
            Test.stopTest();

            System.assert(scope.contains(f.myDistrict.Id));
            System.assert(scope.contains(f.myPosition.Id));
            System.assert(!scope.contains(f.otherDistrict.Id), 'another DM district is out of scope');
            System.assert(!scope.contains(f.line.Id), 'the line itself is context only');
            System.assertEquals(new Set<Id>{ f.line.Id }, lines);
            System.assert(users.contains(f.myRep.Id));
            System.assert(users.contains(f.manager.Id));
            System.assert(!users.contains(f.otherRep.Id));
            System.assertEquals(true, TerritoryConsoleScope.isUserInScope(f.myRep.Id));
            System.assertEquals(false, TerritoryConsoleScope.isUserInScope(f.otherRep.Id));

            Boolean refused = false;
            try {
                TerritoryConsoleScope.requireInScope(f.otherDistrict.Id);
            } catch (AuraHandledException ex) {
                refused = true;
            }
            System.assert(refused, 'changing another team must be refused');
            TerritoryConsoleScope.requireInScope(f.myPosition.Id);
        }
    }

    @IsTest
    static void unseatedUserWithoutPermissionSeesNothing() {
        User nobody = makeUser('scno', 'Medical Rep');
        insert nobody;
        System.runAs(nobody) {
            System.assertEquals(0, TerritoryConsoleScope.getScopedTerritoryIds().size());
            System.assertEquals(0, TerritoryConsoleScope.getScopedLineIds().size());
            System.assertEquals(new Set<Id>{ nobody.Id }, TerritoryConsoleScope.getScopedUserIds());
            System.assertEquals(0, TerritoryConsoleScope.withAncestors(new Set<Id>()).size());
        }
    }

    @IsTest
    static void managerConsoleListsOnlyOwnTeam() {
        Fixture f = build();
        System.runAs(f.manager) {
            Test.startTest();
            TerritoryManagementController.UserQueryRequest request = new TerritoryManagementController.UserQueryRequest();
            request.includeInactive = true;
            request.pageSize = 500;
            TerritoryManagementController.ManagedUsersPage page = TerritoryManagementController.queryManagedUsers(request);
            List<TerritoryManagementController.TerritoryTreeNode> roots = TerritoryManagementController.getTerritoryTree();
            List<TerritoryManagementController.LineSummary> lines = TerritoryManagementController.getProductLines();
            Test.stopTest();

            Set<Id> listed = new Set<Id>();
            for (TerritoryManagementController.UserOption option : page.users) {
                listed.add(option.id);
            }
            System.assert(listed.contains(f.myRep.Id), 'own rep is listed');
            System.assert(!listed.contains(f.otherRep.Id), 'another team rep is hidden');
            System.assertEquals(true, page.teamScoped);
            System.assertEquals(false, page.canManageUsers);

            System.assertNotEquals(null, find(roots, f.myPosition.Id), 'own position is in the tree');
            System.assertEquals(null, find(roots, f.otherDistrict.Id), 'another district is hidden');
            TerritoryManagementController.TerritoryTreeNode lineNode = find(roots, f.line.Id);
            System.assertNotEquals(null, lineNode, 'the line shows as context');
            System.assertEquals(false, lineNode.canEdit, 'context rows are read-only');
            System.assertEquals(true, find(roots, f.myDistrict.Id).canEdit);

            System.assertEquals(1, lines.size(), 'only the line of the manager team: ' + lines);
            System.assertEquals(f.line.Id, lines[0].id);

            Boolean refused = false;
            try {
                TerritoryManagementController.clearTerritoryAssignments(f.otherPosition.Id);
            } catch (AuraHandledException ex) {
                refused = true;
            }
            System.assert(refused, 'clearing another team seat is refused');
        }
    }

    @IsTest
    static void adminConsoleStillSeesEverything() {
        Fixture f = build();
        Test.startTest();
        TerritoryManagementController.UserQueryRequest request = new TerritoryManagementController.UserQueryRequest();
        request.includeInactive = true;
        request.pageSize = 500;
        request.searchTerm = 'scope';
        TerritoryManagementController.ManagedUsersPage page = TerritoryManagementController.queryManagedUsers(request);
        List<TerritoryManagementController.TerritoryTreeNode> roots = TerritoryManagementController.getTerritoryTree();
        Test.stopTest();
        Set<Id> listed = new Set<Id>();
        for (TerritoryManagementController.UserOption option : page.users) {
            listed.add(option.id);
        }
        System.assert(listed.contains(f.myRep.Id) && listed.contains(f.otherRep.Id), 'SFE sees both teams');
        System.assertEquals(false, page.teamScoped);
        System.assertEquals(true, page.canManageUsers);
        System.assertNotEquals(null, find(roots, f.otherDistrict.Id));
    }

    @IsTest
    static void saveTerritoryJsonRenamesTheTerritory() {
        Fixture f = build();
        Test.startTest();
        Id saved = TerritoryManagementController.saveTerritoryJson(
            '{"recordId":"' + f.myDistrict.Id + '","name":"  SCOPE DM RENAMED ","externalId":"TERR_DM_SCOPETEST_A",'
            + '"parentId":null,"level":"District","callRate":12,"amCallRate":null,"pmCallRate":null}'
        );
        Test.stopTest();
        System.assertEquals(f.myDistrict.Id, saved);
        System.assertEquals('SCOPE DM RENAMED', [SELECT Name FROM Territory2 WHERE Id = :f.myDistrict.Id].Name);

        Boolean blank = false;
        try {
            TerritoryManagementController.saveTerritoryJson('');
        } catch (AuraHandledException ex) {
            blank = true;
        }
        System.assert(blank, 'an empty form is refused');
        Boolean bad = false;
        try {
            TerritoryManagementController.saveTerritoryJson('{not json');
        } catch (AuraHandledException ex) {
            bad = true;
        }
        System.assert(bad, 'unreadable JSON is refused');
    }

    @IsTest
    static void managerCannotRenameAnotherTeam() {
        Fixture f = build();
        System.runAs(f.manager) {
            Boolean refused = false;
            try {
                TerritoryManagementController.saveTerritoryJson(
                    '{"recordId":"' + f.otherDistrict.Id + '","name":"HIJACK","level":"District"}'
                );
            } catch (AuraHandledException ex) {
                refused = true;
            }
            System.assert(refused, 'renaming another team district is refused');
        }
        System.assertEquals('SCOPE DM OTHER', [SELECT Name FROM Territory2 WHERE Id = :f.otherDistrict.Id].Name);
    }

    @IsTest
    static void marketingSeatIsNotShownAsALine() {
        Fixture f = build();
        Territory2 bm = node(
            'SCOPE BRAND MANAGER',
            'TERR_BM_SCOPETEST',
            'Other',
            f.line.Id,
            [SELECT Territory2ModelId FROM Territory2 WHERE Id = :f.line.Id].Territory2ModelId,
            [SELECT Territory2TypeId FROM Territory2 WHERE Id = :f.line.Id].Territory2TypeId
        );
        insert bm;
        TerritoryManagementController.TerritoryTreeNode n = find(TerritoryManagementController.getTerritoryTree(), bm.Id);
        System.assertNotEquals(null, n);
        System.assertEquals('Marketing Seat', n.level);
        System.assertEquals(false, n.canAddChild);
    }

    @IsTest
    static void previewExplainsAUserWithoutASeat() {
        User nobody = makeUser('scpv', 'Medical Rep');
        insert nobody;
        String message;
        try {
            TerritoryPreviewService.previewAsUser(nobody.Id);
        } catch (AuraHandledException ex) {
            message = ex.getMessage();
        }
        System.assertNotEquals(null, message);
    }

    @IsTest
    static void previewPicksASeatTheCallerCovers() {
        Fixture f = build();
        System.runAs(f.manager) {
            TerritoryPreviewService.PreviewResult result = TerritoryPreviewService.previewAsUser(f.myRep.Id);
            System.assertEquals(f.myPosition.Id, result.selectedTerritoryId);
            String message;
            try {
                TerritoryPreviewService.previewAsUser(f.otherRep.Id);
            } catch (AuraHandledException ex) {
                message = ex.getMessage();
            }
            System.assertNotEquals(null, message, 'a seat outside the caller seat is explained, not silently failed');
            TerritoryPreviewService.clearPreview();
        }
    }
}
