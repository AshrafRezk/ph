public without sharing class EgyptCoverageMapSeed {

    public class SeedResult {
        public Integer bricksUpserted = 0;
        public Integer pharmaciesUpserted = 0;
        public Integer salesRowsUpserted = 0;
        public String message;
    }

    // externalId|name|brickCode|governorate|city|territoryExternalId|monthlyRevenueEgp
    private static final List<String> COVERAGE_BRICK_SPECS = new List<String>{
        'BRICK_EG30101|Dakahlia - Mansoura Central|EG-30101|Dakahlia|Mansoura|TERR_DIABETES_DM_1_MR_1|4200000',
        'BRICK_EG30102|Qalyubia - Shubra El Kheima|EG-30102|Qalyubia|Shubra|TERR_DIABETES_DM_1_MR_1|3100000',
        'BRICK_EG30103|Sharqia - Zagazig|EG-30103|Sharqia|Zagazig|TERR_DIABETES_DM_1_MR_1|2800000',
        'BRICK_EG30104|Gharbia - Tanta|EG-30104|Gharbia|Tanta|TERR_DIABETES_DM_1_MR_1|2500000',
        'BRICK_EG30105|Beheira - Damanhour|EG-30105|Beheira|Damanhour|TERR_DIABETES_DM_1_MR_1|1900000',
        'BRICK_EG30106|Ismailia - City Center|EG-30106|Ismailia|Ismailia|TERR_DIABETES_DM_1_MR_1|1600000',
        'BRICK_EG30107|Minya - City|EG-30107|Minya|Minya|TERR_DIABETES_DM_1_MR_1|1400000',
        'BRICK_EG30108|Assiut - City|EG-30108|Assiut|Assiut|TERR_DIABETES_DM_1_MR_1|1200000',
        'BRICK_EG30109|Luxor - East Bank|EG-30109|Luxor|Luxor|TERR_DIABETES_DM_1_MR_1|900000',
        'BRICK_EG30110|Aswan - City|EG-30110|Aswan|Aswan|TERR_DIABETES_DM_1_MR_1|750000',
        'BRICK_EG30111|Fayoum - City|EG-30111|Fayoum|Fayoum|TERR_DIABETES_DM_1_MR_1|1100000',
        'BRICK_EG30112|Kafr El Sheikh - City|EG-30112|Kafr El Sheikh|Kafr El Sheikh|TERR_DIABETES_DM_1_MR_1|1700000'
    };

    /**
     * Idempotent seed: expands brick + pharmacy sell-out coverage across Egyptian governorates
     * for the Team KPI Egypt heat map demo.
     */
    public static SeedResult seedCoverageMapData() {
        SeedResult result = new SeedResult();
        Id pharmacyRtId = resolvePharmacyRecordTypeId();
        Map<String, Id> territoryIds = resolveTerritoryIds();
        Map<String, Id> brickIds = upsertCoverageBricks(territoryIds, result);
        Map<String, Id> pharmacyIds = upsertCoveragePharmacies(pharmacyRtId, result);
        createMemberships(brickIds, pharmacyIds, result);
        result.salesRowsUpserted = upsertCurrentMonthSales(brickIds, pharmacyIds);
        result.message = 'Upserted ' + result.bricksUpserted + ' bricks, ' +
            result.pharmaciesUpserted + ' pharmacies, ' + result.salesRowsUpserted + ' sales rows.';
        return result;
    }

    private static Id resolvePharmacyRecordTypeId() {
        List<RecordType> rts = [
            SELECT Id FROM RecordType
            WHERE SObjectType = 'Account' AND DeveloperName = 'Pharmacy'
            WITH SYSTEM_MODE LIMIT 1
        ];
        return rts.isEmpty() ? null : rts[0].Id;
    }

    private static Map<String, Id> resolveTerritoryIds() {
        Set<String> extIds = new Set<String>();
        for (String spec : COVERAGE_BRICK_SPECS) {
            extIds.add(spec.split('\\|')[5]);
        }
        Map<String, Id> result = new Map<String, Id>();
        for (Territory2 territory : [
            SELECT Id, External_ID__c FROM Territory2
            WHERE External_ID__c IN :extIds WITH SYSTEM_MODE
        ]) {
            result.put(territory.External_ID__c, territory.Id);
        }
        return result;
    }

    private static Map<String, Id> upsertCoverageBricks(Map<String, Id> territoryIds, SeedResult result) {
        List<Brick__c> bricks = new List<Brick__c>();
        for (String spec : COVERAGE_BRICK_SPECS) {
            List<String> parts = spec.split('\\|');
            Brick__c brick = new Brick__c(
                Name = parts[1],
                External_ID__c = parts[0],
                Is_Active__c = true
            );
            setFieldIfPresent(brick, 'Brick_Code__c', parts[2]);
            setFieldIfPresent(brick, 'Governorate__c', parts[3]);
            setFieldIfPresent(brick, 'City__c', parts[4]);
            setFieldIfPresent(brick, 'Data_Source__c', 'IQVIA IMS');
            Id territoryId = territoryIds.get(parts[5]);
            if (territoryId != null && PharmacySalesFieldSupport.hasField(Brick__c.SObjectType, 'Territory2_Id__c')) {
                brick.put('Territory2_Id__c', String.valueOf(territoryId));
            }
            bricks.add(brick);
        }
        Database.UpsertResult[] upserts = Database.upsert(bricks, Brick__c.External_ID__c, false, AccessLevel.SYSTEM_MODE);
        for (Database.UpsertResult ur : upserts) {
            if (ur.isSuccess()) {
                result.bricksUpserted++;
            }
        }
        Map<String, Id> ids = new Map<String, Id>();
        for (Brick__c brick : [
            SELECT Id, External_ID__c FROM Brick__c
            WHERE External_ID__c IN :externalIdsFromSpecs() WITH SYSTEM_MODE
        ]) {
            ids.put(brick.External_ID__c, brick.Id);
        }
        return ids;
    }

    private static Map<String, Id> upsertCoveragePharmacies(Id pharmacyRtId, SeedResult result) {
        List<Account> pharmacies = new List<Account>();
        for (String spec : COVERAGE_BRICK_SPECS) {
            List<String> parts = spec.split('\\|');
            String extId = parts[0].replace('BRICK_', 'PHARM_');
            Account pharmacy = new Account(
                Name = parts[1] + ' Pharmacy',
                External_ID__c = extId,
                Account_Status__c = 'Active',
                BillingState = parts[3],
                BillingCountry = 'Egypt'
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
                result.pharmaciesUpserted++;
            }
        }
        Map<String, Id> ids = new Map<String, Id>();
        for (Account pharmacy : [
            SELECT Id, External_ID__c FROM Account
            WHERE External_ID__c LIKE 'PHARM_EG301%' WITH SYSTEM_MODE
        ]) {
            ids.put(pharmacy.External_ID__c, pharmacy.Id);
        }
        return ids;
    }

    private static void createMemberships(
        Map<String, Id> brickIds,
        Map<String, Id> pharmacyIds,
        SeedResult result
    ) {
        List<Brick_Pharmacy__c> memberships = new List<Brick_Pharmacy__c>();
        for (String spec : COVERAGE_BRICK_SPECS) {
            List<String> parts = spec.split('\\|');
            String brickExt = parts[0];
            String pharmExt = brickExt.replace('BRICK_', 'PHARM_');
            Id brickId = brickIds.get(brickExt);
            Id pharmacyId = pharmacyIds.get(pharmExt);
            if (brickId == null || pharmacyId == null) {
                continue;
            }
            memberships.add(new Brick_Pharmacy__c(
                Brick__c = brickId,
                Pharmacy_Account__c = pharmacyId,
                Unique_Key__c = String.valueOf(brickId) + ':' + String.valueOf(pharmacyId),
                Is_Active__c = true
            ));
        }
        if (!memberships.isEmpty()) {
            Database.upsert(memberships, Brick_Pharmacy__c.Unique_Key__c, false, AccessLevel.SYSTEM_MODE);
        }
    }

    private static Integer upsertCurrentMonthSales(Map<String, Id> brickIds, Map<String, Id> pharmacyIds) {
        List<Product2> products = [
            SELECT Id FROM Product2
            WHERE External_ID__c LIKE 'CPI_%' AND IsActive = TRUE
            WITH SYSTEM_MODE LIMIT 1
        ];
        if (products.isEmpty()) {
            return 0;
        }
        Id productId = products[0].Id;
        Date reportMonth = Date.newInstance(Date.today().year(), Date.today().month(), 1);
        List<Pharmacy_Sales_Withdrawal__c> rows = new List<Pharmacy_Sales_Withdrawal__c>();

        for (String spec : COVERAGE_BRICK_SPECS) {
            List<String> parts = spec.split('\\|');
            String brickExt = parts[0];
            String pharmExt = brickExt.replace('BRICK_', 'PHARM_');
            Id brickId = brickIds.get(brickExt);
            Id pharmacyId = pharmacyIds.get(pharmExt);
            if (brickId == null || pharmacyId == null) {
                continue;
            }
            Decimal revenue = Decimal.valueOf(parts[6]);
            Pharmacy_Sales_Withdrawal__c row = new Pharmacy_Sales_Withdrawal__c(
                Data_Source__c = 'IbnSina',
                Report_Month__c = reportMonth,
                Pharmacy_Account__c = pharmacyId,
                Brick__c = brickId,
                Product2_Id__c = String.valueOf(productId),
                Quantity_Withdrawn__c = 100,
                Unit_Price__c = revenue / 100,
                Unique_Key__c = 'EGMAP_' + reportMonth.format() + '_' + brickId + '_' + productId
            );
            if (PharmacySalesFieldSupport.hasField(Pharmacy_Sales_Withdrawal__c.SObjectType, 'Revenue__c')) {
                row.put('Revenue__c', revenue);
            }
            rows.add(row);
        }

        if (rows.isEmpty()) {
            return 0;
        }
        Database.UpsertResult[] upserts = Database.upsert(
            rows,
            Pharmacy_Sales_Withdrawal__c.Unique_Key__c,
            false,
            AccessLevel.SYSTEM_MODE
        );
        Integer count = 0;
        for (Database.UpsertResult ur : upserts) {
            if (ur.isSuccess()) {
                count++;
            }
        }
        return count;
    }

    private static Set<String> externalIdsFromSpecs() {
        Set<String> ids = new Set<String>();
        for (String spec : COVERAGE_BRICK_SPECS) {
            ids.add(spec.split('\\|')[0]);
        }
        return ids;
    }

    private static void setFieldIfPresent(SObject record, String fieldName, Object value) {
        if (record == null || String.isBlank(fieldName)) {
            return;
        }
        Map<String, Schema.SObjectField> fields = record.getSObjectType().getDescribe().fields.getMap();
        if (fields.containsKey(fieldName)) {
            record.put(fieldName, value);
        }
    }
}
