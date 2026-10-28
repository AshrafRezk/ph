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
        TerritoryManagementController.getAssignableUsers('admin');
        List<TerritoryManagementController.LineSummary> lines =
            TerritoryManagementController.getProductLines();
        List<TerritoryManagementController.ParentOption> parents =
            TerritoryManagementController.getParentOptions('Line');
        TerritoryManagementController.getParentOptions('District');
        TerritoryManagementController.getParentOptions('Position');
        TerritoryManagementController.getParentOptions('Business Unit');
        String role = TerritoryManagementController.resolveAssignmentRole(UserInfo.getUserId());
        Test.stopTest();

        System.assertNotEquals(null, users);
        System.assertNotEquals(null, lines);
        System.assertNotEquals(null, parents);
        System.assertNotEquals(null, role);
    }

    @IsTest
    static void userManagement_profilePasswordAndStatusGuards() {
        List<TerritoryManagementController.UserOption> managed =
            TerritoryManagementController.getManagedUsers(null, true);
        System.assertNotEquals(null, managed);

        User current = [
            SELECT Id, FirstName, LastName, Email, Username, Title, Department, Profile.Name
            FROM User
            WHERE Id = :UserInfo.getUserId()
        ];

        TerritoryManagementController.UserProfileForm form =
            new TerritoryManagementController.UserProfileForm();
        form.userId = current.Id;
        form.firstName = current.FirstName;
        form.lastName = current.LastName;
        form.email = current.Email;
        form.username = current.Username;
        form.title = 'Territory Admin Test';
        form.department = current.Department;

        Test.startTest();
        TerritoryManagementController.updateUserProfile(form);

        TerritoryManagementController.UserStatusResult selfDeactivate =
            TerritoryManagementController.setUsersActive(new List<Id>{ current.Id }, false);
        System.assert(
            selfDeactivate.skippedCount >= 1,
            'Expected self/admin deactivation to be skipped.'
        );

        Profile standardProfile = [SELECT Id FROM Profile WHERE Name = 'Standard User' LIMIT 1];
        String uniq = String.valueOf(Math.abs(Crypto.getRandomInteger()));
        User managedUser = new User(
            Alias = 'tmgmt',
            Email = 'tmgmt' + uniq + '@zetapharma.com',
            EmailEncodingKey = 'UTF-8',
            LastName = 'MgmtTest',
            LanguageLocaleKey = 'en_US',
            LocaleSidKey = 'en_US',
            ProfileId = standardProfile.Id,
            TimeZoneSidKey = 'America/Los_Angeles',
            Username = 'tmgmt' + uniq + '@zetapharma.com'
        );
        insert managedUser;

        TerritoryManagementController.PasswordSetResult passwordResult =
            TerritoryManagementController.setOneTimePasswords(
                new List<Id>{ managedUser.Id },
                'Zeta!TempPass9'
            );
        System.assertEquals(
            1,
            passwordResult.successCount,
            String.join(passwordResult.messages, ' | ')
        );
        System.assertEquals(
            1,
            passwordResult.emailSentCount,
            String.join(passwordResult.messages, ' | ')
        );
        System.assertEquals('Zeta!TempPass9', passwordResult.passwordUsed);

        Messaging.SingleEmailMessage sample = TerritoryManagementController.loginMail(
            managedUser,
            'Zeta!TempPass9',
            managedUser.Email
        );
        System.assert(sample.getPlainTextBody().contains('Here is your username:'));
        System.assert(sample.getPlainTextBody().contains(managedUser.Username));
        System.assert(sample.getPlainTextBody().contains('Here is your password:'));
        System.assert(sample.getPlainTextBody().contains('Zeta!TempPass9'));
        System.assert(sample.getPlainTextBody().contains('salesforceoffline.com'));
        System.assertEquals('Your Zeta Pharma login', sample.getSubject());

        TerritoryManagementController.UserStatusResult deactivated =
            TerritoryManagementController.setUsersActive(new List<Id>{ managedUser.Id }, false);
        System.assertEquals(1, deactivated.successCount);

        TerritoryManagementController.UserStatusResult activated =
            TerritoryManagementController.setUsersActive(new List<Id>{ managedUser.Id }, true);
        System.assertEquals(1, activated.successCount);

        deactivated = TerritoryManagementController.setUsersActive(new List<Id>{ managedUser.Id }, false);
        System.assertEquals(1, deactivated.successCount);

        managedUser = [SELECT Id, Name, Username, Email, IsActive FROM User WHERE Id = :managedUser.Id];
        System.assertEquals(false, managedUser.IsActive);
        TerritoryManagementController.PasswordSetResult inactiveResult =
            TerritoryManagementController.setOneTimePasswords(
                new List<Id>{ managedUser.Id },
                'Zeta!TempPass8'
            );
        System.assertEquals(
            1,
            inactiveResult.successCount,
            String.join(inactiveResult.messages, ' | ')
        );
        System.assertEquals(1, inactiveResult.emailSentCount);
        System.assert(
            inactiveResult.messages[0].contains('activated'),
            String.join(inactiveResult.messages, ' | ')
        );
        managedUser = [SELECT Id, IsActive FROM User WHERE Id = :managedUser.Id];
        System.assertEquals(true, managedUser.IsActive);

        TerritoryManagementController.PasswordSetResult generated =
            TerritoryManagementController.setOneTimePasswords(new List<Id>{ managedUser.Id }, null);
        System.assertEquals(1, generated.successCount, String.join(generated.messages, ' | '));
        System.assert(generated.passwordUsed.length() >= 8);
        System.assert(Pattern.matches('.*[A-Za-z].*', generated.passwordUsed));
        System.assert(Pattern.matches('.*\\d.*', generated.passwordUsed));

        Boolean weakBlocked = false;
        try {
            TerritoryManagementController.setOneTimePasswords(
                new List<Id>{ managedUser.Id },
                'letters-only'
            );
        } catch (AuraHandledException ex) {
            weakBlocked = true;
        }
        System.assert(weakBlocked, 'Expected a letters-only password to be rejected.');

        Boolean emptyPasswordBlocked = false;
        try {
            TerritoryManagementController.setOneTimePasswords(new List<Id>(), null);
        } catch (AuraHandledException ex) {
            emptyPasswordBlocked = true;
        }
        System.assert(emptyPasswordBlocked, 'Expected empty user list to be rejected.');
        Test.stopTest();
    }

    @IsTest
    static void adminMutations_guardrails() {
        Territory2 territory = getOrCreateTestTerritory('TERR_TEST_GUARD');
        if (territory == null) {
            return;
        }

        Boolean createBlocked = false;
        try {
            TerritoryManagementController.createProductLine('X', 'X', 'Diabetes');
        } catch (AuraHandledException ex) {
            createBlocked = true;
        }
        System.assert(createBlocked, 'Expected createProductLine guardrail.');

        Boolean userBlocked = false;
        try {
            TerritoryManagementController.createPharmaUser('A', 'B', 'TEAM', 'mr', territory.Id, 'Medical Rep');
        } catch (AuraHandledException ex) {
            userBlocked = true;
        }
        System.assert(userBlocked, 'Expected createPharmaUser guardrail.');

        TerritoryManagementController.TerritoryForm form = new TerritoryManagementController.TerritoryForm();
        form.recordId = territory.Id;
        form.name = 'Territory Mgmt Test Updated';
        Test.startTest();
        Id savedId = TerritoryManagementController.saveTerritory(form);
        Test.stopTest();
        System.assertEquals(territory.Id, savedId);
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

    @IsTest
    static void mapAssignmentRole_coversHierarchyTitles() {
        System.assertEquals(
            'Medical Rep',
            TerritoryManagementController.mapAssignmentRole('Medical Rep', null)
        );
        System.assertEquals(
            'Trainer',
            TerritoryManagementController.mapAssignmentRole('Trainer', null)
        );
        System.assertEquals(
            'District Manager',
            TerritoryManagementController.mapAssignmentRole('DM', null)
        );
        System.assertEquals(
            'Area Manager',
            TerritoryManagementController.mapAssignmentRole('Area Manager', null)
        );
        System.assertEquals(
            'Brand Manager',
            TerritoryManagementController.mapAssignmentRole('Brand Manager', null)
        );
        System.assertEquals(
            'National Sales Manager',
            TerritoryManagementController.mapAssignmentRole('NSM', null)
        );
        System.assertEquals(
            'Business Unit Manager',
            TerritoryManagementController.mapAssignmentRole('BUM', null)
        );
        System.assertEquals(
            'SFE',
            TerritoryManagementController.mapAssignmentRole(null, 'admin@pharma.eg')
        );
        System.assertEquals(
            'Area Manager',
            TerritoryManagementController.mapAssignmentRole(null, 'cardio.am@pharma.demo')
        );
        System.assertEquals(
            'Business Unit Manager',
            TerritoryManagementController.mapAssignmentRole(null, 'chc.bum@pharma.demo')
        );
    }

    @IsTest
    static void vacantPosition_keepsBrickAlignmentAndPromoTargets() {
        Territory2 position = getOrCreatePositionTerritory('TERR_POS_VACANT_SAFE', 'Vacant Safety Pos');
        if (position == null) {
            return;
        }

        Brick__c brick = new Brick__c(
            Name = 'Vacant Safety Brick',
            External_ID__c = 'BRICK_VACANT_SAFE_1',
            Is_Active__c = true
        );
        insert brick;

        insert new Brick_Territory_Alignment__c(
            Brick__c = brick.Id,
            External_ID__c = 'BRICK_VACANT_SAFE_1|TERR_POS_VACANT_SAFE',
            Territory2_Id__c = String.valueOf(position.Id),
            Territory_External_ID__c = 'TERR_POS_VACANT_SAFE',
            Share__c = 1,
            Is_Active__c = true
        );

        PromoGridAdminController.skipLineTerritoryValidation = true;
        List<PromoGridAdminController.PicklistOption> classes =
            PromoGridAdminController.getClassOptions();
        System.assert(!classes.isEmpty(), 'Expected class picklist values.');

        PromoGridAdminController.ClassTargetingInput classInput =
            new PromoGridAdminController.ClassTargetingInput();
        classInput.territory2Id = position.Id;
        classInput.classCode = classes[0].value;
        classInput.listPercentage = 20;
        classInput.targetMonthlyVisits = 6;
        Id classId = PromoGridAdminController.upsertClassTargeting(classInput);

        User runUser = [SELECT Id FROM User WHERE Id = :UserInfo.getUserId()];
        TerritoryManagementController.assignUserToTerritory(
            position.Id,
            runUser.Id,
            'Medical Rep'
        );

        Test.startTest();
        TerritoryManagementController.clearTerritoryAssignments(position.Id);

        classInput.recordId = classId;
        classInput.listPercentage = 25;
        classInput.targetMonthlyVisits = 8;
        Id updatedClassId = PromoGridAdminController.upsertClassTargeting(classInput);

        List<TerritoryManagementController.TerritoryTreeNode> roots =
            TerritoryManagementController.getTerritoryTree();
        Test.stopTest();

        System.assertEquals(
            0,
            [
                SELECT COUNT()
                FROM UserTerritory2Association
                WHERE Territory2Id = :position.Id
            ],
            'Vacant position must have no user associations.'
        );
        System.assertEquals(
            1,
            [
                SELECT COUNT()
                FROM Brick_Territory_Alignment__c
                WHERE External_ID__c = 'BRICK_VACANT_SAFE_1|TERR_POS_VACANT_SAFE'
            ],
            'Brick alignment must survive vacancy.'
        );
        System.assertEquals(classId, updatedClassId);
        Promo_Grid_Class_Targeting__c targeting = [
            SELECT Target_Monthly_Visits__c, List_Percentage__c
            FROM Promo_Grid_Class_Targeting__c
            WHERE Id = :classId
        ];
        System.assertEquals(8, targeting.Target_Monthly_Visits__c);
        System.assertEquals(25, targeting.List_Percentage__c);

        TerritoryManagementController.TerritoryTreeNode vacantNode = findNode(roots, position.Id);
        System.assertNotEquals(null, vacantNode, 'Expected vacant position in territory tree.');
        System.assertEquals(true, vacantNode.isVacant, 'Cleared position must be vacant.');
    }

    @IsTest
    static void productLineLinkage_countsAssignAndClear() {
        Product2 brand = new Product2(
            Name = 'Test Brand Line Link',
            ProductCode = 'TBLINK',
            IsActive = true,
            Product_Type__c = 'Brand',
            Primary_Brand__c = 'Test Brand Line Link',
            Sales_Unit__c = 'DIAB',
            Sales_Line__c = 'DIAB-I'
        );
        Product2 detail = new Product2(
            Name = 'Test Detail Line Link',
            ProductCode = 'TDLINK',
            IsActive = true,
            Product_Type__c = 'Detail',
            Primary_Brand__c = 'Test Brand Line Link',
            Sales_Unit__c = 'DIAB',
            Sales_Line__c = 'Other-Line'
        );
        insert brand;
        detail.Parent_Product__c = brand.Id;
        insert detail;

        Territory2 line = getOrCreateLineTerritory('TERR_LINE_TEST_DIAB_I', 'DIAB-I');
        if (line == null) {
            return;
        }

        Test.startTest();
        List<TerritoryManagementController.LineSummary> lines =
            TerritoryManagementController.getProductLines();
        TerritoryManagementController.LineSummary target;
        for (TerritoryManagementController.LineSummary summary : lines) {
            if (summary.id == line.Id) {
                target = summary;
                break;
            }
        }
        System.assertNotEquals(null, target, 'Expected test line in summaries.');
        System.assert(target.productCount >= 1, 'Expected product count from Sales_Line.');
        System.assertEquals('DIAB', target.therapyArea);

        List<TerritoryManagementController.LineProductRow> linked =
            TerritoryManagementController.getProductsForLine(line.Id);
        System.assert(!linked.isEmpty(), 'Expected linked products for line.');

        TerritoryManagementController.setProductLineAssignment(detail.Id, line.Id, false);
        TerritoryManagementController.setProductLineAssignment(detail.Id, line.Id, true);

        List<Product_Territory_Alignment__c> alignments = [
            SELECT Id, Product2_Id__c, Is_Active__c
            FROM Product_Territory_Alignment__c
            WHERE
                Territory2_Id__c = :String.valueOf(line.Id)
                AND Product2_Id__c = :String.valueOf(detail.Id)
                AND Is_Active__c = TRUE
        ];
        System.assertEquals(1, alignments.size(), 'Expected PTA row after line assignment sync.');

        List<TerritoryManagementController.LineProductRow> searchable =
            TerritoryManagementController.searchAssignableProducts(line.Id, 'Test Detail');
        // detail now on line via sales + mirror; may or may not appear depending on fields
        TerritoryManagementController.clearProductLineAssignment(detail.Id, line.Id);
        searchable = TerritoryManagementController.searchAssignableProducts(line.Id, 'Test Detail');
        System.assert(!searchable.isEmpty(), 'Expected detail available after clear.');
        alignments = [
            SELECT Id
            FROM Product_Territory_Alignment__c
            WHERE
                Territory2_Id__c = :String.valueOf(line.Id)
                AND Product2_Id__c = :String.valueOf(detail.Id)
                AND Is_Active__c = TRUE
        ];
        System.assertEquals(0, alignments.size(), 'Expected PTA deactivated after line clear.');
        Test.stopTest();

        Product2 refreshed = [
            SELECT Sales_Line__c, Mirror_Line__c
            FROM Product2
            WHERE Id = :detail.Id
        ];
        System.assertEquals(null, refreshed.Sales_Line__c);
        // the earlier primary line (Other-Line) was kept as a mirror when DIAB-I became primary
        System.assertEquals('Other-Line', refreshed.Mirror_Line__c);
    }

    @IsTest
    static void assignProductAppendsMirrorsAndKeepsPreviousLine() {
        Territory2 lineA = getOrCreateLineTerritory('TERR_LINE_TEST_APPEND_A', 'APPEND-A');
        Territory2 lineB = getOrCreateLineTerritory('TERR_LINE_TEST_APPEND_B', 'APPEND-B');
        Territory2 lineC = getOrCreateLineTerritory('TERR_LINE_TEST_APPEND_C', 'APPEND-C');
        if (lineA == null || lineB == null || lineC == null) {
            return;
        }
        Product2 product = new Product2(
            Name = 'Append Product',
            ProductCode = 'APPENDP',
            IsActive = true,
            Product_Type__c = 'Brand',
            Sales_Line__c = 'APPEND-A'
        );
        insert product;

        TerritoryManagementController.setProductLineAssignment(product.Id, lineB.Id, true);
        TerritoryManagementController.setProductLineAssignment(product.Id, lineC.Id, true);
        // re-adding the same mirror does not duplicate it
        TerritoryManagementController.setProductLineAssignment(product.Id, lineC.Id, true);
        Product2 after = [SELECT Sales_Line__c, Mirror_Line__c FROM Product2 WHERE Id = :product.Id];
        System.assertEquals('APPEND-A', after.Sales_Line__c);
        System.assertEquals('APPEND-B;APPEND-C', after.Mirror_Line__c, 'mirrors append, never overwrite');

        // moving the primary line demotes the old primary to a mirror
        TerritoryManagementController.setProductLineAssignment(product.Id, lineB.Id, false);
        after = [SELECT Sales_Line__c, Mirror_Line__c FROM Product2 WHERE Id = :product.Id];
        System.assertEquals('APPEND-B', after.Sales_Line__c);
        System.assertEquals('APPEND-B;APPEND-C;APPEND-A', after.Mirror_Line__c);

        // alignments were re-synced for the line the product just joined
        System.assertEquals(
            1,
            [
                SELECT COUNT()
                FROM Product_Territory_Alignment__c
                WHERE
                    Territory2_Id__c = :String.valueOf(lineC.Id)
                    AND Product2_Id__c = :String.valueOf(product.Id)
                    AND Is_Active__c = TRUE
            ]
        );
    }

    @IsTest
    static void bulkRemoveReportsPerProductResults() {
        Territory2 line = getOrCreateLineTerritory('TERR_LINE_TEST_BULK_RM', 'BULK-RM');
        if (line == null) {
            return;
        }
        Product2 onLine = new Product2(Name = 'Bulk On Line', ProductCode = 'BRM1', IsActive = true, Product_Type__c = 'Brand', Sales_Line__c = 'BULK-RM');
        Product2 mirrored = new Product2(Name = 'Bulk Mirrored', ProductCode = 'BRM2', IsActive = true, Product_Type__c = 'Brand', Sales_Line__c = 'Other-Line', Mirror_Line__c = 'BULK-RM;Third-Line');
        Product2 elsewhere = new Product2(Name = 'Bulk Elsewhere', ProductCode = 'BRM3', IsActive = true, Product_Type__c = 'Brand', Sales_Line__c = 'Other-Line');
        insert new List<Product2>{ onLine, mirrored, elsewhere };
        TerritoryManagementController.syncLineProductAlignments(line.Id);

        Id elsewhereId = elsewhere.Id;
        Product2 gone = new Product2(Name = 'Bulk Gone', ProductCode = 'BRM4', IsActive = true, Product_Type__c = 'Brand');
        insert gone;
        Id goneId = gone.Id;
        delete gone;

        TerritoryManagementController.BulkRemoveResult result = TerritoryManagementController.removeProductsFromLine(
            new List<Id>{ onLine.Id, mirrored.Id, elsewhereId, goneId, onLine.Id },
            line.Id
        );
        System.assertEquals(4, result.requested, 'duplicates collapse');
        System.assertEquals(2, result.removed);
        System.assertEquals(1, result.unchanged);
        System.assertEquals(1, result.failed);
        System.assertEquals(4, result.rows.size());
        Map<Id, TerritoryManagementController.ProductRemoveRow> byId = new Map<Id, TerritoryManagementController.ProductRemoveRow>();
        for (TerritoryManagementController.ProductRemoveRow row : result.rows) {
            byId.put(row.productId, row);
        }
        System.assertEquals(true, byId.get(onLine.Id).success);
        System.assertEquals(true, byId.get(elsewhereId).success, 'not on this line is reported, not an error');
        System.assertEquals(false, byId.get(goneId).success);
        System.assertEquals('Product not found.', byId.get(goneId).message);

        Product2 mirroredAfter = [SELECT Sales_Line__c, Mirror_Line__c FROM Product2 WHERE Id = :mirrored.Id];
        System.assertEquals('Other-Line', mirroredAfter.Sales_Line__c);
        System.assertEquals('Third-Line', mirroredAfter.Mirror_Line__c, 'only this line is removed from the mirror list');
        System.assertEquals(
            0,
            [
                SELECT COUNT()
                FROM Product_Territory_Alignment__c
                WHERE Territory2_Id__c = :String.valueOf(line.Id) AND Product2_Id__c = :String.valueOf(onLine.Id) AND Is_Active__c = TRUE
            ],
            'alignments re-synced after bulk remove'
        );
        // the legacy wrapper now delegates to the bulk path and reports how many products were actually unlinked
        System.assertEquals(0, TerritoryManagementController.clearProductLineAssignments(new List<Id>{ onLine.Id, mirrored.Id, elsewhere.Id }, line.Id));
    }

    @IsTest
    static void chcSalesMirrorsEveryPromotedLineAndResyncsAlignments() {
        Territory2 chcSales = getOrCreateLineTerritory('TERR_LINE_TEST_CHC_SALES_M', 'TEST_CHC_SALES_M');
        if (chcSales == null) {
            return;
        }
        Product2 diab = new Product2(Name = 'Mirror Diab', ProductCode = 'MAL1', IsActive = true, Product_Type__c = 'Brand', Sales_Line__c = 'DIAB-I');
        Product2 chc = new Product2(Name = 'Mirror Chc', ProductCode = 'MAL2', IsActive = true, Product_Type__c = 'Brand', Sales_Line__c = 'CHC');
        Product2 viaMirror = new Product2(Name = 'Mirror Via', ProductCode = 'MAL3', IsActive = true, Product_Type__c = 'Brand', Sales_Line__c = 'Non-Promoted', Mirror_Line__c = 'GIT-I');
        Product2 nonPromoted = new Product2(Name = 'Mirror None', ProductCode = 'MAL4', IsActive = true, Product_Type__c = 'Brand', Sales_Line__c = 'Non-Promoted');
        Product2 already = new Product2(Name = 'Mirror Already', ProductCode = 'MAL5', IsActive = true, Product_Type__c = 'Brand', Sales_Line__c = 'GIT-II', Mirror_Line__c = 'TEST_CHC_SALES_M');
        insert new List<Product2>{ diab, chc, viaMirror, nonPromoted, already };

        TerritoryManagementController.MirrorResult result = TerritoryManagementController.mirrorAllPromotedLines('TEST_CHC_SALES_M');
        System.assertEquals(0, result.failed);
        System.assert(result.updated >= 3, 'every promoted line, not just CHC, is mirrored');

        Map<Id, Product2> after = new Map<Id, Product2>([SELECT Id, Sales_Line__c, Mirror_Line__c FROM Product2 WHERE Id IN :new List<Id>{ diab.Id, chc.Id, viaMirror.Id, nonPromoted.Id, already.Id }]);
        System.assertEquals('TEST_CHC_SALES_M', after.get(diab.Id).Mirror_Line__c);
        System.assertEquals('TEST_CHC_SALES_M', after.get(chc.Id).Mirror_Line__c);
        System.assertEquals('GIT-I;TEST_CHC_SALES_M', after.get(viaMirror.Id).Mirror_Line__c);
        System.assertEquals(null, after.get(nonPromoted.Id).Mirror_Line__c, 'non-promoted products are not mirrored');
        System.assertEquals('TEST_CHC_SALES_M', after.get(already.Id).Mirror_Line__c, 'no duplicate label');

        for (Product2 p : new List<Product2>{ diab, chc, viaMirror, already }) {
            System.assertEquals(
                1,
                [
                    SELECT COUNT()
                    FROM Product_Territory_Alignment__c
                    WHERE Territory2_Id__c = :String.valueOf(chcSales.Id) AND Product2_Id__c = :String.valueOf(p.Id) AND Is_Active__c = TRUE
                ],
                'alignment re-synced for ' + p.Name
            );
        }

        // second run is a no-op
        System.assertEquals(0, TerritoryManagementController.mirrorAllPromotedLines('TEST_CHC_SALES_M').updated);

        // CVM mirrors straight from CHC (not from CHC_Sales)
        System.assertEquals(1, TerritoryManagementController.mirrorLineProducts('CHC', 'CVM-I-TEST'));
        System.assertEquals('TEST_CHC_SALES_M', [SELECT Mirror_Line__c FROM Product2 WHERE Id = :diab.Id].Mirror_Line__c);
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
        return findNode(node.children, territoryId) != null;
    }

    private static TerritoryManagementController.TerritoryTreeNode findNode(
        List<TerritoryManagementController.TerritoryTreeNode> nodes,
        Id territoryId
    ) {
        if (nodes == null) {
            return null;
        }
        for (TerritoryManagementController.TerritoryTreeNode node : nodes) {
            if (node == null) {
                continue;
            }
            if (node.id == territoryId) {
                return node;
            }
            TerritoryManagementController.TerritoryTreeNode nested = findNode(node.children, territoryId);
            if (nested != null) {
                return nested;
            }
        }
        return null;
    }

    private static Territory2 getOrCreatePositionTerritory(String externalId, String name) {
        List<Territory2> existing = [
            SELECT Id, Name, External_ID__c, Territory_Type__c
            FROM Territory2
            WHERE External_ID__c = :externalId
            LIMIT 1
        ];
        if (!existing.isEmpty()) {
            Territory2 position = existing[0];
            if (Schema.SObjectType.Territory2.fields.getMap().containsKey('Territory_Type__c')
                && position.Territory_Type__c != 'Position') {
                position.Territory_Type__c = 'Position';
                position.Name = name;
                update position;
            }
            return position;
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
            Name = name,
            DeveloperName = 'Pos_' + String.valueOf(Math.abs(Crypto.getRandomInteger())),
            Territory2ModelId = models[0].Id,
            Territory2TypeId = types[0].Id,
            External_ID__c = externalId
        );
        if (Schema.SObjectType.Territory2.fields.getMap().containsKey('Territory_Type__c')) {
            territory.put('Territory_Type__c', 'Position');
        }
        insert territory;
        return territory;
    }

    private static Territory2 getOrCreateLineTerritory(String externalId, String name) {
        List<Territory2> existing = [
            SELECT Id, Name, External_ID__c, Territory_Type__c
            FROM Territory2
            WHERE External_ID__c = :externalId
            LIMIT 1
        ];
        if (!existing.isEmpty()) {
            Territory2 line = existing[0];
            if (line.Territory_Type__c != 'Line') {
                line.Territory_Type__c = 'Line';
                line.Name = name;
                update line;
            }
            return line;
        }

        List<Territory2Type> types = [SELECT Id FROM Territory2Type LIMIT 1];
        if (types.isEmpty()) {
            return null;
        }

        List<Territory2Model> models = [
            SELECT Id
            FROM Territory2Model
            WHERE State = 'Active'
            LIMIT 1
        ];
        if (models.isEmpty()) {
            models = [SELECT Id FROM Territory2Model LIMIT 1];
        }
        if (models.isEmpty()) {
            return null;
        }

        Territory2 territory = new Territory2(
            Name = name,
            DeveloperName = 'Line_' + String.valueOf(Math.abs(Crypto.getRandomInteger())),
            Territory2ModelId = models[0].Id,
            Territory2TypeId = types[0].Id,
            External_ID__c = externalId,
            Territory_Type__c = 'Line'
        );
        insert territory;
        return territory;
    }

    @IsTest
    static void vacantDmSeat_isReportedSeparatelyFromRollup() {
        Territory2 district = getOrCreateTestTerritory('TERR_DM_TESTVAC');
        if (district == null) {
            return;
        }
        Territory2 position = new Territory2(
            Name = 'Vacant DM Child Position',
            DeveloperName = 'Vacant_DM_Child_Position',
            Territory2ModelId = [SELECT Territory2ModelId FROM Territory2 WHERE Id = :district.Id].Territory2ModelId,
            Territory2TypeId = [SELECT Territory2TypeId FROM Territory2 WHERE Id = :district.Id].Territory2TypeId,
            ParentTerritory2Id = district.Id,
            External_ID__c = 'TERR_POS_TESTVAC'
        );
        insert position;
        insert new UserTerritory2Association(
            UserId = UserInfo.getUserId(),
            Territory2Id = position.Id,
            RoleInTerritory2 = 'Medical Rep'
        );

        Test.startTest();
        List<TerritoryManagementController.TerritoryTreeNode> roots = TerritoryManagementController.getTerritoryTree();
        Test.stopTest();

        TerritoryManagementController.TerritoryTreeNode node = findNode(roots, district.Id);
        System.assertNotEquals(null, node, 'District should be in the tree.');
        System.assertEquals('District', node.level);
        System.assertEquals(true, node.seatVacant, 'Nobody sits in the DM seat itself.');
        System.assertEquals(true, node.isVacant, 'Reps below must not make the DM seat look filled.');
        System.assertEquals(1, node.descendantUserCount, 'Rollup still counts the rep below.');
        System.assertEquals(1, node.vacantDmSeatCount, 'The vacant DM seat is counted on its own.');
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