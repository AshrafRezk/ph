@IsTest
private class MendixSyncServiceTest {
    private class MendixHttpMock implements HttpCalloutMock {
        private Integer statusCode;
        MendixHttpMock(Integer statusCode) {
            this.statusCode = statusCode;
        }
        public HttpResponse respond(HttpRequest request) {
            HttpResponse response = new HttpResponse();
            response.setStatusCode(statusCode);
            response.setBody('{"ok":true}');
            return response;
        }
    }

    @IsTest
    static void exportIncludesHeaderWhenNothingHasSynced() {
        String csv = MendixSyncService.exportSyncCsv();
        System.assert(csv.startsWith('Log,Object,External Id,Status,Last Sync'));
    }

    @IsTest
    static void exportQuotesValuesThatContainCommas() {
        Mendix_Sync_Log__c logRow = new Mendix_Sync_Log__c(
            Object_Type__c = 'Time_Off_Request__c',
            External_Id__c = 'MX, "1"',
            Sync_Status__c = 'Success',
            Last_Sync__c = System.now(),
            Payload_Hash__c = 'hash'
        );
        insert as system logRow;
        String csv = MendixSyncService.exportSyncCsv();
        System.assert(csv.contains('"MX, ""1"""'));
        System.assertNotEquals(null, MendixSyncService.getRecentSyncLogs());
        System.assert(MendixSyncService.getIntegrationStatus().contains('Mendix'));
    }

    @IsTest
    static void outboundAndClosureCoverSuccessAndRejection() {
        DateTime startDt = DateTime.newInstance(Date.newInstance(2027, 6, 7), Time.newInstance(9, 0, 0, 0));
        TimeOffRequestController.TimeOffRequestRow created = TimeOffRequestController.createTimeOff(
            'Training',
            'Full_Day',
            null,
            startDt,
            'mendix coverage',
            'Submitted for Approval'
        );

        Test.setMock(HttpCalloutMock.class, new MendixHttpMock(200));
        MendixSyncService.syncTimeOffOutbound(new Set<Id>{ created.id });
        Test.setMock(HttpCalloutMock.class, new MendixHttpMock(500));
        MendixSyncService.syncTimeOffOutbound(new Set<Id>{ created.id });
        MendixSyncService.syncTimeOffOutbound(null);
        MendixSyncService.enqueueTimeOffOutbound(new Set<Id>());

        MendixSyncService.ClosurePayload approved = new MendixSyncService.ClosurePayload();
        approved.salesforceId = created.id;
        approved.mendixExternalId = 'MX-COV-1';
        approved.status = 'approved';
        Time_Off_Request__c updated = MendixSyncService.applyClosure(approved);
        System.assertEquals('Approved', updated.Stage__c);

        MendixSyncService.ClosurePayload rejected = new MendixSyncService.ClosurePayload();
        rejected.mendixExternalId = 'MX-COV-1';
        rejected.status = 'rejected';
        rejected.rejectionReason = 'Dates';
        System.assertEquals('Rejected', MendixSyncService.applyClosure(rejected).Stage__c);

        MendixSyncService.ClosurePayload cancelled = new MendixSyncService.ClosurePayload();
        cancelled.salesforceId = created.id;
        cancelled.status = 'cancelled';
        System.assertNotEquals(null, MendixSyncService.applyClosure(cancelled).Id);

        Integer refused = 0;
        try {
            MendixSyncService.applyClosure(null);
        } catch (Exception ex) {
            refused++;
        }
        try {
            MendixSyncService.ClosurePayload missing = new MendixSyncService.ClosurePayload();
            missing.salesforceId = UserInfo.getUserId();
            missing.status = 'approved';
            MendixSyncService.applyClosure(missing);
        } catch (Exception ex) {
            refused++;
        }
        try {
            MendixSyncService.ClosurePayload bad = new MendixSyncService.ClosurePayload();
            bad.salesforceId = created.id;
            bad.status = 'hold';
            MendixSyncService.applyClosure(bad);
        } catch (Exception ex) {
            refused++;
        }
        System.assertEquals(3, refused);

        Test.startTest();
        MendixSyncService.enqueueTimeOffOutbound(new Set<Id>{ created.id });
        Test.stopTest();
    }
}
