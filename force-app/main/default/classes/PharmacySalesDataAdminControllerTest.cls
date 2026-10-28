@IsTest
private class PharmacySalesDataAdminControllerTest {
    @IsTest
    static void previewRejectsARowMissingQuantity() {
        PharmacySalesDataAdminController.ImportResult preview =
            PharmacySalesDataAdminController.previewSalesDataCsv(
                'Data_Source,Report_Month,Pharmacy_External_Id,Product_External_Id,Quantity,Unit_Price\n' +
                'IbnSina,2026-10,PHARM-001,PROD-001,,25\n'
            );
        System.assertEquals(1, preview.rowsFailed);
        System.assertEquals(false, preview.previewRows[0].isValid);
    }

    @IsTest
    static void importViewerAndDeleteRoundTrip() {
        Account pharmacy = new Account(Name = 'Import Pharmacy', External_ID__c = 'PHARM-IMP-1');
        insert pharmacy;
        Product2 product = new Product2(
            Name = 'Import Product',
            ProductCode = 'IMP-1',
            IsActive = true,
            External_ID__c = 'PROD-IMP-1'
        );
        insert product;

        String csv =
            'Data_Source,Report_Month,Pharmacy_External_Id,Product_External_Id,Quantity,Unit_Price\n' +
            'IbnSina,2026-10,PHARM-IMP-1,PROD-IMP-1,4,10\n';
        PharmacySalesDataAdminController.ImportResult imported =
            PharmacySalesDataAdminController.importSalesDataCsv(csv, 'test.csv');
        System.assertEquals(1, imported.rowsInserted);
        System.assertEquals(0, imported.rowsFailed);

        List<PharmacySalesDataAdminController.WithdrawalRow> rows =
            PharmacySalesDataAdminController.getWithdrawalRows(
                Date.newInstance(2026, 10, 1),
                Date.newInstance(2026, 10, 31),
                null,
                null,
                50
            );
        System.assertEquals(1, rows.size());
        System.assertEquals(4, rows[0].quantity);

        PharmacySalesDataAdminController.deleteWithdrawalRows(new List<Id>{ rows[0].recordId });
        List<PharmacySalesDataAdminController.WithdrawalRow> afterDelete =
            PharmacySalesDataAdminController.getWithdrawalRows(
                Date.newInstance(2026, 10, 1),
                Date.newInstance(2026, 10, 31),
                null,
                null,
                50
            );
        System.assertEquals(0, afterDelete.size());
    }

    @IsTest
    static void digestionExample_loadsTwiceWithoutDuplicates_andBulkShareIsInPercentTerms() {
        Profile adminProfile = [SELECT Id FROM Profile WHERE Name = 'System Administrator' LIMIT 1];
        String uniq = String.valueOf(Crypto.getRandomInteger()).replace('-', '');
        User admin = new User(
            Alias = 'dgex',
            Email = 'dgex' + uniq + '@example.com',
            Username = 'dgex' + uniq + '@example.com.zeta',
            LastName = 'Admin',
            ProfileId = adminProfile.Id,
            TimeZoneSidKey = 'Africa/Cairo',
            LocaleSidKey = 'en_US',
            EmailEncodingKey = 'UTF-8',
            LanguageLocaleKey = 'en_US'
        );
        insert admin;
        SalesDigestionExampleService.DigestionExample first;
        SalesDigestionExampleService.DigestionExample second;
        SalesDigestionExampleService.DigestionExample saved;
        System.runAs(admin) {
            first = PharmacySalesDataAdminController.seedDigestionExample();
            second = PharmacySalesDataAdminController.seedDigestionExample();
            saved = PharmacySalesDataAdminController.getDigestionExample();
        }
        System.assertEquals(true, first.seeded);
        System.assertEquals(first.totalBulk, second.totalBulk);
        System.assertEquals(1, [SELECT COUNT() FROM Item_Ceiling__c WHERE Unique_Key__c = 'DIGEST_EX_CEIL_PRIVATE']);
        System.assertEquals(1, [SELECT COUNT() FROM Sales_Brick_Share__c WHERE Unique_Key__c = 'DIGEST_EX_SHARE']);
        System.assertEquals(1, [SELECT COUNT() FROM Sales_Item_Target__c WHERE Product__r.External_ID__c = 'DIGEST_EX_NEX']);
        // Percent in, percent out: average of actual and target, applied once to the bulk quantity.
        System.assertEquals((first.actualSharePct + first.targetSharePct) / 2, first.averageSharePct);
        System.assertEquals(first.averageSharePct / 100 * first.totalBulk, first.bulkShareQty);
        System.assertEquals(true, saved.seeded);
    }

    @IsTest
    static void templateDemoSeedAndBatchesWork_andUnknownRowsAreReported() {
        System.assert(PharmacySalesDataAdminController.getCsvTemplate().startsWith('Data_Source'));

        PharmacySalesDataAdminController.SeedResult seeded = PharmacySalesDataAdminController.seedDemoData();
        System.assert(seeded.message.contains('Demo pharmacy'));
        PharmacySalesDataAdminController.seedDemoData();
        System.assertEquals(
            1,
            [SELECT COUNT() FROM Pharmacy_Sales_Withdrawal__c WHERE Pharmacy_Account__r.External_ID__c = 'DEMO-PHARM-SOB']
        );

        PharmacySalesDataAdminController.ImportResult imported = PharmacySalesDataAdminController.importSalesDataCsv(
            'Data_Source,Report_Month,Pharmacy_External_Id,Product_External_Id,Quantity,Unit_Price\n' +
            'IbnSina,2026-10,NO-SUCH-PHARM,NO-SUCH-PROD,3,10\n' +
            'NotASource,2026-10,DEMO-PHARM-SOB,DEMO-PROD-SOB,3,10\n',
            'unknown.csv'
        );
        System.assertEquals(0, imported.rowsInserted);
        System.assertEquals(2, imported.rowsFailed);
        System.assertNotEquals(null, imported.errorLog);

        System.assertNotEquals(null, PharmacySalesDataAdminController.getImportBatches(5));
        PharmacySalesDataAdminController.deleteWithdrawalRows(null);
    }
}
