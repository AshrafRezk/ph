@IsTest
private class FieldVisitWorkflowControllerTest {
    @TestSetup
    static void setup() {
        Account account = new Account(Name = 'Workflow Test HCP', Phone = '01000000000');
        insert account;
        Product2 product = new Product2(Name = 'Workflow Product', IsActive = true);
        insert product;
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
    static void submitChangeRequest_insertsRow() {
        Visit__c visit = [SELECT Id FROM Visit__c LIMIT 1];
        FieldVisitWorkflowController.ChangeRequestInput request = new FieldVisitWorkflowController.ChangeRequestInput();
        request.visitId = visit.Id;
        request.changeType = 'Phone';
        request.proposedValue = '01111111111';
        request.reason = 'Updated mobile';

        Test.startTest();
        FieldVisitWorkflowController.ChangeRequestPayload payload =
            FieldVisitWorkflowController.submitChangeRequest(request);
        Test.stopTest();

        System.assertEquals(1, payload.requests.size());
        System.assertEquals('Submitted', payload.requests[0].status);
        System.assertEquals('01111111111', payload.requests[0].proposedValue);
    }

    @IsTest
    static void saveStoreCheck_insertsLines() {
        Visit__c visit = [SELECT Id FROM Visit__c LIMIT 1];
        Product2 product = [SELECT Id FROM Product2 LIMIT 1];
        FieldVisitWorkflowController.StoreCheckLine line = new FieldVisitWorkflowController.StoreCheckLine();
        line.productId = product.Id;
        line.available = true;
        line.facings = 4;

        Test.startTest();
        FieldVisitWorkflowController.StoreCheckPayload payload = FieldVisitWorkflowController.saveStoreCheck(
            visit.Id,
            'On shelf',
            new List<FieldVisitWorkflowController.StoreCheckLine>{ line }
        );
        Test.stopTest();

        System.assertNotEquals(null, payload.storeCheckId);
        System.assertEquals(1, payload.lines.size());
        System.assertEquals(4, payload.lines[0].facings);
    }

    @IsTest
    static void saveStoreCheckPhoto_attachesAndDeletesImage() {
        Visit__c visit = [SELECT Id FROM Visit__c LIMIT 1];
        String tinyPng = 'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==';

        Test.startTest();
        FieldVisitWorkflowController.StoreCheckPayload payload = FieldVisitWorkflowController.saveStoreCheckPhoto(
            visit.Id,
            'shelf.png',
            tinyPng
        );
        System.assertEquals(1, payload.photos.size());
        FieldVisitWorkflowController.StoreCheckPayload afterDelete = FieldVisitWorkflowController.deleteStoreCheckPhoto(
            visit.Id,
            payload.photos[0].contentDocumentId
        );
        Test.stopTest();

        System.assertEquals(0, afterDelete.photos.size());
    }

    @IsTest
    static void saveAndSubmitFieldOrder() {
        Visit__c visit = [SELECT Id FROM Visit__c LIMIT 1];
        Product2 product = [SELECT Id FROM Product2 LIMIT 1];
        FieldVisitWorkflowController.OrderLine line = new FieldVisitWorkflowController.OrderLine();
        line.productId = product.Id;
        line.quantity = 12;

        Test.startTest();
        FieldVisitWorkflowController.saveFieldOrder(
            visit.Id,
            new List<FieldVisitWorkflowController.OrderLine>{ line }
        );
        FieldVisitWorkflowController.OrderPayload submitted = FieldVisitWorkflowController.submitFieldOrder(visit.Id);
        Test.stopTest();

        System.assertEquals('Submitted', submitted.status);
        System.assertEquals(1, submitted.lines.size());
        System.assertEquals(12, submitted.lines[0].quantity);
    }

    @IsTest
    static void saveVisitSurvey_insertsFeedback() {
        Visit__c visit = [SELECT Id FROM Visit__c LIMIT 1];
        FieldVisitWorkflowController.SurveyInput request = new FieldVisitWorkflowController.SurveyInput();
        request.visitId = visit.Id;
        request.productName = 'Workflow Product';
        request.efficacy = 'Positive';
        request.safety = 'Neutral';
        request.notes = 'HCP liked the profile.';

        Test.startTest();
        FieldVisitWorkflowController.SurveyPayload payload = FieldVisitWorkflowController.saveVisitSurvey(request);
        Test.stopTest();

        System.assertEquals(1, payload.rows.size());
        System.assertEquals('Positive', payload.rows[0].efficacy);
    }

    @IsTest
    static void saveRemoteVisit_updatesVisit() {
        Visit__c visit = [SELECT Id FROM Visit__c LIMIT 1];
        Test.startTest();
        FieldVisitWorkflowController.RemoteContext context = FieldVisitWorkflowController.saveRemoteVisit(
            visit.Id,
            true,
            'https://example.com/join'
        );
        Test.stopTest();
        System.assertEquals(true, context.isRemote);
        System.assertEquals('https://example.com/join', context.joinUrl);
    }

    @IsTest
    static void sendFieldEmail_createsTask() {
        Visit__c visit = [SELECT Id FROM Visit__c LIMIT 1];
        Test.startTest();
        FieldVisitWorkflowController.sendFieldEmail(
            visit.Id,
            'hcp@example.com',
            'Visit follow-up',
            'Thank you for the meeting.'
        );
        Test.stopTest();
        System.assertEquals(1, [SELECT COUNT() FROM Task WHERE WhatId = :visit.Id]);
    }
}
