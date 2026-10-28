@IsTest
private class PharmacySalesExportControllerTest {
    @TestSetup
    static void setup() {
        Account pharmacy = new Account(Name = 'Export Pharmacy', External_ID__c = 'PHARM-EXP-1');
        insert pharmacy;
        List<Product2> products = new List<Product2>{
            new Product2(Name = 'Export Product A', ProductCode = 'EXP-A', IsActive = true, External_ID__c = 'PROD-EXP-A'),
            new Product2(Name = 'Export Product B', ProductCode = 'EXP-B', IsActive = true, External_ID__c = 'PROD-EXP-B')
        };
        insert products;
        Date month = Date.newInstance(2026, 9, 1);
        List<Pharmacy_Sales_Withdrawal__c> rows = new List<Pharmacy_Sales_Withdrawal__c>();
        for (Integer i = 0; i < 3; i++) {
            Product2 p = products[Math.mod(i, 2)];
            rows.add(new Pharmacy_Sales_Withdrawal__c(
                Data_Source__c = i == 2 ? 'Ebda' : 'IbnSina',
                Report_Month__c = month,
                Pharmacy_Account__c = pharmacy.Id,
                Product2_Id__c = String.valueOf(p.Id),
                // Row 0 has no Product__c on purpose: the export falls back to Product2_Id__c.
                Product__c = i == 0 ? null : p.Id,
                Quantity_Withdrawn__c = 10 * (i + 1),
                Unit_Price__c = i == 1 ? null : 5,
                Unique_Key__c = 'EXP_' + i
            ));
        }
        Database.insert(rows, AccessLevel.SYSTEM_MODE);
    }

    @IsTest
    static void exportsProductAndRevenuePerLineAndPages() {
        Date month = Date.newInstance(2026, 9, 17);
        System.assertEquals(new List<String>{ 'Ebda', 'IbnSina' }, PharmacySalesExportController.listDataSources(month));

        PharmacySalesExportController.ExportPage first = PharmacySalesExportController.getExportPage(month, 'All', null, 2);
        System.assertEquals(2, first.rows.size());
        System.assertEquals(true, first.hasMore);
        System.assertEquals(3, first.total);
        PharmacySalesExportController.ExportPage second = PharmacySalesExportController.getExportPage(month, 'All', first.nextCursor, 2);
        System.assertEquals(1, second.rows.size());
        System.assertEquals(false, second.hasMore);

        List<PharmacySalesExportController.ExportRow> all = new List<PharmacySalesExportController.ExportRow>(first.rows);
        all.addAll(second.rows);
        Decimal revenue = 0;
        for (PharmacySalesExportController.ExportRow r : all) {
            System.assertEquals('2026-09', r.reportMonth);
            System.assert(String.isNotBlank(r.product), 'every line carries its product');
            System.assertEquals('Export Pharmacy', r.pharmacy);
            revenue += r.revenue;
        }
        // 10*5 + 20*(no price: standard price or 0) + 30*5 -> at least the two priced lines.
        System.assert(revenue >= 200, 'revenue = quantity * unit price, got ' + revenue);

        PharmacySalesExportController.ExportPage epda = PharmacySalesExportController.getExportPage(month, 'Ebda', null, 100);
        System.assertEquals(1, epda.rows.size());
        System.assertEquals('File', epda.rows[0].priceSource);
    }

    @IsTest
    static void saysWhereEachSaleLandedOnTheProductsLine() {
        SfeApproverTestData data = SfeApproverTestData.build();
        if (data == null) {
            return;
        }
        UserTerritory2Association seatLink = [
            SELECT Id FROM UserTerritory2Association WHERE UserId = :data.rep.Id AND Territory2Id = :data.seat.Id
        ];
        seatLink.RoleInTerritory2 = 'Medical Rep';
        update seatLink;

        Brick__c brick148 = new Brick__c(Name = 'BRICK1 EXPORT', External_ID__c = 'BRICK148_EXPORT_T', Brick_Level__c = '148', Is_Active__c = true);
        insert brick148;
        Brick__c brick702 = new Brick__c(
            Name = 'Export Neighborhood', External_ID__c = 'BRICK_EXPORT_T_702', Brick_Level__c = '702',
            Is_Active__c = true, Parent_Brick__c = brick148.Id
        );
        insert brick702;
        // The brick is aligned to the line's position (half of it) and to a position outside any line.
        insert new List<Brick_Territory_Alignment__c>{
            new Brick_Territory_Alignment__c(
                Brick__c = brick702.Id, External_ID__c = 'EXPORT_T|SEAT', Territory2_Id__c = String.valueOf(data.seat.Id),
                Territory_External_ID__c = data.seat.External_ID__c, Share__c = 0.5, Is_Active__c = true
            ),
            new Brick_Territory_Alignment__c(
                Brick__c = brick702.Id, External_ID__c = 'EXPORT_T|OTHER', Territory2_Id__c = String.valueOf(data.otherSeat.Id),
                Territory_External_ID__c = data.otherSeat.External_ID__c, Share__c = 1, Is_Active__c = true
            )
        };
        Product2 onLine = new Product2(Name = 'Line Product', ProductCode = 'EXP-L', IsActive = true, Sales_Line__c = data.line.Name);
        Product2 offLine = new Product2(Name = 'Other Product', ProductCode = 'EXP-O', IsActive = true, Sales_Line__c = 'No Such Line');
        insert new List<Product2>{ onLine, offLine };
        Date month = Date.newInstance(2026, 10, 1);
        List<Pharmacy_Sales_Withdrawal__c> rows = new List<Pharmacy_Sales_Withdrawal__c>();
        for (Product2 p : new List<Product2>{ onLine, offLine }) {
            rows.add(new Pharmacy_Sales_Withdrawal__c(
                Data_Source__c = 'IbnSina', Report_Month__c = month, Product__c = p.Id, Product2_Id__c = String.valueOf(p.Id), Quantity_Withdrawn__c = 1,
                Unit_Price__c = 1, Brick__c = brick702.Id, Brick_702__c = brick702.Id, Brick_148__c = brick148.Id,
                Brick_Source__c = 'Sales location', Unique_Key__c = 'EXP_LAND_' + p.ProductCode
            ));
        }
        Database.insert(rows, AccessLevel.SYSTEM_MODE);

        Test.startTest();
        PharmacySalesExportController.ExportPage page = PharmacySalesExportController.getExportPage(month, 'IbnSina', null, 100);
        Test.stopTest();

        Map<String, PharmacySalesExportController.ExportRow> byProduct = new Map<String, PharmacySalesExportController.ExportRow>();
        for (PharmacySalesExportController.ExportRow r : page.rows) {
            byProduct.put(r.product, r);
        }
        PharmacySalesExportController.ExportRow landed = byProduct.get('Line Product');
        System.assertEquals('Export Neighborhood', landed.brick);
        System.assertEquals('BRICK1 EXPORT', landed.brick148);
        System.assertEquals('Sales location', landed.brickSource);
        System.assertEquals(false, landed.linkedPharmacy);
        System.assertEquals(data.line.Name, landed.line);
        System.assertEquals(data.seat.Name + ' (50%)', landed.territory, 'only the position on the product\'s line');
        System.assertEquals('Rami Rep Test', landed.rep);
        PharmacySalesExportController.ExportRow unmatched = byProduct.get('Other Product');
        System.assertEquals('No Such Line', unmatched.line, 'a product on no aligned line keeps its own line label');
        System.assertEquals(null, unmatched.territory);
        System.assertEquals('Export Neighborhood', unmatched.brick);
    }

    @IsTest
    static void addsUnplacedSalesAfterThePlacedLinesWithSubTypeAndChain() {
        Product2 p = new Product2(Name = 'Unplaced Product', ProductCode = 'EXP-U', IsActive = true, Sales_Line__c = 'GIT-I');
        insert p;
        Distributor_Sellout_Alias__c chainClient = new Distributor_Sellout_Alias__c(
            Distributor_Code__c = 'POS', Distributor_Client_Code__c = 'C1', Distributor_Client_Name__c = 'Chain Branch',
            Chain__c = 'Abdeen Ph', Status__c = 'Unmatched', Unique_Key__c = 'POS|C1', Governorate__c = 'Cairo'
        );
        Distributor_Sellout_Alias__c store = new Distributor_Sellout_Alias__c(
            Distributor_Code__c = 'POS', Distributor_Client_Code__c = 'C2', Distributor_Client_Name__c = 'Big Store',
            Sub_Type__c = 'Stores', Status__c = 'Unmatched', Unique_Key__c = 'POS|C2'
        );
        // System mode: the new Chain__c / Sub_Type__c fields may not be granted to the running user yet.
        Database.insert(new List<Distributor_Sellout_Alias__c>{ chainClient, store }, AccessLevel.SYSTEM_MODE);
        Date month = Date.newInstance(2026, 11, 1);
        Database.insert(
            new Pharmacy_Sales_Withdrawal__c(
                Data_Source__c = 'POS', Report_Month__c = month, Product__c = p.Id, Product2_Id__c = String.valueOf(p.Id),
                Distributor_Client__c = store.Id, Quantity_Withdrawn__c = 2, Unit_Price__c = 10, Unique_Key__c = 'EXP_U_PLACED'
            ),
            AccessLevel.SYSTEM_MODE
        );
        Database.insert(
            new Distributor_Unplaced_Sale__c(
                Data_Source__c = 'POS', Report_Month__c = month, Distributor_Client__c = chainClient.Id, Product__c = p.Id,
                Quantity__c = 3, Unit_Price__c = 7, Unique_Key__c = 'EXP_U_UNPLACED'
            ),
            AccessLevel.SYSTEM_MODE
        );

        PharmacySalesExportController.ExportPage first = PharmacySalesExportController.getExportPage(month, 'POS', null, 10);
        System.assertEquals(2, first.total, 'placed and unplaced sales both count');
        System.assertEquals(1, first.rows.size());
        System.assertEquals(true, first.hasMore, 'the unplaced sales follow the placed lines');
        System.assertEquals(PharmacySalesExportController.UNPLACED_CURSOR, first.nextCursor);
        PharmacySalesExportController.ExportRow placed = first.rows[0];
        System.assertEquals('Stores', placed.subType);
        System.assertEquals('Private', placed.mainType);
        System.assertEquals('C2', placed.clientCode);
        System.assertEquals('Big Store', placed.pharmacy);
        System.assertEquals(PharmacySalesExportController.PLACED, placed.placement);
        System.assertEquals('GIT-I', placed.line, 'no aligned brick: the product line label');

        PharmacySalesExportController.ExportPage second = PharmacySalesExportController.getExportPage(month, 'POS', first.nextCursor, 10);
        System.assertEquals(false, second.hasMore);
        System.assertEquals(1, second.rows.size());
        PharmacySalesExportController.ExportRow unplaced = second.rows[0];
        System.assertEquals(PharmacySalesExportController.UNKNOWN_BRICK, unplaced.brick);
        System.assertEquals(PharmacySalesExportController.UNFIND, unplaced.placement);
        System.assertEquals('Abdeen Ph', unplaced.chain);
        System.assertEquals('Abdeen Ph', unplaced.subType, 'a chain client takes the chain as sub type');
        System.assertEquals('Governorate only: Cairo', unplaced.brickSource);
        System.assertEquals(false, unplaced.linkedPharmacy);
        System.assertEquals(21, unplaced.revenue, 'no list price: quantity * file price');
        System.assertEquals('File', unplaced.priceSource);
    }

    @IsTest
    static void valuesAtTheListPriceExceptTender() {
        PharmacySalesExportController.ExportRow row = new PharmacySalesExportController.ExportRow();
        PharmacySalesExportController.price(row, 4, 9, 10);
        System.assertEquals(40, row.revenue);
        System.assertEquals('Price list', row.priceSource);

        PharmacySalesExportController.ExportRow tender = new PharmacySalesExportController.ExportRow();
        tender.tender = true;
        PharmacySalesExportController.price(tender, 4, 3, 10);
        System.assertEquals(12, tender.revenue, 'tender SKUs keep the file price');

        PharmacySalesExportController.ExportRow none = new PharmacySalesExportController.ExportRow();
        PharmacySalesExportController.price(none, null, null, null);
        System.assertEquals(0, none.revenue);
        System.assertEquals('No price', none.priceSource);

        PharmacySalesExportController.ExportRow t = new PharmacySalesExportController.ExportRow();
        t.tender = true;
        PharmacySalesExportController.classify(t, null, null);
        System.assertEquals('Tender', t.subType);
        System.assertEquals('Hospital', t.mainType);
        PharmacySalesExportController.ExportRow h = new PharmacySalesExportController.ExportRow();
        PharmacySalesExportController.classify(h, null, 'Hospital');
        System.assertEquals('Private Hospital', h.subType);
    }

    @IsTest
    static void requiresAMonth() {
        try {
            PharmacySalesExportController.getExportPage(null, 'All', null, 10);
            System.assert(false, 'month required');
        } catch (AuraHandledException e) {
            System.assert(true);
        }
    }

    @IsTest
    static void backfillSetsTheProductLookup() {
        Test.startTest();
        Database.executeBatch(new PharmacySalesProductBackfillBatch(), 50);
        Test.stopTest();
        System.assertEquals(
            0,
            [SELECT COUNT() FROM Pharmacy_Sales_Withdrawal__c WHERE Product__c = NULL WITH SYSTEM_MODE],
            'every row has Product__c after the backfill'
        );
    }
}
