@IsTest
private class BricksManagementControllerTest {
    @TestSetup
    static void setup() {
        Account pharmacy = new Account(
            Name = 'Brick Console Pharmacy',
            External_ID__c = 'PHARM_BRICK_CONSOLE'
        );
        Database.insert(pharmacy, AccessLevel.SYSTEM_MODE);
    }

    @IsTest
    static void getBricksByTerritory_returnsRows() {
        Brick__c brick = new Brick__c(
            Name = 'Test Brick Cairo',
            External_ID__c = 'BRICK_CONSOLE_TEST',
            Brick_Code__c = 'EG-99999',
            Data_Source__c = 'IQVIA IMS',
            Governorate__c = 'Cairo',
            City__c = 'Maadi',
            Is_Active__c = true
        );
        Database.insert(brick, AccessLevel.SYSTEM_MODE);

        Test.startTest();
        List<BricksManagementController.BrickRow> rows =
            BricksManagementController.getBricksByTerritory(null);
        List<BricksManagementController.BrickRow> listed = BricksManagementController.listBricks();
        BricksManagementController.SeedResult seed = BricksManagementController.seedBrickDemoData();
        Test.stopTest();

        System.assert(!rows.isEmpty(), 'Expected at least one brick row');
        System.assert(!listed.isEmpty());
        System.assertNotEquals(null, seed.message);
    }

    @IsTest
    static void upsertBrick_createsAndUpdates() {
        BricksManagementController.BrickUpsertInput input = new BricksManagementController.BrickUpsertInput();
        input.name = 'New Brick';
        input.externalId = 'BRICK_UPSERT_TEST';
        input.brickCode = 'EG-88888';
        input.dataSource = 'IbnSina';
        input.governorate = 'Giza';
        input.city = 'Dokki';
        input.isActive = true;

        Test.startTest();
        Id brickId = BricksManagementController.upsertBrick(input);
        input.recordId = brickId;
        input.name = 'Updated Brick';
        Id updatedId = BricksManagementController.upsertBrick(input);
        Test.stopTest();

        System.assertEquals(brickId, updatedId);
        Brick__c saved = [
            SELECT Name, Brick_Code__c
            FROM Brick__c
            WHERE Id = :brickId
            WITH SYSTEM_MODE
        ];
        System.assertEquals('Updated Brick', saved.Name);
        System.assertEquals('EG-88888', saved.Brick_Code__c);
    }

    @IsTest
    static void membership_addAndRemove() {
        Account pharmacy = [
            SELECT Id
            FROM Account
            WHERE External_ID__c = 'PHARM_BRICK_CONSOLE'
            WITH SYSTEM_MODE
            LIMIT 1
        ];
        Brick__c brick = new Brick__c(
            Name = 'Membership Brick',
            External_ID__c = 'BRICK_MEMBERSHIP_TEST',
            Is_Active__c = true
        );
        Database.insert(brick, AccessLevel.SYSTEM_MODE);

        Test.startTest();
        Id membershipId = BricksManagementController.addPharmacyToBrick(brick.Id, pharmacy.Id);
        List<BricksManagementController.BrickPharmacyRow> pharmacies =
            BricksManagementController.getBrickPharmacies(brick.Id);
        List<BricksManagementController.BrickPharmacyRow> listed =
            BricksManagementController.listPharmacies(brick.Id);
        List<BricksManagementController.PharmacyOption> options =
            BricksManagementController.searchPharmacyOptions('Brick Console');
        BricksManagementController.removePharmacyFromBrick(membershipId);
        Test.stopTest();

        System.assertEquals(1, pharmacies.size());
        System.assertEquals(1, listed.size());
        System.assert(!options.isEmpty());
    }

    @IsTest
    static void deleteBrick_blocksWhenMembershipsExist() {
        Account pharmacy = [
            SELECT Id
            FROM Account
            WHERE External_ID__c = 'PHARM_BRICK_CONSOLE'
            WITH SYSTEM_MODE
            LIMIT 1
        ];
        Brick__c brick = new Brick__c(
            Name = 'Delete Guard Brick',
            External_ID__c = 'BRICK_DELETE_GUARD',
            Is_Active__c = true
        );
        Database.insert(brick, AccessLevel.SYSTEM_MODE);
        BricksManagementController.addPharmacyToBrick(brick.Id, pharmacy.Id);

        Boolean threw = false;
        Test.startTest();
        try {
            BricksManagementController.deleteBrick(brick.Id);
        } catch (AuraHandledException e) {
            threw = true;
        }
        Test.stopTest();

        System.assert(threw, 'Expected delete to fail when memberships exist');
    }

    @IsTest
    static void deleteBrick_succeedsWhenEmpty() {
        Brick__c brick = new Brick__c(
            Name = 'Delete Empty Brick',
            External_ID__c = 'BRICK_DELETE_EMPTY',
            Is_Active__c = true
        );
        Database.insert(brick, AccessLevel.SYSTEM_MODE);

        Test.startTest();
        BricksManagementController.deleteBrick(brick.Id);
        Test.stopTest();

        System.assertEquals(
            0,
            [SELECT COUNT() FROM Brick__c WHERE Id = :brick.Id WITH SYSTEM_MODE]
        );
    }

    @IsTest
    static void assignBrickToTerritory_createsAlignment() {
        Brick__c brick = new Brick__c(
            Name = 'Align Brick',
            External_ID__c = 'BRICK_ALIGN_TEST',
            Is_Active__c = true
        );
        Database.insert(brick, AccessLevel.SYSTEM_MODE);

        List<Territory2> territories = [
            SELECT Id
            FROM Territory2
            WITH SYSTEM_MODE
            LIMIT 1
        ];
        if (territories.isEmpty()) {
            return;
        }

        Test.startTest();
        BricksManagementController.assignBrickToTerritory(brick.Id, territories[0].Id);
        List<BricksManagementController.BrickRow> scoped =
            BricksManagementController.getBricksByTerritory(territories[0].Id);
        Test.stopTest();

        System.assert(!scoped.isEmpty());
    }

    @IsTest
    static void upsertBrick_requiresName() {
        Boolean threw = false;
        try {
            BricksManagementController.upsertBrick(new BricksManagementController.BrickUpsertInput());
        } catch (AuraHandledException e) {
            threw = true;
        }
        System.assert(threw);
    }
}
