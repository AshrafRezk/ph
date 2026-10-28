@IsTest
private class BrickSalesPlacementTest {
    static Product2 product() {
        Product2 p = new Product2(Name = 'BRICK PLACEMENT PRODUCT', ProductCode = 'BPP1', External_ID__c = 'BPP1', IsActive = true);
        insert p;
        insert new Distributor_Product_Alias__c(
            Distributor_Code__c = 'Egydrug',
            Distributor_Item_Code__c = 'ITEM1',
            Distributor_Item_Name__c = 'BRICK PLACEMENT PRODUCT',
            Product2_Id__c = p.Id,
            Zeta_Code__c = 'BPP1',
            Match_Confidence__c = 100,
            Match_Method__c = 'Seeded',
            Status__c = 'Confirmed',
            Unique_Key__c = 'Egydrug|ITEM1'
        );
        return p;
    }

    static Account pharmacy(String name) {
        Account a = new Account(Name = name, BillingCountry = 'Egypt');
        insert a;
        return a;
    }

    static Pharmacy_Sales_Withdrawal__c line(Id pharmacyId, Id productId, Id batchId) {
        return new Pharmacy_Sales_Withdrawal__c(
            Data_Source__c = DistributorMatchingUtil.toDataSource('Egydrug'),
            Report_Month__c = Date.newInstance(2026, 6, 1),
            Pharmacy_Account__c = pharmacyId,
            Product2_Id__c = String.valueOf(productId),
            Quantity_Withdrawn__c = 1,
            Unique_Key__c = 'BPT_' + pharmacyId + '_' + productId,
            Import_Batch__c = batchId,
            Import_Run__c = 1
        );
    }

    static Sales_Data_Import_Batch__c batch() {
        Sales_Data_Import_Batch__c b = new Sales_Data_Import_Batch__c(
            File_Name__c = 'bricks.xlsx',
            Distributor_Code__c = 'Egydrug',
            Status__c = 'Queued',
            Report_Month__c = Date.newInstance(2026, 6, 1),
            Chunks_Expected__c = 1,
            Chunks_Received__c = 1,
            Chunks_Processed__c = 0,
            Run_Number__c = 1,
            Rows_Inserted__c = 0,
            Rows_Updated__c = 0,
            Rows_Failed__c = 0,
            Upload_Rows_Failed__c = 0
        );
        insert b;
        return b;
    }

    @IsTest
    static void importedSalesLinesTakeTheBrickOfTheClientLocation() {
        BrickMapTestData d = BrickMapTestData.create();
        product();
        Account ph = pharmacy('Located Pharmacy');
        Distributor_Sellout_Alias__c c = BrickMapTestData.client('CLIENT1', 30.106, 31.3, 'Street');
        c.Pharmacy_Account__c = ph.Id;
        c.Status__c = 'Confirmed';
        c.Match_Confidence__c = 100;
        c.Match_Method__c = 'Manual';
        insert new List<Distributor_Sellout_Alias__c>{ c, BrickMapTestData.client('NO_PHARMACY', 30.106, 31.3, 'Street') };
        Sales_Data_Import_Batch__c b = batch();
        DistributorImportService.stageChunk(
            b.Id,
            0,
            new List<Map<String, Object>>{
                new Map<String, Object>{ 'itemCode' => 'ITEM1', 'clientCode' => 'CLIENT1', 'quantity' => 3 },
                new Map<String, Object>{ 'itemCode' => 'ITEM1', 'clientCode' => 'CLIENT1', 'quantity' => ' 2 ' },
                new Map<String, Object>{ 'itemCode' => 'ITEM1', 'clientCode' => 'NO_PHARMACY', 'quantity' => 4 },
                new Map<String, Object>{ 'itemCode' => 'ITEM1', 'clientCode' => 'UNKNOWN', 'quantity' => 4 }
            }
        );

        Test.startTest();
        System.enqueueJob(new DistributorWithdrawalQueueable(b.Id));
        Test.stopTest();

        List<Pharmacy_Sales_Withdrawal__c> lines = [
            SELECT
                Brick__c,
                Brick_702__c,
                Brick_148__c,
                Brick_Source__c,
                Quantity_Withdrawn__c,
                Pharmacy_Account__c,
                Distributor_Client__r.Distributor_Client_Code__c
            FROM Pharmacy_Sales_Withdrawal__c
            ORDER BY Quantity_Withdrawn__c DESC
        ];
        System.assertEquals(2, lines.size(), 'a located client is a sales line without a CRM pharmacy; an unknown client is not');
        Pharmacy_Sales_Withdrawal__c w = lines[0];
        System.assertEquals(5, w.Quantity_Withdrawn__c);
        System.assertEquals(ph.Id, w.Pharmacy_Account__c);
        System.assertEquals(d.a702.Id, w.Brick_702__c);
        System.assertEquals(d.north148.Id, w.Brick_148__c);
        System.assertEquals(d.a702.Id, w.Brick__c, 'alignment brick is the 702, like Account.Brick__c');
        System.assertEquals(SalesLineBrickResolver.FROM_LOCATION, w.Brick_Source__c);

        Pharmacy_Sales_Withdrawal__c unlinked = lines[1];
        System.assertEquals(4, unlinked.Quantity_Withdrawn__c);
        System.assertEquals(null, unlinked.Pharmacy_Account__c);
        System.assertEquals('NO_PHARMACY', unlinked.Distributor_Client__r.Distributor_Client_Code__c);
        System.assertEquals(d.a702.Id, unlinked.Brick_702__c, 'placed by the client location alone');
    }

    @IsTest
    static void salesOfClientsWithNoPlaceAreKeptAsUnplaced() {
        BrickMapTestData.create();
        Product2 p = product();
        insert BrickMapTestData.client('NOWHERE', null, null, null);
        Sales_Data_Import_Batch__c b = batch();
        DistributorImportService.stageChunk(
            b.Id,
            0,
            new List<Map<String, Object>>{
                new Map<String, Object>{ 'itemCode' => 'ITEM1', 'clientCode' => 'NOWHERE', 'quantity' => 3, 'unitPrice' => 10 },
                new Map<String, Object>{ 'itemCode' => 'ITEM1', 'clientCode' => 'NOWHERE', 'quantity' => 2 },
                new Map<String, Object>{ 'itemCode' => 'ITEM1', 'clientCode' => 'UNKNOWN', 'quantity' => 4 }
            }
        );

        Test.startTest();
        System.enqueueJob(new DistributorWithdrawalQueueable(b.Id));
        Test.stopTest();

        System.assertEquals(0, [SELECT COUNT() FROM Pharmacy_Sales_Withdrawal__c], 'no place, no sales line');
        List<Distributor_Unplaced_Sale__c> unplaced = [
            SELECT Quantity__c, Unit_Price__c, Revenue__c, Product__c, Data_Source__c, Report_Month__c, Distributor_Client__r.Distributor_Client_Code__c
            FROM Distributor_Unplaced_Sale__c
        ];
        System.assertEquals(1, unplaced.size(), 'one row per client and product; an unknown client is not kept');
        System.assertEquals(5, unplaced[0].Quantity__c);
        System.assertEquals(10, unplaced[0].Unit_Price__c);
        System.assertEquals(50, unplaced[0].Revenue__c);
        System.assertEquals(p.Id, unplaced[0].Product__c);
        System.assertEquals('NOWHERE', unplaced[0].Distributor_Client__r.Distributor_Client_Code__c);
        System.assertEquals(Date.newInstance(2026, 6, 1), unplaced[0].Report_Month__c);
        System.assertEquals(3, [SELECT Rows_Failed__c FROM Sales_Data_Import_Batch__c WHERE Id = :b.Id].Rows_Failed__c);
    }

    @IsTest
    static void addressPlacedClientsKeepTheirBrickUntilLocated() {
        BrickMapTestData d = BrickMapTestData.create();
        Distributor_Sellout_Alias__c byAddress = BrickMapTestData.client('BY_ADDRESS', null, null, null);
        byAddress.Brick_702__c = d.b702.Id;
        byAddress.Brick_148__c = d.north148.Id;
        byAddress.Brick_Placement__c = DistributorSelloutBrickPlacement.ADDRESS_MATCH;
        insert byAddress;
        byAddress = [
            SELECT Id, Latitude__c, Longitude__c, Geocode_Precision__c, Brick_702__c, Brick_148__c, Brick_Placement__c
            FROM Distributor_Sellout_Alias__c
            WHERE Id = :byAddress.Id
        ];

        System.assertEquals(0, DistributorSelloutBrickPlacement.stamp(new List<Distributor_Sellout_Alias__c>{ byAddress }).size());
        System.assertEquals(d.b702.Id, byAddress.Brick_702__c, 'Apply regions does not erase an address placement');

        byAddress.Latitude__c = 30.106;
        byAddress.Longitude__c = 31.3;
        byAddress.Geocode_Precision__c = 'Street';
        System.assertEquals(1, DistributorSelloutBrickPlacement.stamp(new List<Distributor_Sellout_Alias__c>{ byAddress }).size());
        System.assertEquals(d.a702.Id, byAddress.Brick_702__c, 'a map location replaces it');
    }

    @IsTest
    static void pharmacyBricksAndMembershipsAreTheFallbacks() {
        BrickMapTestData d = BrickMapTestData.create();
        Account withBricks = new Account(
            Name = 'Pharmacy With Bricks',
            BillingCountry = 'Egypt',
            Brick_702__c = d.b702.Id,
            Brick_148__c = d.north148.Id
        );
        Account withMembership = pharmacy('Pharmacy With Membership');
        Account bare = pharmacy('Pharmacy Without Bricks');
        insert withBricks;
        insert new Brick_Pharmacy__c(
            Brick__c = d.bare702.Id,
            Pharmacy_Account__c = withMembership.Id,
            Is_Active__c = true,
            Unique_Key__c = d.bare702.Id + ':' + withMembership.Id
        );
        SalesLineBrickResolver resolver = new SalesLineBrickResolver(
            new Set<Id>{ withBricks.Id, withMembership.Id, bare.Id }
        );

        Distributor_Sellout_Alias__c located = new Distributor_Sellout_Alias__c(
            Brick_702__c = d.inner702.Id,
            Brick_148__c = d.north148.Id
        );
        System.assertEquals(SalesLineBrickResolver.FROM_LOCATION, resolver.resolve(located, withBricks.Id).source);

        SalesLineBrickResolver.Bricks fromPharmacy = resolver.resolve(new Distributor_Sellout_Alias__c(), withBricks.Id);
        System.assertEquals(SalesLineBrickResolver.FROM_PHARMACY, fromPharmacy.source);
        System.assertEquals(d.b702.Id, fromPharmacy.alignment);

        SalesLineBrickResolver.Bricks fromMembership = resolver.resolve(null, withMembership.Id);
        System.assertEquals(SalesLineBrickResolver.FROM_MEMBERSHIP, fromMembership.source);
        System.assertEquals(d.bare702.Id, fromMembership.brick702);
        System.assertEquals(d.north148.Id, fromMembership.brick148, 'the 702 membership rolls up to its 148');

        System.assertEquals(null, resolver.resolve(null, bare.Id));
        Pharmacy_Sales_Withdrawal__c stale = new Pharmacy_Sales_Withdrawal__c(Brick__c = d.a702.Id);
        System.assertEquals(true, SalesLineBrickResolver.applyTo(stale, null));
        System.assertEquals(null, stale.Brick__c, 'an unplaced line does not keep an old brick');
    }

    @IsTest
    static void applyingRegionsUpdatesClientsThenSalesLines() {
        BrickMapTestData d = BrickMapTestData.create();
        Product2 p = product();
        Account ph = pharmacy('Moved Pharmacy');
        Distributor_Sellout_Alias__c c = BrickMapTestData.client('CLIENT2', 30.106, 31.3, 'Street');
        c.Pharmacy_Account__c = ph.Id;
        insert c;
        Sales_Data_Import_Batch__c b = batch();
        Pharmacy_Sales_Withdrawal__c w = line(ph.Id, p.Id, b.Id);
        insert w;

        // The region moved away from the client after it was placed.
        d.a702.Boundary_GeoJSON__c = BrickMapTestData.square(30.5, 31.5, 0.01);
        update d.a702;

        Test.startTest();
        Database.executeBatch(new BrickSalesPlacementBatch(), 200);
        Test.stopTest();
        c = [SELECT Brick_702__c, Brick_148__c FROM Distributor_Sellout_Alias__c WHERE Id = :c.Id];
        System.assertEquals(null, c.Brick_702__c);
        System.assertEquals(d.north148.Id, c.Brick_148__c);

        List<Pharmacy_Sales_Withdrawal__c> changed = BrickSalesPlacementBatch.placeSalesLines(
            [
                SELECT
                    Id,
                    Pharmacy_Account__c,
                    Distributor_Client__c,
                    Data_Source__c,
                    Brick__c,
                    Brick_702__c,
                    Brick_148__c,
                    Brick_Source__c
                FROM Pharmacy_Sales_Withdrawal__c
            ]
        );
        System.assertEquals(1, changed.size());
        System.assertEquals(d.north148.Id, changed[0].Brick__c);
        System.assertEquals(SalesLineBrickResolver.FROM_LOCATION, changed[0].Brick_Source__c);
    }

    @IsTest
    static void salesLinePhaseRunsAsABatchToo() {
        BrickMapTestData d = BrickMapTestData.create();
        Product2 p = product();
        Account ph = pharmacy('Batch Pharmacy');
        Distributor_Sellout_Alias__c c = BrickMapTestData.client('CLIENT3', 30.106, 31.3, 'Street');
        c.Pharmacy_Account__c = ph.Id;
        insert c;
        insert line(ph.Id, p.Id, batch().Id);

        Test.startTest();
        Database.executeBatch(new BrickSalesPlacementBatch(BrickSalesPlacementBatch.Phase.SALES_LINES), 200);
        Test.stopTest();

        Pharmacy_Sales_Withdrawal__c w = [SELECT Brick_702__c, Brick_Source__c FROM Pharmacy_Sales_Withdrawal__c];
        System.assertEquals(d.a702.Id, w.Brick_702__c);
        System.assertEquals(SalesLineBrickResolver.FROM_LOCATION, w.Brick_Source__c);
    }

    @IsTest
    static void onlyOneRunAtATime() {
        Test.startTest();
        Id first = BrickSalesPlacementBatch.startRun();
        Id second = BrickSalesPlacementBatch.startRun();
        Test.stopTest();
        System.assertNotEquals(null, first);
        System.assertEquals(first, second);
    }

    @IsTest
    static void accountsFollowA702ToItsNew148() {
        BrickMapTestData d = BrickMapTestData.create();
        Account a = new Account(Name = 'Follows Parent', BillingCountry = 'Egypt', Brick_702__c = d.a702.Id, Brick_148__c = d.north148.Id);
        insert a;
        d.a702.Parent_Brick__c = d.south148.Id;
        update d.a702;

        Test.startTest();
        System.enqueueJob(new BrickReparentQueueable(d.a702.Id, null));
        Test.stopTest();

        System.assertEquals(d.south148.Id, [SELECT Brick_148__c FROM Account WHERE Id = :a.Id].Brick_148__c);
    }
}
