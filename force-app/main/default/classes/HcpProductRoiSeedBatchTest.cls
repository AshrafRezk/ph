@IsTest
private class HcpProductRoiSeedBatchTest {
    @IsTest
    static void batch_seedsAtpfSpendAndSnapshots() {
        Account hcp = new Account(Name = 'Batch ROI HCP', Account_Status__c = 'Active');
        Database.insert(hcp, AccessLevel.SYSTEM_MODE);

        Product2 product = new Product2(
            Name = 'Batch DIVIDO',
            ProductCode = 'TBK-DIV-BATCH',
            External_ID__c = 'TBK_DIVIDO_BATCH',
            Family = 'DIVIDO',
            Product_Type__c = 'Detail',
            IsActive = true
        );
        Database.insert(product, AccessLevel.SYSTEM_MODE);
        Database.insert(
            new PricebookEntry(
                Pricebook2Id = Test.getStandardPricebookId(),
                Product2Id = product.Id,
                UnitPrice = 40,
                IsActive = true
            ),
            AccessLevel.SYSTEM_MODE
        );
        Database.insert(
            new Account_Territory_Fields__c(
                Account__c = hcp.Id,
                Territory2_Id__c = 'TERRROIBATCH000001',
                Potential__c = 'B',
                Penetration__c = '2',
                Is_Active__c = true
            ),
            AccessLevel.SYSTEM_MODE
        );

        Test.startTest();
        Id jobId = HcpProductRoiSeedBatch.run();
        Test.stopTest();

        System.assertNotEquals(null, jobId);
        System.assert(
            [
                SELECT COUNT()
                FROM Account_Territory_Product_Fields__c
                WHERE Account__c = :hcp.Id
                    AND Is_Active__c = TRUE
            ] > 0
        );
        System.assert(
            [
                SELECT COUNT()
                FROM HCP_Engagement_Spend__c
                WHERE Account__c = :hcp.Id
            ] > 0
        );
    }

    @IsTest
    static void batch_runForTerritories_filtersScope() {
        Account hcp = new Account(Name = 'Training Batch ROI HCP', Account_Status__c = 'Active');
        Database.insert(hcp, AccessLevel.SYSTEM_MODE);

        Product2 product = new Product2(
            Name = 'Batch Training DIVIDO',
            ProductCode = 'TBK-DIV-BTRAIN',
            External_ID__c = 'TBK_DIVIDO_BTRAIN',
            Family = 'DIVIDO',
            Product_Type__c = 'Detail',
            IsActive = true
        );
        Database.insert(product, AccessLevel.SYSTEM_MODE);
        Database.insert(
            new PricebookEntry(
                Pricebook2Id = Test.getStandardPricebookId(),
                Product2Id = product.Id,
                UnitPrice = 40,
                IsActive = true
            ),
            AccessLevel.SYSTEM_MODE
        );
        Database.insert(
            new Account_Territory_Fields__c(
                Account__c = hcp.Id,
                Territory2_Id__c = 'TERRTRAINBATCH0001',
                Potential__c = 'B',
                Penetration__c = '2',
                Is_Active__c = true
            ),
            AccessLevel.SYSTEM_MODE
        );

        Test.startTest();
        Id jobId = HcpProductRoiSeedBatch.runForTerritories(new Set<String>{ 'TERRTRAINBATCH0001' });
        Test.stopTest();

        System.assertNotEquals(null, jobId);
        System.assert(
            [
                SELECT COUNT()
                FROM Account_Territory_Product_Fields__c
                WHERE Account__c = :hcp.Id
                    AND Is_Active__c = TRUE
            ] > 0
        );
    }
}