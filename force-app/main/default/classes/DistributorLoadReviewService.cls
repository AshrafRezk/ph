/**
 * "Open load" in Distributors Management → Batches (QA B6-01): what one distributor load turned into.
 * - Matched: the sales lines the load wrote, with pharmacy (or distributor client), brick and product.
 * - Unmatched: the staged rows that wrote nothing, grouped by reason and code, using the same rules as
 *   DistributorWithdrawalQueueable (product alias confirmed or >= 85%, client linked to a pharmacy or brick).
 * Large loads are read up to MAX_SCAN_ROWS staged rows; the result says when it stopped early.
 */
public with sharing class DistributorLoadReviewService {
    public class MatchedLine {
        @AuraEnabled public Id id;
        @AuraEnabled public String pharmacy;
        @AuraEnabled public String brick;
        @AuraEnabled public String product;
        @AuraEnabled public Decimal quantity;
        @AuraEnabled public Decimal revenue;
        @AuraEnabled public Boolean isTender;
    }

    public class UnmatchedGroup {
        @AuraEnabled public String key;
        @AuraEnabled public String reason;
        @AuraEnabled public String code;
        @AuraEnabled public String name;
        @AuraEnabled public String fix;
        @AuraEnabled public Integer rows;
        @AuraEnabled public Decimal quantity;
    }

    public class LoadReview {
        @AuraEnabled public Id batchId;
        @AuraEnabled public String batchName;
        @AuraEnabled public String fileName;
        @AuraEnabled public String distributorCode;
        @AuraEnabled public String status;
        @AuraEnabled public Date reportMonth;
        @AuraEnabled public Integer matchedLineCount;
        @AuraEnabled public Boolean stagedRowsMissing;
        @AuraEnabled public Integer rowsScanned;
        @AuraEnabled public Integer rowsMatched;
        @AuraEnabled public Integer rowsUnmatched;
        @AuraEnabled public Integer rowsRejectedAtUpload;
        @AuraEnabled public Boolean partial;
        @AuraEnabled public List<MatchedLine> matchedLines;
        @AuraEnabled public List<UnmatchedGroup> unmatchedGroups;
    }

    @TestVisible private static Integer maxScanRows = 30000;
    private static final Integer MATCHED_LIMIT = 200;
    private static final Integer GROUP_LIMIT = 300;
    private static final String NO_PRODUCT = 'Product not mapped';
    private static final String PRODUCT_REJECTED = 'Product mapping rejected';
    private static final String PRODUCT_UNCONFIRMED = 'Product mapping not confirmed';
    private static final String NO_CLIENT = 'Pharmacy / brick not matched';
    private static final String CLIENT_REJECTED = 'Client rejected';

    @AuraEnabled
    public static LoadReview getLoadReview(Id batchId) {
        if (batchId == null) {
            throw new AuraHandledException('Choose a load to open.');
        }
        Sales_Data_Import_Batch__c batch = DistributorImportService.loadBatch(batchId);
        LoadReview review = new LoadReview();
        review.batchId = batch.Id;
        review.batchName = batch.Name;
        review.fileName = batch.File_Name__c;
        review.distributorCode = batch.Distributor_Code__c;
        review.status = batch.Status__c;
        review.reportMonth = batch.Report_Month__c;
        review.rowsRejectedAtUpload = batch.Upload_Rows_Failed__c == null ? 0 : Integer.valueOf(batch.Upload_Rows_Failed__c);
        loadMatched(review, batchId);
        scanStaged(review, batch);
        return review;
    }

    private static void loadMatched(LoadReview review, Id batchId) {
        // COUNT() costs one query row; COUNT(Id)/SUM() would count every line of a 100k-line load.
        review.matchedLineCount = [
            SELECT COUNT()
            FROM Pharmacy_Sales_Withdrawal__c
            WHERE Import_Batch__c = :batchId
            WITH SYSTEM_MODE
        ];
        review.matchedLines = new List<MatchedLine>();
        for (Pharmacy_Sales_Withdrawal__c w : [
            SELECT
                Id,
                Pharmacy_Account__r.Name,
                Distributor_Client__r.Distributor_Client_Name__c,
                Brick__r.Name,
                Product__r.Name,
                Product2_Id__c,
                Quantity_Withdrawn__c,
                Revenue__c,
                Is_Tender__c
            FROM Pharmacy_Sales_Withdrawal__c
            WHERE Import_Batch__c = :batchId
            WITH SYSTEM_MODE
            ORDER BY Quantity_Withdrawn__c DESC NULLS LAST
            LIMIT :MATCHED_LIMIT
        ]) {
            MatchedLine line = new MatchedLine();
            line.id = w.Id;
            line.pharmacy = w.Pharmacy_Account__r != null
                ? w.Pharmacy_Account__r.Name
                : (w.Distributor_Client__r != null ? w.Distributor_Client__r.Distributor_Client_Name__c + ' (no CRM pharmacy)' : '');
            line.brick = w.Brick__r != null ? w.Brick__r.Name : '';
            line.product = w.Product__r != null ? w.Product__r.Name : w.Product2_Id__c;
            line.quantity = w.Quantity_Withdrawn__c;
            line.revenue = w.Revenue__c;
            line.isTender = w.Is_Tender__c;
            review.matchedLines.add(line);
        }
    }

    private static void scanStaged(LoadReview review, Sales_Data_Import_Batch__c batch) {
        String distCode = DistributorMatchingUtil.normalizeDistributorCode(batch.Distributor_Code__c);
        List<String> distCodes = DistributorMatchingUtil.distributorCodeVariants(distCode);
        Map<String, UnmatchedGroup> groups = new Map<String, UnmatchedGroup>();
        review.rowsScanned = 0;
        review.rowsMatched = 0;
        review.rowsUnmatched = 0;
        review.partial = false;

        for (Id fileId : DistributorImportService.stagingFileIds(batch.Id)) {
            if (
                review.rowsScanned >= maxScanRows ||
                Limits.getHeapSize() > Limits.getLimitHeapSize() / 2 ||
                Limits.getQueries() > Limits.getLimitQueries() - 10 ||
                Limits.getCpuTime() > Limits.getLimitCpuTime() / 2
            ) {
                review.partial = true;
                break;
            }
            List<Map<String, Object>> rows = DistributorImportService.loadStagingFile(fileId);
            Set<String> productKeys = new Set<String>();
            Set<String> selloutKeys = new Set<String>();
            for (Map<String, Object> row : rows) {
                for (String dc : distCodes) {
                    productKeys.add(DistributorMatchingUtil.buildProductUniqueKey(dc, normalize(row.get('itemCode'))));
                    selloutKeys.add(DistributorMatchingUtil.buildSelloutUniqueKey(dc, normalize(row.get('clientCode'))));
                }
            }
            Map<String, Distributor_Product_Alias__c> products = new Map<String, Distributor_Product_Alias__c>();
            for (Distributor_Product_Alias__c a : [
                SELECT Unique_Key__c, Distributor_Item_Code__c, Status__c, Match_Confidence__c, Product2_Id__c
                FROM Distributor_Product_Alias__c
                WHERE Unique_Key__c IN :productKeys
                WITH SYSTEM_MODE
            ]) {
                products.put(a.Unique_Key__c, a);
                products.put(DistributorMatchingUtil.buildProductUniqueKey(distCode, a.Distributor_Item_Code__c), a);
            }
            Map<String, Distributor_Sellout_Alias__c> clients = new Map<String, Distributor_Sellout_Alias__c>();
            for (Distributor_Sellout_Alias__c a : [
                SELECT Unique_Key__c, Distributor_Client_Code__c, Status__c, Pharmacy_Account__c, Brick_702__c, Brick_148__c
                FROM Distributor_Sellout_Alias__c
                WHERE Unique_Key__c IN :selloutKeys
                WITH SYSTEM_MODE
            ]) {
                clients.put(a.Unique_Key__c, a);
                clients.put(DistributorMatchingUtil.buildSelloutUniqueKey(distCode, a.Distributor_Client_Code__c), a);
            }

            for (Map<String, Object> row : rows) {
                if (review.rowsScanned >= maxScanRows) {
                    review.partial = true;
                    break;
                }
                review.rowsScanned++;
                String itemCode = normalize(row.get('itemCode'));
                String clientCode = normalize(row.get('clientCode'));
                Distributor_Product_Alias__c pa = products.get(DistributorMatchingUtil.buildProductUniqueKey(distCode, itemCode));
                Distributor_Sellout_Alias__c sa = clients.get(DistributorMatchingUtil.buildSelloutUniqueKey(distCode, clientCode));
                String reason;
                Boolean productProblem = true;
                if (pa == null || pa.Product2_Id__c == null) {
                    reason = NO_PRODUCT;
                } else if (pa.Status__c == 'Rejected') {
                    reason = PRODUCT_REJECTED;
                } else if (pa.Status__c != 'Confirmed' && (pa.Match_Confidence__c == null || pa.Match_Confidence__c < 85)) {
                    reason = PRODUCT_UNCONFIRMED;
                } else if (sa == null || (sa.Pharmacy_Account__c == null && sa.Brick_702__c == null && sa.Brick_148__c == null)) {
                    reason = NO_CLIENT;
                    productProblem = false;
                } else if (sa.Status__c == 'Rejected') {
                    reason = CLIENT_REJECTED;
                    productProblem = false;
                }
                if (reason == null) {
                    review.rowsMatched++;
                    continue;
                }
                review.rowsUnmatched++;
                String code = productProblem ? itemCode : clientCode;
                String key = reason + '|' + code;
                UnmatchedGroup g = groups.get(key);
                if (g == null) {
                    if (groups.size() >= GROUP_LIMIT * 4) {
                        continue;
                    }
                    g = new UnmatchedGroup();
                    g.key = key;
                    g.reason = reason;
                    g.code = code;
                    g.name = asString(row.get(productProblem ? 'itemName' : 'clientName'));
                    g.fix = productProblem
                        ? 'Product mapping tab: confirm or map this item code.'
                        : 'Sellout mapping tab: link the client to a pharmacy, or give it a brick.';
                    if (reason == PRODUCT_UNCONFIRMED && pa.Match_Confidence__c != null) {
                        g.reason += ' (' + pa.Status__c + ', ' + pa.Match_Confidence__c.setScale(0) + '%)';
                    }
                    g.rows = 0;
                    g.quantity = 0;
                    groups.put(key, g);
                }
                g.rows++;
                Decimal qty = toDecimal(row.get('quantity'));
                g.quantity += qty == null ? 0 : qty;
            }
        }
        if (review.rowsScanned == 0) {
            // Staged rows are gone (or never staged): fall back to what the aliases still say.
            review.stagedRowsMissing = true;
            addAliasFallback(groups, batch.Id, distCodes);
        }
        review.unmatchedGroups = topGroups(groups.values());
    }

    private static void addAliasFallback(Map<String, UnmatchedGroup> groups, Id batchId, List<String> distCodes) {
        for (Distributor_Sellout_Alias__c a : [
            SELECT Distributor_Client_Code__c, Distributor_Client_Name__c, Status__c
            FROM Distributor_Sellout_Alias__c
            WHERE Import_Batch__c = :batchId AND Pharmacy_Account__c = NULL AND Brick_702__c = NULL AND Brick_148__c = NULL
            WITH SYSTEM_MODE
            LIMIT :GROUP_LIMIT
        ]) {
            putAliasGroup(groups, a.Status__c == 'Rejected' ? CLIENT_REJECTED : NO_CLIENT, a.Distributor_Client_Code__c,
                a.Distributor_Client_Name__c, false);
        }
        for (Distributor_Product_Alias__c a : [
            SELECT Distributor_Item_Code__c, Distributor_Item_Name__c, Status__c, Match_Confidence__c, Product2_Id__c
            FROM Distributor_Product_Alias__c
            WHERE Distributor_Code__c IN :distCodes
                AND (Product2_Id__c = NULL OR Status__c = 'Rejected' OR (Status__c != 'Confirmed' AND (Match_Confidence__c = NULL OR Match_Confidence__c < 85)))
            WITH SYSTEM_MODE
            LIMIT :GROUP_LIMIT
        ]) {
            String reason = a.Product2_Id__c == null ? NO_PRODUCT : (a.Status__c == 'Rejected' ? PRODUCT_REJECTED : PRODUCT_UNCONFIRMED);
            putAliasGroup(groups, reason, a.Distributor_Item_Code__c, a.Distributor_Item_Name__c, true);
        }
    }

    private static void putAliasGroup(Map<String, UnmatchedGroup> groups, String reason, String code, String name, Boolean product) {
        UnmatchedGroup g = new UnmatchedGroup();
        g.reason = reason;
        g.code = code;
        g.name = name;
        g.key = reason + '|' + code;
        g.fix = product
            ? 'Product mapping tab: confirm or map this item code.'
            : 'Sellout mapping tab: link the client to a pharmacy, or give it a brick.';
        g.rows = null;
        g.quantity = null;
        groups.put(g.key, g);
    }

    private static List<UnmatchedGroup> topGroups(List<UnmatchedGroup> all) {
        List<UnmatchedGroup> sorted = new List<UnmatchedGroup>();
        for (UnmatchedGroup g : all) {
            Integer i = 0;
            while (i < sorted.size() && nz(sorted[i].rows) >= nz(g.rows)) {
                i++;
            }
            if (i < GROUP_LIMIT) {
                if (i == sorted.size()) {
                    sorted.add(g);
                } else {
                    sorted.add(i, g);
                }
                if (sorted.size() > GROUP_LIMIT) {
                    sorted.remove(GROUP_LIMIT);
                }
            }
        }
        return sorted;
    }

    private static Integer nz(Integer i) {
        return i == null ? 0 : i;
    }

    private static String normalize(Object o) {
        return DistributorMatchingUtil.normalizeCode(asString(o));
    }

    private static String asString(Object o) {
        return o == null ? null : String.valueOf(o);
    }

    private static Decimal toDecimal(Object o) {
        if (o == null) {
            return null;
        }
        if (o instanceof Decimal) {
            return (Decimal) o;
        }
        try {
            return Decimal.valueOf(String.valueOf(o));
        } catch (Exception e) {
            return null;
        }
    }
}
