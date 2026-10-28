public with sharing class CaseSlaController {
    @AuraEnabled(cacheable=true)
    public static CaseSlaService.SlaMilestoneView getSlaMilestone(Id caseId) {
        if (caseId == null) {
            throw new AuraHandledException('Case Id is required.');
        }

        List<Case> cases = [
            SELECT Id, IsClosed, Stage_Start_Time__c, Stage_Due__c
            FROM Case
            WHERE Id = :caseId
            WITH USER_MODE
            LIMIT 1
        ];

        if (cases.isEmpty()) {
            throw new AuraHandledException('Case not found.');
        }

        Case caseRecord = cases[0];
        return CaseSlaService.buildMilestoneView(
            caseRecord.Stage_Start_Time__c,
            caseRecord.Stage_Due__c,
            caseRecord.IsClosed
        );
    }
}