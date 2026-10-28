@IsTest
private class BricksManagementMapTest {
    static BricksManagementController.BrickDetailsInput details(Id recordId, String level, String name, Id parentId) {
        BricksManagementController.BrickDetailsInput input = new BricksManagementController.BrickDetailsInput();
        input.recordId = recordId;
        input.level = level;
        input.name = name;
        input.parentId = parentId;
        input.governorate = 'Cairo';
        input.city = 'Nasr City';
        input.dataSource = 'IQVIA IMS';
        input.isActive = true;
        input.accountSelectable = true;
        return input;
    }

    static String errorOf(BricksManagementController.BrickDetailsInput input) {
        try {
            BricksManagementController.saveBrickDetails(input);
        } catch (AuraHandledException e) {
            return e.getMessage();
        }
        return null;
    }

    @IsTest
    static void mapDataCarriesRegionsParentsAndCoverage() {
        BrickMapTestData d = BrickMapTestData.create();
        insert BrickMapTestData.client('MAP1', 30.106, 31.3, 'Street');
        insert BrickMapTestData.client('MAP2', 30.1, 31.3, 'Governorate');

        BricksManagementController.BrickMapData micro = BricksManagementController.getBrickMap('702');
        System.assertEquals('702', micro.level);
        System.assertEquals(4, micro.bricks.size());
        System.assertEquals(2, micro.parents.size(), 'the 148 bricks to roll up to');
        System.assertEquals(4, micro.stats.total702);
        System.assertEquals(3, micro.stats.mapped702);
        System.assertEquals(1, micro.stats.mapped148);
        System.assertEquals(2, micro.stats.clientsWithLocation);
        System.assertEquals(1, micro.stats.clientsPlaced);
        System.assertEquals(1, micro.stats.clientsApproximate);
        for (BricksManagementController.MapBrick b : micro.bricks) {
            if (b.id == d.a702.Id) {
                System.assertEquals(1, b.clientCount);
                System.assertNotEquals(null, b.geometry);
                System.assertEquals('BRICK1 TEST NORTH', b.parentName);
            }
        }

        BricksManagementController.BrickMapData commercial = BricksManagementController.getBrickMap('148');
        System.assertEquals(2, commercial.bricks.size());
        System.assertEquals(3, commercial.children.size(), 'mapped 702 regions to draw inside the 148s');
        for (BricksManagementController.MapBrick b : commercial.bricks) {
            if (b.id == d.north148.Id) {
                System.assertEquals(4, b.childCount);
                System.assertEquals(3, b.childMapped);
            }
        }

        List<BricksManagementController.SalesPoint> points = BricksManagementController.getSalesPoints();
        System.assertEquals(2, points.size());
    }

    @IsTest
    static void bricksAreCreatedRenamedAndValidated() {
        BrickMapTestData d = BrickMapTestData.create();
        BricksManagementController.MapBrick created = BricksManagementController.saveBrickDetails(
            details(null, '702', '  New   Zone  ', d.north148.Id)
        );
        System.assertEquals('New Zone', created.name);
        System.assertEquals('702', created.level);
        System.assertEquals('BRICK_NEW_ZONE', created.externalId);
        System.assertEquals('New Zone', created.code, 'code defaults to the name like the organogram bricks');

        BricksManagementController.MapBrick renamed = BricksManagementController.saveBrickDetails(
            details(created.id, null, 'Renamed Zone', d.north148.Id)
        );
        System.assertEquals('Renamed Zone', renamed.name);
        System.assertEquals('BRICK_NEW_ZONE', renamed.externalId, 'external id stays the organogram key');

        System.assert(errorOf(details(null, '702', 'Test A', d.north148.Id)).contains('already called'));
        System.assert(errorOf(details(null, '702', 'No Parent', null)).contains('Choose the 148'));
        System.assert(errorOf(details(null, '702', 'Wrong Parent', d.area70.Id)).contains('must roll up to a 148'));
        System.assert(errorOf(details(null, '70', 'Area', null)).contains('148 or 702'));
        System.assert(errorOf(details(null, '148', '', d.area70.Id)).contains('required'));

        BricksManagementController.MapBrick commercial = BricksManagementController.saveBrickDetails(
            details(null, '148', 'BRICK9 NEW', d.area70.Id)
        );
        System.assertEquals('BRICK148_BRICK9_NEW', commercial.externalId);
    }

    @IsTest
    static void moving702ToAnother148MovesItsClientsAndAccounts() {
        BrickMapTestData d = BrickMapTestData.create();
        Distributor_Sellout_Alias__c c = BrickMapTestData.client('MOVE1', 30.106, 31.3, 'Street');
        insert c;
        Account a = new Account(Name = 'Moving Pharmacy', BillingCountry = 'Egypt', Brick_702__c = d.a702.Id);
        insert a;

        Test.startTest();
        BricksManagementController.saveBrickDetails(details(d.a702.Id, null, 'Test A', d.south148.Id));
        Test.stopTest();

        System.assertEquals(d.south148.Id, [SELECT Brick_148__c FROM Distributor_Sellout_Alias__c WHERE Id = :c.Id].Brick_148__c);
        System.assertEquals(d.south148.Id, [SELECT Brick_148__c FROM Account WHERE Id = :a.Id].Brick_148__c);
    }

    @IsTest
    static void savingARegionPlacesTheClientsAroundIt() {
        BrickMapTestData d = BrickMapTestData.create();
        Distributor_Sellout_Alias__c c = BrickMapTestData.client('REG1', 30.3, 31.6, 'Street');
        insert c;
        System.assertEquals(
            BrickLocator.OUTSIDE,
            [SELECT Brick_Placement__c FROM Distributor_Sellout_Alias__c WHERE Id = :c.Id].Brick_Placement__c
        );

        BricksManagementController.MapBrick saved = BricksManagementController.saveBrickRegion(
            d.bare702.Id,
            BrickMapTestData.square(30.3, 31.6, 0.01),
            'Drawn'
        );
        System.assert(saved.areaKm2 > 4, 'area ' + saved.areaKm2);
        System.assertEquals('Drawn', saved.regionSource);
        System.assertEquals(1, saved.clientCount);
        c = [SELECT Brick_702__c, Brick_148__c FROM Distributor_Sellout_Alias__c WHERE Id = :c.Id];
        System.assertEquals(d.bare702.Id, c.Brick_702__c);
        System.assertEquals(d.north148.Id, c.Brick_148__c, 'the 702 parent, even outside the 148 region');

        try {
            BricksManagementController.saveBrickRegion(d.bare702.Id, '{"type":"Polygon","coordinates":[]}', 'Drawn');
            System.assert(false, 'expected an error');
        } catch (AuraHandledException e) {
            System.assert(e.getMessage().contains('outline'), e.getMessage());
        }
        try {
            BricksManagementController.saveBrickRegion(d.area70.Id, BrickMapTestData.square(30.3, 31.6, 0.01), 'Drawn');
            System.assert(false, 'expected an error');
        } catch (AuraHandledException e) {
            System.assert(e.getMessage().contains('148 and 702'), e.getMessage());
        }

        BricksManagementController.MapBrick removed = BricksManagementController.saveBrickRegion(d.bare702.Id, null, null);
        System.assertEquals(null, removed.geometry);
        System.assertEquals(null, removed.areaKm2);
        System.assertEquals(
            BrickLocator.OUTSIDE,
            [SELECT Brick_Placement__c FROM Distributor_Sellout_Alias__c WHERE Id = :c.Id].Brick_Placement__c
        );
    }

    @IsTest
    static void locatingAPointNamesBothBricks() {
        BrickMapTestData d = BrickMapTestData.create();
        BricksManagementController.LocateResult hit = BricksManagementController.locatePoint(30.106, 31.3);
        System.assertEquals(d.a702.Id, hit.brick702Id);
        System.assertEquals('Test A', hit.brick702Name);
        System.assertEquals('BRICK1 TEST NORTH', hit.brick148Name);
        System.assertEquals(BrickLocator.IN_REGION, hit.status);
        try {
            BricksManagementController.locatePoint(null, 31.3);
            System.assert(false, 'expected an error');
        } catch (AuraHandledException e) {
            System.assert(e.getMessage().contains('point'));
        }
    }

    @IsTest
    static void applyImsOutlinesUsesTheScrapedPack() {
        BrickMapTestData d = BrickMapTestData.create();
        ImsBrickOutlineService.packOverride = new Map<String, String>{
            d.bare702.External_ID__c => BrickMapTestData.square(30.4, 31.4, 0.01)
        };
        Test.startTest();
        Integer n = BricksManagementController.applyImsOutlines(false);
        Test.stopTest();
        System.assertEquals(1, n);
        System.assertEquals(
            'Imported',
            [SELECT Boundary_Source__c FROM Brick__c WHERE Id = :d.bare702.Id].Boundary_Source__c
        );
    }

    @IsTest
    static void salesPlacementRunsInTheBackground() {
        BrickMapTestData.create();
        Test.startTest();
        BricksManagementController.PlacementJob job = BricksManagementController.startSalesPlacement();
        Test.stopTest();
        System.assertNotEquals(null, job.jobId);
        BricksManagementController.PlacementJob after = BricksManagementController.getSalesPlacementStatus();
        System.assertEquals(job.jobId, after.jobId);
        System.assertEquals(false, after.running);
    }

    @IsTest
    static void territoriesOfABrickCanBeListedAndRemoved() {
        BrickMapTestData d = BrickMapTestData.create();
        Brick_Territory_Alignment__c alignment = new Brick_Territory_Alignment__c(
            Brick__c = d.a702.Id,
            External_ID__c = 'TEST_A|T1',
            Territory2_Id__c = '0MI000000000001AAA',
            Share__c = 1,
            Is_Active__c = true
        );
        insert alignment;
        List<BricksManagementController.TerritoryLink> links = BricksManagementController.getBrickTerritories(d.a702.Id);
        System.assertEquals(1, links.size());
        System.assertEquals('0MI000000000001AAA', links[0].territoryName, 'unknown territory falls back to its id');

        BricksManagementController.removeBrickTerritory(alignment.Id);
        System.assertEquals(0, BricksManagementController.getBrickTerritories(d.a702.Id).size());
        System.assertEquals(0, BricksManagementController.getBrickTerritories(null).size());
    }

    @IsTest
    static void pharmacySearchUsesTheSharedNameEngine() {
        Id pharmacyType = Schema.SObjectType.Account.getRecordTypeInfosByDeveloperName().get('Pharmacy').getRecordTypeId();
        insert new List<Account>{
            new Account(Name = 'Ahmed Pharmacy', BillingCountry = 'Egypt', RecordTypeId = pharmacyType),
            new Account(Name = 'Hussein Pharmacy', BillingCountry = 'Egypt', RecordTypeId = pharmacyType)
        };
        Set<String> arabic = new Set<String>();
        for (BricksManagementController.PharmacyOption o : BricksManagementController.searchPharmacyOptions('احمد')) {
            arabic.add(o.label);
        }
        System.assert(arabic.contains('Ahmed Pharmacy'), 'Arabic spelling finds the Latin name: ' + arabic);

        Set<String> hassan = new Set<String>();
        for (BricksManagementController.PharmacyOption o : BricksManagementController.searchPharmacyOptions('Hassan')) {
            hassan.add(o.label);
        }
        System.assert(!hassan.contains('Hussein Pharmacy'), 'Hassan and Hussein stay apart: ' + hassan);
    }

    @IsTest
    static void bricksInUseCannotBeDeleted() {
        BrickMapTestData d = BrickMapTestData.create();
        try {
            BricksManagementController.deleteBrick(d.north148.Id);
            System.assert(false, 'expected an error');
        } catch (AuraHandledException e) {
            System.assert(e.getMessage().contains('bricks under this brick'), e.getMessage());
        }
        insert new Account(Name = 'In Brick', BillingCountry = 'Egypt', Brick_702__c = d.bare702.Id);
        try {
            BricksManagementController.deleteBrick(d.bare702.Id);
            System.assert(false, 'expected an error');
        } catch (AuraHandledException e) {
            System.assert(e.getMessage().contains('accounts are in this brick'), e.getMessage());
        }
        BricksManagementController.deleteBrick(d.b702.Id);
        System.assertEquals(0, [SELECT COUNT() FROM Brick__c WHERE Id = :d.b702.Id]);
    }

    @IsTest
    static void brickClientsListAddressPlacedClientsAndLatestSales() {
        BrickMapTestData d = BrickMapTestData.create();
        Distributor_Sellout_Alias__c byAddress = BrickMapTestData.client('ADDR1', null, null, null);
        byAddress.Address__c = 'Midan El Abbasiya';
        byAddress.Brick_Placement__c = DistributorSelloutBrickPlacement.ADDRESS_MATCH;
        byAddress.Brick_702__c = d.bare702.Id;
        byAddress.Brick_148__c = d.north148.Id;
        insert byAddress;
        Date month = Date.newInstance(2026, 9, 1);
        insert new List<Pharmacy_Sales_Withdrawal__c>{
            new Pharmacy_Sales_Withdrawal__c(
                Data_Source__c = 'POS', Report_Month__c = month.addMonths(-1), Brick_702__c = d.bare702.Id,
                Product2_Id__c = 'x', Quantity_Withdrawn__c = 1, Unit_Price__c = 5, Unique_Key__c = 'BC1'
            ),
            new Pharmacy_Sales_Withdrawal__c(
                Data_Source__c = 'POS', Report_Month__c = month, Brick_702__c = d.bare702.Id,
                Product2_Id__c = 'x', Quantity_Withdrawn__c = 3, Unit_Price__c = 10, Unique_Key__c = 'BC2'
            )
        };

        Test.startTest();
        BricksManagementController.BrickClientsPayload micro = BricksManagementController.getBrickClients(d.bare702.Id, '702');
        BricksManagementController.BrickClientsPayload commercial = BricksManagementController.getBrickClients(d.north148.Id, '148');
        BricksManagementController.BrickClientsPayload none = BricksManagementController.getBrickClients(null, '702');
        Test.stopTest();

        System.assertEquals(1, micro.total, 'a client placed by address has no map point but is still listed');
        System.assertEquals('Midan El Abbasiya', micro.clients[0].address);
        System.assertEquals(month, micro.salesMonth);
        System.assertEquals(1, micro.salesLines);
        System.assertEquals(3, micro.salesQuantity);
        System.assertEquals(30, micro.salesRevenue);
        System.assertEquals(1, commercial.total);
        System.assertEquals(0, none.total);
    }
}
