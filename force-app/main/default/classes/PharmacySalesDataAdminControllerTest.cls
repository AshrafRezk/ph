@IsTest
private class PharmacySalesDataAdminControllerTest {
    @TestSetup
    static void setup() {
        Account pharmacy = new Account(
            Name = 'Admin Test Pharmacy',
            External_ID__c = 'PHARM_TEST_ADMIN'
        );
        Database.insert(pharmacy, AccessLevel.SYSTEM_MODE);

        Brick__c brick = new Brick__c(
            Name = 'Admin Test Brick',
            External_ID__c = 'BRICK_TEST_ADMIN',
            Is_Active__c = true
        );
        Database.insert(brick, AccessLevel.SYSTEM_MODE);

        Database.insert(
            new Brick_Pharmacy__c(
                Brick__c = brick.Id,
                Pharmacy_Account__c = pharmacy.Id,
                Unique_Key__c = brick.Id + ':' + pharmacy.Id,
                Is_Active__c = true
            ),
            AccessLevel.SYSTEM_MODE
        );

        Product2 product = new Product2(
            Name = 'Admin Test Product',
            ProductCode = 'TEST-ADMIN',
            External_ID__c = 'ZETA_TEST_ADMIN',
            Family = 'Empacoza',
            Therapy_Area__c = 'Diabetes',
            IsActive = true
        );
        Database.insert(product, AccessLevel.SYSTEM_MODE);

        Id standardPbId = Test.getStandardPricebookId();
        Database.insert(
            new PricebookEntry(
                Pricebook2Id = standardPbId,
                Product2Id = product.Id,
                UnitPrice = 200,
                IsActive = true
            ),
            AccessLevel.SYSTEM_MODE
        );
    }

    @IsTest
    static void getCsvTemplate_returnsHeader() {
        String template = PharmacySalesDataAdminController.getCsvTemplate();
        System.assert(template.contains('data_source'));
        System.assert(template.contains('pharmacy_external_id'));
    }

    @IsTest
    static void importSalesDataCsv_upsertsRows() {
        String csv = 'data_source,report_month,pharmacy_external_id,product_external_id,quantity_withdrawn,unit_price,external_id\n' +
            'IbnSina,2026-01,PHARM_TEST_ADMIN,ZETA_TEST_ADMIN,25,200,EXT_TEST_1';

        Test.startTest();
        PharmacySalesDataAdminController.ImportResult result =
            PharmacySalesDataAdminController.importSalesDataCsv(csv, 'test.csv');
        Test.stopTest();

        System.assertNotEquals(null, result.batchId);
        System.assertEquals(1, result.rowsInserted + result.rowsUpdated);
        List<Pharmacy_Sales_Withdrawal__c> rows = [
            SELECT Id, Quantity_Withdrawn__c
            FROM Pharmacy_Sales_Withdrawal__c
            WITH SYSTEM_MODE
        ];
        System.assertEquals(1, rows.size());
        System.assertEquals(25, rows[0].Quantity_Withdrawn__c);
    }

    @IsTest
    static void previewSalesDataCsv_validatesRows() {
        String csv = 'data_source,report_month,pharmacy_external_id,product_external_id,quantity_withdrawn\n' +
            'BadSource,2026-01,PHARM_TEST_ADMIN,ZETA_TEST_ADMIN,10';

        PharmacySalesDataAdminController.ImportResult preview =
            PharmacySalesDataAdminController.previewSalesDataCsv(csv);
        System.assertEquals(1, preview.rowsFailed);
    }

    @IsTest
    static void brickMembership_crud() {
        Account pharmacy = [
            SELECT Id
            FROM Account
            WHERE External_ID__c = 'PHARM_TEST_ADMIN'
            WITH SYSTEM_MODE
            LIMIT 1
        ];
        Brick__c brick = [
            SELECT Id
            FROM Brick__c
            WHERE External_ID__c = 'BRICK_TEST_ADMIN'
            WITH SYSTEM_MODE
            LIMIT 1
        ];

        List<PharmacySalesDataAdminController.BrickSummaryRow> summaries =
            PharmacySalesDataAdminController.getBrickSummaries();
        System.assert(!summaries.isEmpty());

        List<PharmacySalesDataAdminController.BrickPharmacyRow> members =
            PharmacySalesDataAdminController.getBrickPharmacies(brick.Id);
        System.assertEquals(1, members.size());

        PharmacySalesDataAdminController.removePharmacyFromBrick(members[0].membershipId);
        Id membershipId = PharmacySalesDataAdminController.addPharmacyToBrick(brick.Id, pharmacy.Id);
        System.assertNotEquals(null, membershipId);
    }

    @IsTest
    static void getWithdrawalRows_and_delete() {
        String csv = 'data_source,report_month,pharmacy_external_id,product_external_id,quantity_withdrawn\n' +
            'Pharmaoverseas,2026-02,PHARM_TEST_ADMIN,ZETA_TEST_ADMIN,15';
        PharmacySalesDataAdminController.importSalesDataCsv(csv, 'viewer.csv');

        List<PharmacySalesDataAdminController.WithdrawalViewerRow> rows =
            PharmacySalesDataAdminController.getWithdrawalRows(null, null, 'All', null, 50);
        System.assertEquals(1, rows.size());

        PharmacySalesDataAdminController.deleteWithdrawalRows(new List<Id>{ rows[0].recordId });
        System.assertEquals(
            0,
            [SELECT COUNT() FROM Pharmacy_Sales_Withdrawal__c WITH SYSTEM_MODE]
        );
    }
}
