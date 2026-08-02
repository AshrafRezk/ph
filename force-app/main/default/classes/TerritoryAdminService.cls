public without sharing class TerritoryAdminService {

    private static final String PHARMA_PREFIX = TerritoryModuleCleanup.PHARMA_EXTERNAL_ID_PREFIX;

    private static final Map<String, String> LINE_THERAPY_AREAS = new Map<String, String>{
        'TERR_GIT' => 'Gastroenterology',
        'TERR_CNS' => 'Neurology',
        'TERR_RHEUM' => 'Rheumatology',
        'TERR_CARDIO' => 'Cardiovascular',
        'TERR_CHC' => 'Consumer Health'
    };

    public class LineSummary {
        @AuraEnabled public Id id;
        @AuraEnabled public String name;
        @AuraEnabled public String externalId;
        @AuraEnabled public String therapyArea;
        @AuraEnabled public Integer districtCount;
        @AuraEnabled public Integer repCount;
        @AuraEnabled public Integer productCount;
        @AuraEnabled public Boolean isProtected;
    }

    public class TerritoryForm {
        @AuraEnabled public Id recordId;
        @AuraEnabled public String name;
        @AuraEnabled public String externalId;
        @AuraEnabled public Id parentId;
        @AuraEnabled public String level;
    }

    public class ParentOption {
        @AuraEnabled public Id id;
        @AuraEnabled public String label;
        @AuraEnabled public String level;
    }

    public class CreatedUserResult {
        @AuraEnabled public Id userId;
        @AuraEnabled public String username;
        @AuraEnabled public String message;
    }

    @AuraEnabled(cacheable=true)
    public static List<LineSummary> getProductLines() {
        Id headOfficeId = TerritoryModuleSeed.getTerritoryId('TERR_HEAD_OFFICE');
        if (headOfficeId == null) {
            return new List<LineSummary>();
        }

        List<Territory2> lines = [
            SELECT Id, Name, External_ID__c
            FROM Territory2
            WHERE ParentTerritory2Id = :headOfficeId AND External_ID__c LIKE :(PHARMA_PREFIX + '%')
            WITH SYSTEM_MODE
            ORDER BY Name ASC
        ];
        if (lines.isEmpty()) {
            return new List<LineSummary>();
        }

        Map<Id, Set<Id>> territoryIdsByLine = new Map<Id, Set<Id>>();
        Map<Id, Id> lineIdByTerritory = new Map<Id, Id>();
        for (Territory2 line : lines) {
            Set<Id> scoped = TerritoryHierarchyService.expandTerritoryHierarchy(new Set<Id>{ line.Id });
            territoryIdsByLine.put(line.Id, scoped);
            for (Id scopedId : scoped) {
                lineIdByTerritory.put(scopedId, line.Id);
            }
        }

        Set<Id> allTerritoryIds = new Set<Id>();
        for (Set<Id> scoped : territoryIdsByLine.values()) {
            allTerritoryIds.addAll(scoped);
        }

        Map<Id, Integer> districtCountByLine = new Map<Id, Integer>();
        Map<Id, Integer> repCountByLine = new Map<Id, Integer>();
        for (Territory2 territory : [
            SELECT Id, ParentTerritory2Id, External_ID__c
            FROM Territory2
            WHERE Id IN :allTerritoryIds AND External_ID__c LIKE :(PHARMA_PREFIX + '%')
            WITH SYSTEM_MODE
        ]) {
            Id lineId = lineIdByTerritory.get(territory.Id);
            if (lineId == null) {
                continue;
            }
            String level = resolveLevel(territory.External_ID__c);
            if (level == 'District') {
                districtCountByLine.put(lineId, (districtCountByLine.get(lineId) == null ? 0 : districtCountByLine.get(lineId)) + 1);
            } else if (level == 'MR') {
                repCountByLine.put(lineId, (repCountByLine.get(lineId) == null ? 0 : repCountByLine.get(lineId)) + 1);
            }
        }

        Map<Id, Integer> productCountByLine = new Map<Id, Integer>();
        Set<String> territoryIdStrings = new Set<String>();
        for (Id territoryId : allTerritoryIds) {
            territoryIdStrings.add(String.valueOf(territoryId));
        }
        for (Product_Territory_Alignment__c pta : [
            SELECT Product2_Id__c, Territory2_Id__c
            FROM Product_Territory_Alignment__c
            WHERE Territory2_Id__c IN :territoryIdStrings AND Is_Active__c = TRUE
            WITH SYSTEM_MODE
        ]) {
            Id territoryId;
            try {
                territoryId = (Id) pta.Territory2_Id__c;
            } catch (Exception ex) {
                continue;
            }
            Id lineId = lineIdByTerritory.get(territoryId);
            if (lineId == null) {
                continue;
            }
            productCountByLine.put(lineId, (productCountByLine.get(lineId) == null ? 0 : productCountByLine.get(lineId)) + 1);
        }

        List<LineSummary> summaries = new List<LineSummary>();
        for (Territory2 line : lines) {
            LineSummary summary = new LineSummary();
            summary.id = line.Id;
            summary.name = line.Name;
            summary.externalId = line.External_ID__c;
            summary.therapyArea = LINE_THERAPY_AREAS.get(line.External_ID__c);
            summary.districtCount = districtCountByLine.containsKey(line.Id) ? districtCountByLine.get(line.Id) : 0;
            summary.repCount = repCountByLine.containsKey(line.Id) ? repCountByLine.get(line.Id) : 0;
            summary.productCount = productCountByLine.containsKey(line.Id) ? productCountByLine.get(line.Id) : 0;
            summary.isProtected = line.External_ID__c == 'TERR_HEAD_OFFICE';
            summaries.add(summary);
        }
        return summaries;
    }

    @AuraEnabled(cacheable=true)
    public static List<ParentOption> getParentOptions(String childLevel) {
        List<ParentOption> options = new List<ParentOption>();
        String pharmaLike = PHARMA_PREFIX + '%';
        Id headOfficeId = TerritoryModuleSeed.getTerritoryId('TERR_HEAD_OFFICE');

        if (childLevel == 'Line') {
            if (headOfficeId != null) {
                options.add(buildParentOption(headOfficeId, 'Head Office', 'Head Office'));
            }
            return options;
        }

        if (childLevel == 'District') {
            if (headOfficeId == null) {
                return options;
            }
            for (Territory2 line : [
                SELECT Id, Name
                FROM Territory2
                WHERE ParentTerritory2Id = :headOfficeId AND External_ID__c LIKE :pharmaLike
                WITH SYSTEM_MODE
                ORDER BY Name ASC
            ]) {
                options.add(buildParentOption(line.Id, line.Name, 'Line'));
            }
            return options;
        }

        if (childLevel == 'MR') {
            String districtPattern = PHARMA_PREFIX + '%_DM_%';
            for (Territory2 district : [
                SELECT Id, Name, External_ID__c
                FROM Territory2
                WHERE External_ID__c LIKE :districtPattern
                WITH SYSTEM_MODE
                ORDER BY Name ASC
            ]) {
                if (district.External_ID__c != null && district.External_ID__c.contains('_MR_')) {
                    continue;
                }
                options.add(buildParentOption(district.Id, district.Name, 'District'));
            }
        }
        return options;
    }

    @AuraEnabled
    public static Id saveTerritory(TerritoryForm form) {
        validateTerritoryForm(form);
        Territory2Type territoryType = resolveTerritoryType();
        Territory2Model model = resolveModel();

        if (form.recordId != null) {
            Territory2 territory = [
                SELECT Id, Name, External_ID__c, ParentTerritory2Id
                FROM Territory2
                WHERE Id = :form.recordId
                WITH SYSTEM_MODE
                LIMIT 1
            ];
            assertPharmaTerritory(territory.External_ID__c);
            if (territory.External_ID__c == 'TERR_HEAD_OFFICE') {
                throw new AuraHandledException('Head Office cannot be edited.');
            }
            territory.Name = form.name.trim();
            if (String.isNotBlank(form.externalId)) {
                territory.External_ID__c = normalizeExternalId(form.externalId);
            }
            if (form.parentId != null) {
                territory.ParentTerritory2Id = form.parentId;
            }
            update as system territory;
            return territory.Id;
        }

        String externalId = normalizeExternalId(form.externalId);
        assertUniqueExternalId(externalId, null);
        Id parentId = form.parentId;
        if (parentId == null && form.level == 'Line') {
            parentId = TerritoryModuleSeed.getTerritoryId('TERR_HEAD_OFFICE');
        }
        if (parentId == null) {
            throw new AuraHandledException('Parent territory is required.');
        }

        Territory2 territory = new Territory2(
            Name = form.name.trim(),
            DeveloperName = buildDeveloperName(externalId),
            Territory2ModelId = model.Id,
            Territory2TypeId = territoryType.Id,
            ParentTerritory2Id = parentId,
            External_ID__c = externalId
        );
        insert as system territory;
        return territory.Id;
    }

    @AuraEnabled
    public static Id createProductLine(String name, String code, String therapyArea) {
        if (String.isBlank(name) || String.isBlank(code)) {
            throw new AuraHandledException('Line name and code are required.');
        }
        String normalizedCode = code.trim().toUpperCase().replaceAll('[^A-Z0-9_]', '_');
        Id headOfficeId = TerritoryModuleSeed.getTerritoryId('TERR_HEAD_OFFICE');
        if (headOfficeId == null) {
            throw new AuraHandledException('Head Office territory not found. Run territory seed first.');
        }

        String lineExt = PHARMA_PREFIX + normalizedCode;
        String districtExt = lineExt + '_DM_1';
        String mrExt = districtExt + '_MR_1';

        Id lineId = saveTerritory(buildForm(null, name.trim(), lineExt, headOfficeId, 'Line'));
        Id districtId = saveTerritory(buildForm(null, normalizedCode + '_DM_1', districtExt, lineId, 'District'));
        saveTerritory(buildForm(null, normalizedCode + '_DM_1_MR_1', mrExt, districtId, 'MR'));
        return lineId;
    }

    @AuraEnabled
    public static void deleteTerritory(Id territoryId) {
        if (territoryId == null) {
            throw new AuraHandledException('Territory Id is required.');
        }
        Territory2 territory = [
            SELECT Id, External_ID__c
            FROM Territory2
            WHERE Id = :territoryId
            WITH SYSTEM_MODE
            LIMIT 1
        ];
        assertPharmaTerritory(territory.External_ID__c);
        if (territory.External_ID__c == 'TERR_HEAD_OFFICE') {
            throw new AuraHandledException('Head Office cannot be deleted.');
        }

        Integer childCount = [
            SELECT COUNT()
            FROM Territory2
            WHERE ParentTerritory2Id = :territoryId
            WITH SYSTEM_MODE
        ];
        if (childCount > 0) {
            throw new AuraHandledException('Remove or reassign child territories before deleting this node.');
        }

        delete as system [
            SELECT Id
            FROM UserTerritory2Association
            WHERE Territory2Id = :territoryId
            WITH SYSTEM_MODE
        ];

        if (!Territory2.SObjectType.getDescribe().isDeletable()) {
            throw new AuraHandledException(
                'Territory assignments were cleared. Delete the territory node in Setup > Territory Management.'
            );
        }
        Database.DeleteResult deleteResult = Database.delete(territoryId, false, AccessLevel.SYSTEM_MODE);
        if (!deleteResult.isSuccess()) {
            throw new AuraHandledException(
                deleteResult.getErrors()[0].getMessage()
            );
        }
    }

    @AuraEnabled
    public static CreatedUserResult createPharmaUser(
        String firstName,
        String lastName,
        String teamCode,
        String roleKey,
        Id territoryId,
        String roleInTerritory
    ) {
        if (String.isBlank(firstName) || String.isBlank(lastName) || String.isBlank(teamCode) || String.isBlank(roleKey)) {
            throw new AuraHandledException('First name, last name, team code, and role are required.');
        }

        String team = teamCode.trim().toLowerCase().replaceAll('[^a-z0-9]', '');
        String role = roleKey.trim().toLowerCase();
        if (role != 'dm' && role != 'mr') {
            throw new AuraHandledException('Role must be dm or mr.');
        }

        String username = team + '.' + role + '@pharma.demo';
        List<User> existing = [
            SELECT Id, Username
            FROM User
            WHERE Username = :username
            WITH SYSTEM_MODE
            LIMIT 1
        ];
        if (!existing.isEmpty()) {
            throw new AuraHandledException('User already exists: ' + username);
        }

        Profile userProfile = [
            SELECT Id
            FROM Profile
            WHERE Name = 'Standard User'
            WITH SYSTEM_MODE
            LIMIT 1
        ];

        String roleLabel = role == 'dm' ? 'District Manager' : 'Medical Rep';
        User demoUser = new User(
            Username = username,
            Email = team + '.' + role + '@pharma.eg',
            FirstName = firstName.trim(),
            LastName = lastName.trim(),
            Title = roleLabel,
            Department = team.toUpperCase(),
            Alias = (team + role).left(8),
            TimeZoneSidKey = 'America/New_York',
            LocaleSidKey = 'en_US',
            EmailEncodingKey = 'UTF-8',
            LanguageLocaleKey = 'en_US',
            ProfileId = userProfile.Id,
            CommunityNickname = (team + role + String.valueOf(Crypto.getRandomInteger())).left(40)
        );
        insert as system demoUser;
        assignPersona(demoUser.Id, role);

        if (territoryId != null) {
            insert as system new UserTerritory2Association(
                UserId = demoUser.Id,
                Territory2Id = territoryId,
                RoleInTerritory2 = String.isBlank(roleInTerritory) ? roleLabel : roleInTerritory
            );
        }

        CreatedUserResult result = new CreatedUserResult();
        result.userId = demoUser.Id;
        result.username = username;
        result.message = 'Created ' + demoUser.FirstName + ' ' + demoUser.LastName + ' (' + username + ').';
        return result;
    }

    /**
     * Aligns catalog products to the default MR territories for all seeded Chemipharm lines.
     */
    public static void syncDefaultLineProductAlignments() {
        alignProductsForTherapyArea('Gastroenterology', 'TERR_GIT_DM_1_MR_1');
        alignProductsForTherapyArea('Gastroenterology', 'TERR_GASTRO_DM_1_MR_1');
        alignProductsForTherapyArea('Neurology', 'TERR_CNS_DM_1_MR_1');
        alignProductsForTherapyArea('Neurology', 'TERR_DIABETES_DM_1_MR_1');
        alignProductsForTherapyArea('Rheumatology', 'TERR_RHEUM_DM_1_MR_1');
        alignProductsForTherapyArea('Rheumatology', 'TERR_CLUSTER_DM_1_MR_1');
        alignProductsForTherapyArea('Cardiovascular', 'TERR_CARDIO_DM_1_MR_1');
        alignProductsForTherapyArea('Consumer Health', 'TERR_CHC_DM_1_MR_1');
    }

    public static String resolveLevel(String externalId) {
        if (String.isBlank(externalId)) {
            return 'Unknown';
        }
        if (externalId == 'TERR_HEAD_OFFICE') {
            return 'Head Office';
        }
        if (externalId.contains('_MR_')) {
            return 'MR';
        }
        if (externalId.contains('_DM_')) {
            return 'District';
        }
        return 'Line';
    }

    private static TerritoryForm buildForm(Id recordId, String name, String externalId, Id parentId, String level) {
        TerritoryForm form = new TerritoryForm();
        form.recordId = recordId;
        form.name = name;
        form.externalId = externalId;
        form.parentId = parentId;
        form.level = level;
        return form;
    }

    private static ParentOption buildParentOption(Id id, String name, String level) {
        ParentOption option = new ParentOption();
        option.id = id;
        option.label = name + ' (' + level + ')';
        option.level = level;
        return option;
    }

    private static void validateTerritoryForm(TerritoryForm form) {
        if (form == null || String.isBlank(form.name)) {
            throw new AuraHandledException('Territory name is required.');
        }
        if (form.recordId == null && String.isBlank(form.externalId)) {
            throw new AuraHandledException('External Id is required for new territories.');
        }
    }

    private static String normalizeExternalId(String externalId) {
        String normalized = externalId.trim().toUpperCase();
        if (!normalized.startsWith(PHARMA_PREFIX)) {
            normalized = PHARMA_PREFIX + normalized.replace(PHARMA_PREFIX, '');
        }
        if (!normalized.startsWith(PHARMA_PREFIX)) {
            throw new AuraHandledException('External Id must start with ' + PHARMA_PREFIX);
        }
        return normalized;
    }

    private static void assertPharmaTerritory(String externalId) {
        if (String.isBlank(externalId) || !externalId.startsWith(PHARMA_PREFIX)) {
            throw new AuraHandledException('Only pharma territories (' + PHARMA_PREFIX + '*) can be managed here.');
        }
    }

    private static void assertUniqueExternalId(String externalId, Id recordId) {
        List<Territory2> existing = [
            SELECT Id
            FROM Territory2
            WHERE External_ID__c = :externalId
            WITH SYSTEM_MODE
            LIMIT 1
        ];
        if (!existing.isEmpty() && existing[0].Id != recordId) {
            throw new AuraHandledException('External Id already exists: ' + externalId);
        }
    }

    private static String buildDeveloperName(String externalId) {
        String developerName = externalId.replace(PHARMA_PREFIX, '').replace('__', '_');
        if (developerName.length() > 80) {
            developerName = developerName.left(80);
        }
        return developerName;
    }

    private static Territory2Type resolveTerritoryType() {
        List<Territory2Type> types = [SELECT Id FROM Territory2Type WITH SYSTEM_MODE LIMIT 1];
        if (types.isEmpty()) {
            throw new AuraHandledException('No Territory2Type found.');
        }
        return types[0];
    }

    private static Territory2Model resolveModel() {
        List<Territory2Model> models = [
            SELECT Id
            FROM Territory2Model
            WHERE DeveloperName = 'Current_FY'
            WITH SYSTEM_MODE
            LIMIT 1
        ];
        if (models.isEmpty()) {
            throw new AuraHandledException('Current_FY territory model not found.');
        }
        return models[0];
    }

    private static void assignPersona(Id userId, String roleKey) {
        String groupDeveloperName = roleKey == 'dm' ? 'Pharma_District_Manager_PSG' : 'Pharma_Field_Rep_PSG';
        List<PermissionSetGroup> groups = [
            SELECT Id
            FROM PermissionSetGroup
            WHERE DeveloperName = :groupDeveloperName
            WITH SYSTEM_MODE
            LIMIT 1
        ];
        if (groups.isEmpty()) {
            return;
        }
        Id groupId = groups[0].Id;
        if ([SELECT COUNT() FROM PermissionSetAssignment WHERE AssigneeId = :userId AND PermissionSetGroupId = :groupId WITH SYSTEM_MODE] > 0) {
            return;
        }
        insert as system new PermissionSetAssignment(AssigneeId = userId, PermissionSetGroupId = groupId);
    }

    private static void alignProductsForTherapyArea(String therapyArea, String mrTerritoryExtId) {
        Id territoryId = TerritoryModuleSeed.getTerritoryId(mrTerritoryExtId);
        if (territoryId == null) {
            return;
        }
        List<Product2> products = [
            SELECT Id
            FROM Product2
            WHERE Therapy_Area__c = :therapyArea AND IsActive = TRUE
            WITH SYSTEM_MODE
        ];
        if (products.isEmpty()) {
            return;
        }

        Set<String> existingKeys = new Set<String>();
        for (Product_Territory_Alignment__c existing : [
            SELECT Product2_Id__c, Territory2_Id__c
            FROM Product_Territory_Alignment__c
            WHERE Territory2_Id__c = :String.valueOf(territoryId)
            WITH SYSTEM_MODE
        ]) {
            existingKeys.add(existing.Product2_Id__c + ':' + existing.Territory2_Id__c);
        }

        List<Product_Territory_Alignment__c> toInsert = new List<Product_Territory_Alignment__c>();
        for (Product2 product : products) {
            String key = String.valueOf(product.Id) + ':' + String.valueOf(territoryId);
            if (existingKeys.contains(key)) {
                continue;
            }
            toInsert.add(new Product_Territory_Alignment__c(
                Product2_Id__c = String.valueOf(product.Id),
                Territory2_Id__c = String.valueOf(territoryId),
                Is_Active__c = true,
                Effective_Start_Date__c = Date.today().addMonths(-1)
            ));
        }
        if (!toInsert.isEmpty()) {
            insert as system toInsert;
        }
    }
}
