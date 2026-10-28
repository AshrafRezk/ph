public with sharing class LearningAdminController {
    public class MaterialSummary {
        @AuraEnabled public Id id;
        @AuraEnabled public String title;
        @AuraEnabled public String materialType;
        @AuraEnabled public Boolean isActive;
        @AuraEnabled public Id parentMaterialId;
        @AuraEnabled public String parentTitle;
        @AuraEnabled public Decimal duration;
        @AuraEnabled public String description;
        @AuraEnabled public String materialUrl;
        @AuraEnabled public String contentDocumentId;
        @AuraEnabled public String name;
        @AuraEnabled public Integer assignmentCount;
        @AuraEnabled public Date effectiveStartDate;
        @AuraEnabled public Date effectiveEndDate;
    }

    public class AssignmentRow {
        @AuraEnabled public Id instanceId;
        @AuraEnabled public Id userId;
        @AuraEnabled public String userName;
        @AuraEnabled public String userEmail;
        @AuraEnabled public String status;
        @AuraEnabled public Decimal progress;
        @AuraEnabled public Decimal score;
        @AuraEnabled public Datetime startedOn;
        @AuraEnabled public Datetime completedOn;
    }

    public class AssignResult {
        @AuraEnabled public Id courseInstanceId;
        @AuraEnabled public Integer instanceCount;
        @AuraEnabled public Integer userCount;
    }

    public class TerritorySaveResult {
        @AuraEnabled public Integer territoryCount;
        @AuraEnabled public Integer userCount;
        @AuraEnabled public Integer instanceCount;
        @AuraEnabled public Integer removedInstanceCount;
    }

    public class TerritoryTreeNode {
        @AuraEnabled public Id id;
        @AuraEnabled public String name;
        @AuraEnabled public Id parentId;
        @AuraEnabled public Boolean hasChildren;
        @AuraEnabled public Boolean aligned;
        @AuraEnabled public Boolean isBusinessUnit;
        @AuraEnabled public Date effectiveStartDate;
        @AuraEnabled public Date effectiveEndDate;
        @AuraEnabled public List<TerritoryTreeNode> children;
    }

    public class FilterOption {
        @AuraEnabled public String value;
        @AuraEnabled public String label;
    }

    public class FileUploadResult {
        @AuraEnabled public Id materialId;
        @AuraEnabled public Id contentDocumentId;
        @AuraEnabled public Id contentVersionId;
        @AuraEnabled public String materialUrl;
    }

    @AuraEnabled(cacheable=true)
    public static List<MaterialSummary> getMaterialSummaries(
        String searchTerm,
        String typeFilter,
        String activeFilter,
        String buTerritoryFilter
    ) {
        String soql =
            'SELECT Id, Name, Title__c, Material_Type__c, Active__c, Duration__c, Description__c, Material_URL__c, ' +
            'Content_Document_Id__c, Parent_Material__c, Parent_Material__r.Title__c, ' +
            'Effective_Start_Date__c, Effective_End_Date__c ' +
            'FROM Learning_Material__c ';
        List<String> clauses = new List<String>();
        String likeTerm;
        if (String.isNotBlank(searchTerm)) {
            likeTerm = '%' + String.escapeSingleQuotes(searchTerm.trim()) + '%';
            clauses.add('(Title__c LIKE :likeTerm OR Name LIKE :likeTerm)');
        }
        if (String.isNotBlank(typeFilter) && typeFilter != 'All') {
            clauses.add('Material_Type__c = :typeFilter');
        }
        if (activeFilter == 'Active') {
            clauses.add('Active__c = true');
        } else if (activeFilter == 'Inactive') {
            clauses.add('Active__c = false');
        }

        Set<Id> buScopedMaterialIds;
        if (String.isNotBlank(buTerritoryFilter) && buTerritoryFilter != 'All') {
            buScopedMaterialIds = loadMaterialIdsAlignedToBusinessUnit(buTerritoryFilter);
            if (buScopedMaterialIds.isEmpty()) {
                return new List<MaterialSummary>();
            }
            clauses.add(
                '(Id IN :buScopedMaterialIds OR Parent_Material__c IN :buScopedMaterialIds)'
            );
        }

        if (!clauses.isEmpty()) {
            soql += 'WHERE ' + String.join(clauses, ' AND ') + ' ';
        }
        soql += 'ORDER BY Title__c NULLS LAST LIMIT 200';

        List<Learning_Material__c> materials = Database.query(soql);
        Set<Id> courseIds = new Set<Id>();
        for (Learning_Material__c m : materials) {
            if (m.Material_Type__c == 'Course') {
                courseIds.add(m.Id);
            } else if (m.Parent_Material__c != null) {
                courseIds.add(m.Parent_Material__c);
            } else {
                courseIds.add(m.Id);
            }
        }

        Map<Id, Integer> assignmentCounts = new Map<Id, Integer>();
        if (!courseIds.isEmpty()) {
            for (AggregateResult ar : [
                SELECT Material__c materialId, COUNT(Id) cnt
                FROM Learning_Material_Instance__c
                WHERE Material__c IN :courseIds
                GROUP BY Material__c
            ]) {
                assignmentCounts.put((Id) ar.get('materialId'), (Integer) ar.get('cnt'));
            }
        }

        List<MaterialSummary> rows = new List<MaterialSummary>();
        for (Learning_Material__c m : materials) {
            MaterialSummary row = new MaterialSummary();
            row.id = m.Id;
            row.name = m.Name;
            row.title = m.Title__c;
            row.materialType = m.Material_Type__c;
            row.isActive = m.Active__c;
            row.duration = m.Duration__c;
            row.description = m.Description__c;
            row.materialUrl = m.Material_URL__c;
            row.contentDocumentId = m.Content_Document_Id__c;
            row.parentMaterialId = m.Parent_Material__c;
            row.parentTitle = m.Parent_Material__r != null ? m.Parent_Material__r.Title__c : null;
            row.effectiveStartDate = m.Effective_Start_Date__c;
            row.effectiveEndDate = m.Effective_End_Date__c;
            Id countKey = m.Material_Type__c == 'Course'
                ? m.Id
                : (m.Parent_Material__c != null ? m.Parent_Material__c : m.Id);
            row.assignmentCount = assignmentCounts.containsKey(countKey)
                ? assignmentCounts.get(countKey)
                : 0;
            rows.add(row);
        }
        return rows;
    }

    @AuraEnabled(cacheable=true)
    public static List<FilterOption> getBusinessUnitFilterOptions() {
        List<FilterOption> options = new List<FilterOption>();
        FilterOption allOption = new FilterOption();
        allOption.value = 'All';
        allOption.label = 'All Territories';
        options.add(allOption);

        for (TerritoryHierarchyService.FilterOption bu : TerritoryHierarchyService.getBusinessUnitOptions()) {
            if (bu == null || bu.value == 'ALL') {
                continue;
            }
            FilterOption option = new FilterOption();
            option.value = bu.value;
            option.label = bu.label;
            options.add(option);
        }
        return options;
    }

    @AuraEnabled(cacheable=true)
    public static List<AssignmentRow> getAssignments(Id materialId) {
        if (materialId == null) {
            return new List<AssignmentRow>();
        }
        Learning_Material__c root = [
            SELECT Id, Material_Type__c, Parent_Material__c
            FROM Learning_Material__c
            WHERE Id = :materialId
            LIMIT 1
        ];
        Id courseId = root.Material_Type__c == 'Course'
            ? root.Id
            : (root.Parent_Material__c != null ? root.Parent_Material__c : root.Id);

        List<AssignmentRow> rows = new List<AssignmentRow>();
        for (Learning_Material_Instance__c inst : [
            SELECT
                Id,
                Status__c,
                Progress__c,
                Score__c,
                Started_On__c,
                Completed_On__c,
                Learner__c,
                Learner__r.Name,
                Learner__r.Email
            FROM Learning_Material_Instance__c
            WHERE Material__c = :courseId
            ORDER BY Learner__r.Name
            LIMIT 500
        ]) {
            AssignmentRow row = new AssignmentRow();
            row.instanceId = inst.Id;
            row.userId = inst.Learner__c;
            row.userName = inst.Learner__r != null ? inst.Learner__r.Name : null;
            row.userEmail = inst.Learner__r != null ? inst.Learner__r.Email : null;
            row.status = inst.Status__c;
            row.progress = inst.Progress__c;
            row.score = inst.Score__c;
            row.startedOn = inst.Started_On__c;
            row.completedOn = inst.Completed_On__c;
            rows.add(row);
        }
        return rows;
    }

    @AuraEnabled
    public static Id updateMaterial(
        Id materialId,
        String title,
        String description,
        Boolean active,
        Decimal duration,
        String materialType,
        String materialUrl,
        Date startDate,
        Date endDate
    ) {
        if (materialId == null) {
            throw new AuraHandledException('Material Id is required.');
        }
        if (String.isBlank(title)) {
            throw new AuraHandledException('Title is required.');
        }
        validateAvailabilityWindow(startDate, endDate);
        Learning_Material__c material = [
            SELECT
                Id,
                Title__c,
                Description__c,
                Active__c,
                Duration__c,
                Material_Type__c,
                Material_URL__c,
                Effective_Start_Date__c,
                Effective_End_Date__c,
                Passing_Score__c,
                Quiz_Time_Limit_Minutes__c,
                Quiz_Questions__c,
                Max_Attempts__c,
                Show_Results__c
            FROM Learning_Material__c
            WHERE Id = :materialId
            LIMIT 1
        ];
        material.Title__c = title.trim();
        material.Description__c = description;
        material.Active__c = active == true;
        material.Duration__c = duration;
        material.Material_URL__c = materialUrl;
        if (String.isNotBlank(materialType) && materialType != material.Material_Type__c) {
            material.Material_Type__c = materialType;
            if (materialType == 'Quiz' && String.isBlank(material.Quiz_Questions__c)) {
                material.Passing_Score__c = material.Passing_Score__c == null ? 70 : material.Passing_Score__c;
                material.Quiz_Time_Limit_Minutes__c = material.Quiz_Time_Limit_Minutes__c == null
                    ? 30
                    : material.Quiz_Time_Limit_Minutes__c;
                material.Show_Results__c = true;
                material.Max_Attempts__c = material.Max_Attempts__c == null ? 3 : material.Max_Attempts__c;
                material.Quiz_Questions__c = JSON.serialize(
                    new Map<String, Object>{
                        'version' => '1.1',
                        'totalQuestions' => 1,
                        'totalPoints' => 1,
                        'questions' => new List<Object>{
                            new Map<String, Object>{
                                'id' => 'q1',
                                'question' => 'Sample question - replace in Quiz Editor',
                                'type' => 'single-choice',
                                'options' => new List<String>{ 'A', 'B', 'C', 'D' },
                                'correctAnswer' => 0,
                                'points' => 1,
                                'explanation' => ''
                            }
                        }
                    }
                );
            }
        }
        // Availability window is course-level only; clear stray dates on children.
        if (material.Material_Type__c == 'Course') {
            material.Effective_Start_Date__c = startDate;
            material.Effective_End_Date__c = endDate;
        } else {
            material.Effective_Start_Date__c = null;
            material.Effective_End_Date__c = null;
        }
        update material;
        return material.Id;
    }

    @AuraEnabled
    public static Id createMaterial(
        String title,
        String materialType,
        Id parentMaterialId,
        Boolean active
    ) {
        if (String.isBlank(title)) {
            throw new AuraHandledException('Title is required.');
        }
        if (String.isBlank(materialType)) {
            throw new AuraHandledException('Material type is required.');
        }

        Learning_Material__c material = new Learning_Material__c(
            Title__c = title.trim(),
            Material_Type__c = materialType,
            Parent_Material__c = parentMaterialId,
            Active__c = active == true
        );

        if (materialType == 'Quiz') {
            material.Passing_Score__c = 70;
            material.Quiz_Time_Limit_Minutes__c = 30;
            material.Show_Results__c = true;
            material.Max_Attempts__c = 3;
            material.Quiz_Questions__c = JSON.serialize(
                new Map<String, Object>{
                    'version' => '1.1',
                    'totalQuestions' => 1,
                    'totalPoints' => 1,
                    'questions' => new List<Object>{
                        new Map<String, Object>{
                            'id' => 'q1',
                            'question' => 'Sample question - replace in Quiz Editor',
                            'type' => 'single-choice',
                            'options' => new List<String>{ 'A', 'B', 'C', 'D' },
                            'correctAnswer' => 0,
                            'points' => 1,
                            'explanation' => ''
                        }
                    }
                }
            );
        }

        insert material;
        return material.Id;
    }

    @AuraEnabled
    public static AssignResult assignToUser(Id userId, Id materialId) {
        if (userId == null || materialId == null) {
            throw new AuraHandledException('User and material are required.');
        }
        return assignToUsers(new Set<Id>{ userId }, materialId);
    }

    @AuraEnabled(cacheable=true)
    public static List<TerritoryTreeNode> getTerritoryTreeForMaterial(Id materialId) {
        Map<String, Learning_Material_Territory_Alignment__c> alignedByTerritory =
            loadAlignmentsByTerritory(resolveCourseId(materialId));
        return buildTerritoryTree(alignedByTerritory);
    }

    @AuraEnabled
    public static TerritorySaveResult saveTerritoryAlignments(
        Id materialId,
        List<Id> territoryIds
    ) {
        if (materialId == null) {
            throw new AuraHandledException('Select a course before saving territory alignment.');
        }
        Id courseId = resolveCourseId(materialId);

        Set<Id> requestedTerritoryIds = territoryIds == null
            ? new Set<Id>()
            : new Set<Id>(territoryIds);

        List<Learning_Material_Territory_Alignment__c> existing = [
            SELECT
                Id,
                Territory2_Id__c,
                Is_Active__c
            FROM Learning_Material_Territory_Alignment__c
            WHERE Learning_Material__c = :courseId
        ];

        List<Learning_Material_Territory_Alignment__c> toDelete =
            new List<Learning_Material_Territory_Alignment__c>();
        List<Learning_Material_Territory_Alignment__c> toUpdate =
            new List<Learning_Material_Territory_Alignment__c>();
        Set<Id> existingTerritoryIds = new Set<Id>();

        for (Learning_Material_Territory_Alignment__c alignment : existing) {
            Id territoryId = parseTerritoryId(alignment.Territory2_Id__c);
            if (territoryId == null) {
                toDelete.add(alignment);
                continue;
            }
            existingTerritoryIds.add(territoryId);
            if (!requestedTerritoryIds.contains(territoryId)) {
                toDelete.add(alignment);
                continue;
            }
            alignment.Is_Active__c = true;
            toUpdate.add(alignment);
        }
        if (!toDelete.isEmpty()) {
            delete toDelete;
        }
        if (!toUpdate.isEmpty()) {
            update toUpdate;
        }

        List<Learning_Material_Territory_Alignment__c> toInsert =
            new List<Learning_Material_Territory_Alignment__c>();
        for (Id territoryId : requestedTerritoryIds) {
            if (territoryId == null || existingTerritoryIds.contains(territoryId)) {
                continue;
            }
            toInsert.add(
                new Learning_Material_Territory_Alignment__c(
                    Learning_Material__c = courseId,
                    Territory2_Id__c = String.valueOf(territoryId),
                    Is_Active__c = true
                )
            );
        }
        if (!toInsert.isEmpty()) {
            insert toInsert;
        }

        Set<Id> previousTerritoryIds = new Set<Id>(existingTerritoryIds);
        Set<Id> removedTerritoryIds = new Set<Id>();
        for (Id previousId : previousTerritoryIds) {
            if (!requestedTerritoryIds.contains(previousId)) {
                removedTerritoryIds.add(previousId);
            }
        }

        Set<Id> userIds = loadActiveUserIdsForTerritories(requestedTerritoryIds);
        AssignResult assignResult = assignToUsers(userIds, courseId);
        Integer removedInstanceCount = removeInstancesForTerritories(
            courseId,
            removedTerritoryIds,
            userIds
        );

        TerritorySaveResult result = new TerritorySaveResult();
        result.territoryCount = requestedTerritoryIds.size();
        result.userCount = assignResult.userCount;
        result.instanceCount = assignResult.instanceCount;
        result.removedInstanceCount = removedInstanceCount;
        return result;
    }

    private static AssignResult assignToUsers(Set<Id> userIds, Id materialId) {
        AssignResult result = new AssignResult();
        result.instanceCount = 0;
        result.userCount = 0;
        if (userIds == null || userIds.isEmpty() || materialId == null) {
            return result;
        }

        Id courseId = resolveCourseId(materialId);
        Set<Id> materialIds = collectCourseMaterialIds(courseId, materialId);

        Map<String, Learning_Material_Instance__c> existingByKey =
            new Map<String, Learning_Material_Instance__c>();
        for (Learning_Material_Instance__c inst : [
            SELECT Id, Learner__c, Material__c
            FROM Learning_Material_Instance__c
            WHERE Learner__c IN :userIds AND Material__c IN :materialIds
        ]) {
            existingByKey.put(instanceKey(inst.Learner__c, inst.Material__c), inst);
        }

        List<Learning_Material_Instance__c> toInsert = new List<Learning_Material_Instance__c>();
        Set<Id> touchedUsers = new Set<Id>();

        for (Id userId : userIds) {
            if (userId == null) {
                continue;
            }
            touchedUsers.add(userId);
            for (Id mid : materialIds) {
                String key = instanceKey(userId, mid);
                if (!existingByKey.containsKey(key)) {
                    Learning_Material_Instance__c created = new Learning_Material_Instance__c(
                        Learner__c = userId,
                        Material__c = mid,
                        Status__c = 'Not Started',
                        Progress__c = 0,
                        Attempt_Number__c = 0
                    );
                    toInsert.add(created);
                    existingByKey.put(key, created);
                }
            }
        }

        if (!toInsert.isEmpty()) {
            insert toInsert;
        }

        result.userCount = touchedUsers.size();
        result.instanceCount = existingByKey.size();
        if (!touchedUsers.isEmpty()) {
            for (Id userId : touchedUsers) {
                Learning_Material_Instance__c courseInst = existingByKey.get(
                    instanceKey(userId, courseId)
                );
                if (courseInst != null && courseInst.Id != null) {
                    result.courseInstanceId = courseInst.Id;
                    break;
                }
            }
        }
        return result;
    }

    private static Integer removeInstancesForTerritories(
        Id courseId,
        Set<Id> removedTerritoryIds,
        Set<Id> retainedUserIds
    ) {
        if (courseId == null || removedTerritoryIds == null || removedTerritoryIds.isEmpty()) {
            return 0;
        }
        Set<Id> usersToRemove = loadActiveUserIdsForTerritories(removedTerritoryIds);
        if (retainedUserIds != null) {
            usersToRemove.removeAll(retainedUserIds);
        }
        if (usersToRemove.isEmpty()) {
            return 0;
        }

        Set<Id> materialIds = collectCourseMaterialIds(courseId, courseId);
        // Only remove assignments the learner has not started. Anything in progress, completed
        // or scored is kept, so unticking a territory never erases a rep's training record.
        List<Learning_Material_Instance__c> toDelete = [
            SELECT Id
            FROM Learning_Material_Instance__c
            WHERE Learner__c IN :usersToRemove
              AND Material__c IN :materialIds
              AND (Status__c = null OR Status__c = 'Not Started')
        ];
        Integer removedCount = toDelete.size();
        if (!toDelete.isEmpty()) {
            delete toDelete;
        }
        return removedCount;
    }

    private static Set<Id> loadMaterialIdsAlignedToBusinessUnit(String buTerritoryFilter) {
        Set<Id> materialIds = new Set<Id>();
        Id buTerritoryId = parseTerritoryId(buTerritoryFilter);
        if (buTerritoryId == null) {
            return materialIds;
        }

        Set<Id> scopedTerritoryIds = TerritoryHierarchyService.expandTerritoryHierarchy(
            new Set<Id>{ buTerritoryId }
        );
        if (scopedTerritoryIds.isEmpty()) {
            return materialIds;
        }

        Set<String> territoryKeys = new Set<String>();
        for (Id territoryId : scopedTerritoryIds) {
            territoryKeys.add(String.valueOf(territoryId));
        }

        for (Learning_Material_Territory_Alignment__c alignment : [
            SELECT Learning_Material__c
            FROM Learning_Material_Territory_Alignment__c
            WHERE
                Territory2_Id__c IN :territoryKeys
                AND Is_Active__c = TRUE
                AND Learning_Material__c != NULL
        ]) {
            materialIds.add(alignment.Learning_Material__c);
        }
        return materialIds;
    }

    private static Id resolveCourseId(Id materialId) {
        if (materialId == null) {
            throw new AuraHandledException('Material Id is required.');
        }
        Learning_Material__c root = [
            SELECT Id, Material_Type__c, Parent_Material__c
            FROM Learning_Material__c
            WHERE Id = :materialId
            LIMIT 1
        ];
        return root.Material_Type__c == 'Course'
            ? root.Id
            : (root.Parent_Material__c != null ? root.Parent_Material__c : root.Id);
    }

    private static Set<Id> collectCourseMaterialIds(Id courseId, Id materialId) {
        Set<Id> materialIds = new Set<Id>{ courseId };
        for (Learning_Material__c child : [
            SELECT Id
            FROM Learning_Material__c
            WHERE Parent_Material__c = :courseId AND Active__c = true
        ]) {
            materialIds.add(child.Id);
        }
        if (materialId != null && materialId != courseId) {
            materialIds.add(materialId);
        }
        return materialIds;
    }

    private static String instanceKey(Id userId, Id materialId) {
        return String.valueOf(userId) + ':' + String.valueOf(materialId);
    }

    private static void validateAvailabilityWindow(Date startDate, Date endDate) {
        if (startDate != null && endDate != null && endDate < startDate) {
            throw new AuraHandledException('Available Until must be on or after Available From.');
        }
    }

    private static Map<String, Learning_Material_Territory_Alignment__c> loadAlignmentsByTerritory(
        Id courseId
    ) {
        Map<String, Learning_Material_Territory_Alignment__c> aligned =
            new Map<String, Learning_Material_Territory_Alignment__c>();
        if (courseId == null) {
            return aligned;
        }
        for (Learning_Material_Territory_Alignment__c alignment : [
            SELECT
                Id,
                Territory2_Id__c,
                Effective_Start_Date__c,
                Effective_End_Date__c,
                Is_Active__c
            FROM Learning_Material_Territory_Alignment__c
            WHERE Learning_Material__c = :courseId AND Is_Active__c = TRUE
        ]) {
            if (alignment.Territory2_Id__c != null) {
                aligned.put(alignment.Territory2_Id__c, alignment);
            }
        }
        return aligned;
    }

    private static List<TerritoryTreeNode> buildTerritoryTree(
        Map<String, Learning_Material_Territory_Alignment__c> alignedByTerritory
    ) {
        List<Territory2> territories = [
            SELECT Id, Name, ParentTerritory2Id, External_ID__c, Territory_Type__c
            FROM Territory2
            WHERE External_ID__c LIKE 'TERR_%'
            WITH USER_MODE
            ORDER BY Name ASC
            LIMIT 5000
        ];
        if (territories.isEmpty()) {
            return new List<TerritoryTreeNode>();
        }

        Id headOfficeId = null;
        for (Territory2 territory : territories) {
            if (territory.External_ID__c == 'TERR_HEAD_OFFICE') {
                headOfficeId = territory.Id;
                break;
            }
        }

        Map<Id, List<TerritoryTreeNode>> childrenByParent = new Map<Id, List<TerritoryTreeNode>>();
        Map<Id, TerritoryTreeNode> nodesById = new Map<Id, TerritoryTreeNode>();

        for (Territory2 territory : territories) {
            TerritoryTreeNode node = new TerritoryTreeNode();
            node.id = territory.Id;
            node.name = territory.Name;
            node.parentId = territory.ParentTerritory2Id;
            node.isBusinessUnit =
                isBusinessUnitTerritory(territory, headOfficeId);
            Learning_Material_Territory_Alignment__c alignment =
                alignedByTerritory.get(String.valueOf(territory.Id));
            node.aligned = alignment != null;
            if (alignment != null) {
                node.effectiveStartDate = alignment.Effective_Start_Date__c;
                node.effectiveEndDate = alignment.Effective_End_Date__c;
            }
            node.children = new List<TerritoryTreeNode>();
            node.hasChildren = false;
            nodesById.put(territory.Id, node);
        }

        for (Territory2 territory : territories) {
            TerritoryTreeNode node = nodesById.get(territory.Id);
            if (
                territory.ParentTerritory2Id != null &&
                nodesById.containsKey(territory.ParentTerritory2Id)
            ) {
                if (!childrenByParent.containsKey(territory.ParentTerritory2Id)) {
                    childrenByParent.put(territory.ParentTerritory2Id, new List<TerritoryTreeNode>());
                }
                childrenByParent.get(territory.ParentTerritory2Id).add(node);
            }
        }

        for (Id parentId : childrenByParent.keySet()) {
            if (nodesById.containsKey(parentId)) {
                List<TerritoryTreeNode> children = childrenByParent.get(parentId);
                children.sort(new TerritoryNodeNameComparator());
                nodesById.get(parentId).children = children;
                nodesById.get(parentId).hasChildren = !children.isEmpty();
            }
        }

        List<TerritoryTreeNode> roots = new List<TerritoryTreeNode>();
        for (Territory2 territory : territories) {
            TerritoryTreeNode node = nodesById.get(territory.Id);
            if (
                territory.ParentTerritory2Id == null ||
                !nodesById.containsKey(territory.ParentTerritory2Id)
            ) {
                roots.add(node);
            }
        }
        roots.sort(new TerritoryNodeNameComparator());
        return roots;
    }

    private static Boolean isBusinessUnitTerritory(Territory2 territory, Id headOfficeId) {
        if (territory == null) {
            return false;
        }
        if (territory.Territory_Type__c == 'Business_Unit') {
            return true;
        }
        if (
            String.isNotBlank(territory.External_ID__c) &&
            territory.External_ID__c.startsWith('TERR_BU_')
        ) {
            return true;
        }
        return headOfficeId != null && territory.ParentTerritory2Id == headOfficeId;
    }

    private static Set<Id> loadActiveUserIdsForTerritories(Set<Id> territoryIds) {
        Set<Id> userIds = new Set<Id>();
        if (territoryIds == null || territoryIds.isEmpty()) {
            return userIds;
        }
        for (UserTerritory2Association association : [
            SELECT UserId
            FROM UserTerritory2Association
            WHERE Territory2Id IN :territoryIds AND User.IsActive = TRUE
            WITH SYSTEM_MODE
        ]) {
            if (association.UserId != null) {
                userIds.add(association.UserId);
            }
        }
        return userIds;
    }

    private static Id parseTerritoryId(String territoryIdValue) {
        if (String.isBlank(territoryIdValue)) {
            return null;
        }
        try {
            return (Id) territoryIdValue;
        } catch (Exception ex) {
            return null;
        }
    }

    private class TerritoryNodeNameComparator implements Comparator<TerritoryTreeNode> {
        public Integer compare(TerritoryTreeNode left, TerritoryTreeNode right) {
            String leftName = left != null && left.name != null ? left.name : '';
            String rightName = right != null && right.name != null ? right.name : '';
            return leftName.compareTo(rightName);
        }
    }

    @AuraEnabled
    public static FileUploadResult finalizeMaterialFileUpload(Id materialId, Id contentDocumentId) {
        if (materialId == null || contentDocumentId == null) {
            throw new AuraHandledException('Material and file are required.');
        }

        Learning_Material__c material = [
            SELECT Id, Title__c, Material_URL__c, Content_Document_Id__c
            FROM Learning_Material__c
            WHERE Id = :materialId
            LIMIT 1
        ];

        List<ContentDocumentLink> existingLinks = [
            SELECT Id
            FROM ContentDocumentLink
            WHERE ContentDocumentId = :contentDocumentId AND LinkedEntityId = :materialId
            LIMIT 1
        ];
        if (existingLinks.isEmpty()) {
            insert new ContentDocumentLink(
                ContentDocumentId = contentDocumentId,
                LinkedEntityId = materialId,
                ShareType = 'V',
                Visibility = 'AllUsers'
            );
        }

        ContentVersion version = [
            SELECT Id, Title
            FROM ContentVersion
            WHERE ContentDocumentId = :contentDocumentId AND IsLatest = true
            LIMIT 1
        ];

        List<ContentDistribution> distributions = [
            SELECT Id, DistributionPublicUrl, ContentDownloadUrl
            FROM ContentDistribution
            WHERE ContentVersionId = :version.Id
            ORDER BY CreatedDate DESC
            LIMIT 1
        ];

        ContentDistribution distribution;
        if (distributions.isEmpty()) {
            String distName = String.isBlank(material.Title__c)
                ? version.Title
                : material.Title__c;
            if (distName != null && distName.length() > 100) {
                distName = distName.substring(0, 100);
            }
            distribution = new ContentDistribution(
                Name = distName,
                ContentVersionId = version.Id,
                PreferencesAllowViewInBrowser = true,
                PreferencesLinkLatestVersion = true,
                PreferencesNotifyOnVisit = false,
                PreferencesPasswordRequired = false,
                PreferencesAllowOriginalDownload = true
            );
            insert distribution;
            distribution = [
                SELECT Id, DistributionPublicUrl, ContentDownloadUrl
                FROM ContentDistribution
                WHERE Id = :distribution.Id
                LIMIT 1
            ];
        } else {
            distribution = distributions[0];
        }

        String url = String.isNotBlank(distribution.ContentDownloadUrl)
            ? distribution.ContentDownloadUrl
            : distribution.DistributionPublicUrl;
        if (String.isBlank(url)) {
            url =
                System.URL.getOrgDomainUrl().toExternalForm() +
                '/sfc/servlet.shepherd/document/download/' +
                String.valueOf(contentDocumentId);
        }

        material.Content_Document_Id__c = String.valueOf(contentDocumentId);
        material.Material_URL__c = url;
        update material;

        FileUploadResult result = new FileUploadResult();
        result.materialId = material.Id;
        result.contentDocumentId = contentDocumentId;
        result.contentVersionId = version.Id;
        result.materialUrl = url;
        return result;
    }
}