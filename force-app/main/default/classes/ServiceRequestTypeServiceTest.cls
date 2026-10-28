@IsTest
private class ServiceRequestTypeServiceTest {
    @IsTest
    static void readMethodsNeverRunDml() {
        Test.startTest();
        List<ServiceRequestTypeService.TypeRow> empty = ServiceRequestTypeService.listTypes(null);
        List<ServiceRequestTypeService.TypeRow> emptyAll = ServiceRequestTypeService.listAllTypes('Marketing');
        List<ServiceRequestTypeService.TypeRow> emptyUser = ServiceRequestTypeService.typesForCurrentUser('Field');
        System.assertEquals(0, Limits.getDmlStatements(), 'Read methods must not DML on an empty org');
        System.assertEquals(0, empty.size(), 'No seeding on read');
        System.assertEquals(0, emptyAll.size());
        System.assertEquals(0, emptyUser.size());
        Test.stopTest();
    }

    @IsTest
    static void seedDefaultsLoadsMendixServicesOnce() {
        Test.startTest();
        ServiceRequestTypeService.SeedResult first = ServiceRequestTypeService.seedDefaults();
        System.assertEquals(19, first.marketingInserted);
        System.assertEquals(15, first.medicalInserted);
        System.assertEquals(34, first.total);
        ServiceRequestTypeService.SeedResult second = ServiceRequestTypeService.seedDefaults();
        System.assertEquals(0, second.marketingInserted);
        System.assertEquals(0, second.medicalInserted);
        System.assertEquals(34, second.skipped);
        System.assertEquals(34, second.total);
        Test.stopTest();
    }

    @IsTest
    static void listMethodsAfterSeedDoNoDml() {
        ServiceRequestTypeService.seedDefaults();
        Test.startTest();
        List<ServiceRequestTypeService.TypeRow> marketing = ServiceRequestTypeService.listTypes('Marketing');
        List<ServiceRequestTypeService.TypeRow> medical = ServiceRequestTypeService.listAllTypes('Medical');
        List<ServiceRequestTypeService.TypeRow> all = ServiceRequestTypeService.listAllTypes(null);
        List<ServiceRequestTypeService.TypeRow> mine = ServiceRequestTypeService.typesForCurrentUser('Marketing');
        System.assertEquals(0, Limits.getDmlStatements(), 'listTypes/listAllTypes must not DML');
        System.assertEquals(19, marketing.size());
        System.assertEquals(15, medical.size());
        System.assertEquals(34, all.size());
        System.assertEquals(19, mine.size());
        Test.stopTest();
    }

    @IsTest
    static void saveTypeSupportsMarketingCategory() {
        ServiceRequestTypeService.TypeRow row = new ServiceRequestTypeService.TypeRow();
        row.name = 'Custom Marketing Service';
        row.category = 'Marketing';
        row.isActive = true;
        ServiceRequestTypeService.TypeRow saved = ServiceRequestTypeService.saveType(row);
        System.assertNotEquals(null, saved.id);
        System.assertEquals(1, ServiceRequestTypeService.listTypes('Marketing').size());
    }

    @IsTest
    static void marketingRequestUsesConfiguredService() {
        ServiceRequestTypeService.seedDefaults();
        Account account = new Account(Name = 'Marketing Request HCP');
        insert account;

        FieldRequestService.CreateContext ctx = FieldRequestService.getCreateContext(account.Id, null);
        System.assertEquals(19, ctx.marketingTypes.size());
        System.assert(ctx.medicalTypes.size() > 0, 'Medical affairs questions must not be replaced by services');
        for (FieldRequestService.OptionRow opt : ctx.medicalTypes) {
            System.assertNotEquals('Honorarium', opt.value);
        }

        FieldRequestService.RequestInput input = new FieldRequestService.RequestInput();
        input.accountId = account.Id;
        input.kind = 'Marketing';
        input.requestType = 'Honorarium';
        input.summary = 'Speaker fee for symposium';
        input.source = 'Account';
        FieldRequestService.RequestView view = FieldRequestService.createRequest(input);
        System.assertEquals('Marketing', view.kind);
        System.assertEquals('Honorarium', view.requestType);
        System.assertEquals('With Manager', view.status);
        Field_Request__c row = [SELECT Service_Type__c FROM Field_Request__c WHERE Id = :view.id];
        System.assertNotEquals(null, row.Service_Type__c);

        Boolean threw = false;
        try {
            input.requestType = 'Not A Service';
            FieldRequestService.createRequest(input);
        } catch (AuraHandledException ex) {
            threw = true;
        }
        System.assert(threw, 'Unknown marketing service should be rejected');
    }
}
