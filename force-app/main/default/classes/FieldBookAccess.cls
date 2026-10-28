/**
 * Decides whether the running user works only their own territory book.
 * System administrators and head-office roles can still open the full book.
 * A medical rep cannot, even if a head-office assignment was added by mistake.
 */
public with sharing class FieldBookAccess {
    private static final Set<String> WIDER_ROLES = new Set<String>{
        'District Manager',
        'Region Manager',
        'Line Manager',
        'NSM',
        'Area Manager',
        'National Sales Manager',
        'Business Unit Manager',
        'Brand Manager',
        'SFE',
        'Sales Force Excellence',
        'Trainer'
    };

    public class BookMode {
        @AuraEnabled public Boolean ownBookOnly;
        @AuraEnabled public Boolean canOpenFullBook;
        // SFE (and admins) see the whole book by default, without a Head Office seat.
        @AuraEnabled public Boolean fullBookByDefault;
    }

    @AuraEnabled(cacheable=true)
    public static BookMode getBookMode() {
        BookMode mode = new BookMode();
        mode.ownBookOnly = restrictsToOwnBook();
        mode.fullBookByDefault = isSfeUser();
        mode.canOpenFullBook = !mode.ownBookOnly && (mode.fullBookByDefault || hasHeadOfficeAssignment());
        return mode;
    }

    public static Boolean restrictsToOwnBook() {
        if (isSfeUser()) {
            return false;
        }
        if (explicitMedicalRep()) {
            return !hasWiderTerritoryRole();
        }
        Set<String> roles = territoryRoles();
        if (!roles.contains('Medical Rep')) {
            return false;
        }
        for (String role : roles) {
            if (WIDER_ROLES.contains(role)) {
                return false;
            }
        }
        return true;
    }

    /**
     * Same SFE test as Class Engine: the Merge_Account_Duplicates permission, an SFE
     * classification approver row, an SFE title, or a system administrator.
     */
    public static Boolean isSfeUser() {
        if (cachedIsSfe == null || cachedSfeUserId != UserInfo.getUserId()) {
            cachedSfeUserId = UserInfo.getUserId();
            cachedIsSfe = computeIsSfeUser();
        }
        return cachedIsSfe;
    }

    private static Boolean cachedIsSfe;
    private static Id cachedSfeUserId;
    private static Boolean computeIsSfeUser() {
        if (isSystemAdmin()) {
            return true;
        }
        try {
            if (FeatureManagement.checkPermission('Merge_Account_Duplicates')) {
                return true;
            }
        } catch (Exception ignore) {
        }
        if (SfeApproverService.isApprover(UserInfo.getUserId(), SfeApproverService.CLASSIFICATION)) {
            return true;
        }
        String title = currentUser().Title == null ? '' : currentUser().Title.toLowerCase();
        return Pattern.matches('.*\\bsfe\\b.*', title) || title.contains('sales force excellence');
    }

    public static Boolean canAdministerSales() {
        if (isSystemAdmin()) {
            return true;
        }
        String title = currentUser().Title == null ? '' : currentUser().Title.trim().toLowerCase();
        return title == 'sfe'
            || title == 'sales force excellence'
            || title.contains('admin')
            || title.contains('super user');
    }

    public static void assertCanAdministerSales() {
        if (!canAdministerSales()) {
            throw new AuraHandledException('Only a super admin can change sales setup.');
        }
    }

    private static Boolean explicitMedicalRep() {
        User userRecord = currentUser();
        String title = userRecord.Title == null ? '' : userRecord.Title.trim().toLowerCase();
        if (title == 'medical rep' || title == 'medical representative' || title == 'mr') {
            return true;
        }
        String username = userRecord.Username == null ? '' : userRecord.Username.toLowerCase();
        return username.endsWith('.mr@pharma.demo') || username.endsWith('.mr@pharma.eg');
    }

    private static Boolean hasWiderTerritoryRole() {
        for (String role : territoryRoles()) {
            if (WIDER_ROLES.contains(role)) {
                return true;
            }
        }
        return false;
    }

    private static Boolean hasHeadOfficeAssignment() {
        List<Territory2> offices = [
            SELECT Id
            FROM Territory2
            WHERE External_ID__c = 'TERR_HEAD_OFFICE'
            WITH SYSTEM_MODE
            LIMIT 1
        ];
        if (offices.isEmpty()) {
            return false;
        }
        Integer matches = [
            SELECT COUNT()
            FROM UserTerritory2Association
            WHERE UserId = :UserInfo.getUserId() AND Territory2Id = :offices[0].Id
            WITH SYSTEM_MODE
        ];
        return matches > 0;
    }

    private static Boolean isSystemAdmin() {
        String profileName = currentUser().Profile != null ? currentUser().Profile.Name : null;
        return profileName == 'System Administrator';
    }

    private static User cachedUser;
    private static User currentUser() {
        if (cachedUser == null || cachedUser.Id != UserInfo.getUserId()) {
            cachedUser = [
                SELECT Title, Username, Profile.Name
                FROM User
                WHERE Id = :UserInfo.getUserId()
                WITH SYSTEM_MODE
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
