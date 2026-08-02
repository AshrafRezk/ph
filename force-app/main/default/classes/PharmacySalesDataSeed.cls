public without sharing class PharmacySalesDataSeed {
    public class SeedResult {
        public Integer bricksCreated = 0;
        public Integer pharmaciesCreated = 0;
        public Integer membershipsCreated = 0;
        public Integer affiliationsLinked = 0;
        public Integer withdrawalsPurged = 0;
        public Integer withdrawalsCreated = 0;
        public String message;
    }

    private static final List<String> PHARMACY_SPECS = new List<String>{
        'PHARM_EL_EZABY_MAADI|El Ezaby Pharmacy - Maadi',
        'PHARM_EL_EZABY_ZAMALEK|El Ezaby Pharmacy - Zamalek',
        'PHARM_SEIF|Seif Pharmacies - Nasr City',
        'PHARM_19011|19011 Pharmacy - Heliopolis',
        'PHARM_AHLI|Al Ahli Pharmacy - Dokki',
        'PHARM_MISR|Misr Pharmacy - Alexandria',
        'PHARM_ROXY|Roxy Pharmacy - Heliopolis',
        'PHARM_KHALIL|Dr. Mustafa Khalil Pharmacy - Smouha'
    };

    // externalId|name|brickCode|governorate|city|territoryExternalId|dataSource
    private static final List<String> BRICK_SPECS = new List<String>{
        'BRICK_EG10101|Maadi - Degla|EG-10101|Cairo|Maadi|TERR_GIT_DM_1_MR_1|IQVIA IMS',
        'BRICK_EG10102|Zamalek - Agouza|EG-10102|Cairo|Zamalek|TERR_GIT_DM_1_MR_1|IQVIA IMS',
        'BRICK_EG10201|Nasr City - Abbas El Akkad|EG-10201|Cairo|Nasr City|TERR_CNS_DM_1_MR_1|IQVIA IMS',
        'BRICK_EG10202|Heliopolis - Korba|EG-10202|Cairo|Heliopolis|TERR_CNS_DM_1_MR_1|IbnSina',
        'BRICK_EG10301|Dokki - Tahrir|EG-10301|Giza|Dokki|TERR_RHEUM_DM_1_MR_1|IQVIA IMS',
        'BRICK_EG20101|Alex - Stanley|EG-20101|Alexandria|Stanley|TERR_RHEUM_DM_1_MR_1|Pharmaoverseas',
        'BRICK_EG20102|Alex - Smouha|EG-20102|Alexandria|Smouha|TERR_RHEUM_DM_1_MR_1|Pharmaoverseas',
        'BRICK_EG10401|Cairo West - Dokki|EG-10401|Giza|Dokki|TERR_CARDIO_DM_1_MR_1|IQVIA IMS',
        'BRICK_EG10402|Cairo West - Mohandeseen|EG-10402|Giza|Mohandeseen|TERR_CARDIO_DM_1_MR_1|Pharmaoverseas',
        'BRICK_EG10601|Maadi - Retail Cluster|EG-10601|Cairo|Maadi|TERR_CHC_DM_1_MR_1|IbnSina',
        'BRICK_EG10602|Heliopolis - Retail Cluster|EG-10602|Cairo|Heliopolis|TERR_CHC_DM_1_MR_1|Pharmaoverseas'
    };

    // Calibrated to ~EGP 2.2B annual sell-out; ~10% of company spend is promotional (context only).
    private static final Decimal ANNUAL_REVENUE_TARGET = 2200000000.0;
    private static final Integer SEED_MONTH_COUNT = 12;

    private static final Map<String, Decimal> BASE_BU_REVENUE_SHARE = new Map<String, Decimal>{
        'GIT' => 0.26,
        'CNS' => 0.20,
        'Rheumatology' => 0.23,
        'Cardiovascular' => 0.23,
        'Consumer Health' => 0.08
    };

    private static final Map<String, String> PHARMACY_POTENTIAL_BY_EXT = new Map<String, String>{
        'PHARM_EL_EZABY_MAADI' => 'A',
        'PHARM_SEIF' => 'A',
        'PHARM_EL_EZABY_ZAMALEK' => 'B',
        'PHARM_19011' => 'B',
        'PHARM_AHLI' => 'B',
        'PHARM_MISR' => 'C'
    };

    private static final List<Decimal> MONTHLY_SEASONALITY = new List<Decimal>{
        0.92, 0.95, 1.00, 1.02, 1.05, 1.08, 1.06, 1.04, 1.00, 0.98, 0.95, 1.03
    };

    public static SeedResult seedDemoData() {
        SeedResult result = new SeedResult();
        purgeLegacyBricks();
        Id pharmacyRtId = resolvePharmacyRecordTypeId();
        Map<String, Id> pharmacyIds = upsertPharmacies(pharmacyRtId, result);
        Map<String, Id> brickIds = upsertBricks(result);
        createMemberships(pharmacyIds, brickIds, result);
        result.affiliationsLinked = linkPharmacyAffiliations(pharmacyIds);
        result.withdrawalsPurged = purgeDemoWithdrawals(pharmacyIds.values());
        createWithdrawals(pharmacyIds, brickIds, result);
        result.message = 'Purged ' + result.withdrawalsPurged + ' stale rows. Seeded ' +
            result.withdrawalsCreated + ' withdrawal rows across ' +
            result.bricksCreated + ' bricks and ' + result.pharmaciesCreated + ' pharmacies ' +
            '(~EGP 2.2B annual; BU shares GIT 26% / CNS 20% / Rheumatology 23% / Cardiovascular 23% ' +
            '/ Consumer Health 8% incl. Soul Pharma Soulfort + Genolight). ' +
            'Linked ' + result.affiliationsLinked + ' pharmacy-HCP affiliations for insights.';
        return result;
    }

    private static Id resolvePharmacyRecordTypeId() {
        List<RecordType> rts = [
            SELECT Id
            FROM RecordType
            WHERE SObjectType = 'Account'
            AND DeveloperName = 'Pharmacy'
            WITH SYSTEM_MODE
            LIMIT 1
        ];
        return rts.isEmpty() ? null : rts[0].Id;
    }

    private static Map<String, Id> upsertPharmacies(Id pharmacyRtId, SeedResult result) {
        List<Account> pharmacies = new List<Account>();
        for (String spec : PHARMACY_SPECS) {
            List<String> parts = spec.split('\\|');
            Account pharmacy = new Account(
                Name = parts[1],
                External_ID__c = parts[0],
                Account_Status__c = 'Active'
            );
            if (pharmacyRtId != null) {
                pharmacy.RecordTypeId = pharmacyRtId;
            }
            AccountPhoneDefaults.applyDemoPhone(pharmacy);
            pharmacies.add(pharmacy);
        }
        Database.UpsertResult[] upserts = Database.upsert(pharmacies, Account.External_ID__c, false, AccessLevel.SYSTEM_MODE);
        for (Database.UpsertResult ur : upserts) {
            if (ur.isSuccess()) {
                result.pharmaciesCreated++;
            }
        }
        Map<String, Id> ids = new Map<String, Id>();
        for (Account pharmacy : [
            SELECT Id, External_ID__c
            FROM Account
            WHERE External_ID__c IN :externalIdsFromSpecs(PHARMACY_SPECS)
            WITH SYSTEM_MODE
        ]) {
            ids.put(pharmacy.External_ID__c, pharmacy.Id);
        }
        return ids;
    }

    private static Map<String, Id> upsertBricks(SeedResult result) {
        Set<String> territoryExtIds = new Set<String>();
        for (String spec : BRICK_SPECS) {
            territoryExtIds.add(spec.split('\\|')[5]);
        }
        Map<String, Id> territoryIdsByExt = resolveTerritoryIdsByExternalId(territoryExtIds);
        List<Brick__c> bricks = new List<Brick__c>();
        for (String spec : BRICK_SPECS) {
            List<String> parts = spec.split('\\|');
            Brick__c brick = new Brick__c(
                Name = parts[1],
                External_ID__c = parts[0],
                Is_Active__c = true
            );
            setFieldIfPresent(brick, 'Brick_Code__c', parts[2]);
            setFieldIfPresent(brick, 'Governorate__c', parts[3]);
            setFieldIfPresent(brick, 'City__c', parts[4]);
            setFieldIfPresent(brick, 'Data_Source__c', parts[6]);
            Id territoryId = territoryIdsByExt.get(parts[5]);
            if (territoryId != null && PharmacySalesFieldSupport.hasField(Brick__c.SObjectType, 'Territory2_Id__c')) {
                brick.put('Territory2_Id__c', String.valueOf(territoryId));
            }
            bricks.add(brick);
        }
        Database.UpsertResult[] upserts = Database.upsert(bricks, Brick__c.External_ID__c, false, AccessLevel.SYSTEM_MODE);
        for (Database.UpsertResult ur : upserts) {
            if (ur.isSuccess()) {
                result.bricksCreated++;
            }
        }
        Map<String, Id> ids = new Map<String, Id>();
        for (Brick__c brick : [
            SELECT Id, External_ID__c
            FROM Brick__c
            WHERE External_ID__c IN :externalIdsFromSpecs(BRICK_SPECS)
            WITH SYSTEM_MODE
        ]) {
            ids.put(brick.External_ID__c, brick.Id);
        }
        return ids;
    }

    private static void createMemberships(
        Map<String, Id> pharmacyIds,
        Map<String, Id> brickIds,
        SeedResult result
    ) {
        List<Brick_Pharmacy__c> memberships = new List<Brick_Pharmacy__c>{
            membership(brickIds.get('BRICK_EG10101'), pharmacyIds.get('PHARM_EL_EZABY_MAADI')),
            membership(brickIds.get('BRICK_EG10301'), pharmacyIds.get('PHARM_AHLI')),
            membership(brickIds.get('BRICK_EG10102'), pharmacyIds.get('PHARM_EL_EZABY_ZAMALEK')),
            membership(brickIds.get('BRICK_EG10201'), pharmacyIds.get('PHARM_SEIF')),
            membership(brickIds.get('BRICK_EG10202'), pharmacyIds.get('PHARM_19011')),
            membership(brickIds.get('BRICK_EG10202'), pharmacyIds.get('PHARM_ROXY')),
            membership(brickIds.get('BRICK_EG20101'), pharmacyIds.get('PHARM_MISR')),
            membership(brickIds.get('BRICK_EG20102'), pharmacyIds.get('PHARM_KHALIL'))
        };
        Database.UpsertResult[] upserts = Database.upsert(
            memberships,
            Brick_Pharmacy__c.Unique_Key__c,
            false,
            AccessLevel.SYSTEM_MODE
        );
        for (Database.UpsertResult ur : upserts) {
            if (ur.isSuccess()) {
                result.membershipsCreated++;
            }
        }
        syncAccountBrickLookups(memberships);
    }

    private static Brick_Pharmacy__c membership(Id brickId, Id pharmacyId) {
        return new Brick_Pharmacy__c(
            Brick__c = brickId,
            Pharmacy_Account__c = pharmacyId,
            Unique_Key__c = String.valueOf(brickId) + ':' + String.valueOf(pharmacyId),
            Is_Active__c = true
        );
    }

    private static Integer purgeDemoWithdrawals(List<Id> pharmacyIds) {
        if (pharmacyIds == null || pharmacyIds.isEmpty()) {
            return 0;
        }
        List<Pharmacy_Sales_Withdrawal__c> staleRows = [
            SELECT Id
            FROM Pharmacy_Sales_Withdrawal__c
            WHERE Pharmacy_Account__c IN :pharmacyIds
            WITH SYSTEM_MODE
        ];
        if (staleRows.isEmpty()) {
            return 0;
        }
        Database.delete(staleRows, false, AccessLevel.SYSTEM_MODE);
        return staleRows.size();
    }

    private static void createWithdrawals(
        Map<String, Id> pharmacyIds,
        Map<String, Id> brickIds,
        SeedResult result
    ) {
        List<Product2> products = [
            SELECT Id, External_ID__c, Family, Therapy_Area__c
            FROM Product2
            WHERE (External_ID__c LIKE 'CPI_%' OR External_ID__c LIKE 'SOUL_%')
            AND IsActive = TRUE
            WITH SYSTEM_MODE
        ];
        if (products.isEmpty()) {
            return;
        }

        Map<String, List<Product2>> productsByBu = groupProductsByBu(products);
        if (productsByBu.isEmpty()) {
            return;
        }

        Map<Id, Id> brickByPharmacy = new Map<Id, Id>();
        for (Brick_Pharmacy__c bp : [
            SELECT Pharmacy_Account__c, Brick__c
            FROM Brick_Pharmacy__c
            WITH SYSTEM_MODE
        ]) {
            brickByPharmacy.put(bp.Pharmacy_Account__c, bp.Brick__c);
        }

        Map<Id, Decimal> prices = loadStandardPrices(products);
        List<String> sources = new List<String>{ 'IbnSina', 'Pharmaoverseas' };
        List<Pharmacy_Sales_Withdrawal__c> rows = new List<Pharmacy_Sales_Withdrawal__c>();
        Integer monthCount = Test.isRunningTest() ? 2 : SEED_MONTH_COUNT;
        Date startMonth = Date.today().toStartOfMonth().addMonths(-(monthCount - 1));
        Boolean hasRevenueField = PharmacySalesFieldSupport.hasField(
            Pharmacy_Sales_Withdrawal__c.SObjectType,
            'Revenue__c'
        );

        Integer monthOffset = 0;
        while (monthOffset < monthCount) {
            Date reportMonth = startMonth.addMonths(monthOffset);
            String source = sources[Math.mod(monthOffset, sources.size())];
            Decimal monthlyRevenue = monthlyRevenueTarget(reportMonth, monthOffset);
            Map<String, Decimal> buWeights = activeBuWeights(normalizedBuWeights(reportMonth), productsByBu);

            for (String pharmacyExtId : pharmacyIds.keySet()) {
                Id pharmacyId = pharmacyIds.get(pharmacyExtId);
                Decimal pharmacyShare = pharmacyRevenueShare(pharmacyExtId);

                for (String bu : buWeights.keySet()) {
                    List<Product2> buProducts = productsByBu.get(bu);
                    if (buProducts == null || buProducts.isEmpty()) {
                        continue;
                    }
                    Decimal buRevenue = monthlyRevenue * buWeights.get(bu) * pharmacyShare;
                    Id brickId = brickByPharmacy.get(pharmacyId);
                    Decimal productRevenue = buRevenue / buProducts.size();

                    for (Product2 product : buProducts) {
                        Decimal unitPrice = prices.containsKey(product.Id) ? prices.get(product.Id) : 100;
                        Decimal revenue = productRevenue.setScale(2, RoundingMode.HALF_UP);
                        Decimal qty = unitPrice > 0
                            ? (revenue / unitPrice).setScale(0, RoundingMode.HALF_UP)
                            : 1;
                        if (qty < 1) {
                            qty = 1;
                        }

                        Pharmacy_Sales_Withdrawal__c row = new Pharmacy_Sales_Withdrawal__c(
                            Data_Source__c = source,
                            Report_Month__c = reportMonth,
                            Pharmacy_Account__c = pharmacyId,
                            Brick__c = brickByPharmacy.get(pharmacyId),
                            Product2_Id__c = String.valueOf(product.Id),
                            Quantity_Withdrawn__c = qty,
                            Unit_Price__c = unitPrice,
                            Unique_Key__c = source + '_' + monthKey(reportMonth) + '_' + pharmacyId + '_' + product.Id
                        );
                        if (hasRevenueField) {
                            row.put('Revenue__c', revenue);
                        }
                        rows.add(row);
                    }
                }
            }
            monthOffset++;
        }

        Database.UpsertResult[] upserts = Database.upsert(
            rows,
            Pharmacy_Sales_Withdrawal__c.Unique_Key__c,
            false,
            AccessLevel.SYSTEM_MODE
        );
        for (Database.UpsertResult ur : upserts) {
            if (ur.isSuccess()) {
                result.withdrawalsCreated++;
            }
        }
    }

    private static Map<String, List<Product2>> groupProductsByBu(List<Product2> products) {
        Map<String, List<Product2>> grouped = new Map<String, List<Product2>>();
        for (Product2 product : products) {
            String bu = resolveBu(product);
            if (!grouped.containsKey(bu)) {
                grouped.put(bu, new List<Product2>());
            }
            grouped.get(bu).add(product);
        }
        return grouped;
    }

    private static String resolveBu(Product2 product) {
        String therapyArea = product.Therapy_Area__c;
        if (therapyArea == 'Gastroenterology') {
            return 'GIT';
        }
        if (therapyArea == 'Neurology') {
            return 'CNS';
        }
        if (therapyArea == 'Rheumatology') {
            return 'Rheumatology';
        }
        if (therapyArea == 'Cardiovascular') {
            return 'Cardiovascular';
        }
        if (therapyArea == 'Consumer Health') {
            return 'Consumer Health';
        }
        return 'GIT';
    }

    private static Decimal pharmacyRevenueShare(String pharmacyExtId) {
        String tier = PHARMACY_POTENTIAL_BY_EXT.get(pharmacyExtId);
        if (tier == 'A') {
            return 0.15;
        }
        if (tier == 'B') {
            return 0.20;
        }
        return 0.10;
    }

    private static Decimal monthlyRevenueTarget(Date reportMonth, Integer monthOffset) {
        Integer seasonalityIndex = Math.mod(monthOffset, MONTHLY_SEASONALITY.size());
        Decimal seasonality = MONTHLY_SEASONALITY[seasonalityIndex];
        return (ANNUAL_REVENUE_TARGET / SEED_MONTH_COUNT) * seasonality;
    }

    private static Map<String, Decimal> normalizedBuWeights(Date reportMonth) {
        Map<String, Decimal> weights = new Map<String, Decimal>();
        Decimal total = 0;
        for (String bu : BASE_BU_REVENUE_SHARE.keySet()) {
            Decimal share = BASE_BU_REVENUE_SHARE.get(bu);
            weights.put(bu, share);
            total += share;
        }
        Map<String, Decimal> normalized = new Map<String, Decimal>();
        for (String bu : weights.keySet()) {
            normalized.put(bu, total > 0 ? weights.get(bu) / total : 0);
        }
        return normalized;
    }

    private static Map<String, Decimal> activeBuWeights(
        Map<String, Decimal> buWeights,
        Map<String, List<Product2>> productsByBu
    ) {
        Map<String, Decimal> active = new Map<String, Decimal>();
        Decimal total = 0;
        for (String bu : buWeights.keySet()) {
            List<Product2> buProducts = productsByBu.get(bu);
            if (buProducts == null || buProducts.isEmpty()) {
                continue;
            }
            active.put(bu, buWeights.get(bu));
            total += buWeights.get(bu);
        }
        if (total <= 0) {
            return active;
        }
        Map<String, Decimal> normalized = new Map<String, Decimal>();
        for (String bu : active.keySet()) {
            normalized.put(bu, active.get(bu) / total);
        }
        return normalized;
    }

    private static Map<Id, String> loadBrickExternalIds(Set<Id> brickIds) {
        Map<Id, String> result = new Map<Id, String>();
        if (brickIds == null || brickIds.isEmpty()) {
            return result;
        }
        for (Brick__c brick : [
            SELECT Id, External_ID__c
            FROM Brick__c
            WHERE Id IN :brickIds
            WITH SYSTEM_MODE
        ]) {
            result.put(brick.Id, brick.External_ID__c);
        }
        return result;
    }

    private static Map<Id, Decimal> loadStandardPrices(List<Product2> products) {
        Map<Id, Decimal> result = new Map<Id, Decimal>();
        Set<Id> productIds = new Map<Id, Product2>(products).keySet();
        List<Pricebook2> pbs = [SELECT Id FROM Pricebook2 WHERE IsStandard = TRUE WITH SYSTEM_MODE LIMIT 1];
        if (pbs.isEmpty()) {
            return result;
        }
        for (PricebookEntry pbe : [
            SELECT Product2Id, UnitPrice
            FROM PricebookEntry
            WHERE Pricebook2Id = :pbs[0].Id
            AND Product2Id IN :productIds
            WITH SYSTEM_MODE
        ]) {
            result.put(pbe.Product2Id, pbe.UnitPrice);
        }
        return result;
    }

    private static Set<String> externalIdsFromSpecs(List<String> specs) {
        Set<String> ids = new Set<String>();
        for (String spec : specs) {
            ids.add(spec.split('\\|')[0]);
        }
        return ids;
    }

    private static String monthKey(Date monthDate) {
        return String.valueOf(monthDate.year()) + '-' + String.valueOf(monthDate.month()).leftPad(2, '0');
    }

    private static void purgeLegacyBricks() {
        Set<String> legacyExtIds = new Set<String>{
            'BRICK_MAADI',
            'BRICK_ZAMALEK',
            'BRICK_NASR_CITY',
            'BRICK_ALEX'
        };
        List<Brick__c> stale = [
            SELECT Id
            FROM Brick__c
            WHERE External_ID__c IN :legacyExtIds
            WITH SYSTEM_MODE
        ];
        if (!stale.isEmpty()) {
            Database.delete(stale, false, AccessLevel.SYSTEM_MODE);
        }
    }

    private static Map<String, Id> resolveTerritoryIdsByExternalId(Set<String> externalIds) {
        Map<String, Id> result = new Map<String, Id>();
        if (externalIds == null || externalIds.isEmpty()) {
            return result;
        }
        for (Territory2 territory : [
            SELECT Id, External_ID__c
            FROM Territory2
            WHERE External_ID__c IN :externalIds
            WITH SYSTEM_MODE
        ]) {
            result.put(territory.External_ID__c, territory.Id);
        }
        return result;
    }

    private static void syncAccountBrickLookups(List<Brick_Pharmacy__c> memberships) {
        if (!PharmacySalesFieldSupport.hasField(Account.SObjectType, 'Brick__c')) {
            return;
        }
        List<Account> updates = new List<Account>();
        for (Brick_Pharmacy__c membership : memberships) {
            if (membership.Pharmacy_Account__c == null || membership.Brick__c == null) {
                continue;
            }
            updates.add(new Account(
                Id = membership.Pharmacy_Account__c,
                Brick__c = membership.Brick__c
            ));
        }
        if (!updates.isEmpty()) {
            Database.update(updates, false, AccessLevel.SYSTEM_MODE);
        }
    }

    private static void setFieldIfPresent(SObject record, String fieldApiName, Object value) {
        if (PharmacySalesFieldSupport.hasField(record.getSObjectType(), fieldApiName)) {
            record.put(fieldApiName, value);
        }
    }

    private static Integer linkPharmacyAffiliations(Map<String, Id> pharmacyIds) {
        List<String> pharmacyKeys = new List<String>{
            'PHARM_EL_EZABY_MAADI',
            'PHARM_SEIF',
            'PHARM_EL_EZABY_ZAMALEK'
        };
        List<Id> targetPharmacyIds = new List<Id>();
        for (String key : pharmacyKeys) {
            if (pharmacyIds.containsKey(key)) {
                targetPharmacyIds.add(pharmacyIds.get(key));
            }
        }
        if (targetPharmacyIds.isEmpty()) {
            return 0;
        }

        List<Account> hcps = [
            SELECT Id
            FROM Account
            WHERE IsPersonAccount = TRUE
            AND Account_Status__c = 'Active'
            WITH SYSTEM_MODE
            LIMIT 6
        ];
        if (hcps.isEmpty()) {
            return 0;
        }

        List<Account_Affiliation__c> affiliations = new List<Account_Affiliation__c>();
        for (Integer i = 0; i < hcps.size(); i++) {
            Id pharmacyId = targetPharmacyIds[Math.mod(i, targetPharmacyIds.size())];
            affiliations.add(new Account_Affiliation__c(
                Primary_Account__c = hcps[i].Id,
                Related_Account__c = pharmacyId,
                Affiliation_Type__c = 'Partner',
                Role__c = 'Pharmacist',
                Strength__c = 'Medium',
                Influence__c = 'Medium',
                Is_Active__c = true,
                Outside_Territory__c = false,
                Description__c = 'Pharmacy sales insights demo affiliation'
            ));
        }
        Database.SaveResult[] saves = Database.insert(affiliations, false, AccessLevel.SYSTEM_MODE);
        Integer linked = 0;
        for (Database.SaveResult saveResult : saves) {
            if (saveResult.isSuccess()) {
                linked++;
            }
        }
        return linked;
    }
}
