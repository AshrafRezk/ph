/**
 * Classification cycle approver resolution.
 * Prefers the SFE approver configured for the cycle's line (Admin Console > SFE Approvers):
 * line approvers first, then business unit, then All Lines. Falls back to User.ManagerId.
 */
public with sharing class ClassificationApprovalRouter {
    public static Id resolveApproverId(Id employeeId) {
        return resolveApproverId(employeeId, null);
    }

    /** territoryId is the cycle's territory. Blank uses the employee's latest active seat. */
    public static Id resolveApproverId(Id employeeId, Id territoryId) {
        if (employeeId == null) {
            return null;
        }
        Id seatId = territoryId != null ? territoryId : primaryTerritoryId(employeeId);
        for (Id approverId : SfeApproverService.approversForTerritory(seatId, SfeApproverService.CLASSIFICATION)) {
            if (approverId != employeeId) {
                return approverId;
            }
        }
        List<User> users = [
            SELECT ManagerId
            FROM User
            WHERE Id = :employeeId
            WITH SYSTEM_MODE
            LIMIT 1
        ];
        return users.isEmpty() ? null : users[0].ManagerId;
    }

    private static Id primaryTerritoryId(Id userId) {
        for (UserTerritory2Association assignment : [
            SELECT Territory2Id
            FROM UserTerritory2Association
            WHERE UserId = :userId AND IsActive = TRUE
            WITH SYSTEM_MODE
            ORDER BY LastModifiedDate DESC
            LIMIT 1
        ]) {
            return assignment.Territory2Id;
        }
        return null;
    }
}
