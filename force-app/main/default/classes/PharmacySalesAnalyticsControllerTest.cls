@IsTest
private class PharmacySalesAnalyticsControllerTest {
    @IsTest
    static void filterOptionsAndDashboard_smoke() {
        Test.startTest();
        PharmacySalesAnalyticsController.FilterOptionsPayload options =
            PharmacySalesAnalyticsController.getFilterOptions();
        PharmacySalesAnalyticsController.DashboardPayload dashboard =
            (PharmacySalesAnalyticsController.DashboardPayload) PharmacySalesAnalyticsController.getDashboardData(
                new Map<String, Object>{
                    'startMonth' => Date.today().toStartOfMonth(),
                    'endMonth' => Date.today().toStartOfMonth(),
                    'dataSource' => 'All',
                    'therapyArea' => 'All',
                    'productFamily' => 'All'
                }
            );
        Test.stopTest();

        System.assertNotEquals(null, options);
        System.assertNotEquals(null, options.dataSources);
        System.assertNotEquals(null, dashboard);
        System.assertNotEquals(null, dashboard.kpis);
        System.assertNotEquals(null, dashboard.familyBreakdown);
    }

    @IsTest
    static void dashboard_aggregatesWithdrawalRow() {
        Account pharmacy = new Account(Name = 'Analytics Pharmacy');
        Database.insert(pharmacy, AccessLevel.SYSTEM_MODE);
        Product2 product = new Product2(Name = 'Analytics Product', ProductCode = 'AN-1', IsActive = true, Family = 'GIT');
        Database.insert(product, AccessLevel.SYSTEM_MODE);
        Date month = Date.today().toStartOfMonth();
        Pharmacy_Sales_Withdrawal__c withdrawal = new Pharmacy_Sales_Withdrawal__c(
            Data_Source__c = 'IbnSina',
            Report_Month__c = month,
            Pharmacy_Account__c = pharmacy.Id,
            Product2_Id__c = String.valueOf(product.Id),
            Quantity_Withdrawn__c = 5,
            Unit_Price__c = 20,
            Unique_Key__c = 'AN_' + pharmacy.Id
        );
        Database.insert(withdrawal, AccessLevel.SYSTEM_MODE);

        Test.startTest();
        PharmacySalesAnalyticsController.DashboardPayload dashboard =
            (PharmacySalesAnalyticsController.DashboardPayload) PharmacySalesAnalyticsController.getDashboardData(
                new Map<String, Object>{
                    'startMonth' => month,
                    'endMonth' => month,
                    'dataSource' => 'IbnSina',
                    'therapyArea' => 'All',
                    'productFamily' => 'All'
                }
            );
        Test.stopTest();

        System.assertEquals(5, dashboard.kpis.totalQuantity);
        System.assertEquals(1, dashboard.kpis.pharmacyCount);
        System.assertEquals(1, dashboard.familyBreakdown.size());
    }

    @IsTest
    static void dashboardPage_foldsTotalsAcrossPages() {
        Product2 product = new Product2(Name = 'Paged Product', ProductCode = 'AN-P', IsActive = true, Family = 'GIT');
        Database.insert(product, AccessLevel.SYSTEM_MODE);
        Brick__c brick = new Brick__c(Name = 'Paged Brick', Brick_Code__c = 'PAGED-702', Brick_Level__c = '702');
        Database.insert(brick, AccessLevel.SYSTEM_MODE);
        Date month = Date.today().toStartOfMonth();
        List<Pharmacy_Sales_Withdrawal__c> rows = new List<Pharmacy_Sales_Withdrawal__c>();
        for (Integer i = 0; i < 5; i++) {
            rows.add(new Pharmacy_Sales_Withdrawal__c(
                Data_Source__c = 'POS',
                Report_Month__c = month,
                Brick__c = brick.Id,
                Product2_Id__c = String.valueOf(product.Id),
                Quantity_Withdrawn__c = 2,
                Unit_Price__c = 10,
                Unique_Key__c = 'AN_PAGE_' + i
            ));
        }
        Database.insert(rows, AccessLevel.SYSTEM_MODE);
        Map<String, Object> filters = new Map<String, Object>{
            'startMonth' => month,
            'endMonth' => month,
            'dataSource' => 'All',
            'therapyArea' => 'All',
            'productFamily' => 'All',
            'matrixBrickId' => String.valueOf(brick.Id),
            'matrixMonthKey' => String.valueOf(month)
        };
        PharmacySalesAnalyticsController.pageSize = 2;

        Test.startTest();
        Integer calls = 0;
        String cursor;
        String state;
        PharmacySalesAnalyticsController.DashboardPage page;
        do {
            page = PharmacySalesAnalyticsController.getDashboardPage(filters, cursor, state);
            cursor = page.nextCursor;
            state = page.state;
            calls++;
        } while (page.done != true && calls < 10);
        Test.stopTest();

        System.assertEquals(3, calls, '5 lines at 2 per page');
        System.assertEquals(5, page.rowsTotal);
        System.assertEquals(5, page.rowsRead);
        System.assertEquals(10, page.payload.kpis.totalQuantity);
        System.assertEquals(1, page.payload.kpis.productCount);
        System.assertEquals(1, page.payload.brickMonthMatrix.size());
        System.assertEquals(brick.Id, page.payload.brickMonthMatrix[0].brickId);
        System.assertEquals(100, page.payload.brickMonthMatrix[0].rowTotal);
        System.assertEquals(5, page.payload.detailTotal);
        System.assertEquals(5, page.payload.detailRows.size());
    }

    @IsTest
    static void dashboard_tenderModeFiltersTenderLines() {
        Account pharmacy = new Account(Name = 'Tender Pharmacy');
        Database.insert(pharmacy, AccessLevel.SYSTEM_MODE);
        Product2 product = new Product2(Name = 'Tender Product', ProductCode = 'TN-1', IsActive = true, Family = 'GIT');
        Database.insert(product, AccessLevel.SYSTEM_MODE);
        Date month = Date.today().toStartOfMonth();
        Database.insert(
            new List<Pharmacy_Sales_Withdrawal__c>{
                new Pharmacy_Sales_Withdrawal__c(
                    Data_Source__c = 'IbnSina',
                    Report_Month__c = month,
                    Pharmacy_Account__c = pharmacy.Id,
                    Product2_Id__c = String.valueOf(product.Id),
                    Quantity_Withdrawn__c = 5,
                    Unit_Price__c = 10,
                    Unique_Key__c = 'TN_R_' + pharmacy.Id
                ),
                new Pharmacy_Sales_Withdrawal__c(
                    Data_Source__c = 'IbnSina',
                    Report_Month__c = month,
                    Pharmacy_Account__c = pharmacy.Id,
                    Product2_Id__c = String.valueOf(product.Id),
                    Quantity_Withdrawn__c = 7,
                    Unit_Price__c = 10,
                    Is_Tender__c = true,
                    Unique_Key__c = 'TN_T_' + pharmacy.Id
                )
            },
            AccessLevel.SYSTEM_MODE
        );

        Test.startTest();
        PharmacySalesAnalyticsController.FilterOptionsPayload options = PharmacySalesAnalyticsController.getFilterOptions();
        Decimal byDefault = tenderQty(month, null);
        Decimal onlyTender = tenderQty(month, 'Only');
        Decimal all = tenderQty(month, 'All');
        Test.stopTest();

        System.assertEquals(3, options.tenderModes.size());
        System.assertEquals('Exclude', options.defaultTenderMode, 'Policy default leaves tender out.');
        System.assertEquals(5, byDefault);
        System.assertEquals(7, onlyTender);
        System.assertEquals(12, all);
    }

    private static Decimal tenderQty(Date month, String tenderMode) {
        PharmacySalesAnalyticsController.DashboardPayload dashboard =
            (PharmacySalesAnalyticsController.DashboardPayload) PharmacySalesAnalyticsController.getDashboardData(
                new Map<String, Object>{ 'startMonth' => month, 'endMonth' => month, 'tenderMode' => tenderMode }
            );
        return dashboard.kpis.totalQuantity;
    }
}
