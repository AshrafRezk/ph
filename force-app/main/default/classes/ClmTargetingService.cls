/**
 * Central CLM presentation targeting: decides whether a presentation is visible to the running
 * user based on lifecycle window (Start/End), territory targeting (Territory_Ids__c, matched
 * against the user's territory + ancestors so a line-targeted deck reaches its reps), and role
 * targeting (Target_Roles__c vs the user's RoleInTerritory2). Reps only see presentations
 * targeted to their territory/role; untargeted or Allow_Unaligned decks are broadcast.
 *
 * User territory/role scope is resolved once per transaction (SYSTEM_MODE) and cached.
 */
public with sharing class ClmTargetingService {
    @TestVisible
    private static Set<String> testTerritoryScope;
    @TestVisible
    private static Set<String> testRoles;

    private static Set<String> cachedTerritoryScope;
    private static Set<String> cachedRoles;
    private static Map<Id, String> targetRolesByPresentation;

    /**
     * Target_Roles__c is a new field without broad FLS, so rep-facing queries run WITH USER_MODE
     * cannot select it. Read it here: use the in-memory value when the field was populated
     * (tests / callers that selected it), otherwise load it once in SYSTEM_MODE keyed by Id.
     */
    private static Set<String> targetRolesFor(CLM_Presentation__c pres) {
        if (pres.getPopulatedFieldsAsMap().containsKey('Target_Roles__c')) {
            return parseJsonStrings((String) pres.get('Target_Roles__c'));
        }
        if (pres.Id == null) {
            return new Set<String>();
        }
        if (targetRolesByPresentation == null) {
            targetRolesByPresentation = new Map<Id, String>();
            for (CLM_Presentation__c row : [
                SELECT Id, Target_Roles__c FROM CLM_Presentation__c WITH SYSTEM_MODE LIMIT 10000
            ]) {
                targetRolesByPresentation.put(row.Id, row.Target_Roles__c);
            }
        }
        return parseJsonStrings(targetRolesByPresentation.get(pres.Id));
    }

    /** Filters a list to only the presentations visible to the running user. */
    public static List<CLM_Presentation__c> filterVisible(List<CLM_Presentation__c> presentations) {
        List<CLM_Presentation__c> visible = new List<CLM_Presentation__c>();
        if (presentations == null) {
            return visible;
        }
        Date today = Date.today();
        for (CLM_Presentation__c pres : presentations) {
            if (isInDateWindow(pres, today) && matchesTargeting(pres)) {
                visible.add(pres);
            }
        }
        return visible;
    }

    public static Boolean isVisible(CLM_Presentation__c pres) {
        return isInDateWindow(pres, Date.today()) && matchesTargeting(pres);
    }

    public static Boolean isInDateWindow(CLM_Presentation__c pres, Date today) {
        if (pres.Start_Date__c != null && today < pres.Start_Date__c) {
            return false;
        }
        if (pres.End_Date__c != null && today > pres.End_Date__c) {
            return false;
        }
        return true;
    }

    /** Territory/role match (ignores date window). */
    public static Boolean matchesTargeting(CLM_Presentation__c pres) {
        if (pres.Allow_Unaligned__c == true) {
            return true;
        }
        Set<String> targetTerritories = parseJsonStrings(pres.Territory_Ids__c);
        Set<String> targetRoles = targetRolesFor(pres);
        if (targetTerritories.isEmpty() && targetRoles.isEmpty()) {
            // Untargeted content is visible to everyone.
            return true;
        }
        if (!targetTerritories.isEmpty()) {
            for (String territoryId : resolveUserTerritoryScope()) {
                if (targetTerritories.contains(territoryId)) {
                    return true;
                }
            }
        }
        if (!targetRoles.isEmpty()) {
            for (String role : resolveUserRoles()) {
                if (targetRoles.contains(role)) {
                    return true;
                }
            }
        }
        return false;
    }

    /** The running user's territory ids plus all ancestors (so line-level targeting reaches reps). */
    private static Set<String> resolveUserTerritoryScope() {
        if (testTerritoryScope != null) {
            return testTerritoryScope;
        }
        if (cachedTerritoryScope != null) {
            return cachedTerritoryScope;
        }
        Set<Id> frontier = new Set<Id>();
        for (UserTerritory2Association assignment : [
            SELECT Territory2Id
            FROM UserTerritory2Association
            WHERE UserId = :UserInfo.getUserId()
            WITH SYSTEM_MODE
        ]) {
            frontier.add(assignment.Territory2Id);
        }
        Set<Id> scope = new Set<Id>(frontier);
        Integer guard = 0;
        while (!frontier.isEmpty() && guard < 10) {
            Set<Id> parents = new Set<Id>();
            for (Territory2 territory : [
                SELECT ParentTerritory2Id
                FROM Territory2
                WHERE Id IN :frontier AND ParentTerritory2Id != NULL
                WITH SYSTEM_MODE
            ]) {
                if (!scope.contains(territory.ParentTerritory2Id)) {
                    parents.add(territory.ParentTerritory2Id);
                    scope.add(territory.ParentTerritory2Id);
                }
            }
            frontier = parents;
            guard++;
        }
        cachedTerritoryScope = new Set<String>();
        for (Id territoryId : scope) {
            cachedTerritoryScope.add(String.valueOf(territoryId));
        }
        return cachedTerritoryScope;
    }

    private static Set<String> resolveUserRoles() {
        if (testRoles != null) {
            return testRoles;
        }
        if (cachedRoles != null) {
            return cachedRoles;
        }
        cachedRoles = new Set<String>();
        for (UserTerritory2Association assignment : [
            SELECT RoleInTerritory2
            FROM UserTerritory2Association
            WHERE UserId = :UserInfo.getUserId() AND RoleInTerritory2 != NULL
            WITH SYSTEM_MODE
        ]) {
            cachedRoles.add(assignment.RoleInTerritory2);
        }
        return cachedRoles;
    }

    @TestVisible
    private static Set<String> parseJsonStrings(String raw) {
        Set<String> values = new Set<String>();
        if (String.isBlank(raw)) {
            return values;
        }
        try {
            for (Object item : (List<Object>) JSON.deserializeUntyped(raw)) {
                if (item != null && String.isNotBlank(String.valueOf(item))) {
                    values.add(String.valueOf(item).trim());
                }
            }
            return values;
        } catch (Exception ignored) {
            // Fall back to delimited parsing for non-JSON legacy values.
        }
        for (String token : raw.split('[,;\\n]')) {
            if (String.isNotBlank(token)) {
                values.add(token.trim());
            }
        }
        return values;
    }
}