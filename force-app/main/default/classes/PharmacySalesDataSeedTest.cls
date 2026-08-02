@IsTest
private class PharmacySalesDataSeedTest {
    @IsTest
    static void seedDemoData_createsRecords() {
        Product2 product = new Product2(
            Name = 'Seed Product',
            ProductCode = 'SEED-1',
            External_ID__c = 'ZETA_SEED_1',
            Family = 'Empacoza',
            Therapy_Area__c = 'Diabetes',
            IsActive = true
        );
        Database.insert(product, AccessLevel.SYSTEM_MODE);

        Test.startTest();
        PharmacySalesDataSeed.SeedResult result = PharmacySalesDataSeed.seedDemoData();
        Test.stopTest();

        System.assertNotEquals(null, result.message);
        System.assert(result.pharmaciesCreated > 0);
        System.assert(result.bricksCreated > 0);
    }
}
