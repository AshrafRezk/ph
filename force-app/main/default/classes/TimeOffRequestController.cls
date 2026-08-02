public with sharing class TimeOffRequestController {

    public class RequestSummary {
        @AuraEnabled public Id id;
        @AuraEnabled public String name;
        @AuraEnabled public String typeLabel;
        @AuraEnabled public String spanType;
        @AuraEnabled public Decimal workingDays;
        @AuraEnabled public Date startDate;
        @AuraEnabled public Date endDate;
        @AuraEnabled public String stage;
        @AuraEnabled public DateTime createdDate;
    }

    @AuraEnabled(cacheable=true)
    public static List<RequestSummary> getMyRequests(Integer limitSize) {
        Integer lim = limitSize == null ? 10 : Math.min(limitSize, 50);
        List<RequestSummary> results = new List<RequestSummary>();

        for (Time_Off_Request__c request : [
            SELECT Id, Name, Type__c, Span_Type__c, Working_Day_Equivalent__c,
                   Start_Date__c, End_Date__c, Stage__c, CreatedDate
            FROM Time_Off_Request__c
            WHERE CreatedById = :UserInfo.getUserId()
            ORDER BY CreatedDate DESC
            LIMIT :lim
        ]) {
            RequestSummary summary = new RequestSummary();
            summary.id = request.Id;
            summary.name = request.Name;
            summary.typeLabel = request.Type__c;
            summary.spanType = request.Span_Type__c;
            summary.workingDays = request.Working_Day_Equivalent__c;
            summary.startDate = request.Start_Date__c;
            summary.endDate = request.End_Date__c;
            summary.stage = request.Stage__c;
            summary.createdDate = request.CreatedDate;
            results.add(summary);
        }

        return results;
    }
}
