@IsTest
private class HcpProductRoiServiceTest {
    @TestSetup
    static void setup() {
        Account hcp = new Account(Name = 'ROI HCP Doctor', Account_Status__c = 'Active');
        Account peer = new Account(Name = 'ROI Peer Doctor', Account_Status__c = 'Active');
        Account pharmacy = new Account(
            Name = 'ROI Affiliated Pharmacy',
            External_ID__c = 'PHARM_ROI_HCP_TEST',
            Account_Status__c = 'Active'
        );
        Database.insert(new List<Account>{ hcp, peer, pharmacy }, AccessLevel.SYSTEM_MODE);

        Id pharmacyRtId = null;
        for (RecordType rt : [
            SELECT Id, DeveloperName
            FROM RecordType
            WHERE SObjectType = 'Account'
                AND DeveloperName = 'Pharmacy'
            LIMIT 1
        ]) {
            pharmacyRtId = rt.Id;
        }
        if (pharmacyRtId != null) {
            pharmacy.RecordTypeId = pharmacyRtId;
            Database.update(pharmacy, AccessLevel.SYSTEM_MODE);
        }

        Product2 brand = new Product2(
            Name = 'ROI Brand Parent',
            ProductCode = 'TBK-ROI-BRAND',
            External_ID__c = 'TBK_ROI_BRAND_TEST',
            Family = 'DIVIDO',
            Therapy_Area__c = 'Gastroenterology',
            Product_Type__c = 'Brand',
            IsActive = true
        );
        Database.insert(brand, AccessLevel.SYSTEM_MODE);

        Product2 divido = new Product2(
            Name = 'DIVIDO 75mg Cap',
            ProductCode = 'TBK-DIV-75',
            External_ID__c = 'TBK_DIVIDO_75_TEST',
            Family = 'DIVIDO',
            Therapy_Area__c = 'Gastroenterology',
            Product_Type__c = 'Detail',
            Parent_Product__c = brand.Id,
            IsActive = true
        );
        Product2 other = new Product2(
            Name = 'Other Tabuk SKU',
            ProductCode = 'TBK-OTHER',
            External_ID__c = 'TBK_OTHER_TEST',
            Family = 'Other',
            Therapy_Area__c = 'Gastroenterology',
            Product_Type__c = 'Detail',
            Parent_Product__c = brand.Id,
            IsActive = true
        );
        Database.insert(new List<Product2>{ divido, other }, AccessLevel.SYSTEM_MODE);

        Id stdPbId = Test.getStandardPricebookId();
        Database.insert(
            new List<PricebookEntry>{
                new PricebookEntry(
                    Pricebook2Id = stdPbId,
                    Product2Id = divido.Id,
                    UnitPrice = 50,
                    IsActive = true
                ),
                new PricebookEntry(
                    Pricebook2Id = stdPbId,
                    Product2Id = other.Id,
                    UnitPrice = 40,
                    IsActive = true
                )
            },
            AccessLevel.SYSTEM_MODE
        );

        String territoryKey = 'TERR_ROI_TEST_0001';
        Database.insert(
            new List<Account_Territory_Product_Fields__c>{
                new Account_Territory_Product_Fields__c(
                    Account__c = hcp.Id,
                    Territory2_Id__c = territoryKey,
                    Product2_Id__c = String.valueOf(divido.Id),
                    Penetration__c = 4000,
                    Potential__c = 5000,
                    Rx_Per_Week__c = 77,
                    Is_Active__c = true
                ),
                new Account_Territory_Product_Fields__c(
                    Account__c = hcp.Id,
                    Territory2_Id__c = territoryKey,
                    Product2_Id__c = String.valueOf(other.Id),
                    Penetration__c = 1000,
                    Potential__c = 1500,
                    Rx_Per_Week__c = 20,
                    Is_Active__c = true
                ),
                new Account_Territory_Product_Fields__c(
                    Account__c = peer.Id,
                    Territory2_Id__c = territoryKey,
                    Product2_Id__c = String.valueOf(divido.Id),
                    Penetration__c = 2000,
                    Potential__c = 3000,
                    Rx_Per_Week__c = 40,
                    Is_Active__c = true
                )
            },
            AccessLevel.SYSTEM_MODE
        );

        Database.insert(
            new Account_Affiliation__c(
                Primary_Account__c = hcp.Id,
                Related_Account__c = pharmacy.Id,
                Affiliation_Type__c = 'Partner',
                Role__c = 'Pharmacist',
                Strength__c = 'Medium',
                Influence__c = 'Medium',
                Is_Active__c = true,
                Outside_Territory__c = false,
                Description__c = 'ROI test affiliation'
            ),
            AccessLevel.SYSTEM_MODE
        );

        Date month = Date.today().toStartOfMonth();
        Pharmacy_Sales_Withdrawal__c withdrawal = new Pharmacy_Sales_Withdrawal__c(
            Data_Source__c = 'Sofico',
            Report_Month__c = month,
            Pharmacy_Account__c = pharmacy.Id,
            Product2_Id__c = String.valueOf(divido.Id),
            Quantity_Withdrawn__c = 100,
            Unit_Price__c = 50,
            Unique_Key__c = 'Sofico_' + month.year() + '-' +
                String.valueOf(month.month()).leftPad(2, '0') + '_' + pharmacy.Id + '_' + divido.Id
        );
        Database.insert(withdrawal, AccessLevel.SYSTEM_MODE);

        String year = String.valueOf(Date.today().year());
        Database.insert(
            new List<HCP_Engagement_Spend__c>{
                new HCP_Engagement_Spend__c(
                    Account__c = hcp.Id,
                    Product__c = divido.Id,
                    Spend_Type__c = 'Speaker Meeting',
                    Amount__c = 250,
                    Spend_Date__c = Date.today().toStartOfMonth(),
                    Fiscal_Year__c = year,
                    External_ID__c = 'HES_TEST_SPEAKER'
                ),
                new HCP_Engagement_Spend__c(
                    Account__c = hcp.Id,
                    Product__c = divido.Id,
                    Spend_Type__c = 'Samples',
                    Amount__c = 100,
                    Spend_Date__c = Date.today().toStartOfMonth(),
                    Fiscal_Year__c = year,
                    External_ID__c = 'HES_TEST_SAMPLES'
                ),
                new HCP_Engagement_Spend__c(
                    Account__c = hcp.Id,
                    Product__c = divido.Id,
                    Spend_Type__c = 'Brochures',
                    Amount__c = 50,
                    Spend_Date__c = Date.today().toStartOfMonth(),
                    Fiscal_Year__c = year,
                    External_ID__c = 'HES_TEST_BROCHURES'
                )
            },
            AccessLevel.SYSTEM_MODE
        );

        Database.insert(
            new HCP_Product_Rating_Snapshot__c(
                Account__c = hcp.Id,
                Product__c = divido.Id,
                Snapshot_Month__c = month.addMonths(-1),
                Classification__c = 'B2',
                Classification_Score__c = 5,
                Penetration__c = 3500,
                Potential__c = 5000,
                External_ID__c = 'HPRS_TEST_1'
            ),
            AccessLevel.SYSTEM_MODE
        );
        Database.insert(
            new HCP_Product_Rating_Snapshot__c(
                Account__c = hcp.Id,
                Product__c = divido.Id,
                Snapshot_Month__c = month,
                Classification__c = 'A3',
                Classification_Score__c = 7,
                Penetration__c = 4000,
                Potential__c = 5000,
                External_ID__c = 'HPRS_TEST_2'
            ),
            AccessLevel.SYSTEM_MODE
        );
    }

    @IsTest
    static void getAccountRoi_ranksProductsAndComputesGap() {
        Account hcp = [SELECT Id FROM Account WHERE Name = 'ROI HCP Doctor' LIMIT 1];
        Product2 divido = [SELECT Id FROM Product2 WHERE External_ID__c = 'TBK_DIVIDO_75_TEST' LIMIT 1];

        Test.startTest();
        HcpProductRoiService.RoiPayload payload;
        try {
            payload = HcpProductRoiController.getAccountRoi(hcp.Id, null);
        } catch (Exception e) {
            System.assert(false, e.getTypeName() + ': ' + e.getMessage() + '\n' + e.getStackTraceString());
        }
        Test.stopTest();

        System.assertEquals(divido.Id, payload.selectedProductId, 'Should prefer DIVIDO');
        System.assertEquals(1, payload.selectedProductIds.size());
        System.assertEquals(divido.Id, payload.selectedProductIds[0]);
        System.assertEquals(2, payload.productRanks.size());
        System.assertEquals(200000, payload.writtenValue);
        System.assertEquals(250000, payload.potentialValue);
        System.assertEquals(50000, payload.gapValue);
        System.assertEquals(400, payload.totalSpendYtd);
        System.assertEquals(250, payload.speakerSpendYtd);
        System.assertEquals(100, payload.samplesSpendYtd);
        System.assertEquals(50, payload.brochuresSpendYtd);
        System.assertEquals(1, payload.orgRank);
        System.assertEquals(2, payload.orgTotal);
        System.assert(payload.callToAction.contains('200,000'), payload.callToAction);
        System.assert(payload.callToAction.contains('250,000'), payload.callToAction);
        System.assertEquals(12, payload.salesTrend.size());
        System.assertEquals(12, payload.ratingTrend.size());
        System.assertEquals('EGP', payload.currencyIsoCode);
        System.assertEquals(3, payload.spendEvents.size(), 'Expected one timeline event per spend row');
        System.assertNotEquals(null, payload.timelineYear);
    }

    @IsTest
    static void getAccountRoi_supportsMultipleSelectedProducts() {
        Account hcp = [SELECT Id FROM Account WHERE Name = 'ROI HCP Doctor' LIMIT 1];
        List<Product2> products = [
            SELECT Id
            FROM Product2
            WHERE External_ID__c IN ('TBK_DIVIDO_75_TEST', 'TBK_OTHER_TEST')
            ORDER BY External_ID__c
        ];
        System.assertEquals(2, products.size(), 'Expected two ROI test products');

        List<Id> productIds = new List<Id>{ products[0].Id, products[1].Id };

        Test.startTest();
        HcpProductRoiService.RoiPayload payload = HcpProductRoiController.getAccountRoi(
            hcp.Id,
            productIds
        );
        Test.stopTest();

        System.assertEquals(productIds[0], payload.selectedProductId, 'First selected is primary');
        System.assertEquals(productIds.size(), payload.selectedProductIds.size());
        Integer selectedRankCount = 0;
        for (HcpProductRoiService.ProductRankRow row : payload.productRanks) {
            if (row.isSelected == true) {
                selectedRankCount++;
            }
        }
        System.assert(selectedRankCount >= 1, 'Selected products should be marked in ranking');
    }

    @IsTest
    static void getAccountRoi_pharmacyUsesWithdrawals() {
        Account pharmacy = [SELECT Id FROM Account WHERE External_ID__c = 'PHARM_ROI_HCP_TEST' LIMIT 1];
        Product2 divido = [SELECT Id FROM Product2 WHERE External_ID__c = 'TBK_DIVIDO_75_TEST' LIMIT 1];

        Test.startTest();
        HcpProductRoiService.RoiPayload payload = HcpProductRoiController.getAccountRoi(pharmacy.Id, null);
        Test.stopTest();

        System.assert(!payload.productRanks.isEmpty(), 'Pharmacy sell-out should populate product ranks');
        System.assertEquals(divido.Id, payload.selectedProductId);
        System.assertEquals(12, payload.salesTrend.size());
        Decimal salesTotal = 0;
        for (HcpProductRoiService.MonthPoint point : payload.salesTrend) {
            salesTotal += point.value == null ? 0 : point.value;
        }
        System.assert(salesTotal > 0, 'Pharmacy should show its own withdrawal trend');
    }

    @IsTest
    static void getAccountRoi_doctorSharesSalesOfTheirBrick() {
        BrickMapTestData d = BrickMapTestData.create();
        Account peer = [SELECT Id FROM Account WHERE Name = 'ROI Peer Doctor' LIMIT 1];
        peer.Brick_702__c = d.a702.Id;
        for (RecordType rt : [
            SELECT Id
            FROM RecordType
            WHERE SObjectType = 'Account' AND DeveloperName = 'Institution_HCO'
            LIMIT 1
        ]) {
            peer.RecordTypeId = rt.Id; // the org's default Account record type may be Pharmacy
        }
        Database.update(peer, AccessLevel.SYSTEM_MODE);
        Product2 divido = [SELECT Id FROM Product2 WHERE External_ID__c = 'TBK_DIVIDO_75_TEST' LIMIT 1];
        // A distributor sale placed in the doctor's brick by location, with no CRM pharmacy behind it.
        Database.insert(
            new Pharmacy_Sales_Withdrawal__c(
                Data_Source__c = DistributorMatchingUtil.toDataSource('Egydrug'),
                Report_Month__c = Date.today().toStartOfMonth(),
                Product2_Id__c = String.valueOf(divido.Id),
                Product__c = divido.Id,
                Quantity_Withdrawn__c = 10,
                Unit_Price__c = 25,
                Brick_702__c = d.a702.Id,
                Unique_Key__c = 'ROI_BRICK_ONLY_SALE'
            ),
            AccessLevel.SYSTEM_MODE
        );

        Test.startTest();
        HcpProductRoiService.RoiPayload payload = HcpProductRoiController.getAccountRoi(peer.Id, new List<Id>{ divido.Id });
        Test.stopTest();

        Decimal salesTotal = 0;
        for (HcpProductRoiService.MonthPoint point : payload.salesTrend) {
            salesTotal += point.value == null ? 0 : point.value;
        }
        System.assertEquals(250, salesTotal, 'The doctor sees the sales placed in their brick');
    }

    @IsTest
    static void getAccountRoi_requiresAccountId() {
        Boolean threw = false;
        try {
            HcpProductRoiController.getAccountRoi(null, null);
        } catch (AuraHandledException e) {
            threw = true;
        }
        System.assert(threw, 'Expected AuraHandledException for null account');
    }

    @IsTest
    static void getAccountRoi_wrapsUnexpectedErrors() {
        HcpProductRoiController.throwUnexpected = true;
        Boolean threw = false;
        try {
            HcpProductRoiController.getAccountRoi(UserInfo.getUserId(), null);
        } catch (AuraHandledException e) {
            threw = true;
            System.assert(
                e.getMessage() != null && e.getMessage().contains('Unexpected ROI failure.'),
                e.getMessage()
            );
        } finally {
            HcpProductRoiController.throwUnexpected = false;
        }
        System.assert(threw, 'Expected wrapped AuraHandledException');
    }
}