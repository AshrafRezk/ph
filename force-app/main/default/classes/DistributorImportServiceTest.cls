@IsTest
private class DistributorImportServiceTest {
    private class GeoMock implements HttpCalloutMock {
        public HTTPResponse respond(HTTPRequest req) {
            HttpResponse res = new HttpResponse();
            res.setStatusCode(200);
            res.setBody(
                '{"status":"OK","results":[{"formatted_address":"Cairo","geometry":{"location":{"lat":30.0444,"lng":31.2357}}}]}'
            );
            return res;
        }
    }

    @TestSetup
    static void setupData() {
        upsert new Distributor_Geocode_Config__c(
            SetupOwnerId = UserInfo.getOrganizationId(),
            Google_API_Key__c = 'test-key',
            Auto_Confirm_Threshold__c = 85,
            Proximity_Meters__c = 250
        );
        Product2 p = new Product2(Name = 'IMPORT TEST PRODUCT', ProductCode = 'IMP1', External_ID__c = 'IMP1', IsActive = true);
        insert p;
        Account pharmacy = new Account(Name = 'Import Test Pharmacy', BillingCountry = 'Egypt');
        insert pharmacy;
        Database.insert(
            new List<SObject>{
                new Distributor_Product_Alias__c(
                    Distributor_Code__c = 'Egydrug',
                    Distributor_Item_Code__c = 'ITEM1',
                    Distributor_Item_Name__c = 'IMPORT TEST PRODUCT',
                    Product2_Id__c = p.Id,
                    Zeta_Code__c = 'IMP1',
                    Match_Confidence__c = 100,
                    Match_Method__c = 'Seeded',
                    Status__c = 'Confirmed',
                    Unique_Key__c = 'Egydrug|ITEM1'
                ),
                new Distributor_Sellout_Alias__c(
                    Distributor_Code__c = 'Egydrug',
                    Distributor_Client_Code__c = 'CLIENT1',
                    Distributor_Client_Name__c = 'Import Test Pharmacy',
                    Latitude__c = 30.0444,
                    Longitude__c = 31.2357,
                    Geocode_Status__c = 'Geocoded',
                    Pharmacy_Account__c = pharmacy.Id,
                    Match_Confidence__c = 100,
                    Match_Method__c = 'Manual',
                    Status__c = 'Confirmed',
                    Unique_Key__c = 'Egydrug|CLIENT1'
                )
            },
            AccessLevel.SYSTEM_MODE
        );
    }

    private static String rowsJson(List<Integer> quantities) {
        List<Object> rows = new List<Object>();
        for (Integer q : quantities) {
            rows.add(
                new Map<String, Object>{
                    'itemCode' => 'ITEM1',
                    'itemName' => 'IMPORT TEST PRODUCT',
                    'clientCode' => 'CLIENT1',
                    'clientName' => 'Import Test Pharmacy',
                    'quantity' => q
                }
            );
        }
        return JSON.serialize(rows);
    }

    private static List<Map<String, Object>> rowList(List<Integer> quantities) {
        List<Map<String, Object>> out = new List<Map<String, Object>>();
        for (Object o : (List<Object>) JSON.deserializeUntyped(rowsJson(quantities))) {
            out.add((Map<String, Object>) o);
        }
        return out;
    }

    private static Sales_Data_Import_Batch__c newBatch(String status, Integer expected, Integer processed) {
        Sales_Data_Import_Batch__c b = new Sales_Data_Import_Batch__c(
            File_Name__c = 'unit-test.xlsx',
            Distributor_Code__c = 'Egydrug',
            Status__c = status,
            Report_Month__c = Date.newInstance(2026, 6, 1),
            Chunks_Expected__c = expected,
            Chunks_Received__c = expected,
            Chunks_Processed__c = processed,
            Run_Number__c = 1,
            Rows_Inserted__c = 0,
            Rows_Updated__c = 0,
            Rows_Failed__c = 0,
            Upload_Rows_Failed__c = 0
        );
        insert b;
        return b;
    }

    private static String withdrawalKey(Date month) {
        Id pharmacyId = [SELECT Id FROM Account WHERE Name = 'Import Test Pharmacy' LIMIT 1].Id;
        Id productId = [SELECT Id FROM Product2 WHERE External_ID__c = 'IMP1' LIMIT 1].Id;
        return DistributorMatchingUtil.toDataSource('Egydrug') +
            '_' +
            month.year() +
            '-' +
            (month.month() < 10 ? '0' : '') +
            month.month() +
            '_' +
            pharmacyId +
            '_' +
            productId;
    }

    private static Pharmacy_Sales_Withdrawal__c priorWithdrawal(Id batchId, Decimal qty, Decimal run) {
        Id pharmacyId = [SELECT Id FROM Account WHERE Name = 'Import Test Pharmacy' LIMIT 1].Id;
        Id productId = [SELECT Id FROM Product2 WHERE External_ID__c = 'IMP1' LIMIT 1].Id;
        Pharmacy_Sales_Withdrawal__c w = new Pharmacy_Sales_Withdrawal__c(
            Data_Source__c = DistributorMatchingUtil.toDataSource('Egydrug'),
            Report_Month__c = Date.newInstance(2026, 6, 1),
            Pharmacy_Account__c = pharmacyId,
            Product2_Id__c = String.valueOf(productId),
            Quantity_Withdrawn__c = qty,
            Unique_Key__c = withdrawalKey(Date.newInstance(2026, 6, 1)),
            Import_Batch__c = batchId,
            Import_Run__c = run
        );
        insert w;
        return w;
    }

    private static Pharmacy_Sales_Withdrawal__c onlyWithdrawal() {
        List<Pharmacy_Sales_Withdrawal__c> rows = [
            SELECT Quantity_Withdrawn__c, Import_Run__c, Import_Batch__c, Product__c, Product2_Id__c
            FROM Pharmacy_Sales_Withdrawal__c
            WITH SYSTEM_MODE
        ];
        System.assertEquals(1, rows.size(), 'one withdrawal per pharmacy/product/month');
        return rows[0];
    }

    @IsTest
    static void newBatchStartsUploadingAndStagesOneFilePerChunk() {
        DistributorsManagementController.ImportChunkResult first = DistributorsManagementController.ingestNormalizedRows(
            'Egydrug',
            'two-chunks.xlsx',
            '2026-06',
            rowsJson(new List<Integer>{ 2, 3 }),
            null,
            false,
            0,
            2
        );
        System.assertEquals('Uploading', first.status);
        System.assertEquals(false, first.jobEnqueued);
        System.assertEquals(1, first.chunksReceived);

        // retry of the same chunk replaces that chunk only
        DistributorsManagementController.ingestNormalizedRows(
            'Egydrug',
            'two-chunks.xlsx',
            '2026-06',
            rowsJson(new List<Integer>{ 2, 3 }),
            first.batchId,
            false,
            0,
            2
        );
        System.assertEquals(1, DistributorImportService.countChunks(first.batchId));

        DistributorsManagementController.ingestNormalizedRows(
            'Egydrug',
            'two-chunks.xlsx',
            '2026-06',
            rowsJson(new List<Integer>{ 5 }),
            first.batchId,
            false,
            1,
            2
        );
        System.assertEquals(2, DistributorImportService.countChunks(first.batchId));
        System.assertEquals(
            'DistributorImport_' + first.batchId + '_00000',
            [
                SELECT Title
                FROM ContentVersion
                WHERE Title LIKE :('DistributorImport_' + first.batchId + '_%') AND IsLatest = TRUE
                ORDER BY Title
                LIMIT 1
            ]
            .Title
        );
        Sales_Data_Import_Batch__c b = DistributorImportService.loadBatch(first.batchId);
        System.assertEquals('Uploading', b.Status__c);
        System.assertEquals(2, b.Chunks_Received__c);
    }

    @IsTest
    static void chunkedImportCompletesAndSumsAcrossChunks() {
        Test.setMock(HttpCalloutMock.class, new GeoMock());
        DistributorsManagementController.ImportChunkResult c0 = DistributorsManagementController.ingestNormalizedRows(
            'Egydrug',
            'sum.xlsx',
            '2026-06',
            rowsJson(new List<Integer>{ 2, 3 }),
            null,
            false,
            0,
            2
        );
        Test.startTest();
        DistributorsManagementController.ImportChunkResult c1 = DistributorsManagementController.ingestNormalizedRows(
            'Egydrug',
            'sum.xlsx',
            '2026-06',
            rowsJson(new List<Integer>{ 5 }),
            c0.batchId,
            true,
            1,
            2
        );
        System.assertEquals(true, c1.jobEnqueued);
        System.assertEquals('Queued', c1.status);
        Test.stopTest();

        Sales_Data_Import_Batch__c b = DistributorImportService.loadBatch(c0.batchId);
        System.assertEquals('Completed', b.Status__c, '' + b.Error_Log__c);
        System.assertEquals(2, b.Chunks_Processed__c);
        System.assertEquals(2, b.Chunks_Expected__c);
        System.assertNotEquals(null, b.Job_Id__c);
        System.assertEquals(10, onlyWithdrawal().Quantity_Withdrawn__c);
    }

    @IsTest
    static void incompleteUploadMarksBatchFailed() {
        DistributorsManagementController.ImportChunkResult r = DistributorsManagementController.ingestNormalizedRows(
            'Egydrug',
            'incomplete.xlsx',
            '2026-06',
            rowsJson(new List<Integer>{ 1 }),
            null,
            true,
            0,
            3
        );
        System.assertEquals(false, r.jobEnqueued);
        System.assertEquals('Failed', r.status);
        Sales_Data_Import_Batch__c b = DistributorImportService.loadBatch(r.batchId);
        System.assertEquals('Failed', b.Status__c);
        System.assert(b.Error_Log__c.contains('Upload incomplete'));
    }

    @IsTest
    static void finishedBatchNoLongerAcceptsChunks() {
        Sales_Data_Import_Batch__c b = newBatch('Failed', 1, 0);
        try {
            DistributorsManagementController.ingestNormalizedRows(
                'Egydrug',
                'x.xlsx',
                '2026-06',
                rowsJson(new List<Integer>{ 1 }),
                b.Id,
                false,
                0,
                1
            );
            System.assert(false, 'expected an error');
        } catch (AuraHandledException e) {
            System.assert(true);
        }
    }

    @IsTest
    static void badReportMonthIsRejected() {
        try {
            DistributorsManagementController.ingestNormalizedRows(
                'Egydrug',
                'x.xlsx',
                '06/2026',
                rowsJson(new List<Integer>{ 1 }),
                null,
                false,
                0,
                1
            );
            System.assert(false, 'expected an error');
        } catch (AuraHandledException e) {
            System.assert(true);
        }
    }

    @IsTest
    static void browserCanMarkBatchFailed() {
        DistributorsManagementController.ImportChunkResult r = DistributorsManagementController.ingestNormalizedRows(
            'Egydrug',
            'fail.xlsx',
            '2026-06',
            rowsJson(new List<Integer>{ 1 }),
            null,
            false,
            0,
            2
        );
        DistributorsManagementController.BatchActionResult res = DistributorsManagementController.markImportBatchFailed(
            r.batchId,
            'Upload failed in the browser: boom'
        );
        System.assertEquals('Failed', res.status);
        Sales_Data_Import_Batch__c b = DistributorImportService.loadBatch(r.batchId);
        System.assertEquals('Failed', b.Status__c);
        System.assert(b.Error_Log__c.contains('boom'));

        // Completed batches are never flipped back to Failed
        Sales_Data_Import_Batch__c done = newBatch('Completed', 1, 1);
        System.assertEquals('Completed', DistributorImportService.markFailed(done.Id, 'late').Status__c);
    }

    @IsTest
    static void resumeContinuesFromTheWatermarkWithoutDoubleCounting() {
        Sales_Data_Import_Batch__c b = newBatch('Failed', 2, 1);
        DistributorImportService.stageChunk(b.Id, 0, rowList(new List<Integer>{ 4 }));
        DistributorImportService.stageChunk(b.Id, 1, rowList(new List<Integer>{ 5 }));
        // chunk 0 was applied before the failure
        priorWithdrawal(b.Id, 4, 1);

        Test.startTest();
        DistributorsManagementController.BatchActionResult res = DistributorsManagementController.resumeImportBatch(b.Id);
        System.assertEquals('Queued', res.status);
        Test.stopTest();

        Sales_Data_Import_Batch__c after = DistributorImportService.loadBatch(b.Id);
        System.assertEquals('Completed', after.Status__c, '' + after.Error_Log__c);
        System.assertEquals(2, after.Chunks_Processed__c);
        System.assertEquals(1, after.Run_Number__c, 'resume keeps the run');
        System.assertEquals(9, onlyWithdrawal().Quantity_Withdrawn__c);
    }

    @IsTest
    static void tenderRowsAreFlaggedAndKeptApartFromRegularSales() {
        Sales_Data_Import_Batch__c b = newBatch('Failed', 1, 0);
        List<Map<String, Object>> rows = rowList(new List<Integer>{ 4, 6 });
        rows[1].put('isTender', true);
        DistributorImportService.stageChunk(b.Id, 0, rows);

        Test.startTest();
        DistributorsManagementController.resumeImportBatch(b.Id);
        Test.stopTest();

        Map<Boolean, Decimal> qtyByTender = new Map<Boolean, Decimal>();
        for (Pharmacy_Sales_Withdrawal__c w : [
            SELECT Is_Tender__c, Quantity_Withdrawn__c, Unique_Key__c
            FROM Pharmacy_Sales_Withdrawal__c
            WITH SYSTEM_MODE
        ]) {
            qtyByTender.put(w.Is_Tender__c, w.Quantity_Withdrawn__c);
            System.assertEquals(w.Is_Tender__c, w.Unique_Key__c.endsWith('_T'), 'tender lines get their own key');
        }
        System.assertEquals(4, qtyByTender.get(false), 'regular sale is not merged with the tender line');
        System.assertEquals(6, qtyByTender.get(true), 'tender line is flagged');
    }

    @IsTest
    static void requeueRestartsFromChunkZeroAndOverwrites() {
        Sales_Data_Import_Batch__c b = newBatch('Failed', 2, 2);
        DistributorImportService.stageChunk(b.Id, 0, rowList(new List<Integer>{ 4 }));
        DistributorImportService.stageChunk(b.Id, 1, rowList(new List<Integer>{ 6 }));
        priorWithdrawal(b.Id, 10, 1);

        Test.startTest();
        DistributorsManagementController.requeueImportBatch(b.Id);
        Test.stopTest();

        Sales_Data_Import_Batch__c after = DistributorImportService.loadBatch(b.Id);
        System.assertEquals('Completed', after.Status__c, '' + after.Error_Log__c);
        System.assertEquals(2, after.Run_Number__c);
        System.assertEquals(2, after.Chunks_Processed__c);
        Pharmacy_Sales_Withdrawal__c w = onlyWithdrawal();
        System.assertEquals(10, w.Quantity_Withdrawn__c, 'overwritten by the new run, not 20');
        System.assertEquals(2, w.Import_Run__c);
        System.assertEquals(w.Product2_Id__c, String.valueOf(w.Product__c), 'Product lookup is set for reports and the export');
    }

    @IsTest
    static void resumeAndRequeueRejectUnsafeBatches() {
        Sales_Data_Import_Batch__c uploading = newBatch('Uploading', 2, 0);
        Sales_Data_Import_Batch__c completed = newBatch('Completed', 1, 1);
        Sales_Data_Import_Batch__c noFiles = newBatch('Failed', 2, 0);
        Sales_Data_Import_Batch__c missing = newBatch('Failed', 3, 0);
        DistributorImportService.stageChunk(missing.Id, 0, rowList(new List<Integer>{ 1 }));
        for (Id batchId : new List<Id>{ uploading.Id, completed.Id, noFiles.Id, missing.Id }) {
            try {
                DistributorsManagementController.resumeImportBatch(batchId);
                System.assert(false, 'resume should be rejected for ' + batchId);
            } catch (AuraHandledException e) {
                System.assert(true);
            }
            try {
                DistributorsManagementController.requeueImportBatch(batchId);
                System.assert(false, 'requeue should be rejected for ' + batchId);
            } catch (AuraHandledException e) {
                System.assert(true);
            }
        }
    }

    @IsTest
    static void sweeperFailsStaleBatchesAndLeavesFreshOnesAlone() {
        Sales_Data_Import_Batch__c staleUpload = newBatch('Uploading', 2, 0);
        Sales_Data_Import_Batch__c stuckProcessing = newBatch('Processing', 2, 0);
        Sales_Data_Import_Batch__c freshUpload = newBatch('Uploading', 2, 0);
        staleUpload.Last_Activity__c = System.now().addHours(-3);
        stuckProcessing.Last_Activity__c = System.now().addHours(-3);
        freshUpload.Last_Activity__c = System.now();
        update new List<Sales_Data_Import_Batch__c>{ staleUpload, stuckProcessing, freshUpload };

        Test.startTest();
        System.assertEquals(2, DistributorImportService.sweep(30));
        Test.stopTest();

        System.assertEquals('Failed', DistributorImportService.loadBatch(staleUpload.Id).Status__c);
        System.assert(DistributorImportService.loadBatch(staleUpload.Id).Error_Log__c.contains('Upload stalled'));
        System.assertEquals('Failed', DistributorImportService.loadBatch(stuckProcessing.Id).Status__c);
        System.assert(DistributorImportService.loadBatch(stuckProcessing.Id).Error_Log__c.contains('Resume or Re-queue'));
        System.assertEquals('Uploading', DistributorImportService.loadBatch(freshUpload.Id).Status__c);
    }

    @IsTest
    static void sweeperIsScheduledOnceAndRunsFromTheScheduler() {
        // Scheduled jobs are org-wide and visible to tests; production already runs the sweeper.
        for (CronTrigger ct : [SELECT Id FROM CronTrigger WHERE CronJobDetail.Name LIKE 'Distributor import sweeper%']) {
            System.abortJob(ct.Id);
        }
        Test.startTest();
        System.assertEquals(4, DistributorImportSweeper.scheduleEvery15Minutes());
        System.assertEquals(0, DistributorImportSweeper.scheduleEvery15Minutes());
        new DistributorImportSweeper().execute(null);
        Test.stopTest();
    }

    @IsTest
    static void jobOnlyProcessesItsOwnBatchAliases() {
        Test.setMock(HttpCalloutMock.class, new GeoMock());
        Sales_Data_Import_Batch__c mine = newBatch('Queued', 0, 0);
        Sales_Data_Import_Batch__c other = newBatch('Queued', 0, 0);
        Distributor_Sellout_Alias__c a = new Distributor_Sellout_Alias__c(
            Distributor_Code__c = 'Egydrug',
            Distributor_Client_Code__c = 'MINE1',
            Distributor_Client_Name__c = 'Mine Pharmacy',
            Address__c = 'Cairo Street',
            Geocode_Status__c = 'Pending',
            Status__c = 'Unmatched',
            Unique_Key__c = 'Egydrug|MINE1',
            Import_Batch__c = mine.Id
        );
        Distributor_Sellout_Alias__c b = new Distributor_Sellout_Alias__c(
            Distributor_Code__c = 'Egydrug',
            Distributor_Client_Code__c = 'OTHER1',
            Distributor_Client_Name__c = 'Other Pharmacy',
            Address__c = 'Giza Street',
            Geocode_Status__c = 'Pending',
            Status__c = 'Unmatched',
            Unique_Key__c = 'Egydrug|OTHER1',
            Import_Batch__c = other.Id
        );
        Database.insert(new List<SObject>{ a, b }, AccessLevel.SYSTEM_MODE);

        Test.startTest();
        DistributorImportService.startProcessing(mine.Id);
        Test.stopTest();

        System.assertEquals('Geocoded', [SELECT Geocode_Status__c FROM Distributor_Sellout_Alias__c WHERE Id = :a.Id].Geocode_Status__c);
        System.assertEquals('Pending', [SELECT Geocode_Status__c FROM Distributor_Sellout_Alias__c WHERE Id = :b.Id].Geocode_Status__c);
        System.assertNotEquals(null, DistributorImportService.loadBatch(mine.Id).Job_Id__c);
    }

    @IsTest
    static void ingestClaimsExistingUnmatchedAliasForTheNewBatch() {
        Distributor_Sellout_Alias__c old = new Distributor_Sellout_Alias__c(
            Distributor_Code__c = 'Egydrug',
            Distributor_Client_Code__c = 'OLDCLIENT',
            Distributor_Client_Name__c = 'Old Unmatched',
            Geocode_Status__c = 'Pending',
            Status__c = 'Unmatched',
            Unique_Key__c = 'Egydrug|OLDCLIENT'
        );
        Database.insert(old, AccessLevel.SYSTEM_MODE);

        DistributorsManagementController.ImportChunkResult r = DistributorsManagementController.ingestNormalizedRows(
            'Egydrug',
            'claim.xlsx',
            '2026-06',
            JSON.serialize(
                new List<Object>{
                    new Map<String, Object>{
                        'itemCode' => 'ITEM1',
                        'clientCode' => 'OLDCLIENT',
                        'clientName' => 'Old Unmatched',
                        'quantity' => 1
                    }
                }
            ),
            null,
            false,
            0,
            1
        );
        System.assertEquals(r.batchId, [SELECT Import_Batch__c FROM Distributor_Sellout_Alias__c WHERE Id = :old.Id].Import_Batch__c);
        // a confirmed alias already linked to a pharmacy is not claimed
        System.assertEquals(
            null,
            [SELECT Import_Batch__c FROM Distributor_Sellout_Alias__c WHERE Unique_Key__c = 'Egydrug|CLIENT1'].Import_Batch__c
        );
    }

    @IsTest
    static void batchListExposesProgressAndActions() {
        Sales_Data_Import_Batch__c failed = newBatch('Failed', 4, 1);
        Sales_Data_Import_Batch__c uploading = newBatch('Uploading', 4, 0);
        Sales_Data_Import_Batch__c completed = newBatch('Completed', 4, 4);
        Map<Id, DistributorsManagementController.BatchRow> byId = new Map<Id, DistributorsManagementController.BatchRow>();
        for (DistributorsManagementController.BatchRow row : DistributorsManagementController.getImportBatches(50)) {
            byId.put(row.batchId, row);
        }
        System.assertEquals(true, byId.get(failed.Id).canResume);
        System.assertEquals(1, byId.get(failed.Id).chunksProcessed);
        System.assertEquals(4, byId.get(failed.Id).chunksExpected);
        System.assertEquals(false, byId.get(failed.Id).canFail);
        System.assertEquals(false, byId.get(uploading.Id).canResume);
        System.assertEquals(true, byId.get(uploading.Id).canFail);
        System.assertEquals(false, byId.get(completed.Id).canResume);
        System.assertEquals(false, byId.get(completed.Id).canFail);
    }
}
