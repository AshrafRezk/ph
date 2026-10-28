/**
 * Admin lifecycle actions for CLM presentations: target (territory/role), publish (make Available
 * within a date window), and expire. Upload is handled by the content wizard; this exposes the
 * publish/target/expire transitions as a testable API for clmAdminConsole / clmPresentationWizard.
 */
public with sharing class ClmPresentationAdminController {
    @AuraEnabled
    public static void updateTargeting(
        Id presentationId,
        String territoryIdsJson,
        String rolesJson,
        Boolean allowUnaligned
    ) {
        requireId(presentationId);
        try {
            update new CLM_Presentation__c(
                Id = presentationId,
                Territory_Ids__c = territoryIdsJson,
                Target_Roles__c = rolesJson,
                Allow_Unaligned__c = allowUnaligned == true
            );
        } catch (Exception ex) {
            throw new AuraHandledException(ex.getMessage());
        }
    }

    @AuraEnabled
    public static void publish(Id presentationId, Date startDate, Date endDate) {
        requireId(presentationId);
        if (startDate != null && endDate != null && endDate < startDate) {
            throw new AuraHandledException('End date must be on or after the start date.');
        }
        try {
            update new CLM_Presentation__c(
                Id = presentationId,
                Status__c = 'Available',
                Start_Date__c = startDate,
                End_Date__c = endDate
            );
        } catch (Exception ex) {
            throw new AuraHandledException(ex.getMessage());
        }
    }

    @AuraEnabled
    public static void expire(Id presentationId) {
        requireId(presentationId);
        try {
            update new CLM_Presentation__c(
                Id = presentationId,
                Status__c = 'Unavailable',
                End_Date__c = Date.today()
            );
        } catch (Exception ex) {
            throw new AuraHandledException(ex.getMessage());
        }
    }

    private static void requireId(Id presentationId) {
        if (presentationId == null) {
            throw new AuraHandledException('A presentation id is required.');
        }
    }
}