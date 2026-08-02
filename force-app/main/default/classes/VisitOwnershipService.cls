/**
 * Ensures visit records are owned by the assigned rep so sharing rules
 * do not hide planner and home visit data from field users.
 */
public without sharing class VisitOwnershipService {

    public class RepairResult {
        @AuraEnabled public Integer updatedCount;
        @AuraEnabled public String message;

        public RepairResult(Integer updatedCount) {
            this.updatedCount = updatedCount;
            this.message = 'Realigned ownership on ' + updatedCount + ' visit(s).';
        }
    }

    public static void applyAssignedOwner(Visit__c visit) {
        if (visit != null && visit.Assigned_To__c != null) {
            visit.OwnerId = visit.Assigned_To__c;
        }
    }

    public static void applyAssignedOwners(List<Visit__c> visits) {
        if (visits == null) {
            return;
        }
        for (Visit__c visit : visits) {
            applyAssignedOwner(visit);
        }
    }

    public static RepairResult realignAssignedVisitOwners() {
        return realignAssignedVisitOwners(null);
    }

    public static RepairResult realignAssignedVisitOwners(Set<Id> assignedUserIds) {
        List<Visit__c> candidates;
        if (assignedUserIds == null || assignedUserIds.isEmpty()) {
            candidates = [
                SELECT Id, OwnerId, Assigned_To__c
                FROM Visit__c
                WHERE Assigned_To__c != null
                WITH SYSTEM_MODE
                LIMIT 10000
            ];
        } else {
            candidates = [
                SELECT Id, OwnerId, Assigned_To__c
                FROM Visit__c
                WHERE Assigned_To__c IN :assignedUserIds
                WITH SYSTEM_MODE
                LIMIT 10000
            ];
        }

        List<Visit__c> toUpdate = new List<Visit__c>();
        for (Visit__c visit : candidates) {
            if (visit.Assigned_To__c != visit.OwnerId) {
                toUpdate.add(new Visit__c(Id = visit.Id, OwnerId = visit.Assigned_To__c));
            }
        }
        if (!toUpdate.isEmpty()) {
            update as system toUpdate;
        }
        return new RepairResult(toUpdate.size());
    }
}
