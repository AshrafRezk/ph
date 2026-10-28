/**
 * Pending meeting approvals for the running manager.
 * Meeting__c is private, so the queue reads in system mode and only returns
 * meetings owned by direct reports, territory subordinates, or active delegates.
 */
public without sharing class MeetingApprovalAccess {
    public class PendingRow {
        @AuraEnabled public Id meetingId;
        @AuraEnabled public String meetingName;
        @AuraEnabled public String title;
        @AuraEnabled public String ownerName;
        @AuraEnabled public String recordTypeLabel;
        @AuraEnabled public String status;
        @AuraEnabled public DateTime startDateTime;
    }

    private static final Set<String> PENDING_STATUSES = new Set<String>{
        'PendingApproval',
        'Pending GPM Approval',
        'Pending NLM Approval'
    };

    private static final Set<String> MANAGER_ROLES = new Set<String>{
        'District Manager',
        'Region Manager',
        'Line Manager',
        'NSM',
        'National Sales Manager',
        'Area Manager',
        'Business Unit Manager',
        'Brand Manager',
        'Trainer'
    };

    public static List<PendingRow> getPendingApprovals(Id managerId) {
        List<PendingRow> rows = new List<PendingRow>();
        if (managerId == null) {
            return rows;
        }
        Set<Id> ownerIds = managedUserIds(managerId);
        for (Meeting__c meeting : [
            SELECT Id, Name, Objectives__c, Status__c, Start_Date_Time__c, Owner.Name, RecordType.Name
            FROM Meeting__c
            WHERE (Originating_Department__c = NULL AND Status__c IN :PENDING_STATUSES AND OwnerId IN :ownerIds)
                OR (Originating_Department__c != NULL AND Approval_Status__c = 'In Approval' AND Current_Approver__c = :managerId)
            WITH SYSTEM_MODE
            ORDER BY Start_Date_Time__c ASC NULLS LAST
            LIMIT 200
        ]) {
            PendingRow row = new PendingRow();
            row.meetingId = meeting.Id;
            row.meetingName = meeting.Name;
            row.title = String.isNotBlank(meeting.Objectives__c) ? meeting.Objectives__c : meeting.Name;
            row.ownerName = meeting.Owner != null ? meeting.Owner.Name : null;
            row.recordTypeLabel = meeting.RecordType != null ? meeting.RecordType.Name : null;
            row.status = meeting.Status__c;
            row.startDateTime = meeting.Start_Date_Time__c;
            rows.add(row);
        }
        return rows;
    }

    public static Boolean managesUser(Id managerId, Id userId) {
        if (managerId == null || userId == null || managerId == userId) {
            return false;
        }
        return territorySubordinateIds(managerId).contains(userId);
    }

    private static Set<Id> managedUserIds(Id managerId) {
        Set<Id> userIds = new Set<Id>();
        for (User report : [
            SELECT Id
            FROM User
            WHERE ManagerId = :managerId AND IsActive = TRUE
            WITH SYSTEM_MODE
        ]) {
            userIds.add(report.Id);
        }
        userIds.addAll(territorySubordinateIds(managerId));
        Set<Id> delegatedTerritories = DelegationService.getActiveDelegatedTerritoryIds(managerId);
        if (!delegatedTerritories.isEmpty()) {
            for (UserTerritory2Association member : [
                SELECT UserId
                FROM UserTerritory2Association
                WHERE Territory2Id IN :delegatedTerritories AND UserId != :managerId
                WITH SYSTEM_MODE
            ]) {
                userIds.add(member.UserId);
            }
        }
        userIds.remove(managerId);
        return userIds;
    }

    private static Set<Id> territorySubordinateIds(Id managerId) {
        Set<Id> roots = new Set<Id>();
        for (UserTerritory2Association assignment : [
            SELECT Territory2Id, RoleInTerritory2
            FROM UserTerritory2Association
            WHERE UserId = :managerId AND Territory2Id != NULL AND RoleInTerritory2 != NULL
            WITH SYSTEM_MODE
        ]) {
            if (MANAGER_ROLES.contains(assignment.RoleInTerritory2)) {
                roots.add(assignment.Territory2Id);
            }
        }
        if (roots.isEmpty()) {
            return new Set<Id>();
        }
        Set<Id> tree = TerritoryHierarchyService.expandTerritoryHierarchy(roots);
        Set<Id> userIds = new Set<Id>();
        for (UserTerritory2Association member : [
            SELECT UserId
            FROM UserTerritory2Association
            WHERE Territory2Id IN :tree AND UserId != :managerId
            WITH SYSTEM_MODE
        ]) {
            userIds.add(member.UserId);
        }
        return userIds;
    }
}