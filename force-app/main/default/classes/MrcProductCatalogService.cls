public without sharing class MrcProductCatalogService {

    private static final String PRODUCT_FAMILY = 'Misr Radiology';
    private static final String THERAPY_AREA = 'Diagnostic Imaging';

    public class CatalogResult {
        public Integer productsUpserted = 0;
        public Integer pricebookEntriesInserted = 0;
        public String message;
    }

    public class ProductSpec {
        public String externalId;
        public String name;
        public String productCode;
        public String serviceKey;
        public Decimal unitPrice;
        public String description;
    }

    /**
     * Upserts popular Misr Radiology Center diagnostic services as Product2 records
     * with Standard Price Book entries for CLM binding.
     */
    public static CatalogResult seedMrcCatalog() {
        CatalogResult result = new CatalogResult();
        List<ProductSpec> specs = buildProductSpecs();
        List<Product2> products = new List<Product2>();
        for (ProductSpec spec : specs) {
            products.add(new Product2(
                Name = spec.name,
                ProductCode = spec.productCode,
                External_ID__c = spec.externalId,
                Family = PRODUCT_FAMILY,
                Therapy_Area__c = THERAPY_AREA,
                Description = spec.description,
                IsActive = true
            ));
        }

        Database.UpsertResult[] upsertResults = Database.upsert(
            products,
            Product2.External_ID__c,
            false,
            AccessLevel.SYSTEM_MODE
        );
        for (Database.UpsertResult upsertResult : upsertResults) {
            if (upsertResult.isSuccess()) {
                result.productsUpserted++;
            } else {
                for (Database.Error err : upsertResult.getErrors()) {
                    System.debug('MRC product upsert error: ' + err.getMessage());
                }
            }
        }

        Map<String, Id> productIdsByExtId = loadProductIdsByExternalId(specs);
        result.pricebookEntriesInserted = ensureStandardPricebookEntries(specs, productIdsByExtId);
        result.message = 'Seeded ' + result.productsUpserted + ' MRC products with ' +
            result.pricebookEntriesInserted + ' new standard pricebook entries.';
        return result;
    }

    public static List<ProductSpec> getProductSpecs() {
        return buildProductSpecs();
    }

    public static Map<String, Id> getProductIdsByExternalId() {
        Set<String> externalIds = new Set<String>();
        for (ProductSpec spec : buildProductSpecs()) {
            externalIds.add(spec.externalId);
        }
        Map<String, Id> result = new Map<String, Id>();
        for (Product2 product : [
            SELECT Id, External_ID__c
            FROM Product2
            WHERE External_ID__c IN :externalIds
            WITH SYSTEM_MODE
        ]) {
            result.put(product.External_ID__c, product.Id);
        }
        return result;
    }

    private static List<ProductSpec> buildProductSpecs() {
        return new List<ProductSpec>{
            spec('MRC_MRI', 'MRI', 'MRC-MRI', 'mri', 2500,
                'Magnetic Resonance Imaging at Misr Radiology Center.'),
            spec('MRC_CT_SCAN', 'CT Scan', 'MRC-CT', 'ct_scan', 1800,
                'Multi-slice CT imaging at Misr Radiology Center.'),
            spec('MRC_PET_CT', 'PET/CT', 'MRC-PET-CT', 'pet_ct', 6500,
                'Hybrid PET/CT oncology imaging at Misr Radiology Center.'),
            spec('MRC_ULTRASOUND', 'Ultrasound', 'MRC-US', 'ultrasound', 600,
                'Diagnostic ultrasound at Misr Radiology Center.'),
            spec('MRC_BREAST_IMAGING', 'Breast Imaging (Mammography)', 'MRC-MAMMO', 'breast_imaging', 900,
                'Digital mammography at Misr Radiology Center.'),
            spec('MRC_DENTAL_IMAGING', 'Dental Imaging Unit', 'MRC-DENTAL', 'dental_imaging', 450,
                'Panoramic and cone-beam dental imaging at Misr Radiology Center.')
        };
    }

    private static ProductSpec spec(
        String externalId,
        String name,
        String productCode,
        String serviceKey,
        Decimal unitPrice,
        String description
    ) {
        ProductSpec productSpec = new ProductSpec();
        productSpec.externalId = externalId;
        productSpec.name = name;
        productSpec.productCode = productCode;
        productSpec.serviceKey = serviceKey;
        productSpec.unitPrice = unitPrice;
        productSpec.description = description;
        return productSpec;
    }

    private static Map<String, Id> loadProductIdsByExternalId(List<ProductSpec> specs) {
        Set<String> externalIds = new Set<String>();
        for (ProductSpec spec : specs) {
            externalIds.add(spec.externalId);
        }
        Map<String, Id> productIdsByExtId = new Map<String, Id>();
        for (Product2 product : [
            SELECT Id, External_ID__c
            FROM Product2
            WHERE External_ID__c IN :externalIds
            WITH SYSTEM_MODE
        ]) {
            productIdsByExtId.put(product.External_ID__c, product.Id);
        }
        return productIdsByExtId;
    }

    private static Integer ensureStandardPricebookEntries(
        List<ProductSpec> specs,
        Map<String, Id> productIdsByExtId
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

        List<PricebookEntry> toInsert = new List<PricebookEntry>();
        for (ProductSpec spec : specs) {
            Id productId = productIdsByExtId.get(spec.externalId);
            if (productId == null || existingProductIds.contains(productId)) {
                continue;
            }
            toInsert.add(new PricebookEntry(
                Pricebook2Id = standardPricebookId,
                Product2Id = productId,
                UnitPrice = spec.unitPrice,
                IsActive = true,
                UseStandardPrice = false
            ));
        }

        if (toInsert.isEmpty()) {
            return 0;
        }

        Integer inserted = 0;
        Database.SaveResult[] results = Database.insert(toInsert, false, AccessLevel.SYSTEM_MODE);
        for (Database.SaveResult saveResult : results) {
            if (saveResult.isSuccess()) {
                inserted++;
            }
        }
        return inserted;
    }

    private static Id resolveStandardPricebookId() {
        return Test.isRunningTest()
            ? Test.getStandardPricebookId()
            : [SELECT Id FROM Pricebook2 WHERE IsStandard = true WITH SYSTEM_MODE LIMIT 1].Id;
    }
}
