public with sharing class VisitConsentController {
    public class ConsentRow {
        @AuraEnabled public Id id;
        @AuraEnabled public String name;
        @AuraEnabled public String channel;
        @AuraEnabled public String consentType;
        @AuraEnabled public String status;
        @AuraEnabled public Datetime capturedAt;
        @AuraEnabled public Boolean hasSignature;
        @AuraEnabled public String notes;
    }

    public class ConsentContext {
        @AuraEnabled public Id visitId;
        @AuraEnabled public String visitName;
        @AuraEnabled public Id accountId;
        @AuraEnabled public String accountName;
        @AuraEnabled public Boolean isLocked;
        @AuraEnabled public List<PickOption> channelOptions;
        @AuraEnabled public List<PickOption> consentTypeOptions;
        @AuraEnabled public List<PickOption> statusOptions;
        @AuraEnabled public List<ConsentRow> existingConsents;
    }

    public class PickOption {
        @AuraEnabled public String label;
        @AuraEnabled public String value;
    }

    public class CaptureRequest {
        @AuraEnabled public Id visitId;
        @AuraEnabled public Id accountId;
        @AuraEnabled public String channel;
        @AuraEnabled public String consentType;
        @AuraEnabled public String status;
        @AuraEnabled public String signatureData;
        @AuraEnabled public String notes;
    }

    public class CaptureResult {
        @AuraEnabled public Id consentId;
        @AuraEnabled public String name;
    }

    @AuraEnabled
    public static ConsentContext getVisitConsentContext(Id visitId) {
        if (visitId == null) {
            throw new AuraHandledException('Visit Id is required.');
        }
        List<Visit__c> visits = [
            SELECT Id, Name, Status__c, Account__c, Account__r.Name
            FROM Visit__c
            WHERE Id = :visitId
            WITH USER_MODE
            LIMIT 1
        ];
        if (visits.isEmpty()) {
            throw new AuraHandledException('Visit not found.');
        }
        Visit__c visit = visits[0];
        ConsentContext context = new ConsentContext();
        context.visitId = visit.Id;
        context.visitName = visit.Name;
        context.accountId = visit.Account__c;
        context.accountName = visit.Account__r != null ? visit.Account__r.Name : null;
        context.isLocked = visit.Status__c == 'Completed' || visit.Status__c == 'Cancelled';
        context.channelOptions = picklistOptions(Visit_Consent__c.Channel__c);
        context.consentTypeOptions = picklistOptions(Visit_Consent__c.Consent_Type__c);
        context.statusOptions = picklistOptions(Visit_Consent__c.Status__c);
        context.existingConsents = loadExisting(visit.Id);
        return context;
    }

    @AuraEnabled
    public static CaptureResult captureVisitConsent(CaptureRequest request) {
        if (request == null || request.visitId == null) {
            throw new AuraHandledException('Visit Id is required.');
        }
        if (String.isBlank(request.channel)) {
            throw new AuraHandledException('Select a channel.');
        }
        if (String.isBlank(request.consentType)) {
            throw new AuraHandledException('Select a consent type.');
        }
        String status = String.isBlank(request.status) ? 'Granted' : request.status;
        if (status == 'Granted' && String.isBlank(request.signatureData)) {
            throw new AuraHandledException('Capture a signature before granting consent.');
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
            throw new AuraHandledException('Completed or cancelled visits cannot capture new consent.');
        }

        Visit_Consent__c record = new Visit_Consent__c(
            Visit__c = visit.Id,
            Account__c = request.accountId != null ? request.accountId : visit.Account__c,
            Channel__c = request.channel,
            Consent_Type__c = request.consentType,
            Status__c = status,
            Captured_At__c = Datetime.now(),
            Signature_Data__c = request.signatureData,
            Notes__c = request.notes
        );
        insert as user record;

        Visit_Consent__c stored = [
            SELECT Name
            FROM Visit_Consent__c
            WHERE Id = :record.Id
            WITH USER_MODE
            LIMIT 1
        ];
        CaptureResult result = new CaptureResult();
        result.consentId = record.Id;
        result.name = stored.Name;
        return result;
    }

    private static List<ConsentRow> loadExisting(Id visitId) {
        List<ConsentRow> rows = new List<ConsentRow>();
        for (Visit_Consent__c record : [
            SELECT Id, Name, Channel__c, Consent_Type__c, Status__c, Captured_At__c, Signature_Data__c, Notes__c
            FROM Visit_Consent__c
            WHERE Visit__c = :visitId
            WITH USER_MODE
            ORDER BY Captured_At__c DESC
            LIMIT 50
        ]) {
            ConsentRow row = new ConsentRow();
            row.id = record.Id;
            row.name = record.Name;
            row.channel = record.Channel__c;
            row.consentType = record.Consent_Type__c;
            row.status = record.Status__c;
            row.capturedAt = record.Captured_At__c;
            row.hasSignature = String.isNotBlank(record.Signature_Data__c);
            row.notes = record.Notes__c;
            rows.add(row);
        }
        return rows;
    }

    private static List<PickOption> picklistOptions(Schema.SObjectField field) {
        List<PickOption> options = new List<PickOption>();
        for (Schema.PicklistEntry entry : field.getDescribe().getPicklistValues()) {
            if (!entry.isActive()) {
                continue;
            }
            PickOption option = new PickOption();
            option.label = entry.getLabel();
            option.value = entry.getValue();
            options.add(option);
        }
        return options;
    }
}
