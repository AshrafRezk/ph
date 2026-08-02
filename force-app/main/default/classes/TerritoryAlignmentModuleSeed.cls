public without sharing class TerritoryAlignmentModuleSeed {

    private static final Integer BATCH_SIZE = 200;
    private static final Integer MAX_ATF_SEED = 500;

    public class SeedResult {
        public Integer layoutCount;
        public Integer layoutFieldCount;
        public Integer atfCount;
        public Integer atpfCount;
        public Integer ptaCount;
        public String message;
    }

    /**
     * Seeds default rating layouts and demo account territory ratings.
     * Run after AccountAffiliationModuleSeed.seedDemoData().
     */
    public static SeedResult seedDemoData() {
        SeedResult result = new SeedResult();
        seedRatingLayouts(result);
        seedProductTerritoryAlignments(result);
        seedAccountTerritoryFields(result);
        seedInstitutionTerritoryFields(result);
        seedAccountTerritoryProductFields(result);
        TerritoryModuleSeed.assignAdminToHeadOffice();
        result.message = 'Seeded ' + result.layoutCount + ' layouts, ' + result.atfCount +
            ' ATF, ' + result.atpfCount + ' ATPF, ' + result.ptaCount + ' PTA records.';
        return result;
    }

    private static void seedRatingLayouts(SeedResult result) {
        List<LayoutSpec> layoutSpecs = new List<LayoutSpec>{
            new LayoutSpec(
                'DEMO_ATF_DEFAULT',
                'Default HCP Territory Rating',
                'Account Territory Fields',
                true,
                'Standard territory-level Potential, Penetration, and Classification ratings.',
                new List<FieldSpec>{
                    fieldSpec('DEMO_ATF_KOL', 'Is_KOL__c', 'Is KOL', 5, 'KOL', false, false),
                    fieldSpec('DEMO_ATF_KOL_WHAT', 'KOL_In_What__c', 'KOL Reason', 6, 'KOL', false, false),
                    fieldSpec('DEMO_ATF_POTENTIAL', 'Potential__c', 'Potential', 10, 'Primary Ratings', true, false),
                    fieldSpec('DEMO_ATF_PENETRATION', 'Penetration__c', 'Penetration', 20, 'Primary Ratings', true, false),
                    fieldSpec('DEMO_ATF_MATRIX', 'Matrix_Rating__c', 'Matrix Rating', 30, 'Calculated Ratings', false, true),
                    fieldSpec('DEMO_ATF_CLASS', 'Classification__c', 'Classification', 40, 'Calculated Ratings', false, true)
                }
            ),
            new LayoutSpec(
                'DEMO_ATPF_DEFAULT',
                'Default Product Targeting Rating',
                'Account Territory Product Fields',
                true,
                'Product-level adoption and visit frequency metrics per territory.',
                new List<FieldSpec>{
                    fieldSpec('DEMO_ATPF_RX', 'Rx_Per_Week__c', 'Rx Per Week', 10, 'Product Metrics', false, false),
                    fieldSpec('DEMO_ATPF_ADOPTION', 'Adoption__c', 'Adoption', 20, 'Product Metrics', false, false),
                    fieldSpec('DEMO_ATPF_LOYALTY', 'Loyalty__c', 'Loyalty', 30, 'Product Metrics', false, false),
                    fieldSpec('DEMO_ATPF_MATRIX', 'Product_Matrix_Rating__c', 'Product Matrix Rating', 40, 'Calculated Ratings', false, true),
                    fieldSpec('DEMO_ATPF_FREQ', 'Target_Visit_Frequency__c', 'Target Visit Frequency', 50, 'Product Metrics', false, false),
                    fieldSpec('DEMO_ATPF_NOTES', 'Notes__c', 'Notes', 60, 'General', false, false)
                }
            )
        };

        List<Account_Rating_Layout__c> layouts = new List<Account_Rating_Layout__c>();
        for (LayoutSpec spec : layoutSpecs) {
            layouts.add(new Account_Rating_Layout__c(
                External_Id__c = spec.externalId,
                Layout_Title__c = spec.title,
                Layout_Type__c = spec.layoutType,
                Is_Active__c = true,
                Is_Default__c = spec.isDefault,
                Description__c = spec.description
            ));
        }
        Database.upsert(layouts, Account_Rating_Layout__c.External_Id__c, AccessLevel.SYSTEM_MODE);

        Map<String, Id> layoutIdsByExtId = new Map<String, Id>();
        for (Account_Rating_Layout__c layout : [
            SELECT Id, External_Id__c
            FROM Account_Rating_Layout__c
            WHERE External_Id__c IN :getLayoutExternalIds(layoutSpecs)
            WITH SYSTEM_MODE
        ]) {
            layoutIdsByExtId.put(layout.External_Id__c, layout.Id);
        }

        List<Account_Rating_Layout_Field__c> layoutFields = new List<Account_Rating_Layout_Field__c>();
        for (LayoutSpec spec : layoutSpecs) {
            Id layoutId = layoutIdsByExtId.get(spec.externalId);
            if (layoutId == null) {
                continue;
            }
            for (FieldSpec fs : spec.fields) {
                layoutFields.add(new Account_Rating_Layout_Field__c(
                    External_Id__c = fs.externalId,
                    Account_Rating_Layout__c = layoutId,
                    Field_API_Name__c = fs.apiName,
                    Display_Label__c = fs.label,
                    Display_Order__c = fs.displayOrder,
                    Section__c = fs.section,
                    Is_Required__c = fs.isRequired,
                    Is_Read_Only__c = fs.isReadOnly
                ));
            }
        }
        Database.upsert(layoutFields, Account_Rating_Layout_Field__c.External_Id__c, AccessLevel.SYSTEM_MODE);

        result.layoutCount = layouts.size();
        result.layoutFieldCount = layoutFields.size();
    }

    private static void seedProductTerritoryAlignments(SeedResult result) {
        Integer zetaProductCount = [
            SELECT COUNT()
            FROM Product2
            WHERE External_ID__c LIKE 'CPI_%' AND IsActive = true
            WITH SYSTEM_MODE
        ];
        if (!Test.isRunningTest() && zetaProductCount > 0) {
            return;
        }

        List<Id> territoryIds = TerritoryModuleSeed.getMrTerritoryIds();
        List<Product2> products = getNonZetaActiveProducts(4);
        if (territoryIds.isEmpty() || products.isEmpty()) {
            return;
        }

        Set<String> existingKeys = new Set<String>();
        for (Product_Territory_Alignment__c existing : [
            SELECT Unique_Key__c
            FROM Product_Territory_Alignment__c
            WHERE Unique_Key__c != null
            WITH SYSTEM_MODE
        ]) {
            existingKeys.add(existing.Unique_Key__c);
        }

        List<Product_Territory_Alignment__c> alignments = new List<Product_Territory_Alignment__c>();
        for (Product2 product : products) {
            for (Id territoryId : territoryIds) {
                if (territoryId == null) {
                    continue;
                }
                String key = String.valueOf(product.Id) + ':' + String.valueOf(territoryId);
                if (existingKeys.contains(key)) {
                    continue;
                }
                alignments.add(new Product_Territory_Alignment__c(
                    Product2_Id__c = String.valueOf(product.Id),
                    Territory2_Id__c = String.valueOf(territoryId),
                    Is_Active__c = true,
                    Effective_Start_Date__c = Date.today().addMonths(-1)
                ));
            }
        }
        insertInBatches(alignments);
        result.ptaCount = alignments.size();
    }

    private static void seedAccountTerritoryFields(SeedResult result) {
        Integer maxCount = Test.isRunningTest() ? 5 : MAX_ATF_SEED;
        Integer existingCount = [
            SELECT COUNT()
            FROM Account_Territory_Fields__c
            WITH SYSTEM_MODE
        ];
        if (!Test.isRunningTest() && existingCount >= maxCount) {
            result.atfCount = 0;
            return;
        }

        List<Account> hcps = [
            SELECT Id
            FROM Account
            WHERE External_ID__c LIKE 'DEMO_HCP_%'
            WITH SYSTEM_MODE
            ORDER BY External_ID__c
            LIMIT :maxCount
        ];
        if (hcps.isEmpty()) {
            return;
        }

        Map<Id, Id> territoryByAccountId = getPrimaryTerritoryByAccountId(hcps);
        Set<String> existingKeys = new Set<String>();
        for (Account_Territory_Fields__c existing : [
            SELECT Unique_Key__c
            FROM Account_Territory_Fields__c
            WHERE Account__c IN :hcps
            WITH SYSTEM_MODE
        ]) {
            if (existing.Unique_Key__c != null) {
                existingKeys.add(existing.Unique_Key__c);
            }
        }

        List<String> penetrations = new List<String>{ '1', '2', '3' };
        List<Account_Territory_Fields__c> records = new List<Account_Territory_Fields__c>();
        Integer index = 0;
        Integer total = hcps.size();
        for (Account hcp : hcps) {
            Id territoryId = territoryByAccountId.get(hcp.Id);
            if (territoryId == null) {
                continue;
            }
            String key = String.valueOf(hcp.Id) + ':' + String.valueOf(territoryId);
            if (existingKeys.contains(key)) {
                index++;
                continue;
            }
            records.add(new Account_Territory_Fields__c(
                Account__c = hcp.Id,
                Territory2_Id__c = String.valueOf(territoryId),
                Potential__c = potentialForIndex(index, total),
                Penetration__c = penetrations[Math.mod(index, penetrations.size())],
                Is_Active__c = true
            ));
            index++;
        }
        insertInBatches(records);
        result.atfCount = records.size();
    }

    private static void seedInstitutionTerritoryFields(SeedResult result) {
        List<Account> institutions = [
            SELECT Id, External_ID__c
            FROM Account
            WHERE External_ID__c LIKE 'DEMO_HCO_%' OR External_ID__c LIKE 'DEMO_PH_%'
            WITH SYSTEM_MODE
            ORDER BY External_ID__c
        ];
        List<Account> filteredInstitutions = new List<Account>();
        for (Account institution : institutions) {
            if (institution.External_ID__c != null && !institution.External_ID__c.contains('PARENT')) {
                filteredInstitutions.add(institution);
            }
        }
        institutions = filteredInstitutions;
        if (institutions.isEmpty()) {
            return;
        }

        Map<Id, Id> territoryByAccountId = getPrimaryTerritoryByAccountId(institutions);
        Set<String> existingKeys = new Set<String>();
        for (Account_Territory_Fields__c existing : [
            SELECT Unique_Key__c
            FROM Account_Territory_Fields__c
            WHERE Account__c IN :institutions
            WITH SYSTEM_MODE
        ]) {
            if (existing.Unique_Key__c != null) {
                existingKeys.add(existing.Unique_Key__c);
            }
        }

        List<String> penetrations = new List<String>{ '1', '2', '3' };
        List<Account_Territory_Fields__c> records = new List<Account_Territory_Fields__c>();
        Integer index = 0;
        Integer total = institutions.size();
        for (Account institution : institutions) {
            Id territoryId = territoryByAccountId.get(institution.Id);
            if (territoryId == null) {
                continue;
            }
            String key = String.valueOf(institution.Id) + ':' + String.valueOf(territoryId);
            if (existingKeys.contains(key)) {
                index++;
                continue;
            }
            records.add(new Account_Territory_Fields__c(
                Account__c = institution.Id,
                Territory2_Id__c = String.valueOf(territoryId),
                Potential__c = potentialForIndex(index, total),
                Penetration__c = penetrations[Math.mod(index, penetrations.size())],
                Is_Active__c = true
            ));
            index++;
        }
        if (!records.isEmpty()) {
            insertInBatches(records);
            result.atfCount = (result.atfCount == null ? 0 : result.atfCount) + records.size();
        }
    }

    private static void seedAccountTerritoryProductFields(SeedResult result) {
        List<Product2> products = getNonZetaActiveProducts(2);
        if (products.isEmpty()) {
            return;
        }

        List<Account_Territory_Fields__c> atfRecords = [
            SELECT Id, Account__c, Territory2_Id__c
            FROM Account_Territory_Fields__c
            WITH SYSTEM_MODE
            LIMIT :(Test.isRunningTest() ? 5 : MAX_ATF_SEED)
        ];
        if (atfRecords.isEmpty()) {
            return;
        }

        Set<String> existingKeys = new Set<String>();
        for (Account_Territory_Product_Fields__c existing : [
            SELECT Unique_Key__c
            FROM Account_Territory_Product_Fields__c
            WHERE Unique_Key__c != null
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
        result.atpfCount = records.size();
    }

    private static String potentialForIndex(Integer index, Integer totalCount) {
        if (totalCount == null || totalCount <= 0) {
            return 'B';
        }
        Decimal position = Decimal.valueOf(index) / Decimal.valueOf(totalCount);
        if (position < 0.30) {
            return 'A';
        }
        if (position < 0.90) {
            return 'B';
        }
        return 'C';
    }

    private static List<Product2> getNonZetaActiveProducts(Integer maxCount) {
        List<Product2> selected = new List<Product2>();
        for (Product2 product : [
            SELECT Id, External_ID__c
            FROM Product2
            WHERE IsActive = true
            WITH SYSTEM_MODE
            ORDER BY Name ASC
        ]) {
            if (product.External_ID__c != null && product.External_ID__c.startsWith('ZETA_')) {
                continue;
            }
            selected.add(product);
            if (selected.size() >= maxCount) {
                break;
            }
        }
        return selected;
    }

    private static Map<Id, Id> getPrimaryTerritoryByAccountId(List<Account> accounts) {
        Map<Id, Id> territoryByAccountId = new Map<Id, Id>();
        Set<Id> accountIds = new Map<Id, Account>(accounts).keySet();
        for (ObjectTerritory2Association ota : [
            SELECT ObjectId, Territory2Id
            FROM ObjectTerritory2Association
            WHERE ObjectId IN :accountIds
            WITH SYSTEM_MODE
        ]) {
            if (!territoryByAccountId.containsKey(ota.ObjectId)) {
                territoryByAccountId.put(ota.ObjectId, ota.Territory2Id);
            }
        }
        return territoryByAccountId;
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

    private static Set<String> getLayoutExternalIds(List<LayoutSpec> specs) {
        Set<String> ids = new Set<String>();
        for (LayoutSpec spec : specs) {
            ids.add(spec.externalId);
        }
        return ids;
    }

    private static FieldSpec fieldSpec(
        String externalId,
        String apiName,
        String label,
        Integer displayOrder,
        String section,
        Boolean isRequired,
        Boolean isReadOnly
    ) {
        FieldSpec spec = new FieldSpec();
        spec.externalId = externalId;
        spec.apiName = apiName;
        spec.label = label;
        spec.displayOrder = displayOrder;
        spec.section = section;
        spec.isRequired = isRequired;
        spec.isReadOnly = isReadOnly;
        return spec;
    }

    private class LayoutSpec {
        public String externalId;
        public String title;
        public String layoutType;
        public Boolean isDefault;
        public String description;
        public List<FieldSpec> fields;

        public LayoutSpec(
            String externalId,
            String title,
            String layoutType,
            Boolean isDefault,
            String description,
            List<FieldSpec> fields
        ) {
            this.externalId = externalId;
            this.title = title;
            this.layoutType = layoutType;
            this.isDefault = isDefault;
            this.description = description;
            this.fields = fields;
        }
    }

    private class FieldSpec {
        public String externalId;
        public String apiName;
        public String label;
        public Integer displayOrder;
        public String section;
        public Boolean isRequired;
        public Boolean isReadOnly;
    }
}
