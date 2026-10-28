public with sharing class VisitActorAccess {
    private static final Set<String> MANAGER_ROLES = new Set<String>{
        'District Manager',
        'Region Manager',
        'Line Manager',
        'NSM',
        'Area Manager',
        'National Sales Manager',
        'Business Unit Manager'
    };
    private static final Set<String> SFE_ROLES = new Set<String>{
        'SFE',
        'Sales Force Excellence'
    };

    @TestVisible
    private static Boolean testCanEditSchedule;
    @TestVisible
    private static Boolean testCanViewServiceRequests;

    public static Boolean canEditVisitSchedule() {
        if (Test.isRunningTest() && testCanEditSchedule != null) {
            return testCanEditSchedule;
        }
        return isSystemAdmin() || matchesRole(SFE_ROLES) || matchesRole(MANAGER_ROLES);
    }

    @TestVisible
    private static Boolean testCanEditVisitDate;

    /**
     * SFE override: may move a visit to a past day in the planner. Granted through the
     * Edit_Visit_Date custom permission (assigned in the Pharma SFE permission set).
     */
    public static Boolean canEditVisitDate() {
        if (Test.isRunningTest() && testCanEditVisitDate != null) {
            return testCanEditVisitDate;
        }
        return FeatureManagement.checkPermission('Edit_Visit_Date');
    }

    public static Boolean canViewServiceRequests() {
        if (Test.isRunningTest() && testCanViewServiceRequests != null) {
            return testCanViewServiceRequests;
        }
        return isSystemAdmin() || matchesRole(MANAGER_ROLES);
    }

    private static Boolean isSystemAdmin() {
        String profileName = currentUser().Profile != null ? currentUser().Profile.Name : null;
        return profileName == 'System Administrator';
    }

    private static Boolean matchesRole(Set<String> roles) {
        String assignmentRole = TerritoryManagementController.resolveAssignmentRole(UserInfo.getUserId());
        if (roles.contains(assignmentRole)) {
            return true;
        }
        for (String territoryRole : territoryRoles()) {
            if (roles.contains(territoryRole)) {
                return true;
            }
        }
        return false;
    }

    private static User cachedUser;
    private static User currentUser() {
        if (cachedUser == null || cachedUser.Id != UserInfo.getUserId()) {
            cachedUser = [
                SELECT Profile.Name
                FROM User
                WHERE Id = :UserInfo.getUserId()
                LIMIT 1
            ];
        }
        return cachedUser;
    }

    private static Set<String> cachedRoles;
    private static Id cachedRoleUserId;
    private static Set<String> territoryRoles() {
        if (cachedRoles == null || cachedRoleUserId != UserInfo.getUserId()) {
            cachedRoles = new Set<String>();
            cachedRoleUserId = UserInfo.getUserId();
            for (UserTerritory2Association assignment : [
                SELECT RoleInTerritory2
                FROM UserTerritory2Association
                WHERE UserId = :UserInfo.getUserId() AND RoleInTerritory2 != NULL
                WITH SYSTEM_MODE
            ]) {
                cachedRoles.add(assignment.RoleInTerritory2);
            }
        }
        return cachedRoles;
    }
}