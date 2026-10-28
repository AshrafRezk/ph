/**
 * LWC-facing API for delegation management (invite delegate, list, revoke) — surfaced from
 * fieldRepPlanner. Thin wrapper over DelegationService.
 */
public with sharing class DelegationController {
    @AuraEnabled
    public static Id inviteDelegate(
        Id delegateUserId,
        String territoryId,
        Date startDate,
        Date endDate,
        String notes
    ) {
        try {
            return DelegationService.createDelegation(delegateUserId, territoryId, startDate, endDate, notes).Id;
        } catch (Exception ex) {
            throw new AuraHandledException(ex.getMessage());
        }
    }

    @AuraEnabled
    public static void revokeDelegation(Id delegationId) {
        try {
            DelegationService.revoke(delegationId);
        } catch (Exception ex) {
            throw new AuraHandledException(ex.getMessage());
        }
    }

    @AuraEnabled(cacheable=true)
    public static List<Delegation__c> getDelegationsGranted() {
        return DelegationService.getDelegationsAsDelegator();
    }

    @AuraEnabled(cacheable=true)
    public static List<Delegation__c> getDelegationsReceived() {
        return DelegationService.getDelegationsAsDelegate();
    }
}