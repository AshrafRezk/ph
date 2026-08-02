public without sharing class TerritoryModuleSeed {

    private static final Map<String, String> MR_TO_DM_KEY = new Map<String, String>{
        'git_mr' => 'git_dm',
        'cns_mr' => 'cns_dm',
        'rheum_mr' => 'rheum_dm',
        'cardio_mr' => 'cardio_dm',
        'chc_mr' => 'chc_dm',
        // Legacy keys kept for older seed callers
        'diabetes_mr' => 'cns_dm',
        'cluster_mr' => 'rheum_dm',
        'gastro_mr' => 'git_dm'
    };

    public class SeedResult {
        public Id modelId;
        public Map<String, Id> territoryIdsByExtId;
        public Map<String, Id> userIdsByKey;
        public String message;
    }

    /**
     * Creates Pharma territory hierarchy, demo users, and assignments.
     * Run after TerritoryModuleCleanup.run();
     */
    public static SeedResult seedTerritoriesAndUsers() {
        SeedResult result = new SeedResult();
        result.territoryIdsByExtId = new Map<String, Id>();
        result.userIdsByKey = new Map<String, Id>();

        Territory2Type territoryType = resolveTerritoryType();
        Territory2Model model = upsertModel();
        result.modelId = model.Id;

        Map<String, TerritorySpec> specs = buildTerritorySpecs();
        Map<String, Id> extIdToTerritoryId = new Map<String, Id>();

        for (String extId : specs.keySet()) {
            TerritorySpec spec = specs.get(extId);
            Id parentId = spec.parentExtId == null ? null : extIdToTerritoryId.get(spec.parentExtId);
            Territory2 territory = upsertTerritory(spec, model.Id, territoryType.Id, parentId);
            extIdToTerritoryId.put(extId, territory.Id);
        }
        result.territoryIdsByExtId = extIdToTerritoryId;

        activateModel(model.Id);
        createDemoUsers(result);
        assignUsersToTerritories(result);
        assignPermissionSets(result);
        assignAdminToHeadOffice();

        result.message = 'Seeded Chemipharm territory model with ' + result.territoryIdsByExtId.size()
            + ' territories (GIT / CNS / Rheumatology / Cardiovascular / Consumer Health).';
        return result;
    }

    public static Id getTerritoryId(String externalId) {
        List<Territory2> territories = [
            SELECT Id
            FROM Territory2
            WHERE External_ID__c = :externalId
            WITH SYSTEM_MODE
            LIMIT 1
        ];
        return territories.isEmpty() ? null : territories[0].Id;
    }

    public static List<Id> getMrTerritoryIds() {
        List<Id> territoryIds = new List<Id>();
        for (Territory2 territory : [
            SELECT Id
            FROM Territory2
            WHERE External_ID__c LIKE :(TerritoryModuleCleanup.PHARMA_EXTERNAL_ID_PREFIX + '%_MR_%')
            WITH SYSTEM_MODE
            ORDER BY External_ID__c ASC
        ]) {
            territoryIds.add(territory.Id);
        }
        return territoryIds;
    }

    /**
     * Completes user and product setup for additional product lines after territories exist.
     */
    public static SeedResult seedAdditionalProductLineUsersAndProducts() {
        SeedResult result = new SeedResult();
        result.territoryIdsByExtId = loadTerritoryIdsByExtId();
        result.userIdsByKey = new Map<String, Id>();
        createDemoUsers(result);

        List<UserTerritory2Association> assignments = new List<UserTerritory2Association>();
        addAssignment(assignments, result, 'cardio_dm', 'TERR_CARDIO_DM_1', 'District Manager');
        addAssignment(assignments, result, 'cardio_mr', 'TERR_CARDIO_DM_1_MR_1', 'Medical Rep');
        addAssignment(assignments, result, 'rheum_dm', 'TERR_RHEUM_DM_1', 'District Manager');
        addAssignment(assignments, result, 'rheum_mr', 'TERR_RHEUM_DM_1_MR_1', 'Medical Rep');
        if (!assignments.isEmpty()) {
            insert as system assignments;
        }

        assignPermissionSets(result);
        result.message = 'Seeded cardio/rheum demo users and assignments.';
        return result;
    }

    /**
     * Adds Cardiovascular and Rheumatology territories only (run before users/products).
     */
    public static SeedResult seedAdditionalProductLineTerritories() {
        SeedResult result = new SeedResult();
        result.territoryIdsByExtId = loadTerritoryIdsByExtId();

        if (!result.territoryIdsByExtId.containsKey('TERR_CARDIO')) {
            TerritoryAdminService.createProductLine('Cardiovascular', 'CARDIO', null);
        }
        if (!result.territoryIdsByExtId.containsKey('TERR_RHEUM')) {
            TerritoryAdminService.createProductLine('Rheumatology', 'RHEUM', null);
        }

        result.message = 'Seeded Cardiovascular and Rheumatology territories.';
        return result;
    }

    /**
     * Realigns demo users to the Pharma territory tree without recreating territories.
     * Updates demo user names/titles, clears stale assignments, and reapplies the roster.
     */
    public static SeedResult realignTerritoryAssignments() {
        SeedResult result = new SeedResult();
        result.territoryIdsByExtId = loadTerritoryIdsByExtId();
        result.userIdsByKey = new Map<String, Id>();
        createDemoUsers(result);
        clearPharmaTerritoryAssignments();
        assignUsersToTerritories(result);
        assignAdminToHeadOffice();
        result.message = 'Realigned Pharma territory assignments.';
        return result;
    }

    /**
     * Sets User.ManagerId for each demo MR to its paired DM (e.g. diabetes_mr -> diabetes_dm).
     * Safe to run after reseed-zeta-demo-names or any partial demo user refresh.
     */
    public static Integer assignDemoUserManagersFromOrg() {
        SeedResult result = new SeedResult();
        result.userIdsByKey = loadExistingDemoUserIdsByKey();
        return assignDemoUserManagers(result);
    }

    /**
     * Assigns admin@pharma.eg (Karim Ahmed, SFE) to Head Office for territory switching
     * and full planner account visibility across the hierarchy.
     */
    public static void assignAdminToHeadOffice() {
        Id headOfficeId = getTerritoryId('TERR_HEAD_OFFICE');
        if (headOfficeId == null) {
            return;
        }

        List<User> admins = [
            SELECT Id
            FROM User
            WHERE Username = 'admin@pharma.eg' AND IsActive = TRUE
            WITH SYSTEM_MODE
            LIMIT 1
        ];
        if (admins.isEmpty()) {
            return;
        }

        Id adminUserId = admins[0].Id;
        User adminUser = new User(Id = adminUserId, Title = 'SFE');
        update as system adminUser;

        List<UserTerritory2Association> existing = [
            SELECT Id, RoleInTerritory2
            FROM UserTerritory2Association
            WHERE UserId = :adminUserId AND Territory2Id = :headOfficeId
            WITH SYSTEM_MODE
            LIMIT 1
        ];
        if (!existing.isEmpty()) {
            UserTerritory2Association assignment = existing[0];
            if (assignment.RoleInTerritory2 != 'SFE') {
                assignment.RoleInTerritory2 = 'SFE';
                update as system assignment;
            }
        } else {
            insert as system new UserTerritory2Association(
                UserId = adminUserId,
                Territory2Id = headOfficeId,
                RoleInTerritory2 = 'SFE'
            );
        }

        ensureAdminPlanCycle();
    }

    /**
     * Provisions the current-month plan cycle for admin@pharma.eg so Accounts tab
     * and planner modules show realistic in-plan coverage during SFE testing.
     */
    public static void ensureAdminPlanCycle() {
        List<User> admins = [
            SELECT Id
            FROM User
            WHERE Username = 'admin@pharma.eg' AND IsActive = TRUE
            WITH SYSTEM_MODE
            LIMIT 1
        ];
        if (admins.isEmpty()) {
            return;
        }

        Date monthStart = Date.today().toStartOfMonth();
        Employee_Time_Card__c timeCard = EmployeeTimeCardService.ensureMonthlyTimeCard(
            admins[0].Id,
            monthStart,
            true,
            true
        );
        if (timeCard != null) {
            EmployeeTimeCardService.syncAccountTargets(timeCard.Id);
        }
    }

    private class TerritorySpec {
        public String externalId;
        public String name;
        public String developerName;
        public String parentExtId;
    }

    private static Map<String, TerritorySpec> buildTerritorySpecs() {
        Map<String, TerritorySpec> specs = new Map<String, TerritorySpec>();
        addSpec(specs, 'TERR_HEAD_OFFICE', 'Head Office', 'Head_Office', null);
        addSpec(specs, 'TERR_GIT', 'GIT', 'GIT', 'TERR_HEAD_OFFICE');
        addSpec(specs, 'TERR_CNS', 'CNS', 'CNS', 'TERR_HEAD_OFFICE');
        addSpec(specs, 'TERR_RHEUM', 'Rheumatology', 'Rheumatology', 'TERR_HEAD_OFFICE');
        addSpec(specs, 'TERR_CARDIO', 'Cardiovascular', 'Cardiovascular', 'TERR_HEAD_OFFICE');
        addSpec(specs, 'TERR_CHC', 'Consumer Health', 'Consumer_Health', 'TERR_HEAD_OFFICE');
        addSpec(specs, 'TERR_GIT_DM_1', 'GIT_DM_1', 'GIT_DM_1', 'TERR_GIT');
        addSpec(specs, 'TERR_CNS_DM_1', 'CNS_DM_1', 'CNS_DM_1', 'TERR_CNS');
        addSpec(specs, 'TERR_RHEUM_DM_1', 'Rheum_DM_1', 'Rheum_DM_1', 'TERR_RHEUM');
        addSpec(specs, 'TERR_CARDIO_DM_1', 'Cardio_DM_1', 'Cardio_DM_1', 'TERR_CARDIO');
        addSpec(specs, 'TERR_CHC_DM_1', 'CHC_DM_1', 'CHC_DM_1', 'TERR_CHC');
        addSpec(specs, 'TERR_GIT_DM_1_MR_1', 'GIT_DM_1_MR_1', 'GIT_DM_1_MR_1', 'TERR_GIT_DM_1');
        addSpec(specs, 'TERR_CNS_DM_1_MR_1', 'CNS_DM_1_MR_1', 'CNS_DM_1_MR_1', 'TERR_CNS_DM_1');
        addSpec(specs, 'TERR_RHEUM_DM_1_MR_1', 'Rheum_DM_1_MR_1', 'Rheum_DM_1_MR_1', 'TERR_RHEUM_DM_1');
        addSpec(specs, 'TERR_CARDIO_DM_1_MR_1', 'Cardio_DM_1_MR_1', 'Cardio_DM_1_MR_1', 'TERR_CARDIO_DM_1');
        addSpec(specs, 'TERR_CHC_DM_1_MR_1', 'CHC_DM_1_MR_1', 'CHC_DM_1_MR_1', 'TERR_CHC_DM_1');
        return specs;
    }

    private static void addSpec(
        Map<String, TerritorySpec> specs,
        String externalId,
        String name,
        String developerName,
        String parentExtId
    ) {
        TerritorySpec spec = new TerritorySpec();
        spec.externalId = externalId;
        spec.name = name;
        spec.developerName = developerName;
        spec.parentExtId = parentExtId;
        specs.put(externalId, spec);
    }

    private static Territory2Type resolveTerritoryType() {
        List<Territory2Type> types = [
            SELECT Id, DeveloperName
            FROM Territory2Type
            WITH SYSTEM_MODE
            LIMIT 1
        ];
        if (types.isEmpty()) {
            throw new AuraHandledException('No Territory2Type found. Enable Enterprise Territory Management first.');
        }
        return types[0];
    }

    private static Territory2Model upsertModel() {
        List<Territory2Model> existing = [
            SELECT Id, State, Name
            FROM Territory2Model
            WHERE DeveloperName = 'Current_FY'
            WITH SYSTEM_MODE
            LIMIT 1
        ];
        if (existing.isEmpty()) {
            throw new AuraHandledException('Current_FY territory model not found.');
        }
        Territory2Model model = existing[0];
        model.Name = 'Pharma Field Force';
        update as system model;
        return model;
    }

    private static Territory2 upsertTerritory(
        TerritorySpec spec,
        Id modelId,
        Id typeId,
        Id parentId
    ) {
        List<Territory2> existing = [
            SELECT Id, Name, ParentTerritory2Id
            FROM Territory2
            WHERE External_ID__c = :spec.externalId
            WITH SYSTEM_MODE
            LIMIT 1
        ];
        if (!existing.isEmpty()) {
            Territory2 territory = existing[0];
            territory.Name = spec.name;
            territory.ParentTerritory2Id = parentId;
            update as system territory;
            return territory;
        }
        Territory2 territory = new Territory2(
            Name = spec.name,
            DeveloperName = spec.developerName,
            Territory2ModelId = modelId,
            Territory2TypeId = typeId,
            ParentTerritory2Id = parentId,
            External_ID__c = spec.externalId
        );
        insert as system territory;
        return territory;
    }

    private static void activateModel(Id modelId) {
        // Territory model activation from Planning to Active must be done in Setup when required.
    }

    private static void createDemoUsers(SeedResult result) {
        Profile userProfile = [
            SELECT Id
            FROM Profile
            WHERE Name = 'Standard User'
            WITH SYSTEM_MODE
            LIMIT 1
        ];

        List<UserSpec> userSpecs = buildUserSpecs();

        for (UserSpec spec : userSpecs) {
            String username = spec.team + '.' + spec.roleKey + '@pharma.demo';
            List<User> existing = [
                SELECT Id, FirstName, LastName, Title, Department
                FROM User
                WHERE Username = :username
                WITH SYSTEM_MODE
                LIMIT 1
            ];
            if (!existing.isEmpty()) {
                User demoUser = existing[0];
                Boolean needsUpdate = demoUser.FirstName != spec.firstName
                    || demoUser.LastName != spec.lastName
                    || demoUser.Title != spec.roleLabel
                    || demoUser.Department != spec.team.toUpperCase();
                if (needsUpdate) {
                    demoUser.FirstName = spec.firstName;
                    demoUser.LastName = spec.lastName;
                    demoUser.Title = spec.roleLabel;
                    demoUser.Department = spec.team.toUpperCase();
                    update as system demoUser;
                }
                result.userIdsByKey.put(spec.team + '_' + spec.roleKey, demoUser.Id);
                continue;
            }

            User demoUser = new User(
                Username = username,
                Email = spec.team + '.' + spec.roleKey + '@pharma.eg',
                FirstName = spec.firstName,
                LastName = spec.lastName,
                Title = spec.roleLabel,
                Department = spec.team.toUpperCase(),
                Alias = (spec.team + spec.roleKey).left(8),
                TimeZoneSidKey = 'America/New_York',
                LocaleSidKey = 'en_US',
                EmailEncodingKey = 'UTF-8',
                LanguageLocaleKey = 'en_US',
                ProfileId = userProfile.Id,
                CommunityNickname = (spec.team + spec.roleKey + String.valueOf(Crypto.getRandomInteger())).left(40)
            );
            insert as system demoUser;
            result.userIdsByKey.put(spec.team + '_' + spec.roleKey, demoUser.Id);
        }
        assignDemoUserManagers(result);
    }

    private static Integer assignDemoUserManagers(SeedResult result) {
        List<User> managerUpdates = new List<User>();
        for (String mrKey : MR_TO_DM_KEY.keySet()) {
            String dmKey = MR_TO_DM_KEY.get(mrKey);
            if (!result.userIdsByKey.containsKey(mrKey) || !result.userIdsByKey.containsKey(dmKey)) {
                continue;
            }
            Id mrId = result.userIdsByKey.get(mrKey);
            Id dmId = result.userIdsByKey.get(dmKey);
            List<User> reps = [
                SELECT Id, ManagerId
                FROM User
                WHERE Id = :mrId
                WITH SYSTEM_MODE
                LIMIT 1
            ];
            if (reps.isEmpty() || reps[0].ManagerId == dmId) {
                continue;
            }
            managerUpdates.add(new User(Id = mrId, ManagerId = dmId));
        }
        if (!managerUpdates.isEmpty()) {
            update as system managerUpdates;
        }
        return managerUpdates.size();
    }

    private static Map<String, Id> loadExistingDemoUserIdsByKey() {
        Map<String, Id> userIdsByKey = new Map<String, Id>();
        for (String demoUserKey : ChemipharmDemoDataProfiles.getAllDemoUserKeys()) {
            String username = demoUserKey.replace('_', '.') + '@pharma.demo';
            List<User> users = [
                SELECT Id
                FROM User
                WHERE Username = :username
                WITH SYSTEM_MODE
                LIMIT 1
            ];
            if (!users.isEmpty()) {
                userIdsByKey.put(demoUserKey, users[0].Id);
            }
        }
        return userIdsByKey;
    }

    private static List<UserSpec> buildUserSpecs() {
        List<UserSpec> specs = new List<UserSpec>();
        for (String demoUserKey : ChemipharmDemoDataProfiles.getAllDemoUserKeys()) {
            ChemipharmDemoDataProfiles.DemoUserProfile profile = ChemipharmDemoDataProfiles.getUserProfile(demoUserKey);
            if (profile == null) {
                continue;
            }
            List<String> keyParts = demoUserKey.split('_');
            if (keyParts.size() < 2) {
                continue;
            }
            String team = keyParts[0];
            String roleKey = keyParts[1];
            specs.add(new UserSpec(
                team,
                roleKey,
                profile.roleLabel,
                profile.firstName,
                profile.lastName
            ));
        }
        return specs;
    }

    private class UserSpec {
        public String team;
        public String roleKey;
        public String roleLabel;
        public String firstName;
        public String lastName;

        public UserSpec(String team, String roleKey, String roleLabel, String firstName, String lastName) {
            this.team = team;
            this.roleKey = roleKey;
            this.roleLabel = roleLabel;
            this.firstName = firstName;
            this.lastName = lastName;
        }
    }

    private static void assignUsersToTerritories(SeedResult result) {
        List<UserTerritory2Association> assignments = new List<UserTerritory2Association>();
        addAssignment(assignments, result, 'git_dm', 'TERR_GIT_DM_1', 'District Manager');
        addAssignment(assignments, result, 'git_mr', 'TERR_GIT_DM_1_MR_1', 'Medical Rep');
        addAssignment(assignments, result, 'cns_dm', 'TERR_CNS_DM_1', 'District Manager');
        addAssignment(assignments, result, 'cns_mr', 'TERR_CNS_DM_1_MR_1', 'Medical Rep');
        addAssignment(assignments, result, 'rheum_dm', 'TERR_RHEUM_DM_1', 'District Manager');
        addAssignment(assignments, result, 'rheum_mr', 'TERR_RHEUM_DM_1_MR_1', 'Medical Rep');
        addAssignment(assignments, result, 'cardio_dm', 'TERR_CARDIO_DM_1', 'District Manager');
        addAssignment(assignments, result, 'cardio_mr', 'TERR_CARDIO_DM_1_MR_1', 'Medical Rep');
        addAssignment(assignments, result, 'chc_dm', 'TERR_CHC_DM_1', 'District Manager');
        addAssignment(assignments, result, 'chc_mr', 'TERR_CHC_DM_1_MR_1', 'Medical Rep');

        if (!assignments.isEmpty()) {
            insert as system assignments;
        }
    }

    private static void addAssignment(
        List<UserTerritory2Association> assignments,
        SeedResult result,
        String userKey,
        String territoryExtId,
        String role
    ) {
        if (!result.userIdsByKey.containsKey(userKey) || !result.territoryIdsByExtId.containsKey(territoryExtId)) {
            return;
        }
        Id userId = result.userIdsByKey.get(userKey);
        Id territoryId = result.territoryIdsByExtId.get(territoryExtId);
        List<UserTerritory2Association> existing = [
            SELECT Id, RoleInTerritory2
            FROM UserTerritory2Association
            WHERE UserId = :userId AND Territory2Id = :territoryId
            WITH SYSTEM_MODE
            LIMIT 1
        ];
        if (!existing.isEmpty()) {
            if (existing[0].RoleInTerritory2 != role) {
                existing[0].RoleInTerritory2 = role;
                update as system existing[0];
            }
            return;
        }
        assignments.add(new UserTerritory2Association(
            UserId = userId,
            Territory2Id = territoryId,
            RoleInTerritory2 = role
        ));
    }

    private static Map<String, Id> loadTerritoryIdsByExtId() {
        Map<String, Id> result = new Map<String, Id>();
        String pharmaPrefix = TerritoryModuleCleanup.PHARMA_EXTERNAL_ID_PREFIX + '%';
        for (Territory2 territory : [
            SELECT Id, External_ID__c
            FROM Territory2
            WHERE External_ID__c LIKE :pharmaPrefix
            WITH SYSTEM_MODE
        ]) {
            result.put(territory.External_ID__c, territory.Id);
        }
        return result;
    }

    private static void clearPharmaTerritoryAssignments() {
        String pharmaPrefix = TerritoryModuleCleanup.PHARMA_EXTERNAL_ID_PREFIX + '%';
        List<UserTerritory2Association> toDelete = [
            SELECT Id
            FROM UserTerritory2Association
            WHERE Territory2.External_ID__c LIKE :pharmaPrefix
            WITH SYSTEM_MODE
        ];
        if (!toDelete.isEmpty()) {
            delete as system toDelete;
        }
    }

    private static void assignPermissionSets(SeedResult result) {
        List<PermissionSet> permSets = [
            SELECT Id
            FROM PermissionSet
            WHERE Name = 'Account_Affiliation_Module'
            WITH SYSTEM_MODE
            LIMIT 1
        ];
        if (permSets.isEmpty()) {
            return;
        }
        Id permSetId = permSets[0].Id;
        Set<Id> assigneeIds = new Set<Id>(result.userIdsByKey.values());
        Set<Id> alreadyAssigned = new Set<Id>();
        for (PermissionSetAssignment psa : [
            SELECT AssigneeId
            FROM PermissionSetAssignment
            WHERE PermissionSetId = :permSetId AND AssigneeId IN :assigneeIds
            WITH SYSTEM_MODE
        ]) {
            alreadyAssigned.add(psa.AssigneeId);
        }
        List<PermissionSetAssignment> toInsert = new List<PermissionSetAssignment>();
        for (Id userId : assigneeIds) {
            if (!alreadyAssigned.contains(userId)) {
                toInsert.add(new PermissionSetAssignment(AssigneeId = userId, PermissionSetId = permSetId));
            }
        }
        if (!toInsert.isEmpty()) {
            insert as system toInsert;
        }
    }
}
