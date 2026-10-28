/**
 * Second stage of a distributor import: turns the staged chunks into Pharmacy_Sales_Withdrawal__c.
 *
 * - One staged chunk file at a time, with aliases looked up only for the codes in that chunk (no full-table loads).
 * - Each chunk is applied in a savepoint together with the Chunks_Processed__c watermark, so a failure
 *   can be resumed without double counting.
 * - Rows with the same withdrawal key across chunks are summed when they were written in the current run
 *   (Import_Run__c = Run_Number__c); anything older is overwritten.
 * - Each line takes the 702 / 148 brick of the distributor client's location (SalesLineBrickResolver).
 * - A row whose client has no brick and no CRM pharmacy is kept as a Distributor_Unplaced_Sale__c
 *   (still counted in Rows_Failed__c), so the Bricks Manager can show what was not placed.
 * - Chains itself when the transaction is getting heavy.
 */
public with sharing class DistributorWithdrawalQueueable implements Queueable {
    private final Id batchId;

    @TestVisible
    private static Integer maxChunksPerRun = 25;

    /** Most DML rows one chunk can write: a line per staged row (chunks hold up to 2,000) plus the batch watermark. */
    private static final Integer MAX_CHUNK_DML_ROWS = 2010;

    public DistributorWithdrawalQueueable(Id batchId) {
        this.batchId = batchId;
    }

    public void execute(QueueableContext ctx) {
        Sales_Data_Import_Batch__c batch;
        try {
            batch = DistributorImportService.loadBatch(batchId);
        } catch (Exception e) {
            return;
        }
        if (batch.Status__c == 'Failed' || batch.Status__c == 'Completed') {
            return;
        }
        batch.Status__c = 'Processing';
        try {
            List<Id> files = DistributorImportService.stagingFileIds(batchId);
            Integer total = files.size();
            Integer next = batch.Chunks_Processed__c == null ? 0 : Integer.valueOf(batch.Chunks_Processed__c);
            Integer doneThisRun = 0;
            List<String> notes = new List<String>();
            while (next < total) {
                if (!canTakeAnotherChunk(doneThisRun)) {
                    break;
                }
                Savepoint sp = Database.setSavepoint();
                try {
                    applyChunk(batch, next, files[next], notes);
                } catch (Exception e) {
                    Database.rollback(sp);
                    throw e;
                }
                next++;
                doneThisRun++;
            }
            if (!notes.isEmpty()) {
                batch.Error_Log__c = DistributorImportService.appendLog(batch.Error_Log__c, String.join(notes, '\n'));
            }
            batch.Last_Activity__c = System.now();
            if (next >= total) {
                batch.Status__c = 'Completed';
                Database.update(batch, AccessLevel.SYSTEM_MODE);
            } else {
                Database.update(batch, AccessLevel.SYSTEM_MODE);
                if (!Test.isRunningTest()) {
                    Id jobId = System.enqueueJob(new DistributorWithdrawalQueueable(batchId));
                    DistributorImportService.recordJob(batchId, jobId);
                }
            }
        } catch (Exception e) {
            DistributorImportService.markFailed(
                batchId,
                'Withdrawal processing stopped at chunk ' +
                    (batch.Chunks_Processed__c == null ? 0 : Integer.valueOf(batch.Chunks_Processed__c)) +
                    ': ' +
                    e.getMessage()
            );
        }
    }

    private Boolean canTakeAnotherChunk(Integer doneThisRun) {
        if (doneThisRun >= maxChunksPerRun) {
            return false;
        }
        if (doneThisRun == 0) {
            return true;
        }
        // A chunk can write one line per staged row plus the batch, so keep a full chunk of DML rows in hand:
        // going over the 10,000-row limit cannot be caught and rolls back every chunk of the run.
        return Limits.getCpuTime() < 30000 &&
            Limits.getHeapSize() < (Limits.getLimitHeapSize() / 2) &&
            Limits.getQueries() < (Limits.getLimitQueries() - 20) &&
            Limits.getDmlStatements() < (Limits.getLimitDmlStatements() - 10) &&
            Limits.getDmlRows() + MAX_CHUNK_DML_ROWS <= Limits.getLimitDmlRows();
    }

    /** Applies one chunk and advances the watermark on `batch` (persisted by the caller or here). */
    private void applyChunk(Sales_Data_Import_Batch__c batch, Integer chunkIndex, Id fileId, List<String> notes) {
        String distCode = DistributorMatchingUtil.normalizeDistributorCode(batch.Distributor_Code__c);
        String dataSource = DistributorMatchingUtil.toDataSource(distCode);
        Date reportMonth = batch.Report_Month__c != null ? batch.Report_Month__c : Date.today().toStartOfMonth();
        Decimal run = batch.Run_Number__c == null ? 1 : batch.Run_Number__c;
        List<String> distCodes = DistributorMatchingUtil.distributorCodeVariants(distCode);

        List<Map<String, Object>> rows = DistributorImportService.loadStagingFile(fileId);

        Set<String> productKeys = new Set<String>();
        Set<String> selloutKeys = new Set<String>();
        for (Map<String, Object> row : rows) {
            String itemCode = normalize(row.get('itemCode'));
            String clientCode = normalize(row.get('clientCode'));
            for (String dc : distCodes) {
                productKeys.add(DistributorMatchingUtil.buildProductUniqueKey(dc, itemCode));
                selloutKeys.add(DistributorMatchingUtil.buildSelloutUniqueKey(dc, clientCode));
            }
        }

        Map<String, Distributor_Product_Alias__c> productAliases = new Map<String, Distributor_Product_Alias__c>();
        if (!productKeys.isEmpty()) {
            for (Distributor_Product_Alias__c a : [
                SELECT Id, Unique_Key__c, Product2_Id__c, Status__c, Distributor_Item_Code__c, Match_Confidence__c
                FROM Distributor_Product_Alias__c
                WHERE Unique_Key__c IN :productKeys AND Product2_Id__c != NULL
                WITH SYSTEM_MODE
            ]) {
                productAliases.put(a.Unique_Key__c, a);
                productAliases.put(DistributorMatchingUtil.buildProductUniqueKey(distCode, a.Distributor_Item_Code__c), a);
            }
        }
        Map<String, Distributor_Sellout_Alias__c> selloutAliases = new Map<String, Distributor_Sellout_Alias__c>();
        Set<Id> pharmacyIds = new Set<Id>();
        if (!selloutKeys.isEmpty()) {
            for (Distributor_Sellout_Alias__c a : [
                SELECT
                    Id,
                    Unique_Key__c,
                    Pharmacy_Account__c,
                    Status__c,
                    Distributor_Client_Code__c,
                    Brick_702__c,
                    Brick_148__c
                FROM Distributor_Sellout_Alias__c
                WHERE Unique_Key__c IN :selloutKeys
                WITH SYSTEM_MODE
            ]) {
                selloutAliases.put(a.Unique_Key__c, a);
                selloutAliases.put(
                    DistributorMatchingUtil.buildSelloutUniqueKey(distCode, a.Distributor_Client_Code__c),
                    a
                );
                if (a.Pharmacy_Account__c != null) {
                    pharmacyIds.add(a.Pharmacy_Account__c);
                }
            }
        }

        SalesLineBrickResolver bricks = new SalesLineBrickResolver(pharmacyIds);
        Set<Id> tenderPharmacies = loadTenderPharmacies(pharmacyIds);

        Integer failed = 0;
        Map<Id, Decimal> standardPriceByProduct = loadStandardPrices(rows, distCode, productAliases);
        Map<String, Pharmacy_Sales_Withdrawal__c> withdrawals = new Map<String, Pharmacy_Sales_Withdrawal__c>();
        Map<String, Distributor_Unplaced_Sale__c> unplaced = new Map<String, Distributor_Unplaced_Sale__c>();
        for (Map<String, Object> row : rows) {
            String itemCode = normalize(row.get('itemCode'));
            String clientCode = normalize(row.get('clientCode'));
            Distributor_Product_Alias__c pa = productAliases.get(
                DistributorMatchingUtil.buildProductUniqueKey(distCode, itemCode)
            );
            Distributor_Sellout_Alias__c sa = selloutAliases.get(
                DistributorMatchingUtil.buildSelloutUniqueKey(distCode, clientCode)
            );
            if (pa == null || sa == null || pa.Status__c == 'Rejected' || sa.Status__c == 'Rejected') {
                failed++;
                continue;
            }
            if (pa.Status__c != 'Confirmed' && (pa.Match_Confidence__c == null || pa.Match_Confidence__c < 85)) {
                failed++;
                continue;
            }
            Id productId = pa.Product2_Id__c;
            // A sale needs a place: the client's brick (from its location or address) or a CRM pharmacy.
            // Without one it is kept aside as unplaced instead of becoming a sales line.
            if (sa.Pharmacy_Account__c == null && sa.Brick_702__c == null && sa.Brick_148__c == null) {
                failed++;
                addUnplaced(unplaced, row, sa.Id, productId, dataSource, reportMonth, run, standardPriceByProduct);
                continue;
            }
            Id pharmacyId = sa.Pharmacy_Account__c;
            // Tender: the row came from a tender sheet, or the pharmacy is a tender account.
            Boolean isTender = row.get('isTender') == true || (pharmacyId != null && tenderPharmacies.contains(pharmacyId));
            // One line per pharmacy when the client is linked to one; otherwise per client, so a sale
            // stands without a CRM pharmacy.
            String uk =
                dataSource +
                '_' +
                String.valueOf(reportMonth.year()) +
                '-' +
                (reportMonth.month() < 10 ? '0' : '') +
                String.valueOf(reportMonth.month()) +
                '_' +
                (pharmacyId != null ? String.valueOf(pharmacyId) : 'C' + sa.Id) +
                '_' +
                productId +
                // Tender lines keep their own key, so a tender file never replaces the month's regular sales.
                (isTender ? '_T' : '');

            Decimal qty = toDecimal(row.get('quantity'));
            if (qty == null) {
                qty = 0;
            }
            Decimal unitPrice = toDecimal(row.get('unitPrice'));

            if (withdrawals.containsKey(uk)) {
                Pharmacy_Sales_Withdrawal__c existing = withdrawals.get(uk);
                existing.Quantity_Withdrawn__c =
                    (existing.Quantity_Withdrawn__c == null ? 0 : existing.Quantity_Withdrawn__c) + qty;
            } else {
                Pharmacy_Sales_Withdrawal__c w = new Pharmacy_Sales_Withdrawal__c(
                    Data_Source__c = dataSource,
                    Report_Month__c = reportMonth,
                    Pharmacy_Account__c = pharmacyId,
                    Distributor_Client__c = sa.Id,
                    Product2_Id__c = String.valueOf(productId),
                    Product__c = productId,
                    Quantity_Withdrawn__c = qty,
                    Unique_Key__c = uk,
                    Import_Batch__c = batchId,
                    Import_Run__c = run,
                    Is_Tender__c = isTender
                );
                if (unitPrice == null) {
                    // Revenue__c is Quantity * Unit_Price__c; a file without a price falls back to the standard price.
                    unitPrice = standardPriceByProduct.get(productId);
                }
                if (unitPrice != null) {
                    w.Unit_Price__c = unitPrice;
                }
                SalesLineBrickResolver.applyTo(w, bricks.resolve(sa, pharmacyId));
                withdrawals.put(uk, w);
            }
        }

        Integer inserted = 0;
        Integer updated = 0;
        if (!withdrawals.isEmpty()) {
            // Same key written by an earlier chunk of THIS run: add to it. Anything else is replaced.
            Set<String> keys = withdrawals.keySet();
            for (Pharmacy_Sales_Withdrawal__c prior : [
                SELECT Unique_Key__c, Quantity_Withdrawn__c
                FROM Pharmacy_Sales_Withdrawal__c
                WHERE Unique_Key__c IN :keys AND Import_Batch__c = :batchId AND Import_Run__c = :run
                WITH SYSTEM_MODE
            ]) {
                Pharmacy_Sales_Withdrawal__c w = withdrawals.get(prior.Unique_Key__c);
                if (w != null) {
                    w.Quantity_Withdrawn__c =
                        (w.Quantity_Withdrawn__c == null ? 0 : w.Quantity_Withdrawn__c) +
                        (prior.Quantity_Withdrawn__c == null ? 0 : prior.Quantity_Withdrawn__c);
                }
            }
            Database.UpsertResult[] results = Database.upsert(
                withdrawals.values(),
                Pharmacy_Sales_Withdrawal__c.Unique_Key__c,
                false,
                AccessLevel.SYSTEM_MODE
            );
            for (Database.UpsertResult ur : results) {
                if (ur.isSuccess()) {
                    if (ur.isCreated()) {
                        inserted++;
                    } else {
                        updated++;
                    }
                } else {
                    failed++;
                    if (notes.size() < 25) {
                        notes.add('Chunk ' + chunkIndex + ': ' + ur.getErrors()[0].getMessage());
                    }
                }
            }
        }

        saveUnplaced(unplaced, run, chunkIndex, notes);

        batch.Rows_Inserted__c = (batch.Rows_Inserted__c == null ? 0 : batch.Rows_Inserted__c) + inserted;
        batch.Rows_Updated__c = (batch.Rows_Updated__c == null ? 0 : batch.Rows_Updated__c) + updated;
        batch.Rows_Failed__c = (batch.Rows_Failed__c == null ? 0 : batch.Rows_Failed__c) + failed;
        batch.Chunks_Processed__c = chunkIndex + 1;
        batch.Last_Activity__c = System.now();
        // Persist the watermark inside the same savepoint as the withdrawals it describes.
        Database.update(batch, AccessLevel.SYSTEM_MODE);
    }

    private void addUnplaced(
        Map<String, Distributor_Unplaced_Sale__c> unplaced,
        Map<String, Object> row,
        Id clientId,
        Id productId,
        String dataSource,
        Date reportMonth,
        Decimal run,
        Map<Id, Decimal> standardPriceByProduct
    ) {
        Boolean isTender = row.get('isTender') == true;
        String uk =
            'U_' +
            dataSource +
            '_' +
            String.valueOf(reportMonth.year()) +
            '-' +
            (reportMonth.month() < 10 ? '0' : '') +
            String.valueOf(reportMonth.month()) +
            '_' +
            clientId +
            '_' +
            productId +
            (isTender ? '_T' : '');
        Decimal qty = toDecimal(row.get('quantity'));
        if (qty == null) {
            qty = 0;
        }
        Distributor_Unplaced_Sale__c existing = unplaced.get(uk);
        if (existing != null) {
            existing.Quantity__c += qty;
            return;
        }
        Decimal unitPrice = toDecimal(row.get('unitPrice'));
        if (unitPrice == null) {
            unitPrice = standardPriceByProduct.get(productId);
        }
        unplaced.put(
            uk,
            new Distributor_Unplaced_Sale__c(
                Data_Source__c = dataSource,
                Report_Month__c = reportMonth,
                Distributor_Client__c = clientId,
                Product__c = productId,
                Quantity__c = qty,
                Unit_Price__c = unitPrice,
                Unique_Key__c = uk,
                Import_Batch__c = batchId,
                Import_Run__c = run,
                Is_Tender__c = isTender
            )
        );
    }

    /** Same rules as the sales lines: a key written earlier in this run is added to, anything older is replaced. */
    private void saveUnplaced(Map<String, Distributor_Unplaced_Sale__c> unplaced, Decimal run, Integer chunkIndex, List<String> notes) {
        if (unplaced.isEmpty()) {
            return;
        }
        Set<String> keys = unplaced.keySet();
        for (Distributor_Unplaced_Sale__c prior : [
            SELECT Unique_Key__c, Quantity__c
            FROM Distributor_Unplaced_Sale__c
            WHERE Unique_Key__c IN :keys AND Import_Batch__c = :batchId AND Import_Run__c = :run
            WITH SYSTEM_MODE
        ]) {
            Distributor_Unplaced_Sale__c u = unplaced.get(prior.Unique_Key__c);
            if (u != null && prior.Quantity__c != null) {
                u.Quantity__c += prior.Quantity__c;
            }
        }
        Database.UpsertResult[] results = Database.upsert(
            unplaced.values(),
            Distributor_Unplaced_Sale__c.Unique_Key__c,
            false,
            AccessLevel.SYSTEM_MODE
        );
        for (Database.UpsertResult ur : results) {
            if (!ur.isSuccess() && notes.size() < 25) {
                notes.add('Chunk ' + chunkIndex + ' (unplaced): ' + ur.getErrors()[0].getMessage());
            }
        }
    }

    private static Map<Id, Decimal> loadStandardPrices(
        List<Map<String, Object>> rows,
        String distCode,
        Map<String, Distributor_Product_Alias__c> productAliases
    ) {
        Set<Id> productIds = new Set<Id>();
        for (Map<String, Object> row : rows) {
            Distributor_Product_Alias__c pa = productAliases.get(
                DistributorMatchingUtil.buildProductUniqueKey(distCode, normalize(row.get('itemCode')))
            );
            if (pa != null && pa.Product2_Id__c != null) {
                productIds.add((Id) pa.Product2_Id__c);
            }
        }
        Map<Id, Decimal> prices = new Map<Id, Decimal>();
        if (productIds.isEmpty()) {
            return prices;
        }
        for (PricebookEntry entry : [
            SELECT Product2Id, UnitPrice
            FROM PricebookEntry
            WHERE Pricebook2.IsStandard = TRUE AND Product2Id IN :productIds AND IsActive = TRUE
            WITH SYSTEM_MODE
        ]) {
            prices.put(entry.Product2Id, entry.UnitPrice);
        }
        return prices;
    }

    private static Set<Id> loadTenderPharmacies(Set<Id> pharmacyIds) {
        Set<Id> ids = new Set<Id>();
        if (pharmacyIds.isEmpty()) {
            return ids;
        }
        for (Account a : [SELECT Id FROM Account WHERE Id IN :pharmacyIds AND Is_Tender__c = TRUE WITH SYSTEM_MODE]) {
            ids.add(a.Id);
        }
        return ids;
    }

    private static String normalize(Object o) {
        return o == null ? '' : String.valueOf(o).trim().replaceAll('\\s+', '');
    }

    private static Decimal toDecimal(Object o) {
        if (o == null) {
            return null;
        }
        if (o instanceof Decimal) {
            return (Decimal) o;
        }
        if (o instanceof Integer) {
            return Decimal.valueOf((Integer) o);
        }
        if (o instanceof Long) {
            return Decimal.valueOf((Long) o);
        }
        if (o instanceof Double) {
            return Decimal.valueOf((Double) o);
        }
        try {
            return Decimal.valueOf(String.valueOf(o).trim());
        } catch (Exception e) {
            return null;
        }
    }
}
