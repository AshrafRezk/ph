/**
 * Time-bound delegation: a rep can act as DM over a line for a period. An active delegation
 * (Active__c, and today within Start/End) grants the delegate DM-like reach over the delegated
 * territory subtree — used by FieldPlannerController to expose the line's planners and by the
 * double-visit flow to let the delegate act as the managing DM.
 *
 * Delegation__c reads run in SYSTEM_MODE (internal access-resolution service, mirroring
 * TerritoryHierarchyService) so delegation resolution does not depend on per-profile FLS.
 */
public with sharing class DelegationService {
    public static Boolean isActiveDelegate(Id delegateUserId) {
        return !getActiveDelegations(delegateUserId).isEmpty();
    }

    public static List<Delegation__c> getActiveDelegations(Id delegateUserId) {
        if (delegateUserId == null) {
            return new List<Delegation__c>();
        }
        Date today = Date.today();
        return [
            SELECT Id, Delegator__c, Delegate__c, Territory_Id__c, Start_Date__c, End_Date__c, Active__c, Notes__c
            FROM Delegation__c
            WHERE
                Delegate__c = :delegateUserId
                AND Active__c = TRUE
                AND (Start_Date__c = NULL OR Start_Date__c <= :today)
                AND (End_Date__c = NULL OR End_Date__c >= :today)
            WITH SYSTEM_MODE
            ORDER BY End_Date__c ASC NULLS LAST
        ];
    }

    /** Territory subtree(s) the delegate currently acts as DM over. */
    public static Set<Id> getActiveDelegatedTerritoryIds(Id delegateUserId) {
        Set<Id> roots = new Set<Id>();
        for (Delegation__c delegation : getActiveDelegations(delegateUserId)) {
            if (String.isNotBlank(delegation.Territory_Id__c)) {
                try {
                    roots.add((Id) delegation.Territory_Id__c);
                } catch (Exception ignored) {
                    // Malformed stored id — skip.
                }
            }
        }
        if (roots.isEmpty()) {
            return new Set<Id>();
        }
        return TerritoryHierarchyService.expandTerritoryHierarchy(roots);
    }

    /** True when the delegate currently manages the given rep via an active line delegation. */
    public static Boolean canActAsManagerFor(Id delegateUserId, Id repUserId) {
        if (repUserId == null) {
            return false;
        }
        Set<Id> territoryIds = getActiveDelegatedTerritoryIds(delegateUserId);
        if (territoryIds.isEmpty()) {
            return false;
        }
        for (UserTerritory2Association assignment : [
            SELECT Id
            FROM UserTerritory2Association
            WHERE UserId = :repUserId AND Territory2Id IN :territoryIds
            WITH SYSTEM_MODE
            LIMIT 1
        ]) {
            return true;
        }
        return false;
    }

    /** Invite/create a delegation. Delegator is the running user (the granting DM). */
    public static Delegation__c createDelegation(
        Id delegateUserId,
        String territoryId,
        Date startDate,
        Date endDate,
        String notes
    ) {
        if (delegateUserId == null) {
            throw new DelegationException('A delegate is required.');
        }
        if (delegateUserId == UserInfo.getUserId()) {
            throw new DelegationException('You cannot delegate to yourself.');
        }
        if (startDate != null && endDate != null && endDate < startDate) {
            throw new DelegationException('End date must be on or after the start date.');
        }
        Delegation__c delegation = new Delegation__c(
            Delegator__c = UserInfo.getUserId(),
            Delegate__c = delegateUserId,
            Territory_Id__c = territoryId,
            Start_Date__c = startDate,
            End_Date__c = endDate,
            Active__c = true,
            Notes__c = notes
        );
        insert delegation;
        return delegation;
    }

    public static void revoke(Id delegationId) {
        if (delegationId == null) {
            throw new DelegationException('A delegation id is required.');
        }
        update new Delegation__c(Id = delegationId, Active__c = false);
    }

    public static List<Delegation__c> getDelegationsAsDelegator() {
        return [
            SELECT Id, Delegate__c, Delegate__r.Name, Territory_Id__c, Start_Date__c, End_Date__c, Active__c, Notes__c
            FROM Delegation__c
            WHERE Delegator__c = :UserInfo.getUserId()
            WITH SYSTEM_MODE
            ORDER BY CreatedDate DESC
            LIMIT 500
        ];
    }

    public static List<Delegation__c> getDelegationsAsDelegate() {
        return [
            SELECT Id, Delegator__c, Delegator__r.Name, Territory_Id__c, Start_Date__c, End_Date__c, Active__c, Notes__c
            FROM Delegation__c
            WHERE Delegate__c = :UserInfo.getUserId()
            WITH SYSTEM_MODE
            ORDER BY CreatedDate DESC
            LIMIT 500
        ];
    }

    public class DelegationException extends Exception {
    }
}