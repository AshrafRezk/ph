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

    public static Set<Id> getAssignedTerritoryIds(Id userId) {
        Set<Id> territoryIds = new Set<Id>();
        if (userId == null) {
            return territoryIds;
        }
        for (UserTerritory2Association assignment : [
            SELECT Territory2Id
            FROM UserTerritory2Association
            WHERE UserId = :userId
            WITH SYSTEM_MODE
        ]) {
            territoryIds.add(assignment.Territory2Id);
        }
        return territoryIds;
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

    public static Id getSelectedTerritoryId() {
        User_Territory_Context__c row = User_Territory_Context__c.getValues(UserInfo.getUserId());
        if (row == null || String.isBlank(row.Territory2_Id__c)) {
            return null;
        }
        try {
            return (Id) row.Territory2_Id__c;
        } catch (Exception ex) {
            return null;
        }
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

    private static void upsertUserRow(String territoryIdValue) {
        Id userId = UserInfo.getUserId();
        List<User_Territory_Context__c> existing = [
            SELECT Id, Territory2_Id__c
            FROM User_Territory_Context__c
            WHERE SetupOwnerId = :userId
            WITH SYSTEM_MODE
            LIMIT 1
        ];
        User_Territory_Context__c row = existing.isEmpty()
            ? new User_Territory_Context__c(SetupOwnerId = userId)
            : existing[0];
        row.Territory2_Id__c = territoryIdValue;
        upsert row;
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
            if (typeValue == 'Position') {
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
}
