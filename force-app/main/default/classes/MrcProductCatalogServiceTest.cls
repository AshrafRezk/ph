@IsTest
private class MrcProductCatalogServiceTest {

    @IsTest
    static void seedMrcCatalog_upsertsProductsAndPricebookEntries() {
        Test.startTest();
        MrcProductCatalogService.CatalogResult result = MrcProductCatalogService.seedMrcCatalog();
        Test.stopTest();

        System.assert(result.productsUpserted > 0, 'Expected MRC products to be upserted.');
        System.assertNotEquals(null, result.message);

        List<Product2> products = [
            SELECT Id, External_ID__c, Family, Therapy_Area__c
            FROM Product2
            WHERE External_ID__c LIKE 'MRC_%'
        ];
        System.assertEquals(6, products.size(), 'Expected six popular MRC service products.');
        for (Product2 product : products) {
            System.assertEquals('Misr Radiology', product.Family);
            System.assertEquals('Diagnostic Imaging', product.Therapy_Area__c);
        }

        Id standardPricebookId = Test.getStandardPricebookId();
        Integer entryCount = [
            SELECT COUNT()
            FROM PricebookEntry
            WHERE Pricebook2Id = :standardPricebookId
                AND Product2.External_ID__c LIKE 'MRC_%'
        ];
        System.assertEquals(6, entryCount, 'Expected pricebook entries for all MRC products.');
    }

    @IsTest
    static void getProductIdsByExternalId_returnsSeededProducts() {
        MrcProductCatalogService.seedMrcCatalog();

        Map<String, Id> productIds = MrcProductCatalogService.getProductIdsByExternalId();
        System.assertEquals(6, productIds.size());
        System.assert(productIds.containsKey('MRC_MRI'));
        System.assert(productIds.containsKey('MRC_CT_SCAN'));
    }

    @IsTest
    static void getProductSpecs_returnsPopularServices() {
        List<MrcProductCatalogService.ProductSpec> specs = MrcProductCatalogService.getProductSpecs();
        System.assertEquals(6, specs.size());

        Set<String> serviceKeys = new Set<String>();
        for (MrcProductCatalogService.ProductSpec spec : specs) {
            serviceKeys.add(spec.serviceKey);
        }
        System.assert(serviceKeys.contains('mri'));
        System.assert(serviceKeys.contains('dental_imaging'));
    }
}
