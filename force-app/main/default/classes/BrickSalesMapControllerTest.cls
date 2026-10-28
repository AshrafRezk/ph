@IsTest
private class BrickSalesMapControllerTest {
    static final Date MONTH = Date.newInstance(2026, 9, 1);

    static Product2 product(String name) {
        Product2 p = new Product2(Name = name, ProductCode = name, External_ID__c = name, IsActive = true);
        insert p;
        return p;
    }

    static Pharmacy_Sales_Withdrawal__c line(Distributor_Sellout_Alias__c c, Product2 p, Decimal qty, Decimal price, Id b702, Id b148) {
        return new Pharmacy_Sales_Withdrawal__c(
            Data_Source__c = DistributorMatchingUtil.toDataSource('Egydrug'),
            Report_Month__c = MONTH,
            Distributor_Client__c = c.Id,
            Product__c = p.Id,
            Product2_Id__c = String.valueOf(p.Id),
            Quantity_Withdrawn__c = qty,
            Unit_Price__c = price,
            Brick_702__c = b702,
            Brick_148__c = b148,
            Unique_Key__c = 'BSM_' + c.Id + '_' + p.Id
        );
    }

    static Distributor_Unplaced_Sale__c unplaced(Distributor_Sellout_Alias__c c, Product2 p, Decimal qty, Decimal price) {
        return new Distributor_Unplaced_Sale__c(
            Data_Source__c = DistributorMatchingUtil.toDataSource('Egydrug'),
            Report_Month__c = MONTH,
            Distributor_Client__c = c.Id,
            Product__c = p.Id,
            Quantity__c = qty,
            Unit_Price__c = price,
            Unique_Key__c = 'BSMU_' + c.Id + '_' + p.Id
        );
    }

    @IsTest
    static void salesAddUpByBrickProductAndClient() {
        BrickMapTestData d = BrickMapTestData.create();
        Product2 a = product('BSM A');
        Product2 b = product('BSM B');
        Distributor_Sellout_Alias__c c1 = BrickMapTestData.client('C1', 30.106, 31.3, 'Street');
        Distributor_Sellout_Alias__c c2 = BrickMapTestData.client('C2', 30.106, 31.3, 'Street');
        insert new List<Distributor_Sellout_Alias__c>{ c1, c2 };
        insert new List<Pharmacy_Sales_Withdrawal__c>{
            line(c1, a, 2, 10, d.a702.Id, d.north148.Id),
            line(c2, a, 1, 10, d.a702.Id, d.north148.Id),
            line(c2, b, 5, 3, d.b702.Id, d.north148.Id)
        };
        String source = DistributorMatchingUtil.toDataSource('Egydrug');

        BrickSalesMapController.SalesFilters filters = BrickSalesMapController.getSalesFilters();
        System.assertEquals(2, filters.placed.size(), 'one row per distributor, month and product');
        System.assertEquals(0, filters.unplaced.size());

        BrickSalesMapController.SalesChunk chunk = BrickSalesMapController.getSalesChunk('702', MONTH, new List<Id>{ a.Id, b.Id });
        Map<Id, BrickSalesMapController.BrickTotal> by702 = new Map<Id, BrickSalesMapController.BrickTotal>();
        for (BrickSalesMapController.BrickTotal t : chunk.bricks) {
            by702.put(t.brickId, t);
            System.assertEquals(source, t.source);
        }
        System.assertEquals(30, by702.get(d.a702.Id).revenue);
        System.assertEquals(2, by702.get(d.a702.Id).lines);
        System.assertEquals(15, by702.get(d.b702.Id).revenue);
        System.assertEquals(2, chunk.products.size(), 'one row per product and distributor');

        BrickSalesMapController.SalesChunk productOnly = BrickSalesMapController.getSalesChunk('148', MONTH, new List<Id>{ b.Id });
        System.assertEquals(1, productOnly.bricks.size());
        System.assertEquals(d.north148.Id, productOnly.bricks[0].brickId);
        System.assertEquals(5, productOnly.bricks[0].quantity);
        System.assertEquals('BSM B', productOnly.products[0].productName);

        BrickSalesMapController.SalesBreakdown brick = BrickSalesMapController.getBrickSales(d.north148.Id, '148', source, MONTH, MONTH.addMonths(2), null);
        System.assertEquals(3, brick.lines);
        System.assertEquals(45, brick.revenue);
        System.assertEquals(2, brick.products.size());
        System.assertEquals(a.Id, brick.products[0].productId, 'highest revenue first');
        System.assertEquals(2, brick.clientCount);
        System.assertEquals('Client C2', brick.clients[0].name, 'highest revenue first');

        BrickSalesMapController.DistributorCounts counts = BrickSalesMapController.getDistributorCounts('702', MONTH, MONTH, null);
        System.assertEquals(1, counts.sources.size());
        System.assertEquals(source, counts.sources[0].source);
        System.assertEquals(3, counts.sources[0].lines);
        System.assertEquals(2, counts.sources[0].bricks, 'a702 and b702');
        System.assertEquals(3, counts.sources[0].addressLines + counts.sources[0].pointLines + counts.sources[0].otherLines);
        System.assertEquals(2, counts.bricks.size());
    }

    @IsTest
    static void unplacedRowsSplitStillUnplacedFromPlacedSince() {
        BrickMapTestData d = BrickMapTestData.create();
        Product2 a = product('BSM A');
        Distributor_Sellout_Alias__c nowhere = BrickMapTestData.client('NOWHERE', null, null, null);
        Distributor_Sellout_Alias__c fixedSince = BrickMapTestData.client('FIXED', null, null, null);
        insert new List<Distributor_Sellout_Alias__c>{ nowhere, fixedSince };
        insert new List<Distributor_Unplaced_Sale__c>{ unplaced(nowhere, a, 4, 10), unplaced(fixedSince, a, 1, 7) };
        fixedSince.Brick_702__c = d.a702.Id;
        update fixedSince;

        BrickSalesMapController.SalesFilters filters = BrickSalesMapController.getSalesFilters();
        System.assertEquals(1, filters.unplaced.size());
        System.assertEquals(2, filters.unplaced[0].lines);

        BrickSalesMapController.SalesBreakdown result = BrickSalesMapController.getUnplacedSales(null, MONTH, MONTH, null);
        System.assertEquals(1, result.lines);
        System.assertEquals(40, result.revenue);
        System.assertEquals(1, result.clients.size());
        System.assertEquals('NOWHERE', result.clients[0].code);
        System.assertEquals(false, result.clients[0].placedSince);
        System.assertEquals(1, result.placedSinceLines);
        System.assertEquals(7, result.placedSinceRevenue);
        System.assertEquals(1, BrickSalesMapController.getDistributorCounts('148', MONTH.addMonths(-2), MONTH, a.Id).sources[0].unplacedRows);
    }

    @IsTest
    static void tooManyRowsAskForANarrowerFilter() {
        BrickMapTestData d = BrickMapTestData.create();
        Product2 a = product('BSM A');
        Distributor_Sellout_Alias__c c1 = BrickMapTestData.client('C1', 30.106, 31.3, 'Street');
        insert c1;
        insert line(c1, a, 1, 1, d.a702.Id, d.north148.Id);
        BrickSalesMapController.maxChunkRows = 0;
        BrickSalesMapController.maxBreakdownRows = 0;
        try {
            BrickSalesMapController.getSalesChunk('702', MONTH, new List<Id>{ a.Id });
            System.assert(false, 'expected a fewer-products message');
        } catch (AuraHandledException e) {
            System.assert(e.getMessage().contains('Pick fewer products'), e.getMessage());
        }
        try {
            BrickSalesMapController.getBrickSales(d.a702.Id, '702', null, MONTH, MONTH, null);
            System.assert(false, 'expected a narrower-filter message');
        } catch (AuraHandledException e) {
            System.assert(e.getMessage().contains('Pick a distributor or a product'), e.getMessage());
        }
        try {
            BrickSalesMapController.getSalesChunk('702', null, new List<Id>{ a.Id });
            System.assert(false, 'expected a month message');
        } catch (AuraHandledException e) {
            System.assertEquals('Choose a month.', e.getMessage());
        }
        try {
            BrickSalesMapController.getSalesChunk('702', MONTH, new List<Id>());
            System.assert(false, 'expected a product message');
        } catch (AuraHandledException e) {
            System.assertEquals('Choose at least one product.', e.getMessage());
        }
        try {
            BrickSalesMapController.getUnplacedSales(null, MONTH, MONTH.addMonths(-1), null);
            System.assert(false, 'expected a range message');
        } catch (AuraHandledException e) {
            System.assertEquals('The end month is before the start month.', e.getMessage());
        }
    }
}
