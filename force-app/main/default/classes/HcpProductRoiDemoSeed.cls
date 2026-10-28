/**
 * Seeds product ratings, engagement spend, and rating snapshots so Account Product ROI
 * is populated for every aligned account (HCPs and pharmacies) across multiple products.
 */
public without sharing class HcpProductRoiDemoSeed {
    public class SeedResult {
        public Integer atfCreated = 0;
        public Integer atpfCreated = 0;
        public Integer atpfUpdated = 0;
        public Integer spendRows = 0;
        public Integer snapshotRows = 0;
        public Id jobId;
        public String message;
    }

    private static final Integer MAX_PRODUCTS = 6;
    private static final Integer MAX_NEW_ATF = 2000;
    private static final String FALLBACK_TERRITORY = 'TERRPHARMROI000001';
    private static final List<String> CLASSIFICATION_PATH = new List<String>{
        'C3', 'C2', 'C1', 'B3', 'B2', 'B1', 'A3', 'A2', 'A1', 'A1', 'A1', 'A1'
    };
    private static final List<String> SPEND_TYPES = new List<String>{
        'Speaker Meeting', 'Samples', 'Brochures'
    };

    public static SeedResult seedDemoData() {
        if (Test.isRunningTest()) {
            SeedResult result = new SeedResult();
            List<Product2> products = loadDetailProducts();
            if (products.isEmpty()) {
                result.message = 'No active products found to seed Account Product ROI.';
                return result;
            }
            result.atfCreated = ensureAtfForTargetAccounts();
            return seedSync(products, result);
        }
        return seedTrainingTerritories();
    }

    /**
     * Seeds APM ratings, spend, and snapshots for every account aligned to
     * Training BU / Line / DM / position territories.
     */
    @AuraEnabled
    public static SeedResult seedTrainingTerritories() {
        SeedResult result = new SeedResult();
        List<Product2> products = loadDetailProducts();
        if (products.isEmpty()) {
            result.message = 'No active products found to seed Account Product ROI.';
            return result;
        }

        Set<String> trainingIds = resolveTrainingTerritoryIds();
        if (trainingIds.isEmpty()) {
            result.message = 'No training territories found. Check Territory2 External_ID / DeveloperName for TRAINING.';
            return result;
        }

        result.atfCreated = ensureAtfForTrainingTerritories(trainingIds);

        if (Test.isRunningTest()) {
            List<Account_Territory_Fields__c> atfRows = [
                SELECT Account__c, Territory2_Id__c
                FROM Account_Territory_Fields__c
                WHERE Is_Active__c = TRUE
                    AND Account__c != NULL
                    AND Territory2_Id__c IN :trainingIds
                WITH SYSTEM_MODE
            ];
            processAtfScope(atfRows, result);
            result.message = 'Training APM seed: territories=' + trainingIds.size()
                + ', atfCreated=' + result.atfCreated
                + ', atpfCreated=' + result.atpfCreated
                + ', atpfUpdated=' + result.atpfUpdated
                + ', spendRows=' + result.spendRows
                + ', snapshotRows=' + result.snapshotRows;
            return result;
        }

        result.jobId = HcpProductRoiSeedBatch.runForTerritories(trainingIds);
        result.message = 'Queued training APM seed job ' + String.valueOf(result.jobId)
            + ' for ' + trainingIds.size() + ' territories / ' + products.size() + ' products'
            + ' (atfCreated=' + result.atfCreated + ').';
        return result;
    }

    @TestVisible static Set<String> overrideTrainingTerritoryIds;

    public static Set<String> resolveTrainingTerritoryIds() {
        if (Test.isRunningTest() && overrideTrainingTerritoryIds != null) {
            return overrideTrainingTerritoryIds;
        }
        Set<Id> ids = new Set<Id>();
        try {
            for (Territory2 territory : [
                SELECT Id
                FROM Territory2
                WHERE External_ID__c LIKE '%TRAINING%'
                    OR DeveloperName LIKE '%TRAINING%'
                    OR Name LIKE '%Training%'
                WITH SYSTEM_MODE
            ]) {
                ids.add(territory.Id);
            }
        } catch (Exception e) {
            for (Territory2 territory : [
                SELECT Id
                FROM Territory2
                WHERE DeveloperName LIKE '%TRAINING%'
                    OR Name LIKE '%Training%'
                WITH SYSTEM_MODE
            ]) {
                ids.add(territory.Id);
            }
        }

        for (Integer depth = 0; depth < 4 && !ids.isEmpty(); depth++) {
            Integer before = ids.size();
            for (Territory2 child : [
                SELECT Id
                FROM Territory2
                WHERE ParentTerritory2Id IN :ids
                WITH SYSTEM_MODE
            ]) {
                ids.add(child.Id);
            }
            if (ids.size() == before) {
                break;
            }
        }

        Set<String> texts = new Set<String>();
        for (Id territoryId : ids) {
            String fullId = String.valueOf(territoryId);
            texts.add(fullId);
            if (fullId.length() >= 15) {
                texts.add(fullId.substring(0, 15));
            }
        }
        return texts;
    }

    private static Integer ensureAtfForTrainingTerritories(Set<String> trainingIds) {
        if (trainingIds == null || trainingIds.isEmpty()) {
            return 0;
        }
        Set<Id> territoryIds = new Set<Id>();
        for (String text : trainingIds) {
            if (String.isBlank(text) || text.length() < 15) {
                continue;
            }
            try {
                territoryIds.add(Id.valueOf(text));
            } catch (Exception e) {
                // ignore non-id tokens
            }
        }

        Map<String, Id> accountToTerritory = new Map<String, Id>();
        if (!Test.isRunningTest() && !territoryIds.isEmpty()) {
            try {
                for (ObjectTerritory2Association ota : [
                    SELECT ObjectId, Territory2Id
                    FROM ObjectTerritory2Association
                    WHERE Territory2Id IN :territoryIds
                    WITH SYSTEM_MODE
                ]) {
                    String objectId = String.valueOf(ota.ObjectId);
                    if (objectId != null && objectId.startsWith('001')) {
                        accountToTerritory.put(objectId, ota.Territory2Id);
                    }
                }
            } catch (Exception e) {
                // Territory management association may be unavailable in some orgs.
            }
        }

        for (Account_Territory_Fields__c atf : [
            SELECT Account__c, Territory2_Id__c
            FROM Account_Territory_Fields__c
            WHERE Territory2_Id__c IN :trainingIds
                AND Account__c != NULL
            WITH SYSTEM_MODE
        ]) {
            try {
                accountToTerritory.put(String.valueOf(atf.Account__c), Id.valueOf(atf.Territory2_Id__c));
            } catch (Exception e) {
                // skip malformed territory keys
            }
        }

        if (accountToTerritory.isEmpty()) {
            return 0;
        }

        Set<Id> accountIds = new Set<Id>();
        for (String accountId : accountToTerritory.keySet()) {
            accountIds.add(Id.valueOf(accountId));
        }

        Set<String> existing = new Set<String>();
        for (Account_Territory_Fields__c atf : [
            SELECT Account__c, Territory2_Id__c
            FROM Account_Territory_Fields__c
            WHERE Account__c IN :accountIds
                AND Territory2_Id__c IN :trainingIds
            WITH SYSTEM_MODE
        ]) {
            existing.add(String.valueOf(atf.Account__c) + ':' + atf.Territory2_Id__c);
        }

        List<Account_Territory_Fields__c> toInsert = new List<Account_Territory_Fields__c>();
        for (String accountId : accountToTerritory.keySet()) {
            Id territoryId = accountToTerritory.get(accountId);
            if (territoryId == null) {
                continue;
            }
            String territoryKey = String.valueOf(territoryId);
            String key15 = territoryKey.length() >= 15 ? territoryKey.substring(0, 15) : territoryKey;
            String key = accountId + ':' + territoryKey;
            if (existing.contains(key) || existing.contains(accountId + ':' + key15)) {
                continue;
            }
            toInsert.add(new Account_Territory_Fields__c(
                Account__c = accountId,
                Territory2_Id__c = territoryKey,
                Potential__c = 'B',
                Penetration__c = '2',
                Is_Active__c = true
            ));
            existing.add(key);
        }
        return insertCount(toInsert);
    }

    public static SeedResult seedSync(List<Product2> products, SeedResult result) {
        if (result == null) {
            result = new SeedResult();
        }
        if (products == null || products.isEmpty()) {
            products = loadDetailProducts();
        }
        List<Account_Territory_Fields__c> atfRows = [
            SELECT Account__c, Territory2_Id__c
            FROM Account_Territory_Fields__c
            WHERE Is_Active__c = TRUE
                AND Account__c != NULL
                AND Territory2_Id__c != NULL
            WITH SYSTEM_MODE
        ];
        result.atpfCreated += ensureAtpf(atfRows, products);
        List<Account_Territory_Product_Fields__c> atpfRows = loadAtpfForProducts(products);
        result.atpfUpdated += enrichAtpf(atpfRows);
        result.spendRows += seedSpendForAtpf(atpfRows, products);
        result.snapshotRows += seedRatingSnapshots(atpfRows);
        result.message = 'HCP ROI demo: atfCreated=' + result.atfCreated
            + ', atpfCreated=' + result.atpfCreated
            + ', atpfUpdated=' + result.atpfUpdated
            + ', spendRows=' + result.spendRows
            + ', snapshotRows=' + result.snapshotRows;
        return result;
    }

    public static void processAtfScope(
        List<Account_Territory_Fields__c> atfRows,
        SeedResult result
    ) {
        List<Product2> products = loadDetailProducts();
        if (products.isEmpty() || atfRows == null || atfRows.isEmpty()) {
            return;
        }
        result.atpfCreated += ensureAtpf(atfRows, products);
        Set<Id> accountIds = new Set<Id>();
        for (Account_Territory_Fields__c atf : atfRows) {
            if (atf.Account__c != null) {
                accountIds.add(atf.Account__c);
            }
        }
        List<Account_Territory_Product_Fields__c> atpfRows = loadAtpfForAccounts(accountIds, products);
        result.atpfUpdated += enrichAtpf(atpfRows);
        result.spendRows += seedSpendForAtpf(atpfRows, products);
        result.snapshotRows += seedRatingSnapshots(atpfRows);
    }

    public static List<Product2> loadDetailProducts() {
        List<Product2> selected = new List<Product2>();
        Set<String> families = new Set<String>();
        for (Product2 product : [
            SELECT Id, Name, Family, External_ID__c, Product_Type__c
            FROM Product2
            WHERE IsActive = TRUE
                AND Product_Type__c = 'Detail'
            WITH SYSTEM_MODE
            ORDER BY Family, External_ID__c, Name
            LIMIT 80
        ]) {
            String familyKey = String.isBlank(product.Family) ? '_' : product.Family;
            if (!families.contains(familyKey) || selected.size() < 3) {
                selected.add(product);
                families.add(familyKey);
            } else if (selected.size() < MAX_PRODUCTS) {
                selected.add(product);
                families.add(familyKey);
            }
            if (selected.size() >= MAX_PRODUCTS) {
                break;
            }
        }
        if (!selected.isEmpty()) {
            return selected;
        }
        return [
            SELECT Id, Name, Family, External_ID__c, Product_Type__c
            FROM Product2
            WHERE IsActive = TRUE
            WITH SYSTEM_MODE
            ORDER BY Family, Name
            LIMIT :MAX_PRODUCTS
        ];
    }

    private static Integer ensureAtfForTargetAccounts() {
        String territoryId = resolveDefaultTerritoryId();
        Integer cap = Test.isRunningTest() ? 20 : MAX_NEW_ATF;
        List<Account> targets = [
            SELECT Id
            FROM Account
            WHERE IsPersonAccount = TRUE
                OR RecordType.DeveloperName = 'Pharmacy'
                OR External_ID__c LIKE 'PHARM_%'
                OR Name LIKE '%Pharmacy%'
            WITH SYSTEM_MODE
            LIMIT :cap
        ];
        if (targets.isEmpty()) {
            return 0;
        }

        Set<Id> targetIds = new Map<Id, Account>(targets).keySet();
        Set<Id> existing = new Set<Id>();
        for (Account_Territory_Fields__c atf : [
            SELECT Account__c
            FROM Account_Territory_Fields__c
            WHERE Account__c IN :targetIds
                AND Is_Active__c = TRUE
            WITH SYSTEM_MODE
        ]) {
            existing.add(atf.Account__c);
        }

        List<Account_Territory_Fields__c> toInsert = new List<Account_Territory_Fields__c>();
        for (Account account : targets) {
            if (existing.contains(account.Id)) {
                continue;
            }
            toInsert.add(new Account_Territory_Fields__c(
                Account__c = account.Id,
                Territory2_Id__c = territoryId,
                Potential__c = 'B',
                Penetration__c = '2',
                Is_Active__c = true
            ));
            existing.add(account.Id);
        }
        return insertCount(toInsert);
    }

    private static String resolveDefaultTerritoryId() {
        for (Account_Territory_Fields__c row : [
            SELECT Territory2_Id__c
            FROM Account_Territory_Fields__c
            WHERE Territory2_Id__c != NULL
            WITH SYSTEM_MODE
            LIMIT 1
        ]) {
            return row.Territory2_Id__c;
        }
        return FALLBACK_TERRITORY;
    }

    private static Integer ensureAtpf(
        List<Account_Territory_Fields__c> atfRows,
        List<Product2> products
    ) {
        if (atfRows == null || atfRows.isEmpty() || products == null || products.isEmpty()) {
            return 0;
        }
        Set<Id> accountIds = new Set<Id>();
        for (Account_Territory_Fields__c atf : atfRows) {
            if (atf.Account__c != null) {
                accountIds.add(atf.Account__c);
            }
        }
        Set<String> existingKeys = new Set<String>();
        for (Account_Territory_Product_Fields__c existing : [
            SELECT Unique_Key__c, Account__c, Territory2_Id__c, Product2_Id__c
            FROM Account_Territory_Product_Fields__c
            WHERE Account__c IN :accountIds
            WITH SYSTEM_MODE
        ]) {
            if (String.isNotBlank(existing.Unique_Key__c)) {
                existingKeys.add(existing.Unique_Key__c);
            }
            existingKeys.add(
                String.valueOf(existing.Account__c) + ':' + existing.Territory2_Id__c
                    + ':' + existing.Product2_Id__c
            );
        }

        List<Account_Territory_Product_Fields__c> toInsert = new List<Account_Territory_Product_Fields__c>();
        Integer index = 0;
        for (Account_Territory_Fields__c atf : atfRows) {
            if (atf.Account__c == null || String.isBlank(atf.Territory2_Id__c)) {
                continue;
            }
            for (Product2 product : products) {
                String key = String.valueOf(atf.Account__c) + ':' + atf.Territory2_Id__c
                    + ':' + String.valueOf(product.Id);
                if (existingKeys.contains(key)) {
                    continue;
                }
                Integer band = Math.mod(index + Math.abs(String.valueOf(atf.Account__c).hashCode()), 12);
                toInsert.add(new Account_Territory_Product_Fields__c(
                    Account__c = atf.Account__c,
                    Territory2_Id__c = atf.Territory2_Id__c,
                    Product2_Id__c = String.valueOf(product.Id),
                    Rx_Per_Week__c = Decimal.valueOf(Math.mod(band + 5, 20) + 4),
                    Penetration__c = Decimal.valueOf(Math.mod(band + 3, 40) + 18) * 52,
                    Potential__c = Decimal.valueOf(Math.mod(band + 5, 40) + 28) * 52,
                    Adoption__c = Math.mod(band, 3) == 0 ? 'H' : (Math.mod(band, 3) == 1 ? 'M' : 'L'),
                    Loyalty__c = Math.mod(band, 2) == 0 ? 'H' : 'M',
                    Product_Matrix_Rating__c = Math.mod(band, 3) == 0 ? 'A2' : (Math.mod(band, 3) == 1 ? 'B1' : 'C1'),
                    Target_Visit_Frequency__c = Math.mod(band, 2) == 0 ? 'Monthly' : 'Bi-Weekly',
                    Unique_Key__c = key.length() <= 60 ? key : key.substring(0, 60),
                    Is_Active__c = true
                ));
                existingKeys.add(key);
                index++;
            }
        }
        return insertCount(toInsert);
    }

    private static List<Account_Territory_Product_Fields__c> loadAtpfForProducts(List<Product2> products) {
        Set<String> productIds = productIdTexts(products);
        if (productIds.isEmpty()) {
            return new List<Account_Territory_Product_Fields__c>();
        }
        return [
            SELECT Id, Account__c, Product2_Id__c, Rx_Per_Week__c, Penetration__c, Potential__c
            FROM Account_Territory_Product_Fields__c
            WHERE Product2_Id__c IN :productIds
                AND Is_Active__c = TRUE
                AND Account__c != NULL
            WITH SYSTEM_MODE
            ORDER BY Account__c, Product2_Id__c
        ];
    }

    private static List<Account_Territory_Product_Fields__c> loadAtpfForAccounts(
        Set<Id> accountIds,
        List<Product2> products
    ) {
        Set<String> productIds = productIdTexts(products);
        if (accountIds == null || accountIds.isEmpty() || productIds.isEmpty()) {
            return new List<Account_Territory_Product_Fields__c>();
        }
        return [
            SELECT Id, Account__c, Product2_Id__c, Rx_Per_Week__c, Penetration__c, Potential__c
            FROM Account_Territory_Product_Fields__c
            WHERE Account__c IN :accountIds
                AND Product2_Id__c IN :productIds
                AND Is_Active__c = TRUE
            WITH SYSTEM_MODE
            ORDER BY Account__c, Product2_Id__c
        ];
    }

    private static Set<String> productIdTexts(List<Product2> products) {
        Set<String> productIds = new Set<String>();
        if (products == null) {
            return productIds;
        }
        for (Product2 product : products) {
            productIds.add(String.valueOf(product.Id));
        }
        return productIds;
    }

    private static Integer enrichAtpf(List<Account_Territory_Product_Fields__c> atpfRows) {
        if (atpfRows == null || atpfRows.isEmpty()) {
            return 0;
        }
        Map<Id, Decimal> prices = loadPrices(atpfRows);
        List<Account_Territory_Product_Fields__c> updates = new List<Account_Territory_Product_Fields__c>();
        Integer index = 0;
        for (Account_Territory_Product_Fields__c row : atpfRows) {
            Id productId = resolveProductId(row.Product2_Id__c);
            Decimal unitPrice = (productId != null && prices.containsKey(productId))
                ? prices.get(productId)
                : 50;
            if (unitPrice == null || unitPrice <= 0) {
                unitPrice = 50;
            }
            Integer salt = Math.mod(Math.abs(String.valueOf(row.Account__c).hashCode() + index), 10);
            Decimal targetWritten = 80000 + (salt * 18000);
            Decimal targetPotential = (targetWritten * (1.18 + (salt * 0.03))).setScale(0, RoundingMode.HALF_UP);
            Decimal penetration = (targetWritten / unitPrice).setScale(0, RoundingMode.HALF_UP);
            Decimal potential = (targetPotential / unitPrice).setScale(0, RoundingMode.HALF_UP);
            if (penetration < 1) {
                penetration = 1;
            }
            if (potential <= penetration) {
                potential = penetration + Math.max(1, (penetration * 0.2).setScale(0, RoundingMode.HALF_UP));
            }
            Decimal rxPerWeek = (penetration / 52).setScale(0, RoundingMode.HALF_UP);
            if (rxPerWeek < 1) {
                rxPerWeek = 1;
            }
            row.Penetration__c = penetration;
            row.Potential__c = potential;
            row.Rx_Per_Week__c = rxPerWeek;
            updates.add(row);
            index++;
        }
        return updateCount(updates);
    }

    private static Map<Id, Decimal> loadPrices(List<Account_Territory_Product_Fields__c> atpfRows) {
        Set<Id> productIds = new Set<Id>();
        for (Account_Territory_Product_Fields__c row : atpfRows) {
            Id productId = resolveProductId(row.Product2_Id__c);
            if (productId != null) {
                productIds.add(productId);
            }
        }
        Map<Id, Decimal> prices = new Map<Id, Decimal>();
        if (productIds.isEmpty()) {
            return prices;
        }
        for (PricebookEntry entry : [
            SELECT Product2Id, UnitPrice
            FROM PricebookEntry
            WHERE Pricebook2.IsStandard = TRUE
                AND Product2Id IN :productIds
                AND IsActive = TRUE
            WITH SYSTEM_MODE
        ]) {
            prices.put(entry.Product2Id, entry.UnitPrice);
        }
        return prices;
    }

    private static Integer seedSpendForAtpf(
        List<Account_Territory_Product_Fields__c> atpfRows,
        List<Product2> products
    ) {
        Map<Id, Id> productByAccount = new Map<Id, Id>();
        for (Account_Territory_Product_Fields__c row : atpfRows) {
            if (!productByAccount.containsKey(row.Account__c)) {
                Id productId = resolveProductId(row.Product2_Id__c);
                if (productId != null) {
                    productByAccount.put(row.Account__c, productId);
                }
            }
        }
        if (productByAccount.isEmpty() && products != null && !products.isEmpty()) {
            return 0;
        }

        String year = String.valueOf(Date.today().year());
        List<HCP_Engagement_Spend__c> rows = new List<HCP_Engagement_Spend__c>();
        List<Decimal> amounts = new List<Decimal>{ 250, 100, 50 };
        Integer accountIndex = 0;
        for (Id accountId : productByAccount.keySet()) {
            Id productId = productByAccount.get(accountId);
            Integer salt = Math.mod(Math.abs(String.valueOf(accountId).hashCode()), 5);
            for (Integer i = 0; i < SPEND_TYPES.size(); i++) {
                rows.add(new HCP_Engagement_Spend__c(
                    Account__c = accountId,
                    Product__c = productId,
                    Spend_Type__c = SPEND_TYPES[i],
                    Amount__c = amounts[i] + (salt * 15),
                    Spend_Date__c = Date.today().toStartOfMonth().addMonths(-(i + 1)),
                    Fiscal_Year__c = year,
                    External_ID__c = 'HES_' + accountId + '_' + SPEND_TYPES[i].replace(' ', '') + '_' + year
                ));
            }
            accountIndex++;
            if (Test.isRunningTest() && accountIndex >= 5) {
                break;
            }
        }
        return upsertCount(rows, HCP_Engagement_Spend__c.External_ID__c);
    }

    private static Integer seedRatingSnapshots(List<Account_Territory_Product_Fields__c> atpfRows) {
        Integer monthCount = Test.isRunningTest() ? 3 : 12;
        Date startMonth = Date.today().toStartOfMonth().addMonths(-(monthCount - 1));
        List<HCP_Product_Rating_Snapshot__c> snapshots = new List<HCP_Product_Rating_Snapshot__c>();
        Set<String> seen = new Set<String>();
        Integer pairCount = 0;
        for (Account_Territory_Product_Fields__c row : atpfRows) {
            String accountProductKey = String.valueOf(row.Account__c) + ':' + row.Product2_Id__c;
            if (seen.contains(accountProductKey)) {
                continue;
            }
            seen.add(accountProductKey);
            pairCount++;
            if (Test.isRunningTest() && pairCount > 6) {
                break;
            }

            Id productId = resolveProductId(row.Product2_Id__c);
            Decimal endPenetration = row.Penetration__c != null ? row.Penetration__c : 1000;
            Decimal endPotential = row.Potential__c != null ? row.Potential__c : (endPenetration * 1.25);
            Integer pathOffset = Math.mod(Math.abs(String.valueOf(row.Account__c).hashCode()), 4);

            for (Integer m = 0; m < monthCount; m++) {
                Date month = startMonth.addMonths(m);
                Decimal progress = monthCount <= 1 ? 1 : (Decimal.valueOf(m) / Decimal.valueOf(monthCount - 1));
                Decimal penetration = (endPenetration * (0.55 + (0.45 * progress))).setScale(0, RoundingMode.HALF_UP);
                Integer pathIndex = Math.min(m + pathOffset, CLASSIFICATION_PATH.size() - 1);
                String classification = CLASSIFICATION_PATH[pathIndex];
                snapshots.add(new HCP_Product_Rating_Snapshot__c(
                    Account__c = row.Account__c,
                    Product__c = productId,
                    Snapshot_Month__c = month,
                    Classification__c = classification,
                    Classification_Score__c = classificationScore(classification),
                    Penetration__c = penetration,
                    Potential__c = endPotential,
                    External_ID__c = 'HPRS_' + row.Account__c + '_' + row.Product2_Id__c + '_'
                        + String.valueOf(month.year()) + '-' + String.valueOf(month.month()).leftPad(2, '0')
                ));
            }
        }
        return upsertCount(snapshots, HCP_Product_Rating_Snapshot__c.External_ID__c);
    }

    private static Decimal classificationScore(String classification) {
        if (String.isBlank(classification) || classification.length() < 2) {
            return 1;
        }
        String letter = classification.substring(0, 1).toUpperCase();
        String digit = classification.substring(1, 2);
        Decimal base = letter == 'A' ? 7 : (letter == 'B' ? 4 : 1);
        Decimal step = 0;
        try {
            step = Decimal.valueOf(digit);
        } catch (Exception e) {
            step = 1;
        }
        return base + (3 - Math.min(3, step));
    }

    private static Id resolveProductId(String productIdText) {
        if (String.isBlank(productIdText) || productIdText.length() < 15) {
            return null;
        }
        try {
            return Id.valueOf(productIdText);
        } catch (Exception e) {
            return null;
        }
    }

    private static Integer insertCount(List<SObject> rows) {
        if (rows == null || rows.isEmpty()) {
            return 0;
        }
        Integer ok = 0;
        Integer offset = 0;
        while (offset < rows.size()) {
            Integer endExclusive = Math.min(offset + 200, rows.size());
            List<SObject> chunk = new List<SObject>();
            for (Integer i = offset; i < endExclusive; i++) {
                chunk.add(rows[i]);
            }
            Database.SaveResult[] saves = Database.insert(chunk, false, AccessLevel.SYSTEM_MODE);
            for (Database.SaveResult sr : saves) {
                if (sr.isSuccess()) {
                    ok++;
                }
            }
            offset = endExclusive;
        }
        return ok;
    }

    private static Integer updateCount(List<SObject> rows) {
        if (rows == null || rows.isEmpty()) {
            return 0;
        }
        Integer ok = 0;
        Integer offset = 0;
        while (offset < rows.size()) {
            Integer endExclusive = Math.min(offset + 200, rows.size());
            List<SObject> chunk = new List<SObject>();
            for (Integer i = offset; i < endExclusive; i++) {
                chunk.add(rows[i]);
            }
            Database.SaveResult[] saves = Database.update(chunk, false, AccessLevel.SYSTEM_MODE);
            for (Database.SaveResult sr : saves) {
                if (sr.isSuccess()) {
                    ok++;
                }
            }
            offset = endExclusive;
        }
        return ok;
    }

    private static Integer upsertCount(List<SObject> rows, Schema.SObjectField externalIdField) {
        if (rows == null || rows.isEmpty()) {
            return 0;
        }
        Integer ok = 0;
        Integer offset = 0;
        while (offset < rows.size()) {
            Integer endExclusive = Math.min(offset + 200, rows.size());
            List<SObject> chunk = new List<SObject>();
            for (Integer i = offset; i < endExclusive; i++) {
                chunk.add(rows[i]);
            }
            Database.UpsertResult[] upserts = Database.upsert(
                chunk,
                externalIdField,
                false,
                AccessLevel.SYSTEM_MODE
            );
            for (Database.UpsertResult ur : upserts) {
                if (ur.isSuccess()) {
                    ok++;
                }
            }
            offset = endExclusive;
        }
        return ok;
    }
}