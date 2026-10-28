/**
 * Loads production organogram territories and brick masters from Static Resource
 * ZetaOrganogramTerritories, then queues alignment batches for Brick_Territory_Alignment__c.
 * Idempotent: upserts by External_ID__c. Does not create demo users or accounts.
 */
public without sharing class ZetaOrganogramTerritoryLoader {
    private static final String TERRITORIES_RESOURCE = 'ZetaOrganogramTerritories';
    private static final List<String> ALIGNMENT_RESOURCES = new List<String>{
        'ZetaOrganogramAlignments01',
        'ZetaOrganogramAlignments02',
        'ZetaOrganogramAlignments03',
        'ZetaOrganogramAlignments04',
        'ZetaOrganogramAlignments05',
        'ZetaOrganogramAlignments06'
    };

    @TestVisible private static String testTerritoriesJson;
    @TestVisible private static Boolean skipAlignmentQueue = false;

    public class LoadResult {
        @AuraEnabled public Id headOfficeId;
        @AuraEnabled public Integer businessUnitsUpserted;
        @AuraEnabled public Integer linesUpserted;
        @AuraEnabled public Integer districtsUpserted;
        @AuraEnabled public Integer positionsUpserted;
        @AuraEnabled public Integer bricksUpserted;
        @AuraEnabled public Integer alignmentBatchesQueued;
        @AuraEnabled public String message;
        @AuraEnabled public List<String> errors;
    }

    private class TerritoryNode {
        public String externalId;
        public String name;
        public String developerName;
        public String parentExternalId;
        public String territoryType;
    }

    private class BrickNode {
        public String externalId;
        public String name;
        public String dataSource;
        public Boolean isActive;
        public String brickLevel;
        public String brickCode;
        public String parentExternalId;
        public Boolean accountSelectable;
    }

    private class TerritoriesPayload {
        public TerritoryNode headOffice;
        public List<TerritoryNode> businessUnits;
        public List<TerritoryNode> lines;
        public List<TerritoryNode> districts;
        public List<TerritoryNode> positions;
        public List<BrickNode> bricks;
    }

    @AuraEnabled
    public static LoadResult loadTerritoriesAndQueueAlignments() {
        LoadResult result = loadTerritoriesOnly();
        if (result.headOfficeId == null) {
            return result;
        }
        // Territory2 is a setup object; Brick__c DML must run in a separate transaction.
        if (!skipAlignmentQueue) {
            System.enqueueJob(new ZetaOrganogramBrickLoadQueueable());
            result.message = result.message + ' Brick/alignment load queued.';
        }
        return result;
    }

    @AuraEnabled
    public static LoadResult loadTerritoriesOnly() {
        LoadResult result = new LoadResult();
        result.errors = new List<String>();
        result.businessUnitsUpserted = 0;
        result.linesUpserted = 0;
        result.districtsUpserted = 0;
        result.positionsUpserted = 0;
        result.bricksUpserted = 0;
        result.alignmentBatchesQueued = 0;

        TerritoriesPayload payload = parseTerritoriesPayload();
        Territory2Model model = resolveModel();
        Territory2Type territoryType = resolveTerritoryType();

        Map<String, Id> idsByExt = new Map<String, Id>();
        result.headOfficeId = upsertTerritoryNode(
            payload.headOffice,
            null,
            model.Id,
            territoryType.Id,
            idsByExt,
            result.errors
        );
        if (result.headOfficeId == null) {
            result.message = 'Head Office upsert failed.';
            return result;
        }

        result.businessUnitsUpserted = upsertLevelBulk(
            payload.businessUnits,
            idsByExt,
            model.Id,
            territoryType.Id,
            result.errors
        );
        result.linesUpserted = upsertLevelBulk(
            payload.lines,
            idsByExt,
            model.Id,
            territoryType.Id,
            result.errors
        );
        result.districtsUpserted = upsertLevelBulk(
            payload.districts,
            idsByExt,
            model.Id,
            territoryType.Id,
            result.errors
        );
        result.positionsUpserted = upsertLevelBulk(
            payload.positions,
            idsByExt,
            model.Id,
            territoryType.Id,
            result.errors
        );

        result.message =
            'Upserted HO + ' +
            result.businessUnitsUpserted +
            ' BUs, ' +
            result.linesUpserted +
            ' lines, ' +
            result.districtsUpserted +
            ' districts, ' +
            result.positionsUpserted +
            ' positions.';
        return result;
    }

    public static final String TRAINING_BU_EXT = 'TERR_BU_TRAINING';
    public static final String TRAINING_LINE_EXT = 'TERR_LINE_TRAINING';
    public static final String TRAINING_REP_EXT = 'TERR_POS_TRAINING_REP';
    public static final String DEMO_FIELD_REP_USERNAME = 'demo.rep@zeta-pharma.com.zeta';
    public static final String DEMO_DM_USERNAME = 'demo.dm@zeta-pharma.com.zeta';

    public class TrainingLineSpec {
        public String key;
        public String lineExternalId;
        public String lineName;
        public String lineDeveloperName;
        public String districtExternalId;
        public String districtName;
        public String districtDeveloperName;
        public String positionExternalId;
        public String positionName;
        public String positionDeveloperName;
        public String username;
        public String firstName;
        public String lastName;
        public String managerUsername;
    }

    /**
     * Named training lines under Training BU, each with a Cairo position and assigned user.
     */
    public static List<TrainingLineSpec> trainingLineSpecs() {
        // CLUSTER is the Pedia training line. Peter Alfred manages that district.
        return new List<TrainingLineSpec>{
            trainingLineWithManager(
                'DIAB',
                'Diab T',
                'Diab T Cairo',
                'bassant.bahaaelden@zetapharma.net',
                'Bassant',
                'Bahaaeldeen',
                'mohamed.eltahlawy@zeta-pharma.com'
            ),
            trainingLineWithManager(
                'CHC',
                'CHC T',
                'CHC T Cairo',
                'nada.wael@zetapharma.net',
                'Nada',
                'Wael',
                'marina.atef@zeta-pharma.com'
            ),
            trainingLineWithManager(
                'GIT',
                'GIT T',
                'GIT T Cairo',
                'omar@zetapharma.net',
                'Omar',
                'Mohsen',
                'ahmed.fathy@zeta-pharma.com'
            ),
            trainingLineWithManager(
                'PEDIA',
                'Pedia T',
                'Pedia T Cairo',
                'gassem@zetapharma.net',
                'Gassem',
                'Gamal',
                'peter.alfred@zeta-pharma.com'
            )
        };
    }

    public static Set<String> trainingLineUsernames() {
        Set<String> usernames = new Set<String>();
        for (TrainingLineSpec spec : trainingLineSpecs()) {
            usernames.add(spec.username.toLowerCase());
        }
        return usernames;
    }

    public static Set<String> reservedTrainingUsernames() {
        Set<String> usernames = trainingLineUsernames();
        usernames.add(DEMO_FIELD_REP_USERNAME);
        usernames.add(DEMO_DM_USERNAME);
        return usernames;
    }

    public static TrainingLineSpec diabTrainingLineSpec() {
        for (TrainingLineSpec spec : trainingLineSpecs()) {
            if (spec.key == 'DIAB') {
                return spec;
            }
        }
        return null;
    }

    private static TrainingLineSpec trainingLineSpec(
        String key,
        String lineName,
        String positionName,
        String username,
        String firstName,
        String lastName
    ) {
        TrainingLineSpec spec = new TrainingLineSpec();
        spec.key = key;
        spec.lineExternalId = 'TERR_LINE_TRAINING_' + key;
        spec.lineName = lineName;
        spec.lineDeveloperName = 'LINE_TRAINING_' + key;
        spec.positionExternalId = 'TERR_POS_TRAINING_' + key + '_CAIRO';
        spec.positionName = positionName;
        spec.positionDeveloperName = 'POS_TRAINING_' + key + '_CAIRO';
        spec.username = username;
        spec.firstName = firstName;
        spec.lastName = lastName;
        return spec;
    }

    private static TrainingLineSpec trainingLineWithManager(
        String key,
        String lineName,
        String positionName,
        String username,
        String firstName,
        String lastName,
        String managerUsername
    ) {
        TrainingLineSpec spec = trainingLineSpec(key, lineName, positionName, username, firstName, lastName);
        spec.districtExternalId = 'TERR_DM_TRAINING_' + key;
        spec.districtName = lineName + ' DM';
        spec.districtDeveloperName = 'DM_TRAINING_' + key;
        spec.managerUsername = managerUsername;
        return spec;
    }

    /**
     * Assigns each training-line manager to the district between the line and the Cairo position.
     * Does not remove other users already on that district.
     */
    public static List<String> assignTrainingLineManagers() {
        List<String> messages = new List<String>();
        List<TrainingLineSpec> specs = trainingLineSpecs();
        Set<String> territoryExtIds = new Set<String>();
        Set<String> managerUsernames = new Set<String>();
        Set<String> repUsernames = new Set<String>();
        for (TrainingLineSpec spec : specs) {
            territoryExtIds.add(spec.districtExternalId);
            territoryExtIds.add(spec.positionExternalId);
            if (String.isNotBlank(spec.managerUsername)) {
                managerUsernames.add(spec.managerUsername.toLowerCase());
            }
            if (String.isNotBlank(spec.username)) {
                repUsernames.add(spec.username.toLowerCase());
            }
        }

        Map<String, Id> territoryIds = new Map<String, Id>();
        for (Territory2 territory : [
            SELECT Id, External_ID__c
            FROM Territory2
            WHERE External_ID__c IN :territoryExtIds
            WITH SYSTEM_MODE
        ]) {
            territoryIds.put(territory.External_ID__c, territory.Id);
        }

        Map<String, User> usersByUsername = new Map<String, User>();
        Set<String> lookupUsernames = new Set<String>();
        lookupUsernames.addAll(managerUsernames);
        lookupUsernames.addAll(repUsernames);
        for (User person : [
            SELECT Id, Username, Title, Department, ManagerId, IsActive
            FROM User
            WHERE Username IN :lookupUsernames
            WITH SYSTEM_MODE
        ]) {
            usersByUsername.put(person.Username.toLowerCase(), person);
        }

        Set<Id> managerIds = new Set<Id>();
        for (String username : managerUsernames) {
            User manager = usersByUsername.get(username);
            if (manager != null) {
                managerIds.add(manager.Id);
            }
        }
        Map<String, Id> existingAssignment = new Map<String, Id>();
        if (!managerIds.isEmpty()) {
            for (UserTerritory2Association row : [
                SELECT Id, UserId, Territory2Id
                FROM UserTerritory2Association
                WHERE UserId IN :managerIds
                WITH SYSTEM_MODE
            ]) {
                existingAssignment.put(String.valueOf(row.UserId) + ':' + String.valueOf(row.Territory2Id), row.Id);
            }
        }

        List<UserTerritory2Association> toInsert = new List<UserTerritory2Association>();
        List<User> managersToUpdate = new List<User>();
        List<User> repsToUpdate = new List<User>();
        for (TrainingLineSpec spec : specs) {
            Id districtId = territoryIds.get(spec.districtExternalId);
            User manager = usersByUsername.get(
                spec.managerUsername == null ? null : spec.managerUsername.toLowerCase()
            );
            if (districtId == null || manager == null) {
                messages.add(spec.key + ': manager or district missing.');
                continue;
            }
            String key = String.valueOf(manager.Id) + ':' + String.valueOf(districtId);
            if (!existingAssignment.containsKey(key)) {
                toInsert.add(
                    new UserTerritory2Association(
                        UserId = manager.Id,
                        Territory2Id = districtId,
                        RoleInTerritory2 = 'District Manager'
                    )
                );
            }
            managersToUpdate.add(
                new User(
                    Id = manager.Id,
                    Title = 'District Manager',
                    Department = spec.lineName
                )
            );
            messages.add(spec.lineName + ': ' + manager.Username + ' → ' + spec.districtName);
        }

        Set<Id> positionIds = new Set<Id>();
        Map<Id, Id> managerByPosition = new Map<Id, Id>();
        for (TrainingLineSpec spec : specs) {
            Id positionId = territoryIds.get(spec.positionExternalId);
            User manager = usersByUsername.get(
                spec.managerUsername == null ? null : spec.managerUsername.toLowerCase()
            );
            if (positionId == null || manager == null) {
                continue;
            }
            positionIds.add(positionId);
            managerByPosition.put(positionId, manager.Id);
        }
        if (!positionIds.isEmpty()) {
            for (UserTerritory2Association row : [
                SELECT UserId, Territory2Id, User.ManagerId
                FROM UserTerritory2Association
                WHERE Territory2Id IN :positionIds AND RoleInTerritory2 = 'Medical Rep'
                WITH SYSTEM_MODE
            ]) {
                Id managerId = managerByPosition.get(row.Territory2Id);
                if (managerId != null && row.UserId != managerId && row.User.ManagerId != managerId) {
                    repsToUpdate.add(new User(Id = row.UserId, ManagerId = managerId));
                }
            }
        }

        if (!toInsert.isEmpty()) {
            Database.SaveResult[] inserted = Database.insert(toInsert, false, AccessLevel.SYSTEM_MODE);
            for (Integer i = 0; i < inserted.size(); i++) {
                if (!inserted[i].isSuccess()) {
                    messages.add(toInsert[i].UserId + ': ' + inserted[i].getErrors()[0].getMessage());
                }
            }
        }
        if (!managersToUpdate.isEmpty()) {
            Database.update(managersToUpdate, false, AccessLevel.SYSTEM_MODE);
        }
        if (!repsToUpdate.isEmpty()) {
            Database.update(repsToUpdate, false, AccessLevel.SYSTEM_MODE);
        }
        return messages;
    }

    /**
     * Idempotent: creates Training BU, Training Line, and Training Rep under Head Office.
     */
    @AuraEnabled
    public static LoadResult seedTrainingHierarchy() {
        LoadResult result = new LoadResult();
        result.errors = new List<String>();
        result.businessUnitsUpserted = 0;
        result.linesUpserted = 0;
        result.districtsUpserted = 0;
        result.positionsUpserted = 0;
        result.bricksUpserted = 0;
        result.alignmentBatchesQueued = 0;

        Territory2Model model = resolveModel();
        Territory2Type territoryType = resolveTerritoryType();
        Map<String, Id> idsByExt = new Map<String, Id>();

        TerritoryNode headOfficeRef = trainingNode(
            'TERR_HEAD_OFFICE',
            'Head Office',
            'Head_Office',
            null,
            'Head_Office'
        );
        Territory2 existingHo = findExistingTerritory(headOfficeRef);
        if (existingHo == null) {
            result.message = 'Head Office not found. Load organogram territories first.';
            result.errors.add(result.message);
            return result;
        }
        idsByExt.put('TERR_HEAD_OFFICE', existingHo.Id);
        result.headOfficeId = existingHo.Id;

        Id buId = upsertTerritoryNode(
            trainingNode(TRAINING_BU_EXT, 'Training', 'BU_TRAINING', 'TERR_HEAD_OFFICE', 'Business_Unit'),
            existingHo.Id,
            model.Id,
            territoryType.Id,
            idsByExt,
            result.errors
        );
        if (buId != null) {
            result.businessUnitsUpserted = 1;
        }

        Id lineId = upsertTerritoryNode(
            trainingNode(TRAINING_LINE_EXT, 'Training Line', 'LINE_TRAINING', TRAINING_BU_EXT, 'Line'),
            buId,
            model.Id,
            territoryType.Id,
            idsByExt,
            result.errors
        );
        if (lineId != null) {
            result.linesUpserted = 1;
        }

        Id repId = upsertTerritoryNode(
            trainingNode(
                TRAINING_REP_EXT,
                'Training Rep',
                'POS_TRAINING_REP',
                TRAINING_LINE_EXT,
                'Position'
            ),
            lineId,
            model.Id,
            territoryType.Id,
            idsByExt,
            result.errors
        );
        if (repId != null) {
            result.positionsUpserted = 1;
        }

        List<TerritoryNode> extraLines = new List<TerritoryNode>();
        List<TerritoryNode> extraDistricts = new List<TerritoryNode>();
        List<TerritoryNode> extraPositions = new List<TerritoryNode>();
        for (TrainingLineSpec spec : trainingLineSpecs()) {
            extraLines.add(
                trainingNode(spec.lineExternalId, spec.lineName, spec.lineDeveloperName, TRAINING_BU_EXT, 'Line')
            );
            String positionParent = spec.lineExternalId;
            if (String.isNotBlank(spec.districtExternalId)) {
                extraDistricts.add(
                    trainingNode(
                        spec.districtExternalId,
                        spec.districtName,
                        spec.districtDeveloperName,
                        spec.lineExternalId,
                        'District'
                    )
                );
                positionParent = spec.districtExternalId;
            }
            extraPositions.add(
                trainingNode(
                    spec.positionExternalId,
                    spec.positionName,
                    spec.positionDeveloperName,
                    positionParent,
                    'Position'
                )
            );
        }
        result.linesUpserted += upsertLevelBulk(
            extraLines,
            idsByExt,
            model.Id,
            territoryType.Id,
            result.errors
        );
        result.districtsUpserted += upsertLevelBulk(
            extraDistricts,
            idsByExt,
            model.Id,
            territoryType.Id,
            result.errors
        );
        result.positionsUpserted += upsertLevelBulk(
            extraPositions,
            idsByExt,
            model.Id,
            territoryType.Id,
            result.errors
        );

        result.message =
            'Training hierarchy upserted: BU=' +
            result.businessUnitsUpserted +
            ', Line=' +
            result.linesUpserted +
            ', District=' +
            result.districtsUpserted +
            ', Rep=' +
            result.positionsUpserted +
            '.';
        return result;
    }

    private static TerritoryNode trainingNode(
        String externalId,
        String name,
        String developerName,
        String parentExternalId,
        String territoryType
    ) {
        TerritoryNode node = new TerritoryNode();
        node.externalId = externalId;
        node.name = name;
        node.developerName = developerName;
        node.parentExternalId = parentExternalId;
        node.territoryType = territoryType;
        return node;
    }

    @AuraEnabled
    public static LoadResult loadBricksOnly() {
        LoadResult result = new LoadResult();
        result.errors = new List<String>();
        result.bricksUpserted = 0;
        result.alignmentBatchesQueued = 0;
        TerritoriesPayload payload = parseTerritoriesPayload();
        result.bricksUpserted = upsertBricks(payload.bricks, result.errors);
        result.message = 'Upserted ' + result.bricksUpserted + ' bricks.';
        return result;
    }

    @AuraEnabled
    public static LoadResult loadBricksAndQueueAlignments() {
        LoadResult result = loadBricksOnly();
        if (!skipAlignmentQueue) {
            result.alignmentBatchesQueued = queueAlignmentBatches(result.errors);
        }
        result.message =
            'Upserted ' +
            result.bricksUpserted +
            ' bricks. Queued ' +
            result.alignmentBatchesQueued +
            ' alignment batches.';
        return result;
    }

    public static Integer queueAlignmentBatches(List<String> errors) {
        Integer queued = 0;
        for (String resourceName : ALIGNMENT_RESOURCES) {
            try {
                Id jobId = Database.executeBatch(
                    new ZetaOrganogramAlignmentBatch(resourceName),
                    200
                );
                if (jobId != null) {
                    queued++;
                }
            } catch (Exception ex) {
                if (errors != null) {
                    errors.add(resourceName + ': ' + ex.getMessage());
                }
            }
        }
        return queued;
    }

    /** External ids of every Business Unit, Line, District and Position in the current organogram resource. */
    public static Set<String> organogramExternalIds() {
        TerritoriesPayload payload = parseTerritoriesPayload();
        Set<String> out = new Set<String>();
        for (List<TerritoryNode> level : new List<List<TerritoryNode>>{
            payload.businessUnits, payload.lines, payload.districts, payload.positions
        }) {
            if (level == null) {
                continue;
            }
            for (TerritoryNode node : level) {
                if (node != null && String.isNotBlank(node.externalId)) {
                    out.add(node.externalId);
                }
            }
        }
        if (payload.headOffice != null && String.isNotBlank(payload.headOffice.externalId)) {
            out.add(payload.headOffice.externalId);
        }
        return out;
    }

    /** External id to display name for the Business Units in the organogram resource. */
    public static Map<String, String> businessUnitNames() {
        Map<String, String> out = new Map<String, String>();
        TerritoriesPayload payload = parseTerritoriesPayload();
        if (payload.businessUnits != null) {
            for (TerritoryNode node : payload.businessUnits) {
                if (node != null && String.isNotBlank(node.externalId) && String.isNotBlank(node.name)) {
                    out.put(node.externalId, node.name);
                }
            }
        }
        return out;
    }

    public static List<String> alignmentResourceNames() {
        return new List<String>(ALIGNMENT_RESOURCES);
    }

    private static TerritoriesPayload parseTerritoriesPayload() {
        String body = testTerritoriesJson;
        if (String.isBlank(body)) {
            StaticResource resource = [
                SELECT Body
                FROM StaticResource
                WHERE Name = :TERRITORIES_RESOURCE
                WITH SYSTEM_MODE
                LIMIT 1
            ];
            body = resource.Body.toString();
        }
        return (TerritoriesPayload) JSON.deserialize(body, TerritoriesPayload.class);
    }

    private static Integer upsertLevelBulk(
        List<TerritoryNode> nodes,
        Map<String, Id> idsByExt,
        Id modelId,
        Id typeId,
        List<String> errors
    ) {
        if (nodes == null || nodes.isEmpty()) {
            return 0;
        }

        Set<String> externalIds = new Set<String>();
        Set<String> developerNames = new Set<String>();
        for (TerritoryNode node : nodes) {
            if (String.isBlank(node.externalId)) {
                continue;
            }
            externalIds.add(node.externalId);
            if (String.isNotBlank(node.developerName)) {
                developerNames.add(sanitizeDeveloperName(node.developerName, node.externalId));
            }
        }

        Map<String, Territory2> existingByExt = new Map<String, Territory2>();
        Map<String, Territory2> existingByDev = new Map<String, Territory2>();
        for (Territory2 territory : [
            SELECT Id, Name, ParentTerritory2Id, External_ID__c, DeveloperName
            FROM Territory2
            WHERE External_ID__c IN :externalIds OR DeveloperName IN :developerNames
            WITH SYSTEM_MODE
        ]) {
            if (String.isNotBlank(territory.External_ID__c)) {
                existingByExt.put(territory.External_ID__c, territory);
            }
            if (String.isNotBlank(territory.DeveloperName) && !existingByDev.containsKey(territory.DeveloperName)) {
                existingByDev.put(territory.DeveloperName, territory);
            }
        }

        List<Territory2> toInsert = new List<Territory2>();
        List<Territory2> toUpdate = new List<Territory2>();
        List<TerritoryNode> insertNodes = new List<TerritoryNode>();

        for (TerritoryNode node : nodes) {
            if (String.isBlank(node.externalId)) {
                errors.add('Blank territory node.');
                continue;
            }
            Id parentId = null;
            if (String.isNotBlank(node.parentExternalId)) {
                parentId = idsByExt.get(node.parentExternalId);
                if (parentId == null) {
                    errors.add('Missing parent ' + node.parentExternalId + ' for ' + node.externalId);
                    continue;
                }
            }

            String developerName = sanitizeDeveloperName(node.developerName, node.externalId);
            Territory2 existing = existingByExt.get(node.externalId);
            if (existing == null) {
                existing = existingByDev.get(developerName);
            }

            if (existing != null) {
                existing.Name = node.name;
                existing.ParentTerritory2Id = parentId;
                existing.External_ID__c = node.externalId;
                applyTerritoryType(existing, node.territoryType);
                toUpdate.add(existing);
                idsByExt.put(node.externalId, existing.Id);
            } else {
                Territory2 territory = new Territory2(
                    Name = node.name,
                    DeveloperName = developerName,
                    Territory2ModelId = modelId,
                    Territory2TypeId = typeId,
                    ParentTerritory2Id = parentId,
                    External_ID__c = node.externalId
                );
                applyTerritoryType(territory, node.territoryType);
                toInsert.add(territory);
                insertNodes.add(node);
            }
        }

        Integer success = 0;
        if (!toUpdate.isEmpty()) {
            Database.SaveResult[] updates = Database.update(toUpdate, false, AccessLevel.SYSTEM_MODE);
            for (Integer i = 0; i < updates.size(); i++) {
                if (updates[i].isSuccess()) {
                    success++;
                    idsByExt.put(toUpdate[i].External_ID__c, toUpdate[i].Id);
                } else {
                    errors.add(toUpdate[i].External_ID__c + ': ' + updates[i].getErrors()[0].getMessage());
                }
            }
        }

        if (!toInsert.isEmpty()) {
            Database.SaveResult[] inserts = Database.insert(toInsert, false, AccessLevel.SYSTEM_MODE);
            for (Integer i = 0; i < inserts.size(); i++) {
                if (inserts[i].isSuccess()) {
                    success++;
                    idsByExt.put(insertNodes[i].externalId, inserts[i].getId());
                } else {
                    errors.add(insertNodes[i].externalId + ': ' + inserts[i].getErrors()[0].getMessage());
                }
            }
        }
        return success;
    }

    private static Id upsertTerritoryNode(
        TerritoryNode node,
        Id parentId,
        Id modelId,
        Id typeId,
        Map<String, Id> idsByExt,
        List<String> errors
    ) {
        if (node == null || String.isBlank(node.externalId)) {
            errors.add('Blank territory node.');
            return null;
        }

        try {
            Territory2 existing = findExistingTerritory(node);
            if (existing != null) {
                existing.Name = node.name;
                existing.ParentTerritory2Id = parentId;
                existing.External_ID__c = node.externalId;
                applyTerritoryType(existing, node.territoryType);
                update as system existing;
                idsByExt.put(node.externalId, existing.Id);
                return existing.Id;
            }

            Territory2 territory = new Territory2(
                Name = node.name,
                DeveloperName = sanitizeDeveloperName(node.developerName, node.externalId),
                Territory2ModelId = modelId,
                Territory2TypeId = typeId,
                ParentTerritory2Id = parentId,
                External_ID__c = node.externalId
            );
            applyTerritoryType(territory, node.territoryType);
            insert as system territory;
            idsByExt.put(node.externalId, territory.Id);
            return territory.Id;
        } catch (Exception ex) {
            errors.add(node.externalId + ': ' + ex.getMessage());
            return null;
        }
    }

    private static Territory2 findExistingTerritory(TerritoryNode node) {
        List<Territory2> byExt = [
            SELECT Id, Name, ParentTerritory2Id, External_ID__c, DeveloperName
            FROM Territory2
            WHERE External_ID__c = :node.externalId
            WITH SYSTEM_MODE
            LIMIT 1
        ];
        if (!byExt.isEmpty()) {
            return byExt[0];
        }

        if (String.isNotBlank(node.developerName)) {
            List<Territory2> byDev = [
                SELECT Id, Name, ParentTerritory2Id, External_ID__c, DeveloperName
                FROM Territory2
                WHERE DeveloperName = :node.developerName
                WITH SYSTEM_MODE
                LIMIT 1
            ];
            if (!byDev.isEmpty()) {
                return byDev[0];
            }
        }

        if (node.externalId == 'TERR_HEAD_OFFICE') {
            List<Territory2> byName = [
                SELECT Id, Name, ParentTerritory2Id, External_ID__c, DeveloperName
                FROM Territory2
                WHERE Name = 'Head Office'
                WITH SYSTEM_MODE
                LIMIT 1
            ];
            if (!byName.isEmpty()) {
                return byName[0];
            }
        }
        return null;
    }

    private static Integer upsertBricks(List<BrickNode> bricks, List<String> errors) {
        if (bricks == null || bricks.isEmpty()) {
            return 0;
        }
        Map<String, Schema.SObjectField> brickFields = Schema.SObjectType.Brick__c.fields.getMap();
        List<Brick__c> records = new List<Brick__c>();
        for (BrickNode brick : bricks) {
            Brick__c row = new Brick__c(
                Name = brick.name,
                External_ID__c = brick.externalId,
                Is_Active__c = brick.isActive == null ? true : brick.isActive
            );
            if (brickFields.containsKey('Data_Source__c')) {
                row.put('Data_Source__c', String.isBlank(brick.dataSource) ? 'IQVIA IMS' : brick.dataSource);
            }
            if (brickFields.containsKey('Brick_Level__c') && String.isNotBlank(brick.brickLevel)) {
                row.put('Brick_Level__c', brick.brickLevel);
            }
            if (brickFields.containsKey('Brick_Code__c') && String.isNotBlank(brick.brickCode)) {
                row.put('Brick_Code__c', brick.brickCode.left(32));
            }
            if (brickFields.containsKey('Account_Selectable__c')) {
                Boolean selectable = brick.accountSelectable;
                if (selectable == null) {
                    selectable = brick.brickLevel != '70';
                }
                row.put('Account_Selectable__c', selectable);
            }
            records.add(row);
        }

        Integer success = 0;
        for (Integer start = 0; start < records.size(); start += 200) {
            Integer endIdx = Math.min(start + 200, records.size());
            List<Brick__c> batch = new List<Brick__c>();
            for (Integer i = start; i < endIdx; i++) {
                batch.add(records[i]);
            }
            Database.UpsertResult[] upserts = Database.upsert(
                batch,
                Brick__c.External_ID__c,
                false,
                AccessLevel.SYSTEM_MODE
            );
            for (Integer i = 0; i < upserts.size(); i++) {
                if (upserts[i].isSuccess()) {
                    success++;
                } else {
                    errors.add(
                        batch[i].External_ID__c +
                            ': ' +
                            upserts[i].getErrors()[0].getMessage()
                    );
                }
            }
        }

        applyBrickParents(bricks, errors);
        return success;
    }

    private static void applyBrickParents(List<BrickNode> bricks, List<String> errors) {
        if (!Schema.SObjectType.Brick__c.fields.getMap().containsKey('Parent_Brick__c')) {
            return;
        }
        Set<String> externalIds = new Set<String>();
        for (BrickNode brick : bricks) {
            if (String.isNotBlank(brick.externalId)) {
                externalIds.add(brick.externalId);
            }
            if (String.isNotBlank(brick.parentExternalId)) {
                externalIds.add(brick.parentExternalId);
            }
        }
        if (externalIds.isEmpty()) {
            return;
        }

        Map<String, Id> idsByExt = new Map<String, Id>();
        for (Brick__c row : [
            SELECT Id, External_ID__c
            FROM Brick__c
            WHERE External_ID__c IN :externalIds
            WITH SYSTEM_MODE
        ]) {
            idsByExt.put(row.External_ID__c, row.Id);
        }

        List<Brick__c> parentUpdates = new List<Brick__c>();
        for (BrickNode brick : bricks) {
            Id brickId = idsByExt.get(brick.externalId);
            if (brickId == null) {
                continue;
            }
            Id parentId = String.isBlank(brick.parentExternalId) ? null : idsByExt.get(brick.parentExternalId);
            if (String.isNotBlank(brick.parentExternalId) && parentId == null) {
                errors.add(brick.externalId + ': missing parent ' + brick.parentExternalId);
                continue;
            }
            parentUpdates.add(new Brick__c(Id = brickId, Parent_Brick__c = parentId));
        }

        for (Integer start = 0; start < parentUpdates.size(); start += 200) {
            Integer endIdx = Math.min(start + 200, parentUpdates.size());
            List<Brick__c> batch = new List<Brick__c>();
            for (Integer i = start; i < endIdx; i++) {
                batch.add(parentUpdates[i]);
            }
            Database.update(batch, false, AccessLevel.SYSTEM_MODE);
        }
    }

    private static void applyTerritoryType(Territory2 territory, String territoryType) {
        if (!Schema.SObjectType.Territory2.fields.getMap().containsKey('Territory_Type__c')) {
            return;
        }
        if (String.isBlank(territoryType)) {
            return;
        }
        territory.put('Territory_Type__c', territoryType);
    }

    private static String sanitizeDeveloperName(String developerName, String externalId) {
        String source = String.isNotBlank(developerName) ? developerName : externalId;
        String cleaned = source == null ? 'Territory' : source.replaceAll('[^A-Za-z0-9_]', '_');
        cleaned = cleaned.replaceAll('_+', '_');
        if (cleaned.length() == 0 || !cleaned.substring(0, 1).isAlpha()) {
            cleaned = 'T_' + cleaned;
        }
        return cleaned.left(80);
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

    private static Territory2Model resolveModel() {
        List<Territory2Model> existing = [
            SELECT Id, State, Name, DeveloperName
            FROM Territory2Model
            WHERE DeveloperName = 'Current_FY'
            WITH SYSTEM_MODE
            LIMIT 1
        ];
        if (existing.isEmpty()) {
            throw new AuraHandledException('Current_FY territory model not found.');
        }
        return existing[0];
    }
}