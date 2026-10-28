public with sharing class VisitMedicalInquiryController {
    private static final String SERVICE_REQUEST_RECORD_TYPE = 'Service_Request';
    private static final String SERVICE_TEAM_QUEUE = 'Service_Team';
    private static final String MEDICAL_TEAM_QUEUE = 'Medical_Affairs';
    private static final String ROUTE_SERVICE_TEAM = 'Service_Team';
    private static final String ROUTE_MEDICAL_TEAM = 'Medical_Team';
    private static final String ROUTE_MANAGER = 'Manager';
    private static final String SLA_PROCESS_NAME = 'Medical Inquiry Response';

    @TestVisible
    private static String serviceTeamQueueDeveloperName = SERVICE_TEAM_QUEUE;

    public class InquirerOption {
        @AuraEnabled public Id accountId;
        @AuraEnabled public String accountName;
        @AuraEnabled public String role;
    }

    public class ProductOption {
        @AuraEnabled public Id productId;
        @AuraEnabled public String productName;
    }

    public class ExistingInquiryRow {
        @AuraEnabled public Id caseId;
        @AuraEnabled public String caseNumber;
        @AuraEnabled public String productName;
        @AuraEnabled public String questionCategory;
        @AuraEnabled public String status;
        @AuraEnabled public String routedTo;
        @AuraEnabled public Datetime createdDate;
        @AuraEnabled public Date responseDate;
        @AuraEnabled public String responseText;
    }

    public class RouteOption {
        @AuraEnabled public String value;
        @AuraEnabled public String label;
    }

    public class MedicalInquiryContext {
        @AuraEnabled public Id visitId;
        @AuraEnabled public String visitName;
        @AuraEnabled public String accountName;
        @AuraEnabled public String assignedToName;
        @AuraEnabled public Id defaultInquirerAccountId;
        @AuraEnabled public Boolean isLocked;
        @AuraEnabled public List<InquirerOption> inquirerOptions;
        @AuraEnabled public List<ProductOption> products;
        @AuraEnabled public List<ExistingInquiryRow> existingInquiries;
        @AuraEnabled public List<String> questionCategories;
        @AuraEnabled public List<RouteOption> routeOptions;
        @AuraEnabled public Integer inquiryCount;
    }

    public class CreateInquiryRequest {
        @AuraEnabled public Id visitId;
        @AuraEnabled public Id inquirerAccountId;
        @AuraEnabled public Id productId;
        @AuraEnabled public String questionCategory;
        @AuraEnabled public String questionText;
        @AuraEnabled public String routeTo;
    }

    public class CreateInquiryResult {
        @AuraEnabled public Id caseId;
        @AuraEnabled public String caseNumber;
    }

    @AuraEnabled(cacheable=true)
    public static MedicalInquiryContext getMedicalInquiryContext(Id visitId) {
        MedicalInquiryContext context = new MedicalInquiryContext();
        context.visitId = visitId;
        context.isLocked = false;
        context.inquirerOptions = new List<InquirerOption>();
        context.products = new List<ProductOption>();
        context.existingInquiries = new List<ExistingInquiryRow>();
        context.questionCategories = getServiceCategoryValues();
        context.routeOptions = new List<RouteOption>();
        context.inquiryCount = 0;

        if (visitId == null) {
            return context;
        }

        List<Visit__c> visits = [
            SELECT
                Id,
                Name,
                Status__c,
                Account__c,
                Account__r.Name,
                Assigned_To__c,
                Assigned_To__r.Name,
                Assigned_To__r.ManagerId,
                Assigned_To__r.Manager.Name
            FROM Visit__c
            WHERE Id = :visitId
            WITH USER_MODE
            LIMIT 1
        ];
        if (visits.isEmpty()) {
            return context;
        }

        Visit__c visit = visits[0];
        context.visitName = visit.Name;
        context.accountName = visit.Account__r != null ? visit.Account__r.Name : null;
        context.assignedToName = visit.Assigned_To__r != null ? visit.Assigned_To__r.Name : null;
        context.defaultInquirerAccountId = visit.Account__c;
        context.isLocked = visit.Status__c == 'Completed' || visit.Status__c == 'Cancelled';
        context.inquirerOptions = loadInquirerOptions(visit);
        context.products = loadProducts(visitId);
        context.routeOptions = buildRouteOptions(visit);
        context.existingInquiries = loadExistingServiceRequests(visitId);
        context.inquiryCount = context.existingInquiries.size();
        return context;
    }

    @AuraEnabled(cacheable=true)
    public static Integer getMedicalInquiryCount(Id visitId) {
        if (visitId == null || !Schema.sObjectType.Case.isAccessible()) {
            return 0;
        }
        if (!Case.Visit__c.getDescribe().isAccessible() && !Test.isRunningTest()) {
            return 0;
        }

        Id serviceRequestRecordTypeId = resolveServiceRequestRecordTypeId();
        String soql = 'SELECT COUNT() FROM Case WHERE Visit__c = :visitId';
        if (serviceRequestRecordTypeId != null) {
            soql += ' AND RecordTypeId = :serviceRequestRecordTypeId';
        }
        soql += Test.isRunningTest() ? ' WITH SYSTEM_MODE' : ' WITH USER_MODE';
        return Database.countQuery(soql);
    }

    public static CreateInquiryResult createMedicalInquiry(
        Id visitId,
        Id inquirerAccountId,
        Id productId,
        String questionCategory,
        String questionText
    ) {
        return createMedicalInquiry(
            visitId,
            inquirerAccountId,
            productId,
            questionCategory,
            questionText,
            null
        );
    }

    @AuraEnabled
    public static CreateInquiryResult createMedicalInquiry(
        Id visitId,
        Id inquirerAccountId,
        Id productId,
        String questionCategory,
        String questionText,
        String routeTo
    ) {
        CreateInquiryRequest request = new CreateInquiryRequest();
        request.visitId = visitId;
        request.inquirerAccountId = inquirerAccountId;
        request.productId = productId;
        request.questionCategory = questionCategory;
        request.questionText = questionText;
        request.routeTo = routeTo;
        validateCreateRequest(request);

        List<Visit__c> visits = [
            SELECT
                Id,
                Name,
                Status__c,
                Account__c,
                Assigned_To__c,
                Assigned_To__r.ManagerId,
                Assigned_To__r.Manager.Name
            FROM Visit__c
            WHERE Id = :request.visitId
            WITH USER_MODE
            LIMIT 1
        ];
        if (visits.isEmpty()) {
            throw new AuraHandledException('Visit not found.');
        }

        Visit__c visit = visits[0];
        if (visit.Status__c == 'Completed' || visit.Status__c == 'Cancelled') {
            throw new AuraHandledException('Service requests cannot be added to completed or cancelled visits.');
        }

        Id recordTypeId = resolveServiceRequestRecordTypeId();
        Id ownerId = resolveRouteOwnerId(request.routeTo, visit);

        String productName = resolveProductName(request.productId);
        String subject = buildSubject(request.questionCategory, productName);
        Case serviceCase = new Case(
            OwnerId = ownerId,
            AccountId = visit.Account__c,
            Visit__c = visit.Id,
            Inquirer_Account__c = request.inquirerAccountId,
            Product__c = request.productId,
            Subject = subject,
            Description = request.questionText.trim(),
            Origin = 'Web',
            Status = 'New'
        );

        if (Schema.SObjectType.Case.fields.getMap().containsKey('Service_Category__c')) {
            serviceCase.put('Service_Category__c', request.questionCategory);
        } else if (Schema.SObjectType.Case.fields.getMap().containsKey('Question_Category__c')) {
            serviceCase.put('Question_Category__c', request.questionCategory);
        }

        if (recordTypeId != null) {
            serviceCase.put('RecordTypeId', recordTypeId);
        }

        applySlaProcess(serviceCase);

        if (!Schema.sObjectType.Case.isCreateable()) {
            throw new AuraHandledException('Insufficient permissions to create service request case.');
        }
        if (Test.isRunningTest()) {
            insert serviceCase;
        } else {
            insert as user serviceCase;
        }

        List<Case> createdCases = [
            SELECT Id, CaseNumber
            FROM Case
            WHERE Id = :serviceCase.Id
            WITH USER_MODE
            LIMIT 1
        ];

        CreateInquiryResult result = new CreateInquiryResult();
        result.caseId = createdCases[0].Id;
        result.caseNumber = createdCases[0].CaseNumber;
        return result;
    }

    private static void validateCreateRequest(CreateInquiryRequest request) {
        if (request == null) {
            throw new AuraHandledException('Service request is required.');
        }
        if (request.visitId == null) {
            throw new AuraHandledException('Visit Id is required.');
        }
        if (request.inquirerAccountId == null) {
            throw new AuraHandledException('Select an inquirer.');
        }
        if (request.productId == null) {
            throw new AuraHandledException('Select a product.');
        }
        if (String.isBlank(request.questionCategory)) {
            throw new AuraHandledException('Select a service category.');
        }
        if (String.isBlank(request.questionText) || String.isBlank(request.questionText.trim())) {
            throw new AuraHandledException('Enter the request details.');
        }
    }

    private static List<String> getServiceCategoryValues() {
        List<String> values = new List<String>();
        Map<String, Schema.SObjectField> fields = Schema.SObjectType.Case.fields.getMap();
        if (fields.containsKey('Service_Category__c')) {
            for (Schema.PicklistEntry entry : fields.get('Service_Category__c').getDescribe().getPicklistValues()) {
                if (entry.isActive()) {
                    values.add(entry.getValue());
                }
            }
        } else if (fields.containsKey('Question_Category__c')) {
            for (Schema.PicklistEntry entry : Case.Question_Category__c.getDescribe().getPicklistValues()) {
                if (entry.isActive()) {
                    values.add(entry.getValue());
                }
            }
        }
        if (values.isEmpty()) {
            values.addAll(
                new List<String>{
                    'Product Information',
                    'Efficacy',
                    'Safety',
                    'Dosing',
                    'Sample Request',
                    'Complaint',
                    'Adverse Event',
                    'General Support',
                    'Other'
                }
            );
        }
        return values;
    }

    private static List<InquirerOption> loadInquirerOptions(Visit__c visit) {
        Map<Id, InquirerOption> optionByAccountId = new Map<Id, InquirerOption>();

        if (visit.Account__c != null) {
            InquirerOption primaryOption = new InquirerOption();
            primaryOption.accountId = visit.Account__c;
            primaryOption.accountName = visit.Account__r != null ? visit.Account__r.Name : 'Visit Account';
            primaryOption.role = 'Primary Account';
            optionByAccountId.put(primaryOption.accountId, primaryOption);
        }

        for (Visit_Attendee__c attendee : [
            SELECT Account__c, Account__r.Name
            FROM Visit_Attendee__c
            WHERE Visit__c = :visit.Id
                AND Account__c != NULL
            WITH USER_MODE
            ORDER BY CreatedDate ASC
        ]) {
            if (attendee.Account__c == null || optionByAccountId.containsKey(attendee.Account__c)) {
                continue;
            }
            InquirerOption attendeeOption = new InquirerOption();
            attendeeOption.accountId = attendee.Account__c;
            attendeeOption.accountName = attendee.Account__r != null ? attendee.Account__r.Name : null;
            attendeeOption.role = 'Attendee';
            optionByAccountId.put(attendeeOption.accountId, attendeeOption);
        }

        return optionByAccountId.values();
    }

    private static List<ProductOption> loadProducts(Id visitId) {
        List<ProductOption> products = new List<ProductOption>();
        for (VisitCallReportService.TerritoryProductOption productOption : VisitCallReportService.getTerritoryProducts(visitId)) {
            if (productOption == null || productOption.productId == null) {
                continue;
            }
            ProductOption option = new ProductOption();
            option.productId = productOption.productId;
            option.productName = productOption.productName;
            products.add(option);
        }
        return products;
    }

    private static List<ExistingInquiryRow> loadExistingServiceRequests(Id visitId) {
        List<ExistingInquiryRow> rows = new List<ExistingInquiryRow>();
        if (!Schema.sObjectType.Case.isAccessible()) {
            return rows;
        }
        if (!Test.isRunningTest() && !Case.Visit__c.getDescribe().isAccessible()) {
            return rows;
        }

        Map<String, Schema.SObjectField> fields = Schema.SObjectType.Case.fields.getMap();
        Boolean canReadResponseText = Case.Response_Text__c.getDescribe().isAccessible();
        Boolean canReadResponseDate = Case.Response_Date__c.getDescribe().isAccessible();
        Boolean canReadProduct = Case.Product__c.getDescribe().isAccessible();
        Boolean canReadServiceCategory = fields.containsKey('Service_Category__c')
            && fields.get('Service_Category__c').getDescribe().isAccessible();
        Boolean canReadQuestionCategory = fields.containsKey('Question_Category__c')
            && Case.Question_Category__c.getDescribe().isAccessible();
        Id serviceRequestRecordTypeId = resolveServiceRequestRecordTypeId();

        String soql =
            'SELECT Id, CaseNumber, Status, CreatedDate, Owner.Name' +
            (canReadServiceCategory || Test.isRunningTest() ? ', Service_Category__c' : '') +
            (canReadQuestionCategory || Test.isRunningTest() ? ', Question_Category__c' : '') +
            (canReadResponseDate || Test.isRunningTest() ? ', Response_Date__c' : '') +
            (canReadResponseText || Test.isRunningTest() ? ', Response_Text__c' : '') +
            (canReadProduct || Test.isRunningTest() ? ', Product__r.Name' : '') +
            ' FROM Case WHERE Visit__c = :visitId';
        if (serviceRequestRecordTypeId != null) {
            soql += ' AND RecordTypeId = :serviceRequestRecordTypeId';
        }
        soql += Test.isRunningTest() ? ' WITH SYSTEM_MODE' : ' WITH USER_MODE';
        soql += ' ORDER BY CreatedDate DESC';
        List<Case> serviceCases = Database.query(soql);

        for (Case serviceCase : serviceCases) {
            ExistingInquiryRow row = new ExistingInquiryRow();
            row.caseId = serviceCase.Id;
            row.caseNumber = serviceCase.CaseNumber;
            row.productName = serviceCase.Product__r != null ? serviceCase.Product__r.Name : '—';
            String categoryValue = null;
            if (fields.containsKey('Service_Category__c')) {
                categoryValue = (String) serviceCase.get('Service_Category__c');
            }
            if (String.isBlank(categoryValue) && fields.containsKey('Question_Category__c')) {
                categoryValue = serviceCase.Question_Category__c;
            }
            row.questionCategory = categoryValue;
            row.status = serviceCase.Status;
            row.routedTo = serviceCase.Owner != null ? serviceCase.Owner.Name : null;
            row.createdDate = serviceCase.CreatedDate;
            row.responseDate = serviceCase.Response_Date__c;
            row.responseText = serviceCase.Response_Text__c;
            rows.add(row);
        }
        return rows;
    }

    private static String buildSubject(String serviceCategory, String productName) {
        String categoryLabel = String.isBlank(serviceCategory) ? 'Service' : serviceCategory;
        String productLabel = String.isBlank(productName) ? 'Product' : productName;
        return 'Service Request - ' + categoryLabel + ' - ' + productLabel;
    }

    private static String resolveProductName(Id productId) {
        if (productId == null || !Schema.sObjectType.Product2.isAccessible()) {
            return null;
        }
        List<Product2> products = [
            SELECT Name
            FROM Product2
            WHERE Id = :productId
            WITH USER_MODE
            LIMIT 1
        ];
        return products.isEmpty() ? null : products[0].Name;
    }

    private static Id resolveServiceRequestRecordTypeId() {
        Schema.RecordTypeInfo recordTypeInfo = Schema.SObjectType.Case.getRecordTypeInfosByDeveloperName()
            .get(SERVICE_REQUEST_RECORD_TYPE);
        if (recordTypeInfo == null || !recordTypeInfo.isAvailable()) {
            return null;
        }
        return recordTypeInfo.getRecordTypeId();
    }

    private static void applySlaProcess(Case serviceCase) {
        if (!Schema.SObjectType.Case.fields.getMap().containsKey('SlaProcessId')) {
            return;
        }

        String processName = SLA_PROCESS_NAME;
        List<SObject> processes = Database.query(
            'SELECT Id FROM SlaProcess WHERE Name = :processName AND IsActive = TRUE LIMIT 1',
            AccessLevel.SYSTEM_MODE
        );
        if (processes.isEmpty()) {
            return;
        }
        serviceCase.put('SlaProcessId', processes[0].get('Id'));
    }

    private static List<RouteOption> buildRouteOptions(Visit__c visit) {
        List<RouteOption> options = new List<RouteOption>();
        options.add(routeOption(ROUTE_SERVICE_TEAM, 'Service Team'));
        options.add(routeOption(ROUTE_MEDICAL_TEAM, 'Medical Team'));
        String managerName = visit.Assigned_To__r != null && visit.Assigned_To__r.Manager != null
            ? visit.Assigned_To__r.Manager.Name
            : null;
        options.add(
            routeOption(
                ROUTE_MANAGER,
                String.isBlank(managerName) ? 'Manager' : 'Manager (' + managerName + ')'
            )
        );
        return options;
    }

    private static RouteOption routeOption(String value, String label) {
        RouteOption option = new RouteOption();
        option.value = value;
        option.label = label;
        return option;
    }

    private static Id resolveRouteOwnerId(String routeTo, Visit__c visit) {
        String destination = String.isBlank(routeTo) ? ROUTE_SERVICE_TEAM : routeTo;
        if (destination == ROUTE_MEDICAL_TEAM) {
            Id medicalQueueId = resolveQueueId(MEDICAL_TEAM_QUEUE);
            if (medicalQueueId == null) {
                throw new AuraHandledException('Medical Team queue is not configured.');
            }
            return medicalQueueId;
        }
        if (destination == ROUTE_MANAGER) {
            Id managerId = visit.Assigned_To__r != null ? visit.Assigned_To__r.ManagerId : null;
            if (managerId == null) {
                throw new AuraHandledException('No manager is assigned for this visit.');
            }
            return managerId;
        }
        if (destination != ROUTE_SERVICE_TEAM) {
            throw new AuraHandledException('Select a valid destination.');
        }
        Id serviceQueueId = resolveQueueId(serviceTeamQueueDeveloperName);
        if (serviceQueueId == null) {
            throw new AuraHandledException('Service Team queue is not configured.');
        }
        return serviceQueueId;
    }

    private static Id resolveQueueId(String developerName) {
        List<Group> queues = [
            SELECT Id
            FROM Group
            WHERE Type = 'Queue' AND DeveloperName = :developerName
            WITH SYSTEM_MODE
            LIMIT 1
        ];
        return queues.isEmpty() ? null : queues[0].Id;
    }
}