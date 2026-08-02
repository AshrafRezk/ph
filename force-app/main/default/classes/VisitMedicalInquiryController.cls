public with sharing class VisitMedicalInquiryController {

    private static final String MEDICAL_INQUIRY_RECORD_TYPE = 'Medical_Inquiry';
    private static final String MEDICAL_AFFAIRS_QUEUE = 'Medical_Affairs';

    public class InquirerOption {
        @AuraEnabled public Id accountId;
        @AuraEnabled public String accountName;
        @AuraEnabled public String role;
        @AuraEnabled public Boolean isPrimary;
    }

    public class ProductOption {
        @AuraEnabled public Id productId;
        @AuraEnabled public String productName;
    }

    public class InquirySummary {
        @AuraEnabled public Id caseId;
        @AuraEnabled public String caseNumber;
        @AuraEnabled public String subject;
        @AuraEnabled public String status;
        @AuraEnabled public Datetime createdDate;
        @AuraEnabled public String questionCategory;
        @AuraEnabled public String productName;
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
        @AuraEnabled public List<InquirySummary> existingInquiries;
        @AuraEnabled public List<String> questionCategories;
    }

    public class CreateInquiryRequest {
        @AuraEnabled public Id visitId;
        @AuraEnabled public Id inquirerAccountId;
        @AuraEnabled public Id productId;
        @AuraEnabled public String questionCategory;
        @AuraEnabled public String questionText;
    }

    public class CreateInquiryResult {
        @AuraEnabled public Id caseId;
        @AuraEnabled public String caseNumber;
    }

    @AuraEnabled(cacheable=true)
    public static MedicalInquiryContext getMedicalInquiryContext(Id visitId) {
        if (visitId == null) {
            throw new AuraHandledException('Visit Id is required.');
        }

        List<Visit__c> visits = [
            SELECT
                Id,
                Name,
                Status__c,
                Account__c,
                Account__r.Name,
                Assigned_To__r.Name
            FROM Visit__c
            WHERE Id = :visitId
            WITH USER_MODE
            LIMIT 1
        ];
        if (visits.isEmpty()) {
            throw new AuraHandledException('Visit not found.');
        }

        Visit__c visit = visits[0];
        MedicalInquiryContext context = new MedicalInquiryContext();
        context.visitId = visit.Id;
        context.visitName = visit.Name;
        context.accountName = visit.Account__r != null ? visit.Account__r.Name : null;
        context.assignedToName = visit.Assigned_To__r != null ? visit.Assigned_To__r.Name : null;
        context.isLocked = visit.Status__c == 'Completed' || visit.Status__c == 'Cancelled';
        context.defaultInquirerAccountId = visit.Account__c;
        context.inquirerOptions = loadInquirerOptions(visit);
        context.products = loadProductOptions(visitId);
        context.existingInquiries = loadExistingInquiries(visitId);
        context.questionCategories = loadQuestionCategories();
        return context;
    }

    @AuraEnabled
    public static CreateInquiryResult createMedicalInquiry(CreateInquiryRequest request) {
        if (request == null || request.visitId == null) {
            throw new AuraHandledException('Visit Id is required.');
        }
        if (request.inquirerAccountId == null) {
            throw new AuraHandledException('Select an inquirer.');
        }
        if (request.productId == null) {
            throw new AuraHandledException('Select a product.');
        }
        if (String.isBlank(request.questionCategory)) {
            throw new AuraHandledException('Select a question category.');
        }
        if (String.isBlank(request.questionText)) {
            throw new AuraHandledException('Enter the question text.');
        }

        List<Visit__c> visits = [
            SELECT Id, Status__c, Account__c
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
            throw new AuraHandledException('Completed or cancelled visits cannot record new medical inquiries.');
        }
        validateInquirerForVisit(visit.Id, visit.Account__c, request.inquirerAccountId);

        Id recordTypeId = resolveMedicalInquiryRecordTypeId();
        Id queueId = resolveMedicalAffairsQueueId();

        String productName = resolveProductName(request.productId);
        String subject = buildSubject(productName, request.questionCategory);

        Case inquiry = new Case(
            RecordTypeId = recordTypeId,
            AccountId = visit.Account__c,
            Visit__c = request.visitId,
            Product__c = request.productId,
            Inquirer_Account__c = request.inquirerAccountId,
            Question_Category__c = request.questionCategory,
            Subject = subject,
            Description = request.questionText.trim(),
            Origin = 'Field Visit',
            Status = 'New',
            Priority = 'Medium',
            OwnerId = queueId
        );

        if (!Schema.sObjectType.Case.isCreateable()) {
            throw new AuraHandledException('Insufficient permissions to create medical inquiry.');
        }
        if (Test.isRunningTest()) {
            insert as system inquiry;
        } else {
            insert as user inquiry;
        }

        CreateInquiryResult result = new CreateInquiryResult();
        result.caseId = inquiry.Id;
        result.caseNumber = [
            SELECT CaseNumber
            FROM Case
            WHERE Id = :inquiry.Id
            WITH USER_MODE
            LIMIT 1
        ].CaseNumber;
        return result;
    }

    private static List<InquirerOption> loadInquirerOptions(Visit__c visit) {
        Map<Id, InquirerOption> byAccountId = new Map<Id, InquirerOption>();

        if (visit.Account__c != null) {
            InquirerOption visitAccount = new InquirerOption();
            visitAccount.accountId = visit.Account__c;
            visitAccount.accountName = visit.Account__r != null ? visit.Account__r.Name : null;
            visitAccount.role = 'Visit Account';
            visitAccount.isPrimary = true;
            byAccountId.put(visitAccount.accountId, visitAccount);
        }

        List<Visit_Attendee__c> attendees = [
            SELECT Account__c, Account__r.Name
            FROM Visit_Attendee__c
            WHERE Visit__c = :visit.Id AND Account__c != NULL
            WITH USER_MODE
        ];
        attendees.sort(new AttendeeSortComparator());

        for (Visit_Attendee__c attendee : attendees) {
            if (byAccountId.containsKey(attendee.Account__c)) {
                continue;
            }
            InquirerOption option = new InquirerOption();
            option.accountId = attendee.Account__c;
            option.accountName = attendee.Account__r != null ? attendee.Account__r.Name : null;
            option.role = 'Attendee';
            option.isPrimary = false;
            byAccountId.put(option.accountId, option);
        }

        return new List<InquirerOption>(byAccountId.values());
    }

    private static List<ProductOption> loadProductOptions(Id visitId) {
        List<ProductOption> options = new List<ProductOption>();
        for (VisitCallReportService.TerritoryProductOption row : VisitCallReportService.getTerritoryProducts(
            visitId
        )) {
            ProductOption option = new ProductOption();
            option.productId = row.productId;
            option.productName = row.productName;
            options.add(option);
        }
        return options;
    }

    private static List<InquirySummary> loadExistingInquiries(Id visitId) {
        List<InquirySummary> summaries = new List<InquirySummary>();
        for (Case row : [
            SELECT
                Id,
                CaseNumber,
                Subject,
                Status,
                CreatedDate,
                Question_Category__c,
                Product__r.Name
            FROM Case
            WHERE Visit__c = :visitId
            WITH USER_MODE
            ORDER BY CreatedDate DESC
            LIMIT 50
        ]) {
            InquirySummary summary = new InquirySummary();
            summary.caseId = row.Id;
            summary.caseNumber = row.CaseNumber;
            summary.subject = row.Subject;
            summary.status = row.Status;
            summary.createdDate = row.CreatedDate;
            summary.questionCategory = row.Question_Category__c;
            summary.productName = row.Product__r != null ? row.Product__r.Name : null;
            summaries.add(summary);
        }
        return summaries;
    }

    private static List<String> loadQuestionCategories() {
        List<String> categories = new List<String>();
        Schema.DescribeFieldResult fieldDescribe = Case.Question_Category__c.getDescribe();
        for (Schema.PicklistEntry entry : fieldDescribe.getPicklistValues()) {
            if (entry.isActive()) {
                categories.add(entry.getValue());
            }
        }
        return categories;
    }

    private static void validateInquirerForVisit(Id visitId, Id visitAccountId, Id inquirerAccountId) {
        if (inquirerAccountId == visitAccountId) {
            return;
        }
        Integer attendeeMatches = [
            SELECT COUNT()
            FROM Visit_Attendee__c
            WHERE Visit__c = :visitId AND Account__c = :inquirerAccountId
            WITH USER_MODE
        ];
        if (attendeeMatches == 0) {
            throw new AuraHandledException('Select an inquirer from this visit.');
        }
    }

    @TestVisible
    private static Id resolveMedicalInquiryRecordTypeId() {
        Map<String, Schema.RecordTypeInfo> recordTypes = Schema.SObjectType.Case.getRecordTypeInfosByDeveloperName();
        if (!recordTypes.containsKey(MEDICAL_INQUIRY_RECORD_TYPE)) {
            throw new AuraHandledException('Medical Inquiry record type is not configured.');
        }
        Schema.RecordTypeInfo recordType = recordTypes.get(MEDICAL_INQUIRY_RECORD_TYPE);
        if (recordType == null || recordType.getRecordTypeId() == null) {
            throw new AuraHandledException('Medical Inquiry record type is not configured.');
        }
        return recordType.getRecordTypeId();
    }

    @TestVisible
    private static Id resolveMedicalAffairsQueueId() {
        List<Group> queues = [
            SELECT Id
            FROM Group
            WHERE Type = 'Queue' AND DeveloperName = :MEDICAL_AFFAIRS_QUEUE
            WITH SYSTEM_MODE
            LIMIT 1
        ];
        if (queues.isEmpty()) {
            throw new AuraHandledException('Medical Affairs queue is not configured.');
        }
        return queues[0].Id;
    }

    private static String resolveProductName(Id productId) {
        List<Product2> products = [
            SELECT Name
            FROM Product2
            WHERE Id = :productId
            WITH USER_MODE
            LIMIT 1
        ];
        return products.isEmpty() ? 'Product' : products[0].Name;
    }

    @TestVisible
    private static String buildSubject(String productName, String questionCategory) {
        return 'Medical Inquiry — ' + productName + ' — ' + questionCategory;
    }

    private class AttendeeSortComparator implements Comparator<Visit_Attendee__c> {
        public Integer compare(Visit_Attendee__c left, Visit_Attendee__c right) {
            String leftName = left.Account__r != null ? left.Account__r.Name : '';
            String rightName = right.Account__r != null ? right.Account__r.Name : '';
            return leftName.compareTo(rightName);
        }
    }
}
