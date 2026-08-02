public with sharing class CrossDeptController {

    public class RequestRow {
        @AuraEnabled public Id id;
        @AuraEnabled public String subject;
        @AuraEnabled public String status;
        @AuraEnabled public String priority;
        @AuraEnabled public String requestingDept;
        @AuraEnabled public String targetDept;
        @AuraEnabled public String relatedProject;
        @AuraEnabled public Decimal budgetImpact;
    }

    @AuraEnabled(cacheable=true)
    public static List<RequestRow> getCollaborationRequests() {
        List<RequestRow> rows = new List<RequestRow>();
        for (Collaboration_Request__c req : [
            SELECT Id, Name, Status__c, Priority__c, Budget_Impact__c,
                Requesting_Department__r.Name, Target_Department__r.Name,
                Related_Project__r.Name
            FROM Collaboration_Request__c
            WITH SYSTEM_MODE
            ORDER BY CreatedDate DESC
            LIMIT 100
        ]) {
            RequestRow row = new RequestRow();
            row.id = req.Id;
            row.subject = req.Name;
            row.status = req.Status__c;
            row.priority = req.Priority__c;
            row.requestingDept = req.Requesting_Department__r != null ? req.Requesting_Department__r.Name : null;
            row.targetDept = req.Target_Department__r != null ? req.Target_Department__r.Name : null;
            row.relatedProject = req.Related_Project__r != null ? req.Related_Project__r.Name : null;
            row.budgetImpact = req.Budget_Impact__c;
            rows.add(row);
        }
        return rows;
    }
}
