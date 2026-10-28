@IsTest
private class DistributorLoadReviewServiceTest {
    @TestSetup
    static void setupData() {
        Product2 p = new Product2(Name = 'REVIEW PRODUCT', ProductCode = 'REV1', External_ID__c = 'REV1', IsActive = true);
        insert p;
        Account pharmacy = new Account(Name = 'Review Pharmacy', BillingCountry = 'Egypt');
        insert pharmacy;
        Database.insert(
            new List<SObject>{
                new Distributor_Product_Alias__c(
                    Distributor_Code__c = 'Egydrug',
                    Distributor_Item_Code__c = 'ITEM1',
                    Distributor_Item_Name__c = 'REVIEW PRODUCT',
                    Product2_Id__c = p.Id,
                    Match_Confidence__c = 100,
                    Status__c = 'Confirmed',
                    Unique_Key__c = DistributorMatchingUtil.buildProductUniqueKey('Egydrug', 'ITEM1')
                ),
                new Distributor_Product_Alias__c(
                    Distributor_Code__c = 'Egydrug',
                    Distributor_Item_Code__c = 'ITEM2',
                    Distributor_Item_Name__c = 'MAYBE PRODUCT',
                    Product2_Id__c = p.Id,
                    Match_Confidence__c = 60,
                    Status__c = 'Suggested',
                    Unique_Key__c = DistributorMatchingUtil.buildProductUniqueKey('Egydrug', 'ITEM2')
                ),
                new Distributor_Sellout_Alias__c(
                    Distributor_Code__c = 'Egydrug',
                    Distributor_Client_Code__c = 'CLIENT1',
                    Distributor_Client_Name__c = 'Review Pharmacy',
                    Pharmacy_Account__c = pharmacy.Id,
                    Status__c = 'Confirmed',
                    Unique_Key__c = DistributorMatchingUtil.buildSelloutUniqueKey('Egydrug', 'CLIENT1')
                )
            },
            AccessLevel.SYSTEM_MODE
        );
    }

    private static Map<String, Object> row(String item, String client, Integer qty) {
        return new Map<String, Object>{
            'itemCode' => item,
            'itemName' => item + ' NAME',
            'clientCode' => client,
            'clientName' => client + ' NAME',
            'quantity' => qty
        };
    }

    @IsTest
    static void openLoadListsMatchedLinesAndUnmatchedReasons() {
        Sales_Data_Import_Batch__c b = new Sales_Data_Import_Batch__c(
            File_Name__c = 'review.xlsx',
            Distributor_Code__c = 'Egydrug',
            Status__c = 'Failed',
            Report_Month__c = Date.newInstance(2026, 9, 1),
            Chunks_Expected__c = 1,
            Chunks_Received__c = 1,
            Chunks_Processed__c = 0,
            Run_Number__c = 1,
            Rows_Inserted__c = 0,
            Rows_Updated__c = 0,
            Rows_Failed__c = 0,
            Upload_Rows_Failed__c = 0
        );
        insert b;
        DistributorImportService.stageChunk(
            b.Id,
            0,
            new List<Map<String, Object>>{
                row('ITEM1', 'CLIENT1', 5),
                row('ITEM2', 'CLIENT1', 3),
                row('ITEM9', 'CLIENT1', 2),
                row('ITEM9', 'CLIENT1', 4),
                row('ITEM1', 'CLIENT9', 7)
            }
        );
        Test.startTest();
        DistributorsManagementController.resumeImportBatch(b.Id);
        Test.stopTest();

        DistributorLoadReviewService.LoadReview r = DistributorLoadReviewService.getLoadReview(b.Id);

        System.assertEquals(1, r.matchedLineCount);
        System.assertEquals('Review Pharmacy', r.matchedLines[0].pharmacy);
        System.assertEquals('REVIEW PRODUCT', r.matchedLines[0].product);
        System.assertEquals(5, r.rowsScanned);
        System.assertEquals(1, r.rowsMatched);
        System.assertEquals(4, r.rowsUnmatched);
        System.assertEquals(false, r.partial);

        Map<String, DistributorLoadReviewService.UnmatchedGroup> byCode = new Map<String, DistributorLoadReviewService.UnmatchedGroup>();
        for (DistributorLoadReviewService.UnmatchedGroup g : r.unmatchedGroups) {
            byCode.put(g.code, g);
        }
        System.assertEquals('Product not mapped', byCode.get('ITEM9').reason);
        System.assertEquals(2, byCode.get('ITEM9').rows, 'same code is grouped');
        System.assertEquals(6, byCode.get('ITEM9').quantity);
        System.assert(byCode.get('ITEM2').reason.startsWith('Product mapping not confirmed'), byCode.get('ITEM2').reason);
        System.assertEquals('Pharmacy / brick not matched', byCode.get('CLIENT9').reason);
        System.assertEquals(r.unmatchedGroups[0].code, 'ITEM9', 'largest group first');
    }

    @IsTest
    static void bigLoadsStopEarlyAndSaySo() {
        Sales_Data_Import_Batch__c b = new Sales_Data_Import_Batch__c(
            File_Name__c = 'big.xlsx',
            Distributor_Code__c = 'Egydrug',
            Status__c = 'Completed',
            Report_Month__c = Date.newInstance(2026, 9, 1)
        );
        insert b;
        DistributorImportService.stageChunk(b.Id, 0, new List<Map<String, Object>>{ row('ITEM9', 'CLIENT1', 1), row('ITEM9', 'CLIENT1', 1) });
        DistributorLoadReviewService.maxScanRows = 1;

        DistributorLoadReviewService.LoadReview r = DistributorLoadReviewService.getLoadReview(b.Id);
        System.assertEquals(true, r.partial);
        System.assertEquals(1, r.rowsScanned);
    }

    @IsTest
    static void needsALoad() {
        Boolean failed = false;
        try {
            DistributorLoadReviewService.getLoadReview(null);
        } catch (AuraHandledException e) {
            failed = true;
        }
        System.assert(failed);
    }

    @IsTest
    static void loadWithoutStagedRowsFallsBackToAliases() {
        Sales_Data_Import_Batch__c b = new Sales_Data_Import_Batch__c(
            File_Name__c = 'gone.xlsx',
            Distributor_Code__c = 'Egydrug',
            Status__c = 'Completed',
            Report_Month__c = Date.newInstance(2026, 9, 1)
        );
        insert b;
        insert new Distributor_Sellout_Alias__c(
            Distributor_Code__c = 'Egydrug',
            Distributor_Client_Code__c = 'LOST1',
            Distributor_Client_Name__c = 'Lost Client',
            Status__c = 'Unmatched',
            Import_Batch__c = b.Id,
            Unique_Key__c = DistributorMatchingUtil.buildSelloutUniqueKey('Egydrug', 'LOST1')
        );

        DistributorLoadReviewService.LoadReview r = DistributorLoadReviewService.getLoadReview(b.Id);
        System.assertEquals(true, r.stagedRowsMissing);
        Set<String> codes = new Set<String>();
        for (DistributorLoadReviewService.UnmatchedGroup g : r.unmatchedGroups) {
            codes.add(g.code);
        }
        System.assert(codes.contains('LOST1'), 'unmatched client of this load');
        System.assert(codes.contains('ITEM2'), 'unconfirmed product of this distributor');
    }
}
