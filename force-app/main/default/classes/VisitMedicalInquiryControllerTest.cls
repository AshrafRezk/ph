@IsTest
private class VisitMedicalInquiryControllerTest {

    @TestSetup
    static void setup() {
        Account account = new Account(Name = 'Medical Inquiry Test HCP', BillingLatitude = 30.0, BillingLongitude = 31.0);
        insert account;

        Product2 product = new Product2(Name = 'Test Product Alpha', IsActive = true);
        insert product;

        Visit__c visit = new Visit__c(
            Account__c = account.Id,
            Assigned_To__c = UserInfo.getUserId(),
            Status__c = 'Draft',
            Visit_Type__c = 'Planned (Automatically)',
            Start_Date__c = System.now(),
            End_Date__c = System.now().addHours(1),
            Visit_Objective__c = 'Discuss efficacy data'
        );
        insert visit;
    }

    @IsTest
    static void getMedicalInquiryContext_returnsVisitDataAndOptions() {
        Visit__c visit = [SELECT Id FROM Visit__c LIMIT 1];

        Test.startTest();
        VisitMedicalInquiryController.MedicalInquiryContext context =
            VisitMedicalInquiryController.getMedicalInquiryContext(visit.Id);
        Test.stopTest();

        System.assertEquals(visit.Id, context.visitId);
        System.assertEquals(false, context.isLocked);
        System.assert(!context.inquirerOptions.isEmpty(), 'Expected inquirer options');
        System.assert(!context.questionCategories.isEmpty(), 'Expected question categories');
    }

    @IsTest
    static void createMedicalInquiry_createsCaseAssignedToQueue() {
        Visit__c visit = [SELECT Id, Account__c FROM Visit__c LIMIT 1];
        Product2 product = [SELECT Id FROM Product2 LIMIT 1];
        Id recordTypeId = VisitMedicalInquiryController.resolveMedicalInquiryRecordTypeId();
        Id queueId = VisitMedicalInquiryController.resolveMedicalAffairsQueueId();

        VisitMedicalInquiryController.CreateInquiryRequest request =
            new VisitMedicalInquiryController.CreateInquiryRequest();
        request.visitId = visit.Id;
        request.inquirerAccountId = visit.Account__c;
        request.productId = product.Id;
        request.questionCategory = 'Efficacy';
        request.questionText = 'What is the recommended dosing for elderly patients?';

        Test.startTest();
        VisitMedicalInquiryController.CreateInquiryResult result =
            VisitMedicalInquiryController.createMedicalInquiry(request);
        Test.stopTest();

        System.assertNotEquals(null, result.caseId);
        System.assertNotEquals(null, result.caseNumber);

        Case created = [
            SELECT
                Id,
                RecordTypeId,
                OwnerId,
                AccountId,
                Visit__c,
                Product__c,
                Inquirer_Account__c,
                Question_Category__c,
                Subject,
                Description,
                Origin,
                Status
            FROM Case
            WHERE Id = :result.caseId
            LIMIT 1
        ];
        System.assertEquals(recordTypeId, created.RecordTypeId);
        System.assertEquals(queueId, created.OwnerId);
        System.assertEquals(visit.Id, created.Visit__c);
        System.assertEquals(visit.Account__c, created.AccountId);
        System.assertEquals(visit.Account__c, created.Inquirer_Account__c);
        System.assertEquals(product.Id, created.Product__c);
        System.assertEquals('Efficacy', created.Question_Category__c);
        System.assertEquals('Field Visit', created.Origin);
        System.assertEquals('New', created.Status);
        System.assert(created.Subject.contains('Test Product Alpha'));
        System.assertEquals(request.questionText, created.Description);
    }

    @IsTest
    static void createMedicalInquiry_rejectsLockedVisit() {
        Visit__c visit = [SELECT Id, Account__c FROM Visit__c LIMIT 1];
        Product2 product = [SELECT Id FROM Product2 LIMIT 1];
        visit.Status__c = 'Completed';
        update visit;

        VisitMedicalInquiryController.CreateInquiryRequest request =
            new VisitMedicalInquiryController.CreateInquiryRequest();
        request.visitId = visit.Id;
        request.inquirerAccountId = visit.Account__c;
        request.productId = product.Id;
        request.questionCategory = 'Safety';
        request.questionText = 'Are there known drug interactions?';

        Boolean threw = false;
        Test.startTest();
        try {
            VisitMedicalInquiryController.createMedicalInquiry(request);
        } catch (AuraHandledException e) {
            threw = true;
        }
        Test.stopTest();

        System.assertEquals(true, threw, 'Expected locked visit rejection');
    }

    @IsTest
    static void createMedicalInquiry_requiresQuestionText() {
        Visit__c visit = [SELECT Id, Account__c FROM Visit__c LIMIT 1];
        Product2 product = [SELECT Id FROM Product2 LIMIT 1];

        VisitMedicalInquiryController.CreateInquiryRequest request =
            new VisitMedicalInquiryController.CreateInquiryRequest();
        request.visitId = visit.Id;
        request.inquirerAccountId = visit.Account__c;
        request.productId = product.Id;
        request.questionCategory = 'Other';

        Boolean threw = false;
        Test.startTest();
        try {
            VisitMedicalInquiryController.createMedicalInquiry(request);
        } catch (AuraHandledException e) {
            threw = true;
        }
        Test.stopTest();

        System.assertEquals(true, threw, 'Expected validation for missing question text');
    }

    @IsTest
    static void buildSubject_formatsExpectedLabel() {
        String subject = VisitMedicalInquiryController.buildSubject('CardioMax', 'Dosing');
        System.assertEquals('Medical Inquiry — CardioMax — Dosing', subject);
    }
}
