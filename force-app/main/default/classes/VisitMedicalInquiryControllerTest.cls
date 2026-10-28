@IsTest(SeeAllData=false)
private class VisitMedicalInquiryControllerTest {
    @TestSetup
    static void setup() {
        Account account = new Account(Name = 'MI Test Account');
        insert account;

        Account attendeeAccount = new Account(Name = 'MI Attendee');
        insert attendeeAccount;

        Product2 product = new Product2(Name = 'MI Test Product', IsActive = true);
        insert product;

        Visit__c visit = new Visit__c(
            Account__c = account.Id,
            Assigned_To__c = UserInfo.getUserId(),
            Status__c = 'Draft',
            Visit_Type__c = 'Planned (Automatically)',
            Start_Date__c = System.now(),
            End_Date__c = System.now().addHours(1)
        );
        insert visit;

        insert new Visit_Attendee__c(
            Visit__c = visit.Id,
            Account__c = attendeeAccount.Id
        );

        Id queueId = ensureServiceTeamQueue();
        ensureQueueMembership(queueId);
        ensureMedicalTeamQueue();
    }

    private static void ensureQueueMembership(Id queueId) {
        if (queueId == null) {
            return;
        }

        List<GroupMember> existingMembers = [
            SELECT Id
            FROM GroupMember
            WHERE GroupId = :queueId
                AND UserOrGroupId = :UserInfo.getUserId()
            LIMIT 1
        ];
        if (!existingMembers.isEmpty()) {
            return;
        }

        insert new GroupMember(
            GroupId = queueId,
            UserOrGroupId = UserInfo.getUserId()
        );
    }

    private static void grantMedicalInquiryAccess() {
        List<PermissionSet> permissionSets = [
            SELECT Id
            FROM PermissionSet
            WHERE Name = 'Medical_Inquiry_Module'
            LIMIT 1
        ];
        if (permissionSets.isEmpty()) {
            return;
        }

        List<PermissionSetAssignment> existingAssignments = [
            SELECT Id
            FROM PermissionSetAssignment
            WHERE AssigneeId = :UserInfo.getUserId()
                AND PermissionSetId = :permissionSets[0].Id
            LIMIT 1
        ];
        if (!existingAssignments.isEmpty()) {
            return;
        }

        insert new PermissionSetAssignment(
            AssigneeId = UserInfo.getUserId(),
            PermissionSetId = permissionSets[0].Id
        );
    }

    @IsTest
    static void getMedicalInquiryContext_loadsVisitProductsAndInquirers() {
        grantMedicalInquiryAccess();
        Visit__c visit = [SELECT Id FROM Visit__c LIMIT 1];

        Test.startTest();
        VisitMedicalInquiryController.MedicalInquiryContext context =
            VisitMedicalInquiryController.getMedicalInquiryContext(visit.Id);
        Test.stopTest();

        Assert.areEqual(visit.Id, context.visitId);
        Assert.isFalse(context.isLocked);
        Assert.isFalse(context.questionCategories.isEmpty());
        Assert.areEqual(2, context.inquirerOptions.size());
        Assert.areEqual(3, context.routeOptions.size());
        Assert.areEqual(0, context.inquiryCount);
    }

    @IsTest
    static void getMedicalInquiryContext_returnsExistingInquiries() {
        grantMedicalInquiryAccess();
        Visit__c visit = [SELECT Id, Account__c FROM Visit__c LIMIT 1];
        Product2 product = [SELECT Id FROM Product2 LIMIT 1];
        Id queueId = ensureServiceTeamQueue();
        Id recordTypeId = resolveServiceRequestRecordTypeId();

        Case existingCase = new Case(
            OwnerId = queueId,
            AccountId = visit.Account__c,
            Visit__c = visit.Id,
            Inquirer_Account__c = visit.Account__c,
            Product__c = product.Id,
            Subject = 'Existing Service Request',
            Description = 'Existing question',
            Status = 'Closed',
            Response_Text__c = 'Use standard dosing guidance.',
            Response_Date__c = Date.today()
        );
        if (Schema.SObjectType.Case.fields.getMap().containsKey('Service_Category__c')) {
            existingCase.put('Service_Category__c', 'Efficacy');
        } else {
            existingCase.Question_Category__c = 'Efficacy';
        }
        if (recordTypeId != null) {
            existingCase.put('RecordTypeId', recordTypeId);
        }
        insert existingCase;

        Test.startTest();
        VisitMedicalInquiryController.MedicalInquiryContext context =
            VisitMedicalInquiryController.getMedicalInquiryContext(visit.Id);
        Integer count = VisitMedicalInquiryController.getMedicalInquiryCount(visit.Id);
        Test.stopTest();

        Assert.areEqual(1, context.inquiryCount);
        Assert.areEqual(1, count);
        Assert.areEqual(1, context.existingInquiries.size());
        Assert.areEqual('Use standard dosing guidance.', context.existingInquiries[0].responseText);
    }

    @IsTest
    static void createMedicalInquiry_createsRoutedCase() {
        grantMedicalInquiryAccess();
        Visit__c visit = [SELECT Id, Account__c FROM Visit__c LIMIT 1];
        Product2 product = [SELECT Id FROM Product2 LIMIT 1];
        Id queueId = ensureServiceTeamQueue();

        VisitMedicalInquiryController.CreateInquiryRequest request =
            new VisitMedicalInquiryController.CreateInquiryRequest();
        request.visitId = visit.Id;
        request.inquirerAccountId = visit.Account__c;
        request.productId = product.Id;
        request.questionCategory = 'Safety';
        request.questionText = 'What are the contraindications for elderly patients?';

        Test.startTest();
        VisitMedicalInquiryController.CreateInquiryResult result =
            VisitMedicalInquiryController.createMedicalInquiry(
                request.visitId,
                request.inquirerAccountId,
                request.productId,
                request.questionCategory,
                request.questionText
            );
        Test.stopTest();

        Case createdCase = [
            SELECT
                Id,
                CaseNumber,
                OwnerId,
                RecordTypeId,
                Visit__c,
                AccountId,
                Inquirer_Account__c,
                Product__c,
                Service_Category__c,
                Description,
                Status
            FROM Case
            WHERE Id = :result.caseId
        ];

        Assert.areEqual(result.caseId, createdCase.Id);
        Assert.areEqual(result.caseNumber, createdCase.CaseNumber);
        Assert.areEqual(queueId, createdCase.OwnerId);
        Id recordTypeId = resolveServiceRequestRecordTypeId();
        if (recordTypeId != null) {
            Assert.areEqual(recordTypeId, (Id) createdCase.get('RecordTypeId'));
        }
        Assert.areEqual(visit.Id, createdCase.Visit__c);
        Assert.areEqual(visit.Account__c, createdCase.AccountId);
        Assert.areEqual(visit.Account__c, createdCase.Inquirer_Account__c);
        Assert.areEqual(product.Id, createdCase.Product__c);
        Assert.areEqual('Safety', createdCase.Service_Category__c);
        Assert.areEqual(request.questionText, createdCase.Description);
        Assert.areEqual('New', createdCase.Status);
    }

    @IsTest
    static void createMedicalInquiry_blocksCompletedVisit() {
        grantMedicalInquiryAccess();
        Visit__c visit = [SELECT Id, Account__c, Status__c FROM Visit__c LIMIT 1];
        Product2 product = [SELECT Id FROM Product2 LIMIT 1];
        visit.Status__c = 'Cancelled';
        visit.Cancellation_Reason__c = 'Test cancellation';
        update visit;

        Visit__c lockedVisit = [
            SELECT Status__c
            FROM Visit__c
            WHERE Id = :visit.Id
        ];
        Assert.areEqual('Cancelled', lockedVisit.Status__c);

        VisitMedicalInquiryController.CreateInquiryRequest request =
            new VisitMedicalInquiryController.CreateInquiryRequest();
        request.visitId = visit.Id;
        request.inquirerAccountId = visit.Account__c;
        request.productId = product.Id;
        request.questionCategory = 'Other';
        request.questionText = 'Late question';

        Boolean threw = false;
        Test.startTest();
        try {
            VisitMedicalInquiryController.createMedicalInquiry(
                request.visitId,
                request.inquirerAccountId,
                request.productId,
                request.questionCategory,
                request.questionText
            );
        } catch (Exception ex) {
            threw = true;
        }
        Test.stopTest();

        Assert.isTrue(threw, 'Expected create to fail for cancelled visit.');
    }

    @IsTest
    static void createMedicalInquiry_requiresQuestionText() {
        grantMedicalInquiryAccess();
        Visit__c visit = [SELECT Id, Account__c FROM Visit__c LIMIT 1];
        Product2 product = [SELECT Id FROM Product2 LIMIT 1];

        VisitMedicalInquiryController.CreateInquiryRequest request =
            new VisitMedicalInquiryController.CreateInquiryRequest();
        request.visitId = visit.Id;
        request.inquirerAccountId = visit.Account__c;
        request.productId = product.Id;
        request.questionCategory = 'Other';
        request.questionText = '   ';

        Boolean threw = false;
        Test.startTest();
        try {
            VisitMedicalInquiryController.createMedicalInquiry(
                request.visitId,
                request.inquirerAccountId,
                request.productId,
                request.questionCategory,
                request.questionText
            );
        } catch (AuraHandledException ex) {
            threw = true;
        }
        Test.stopTest();

        Assert.isTrue(threw);
    }

    @IsTest
    static void createMedicalInquiry_routesToMedicalTeam() {
        grantMedicalInquiryAccess();
        Visit__c visit = [SELECT Id, Account__c FROM Visit__c LIMIT 1];
        Product2 product = [SELECT Id FROM Product2 LIMIT 1];
        Id medicalQueueId = ensureMedicalTeamQueue();

        Test.startTest();
        VisitMedicalInquiryController.CreateInquiryResult result =
            VisitMedicalInquiryController.createMedicalInquiry(
                visit.Id,
                visit.Account__c,
                product.Id,
                'Safety',
                'Route this to medical affairs',
                'Medical_Team'
            );
        Test.stopTest();

        Case createdCase = [SELECT OwnerId FROM Case WHERE Id = :result.caseId];
        Assert.areEqual(medicalQueueId, createdCase.OwnerId);
    }

    @IsTest
    static void createMedicalInquiry_routesToManager() {
        grantMedicalInquiryAccess();
        Profile admin = [SELECT Id FROM Profile WHERE Name = 'System Administrator' LIMIT 1];
        String suffix = String.valueOf(Crypto.getRandomInteger());
        User manager = new User(
            Alias = 'srmgr',
            Email = 'srmgr' + suffix + '@example.com',
            EmailEncodingKey = 'UTF-8',
            LastName = 'ServiceRequestManager',
            LanguageLocaleKey = 'en_US',
            LocaleSidKey = 'en_US',
            TimeZoneSidKey = 'Africa/Cairo',
            UserName = 'srmgr' + suffix + '@example.com.test',
            ProfileId = admin.Id
        );
        insert manager;
        update new User(Id = UserInfo.getUserId(), ManagerId = manager.Id);

        Visit__c visit = [SELECT Id, Account__c FROM Visit__c LIMIT 1];
        Product2 product = [SELECT Id FROM Product2 LIMIT 1];
        VisitMedicalInquiryController.CreateInquiryResult result;
        System.runAs(new User(Id = UserInfo.getUserId())) {
            result = VisitMedicalInquiryController.createMedicalInquiry(
                visit.Id,
                visit.Account__c,
                product.Id,
                'General Support',
                'Please review this with my manager',
                'Manager'
            );
        }

        Case createdCase = [SELECT OwnerId FROM Case WHERE Id = :result.caseId];
        Assert.areEqual(manager.Id, createdCase.OwnerId);
    }

    @IsTest
    static void createMedicalInquiry_requiresManagerWhenRoutedToManager() {
        grantMedicalInquiryAccess();
        Visit__c visit = [SELECT Id, Account__c FROM Visit__c LIMIT 1];
        Product2 product = [SELECT Id FROM Product2 LIMIT 1];
        update new User(Id = UserInfo.getUserId(), ManagerId = null);

        Boolean threw = false;
        System.runAs(new User(Id = UserInfo.getUserId())) {
            try {
                VisitMedicalInquiryController.createMedicalInquiry(
                    visit.Id,
                    visit.Account__c,
                    product.Id,
                    'Other',
                    'Needs a manager',
                    'Manager'
                );
            } catch (Exception ex) {
                threw = true;
            }
        }
        Assert.isTrue(threw);
    }

    @IsTest
    static void getMedicalInquiryContext_returnsNullVisit() {
        VisitMedicalInquiryController.MedicalInquiryContext context =
            VisitMedicalInquiryController.getMedicalInquiryContext(null);

        Assert.areEqual(0, context.inquiryCount);
        Assert.isTrue(context.inquirerOptions.isEmpty());
    }

    @IsTest
    static void getMedicalInquiryCount_returnsZeroForNullVisit() {
        Assert.areEqual(0, VisitMedicalInquiryController.getMedicalInquiryCount(null));
    }

    @IsTest
    static void createMedicalInquiry_validationAndCategoryCoverage() {
        grantMedicalInquiryAccess();
        Visit__c visit = [SELECT Id, Account__c FROM Visit__c LIMIT 1];
        Product2 product = [SELECT Id FROM Product2 LIMIT 1];
        ensureServiceTeamQueue();

        Boolean missingInquirer = false;
        try {
            VisitMedicalInquiryController.createMedicalInquiry(
                visit.Id,
                null,
                product.Id,
                'General Support',
                'Details'
            );
        } catch (Exception ex) {
            missingInquirer = true;
        }
        Assert.isTrue(missingInquirer);

        Boolean missingProduct = false;
        try {
            VisitMedicalInquiryController.createMedicalInquiry(
                visit.Id,
                visit.Account__c,
                null,
                'General Support',
                'Details'
            );
        } catch (Exception ex) {
            missingProduct = true;
        }
        Assert.isTrue(missingProduct);

        Boolean missingCategory = false;
        try {
            VisitMedicalInquiryController.createMedicalInquiry(
                visit.Id,
                visit.Account__c,
                product.Id,
                '',
                'Details'
            );
        } catch (Exception ex) {
            missingCategory = true;
        }
        Assert.isTrue(missingCategory);

        Test.startTest();
        VisitMedicalInquiryController.CreateInquiryResult result =
            VisitMedicalInquiryController.createMedicalInquiry(
                visit.Id,
                visit.Account__c,
                product.Id,
                'Product Information',
                'Need product leaflet support'
            );
        Integer count = VisitMedicalInquiryController.getMedicalInquiryCount(visit.Id);
        VisitMedicalInquiryController.MedicalInquiryContext context =
            VisitMedicalInquiryController.getMedicalInquiryContext(visit.Id);
        Test.stopTest();

        Assert.isNotNull(result.caseId);
        Assert.isTrue(count >= 1);
        Assert.isTrue(context.inquiryCount >= 1);
        Assert.isFalse(context.questionCategories.isEmpty());
    }

    private static Id ensureMedicalTeamQueue() {
        List<Group> queues = [
            SELECT Id
            FROM Group
            WHERE Type = 'Queue' AND DeveloperName = 'Medical_Affairs'
            LIMIT 1
        ];
        if (!queues.isEmpty()) {
            return queues[0].Id;
        }

        Group queueGroup = new Group(
            Name = 'Medical Affairs',
            DeveloperName = 'Medical_Affairs',
            Type = 'Queue'
        );
        insert queueGroup;
        insert new QueueSObject(QueueId = queueGroup.Id, SObjectType = 'Case');
        return queueGroup.Id;
    }

    private static Id ensureServiceTeamQueue() {
        List<Group> queues = [
            SELECT Id
            FROM Group
            WHERE Type = 'Queue' AND DeveloperName = 'Service_Team'
            LIMIT 1
        ];
        if (!queues.isEmpty()) {
            return queues[0].Id;
        }

        Group queueGroup = new Group(
            Name = 'Service Team',
            DeveloperName = 'Service_Team',
            Type = 'Queue'
        );
        insert queueGroup;
        insert new QueueSObject(QueueId = queueGroup.Id, SObjectType = 'Case');
        return queueGroup.Id;
    }

    private static Id resolveServiceRequestRecordTypeId() {
        Schema.RecordTypeInfo recordTypeInfo = Schema.SObjectType.Case.getRecordTypeInfosByDeveloperName()
            .get('Service_Request');
        if (recordTypeInfo == null || !recordTypeInfo.isAvailable()) {
            return null;
        }
        return recordTypeInfo.getRecordTypeId();
    }
}