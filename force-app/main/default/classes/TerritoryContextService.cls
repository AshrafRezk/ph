public without sharing class TerritoryContextService {
    private static final String ALL_ASSIGNED_LABEL = 'All assigned territories';

    public class TerritoryNode {
        @AuraEnabled public Id id;
        @AuraEnabled public String name;
        @AuraEnabled public String externalId;
        @AuraEnabled public String level;
        @AuraEnabled public Id parentId;
        @AuraEnabled public Boolean hasChildren;
        @AuraEnabled public List<TerritoryNode> children;
    }

    public class SwitcherContext {
        @AuraEnabled public Id selectedTerritoryId;
        @AuraEnabled public String selectedTerritoryName;
        @AuraEnabled public String selectedLevel;
        @AuraEnabled public Boolean usingAllAssigned;
        @AuraEnabled public Boolean hasAssignment;
        @AuraEnabled public List<TerritoryNode> tree;
    }

    // Seats and the saved selection are read once per request (Home and Planner ask per card), and the
    // selection cache is cleared whenever it is written. Off in tests by default, because tests seat users as they go.
    @TestVisible private static Boolean cacheEnabled = !Test.isRunningTest();
    private static Map<Id, Set<Id>> assignedCache = new Map<Id, Set<Id>>();

    public static Set<Id> getAssignedTerritoryIds(Id userId) {
        Set<Id> territoryIds = new Set<Id>();
        if (userId == null) {
            return territoryIds;
        }
        if (cacheEnabled && assignedCache.containsKey(userId)) {
            return new Set<Id>(assignedCache.get(userId));
        }
        for (UserTerritory2Association assignment : [
            SELECT Territory2Id, RoleInTerritory2
            FROM UserTerritory2Association
            WHERE UserId = :userId
            WITH SYSTEM_MODE
        ]) {
            territoryIds.add(assignment.Territory2Id);
        }
        // Area Managers on a line with no National seat get line-level scope.
        // Brand Managers seated on a Line already expand to that line's districts.
        Set<Id> result = TerritoryHierarchyService.promoteActingNationalScope(userId, territoryIds);
        if (cacheEnabled) {
            assignedCache.put(userId, new Set<Id>(result));
        }
        return result;
    }

    public static Set<Id> getSwitchableTerritoryIds(Id userId) {
        return TerritoryHierarchyService.expandTerritoryHierarchy(getAssignedTerritoryIds(userId));
    }

    public static Set<Id> getEffectiveTerritoryIds(Id userId) {
        Set<Id> assigned = getAssignedTerritoryIds(userId);
        if (userId == null || userId != UserInfo.getUserId()) {
            return assigned;
        }
        Id selectedId = getSelectedTerritoryId();
        if (selectedId == null) {
            return assigned;
        }
        Set<Id> switchable = TerritoryHierarchyService.expandTerritoryHierarchy(assigned);
        if (!switchable.contains(selectedId)) {
            clearSelectedTerritory();
            return assigned;
        }
        return new Set<Id>{ selectedId };
    }

    // The saved selection is read once per request: Home and Planner ask for it per account group,
    // which pushed one dashboard load past 100 queries. Cleared whenever the selection is written.
    private static Boolean selectionLoaded = false;
    private static Id selectionCache;

    public static Id getSelectedTerritoryId() {
        if (cacheEnabled && selectionLoaded) {
            return selectionCache;
        }
        // Read only the running user's own hierarchy row. Do not use getValues(),
        // which inherits org/profile defaults and can make every user look switched.
        User_Territory_Context__c row = queryUserContextRow(UserInfo.getUserId());
        selectionCache = null;
        if (row != null && String.isNotBlank(row.Territory2_Id__c)) {
            try {
                selectionCache = (Id) row.Territory2_Id__c;
            } catch (Exception ex) {
                selectionCache = null;
            }
        }
        selectionLoaded = true;
        return selectionCache;
    }

    public static Boolean hasSelectedTerritory() {
        return getSelectedTerritoryId() != null;
    }

    public static SwitcherContext getSwitcherContext() {
        Id userId = UserInfo.getUserId();
        Set<Id> assigned = getAssignedTerritoryIds(userId);
        Set<Id> switchable = TerritoryHierarchyService.expandTerritoryHierarchy(assigned);
        Id selectedId = getSelectedTerritoryId();
        if (selectedId != null && !switchable.contains(selectedId)) {
            clearSelectedTerritory();
            selectedId = null;
        }

        SwitcherContext context = new SwitcherContext();
        context.hasAssignment = !assigned.isEmpty();
        context.usingAllAssigned = selectedId == null;
        context.selectedTerritoryId = selectedId;
        context.selectedTerritoryName = ALL_ASSIGNED_LABEL;
        context.selectedLevel = '';
        context.tree = buildTree(switchable);

        if (selectedId != null) {
            Territory2 selected = queryTerritory(selectedId);
            if (selected != null) {
                context.selectedTerritoryName = selected.Name;
                context.selectedLevel = resolveLevel(selected);
            }
        }
        return context;
    }

    public static SwitcherContext setSelectedTerritory(Id territoryId) {
        if (territoryId == null) {
            clearSelectedTerritory();
            return getSwitcherContext();
        }
        Set<Id> switchable = getSwitchableTerritoryIds(UserInfo.getUserId());
        if (!switchable.contains(territoryId)) {
            throw new AuraHandledException('You cannot switch into that territory.');
        }
        upsertUserRow(String.valueOf(territoryId));
        return getSwitcherContext();
    }

    @TestVisible
    static void clearSelectedTerritory() {
        upsertUserRow(null);
    }

    private static User_Territory_Context__c queryUserContextRow(Id userId) {
        if (userId == null) {
            return null;
        }
        List<User_Territory_Context__c> rows = [
            SELECT Id, Territory2_Id__c, SetupOwnerId
            FROM User_Territory_Context__c
            WHERE SetupOwnerId = :userId
            WITH SYSTEM_MODE
            LIMIT 1
        ];
        return rows.isEmpty() ? null : rows[0];
    }

    private static void upsertUserRow(String territoryIdValue) {
        Id userId = UserInfo.getUserId();
        User_Territory_Context__c existing = queryUserContextRow(userId);
        User_Territory_Context__c row = existing == null
            ? new User_Territory_Context__c(SetupOwnerId = userId)
            : existing;
        row.Territory2_Id__c = territoryIdValue;
        selectionLoaded = false;
        // Hierarchy custom-setting DML often requires Customize Application for
        // non-admins; SYSTEM_MODE keeps switch/clear working for all personas.
        Database.upsert(row, AccessLevel.SYSTEM_MODE);
    }

    private static List<TerritoryNode> buildTree(Set<Id> switchableIds) {
        List<TerritoryNode> roots = new List<TerritoryNode>();
        if (switchableIds == null || switchableIds.isEmpty()) {
            return roots;
        }

        Map<Id, TerritoryNode> nodesById = new Map<Id, TerritoryNode>();
        Map<Id, List<TerritoryNode>> childrenByParent = new Map<Id, List<TerritoryNode>>();
        String typeSelect = Schema.SObjectType.Territory2.fields.getMap().containsKey('Territory_Type__c')
            ? ', Territory_Type__c'
            : '';
        String soql =
            'SELECT Id, Name, ParentTerritory2Id, External_ID__c' +
            typeSelect +
            ' FROM Territory2 WHERE Id IN :switchableIds WITH SYSTEM_MODE ORDER BY Name';

        for (Territory2 territory : Database.query(soql)) {
            TerritoryNode node = new TerritoryNode();
            node.id = territory.Id;
            node.name = territory.Name;
            node.externalId = (String) territory.get('External_ID__c');
            node.parentId = territory.ParentTerritory2Id;
            node.level = resolveLevel(territory);
            node.hasChildren = false;
            node.children = new List<TerritoryNode>();
            nodesById.put(territory.Id, node);
            if (territory.ParentTerritory2Id != null) {
                if (!childrenByParent.containsKey(territory.ParentTerritory2Id)) {
                    childrenByParent.put(territory.ParentTerritory2Id, new List<TerritoryNode>());
                }
                childrenByParent.get(territory.ParentTerritory2Id).add(node);
            }
        }

        for (Id parentId : childrenByParent.keySet()) {
            if (nodesById.containsKey(parentId)) {
                TerritoryNode parent = nodesById.get(parentId);
                parent.children = childrenByParent.get(parentId);
                parent.hasChildren = !parent.children.isEmpty();
            }
        }

        for (Territory2 territory : Database.query(soql)) {
            TerritoryNode node = nodesById.get(territory.Id);
            if (
                territory.ParentTerritory2Id == null ||
                !nodesById.containsKey(territory.ParentTerritory2Id)
            ) {
                roots.add(node);
            }
        }
        return roots;
    }

    private static Territory2 queryTerritory(Id territoryId) {
        if (territoryId == null) {
            return null;
        }
        String typeSelect = Schema.SObjectType.Territory2.fields.getMap().containsKey('Territory_Type__c')
            ? ', Territory_Type__c'
            : '';
        String soql =
            'SELECT Id, Name, External_ID__c' +
            typeSelect +
            ' FROM Territory2 WHERE Id = :territoryId WITH SYSTEM_MODE LIMIT 1';
        List<Territory2> rows = Database.query(soql);
        return rows.isEmpty() ? null : rows[0];
    }

    private static String resolveLevel(Territory2 territory) {
        if (territory == null) {
            return 'Unknown';
        }
        String typeValue = Schema.SObjectType.Territory2.fields.getMap().containsKey('Territory_Type__c')
            ? (String) territory.get('Territory_Type__c')
            : null;
        if (String.isNotBlank(typeValue)) {
            if (typeValue == 'Head_Office') {
                return 'Head Office';
            }
            if (typeValue == 'Business_Unit') {
                return 'Business Unit';
            }
            if (typeValue == 'Line') {
                return 'Line';
            }
            if (typeValue == 'District') {
                return 'District';
            }
            if (typeValue == 'Position' || typeValue == 'MR') {
                return 'Position';
            }
        }
        String externalId = Schema.SObjectType.Territory2.fields.getMap().containsKey('External_ID__c')
            ? (String) territory.get('External_ID__c')
            : null;
        if (String.isBlank(externalId)) {
            return 'Unknown';
        }
        if (externalId == 'TERR_HEAD_OFFICE') {
            return 'Head Office';
        }
        if (externalId.startsWith('TERR_BU_')) {
            return 'Business Unit';
        }
        if (externalId.contains('_MR_') || externalId.startsWith('TERR_POS_')) {
            return 'Position';
        }
        if (externalId.contains('_DM_')) {
            return 'District';
        }
        if (externalId.startsWith('TERR_LINE_')) {
            return 'Line';
        }
        return 'Unknown';
    }

    public static Boolean hasSubordinateTerritories(Id userId) {
        return hasChildTerritories(getAssignedTerritoryIds(userId));
    }

    public static Boolean isAlignedOnRepTerritory() {
        // Assigned hierarchy/role wins over the territory switcher. A manager who
        // opens a leaf (MR) territory must still be treated as a manager so Coach
        // stays available without switching back. Anyone with a territory under
        // theirs is a manager for this check, even without a manager role name.
        Boolean managesSubordinates = hasSubordinateTerritories(UserInfo.getUserId());
        Boolean onlyRepTerritories = isAssignedOnlyToRepTerritories(UserInfo.getUserId());
        if (managesSubordinates || !onlyRepTerritories) {
            return false;
        }
        Id selectedId = getSelectedTerritoryId();
        if (selectedId != null) {
            Territory2 selected = queryTerritory(selectedId);
            String level = resolveLevel(selected);
            if (isRepLevel(level)) {
                return true;
            }
            if (level != 'Unknown') {
                return false;
            }
        }
        return true;
    }

    private static Boolean isRepLevel(String level) {
        return level == 'Position';
    }

    private static Boolean isAssignedOnlyToRepTerritories(Id userId) {
        if (userId == null) {
            return false;
        }
        List<UserTerritory2Association> assignments = [
            SELECT RoleInTerritory2, Territory2Id
            FROM UserTerritory2Association
            WHERE UserId = :userId
            WITH SYSTEM_MODE
        ];
        if (assignments.isEmpty()) {
            return false;
        }

        Boolean sawManagerRole = false;
        Boolean sawRepRole = false;
        Set<Id> territoryIds = new Set<Id>();
        for (UserTerritory2Association assignment : assignments) {
            String role = assignment.RoleInTerritory2 == null ? '' : assignment.RoleInTerritory2;
            if (role == 'Medical Rep') {
                sawRepRole = true;
            }
            if (
                role == 'District Manager' ||
                role == 'Region Manager' ||
                role == 'Line Manager' ||
                role == 'NSM'
            ) {
                sawManagerRole = true;
            }
            if (assignment.Territory2Id != null) {
                territoryIds.add(assignment.Territory2Id);
            }
        }
        if (sawManagerRole) {
            return false;
        }

        Integer knownCount = 0;
        Integer repCount = 0;
        for (Territory2 territory : queryTerritories(territoryIds)) {
            String level = resolveLevel(territory);
            if (level == 'Unknown') {
                continue;
            }
            knownCount++;
            if (isRepLevel(level)) {
                repCount++;
            }
        }
        if (knownCount > 0) {
            return repCount == knownCount;
        }
        return sawRepRole;
    }

    private static Boolean hasChildTerritories(Set<Id> territoryIds) {
        if (territoryIds == null || territoryIds.isEmpty()) {
            return false;
        }
        return ![
            SELECT Id
            FROM Territory2
            WHERE ParentTerritory2Id IN :territoryIds
            WITH SYSTEM_MODE
            LIMIT 1
        ].isEmpty();
    }

    private static List<Territory2> queryTerritories(Set<Id> territoryIds) {
        if (territoryIds == null || territoryIds.isEmpty()) {
            return new List<Territory2>();
        }
        String typeSelect = Schema.SObjectType.Territory2.fields.getMap().containsKey('Territory_Type__c')
            ? ', Territory_Type__c'
            : '';
        String soql =
            'SELECT Id, Name, External_ID__c' +
            typeSelect +
            ' FROM Territory2 WHERE Id IN :territoryIds WITH SYSTEM_MODE';
        return Database.query(soql);
    }
}