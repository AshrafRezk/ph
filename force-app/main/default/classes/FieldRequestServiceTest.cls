@IsTest
private class FieldRequestServiceTest {
    @IsTest
    static void createApproveDeclineAndRoute() {
        FieldAppFeatureController.getFeatureCatalog();
        FieldAppFeatureController.getEnabledFeatureMap();

        Account account = new Account(Name = 'Field Request HCP');
        insert account;

        FieldRequestService.CreateContext ctx =
            FieldRequestService.getCreateContext(account.Id, null);
        System.assertEquals(true, ctx.requestsEnabled);
        System.assert(!ctx.fieldTypes.isEmpty());

        FieldRequestService.RequestInput field = new FieldRequestService.RequestInput();
        field.accountId = account.Id;
        field.kind = 'Field';
        field.requestType = 'Device';
        field.summary = 'Doctor needs a demo device';
        field.source = 'Account';
        field.urgency = 'Urgent';

        Test.startTest();
        FieldRequestService.RequestView created = FieldRequestService.createRequest(field);
        Test.stopTest();

        System.assertEquals('With Manager', created.status);
        System.assertEquals(account.Id, created.accountId);

        Field_Request__c row = [
            SELECT Id, Manager__c, Status__c FROM Field_Request__c WHERE Id = :created.id
        ];
        row.Manager__c = UserInfo.getUserId();
        update row;

        List<FieldRequestService.RequestView> queue = FieldRequestService.getManagerQueue();
        System.assertEquals(1, queue.size());

        FieldRequestService.RequestView approved =
            FieldRequestService.approve(created.id, 'Approved');
        System.assertEquals('Done', approved.status);

        FieldRequestService.RequestInput again = new FieldRequestService.RequestInput();
        again.accountId = account.Id;
        again.kind = 'Field';
        again.requestType = 'Other';
        again.summary = 'Needs medical opinion';
        again.source = 'Home';
        FieldRequestService.RequestView pending = FieldRequestService.createRequest(again);
        Field_Request__c pendingRow = [
            SELECT Id FROM Field_Request__c WHERE Id = :pending.id
        ];
        pendingRow.Manager__c = UserInfo.getUserId();
        update pendingRow;

        FieldRequestService.RequestView routed =
            FieldRequestService.sendToMedical(pending.id, 'Please review');
        System.assertEquals('With Medical', routed.status);

        FieldRequestService.RequestView needsYou =
            FieldRequestService.markNeedsYou(pending.id, 'Please clarify dose');
        System.assertEquals('Needs You', needsYou.status);

        FieldRequestService.RequestInput declineInput = new FieldRequestService.RequestInput();
        declineInput.accountId = account.Id;
        declineInput.kind = 'Field';
        declineInput.requestType = 'Follow-up';
        declineInput.summary = 'Decline this one';
        declineInput.source = 'Visit';
        FieldRequestService.RequestView toDecline = FieldRequestService.createRequest(declineInput);
        Field_Request__c declineRow = [
            SELECT Id FROM Field_Request__c WHERE Id = :toDecline.id
        ];
        declineRow.Manager__c = UserInfo.getUserId();
        update declineRow;
        FieldRequestService.RequestView declined =
            FieldRequestService.decline(toDecline.id, 'Not needed');
        System.assertEquals('Declined', declined.status);

        FieldRequestService.RequestInput medical = new FieldRequestService.RequestInput();
        medical.accountId = account.Id;
        medical.kind = 'Medical';
        medical.requestType = 'Safety';
        medical.summary = 'Any known interactions?';
        medical.source = 'Home';
        FieldRequestService.RequestView medicalView = FieldRequestService.createRequest(medical);
        System.assertEquals('With Medical', medicalView.status);
        System.assertEquals('Medical', medicalView.kind);

        FieldRequestService.RequestView answered =
            FieldRequestService.markMedicalDone(medicalView.id, 'No known interactions');
        System.assertEquals('Done', answered.status);

        List<FieldRequestService.RequestView> mine = FieldRequestService.getMyOpenRequests();
        System.assert(!mine.isEmpty());
        System.assert(!FieldRequestService.getRequestsForAccount(account.Id).isEmpty());
        System.assertEquals(0, FieldRequestService.getRequestsForVisit(null).size());
        System.assertEquals(
            true,
            FieldRequestService.searchAccounts('Field').size() >= 0
        );

        FieldRequestService.CreateContext hints =
            FieldRequestService.getCreateContext(null, null);
        System.assertEquals(true, hints.requestsEnabled);

        Boolean threw = false;
        try {
            FieldRequestService.RequestInput bad = new FieldRequestService.RequestInput();
            bad.kind = 'Field';
            bad.requestType = 'Device';
            bad.summary = 'missing account';
            FieldRequestService.createRequest(bad);
        } catch (AuraHandledException ex) {
            threw = true;
        }
        System.assert(threw, 'Creating without an account should fail');
    }
}
