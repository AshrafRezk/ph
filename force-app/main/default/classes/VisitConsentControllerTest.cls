@IsTest
private class VisitConsentControllerTest {
    @TestSetup
    static void setup() {
        Account account = new Account(Name = 'Consent Test HCP');
        insert account;
        insert new Visit__c(
            Account__c = account.Id,
            Assigned_To__c = UserInfo.getUserId(),
            Status__c = 'Draft',
            Visit_Type__c = 'Planned (Automatically)',
            Start_Date__c = System.now(),
            End_Date__c = System.now().addHours(1)
        );
    }

    @IsTest
    static void getVisitConsentContext_returnsOptions() {
        Visit__c visit = [SELECT Id FROM Visit__c LIMIT 1];
        Test.startTest();
        VisitConsentController.ConsentContext context = VisitConsentController.getVisitConsentContext(visit.Id);
        Test.stopTest();
        System.assertEquals(visit.Id, context.visitId);
        System.assertEquals(false, context.isLocked);
        System.assert(!context.channelOptions.isEmpty(), 'Expected channel options');
        System.assert(!context.consentTypeOptions.isEmpty(), 'Expected consent type options');
    }

    @IsTest
    static void captureVisitConsent_requiresSignatureForGranted() {
        Visit__c visit = [SELECT Id, Account__c FROM Visit__c LIMIT 1];
        VisitConsentController.CaptureRequest request = new VisitConsentController.CaptureRequest();
        request.visitId = visit.Id;
        request.accountId = visit.Account__c;
        request.channel = 'Visit';
        request.consentType = 'Detailing';
        request.status = 'Granted';
        Boolean threw = false;
        Test.startTest();
        try {
            VisitConsentController.captureVisitConsent(request);
        } catch (Exception ex) {
            threw = true;
        }
        Test.stopTest();
        System.assertEquals(true, threw, 'Expected signature requirement');
    }

    @IsTest
    static void captureVisitConsent_insertsGrantedRecord() {
        Visit__c visit = [SELECT Id, Account__c FROM Visit__c LIMIT 1];
        VisitConsentController.CaptureRequest request = new VisitConsentController.CaptureRequest();
        request.visitId = visit.Id;
        request.accountId = visit.Account__c;
        request.channel = 'Samples';
        request.consentType = 'Samples';
        request.status = 'Granted';
        request.signatureData = 'data:image/png;base64,aaa';
        request.notes = 'Signed on device';

        Test.startTest();
        VisitConsentController.CaptureResult result = VisitConsentController.captureVisitConsent(request);
        Test.stopTest();

        System.assertNotEquals(null, result.consentId);
        Visit_Consent__c stored = [
            SELECT Channel__c, Consent_Type__c, Status__c, Signature_Data__c
            FROM Visit_Consent__c
            WHERE Id = :result.consentId
        ];
        System.assertEquals('Samples', stored.Channel__c);
        System.assertEquals('Granted', stored.Status__c);
        System.assert(String.isNotBlank(stored.Signature_Data__c));
    }
}
