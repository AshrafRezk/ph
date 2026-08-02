@IsTest
private class ChemipharmProductCatalogServiceTest {

    @IsTest
    static void resetAndSeedCatalog_createsProductsAndPricing() {
        createTestTerritory('TERR_GIT_DM_1_MR_1');
        createTestTerritory('TERR_CNS_DM_1_MR_1');
        createTestTerritory('TERR_RHEUM_DM_1_MR_1');
        createTestTerritory('TERR_CARDIO_DM_1_MR_1');
        createTestTerritory('TERR_CHC_DM_1_MR_1');

        Product2 legacyProduct = new Product2(
            Name = 'Legacy SDO Product',
            IsActive = true,
            ProductCode = 'LEGACY-001'
        );
        insert legacyProduct;

        Id standardPricebookId = Test.getStandardPricebookId();
        insert new PricebookEntry(
            Pricebook2Id = standardPricebookId,
            Product2Id = legacyProduct.Id,
            UnitPrice = 99,
            IsActive = true
        );

        Pricebook2 customPricebook = new Pricebook2(
            Name = 'Test Custom Pricebook',
            IsActive = true
        );
        insert customPricebook;

        Test.startTest();
        ChemipharmProductCatalogService.CatalogResult result =
            ChemipharmProductCatalogService.resetAndSeedCatalog();
        Test.stopTest();

        System.assertNotEquals(null, result.message);
        System.assertEquals(29, [
            SELECT COUNT()
            FROM Product2
            WHERE External_ID__c LIKE 'CPI_%' AND IsActive = TRUE
        ]);
        System.assertEquals(5, [
            SELECT COUNT()
            FROM Product2
            WHERE External_ID__c LIKE 'CPI_%' AND Product_Type__c = 'Brand'
        ]);
        System.assertEquals(13, [
            SELECT COUNT()
            FROM Product2
            WHERE External_ID__c LIKE 'CPI_%' AND Product_Type__c = 'Detail'
        ]);
        System.assertEquals(8, [
            SELECT COUNT()
            FROM Product2
            WHERE External_ID__c LIKE 'CPI_%' AND Therapy_Area__c = 'Gastroenterology'
        ]);
        System.assertEquals(18, [
            SELECT COUNT()
            FROM Product2
            WHERE External_ID__c LIKE 'CPI_%'
                AND Product_Type__c IN ('Detail', 'Sample')
                AND Strength__c != NULL
                AND Form__c != NULL
                AND Unit_of_Measure__c != NULL
                AND Quantity_Per_Unit__c != NULL
                AND Box_Quantity__c != NULL
        ]);
        System.assertEquals(8, [
            SELECT COUNT()
            FROM Product2
            WHERE External_ID__c LIKE 'SOUL_%'
                AND Therapy_Area__c = 'Consumer Health'
                AND IsActive = TRUE
        ]);
        Product2 detailChild = [
            SELECT Parent_Product__r.External_ID__c, Product_Type__c, Box_Quantity__c
            FROM Product2
            WHERE External_ID__c = 'CPI_COLOVERIN_135'
            LIMIT 1
        ];
        System.assertEquals('Detail', detailChild.Product_Type__c);
        System.assertEquals('CPI_COLOVERIN', detailChild.Parent_Product__r.External_ID__c);
        System.assertEquals(30, detailChild.Box_Quantity__c);
        Product2 reminder = [
            SELECT Brand_Reminder_Kind__c, Parent_Product__r.External_ID__c
            FROM Product2
            WHERE External_ID__c = 'CPI_COLOVERIN_BUG'
            LIMIT 1
        ];
        System.assertEquals('Bug', reminder.Brand_Reminder_Kind__c);
        System.assertEquals('CPI_COLOVERIN', reminder.Parent_Product__r.External_ID__c);
        System.assertEquals(0, [SELECT COUNT() FROM Product2 WHERE ProductCode = 'LEGACY-001']);
        System.assertEquals(0, [SELECT COUNT() FROM Pricebook2 WHERE Id = :customPricebook.Id]);
    }

    @IsTest
    static void purgeNonPharmaProducts_preservesChemipharmCatalog() {
        Product2 legacyProduct = new Product2(
            Name = 'Legacy SDO Product',
            IsActive = true,
            ProductCode = 'LEGACY-PURGE-001'
        );
        insert legacyProduct;

        Product2 cpiProduct = new Product2(
            Name = 'Coloverin Test',
            IsActive = true,
            ProductCode = 'CPI-TEST',
            External_ID__c = 'CPI_COLOVERIN_135',
            Product_Type__c = 'Detail',
            Strength__c = '135mg',
            Form__c = 'Sugar Coated Tablet'
        );
        insert cpiProduct;

        Test.startTest();
        ChemipharmProductCatalogService.PurgeResult result =
            ChemipharmProductCatalogService.purgeNonPharmaProducts();
        Test.stopTest();

        System.assertNotEquals(null, result.message);
        System.assertEquals(0, [SELECT COUNT() FROM Product2 WHERE ProductCode = 'LEGACY-PURGE-001']);
        System.assertEquals(1, [
            SELECT COUNT()
            FROM Product2
            WHERE External_ID__c = 'CPI_COLOVERIN_135'
        ]);
    }

    @IsTest
    static void getProductSpecs_returnsCoreSkus() {
        List<ChemipharmProductCatalogService.ProductSpec> specs =
            ChemipharmProductCatalogService.getProductSpecs();
        System.assertEquals(37, specs.size());
        System.assertEquals('CPI_COLOVERIN', specs[0].externalId);
        System.assertEquals('Brand', specs[0].productType);
        System.assertEquals('CPI_COLOVERIN_135', specs[1].externalId);
        System.assertEquals('Detail', specs[1].productType);
        System.assertEquals('CPI_COLOVERIN', specs[1].parentExternalId);
        System.assertEquals('135mg', specs[1].strength);
        System.assertEquals('Sugar Coated Tablet', specs[1].form);
        System.assertEquals('mg', specs[1].unitOfMeasure);
        System.assertEquals(135, specs[1].quantityPerUnit);
        System.assertEquals(30, specs[1].boxQuantity);
    }

    private static Territory2 createTestTerritory(String externalId) {
        List<Territory2> existing = [
            SELECT Id FROM Territory2 WHERE External_ID__c = :externalId LIMIT 1
        ];
        if (!existing.isEmpty()) {
            return existing[0];
        }
        List<Territory2Model> models = [
            SELECT Id FROM Territory2Model WHERE State = 'Active' LIMIT 1
        ];
        if (models.isEmpty()) {
            return null;
        }
        List<Territory2Type> types = [SELECT Id FROM Territory2Type LIMIT 1];
        if (types.isEmpty()) {
            return null;
        }
        Territory2 territory = new Territory2(
            Name = externalId,
            DeveloperName = externalId.replace('-', '_'),
            Territory2ModelId = models[0].Id,
            Territory2TypeId = types[0].Id
        );
        // External ID may be custom; set via put if field exists
        Map<String, Schema.SObjectField> fields = Schema.SObjectType.Territory2.fields.getMap();
        if (fields.containsKey('External_ID__c')) {
            territory.put('External_ID__c', externalId);
        }
        try {
            insert territory;
        } catch (Exception e) {
            return null;
        }
        return territory;
    }
}
