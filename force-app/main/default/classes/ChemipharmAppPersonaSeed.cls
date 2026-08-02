public without sharing class ChemipharmAppPersonaSeed {

    public class SeedResult {
        public Integer assignmentsCreated = 0;
        public String message;
    }

    /**
     * Assigns Pharma permission set groups to demo territory users.
     * MR users -> Pharma_Field_Rep_PSG
     * DM users -> Pharma_District_Manager_PSG
     * Run after deploying three-app metadata.
     */
    public static SeedResult assignDemoPersonas() {
        SeedResult result = new SeedResult();
        Map<String, Id> psgIds = loadPermissionSetGroupIds();
        Map<String, Id> userIds = loadDemoUserIds();

        assignGroup(result, psgIds.get('Pharma_Field_Rep_PSG'), userIds, new List<String>{
            'git_mr', 'cns_mr', 'rheum_mr', 'cardio_mr', 'chc_mr'
        });
        assignGroup(result, psgIds.get('Pharma_District_Manager_PSG'), userIds, new List<String>{
            'git_dm', 'cns_dm', 'rheum_dm', 'cardio_dm', 'chc_dm'
        });

        result.message = 'Assigned ' + result.assignmentsCreated + ' permission set group memberships.';
        return result;
    }

    private static void assignGroup(
        SeedResult result,
        Id groupId,
        Map<String, Id> userIds,
        List<String> userKeys
    ) {
        if (groupId == null) {
            return;
        }
        for (String key : userKeys) {
            Id userId = userIds.get(key);
            if (userId == null) {
                continue;
            }
            if (hasGroupAssignment(userId, groupId)) {
                continue;
            }
            insert as system new PermissionSetAssignment(
                AssigneeId = userId,
                PermissionSetGroupId = groupId
            );
            result.assignmentsCreated++;
        }
    }

    private static Boolean hasGroupAssignment(Id userId, Id groupId) {
        return ![SELECT Id FROM PermissionSetAssignment
            WHERE AssigneeId = :userId AND PermissionSetGroupId = :groupId
            WITH SYSTEM_MODE LIMIT 1].isEmpty();
    }

    private static Map<String, Id> loadPermissionSetGroupIds() {
        Map<String, Id> result = new Map<String, Id>();
        for (PermissionSetGroup psg : [
            SELECT Id, DeveloperName
            FROM PermissionSetGroup
            WHERE DeveloperName IN (
                'Pharma_Field_Rep_PSG',
                'Pharma_District_Manager_PSG',
                'Pharma_Region_Manager_PSG',
                'Pharma_C_Level_PSG'
            )
            WITH SYSTEM_MODE
        ]) {
            result.put(psg.DeveloperName, psg.Id);
        }
        return result;
    }

    private static Map<String, Id> loadDemoUserIds() {
        Map<String, Id> result = new Map<String, Id>();
        for (User u : [
            SELECT Id, Username
            FROM User
            WHERE Username LIKE '%@pharma.demo'
            AND IsActive = true
            WITH SYSTEM_MODE
        ]) {
            String key = resolveUserKey(u.Username);
            if (key != null) {
                result.put(key, u.Id);
            }
        }
        return result;
    }

    private static String resolveUserKey(String username) {
        if (String.isBlank(username)) {
            return null;
        }
        String lower = username.toLowerCase();
        for (String team : new List<String>{ 'git', 'cns', 'rheum', 'cardio', 'chc' }) {
            for (String role : new List<String>{ 'dm', 'mr' }) {
                if (lower.startsWith(team + '.' + role + '@')) {
                    return team + '_' + role;
                }
            }
        }
        return null;
    }
}
