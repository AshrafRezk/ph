@IsTest
private class PharmacySalesRoiServiceTest {
    @TestSetup
    static void setup() {
        Account pharmacy = new Account(
            Name = 'ROI Test Pharmacy',
            External_ID__c = 'PHARM_TEST_ROI',
            BillingLatitude = 30.0444,
            BillingLongitude = 31.2357
        );
        Database.insert(pharmacy, AccessLevel.SYSTEM_MODE);

        Account pharmacyTwo = new Account(
            Name = 'ROI Test Pharmacy 2',
            External_ID__c = 'PHARM_TEST_ROI_2',
            BillingLatitude = 30.0500,
            BillingLongitude = 31.2400
        );
        Database.insert(pharmacyTwo, AccessLevel.SYSTEM_MODE);

        Brick__c brick = new Brick__c(
            Name = 'ROI Brick',
            External_ID__c = 'BRICK_TEST_ROI',
            Is_Active__c = true
        );
        Database.insert(brick, AccessLevel.SYSTEM_MODE);

        Database.insert(
            new List<Brick_Pharmacy__c>{
                new Brick_Pharmacy__c(
                    Brick__c = brick.Id,
                    Pharmacy_Account__c = pharmacy.Id,
                    Unique_Key__c = brick.Id + ':' + pharmacy.Id,
                    Is_Active__c = true
                ),
                new Brick_Pharmacy__c(
                    Brick__c = brick.Id,
                    Pharmacy_Account__c = pharmacyTwo.Id,
                    Unique_Key__c = brick.Id + ':' + pharmacyTwo.Id,
                    Is_Active__c = true
                )
            },
            AccessLevel.SYSTEM_MODE
        );

        Product2 product = new Product2(
            Name = 'ROI Test Product',
            ProductCode = 'ROI-TEST',
            External_ID__c = 'ZETA_TEST_ROI',
            Family = 'Empacoza',
            Therapy_Area__c = 'Diabetes',
            IsActive = true
        );
        Database.insert(product, AccessLevel.SYSTEM_MODE);

        Date month = Date.today().toStartOfMonth();
        Database.insert(
            new Pharmacy_Sales_Withdrawal__c(
                Data_Source__c = 'IbnSina',
                Report_Month__c = month,
                Pharmacy_Account__c = pharmacy.Id,
                Brick__c = brick.Id,
                Product2_Id__c = String.valueOf(product.Id),
                Quantity_Withdrawn__c = 50,
                Unit_Price__c = 200,
                Unique_Key__c = 'ROI_' + month.year() + '-' +
                    String.valueOf(month.month()).leftPad(2, '0') + '_' + pharmacy.Id + '_' + product.Id
            ),
            AccessLevel.SYSTEM_MODE
        );

        Id repId = UserInfo.getUserId();
        Date monthStart = month;
        Database.insert(
            new Employee_Time_Card__c(
                Employee__c = repId,
                Time_Card_Month_Start_Date__c = monthStart,
                Active_Time_Card__c = true,
                Base_Salary__c = 18000
            ),
            AccessLevel.SYSTEM_MODE
        );

        Datetime visitStart = Datetime.newInstance(month.year(), month.month(), 10, 9, 0, 0);
        Database.insert(
            new List<Visit__c>{
                new Visit__c(
                    Account__c = pharmacy.Id,
                    Assigned_To__c = repId,
                    Start_Date__c = visitStart,
                    Status__c = 'Completed',
                    Products_Discussed__c = product.Name
                ),
                new Visit__c(
                    Account__c = pharmacyTwo.Id,
                    Assigned_To__c = repId,
                    Start_Date__c = visitStart.addHours(2),
                    Status__c = 'Completed',
                    Products_Discussed__c = product.Name
                )
            },
            AccessLevel.SYSTEM_MODE
        );
    }

    @IsTest
    static void computeRoi_allocatesSalaryAndCommute() {
        PharmacySalesAnalyticsController.DashboardFilterInput filters =
            new PharmacySalesAnalyticsController.DashboardFilterInput();
        filters.startMonth = Date.today().toStartOfMonth();
        filters.endMonth = Date.today().toStartOfMonth();
        filters.dataSource = 'All';

        Map<String, Decimal> revenueByFamily = new Map<String, Decimal>{ 'Empacoza' => 10000 };
        PharmacySalesFieldSupport.BrickContext brickContext =
            PharmacySalesFieldSupport.loadBrickContext();

        Test.startTest();
        PharmacySalesRoiService.RoiSnapshot snapshot = PharmacySalesRoiService.computeRoi(
            filters,
            brickContext,
            revenueByFamily,
            new Map<Id, Decimal>()
        );
        Test.stopTest();

        System.assert(snapshot.byFamily.containsKey('Empacoza'), 'Expected Empacoza ROI row');
        PharmacySalesRoiService.RoiMetrics metrics = snapshot.byFamily.get('Empacoza');
        System.assertEquals(2, metrics.visitCountWithDetailing);
        System.assert(metrics.commuteCostEstimate > 0, 'Expected commute cost from route distance');
        System.assertNotEquals(null, metrics.roiPercent);
    }

    @IsTest
    static void getProductFamilyRoi_returnsFamilyMetrics() {
        PharmacySalesAnalyticsController.DashboardFilterInput filters =
            new PharmacySalesAnalyticsController.DashboardFilterInput();
        filters.startMonth = Date.today().toStartOfMonth();
        filters.endMonth = Date.today().toStartOfMonth();
        filters.dataSource = 'All';
        filters.productFamily = 'Empacoza';

        Test.startTest();
        PharmacySalesRoiService.RoiMetrics metrics =
            PharmacySalesRoiService.getProductFamilyRoi(filters, 'Empacoza');
        PharmacySalesAnalyticsController.DashboardData dashboard =
            PharmacySalesAnalyticsController.getDashboardData(filters);
        Test.stopTest();

        System.assertEquals(2, metrics.visitCountWithDetailing);
        System.assert(metrics.commuteCostEstimate > 0, 'Expected commute allocation');
        System.assertNotEquals(null, metrics.roiPercent);
        System.assert(!dashboard.familyBreakdown.isEmpty());
        System.assertEquals(2, dashboard.familyBreakdown[0].visitCountWithDetailing);
        System.assertNotEquals(null, dashboard.familyBreakdown[0].roiPercent);
    }
}
