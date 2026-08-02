/**
 * Aligns demo HCP accounts to each MR territory in slices sized by ChemipharmDemoDataProfiles.targetCustomers.
 * Run after AccountAffiliationModuleSeed and before MedicalRep360Seed / time-card target sync.
 */
public without sharing class DemoMrAccountAlignmentSeed {

    private static final Integer BATCH_SIZE = 200;

    private static final List<String> MR_USER_KEYS = new List<String>{
        'git_mr', 'cns_mr', 'rheum_mr', 'cardio_mr', 'chc_mr'
    };

    private static final Map<String, String> MR_TO_TERRITORY_EXT = new Map<String, String>{
        'git_mr' => 'TERR_GIT_DM_1_MR_1',
        'cns_mr' => 'TERR_CNS_DM_1_MR_1',
        'rheum_mr' => 'TERR_RHEUM_DM_1_MR_1',
        'cardio_mr' => 'TERR_CARDIO_DM_1_MR_1',
        'chc_mr' => 'TERR_CHC_DM_1_MR_1'
    };

    public class SeedResult {
        public Integer otaCount = 0;
        public Integer atfCount = 0;
        public Integer atpfCount = 0;
        public String message;
    }

    public static SeedResult alignAllMrAccounts() {
        SeedResult result = new SeedResult();
        Map<String, Id> territoryIdsByExt = loadTerritoryIdsByExternalId();
        List<Account> hcps = loadHcpAccounts();
        if (hcps.isEmpty()) {
            result.message = 'No DEMO_HCP accounts found. Run AccountAffiliationModuleSeed first.';
            return result;
        }

        Set<String> existingOtaKeys = loadExistingOtaKeys();
        Set<String> existingAtfKeys = loadExistingAtfKeys();
        Set<String> existingAtpfKeys = loadExistingAtpfKeys();
        List<Product2> products = loadActiveProducts(Test.isRunningTest() ? 1 : 2);

        List<ObjectTerritory2Association> otaToInsert = new List<ObjectTerritory2Association>();
        List<Account_Territory_Fields__c> atfToInsert = new List<Account_Territory_Fields__c>();
        List<Account_Territory_Product_Fields__c> atpfToInsert = new List<Account_Territory_Product_Fields__c>();

        Integer cursor = 0;
        Integer repIndex = 0;
        for (String mrKey : MR_USER_KEYS) {
            ChemipharmDemoDataProfiles.DemoUserProfile profile = ChemipharmDemoDataProfiles.getUserProfile(mrKey);
            Integer targetCount = resolveTargetCount(profile);
            String territoryExt = MR_TO_TERRITORY_EXT.get(mrKey);
            Id territoryId = territoryIdsByExt.get(territoryExt);
            if (territoryId == null) {
                repIndex++;
                continue;
            }

            List<Account> slice = sliceAccounts(hcps, cursor, targetCount);
            cursor += slice.size();
            Integer fieldIndex = 0;
            for (Account hcp : slice) {
                String otaKey = String.valueOf(hcp.Id) + ':' + String.valueOf(territoryId);
                if (!existingOtaKeys.contains(otaKey)) {
                    otaToInsert.add(new ObjectTerritory2Association(
                        ObjectId = hcp.Id,
                        Territory2Id = territoryId,
                        AssociationCause = 'Territory2Manual'
                    ));
                    existingOtaKeys.add(otaKey);
                    result.otaCount++;
                }

                String atfKey = String.valueOf(hcp.Id) + ':' + String.valueOf(territoryId);
                if (!existingAtfKeys.contains(atfKey)) {
                    atfToInsert.add(buildAtf(hcp.Id, territoryId, fieldIndex, slice.size()));
                    existingAtfKeys.add(atfKey);
                    result.atfCount++;
                }

                if (!products.isEmpty() && Math.mod(fieldIndex, 2) == 0) {
                    for (Product2 product : products) {
                        String atpfKey = String.valueOf(hcp.Id) + ':' + String.valueOf(territoryId) + ':' + String.valueOf(product.Id);
                        if (!existingAtpfKeys.contains(atpfKey)) {
                            atpfToInsert.add(buildAtpf(hcp.Id, territoryId, product.Id, fieldIndex));
                            existingAtpfKeys.add(atpfKey);
                            result.atpfCount++;
                        }
                    }
                }
                fieldIndex++;
            }
            repIndex++;
        }

        insertInBatches(otaToInsert);
        insertInBatches(atfToInsert);
        insertInBatches(atpfToInsert);
        result.atfCount += deactivateNonHcpAtfOnMrTerritories(territoryIdsByExt.values());
        result.atfCount += deactivateOutOfSliceHcpAtf(hcps, territoryIdsByExt);

        result.message = 'Aligned demo MR accounts: ' + result.otaCount + ' OTA, ' +
            result.atfCount + ' ATF, ' + result.atpfCount + ' ATPF.';
        return result;
    }

    private static Integer resolveTargetCount(ChemipharmDemoDataProfiles.DemoUserProfile profile) {
        if (profile == null || profile.targetCustomers == null || profile.targetCustomers <= 0) {
            return Test.isRunningTest() ? 3 : 70;
        }
        if (Test.isRunningTest()) {
            return Math.min(3, profile.targetCustomers);
        }
        return profile.targetCustomers;
    }

    private static List<Account> sliceAccounts(List<Account> hcps, Integer startIndex, Integer count) {
        List<Account> slice = new List<Account>();
        if (count <= 0 || hcps.isEmpty()) {
            return slice;
        }
        for (Integer i = 0; i < count; i++) {
            Integer index = startIndex + i;
            if (index >= hcps.size()) {
                index = Math.mod(index, hcps.size());
            }
            slice.add(hcps[index]);
        }
        return slice;
    }

    private static Account_Territory_Fields__c buildAtf(Id accountId, Id territoryId, Integer index, Integer total) {
        List<String> potentials = new List<String>{ 'A', 'B', 'C' };
        List<String> penetrations = new List<String>{ '1', '2', '3' };
        return new Account_Territory_Fields__c(
            Account__c = accountId,
            Territory2_Id__c = String.valueOf(territoryId),
            Potential__c = potentialForIndex(index, total, potentials),
            Penetration__c = penetrations[Math.mod(index, penetrations.size())],
            Is_Active__c = true
        );
    }

    private static Account_Territory_Product_Fields__c buildAtpf(
        Id accountId,
        Id territoryId,
        Id productId,
        Integer index
    ) {
        List<String> adoptions = new List<String>{ 'H', 'M', 'L' };
        List<String> loyalties = new List<String>{ 'H', 'M', 'L' };
        List<String> frequencies = new List<String>{ 'Weekly', 'Bi-Weekly', 'Monthly', 'Quarterly' };
        return new Account_Territory_Product_Fields__c(
            Account__c = accountId,
            Territory2_Id__c = String.valueOf(territoryId),
            Product2_Id__c = String.valueOf(productId),
            Rx_Per_Week__c = Decimal.valueOf(Math.mod(index + 1, 20) + 1),
            Adoption__c = adoptions[Math.mod(index, adoptions.size())],
            Loyalty__c = loyalties[Math.mod(index + 1, loyalties.size())],
            Target_Visit_Frequency__c = frequencies[Math.mod(index, frequencies.size())],
            Is_Active__c = true
        );
    }

    private static String potentialForIndex(Integer index, Integer total, List<String> potentials) {
        if (total == null || total <= 0) {
            return potentials[1];
        }
        Decimal position = Decimal.valueOf(index) / Decimal.valueOf(total);
        if (position < 0.30) {
            return potentials[0];
        }
        if (position < 0.90) {
            return potentials[1];
        }
        return potentials[2];
    }

    private static List<Account> loadHcpAccounts() {
        Integer limitSize = Test.isRunningTest() ? 20 : 500;
        return [
            SELECT Id, External_ID__c
            FROM Account
            WHERE External_ID__c LIKE 'DEMO_HCP_%'
            WITH SYSTEM_MODE
            ORDER BY External_ID__c ASC
            LIMIT :limitSize
        ];
    }

    private static Map<String, Id> loadTerritoryIdsByExternalId() {
        Map<String, Id> result = new Map<String, Id>();
        for (Territory2 territory : [
            SELECT Id, External_ID__c
            FROM Territory2
            WHERE External_ID__c IN :MR_TO_TERRITORY_EXT.values()
            WITH SYSTEM_MODE
        ]) {
            result.put(territory.External_ID__c, territory.Id);
        }
        return result;
    }

    private static Set<String> loadExistingOtaKeys() {
        Set<String> keys = new Set<String>();
        for (ObjectTerritory2Association ota : [
            SELECT ObjectId, Territory2Id
            FROM ObjectTerritory2Association
            WHERE Territory2.External_ID__c IN :MR_TO_TERRITORY_EXT.values()
            WITH SYSTEM_MODE
        ]) {
            keys.add(String.valueOf(ota.ObjectId) + ':' + String.valueOf(ota.Territory2Id));
        }
        return keys;
    }

    private static Set<String> loadExistingAtfKeys() {
        Set<String> keys = new Set<String>();
        for (Account_Territory_Fields__c atf : [
            SELECT Unique_Key__c
            FROM Account_Territory_Fields__c
            WHERE Territory2_Id__c != null
            WITH SYSTEM_MODE
        ]) {
            if (atf.Unique_Key__c != null) {
                keys.add(atf.Unique_Key__c);
            }
        }
        return keys;
    }

    private static Set<String> loadExistingAtpfKeys() {
        Set<String> keys = new Set<String>();
        for (Account_Territory_Product_Fields__c atpf : [
            SELECT Unique_Key__c
            FROM Account_Territory_Product_Fields__c
            WHERE Unique_Key__c != null
            WITH SYSTEM_MODE
        ]) {
            keys.add(atpf.Unique_Key__c);
        }
        return keys;
    }

    private static List<Product2> loadActiveProducts(Integer maxCount) {
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

  private static Integer deactivateNonHcpAtfOnMrTerritories(Iterable<Id> territoryIds) {
        Set<String> territoryIdStrings = new Set<String>();
        for (Id territoryId : territoryIds) {
            if (territoryId != null) {
                territoryIdStrings.add(String.valueOf(territoryId));
            }
        }
        if (territoryIdStrings.isEmpty()) {
            return 0;
        }

        List<Account_Territory_Fields__c> atfRecords = [
            SELECT Id, Account__r.External_ID__c
            FROM Account_Territory_Fields__c
            WHERE Territory2_Id__c IN :territoryIdStrings
            AND Is_Active__c = true
            WITH SYSTEM_MODE
        ];
        List<Account_Territory_Fields__c> toDeactivate = new List<Account_Territory_Fields__c>();
        for (Account_Territory_Fields__c atf : atfRecords) {
            String externalId = atf.Account__r.External_ID__c;
            if (externalId == null || !externalId.startsWith('DEMO_HCP_')) {
                atf.Is_Active__c = false;
                toDeactivate.add(atf);
            }
        }
        if (!toDeactivate.isEmpty()) {
            Database.update(toDeactivate, AccessLevel.SYSTEM_MODE);
        }
        return toDeactivate.size();
    }

    private static Integer deactivateOutOfSliceHcpAtf(
        List<Account> hcps,
        Map<String, Id> territoryIdsByExt
    ) {
        Map<Id, Set<Id>> allowedAccountsByTerritory = new Map<Id, Set<Id>>();
        Integer cursor = 0;
        for (String mrKey : MR_USER_KEYS) {
            ChemipharmDemoDataProfiles.DemoUserProfile profile = ChemipharmDemoDataProfiles.getUserProfile(mrKey);
            Integer targetCount = resolveTargetCount(profile);
            Id territoryId = territoryIdsByExt.get(MR_TO_TERRITORY_EXT.get(mrKey));
            if (territoryId == null) {
                continue;
            }
            Set<Id> allowed = new Set<Id>();
            for (Account hcp : sliceAccounts(hcps, cursor, targetCount)) {
                allowed.add(hcp.Id);
            }
            cursor += targetCount;
            allowedAccountsByTerritory.put(territoryId, allowed);
        }

        Set<String> territoryIdStrings = new Set<String>();
        for (Id territoryId : allowedAccountsByTerritory.keySet()) {
            territoryIdStrings.add(String.valueOf(territoryId));
        }
        if (territoryIdStrings.isEmpty()) {
            return 0;
        }

        List<Account_Territory_Fields__c> toDeactivate = new List<Account_Territory_Fields__c>();
        for (Account_Territory_Fields__c atf : [
            SELECT Id, Account__c, Territory2_Id__c
            FROM Account_Territory_Fields__c
            WHERE Territory2_Id__c IN :territoryIdStrings
            AND Is_Active__c = true
            WITH SYSTEM_MODE
        ]) {
            Set<Id> allowed = allowedAccountsByTerritory.get((Id) atf.Territory2_Id__c);
            if (allowed == null || !allowed.contains(atf.Account__c)) {
                atf.Is_Active__c = false;
                toDeactivate.add(atf);
            }
        }
        if (!toDeactivate.isEmpty()) {
            Database.update(toDeactivate, AccessLevel.SYSTEM_MODE);
        }
        return toDeactivate.size();
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
}
