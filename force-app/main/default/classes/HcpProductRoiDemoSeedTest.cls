@IsTest
private class HcpProductRoiDemoSeedTest {
    @IsTest
    static void seedDemoData_enrichesAtpfAndSpend() {
        Account hcp = new Account(Name = 'Seed ROI HCP', Account_Status__c = 'Active');
        Database.insert(hcp, AccessLevel.SYSTEM_MODE);

        Product2 product = new Product2(
            Name = 'DIVIDO Seed',
            ProductCode = 'TBK-DIV-SEED',
            External_ID__c = 'TBK_DIVIDO_SEED',
            Family = 'DIVIDO',
            Therapy_Area__c = 'Gastroenterology',
            Product_Type__c = 'Detail',
            IsActive = true
        );
        Database.insert(product, AccessLevel.SYSTEM_MODE);

        Database.insert(
            new PricebookEntry(
                Pricebook2Id = Test.getStandardPricebookId(),
                Product2Id = product.Id,
                UnitPrice = 50,
                IsActive = true
            ),
            AccessLevel.SYSTEM_MODE
        );

        Database.insert(
            new Account_Territory_Product_Fields__c(
                Account__c = hcp.Id,
                Territory2_Id__c = 'TERR_SEED_ROI_0001',
                Product2_Id__c = String.valueOf(product.Id),
                Rx_Per_Week__c = 10,
                Is_Active__c = true
            ),
            AccessLevel.SYSTEM_MODE
        );

        Test.startTest();
        HcpProductRoiDemoSeed.SeedResult result = HcpProductRoiDemoSeed.seedDemoData();
        Test.stopTest();

        System.assert(result.atpfUpdated > 0 || result.atpfCreated > 0, result.message);
        System.assert(result.spendRows > 0, result.message);
        System.assert(result.snapshotRows > 0, result.message);

        Account_Territory_Product_Fields__c atpf = [
            SELECT Penetration__c, Potential__c
            FROM Account_Territory_Product_Fields__c
            WHERE Account__c = :hcp.Id
            LIMIT 1
        ];
        System.assert(atpf.Penetration__c > 0);
        System.assert(atpf.Potential__c > atpf.Penetration__c);
        System.assertEquals(
            3,
            [
                SELECT COUNT()
                FROM HCP_Engagement_Spend__c
                WHERE Account__c = :hcp.Id
            ]
        );
    }

    @IsTest
    static void seedTrainingTerritories_returnsMessage() {
        Test.startTest();
        HcpProductRoiDemoSeed.SeedResult result = HcpProductRoiDemoSeed.seedTrainingTerritories();
        Test.stopTest();
        System.assertNotEquals(null, result.message);
    }

    @IsTest
    static void seedTrainingTerritories_seedsOverriddenTerritory() {
        Account hcp = new Account(Name = 'Training ROI HCP', Account_Status__c = 'Active');
        Database.insert(hcp, AccessLevel.SYSTEM_MODE);

        Product2 product = new Product2(
            Name = 'DIVIDO Training',
            ProductCode = 'TBK-DIV-TRAIN',
            External_ID__c = 'TBK_DIVIDO_TRAIN',
            Family = 'DIVIDO',
            Therapy_Area__c = 'Gastroenterology',
            Product_Type__c = 'Detail',
            IsActive = true
        );
        Database.insert(product, AccessLevel.SYSTEM_MODE);
        Database.insert(
            new PricebookEntry(
                Pricebook2Id = Test.getStandardPricebookId(),
                Product2Id = product.Id,
                UnitPrice = 50,
                IsActive = true
            ),
            AccessLevel.SYSTEM_MODE
        );

        String territoryKey = 'TERRTRAINAPM00001';
        HcpProductRoiDemoSeed.overrideTrainingTerritoryIds = new Set<String>{ territoryKey };
        Database.insert(
            new Account_Territory_Fields__c(
                Account__c = hcp.Id,
                Territory2_Id__c = territoryKey,
                Potential__c = 'B',
                Penetration__c = '2',
                Is_Active__c = true
            ),
            AccessLevel.SYSTEM_MODE
        );

        Test.startTest();
        HcpProductRoiDemoSeed.SeedResult result = HcpProductRoiDemoSeed.seedTrainingTerritories();
        Test.stopTest();

        System.assert(result.atpfCreated > 0 || result.atpfUpdated > 0, result.message);
        System.assert(
            [
                SELECT COUNT()
                FROM Account_Territory_Product_Fields__c
                WHERE Account__c = :hcp.Id
                    AND Is_Active__c = TRUE
            ] > 0
        );
        HcpProductRoiDemoSeed.overrideTrainingTerritoryIds = null;
    }
}