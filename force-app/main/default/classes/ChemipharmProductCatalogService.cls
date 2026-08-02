public without sharing class ChemipharmProductCatalogService {

    private static final Integer BATCH_SIZE = 200;

    public class CatalogResult {
        public Integer atpfDeleted = 0;
        public Integer ptaDeleted = 0;
        public Integer pricebookEntriesDeleted = 0;
        public Integer pricebooksDeleted = 0;
        public Integer productsDeleted = 0;
        public Integer productsUpserted = 0;
        public Integer pricebookEntriesInserted = 0;
        public Integer ptaInserted = 0;
        public Integer atpfInserted = 0;
        public String message;
    }

    public class PurgeResult {
        public Integer dependenciesDeleted = 0;
        public Integer pricebookEntriesDeleted = 0;
        public Integer productsDeleted = 0;
        public Integer productsDeactivated = 0;
        public Integer productsRemaining = 0;
        public String message;
    }

    public class ProductSpec {
        public String externalId;
        public String name;
        public String productCode;
        public String productType;
        public String parentExternalId;
        public String brandReminderKind;
        public String productFamily;
        public String therapyArea;
        public String activeIngredient;
        public String strength;
        public String form;
        public String unitOfMeasure;
        public Decimal quantityPerUnit;
        public Decimal boxQuantity;
        public Decimal unitPrice;
        public String displayUrl;
        public String imageUrl;
        public String description;
    }

    /**
     * Removes all catalog data and seeds Chemipharm core brand SKUs with
     * Standard Price Book entries and therapy-area territory PTA alignment.
     */
    public static CatalogResult resetAndSeedCatalog() {
        CatalogResult result = new CatalogResult();
        cleanupCatalog(result);
        seedCatalog(result);
        reseedAccountTerritoryProductFields(result);
        result.message = buildMessage(result);
        return result;
    }

    public static CatalogResult cleanupCatalog() {
        CatalogResult result = new CatalogResult();
        cleanupCatalog(result);
        result.message = 'Cleanup complete.';
        return result;
    }

    public static List<ProductSpec> getProductSpecs() {
        return buildProductSpecs();
    }

    /**
     * Updates Family and Therapy Area on existing Chemipharm catalog products without a full reset.
     */
    public static Integer refreshProductClassifications() {
        List<ProductSpec> specs = buildProductSpecs();
        Map<String, ProductSpec> specsByExtId = new Map<String, ProductSpec>();
        for (ProductSpec spec : specs) {
            specsByExtId.put(spec.externalId, spec);
        }
        Map<String, Id> productIdsByExtId = loadProductIdsByExternalId(specs);
        List<Product2> updates = new List<Product2>();
        for (Product2 product : [
            SELECT Id, External_ID__c
            FROM Product2
            WHERE External_ID__c IN :specsByExtId.keySet()
            WITH SYSTEM_MODE
        ]) {
            ProductSpec spec = specsByExtId.get(product.External_ID__c);
            Id parentId = String.isBlank(spec.parentExternalId)
                ? null
                : productIdsByExtId.get(spec.parentExternalId);
            updates.add(toProduct2(spec, product.Id, parentId));
        }
        if (updates.isEmpty()) {
            return 0;
        }
        Database.SaveResult[] results = Database.update(updates, false, AccessLevel.SYSTEM_MODE);
        Integer successCount = 0;
        for (Database.SaveResult result : results) {
            if (result.isSuccess()) {
                successCount++;
            } else {
                for (Database.Error err : result.getErrors()) {
                    System.debug('Update error: ' + err.getMessage());
                }
            }
        }
        return successCount;
    }

    /**
     * Upserts the full Chemipharm product catalog and Standard Price Book entries without a destructive reset.
     */
    public static CatalogResult seedExtendedCatalog() {
        CatalogResult result = new CatalogResult();
        upsertCatalogProductsAndPricing(result);
        result.message = 'Seeded ' + result.productsUpserted + ' Chemipharm products with ' +
            result.pricebookEntriesInserted + ' new standard pricebook entries.';
        return result;
    }

    /**
     * Removes SDO / non-pharma products while preserving the Chemipharm catalog SKUs.
     */
    public static PurgeResult purgeNonPharmaProducts() {
        PurgeResult result = new PurgeResult();
        List<Product2> nonPharmaProducts = getNonPharmaProducts();
        if (nonPharmaProducts.isEmpty()) {
            result.message = 'No non-pharma products found.';
            return result;
        }

        Set<Id> productIds = new Map<Id, Product2>(nonPharmaProducts).keySet();
        result.dependenciesDeleted += deleteDependenciesForProducts(productIds);
        result.pricebookEntriesDeleted += deletePricebookEntriesForProducts(productIds);

        deleteNonPharmaProductsInOrder(productIds, result);

        List<Product2> remaining = getNonPharmaProducts();
        if (!remaining.isEmpty()) {
            for (Product2 product : remaining) {
                product.IsActive = false;
                if (product.Name != null && !product.Name.startsWith('ARCHIVED - ')) {
                    product.Name = 'ARCHIVED - ' + product.Name;
                }
            }
            Database.SaveResult[] updateResults = Database.update(remaining, false, AccessLevel.SYSTEM_MODE);
            for (Database.SaveResult updateResult : updateResults) {
                if (updateResult.isSuccess()) {
                    result.productsDeactivated++;
                }
            }
        }

        result.productsRemaining = getNonPharmaProducts().size();
        result.message = 'Purged non-pharma catalog. Deleted ' + result.productsDeleted +
            ' products, ' + result.pricebookEntriesDeleted + ' pricebook entries, ' +
            result.dependenciesDeleted + ' dependent records. ' +
            result.productsRemaining + ' legacy SDO products archived (inactive, prefixed ARCHIVED -).';
        return result;
    }

    private static void cleanupCatalog(CatalogResult result) {
        result.atpfDeleted += deleteAllSObjects('Account_Territory_Product_Fields__c');
        result.ptaDeleted += deleteAllSObjects('Product_Territory_Alignment__c');

        deleteLineItemsReferencingProducts();
        result.pricebookEntriesDeleted += deleteAllSObjects('PricebookEntry');

        List<Pricebook2> customPricebooks = [
            SELECT Id
            FROM Pricebook2
            WHERE IsStandard = false
            WITH SYSTEM_MODE
        ];
        if (!customPricebooks.isEmpty()) {
            Database.DeleteResult[] deleteResults = Database.delete(customPricebooks, false, AccessLevel.SYSTEM_MODE);
            for (Database.DeleteResult dr : deleteResults) {
                if (dr.isSuccess()) {
                    result.pricebooksDeleted++;
                }
            }
        }

        List<Product2> products = [SELECT Id FROM Product2 WITH SYSTEM_MODE];
        if (!products.isEmpty()) {
            Set<Id> allProductIds = new Map<Id, Product2>(products).keySet();
            // Delete hierarchy children first (Detail/Sample/Brand Reminder), then Brand parents.
            Set<Id> childIds = new Set<Id>();
            for (Product2 child : [
                SELECT Id
                FROM Product2
                WHERE Parent_Product__c != NULL
                WITH SYSTEM_MODE
            ]) {
                childIds.add(child.Id);
            }
            if (!childIds.isEmpty()) {
                result.productsDeleted += deleteProductsById(childIds);
                allProductIds.removeAll(childIds);
            }
            if (!allProductIds.isEmpty()) {
                result.productsDeleted += deleteProductsById(allProductIds);
            }
        }

        PurgeResult purgeResult = purgeNonPharmaProducts();
        result.productsDeleted += purgeResult.productsDeleted;
        result.pricebookEntriesDeleted += purgeResult.pricebookEntriesDeleted;
    }

    private static List<Product2> getNonPharmaProducts() {
        Set<String> catalogExternalIds = getCatalogExternalIds();
        List<Product2> products = new List<Product2>();
        for (Product2 product : [
            SELECT Id, Name, External_ID__c, IsActive
            FROM Product2
            WITH SYSTEM_MODE
        ]) {
            if (product.External_ID__c != null && catalogExternalIds.contains(product.External_ID__c)) {
                continue;
            }
            products.add(product);
        }
        return products;
    }

    private static void deleteNonPharmaProductsInOrder(Set<Id> productIds, PurgeResult result) {
        if (productIds == null || productIds.isEmpty()) {
            return;
        }

        Set<Id> childProductIds = new Set<Id>();
        for (ProductAttribute attribute : [
            SELECT ProductId
            FROM ProductAttribute
            WHERE VariantParentId IN :productIds AND ProductId != NULL
            WITH SYSTEM_MODE
        ]) {
            childProductIds.add(attribute.ProductId);
        }
        for (Product2 child : [
            SELECT Id
            FROM Product2
            WHERE Parent_Product__c IN :productIds
            WITH SYSTEM_MODE
        ]) {
            childProductIds.add(child.Id);
        }
        childProductIds.retainAll(productIds);

        if (!childProductIds.isEmpty()) {
            result.dependenciesDeleted += deleteDependenciesForProducts(childProductIds);
            result.pricebookEntriesDeleted += deletePricebookEntriesForProducts(childProductIds);
            result.productsDeleted += deleteProductsById(childProductIds);
            productIds.removeAll(childProductIds);
        }

        if (!productIds.isEmpty()) {
            result.productsDeleted += deleteProductsById(productIds);
        }
    }

    private static Integer deleteProductsById(Set<Id> productIds) {
        if (productIds == null || productIds.isEmpty()) {
            return 0;
        }
        Integer deleted = 0;
        Database.DeleteResult[] deleteResults = Database.delete(
            [SELECT Id FROM Product2 WHERE Id IN :productIds WITH SYSTEM_MODE],
            false,
            AccessLevel.SYSTEM_MODE
        );
        for (Database.DeleteResult deleteResult : deleteResults) {
            if (deleteResult.isSuccess()) {
                deleted++;
            }
        }
        return deleted;
    }

    private static Integer deleteDependenciesForProducts(Set<Id> productIds) {
        if (productIds == null || productIds.isEmpty()) {
            return 0;
        }

        Integer deleted = 0;
        deleted += deleteQueryRecords([
            SELECT Id FROM OpportunityLineItem WHERE Product2Id IN :productIds WITH SYSTEM_MODE
        ]);
        deleted += deleteQueryRecords([
            SELECT Id FROM OrderItem WHERE Product2Id IN :productIds WITH SYSTEM_MODE
        ]);
        deleted += deleteQueryRecords([
            SELECT Id FROM QuoteLineItem WHERE Product2Id IN :productIds WITH SYSTEM_MODE
        ]);
        deleted += deleteQueryRecords([
            SELECT Id FROM ContractLineItem WHERE Product2Id IN :productIds WITH SYSTEM_MODE
        ]);
        deleted += deleteQueryRecords([
            SELECT Id FROM WorkOrderLineItem WHERE Product2Id IN :productIds WITH SYSTEM_MODE
        ]);
        deleted += deleteQueryRecords([
            SELECT Id FROM Asset WHERE Product2Id IN :productIds WITH SYSTEM_MODE
        ]);
        deleted += deleteQueryRecords([
            SELECT Id FROM ProductItem WHERE Product2Id IN :productIds WITH SYSTEM_MODE
        ]);
        deleted += deleteQueryRecords([
            SELECT Id FROM Sample_Inventory__c WHERE Product2__c IN :productIds WITH SYSTEM_MODE
        ]);
        deleted += deleteQueryRecords([
            SELECT Id
            FROM Account_Territory_Product_Fields__c
            WHERE Product2_Id__c IN :stringifyIds(productIds)
            WITH SYSTEM_MODE
        ]);
        deleted += deleteQueryRecords([
            SELECT Id
            FROM Product_Territory_Alignment__c
            WHERE Product2_Id__c IN :stringifyIds(productIds)
            WITH SYSTEM_MODE
        ]);
        deleted += deleteQueryRecords([
            SELECT Id
            FROM ProductAttribute
            WHERE ProductId IN :productIds OR VariantParentId IN :productIds
            WITH SYSTEM_MODE
        ]);
        deleted += deleteQueryRecords([
            SELECT Id
            FROM ProductAttributeSetProduct
            WHERE ProductId IN :productIds
            WITH SYSTEM_MODE
        ]);
        deleted += deleteQueryRecords([
            SELECT Id
            FROM ProductRelatedComponent
            WHERE ChildProductId IN :productIds OR ParentProductId IN :productIds
            WITH SYSTEM_MODE
        ]);
        deleted += clearClmPresentationProducts(productIds);
        deleted += deleteOptionalProductDependencies(productIds);
        return deleted;
    }

    private static Integer deleteOptionalProductDependencies(Set<Id> productIds) {
        Integer deleted = 0;
        List<String> optionalObjects = new List<String>{
            'ProductConsumed',
            'ConsumedProduct',
            'CartItem',
            'ShipmentItem',
            'ReturnOrderLineItem',
            'ProductTransfer',
            'ProductRequestLineItem'
        };
        for (String objectApiName : optionalObjects) {
            if (!Schema.getGlobalDescribe().containsKey(objectApiName)) {
                continue;
            }
            deleted += deleteQueryRecords(Database.query(
                'SELECT Id FROM ' + objectApiName + ' WHERE Product2Id IN :productIds',
                AccessLevel.SYSTEM_MODE
            ));
        }
        return deleted;
    }

    private static Integer clearClmPresentationProducts(Set<Id> productIds) {
        if (!Schema.getGlobalDescribe().containsKey('CLM_Presentation__c')) {
            return 0;
        }
        List<SObject> presentations = Database.query(
            'SELECT Id, Product__c FROM CLM_Presentation__c WHERE Product__c IN :productIds',
            AccessLevel.SYSTEM_MODE
        );
        for (SObject presentation : presentations) {
            presentation.put('Product__c', null);
        }
        if (presentations.isEmpty()) {
            return 0;
        }
        Database.update(presentations, false, AccessLevel.SYSTEM_MODE);
        return presentations.size();
    }

    private static Integer deletePricebookEntriesForProducts(Set<Id> productIds) {
        return deleteQueryRecords([
            SELECT Id FROM PricebookEntry WHERE Product2Id IN :productIds WITH SYSTEM_MODE
        ]);
    }

    private static Set<String> stringifyIds(Set<Id> recordIds) {
        Set<String> values = new Set<String>();
        for (Id recordId : recordIds) {
            values.add(String.valueOf(recordId));
        }
        return values;
    }

    private static Integer deleteQueryRecords(List<SObject> records) {
        if (records == null || records.isEmpty()) {
            return 0;
        }
        Integer deleted = 0;
        Database.DeleteResult[] results = Database.delete(records, false, AccessLevel.SYSTEM_MODE);
        for (Database.DeleteResult result : results) {
            if (result.isSuccess()) {
                deleted++;
            }
        }
        return deleted;
    }

    private static void deleteLineItemsReferencingProducts() {
        deleteIfPresent([
            SELECT Id
            FROM OpportunityLineItem
            WHERE Product2Id != NULL
            WITH SYSTEM_MODE
        ]);
        deleteIfPresent([
            SELECT Id
            FROM OrderItem
            WHERE Product2Id != NULL
            WITH SYSTEM_MODE
        ]);
        deleteIfPresent([
            SELECT Id
            FROM QuoteLineItem
            WHERE Product2Id != NULL
            WITH SYSTEM_MODE
        ]);
        deleteIfPresent([
            SELECT Id
            FROM ContractLineItem
            WHERE Product2Id != NULL
            WITH SYSTEM_MODE
        ]);
        deleteIfPresent([
            SELECT Id
            FROM WorkOrderLineItem
            WHERE Product2Id != NULL
            WITH SYSTEM_MODE
        ]);
        deleteIfPresent([
            SELECT Id
            FROM Asset
            WHERE Product2Id != NULL
            WITH SYSTEM_MODE
        ]);
        deleteIfPresent([
            SELECT Id
            FROM ProductItem
            WHERE Product2Id != NULL
            WITH SYSTEM_MODE
        ]);
    }

    private static void seedCatalog(CatalogResult result) {
        Map<String, Id> productIdsByExtId = upsertCatalogProductsAndPricing(result);
        seedProductTerritoryAlignments(productIdsByExtId, result);
    }

    private static Map<String, Id> upsertCatalogProductsAndPricing(CatalogResult result) {
        List<ProductSpec> specs = buildProductSpecs();
        List<ProductSpec> brandSpecs = new List<ProductSpec>();
        List<ProductSpec> childSpecs = new List<ProductSpec>();
        for (ProductSpec spec : specs) {
            if (spec.productType == 'Brand') {
                brandSpecs.add(spec);
            } else {
                childSpecs.add(spec);
            }
        }

        // Pass 1: Brand parents (no Parent_Product__c)
        result.productsUpserted += upsertProductBatch(brandSpecs, null);

        Map<String, Id> productIdsByExtId = loadProductIdsByExternalId(specs);

        // Pass 2: Detail / Sample / Brand Reminder children under Brand
        result.productsUpserted += upsertProductBatch(childSpecs, productIdsByExtId);
        productIdsByExtId = loadProductIdsByExternalId(specs);

        seedStandardPricebookEntries(specs, productIdsByExtId, result);
        return productIdsByExtId;
    }

    private static Integer upsertProductBatch(
        List<ProductSpec> specs,
        Map<String, Id> parentIdsByExtId
    ) {
        if (specs == null || specs.isEmpty()) {
            return 0;
        }
        List<Product2> products = new List<Product2>();
        for (ProductSpec spec : specs) {
            Id parentId = null;
            if (parentIdsByExtId != null && String.isNotBlank(spec.parentExternalId)) {
                parentId = parentIdsByExtId.get(spec.parentExternalId);
            }
            products.add(toProduct2(spec, null, parentId));
        }
        Integer upserted = 0;
        Database.UpsertResult[] upsertResults = Database.upsert(
            products,
            Product2.External_ID__c,
            false,
            AccessLevel.SYSTEM_MODE
        );
        for (Database.UpsertResult ur : upsertResults) {
            if (ur.isSuccess()) {
                upserted++;
            } else {
                for (Database.Error err : ur.getErrors()) {
                    System.debug('Product upsert error: ' + err.getMessage());
                }
            }
        }
        return upserted;
    }

    private static Product2 toProduct2(ProductSpec spec, Id existingId, Id parentId) {
        Product2 product = new Product2(
            Name = spec.name,
            ProductCode = spec.productCode,
            External_ID__c = spec.externalId,
            Family = spec.productFamily,
            Therapy_Area__c = spec.therapyArea,
            Product_Type__c = spec.productType,
            Parent_Product__c = parentId,
            Brand_Reminder_Kind__c = spec.brandReminderKind,
            Strength__c = spec.strength,
            Form__c = spec.form,
            Unit_of_Measure__c = spec.unitOfMeasure,
            Quantity_Per_Unit__c = spec.quantityPerUnit,
            Box_Quantity__c = spec.boxQuantity,
            Description = spec.description,
            DisplayUrl = spec.displayUrl,
            Product_Image_URL__c = spec.imageUrl,
            IsActive = true
        );
        if (existingId != null) {
            product.Id = existingId;
        }
        return product;
    }

    private static Map<String, Id> loadProductIdsByExternalId(List<ProductSpec> specs) {
        Map<String, Id> productIdsByExtId = new Map<String, Id>();
        for (Product2 product : [
            SELECT Id, External_ID__c
            FROM Product2
            WHERE External_ID__c IN :getExternalIds(specs)
            WITH SYSTEM_MODE
        ]) {
            productIdsByExtId.put(product.External_ID__c, product.Id);
        }
        return productIdsByExtId;
    }

    private static void seedStandardPricebookEntries(
        List<ProductSpec> specs,
        Map<String, Id> productIdsByExtId,
        CatalogResult result
    ) {
        Id standardPricebookId = resolveStandardPricebookId();
        Set<Id> productIds = new Set<Id>(productIdsByExtId.values());
        Set<Id> existingProductIds = new Set<Id>();
        for (PricebookEntry existing : [
            SELECT Product2Id
            FROM PricebookEntry
            WHERE Pricebook2Id = :standardPricebookId AND Product2Id IN :productIds
            WITH SYSTEM_MODE
        ]) {
            existingProductIds.add(existing.Product2Id);
        }

        List<PricebookEntry> entries = new List<PricebookEntry>();
        for (ProductSpec spec : specs) {
            Id productId = productIdsByExtId.get(spec.externalId);
            if (productId == null || existingProductIds.contains(productId)) {
                continue;
            }
            Decimal price = spec.unitPrice == null ? 0 : spec.unitPrice;
            entries.add(new PricebookEntry(
                Pricebook2Id = standardPricebookId,
                Product2Id = productId,
                UnitPrice = price,
                IsActive = true,
                UseStandardPrice = false
            ));
        }
        if (!entries.isEmpty()) {
            Database.SaveResult[] saveResults = Database.insert(entries, false, AccessLevel.SYSTEM_MODE);
            for (Database.SaveResult sr : saveResults) {
                if (sr.isSuccess()) {
                    result.pricebookEntriesInserted++;
                }
            }
        }
    }

    private static void seedProductTerritoryAlignments(
        Map<String, Id> productIdsByExtId,
        CatalogResult result
    ) {
        Map<String, String> therapyToTerritoryExt = new Map<String, String>{
            'Gastroenterology' => 'TERR_GIT_DM_1_MR_1',
            'Neurology' => 'TERR_CNS_DM_1_MR_1',
            'Rheumatology' => 'TERR_RHEUM_DM_1_MR_1',
            'Cardiovascular' => 'TERR_CARDIO_DM_1_MR_1',
            'Consumer Health' => 'TERR_CHC_DM_1_MR_1'
        };

        Set<String> existingKeys = new Set<String>();
        for (Product_Territory_Alignment__c existing : [
            SELECT Unique_Key__c
            FROM Product_Territory_Alignment__c
            WHERE Unique_Key__c != NULL
            WITH SYSTEM_MODE
        ]) {
            existingKeys.add(existing.Unique_Key__c);
        }

        List<Product_Territory_Alignment__c> alignments = new List<Product_Territory_Alignment__c>();
        Map<String, ProductSpec> specsByExtId = new Map<String, ProductSpec>();
        for (ProductSpec spec : buildProductSpecs()) {
            specsByExtId.put(spec.externalId, spec);
        }
        for (String externalId : productIdsByExtId.keySet()) {
            ProductSpec spec = specsByExtId.get(externalId);
            // Align operational children (Detail / Sample / Brand Reminder), not Brand parents.
            if (spec == null
                || spec.productType == 'Brand'
                || !therapyToTerritoryExt.containsKey(spec.therapyArea)
            ) {
                continue;
            }
            Id territoryId = TerritoryModuleSeed.getTerritoryId(therapyToTerritoryExt.get(spec.therapyArea));
            if (territoryId == null) {
                continue;
            }
            Id productId = productIdsByExtId.get(externalId);
            String key = String.valueOf(productId) + ':' + String.valueOf(territoryId);
            if (existingKeys.contains(key)) {
                continue;
            }
            alignments.add(new Product_Territory_Alignment__c(
                Product2_Id__c = String.valueOf(productId),
                Territory2_Id__c = String.valueOf(territoryId),
                Is_Active__c = true,
                Effective_Start_Date__c = Date.today().addMonths(-1)
            ));
        }
        insertInBatches(alignments);
        result.ptaInserted = alignments.size();
    }

    private static void reseedAccountTerritoryProductFields(CatalogResult result) {
        List<Product2> products = [
            SELECT Id
            FROM Product2
            WHERE External_ID__c LIKE 'CPI_%'
                AND Product_Type__c = 'Detail'
                AND IsActive = true
            WITH SYSTEM_MODE
            ORDER BY ProductCode ASC
            LIMIT 2
        ];
        if (products.isEmpty()) {
            return;
        }

        List<Account_Territory_Fields__c> atfRecords = [
            SELECT Id, Account__c, Territory2_Id__c
            FROM Account_Territory_Fields__c
            WITH SYSTEM_MODE
            LIMIT 500
        ];
        if (atfRecords.isEmpty()) {
            return;
        }

        Set<String> existingKeys = new Set<String>();
        for (Account_Territory_Product_Fields__c existing : [
            SELECT Unique_Key__c
            FROM Account_Territory_Product_Fields__c
            WHERE Unique_Key__c != NULL
            WITH SYSTEM_MODE
        ]) {
            existingKeys.add(existing.Unique_Key__c);
        }

        List<String> adoptions = new List<String>{ 'H', 'M', 'L' };
        List<String> loyalties = new List<String>{ 'H', 'M', 'L' };
        List<String> frequencies = new List<String>{ 'Weekly', 'Bi-Weekly', 'Monthly', 'Quarterly' };
        List<Account_Territory_Product_Fields__c> records = new List<Account_Territory_Product_Fields__c>();
        Integer index = 0;
        for (Account_Territory_Fields__c atf : atfRecords) {
            if (Math.mod(index, 2) != 0) {
                index++;
                continue;
            }
            for (Product2 product : products) {
                String key = String.valueOf(atf.Account__c) + ':' + atf.Territory2_Id__c + ':' + String.valueOf(product.Id);
                if (existingKeys.contains(key)) {
                    continue;
                }
                records.add(new Account_Territory_Product_Fields__c(
                    Account__c = atf.Account__c,
                    Territory2_Id__c = atf.Territory2_Id__c,
                    Product2_Id__c = String.valueOf(product.Id),
                    Rx_Per_Week__c = Decimal.valueOf(Math.mod(index + 1, 20) + 1),
                    Adoption__c = adoptions[Math.mod(index, adoptions.size())],
                    Loyalty__c = loyalties[Math.mod(index + 1, loyalties.size())],
                    Target_Visit_Frequency__c = frequencies[Math.mod(index, frequencies.size())],
                    Is_Active__c = true
                ));
            }
            index++;
        }
        insertInBatches(records);
        result.atpfInserted = records.size();
    }

    private static List<ProductSpec> buildProductSpecs() {
        List<ProductSpec> specs = new List<ProductSpec>();

        // --- Coloverin ---
        specs.add(brand(
            'CPI_COLOVERIN', 'Coloverin', 'CPI-COL', 'Coloverin',
            'Gastroenterology', 'Mebeverine HCl',
            'Coloverin brand — Mebeverine antispasmodic line for IBS and GI spasm.'
        ));
        specs.add(detail(
            'CPI_COLOVERIN_135', 'Coloverin 135 mg', 'CPI-COL-135', 'CPI_COLOVERIN', 'Coloverin',
            'Gastroenterology', 'Mebeverine HCl', '135mg', 'Sugar Coated Tablet', 'mg', 135, 30, 95,
            'Mebeverine HCl 135mg sugar coated tablet. Antispasmodic for IBS without atropine-like side effects.'
        ));
        specs.add(detail(
            'CPI_COLOVERIN_D_135_40', 'Coloverin D 135/40 mg', 'CPI-COL-D-135-40', 'CPI_COLOVERIN', 'Coloverin',
            'Gastroenterology', 'Mebeverine + Dimethicone', '135mg + 40mg', 'Film Coated Tablet', 'mg', 135, 30, 120,
            'Mebeverine 135mg + dimethicone 40mg film coated tablet (Coloverin D) for IBS with bloating.'
        ));
        specs.add(detail(
            'CPI_COLOVERIN_A_135_5', 'Coloverin A 135/5 mg', 'CPI-COL-A-135-5', 'CPI_COLOVERIN', 'Coloverin',
            'Gastroenterology', 'Mebeverine Hydrochloride + Chlordiazepoxide', '135mg + 5mg', 'Film Coated Tablet', 'mg', 135, 20, 130,
            'Mebeverine 135mg + chlordiazepoxide 5mg film coated tablet (Coloverin A).'
        ));
        specs.add(detail(
            'CPI_COLOVERIN_SR_200', 'Coloverin SR 200 mg', 'CPI-COL-SR-200', 'CPI_COLOVERIN', 'Coloverin',
            'Gastroenterology', 'Mebeverine HCl Pellets', '200mg', 'SR Hard Gelatin Capsule', 'mg', 200, 20, 140,
            'Mebeverine HCl pellets 200mg SR hard gelatin capsule (Coloverin SR).'
        ));
        specs.add(sample(
            'CPI_COLOVERIN_135_SAMPLE', 'Coloverin 135 mg Sample', 'CPI-COL-135-SMP', 'CPI_COLOVERIN', 'Coloverin',
            'Gastroenterology', 'Mebeverine HCl', '135mg', 'Sugar Coated Tablet', 'mg', 135, 4,
            'Coloverin 135mg leave-behind sample pack (4 sugar coated tablets).'
        ));
        specs.add(brandReminder(
            'CPI_COLOVERIN_BROCHURE', 'Coloverin Brand Brochure', 'CPI-COL-BRC', 'CPI_COLOVERIN', 'Coloverin',
            'Gastroenterology', 'Brochure',
            'Coloverin HCP brochure — leave-behind brand reminder for IBS indication.'
        ));
        specs.add(brandReminder(
            'CPI_COLOVERIN_BUG', 'Coloverin Sticky Pad Bug', 'CPI-COL-BUG', 'CPI_COLOVERIN', 'Coloverin',
            'Gastroenterology', 'Bug',
            'Coloverin branded sticky-pad giveaway (bug) for clinic desk leave-behind.'
        ));

        // --- Verserc ---
        specs.add(brand(
            'CPI_VERSERC', 'Verserc', 'CPI-VER', 'Verserc',
            'Neurology', 'Betahistine Dihydrochloride',
            'Verserc brand — Betahistine line for vertigo and Meniere\'s disease.'
        ));
        specs.add(detail(
            'CPI_VERSERC_8', 'Verserc 8 mg', 'CPI-VER-8', 'CPI_VERSERC', 'Verserc',
            'Neurology', 'Betahistine Dihydrochloride', '8mg', 'Tablet', 'mg', 8, 30, 75,
            'Betahistine dihydrochloride 8mg tablet for vertigo and Meniere\'s disease.'
        ));
        specs.add(detail(
            'CPI_VERSERC_16', 'Verserc 16 mg', 'CPI-VER-16', 'CPI_VERSERC', 'Verserc',
            'Neurology', 'Betahistine Dihydrochloride', '16mg', 'Tablet', 'mg', 16, 30, 95,
            'Betahistine dihydrochloride 16mg tablet for vertigo and Meniere\'s disease.'
        ));
        specs.add(detail(
            'CPI_VERSERC_24', 'Verserc 24 mg', 'CPI-VER-24', 'CPI_VERSERC', 'Verserc',
            'Neurology', 'Betahistine Dihydrochloride', '24mg', 'Tablet', 'mg', 24, 20, 110,
            'Betahistine dihydrochloride 24mg tablet for vertigo and Meniere\'s disease.'
        ));
        specs.add(sample(
            'CPI_VERSERC_16_SAMPLE', 'Verserc 16 mg Sample', 'CPI-VER-16-SMP', 'CPI_VERSERC', 'Verserc',
            'Neurology', 'Betahistine Dihydrochloride', '16mg', 'Tablet', 'mg', 16, 6,
            'Verserc 16mg leave-behind sample pack (6 tablets).'
        ));
        specs.add(brandReminder(
            'CPI_VERSERC_BROCHURE', 'Verserc Brand Brochure', 'CPI-VER-BRC', 'CPI_VERSERC', 'Verserc',
            'Neurology', 'Brochure',
            'Verserc HCP brochure — brand reminder for vertigo / Meniere\'s messaging.'
        ));

        // --- Dantrelax ---
        specs.add(brand(
            'CPI_DANTRELAX', 'Dantrelax', 'CPI-DAN', 'Dantrelax',
            'Rheumatology', 'Dantrolene Sodium',
            'Dantrelax brand — Dantrolene line for skeletal muscle spasm.'
        ));
        specs.add(detail(
            'CPI_DANTRELAX_25', 'Dantrelax 25 mg', 'CPI-DAN-25', 'CPI_DANTRELAX', 'Dantrelax',
            'Rheumatology', 'Dantrolene Sodium', '25mg', 'Hard Gelatin Capsule', 'mg', 25, 30, 85,
            'Dantrolene sodium 25mg hard gelatin capsule for skeletal muscle spasms.'
        ));
        specs.add(detail(
            'CPI_DANTRELAX_COMPOUND_25_300', 'Dantrelax Compound 25/300 mg', 'CPI-DAN-CMP-25-300', 'CPI_DANTRELAX', 'Dantrelax',
            'Rheumatology', 'Dantrolene Sodium + Paracetamol', '25mg + 300mg', 'Hard Gelatin Capsule', 'mg', 25, 20, 105,
            'Dantrolene sodium 25mg + paracetamol 300mg (Dantrelax Compound).'
        ));
        specs.add(sample(
            'CPI_DANTRELAX_25_SAMPLE', 'Dantrelax 25 mg Sample', 'CPI-DAN-25-SMP', 'CPI_DANTRELAX', 'Dantrelax',
            'Rheumatology', 'Dantrolene Sodium', '25mg', 'Hard Gelatin Capsule', 'mg', 25, 4,
            'Dantrelax 25mg leave-behind sample pack (4 hard gelatin capsules).'
        ));
        specs.add(brandReminder(
            'CPI_DANTRELAX_BUG', 'Dantrelax Pen Bug', 'CPI-DAN-BUG', 'CPI_DANTRELAX', 'Dantrelax',
            'Rheumatology', 'Bug',
            'Dantrelax branded pen giveaway (bug) for clinic leave-behind.'
        ));

        // --- Rosuvast ---
        specs.add(brand(
            'CPI_ROSUVAST', 'Rosuvast', 'CPI-ROS', 'Rosuvast',
            'Cardiovascular', 'Rosuvastatin Calcium',
            'Rosuvast brand — Rosuvastatin line for hypercholesterolemia.'
        ));
        specs.add(detail(
            'CPI_ROSUVAST_5', 'Rosuvast 5 mg', 'CPI-ROS-5', 'CPI_ROSUVAST', 'Rosuvast',
            'Cardiovascular', 'Rosuvastatin Calcium', '5mg', 'Film Coated Tablet', 'mg', 5, 28, 90,
            'Rosuvastatin calcium 5mg film coated tablet for hypercholesterolemia.'
        ));
        specs.add(detail(
            'CPI_ROSUVAST_10', 'Rosuvast 10 mg', 'CPI-ROS-10', 'CPI_ROSUVAST', 'Rosuvast',
            'Cardiovascular', 'Rosuvastatin Calcium', '10mg', 'Film Coated Tablet', 'mg', 10, 28, 120,
            'Rosuvastatin calcium 10mg film coated tablet for hypercholesterolemia.'
        ));
        specs.add(detail(
            'CPI_ROSUVAST_20', 'Rosuvast 20 mg', 'CPI-ROS-20', 'CPI_ROSUVAST', 'Rosuvast',
            'Cardiovascular', 'Rosuvastatin Calcium', '20mg', 'Film Coated Tablet', 'mg', 20, 28, 150,
            'Rosuvastatin calcium 20mg film coated tablet for hypercholesterolemia.'
        ));
        specs.add(sample(
            'CPI_ROSUVAST_10_SAMPLE', 'Rosuvast 10 mg Sample', 'CPI-ROS-10-SMP', 'CPI_ROSUVAST', 'Rosuvast',
            'Cardiovascular', 'Rosuvastatin Calcium', '10mg', 'Film Coated Tablet', 'mg', 10, 7,
            'Rosuvast 10mg leave-behind sample pack (7 film coated tablets).'
        ));
        specs.add(brandReminder(
            'CPI_ROSUVAST_BROCHURE', 'Rosuvast Brand Brochure', 'CPI-ROS-BRC', 'CPI_ROSUVAST', 'Rosuvast',
            'Cardiovascular', 'Brochure',
            'Rosuvast HCP brochure — LDL-C reduction and CV risk messaging.'
        ));

        // --- Algesal ---
        specs.add(brand(
            'CPI_ALGESAL', 'Algesal', 'CPI-ALG', 'Algesal',
            'Rheumatology', 'Diethylamine Salicylate',
            'Algesal brand — topical salicylate analgesic cream line.'
        ));
        specs.add(detail(
            'CPI_ALGESAL_10', 'Algesal Suractive Cream', 'CPI-ALG-10', 'CPI_ALGESAL', 'Algesal',
            'Rheumatology', 'Diethylamine Salicylate', '10gm/100gm', 'Cream', 'gm', 10, 1, 65,
            'Diethylamine salicylate 10gm/100gm cream for transdermal analgesia and rheumatic pain.'
        ));
        specs.add(sample(
            'CPI_ALGESAL_10_SAMPLE', 'Algesal Suractive Cream Sample', 'CPI-ALG-10-SMP', 'CPI_ALGESAL', 'Algesal',
            'Rheumatology', 'Diethylamine Salicylate', '10gm/100gm', 'Cream', 'gm', 10, 1,
            'Algesal Suractive leave-behind sample tube (small pack).'
        ));
        specs.add(brandReminder(
            'CPI_ALGESAL_BROCHURE', 'Algesal Brand Brochure', 'CPI-ALG-BRC', 'CPI_ALGESAL', 'Algesal',
            'Rheumatology', 'Brochure',
            'Algesal HCP brochure — topical analgesia without oral NSAID gastric risk.'
        ));

        // --- Soul Pharma ---
        specs.add(brand(
            'SOUL_SOULFORT', 'Soulfort', 'SOUL-FORT', 'Soulfort',
            'Consumer Health', 'Multivitamin + Zinc Complex',
            'Soulfort brand — Soul Pharma daily multivitamin + zinc supplement line.'
        ));
        specs.add(detail(
            'SOUL_SOULFORT_CAP_20', 'Soulfort Capsules', 'SOUL-FORT-20', 'SOUL_SOULFORT', 'Soulfort',
            'Consumer Health', 'Multivitamin + Zinc Complex', '500mg', 'Hard Gelatin Capsule', 'mg', 500, 20, 180,
            'Soulfort nutritional supplement, 20 hard gelatin capsules. Soul Pharma best-selling ' +
            'daily supplement for energy and immunity support.'
        ));
        specs.add(sample(
            'SOUL_SOULFORT_CAP_SAMPLE', 'Soulfort Capsules Sample', 'SOUL-FORT-SMP', 'SOUL_SOULFORT', 'Soulfort',
            'Consumer Health', 'Multivitamin + Zinc Complex', '500mg', 'Hard Gelatin Capsule', 'mg', 500, 4,
            'Soulfort leave-behind sample pack (4 hard gelatin capsules).'
        ));
        specs.add(brandReminder(
            'SOUL_SOULFORT_BROCHURE', 'Soulfort Brand Brochure', 'SOUL-FORT-BRC', 'SOUL_SOULFORT', 'Soulfort',
            'Consumer Health', 'Brochure',
            'Soulfort consumer / pharmacy brochure — energy and immunity positioning.'
        ));

        specs.add(brand(
            'SOUL_GENOLIGHT', 'Genolight', 'SOUL-GENO', 'Genolight',
            'Consumer Health', 'Niacinamide + Alpha Arbutin',
            'Genolight brand — Soul Pharma skin-brightening medical cosmetic line.'
        ));
        specs.add(detail(
            'SOUL_GENOLIGHT_CREAM', 'Genolight Whitening Cream', 'SOUL-GENO-30', 'SOUL_GENOLIGHT', 'Genolight',
            'Consumer Health', 'Niacinamide + Alpha Arbutin', '30gm', 'Topical Cream', 'gm', 30, 1, 150,
            'Genolight skin-brightening cream 30gm tube. Soul Pharma best-selling medical ' +
            'cosmetic for pigmentation and tone correction.'
        ));
        specs.add(sample(
            'SOUL_GENOLIGHT_CREAM_SAMPLE', 'Genolight Whitening Cream Sample', 'SOUL-GENO-SMP', 'SOUL_GENOLIGHT', 'Genolight',
            'Consumer Health', 'Niacinamide + Alpha Arbutin', '5gm', 'Topical Cream', 'gm', 5, 1,
            'Genolight leave-behind sample sachet/tube (5gm).'
        ));
        specs.add(brandReminder(
            'SOUL_GENOLIGHT_BUG', 'Genolight Mirror Bug', 'SOUL-GENO-BUG', 'SOUL_GENOLIGHT', 'Genolight',
            'Consumer Health', 'Bug',
            'Genolight branded pocket-mirror giveaway (bug) for pharmacy / clinic leave-behind.'
        ));

        return specs;
    }

    private static ProductSpec brand(
        String externalId,
        String name,
        String productCode,
        String productFamily,
        String therapyArea,
        String activeIngredient,
        String description
    ) {
        return baseSpec(externalId, name, productCode, 'Brand', null, null, productFamily,
            therapyArea, activeIngredient, null, null, null, null, null, 0, description);
    }

    private static ProductSpec detail(
        String externalId,
        String name,
        String productCode,
        String parentExternalId,
        String productFamily,
        String therapyArea,
        String activeIngredient,
        String strength,
        String form,
        String unitOfMeasure,
        Decimal quantityPerUnit,
        Decimal boxQuantity,
        Decimal unitPrice,
        String description
    ) {
        return baseSpec(externalId, name, productCode, 'Detail', parentExternalId, null, productFamily,
            therapyArea, activeIngredient, strength, form, unitOfMeasure, quantityPerUnit, boxQuantity,
            unitPrice, description);
    }

    private static ProductSpec sample(
        String externalId,
        String name,
        String productCode,
        String parentExternalId,
        String productFamily,
        String therapyArea,
        String activeIngredient,
        String strength,
        String form,
        String unitOfMeasure,
        Decimal quantityPerUnit,
        Decimal boxQuantity,
        String description
    ) {
        return baseSpec(externalId, name, productCode, 'Sample', parentExternalId, null, productFamily,
            therapyArea, activeIngredient, strength, form, unitOfMeasure, quantityPerUnit, boxQuantity,
            0, description);
    }

    private static ProductSpec brandReminder(
        String externalId,
        String name,
        String productCode,
        String parentExternalId,
        String productFamily,
        String therapyArea,
        String brandReminderKind,
        String description
    ) {
        return baseSpec(externalId, name, productCode, 'Brand Reminder', parentExternalId, brandReminderKind,
            productFamily, therapyArea, null, null, null, null, null, null, 0, description);
    }

    private static ProductSpec baseSpec(
        String externalId,
        String name,
        String productCode,
        String productType,
        String parentExternalId,
        String brandReminderKind,
        String productFamily,
        String therapyArea,
        String activeIngredient,
        String strength,
        String form,
        String unitOfMeasure,
        Decimal quantityPerUnit,
        Decimal boxQuantity,
        Decimal unitPrice,
        String description
    ) {
        ProductSpec productSpec = new ProductSpec();
        productSpec.externalId = externalId;
        productSpec.name = name;
        productSpec.productCode = productCode;
        productSpec.productType = productType;
        productSpec.parentExternalId = parentExternalId;
        productSpec.brandReminderKind = brandReminderKind;
        productSpec.productFamily = productFamily;
        productSpec.therapyArea = therapyArea;
        productSpec.activeIngredient = activeIngredient;
        productSpec.strength = strength;
        productSpec.form = form;
        productSpec.unitOfMeasure = unitOfMeasure;
        productSpec.quantityPerUnit = quantityPerUnit;
        productSpec.boxQuantity = boxQuantity;
        productSpec.unitPrice = unitPrice;
        productSpec.displayUrl = null;
        productSpec.imageUrl = null;
        productSpec.description = description;
        return productSpec;
    }

    private static Set<String> getExternalIds(List<ProductSpec> specs) {
        Set<String> ids = new Set<String>();
        for (ProductSpec spec : specs) {
            ids.add(spec.externalId);
        }
        return ids;
    }

    private static Integer deleteAllSObjects(String objectApiName) {
        String soql = 'SELECT Id FROM ' + objectApiName;
        List<SObject> records = Database.query(soql, AccessLevel.SYSTEM_MODE);
        if (records.isEmpty()) {
            return 0;
        }
        Integer deleted = 0;
        for (Integer start = 0; start < records.size(); start += BATCH_SIZE) {
            Integer endIdx = Math.min(start + BATCH_SIZE, records.size());
            List<SObject> batch = new List<SObject>();
            for (Integer i = start; i < endIdx; i++) {
                batch.add(records[i]);
            }
            Database.DeleteResult[] results = Database.delete(batch, false, AccessLevel.SYSTEM_MODE);
            for (Database.DeleteResult dr : results) {
                if (dr.isSuccess()) {
                    deleted++;
                }
            }
        }
        return deleted;
    }

    private static void deleteIfPresent(List<SObject> records) {
        if (records == null || records.isEmpty()) {
            return;
        }
        Database.delete(records, false, AccessLevel.SYSTEM_MODE);
    }

    private static void insertInBatches(List<SObject> records) {
        if (records == null || records.isEmpty()) {
            return;
        }
        for (Integer start = 0; start < records.size(); start += BATCH_SIZE) {
            Integer endIdx = Math.min(start + BATCH_SIZE, records.size());
            List<SObject> batch = new List<SObject>();
            for (Integer i = start; i < endIdx; i++) {
                batch.add(records[i]);
            }
            Database.insert(batch, AccessLevel.SYSTEM_MODE);
        }
    }

    private static Id resolveStandardPricebookId() {
        if (Test.isRunningTest()) {
            return Test.getStandardPricebookId();
        }
        List<Pricebook2> pricebooks = [
            SELECT Id
            FROM Pricebook2
            WHERE IsStandard = true
            WITH SYSTEM_MODE
            LIMIT 1
        ];
        if (pricebooks.isEmpty()) {
            throw new AuraHandledException('Standard Price Book not found.');
        }
        return pricebooks[0].Id;
    }

    private static Set<String> getCatalogExternalIds() {
        Set<String> ids = new Set<String>();
        for (ProductSpec spec : buildProductSpecs()) {
            ids.add(spec.externalId);
        }
        return ids;
    }

    private static String buildMessage(CatalogResult result) {
        return 'Catalog reset complete. Deleted ' + result.productsDeleted + ' products, ' +
            result.pricebookEntriesDeleted + ' pricebook entries, ' + result.pricebooksDeleted +
            ' custom pricebooks. Upserted ' + result.productsUpserted + ' Chemipharm products, ' +
            result.pricebookEntriesInserted + ' standard entries, ' + result.ptaInserted +
            ' PTA, ' + result.atpfInserted + ' ATPF.';
    }
}
