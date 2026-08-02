@IsTest
private class PharmacySalesAnalyticsControllerTest {
    @TestSetup
    static void setup() {
        insertTestData();
    }

    @IsTest
    static void getFilterOptions_returnsPicklists() {
        Test.startTest();
        PharmacySalesAnalyticsController.FilterOptions options =
            PharmacySalesAnalyticsController.getFilterOptions();
        Test.stopTest();

        System.assertNotEquals(null, options);
        System.assert(options.dataSources.size() >= 3);
        System.assert(options.bricks.size() >= 2);
    }

    @IsTest
    static void getDashboardData_aggregatesRows() {
        PharmacySalesAnalyticsController.DashboardFilterInput filters =
            new PharmacySalesAnalyticsController.DashboardFilterInput();
        filters.startMonth = Date.today().toStartOfMonth().addMonths(-2);
        filters.endMonth = Date.today().toStartOfMonth();
        filters.dataSource = 'All';

        Test.startTest();
        PharmacySalesAnalyticsController.DashboardData data =
            PharmacySalesAnalyticsController.getDashboardData(filters);
        Test.stopTest();

        System.assertNotEquals(null, data.kpis);
        System.assert(data.kpis.totalQuantity > 0);
        System.assert(!data.familyBreakdown.isEmpty());
        System.assert(!data.detailRows.isEmpty());
    }

    @IsTest
    static void getDashboardData_filtersBySource() {
        PharmacySalesAnalyticsController.DashboardFilterInput filters =
            new PharmacySalesAnalyticsController.DashboardFilterInput();
        filters.startMonth = Date.today().toStartOfMonth();
        filters.endMonth = Date.today().toStartOfMonth();
        filters.dataSource = 'IbnSina';

        Test.startTest();
        PharmacySalesAnalyticsController.DashboardData data =
            PharmacySalesAnalyticsController.getDashboardData(filters);
        Test.stopTest();

        for (PharmacySalesAnalyticsController.DetailRow row : data.detailRows) {
            System.assertEquals('IbnSina', row.dataSource);
        }
    }

    private static void insertTestData() {
        Account pharmacy = new Account(
            Name = 'Test Pharmacy',
            External_ID__c = 'PHARM_TEST_ANALYTICS'
        );
        Database.insert(pharmacy, AccessLevel.SYSTEM_MODE);

        Brick__c brick = new Brick__c(
            Name = 'Test Brick',
            External_ID__c = 'BRICK_TEST_ANALYTICS',
            Is_Active__c = true
        );
        Database.insert(brick, AccessLevel.SYSTEM_MODE);

        Brick_Pharmacy__c membership = new Brick_Pharmacy__c(
            Brick__c = brick.Id,
            Pharmacy_Account__c = pharmacy.Id,
            Unique_Key__c = brick.Id + ':' + pharmacy.Id,
            Is_Active__c = true
        );
        Database.insert(membership, AccessLevel.SYSTEM_MODE);

        Product2 product = new Product2(
            Name = 'Test Product Analytics',
            ProductCode = 'TEST-ANALYTICS',
            External_ID__c = 'ZETA_TEST_ANALYTICS',
            Family = 'Empacoza',
            Therapy_Area__c = 'Diabetes',
            Product_Image_URL__c = 'https://example.com/product.png',
            IsActive = true
        );
        Database.insert(product, AccessLevel.SYSTEM_MODE);

        Date month = Date.today().toStartOfMonth();
        Pharmacy_Sales_Withdrawal__c row = new Pharmacy_Sales_Withdrawal__c(
            Data_Source__c = 'IbnSina',
            Report_Month__c = month,
            Pharmacy_Account__c = pharmacy.Id,
            Brick__c = brick.Id,
            Product2_Id__c = String.valueOf(product.Id),
            Quantity_Withdrawn__c = 100,
            Unit_Price__c = 180,
            Unique_Key__c = 'IbnSina_' + month.year() + '-' +
                String.valueOf(month.month()).leftPad(2, '0') + '_' + pharmacy.Id + '_' + product.Id
        );
        Database.insert(row, AccessLevel.SYSTEM_MODE);
    }
}
