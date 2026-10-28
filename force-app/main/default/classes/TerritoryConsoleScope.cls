/**
 * Span of control for the admin console (Territories, Users and Products).
 *
 * Full scope: callers with Manage Users, View All Data or Modify All Data
 * (SFE and System Administrators). They see the whole organogram.
 *
 * Everyone else sees only the territories at or below their own active seats:
 *   - a District Manager sees their district(s) and the positions under them;
 *   - a National Sales Manager or Brand Manager seated on a Line sees that line;
 *   - a Group Brand Lead or BU Manager seated on a Business Unit sees that BU.
 * A caller with neither the permission nor a seat sees nothing.
 *
 * Other consoles (for example the Products Manager) call
 *   TerritoryConsoleScope.getScopedTerritoryIds()   null = everything, else the allowed Territory2 ids
 *   TerritoryConsoleScope.getScopedLineIds()        null = every line, else the allowed Line ids
 *   TerritoryConsoleScope.requireInScope(territoryId) before a change
 */
public without sharing class TerritoryConsoleScope {
    public static final String OUT_OF_SCOPE_MESSAGE = 'You can only see and change your own team.';

    private static Map<Id, Boolean> fullScopeByUser = new Map<Id, Boolean>();
    private static Map<Id, Set<Id>> scopeByUser = new Map<Id, Set<Id>>();

    /** Tests only: force the running user to be treated as a manager (not full scope). */
    @TestVisible
    private static Boolean forceManagerScope = false;

    public static Boolean hasFullScope() {
        return hasFullScope(UserInfo.getUserId());
    }

    public static Boolean hasFullScope(Id userId) {
        if (userId == null) {
            return false;
        }
        if (Test.isRunningTest() && forceManagerScope && userId == UserInfo.getUserId()) {
            return false;
        }
        if (fullScopeByUser.containsKey(userId)) {
            return fullScopeByUser.get(userId);
        }
        // Includes the profile's own permission set and permission set groups.
        Integer grants = [
            SELECT COUNT()
            FROM PermissionSetAssignment
            WHERE AssigneeId = :userId
                AND (PermissionSet.PermissionsManageUsers = TRUE
                    OR PermissionSet.PermissionsViewAllData = TRUE
                    OR PermissionSet.PermissionsModifyAllData = TRUE)
            WITH SYSTEM_MODE
        ];
        Boolean full = grants > 0;
        fullScopeByUser.put(userId, full);
        return full;
    }

    /** Null when the user may see every territory; otherwise the territories at or below their seats. */
    public static Set<Id> getScopedTerritoryIds() {
        return getScopedTerritoryIds(UserInfo.getUserId());
    }

    public static Set<Id> getScopedTerritoryIds(Id userId) {
        if (hasFullScope(userId)) {
            return null;
        }
        if (userId == null) {
            return new Set<Id>();
        }
        if (scopeByUser.containsKey(userId)) {
            return new Set<Id>(scopeByUser.get(userId));
        }
        Set<Id> seats = new Set<Id>();
        for (UserTerritory2Association link : [
            SELECT Territory2Id
            FROM UserTerritory2Association
            WHERE UserId = :userId AND IsActive = TRUE
            WITH SYSTEM_MODE
        ]) {
            seats.add(link.Territory2Id);
        }
        Set<Id> scope = seats.isEmpty()
            ? new Set<Id>()
            : TerritoryHierarchyService.expandTerritoryHierarchy(seats);
        scopeByUser.put(userId, scope);
        return new Set<Id>(scope);
    }

    /** Null when every line is visible; otherwise the Line territories inside or above the caller's seats. */
    public static Set<Id> getScopedLineIds() {
        Set<Id> scope = getScopedTerritoryIds();
        if (scope == null) {
            return null;
        }
        Set<Id> lineIds = new Set<Id>();
        if (scope.isEmpty()) {
            return lineIds;
        }
        Set<Id> withAncestors = withAncestors(scope);
        for (Territory2 line : [
            SELECT Id
            FROM Territory2
            WHERE Id IN :withAncestors AND Territory_Type__c = 'Line'
            WITH SYSTEM_MODE
        ]) {
            lineIds.add(line.Id);
        }
        return lineIds;
    }

    /** Users seated (active seat) in the caller's scope, plus the caller. Null when unrestricted. */
    public static Set<Id> getScopedUserIds() {
        Set<Id> scope = getScopedTerritoryIds();
        if (scope == null) {
            return null;
        }
        Set<Id> userIds = new Set<Id>{ UserInfo.getUserId() };
        if (scope.isEmpty()) {
            return userIds;
        }
        for (UserTerritory2Association link : [
            SELECT UserId
            FROM UserTerritory2Association
            WHERE Territory2Id IN :scope AND IsActive = TRUE
            WITH SYSTEM_MODE
        ]) {
            userIds.add(link.UserId);
        }
        return userIds;
    }

    public static Boolean isInScope(Id territoryId) {
        Set<Id> scope = getScopedTerritoryIds();
        return scope == null || (territoryId != null && scope.contains(territoryId));
    }

    public static void requireInScope(Id territoryId) {
        if (!isInScope(territoryId)) {
            throw new AuraHandledException(OUT_OF_SCOPE_MESSAGE);
        }
    }

    public static Boolean isUserInScope(Id userId) {
        Set<Id> users = getScopedUserIds();
        return users == null || (userId != null && users.contains(userId));
    }

    /** The given territories plus every ancestor up to the root. */
    public static Set<Id> withAncestors(Set<Id> territoryIds) {
        Set<Id> result = new Set<Id>();
        if (territoryIds == null || territoryIds.isEmpty()) {
            return result;
        }
        result.addAll(territoryIds);
        Set<Id> frontier = new Set<Id>(territoryIds);
        // Head Office > BU > Line > District > Position: a few hops at most.
        for (Integer hop = 0; hop < 8 && !frontier.isEmpty(); hop++) {
            Set<Id> parents = new Set<Id>();
            for (Territory2 node : [
                SELECT ParentTerritory2Id
                FROM Territory2
                WHERE Id IN :frontier AND ParentTerritory2Id != NULL
                WITH SYSTEM_MODE
            ]) {
                if (!result.contains(node.ParentTerritory2Id)) {
                    parents.add(node.ParentTerritory2Id);
                }
            }
            result.addAll(parents);
            frontier = parents;
        }
        return result;
    }

    @TestVisible
    private static void resetCache() {
        fullScopeByUser.clear();
        scopeByUser.clear();
    }
}
