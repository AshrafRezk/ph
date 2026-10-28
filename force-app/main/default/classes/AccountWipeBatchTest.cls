@IsTest
private class AccountWipeBatchTest {
    @IsTest
    static void wipeStartsAtFieldOrders_andDeletesOrders() {
        Id pharmacyRt = AccountMasterImportUtil.recordTypeId('Pharmacy');
        Account pharmacy = new Account(
            Name = 'Wipe Pharmacy',
            RecordTypeId = pharmacyRt,
            External_ID__c = 'WIPE-PH-' + String.valueOf(Math.abs(Crypto.getRandomInteger())).left(8),
            BillingCountry = 'Egypt'
        );
        insert pharmacy;

        insert new Field_Request__c(
            Account__c = pharmacy.Id,
            Kind__c = 'Field',
            Request_Type__c = 'Other',
            Status__c = 'With Manager',
            Summary__c = 'Wipe test request'
        );
        insert new Field_Order__c(
            Account__c = pharmacy.Id,
            Order_Type__c = 'Direct',
            Status__c = 'Draft'
        );

        AccountWipeBatch starter = new AccountWipeBatch();
        System.assertEquals(AccountWipeBatch.PHASE_FIELD_ORDERS, starter.currentPhase);

        Test.startTest();
        Database.executeBatch(new AccountWipeBatch(), 50);
        Test.stopTest();

        System.assertEquals(
            0,
            [SELECT COUNT() FROM Field_Order__c WHERE Account__c = :pharmacy.Id],
            'FIELD_ORDERS phase should delete Field_Order__c'
        );
    }

    @IsTest
    static void fieldRequestsPhase_deletesRequests() {
        Id pharmacyRt = AccountMasterImportUtil.recordTypeId('Pharmacy');
        Account pharmacy = new Account(
            Name = 'Wipe Req Pharmacy',
            RecordTypeId = pharmacyRt,
            External_ID__c = 'WIPE-RQ-' + String.valueOf(Math.abs(Crypto.getRandomInteger())).left(8),
            BillingCountry = 'Egypt'
        );
        insert pharmacy;
        insert new Field_Request__c(
            Account__c = pharmacy.Id,
            Kind__c = 'Field',
            Request_Type__c = 'Other',
            Status__c = 'With Manager',
            Summary__c = 'Wipe request phase'
        );

        Test.startTest();
        Database.executeBatch(new AccountWipeBatch(AccountWipeBatch.PHASE_FIELD_REQUESTS), 50);
        Test.stopTest();

        System.assertEquals(
            0,
            [SELECT COUNT() FROM Field_Request__c WHERE Account__c = :pharmacy.Id],
            'FIELD_REQUESTS phase should delete Field_Request__c'
        );
    }
}
