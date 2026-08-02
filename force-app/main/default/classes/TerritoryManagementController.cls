public with sharing class TerritoryManagementController {

    public class TerritoryAssignment {
        @AuraEnabled public Id associationId;
        @AuraEnabled public Id userId;
        @AuraEnabled public String userName;
        @AuraEnabled public String role;
    }

    public class TerritoryTreeNode {
        @AuraEnabled public Id id;
        @AuraEnabled public String name;
        @AuraEnabled public String externalId;
        @AuraEnabled public String level;
        @AuraEnabled public Id parentId;
        @AuraEnabled public Boolean hasChildren;
        @AuraEnabled public Boolean isVacant;
        @AuraEnabled public Boolean canEdit;
        @AuraEnabled public Boolean canDelete;
        @AuraEnabled public Boolean canAddChild;
        @AuraEnabled public List<TerritoryAssignment> assignments;
        @AuraEnabled public List<TerritoryTreeNode> children;
    }

    public class UserOption {
        @AuraEnabled public Id id;
        @AuraEnabled public String name;
        @AuraEnabled public String username;
        @AuraEnabled public String title;
        @AuraEnabled public String businessUnit;
        @AuraEnabled public String label;
    }

    @AuraEnabled(cacheable=true)
    public static List<TerritoryAdminService.LineSummary> getProductLines() {
        return TerritoryAdminService.getProductLines();
    }

    @AuraEnabled(cacheable=true)
    public static List<TerritoryAdminService.ParentOption> getParentOptions(String childLevel) {
        return TerritoryAdminService.getParentOptions(childLevel);
    }

    @AuraEnabled
    public static Id saveTerritory(TerritoryAdminService.TerritoryForm form) {
        return TerritoryAdminService.saveTerritory(form);
    }

    @AuraEnabled
    public static Id createProductLine(String name, String code, String therapyArea) {
        return TerritoryAdminService.createProductLine(name, code, therapyArea);
    }

    @AuraEnabled
    public static void deleteTerritory(Id territoryId) {
        TerritoryAdminService.deleteTerritory(territoryId);
    }

    @AuraEnabled
    public static TerritoryAdminService.CreatedUserResult createPharmaUser(
        String firstName,
        String lastName,
        String teamCode,
        String roleKey,
        Id territoryId,
        String roleInTerritory
    ) {
        return TerritoryAdminService.createPharmaUser(
            firstName,
            lastName,
            teamCode,
            roleKey,
            territoryId,
            roleInTerritory
        );
    }

    @AuraEnabled
    public static void syncDefaultLineProductAlignments() {
        TerritoryAdminService.syncDefaultLineProductAlignments();
    }

    @AuraEnabled(cacheable=true)
    public static List<TerritoryTreeNode> getTerritoryTree() {
        String pharmaPrefix = TerritoryModuleCleanup.PHARMA_EXTERNAL_ID_PREFIX + '%';
        List<Territory2> territories = [
            SELECT Id, Name, ParentTerritory2Id, External_ID__c
            FROM Territory2
            WHERE External_ID__c LIKE :pharmaPrefix
            WITH USER_MODE
            ORDER BY Name ASC
            LIMIT 500
        ];
        if (territories.isEmpty()) {
            return new List<TerritoryTreeNode>();
        }

        Set<Id> territoryIds = new Map<Id, Territory2>(territories).keySet();
        Map<Id, List<TerritoryAssignment>> assignmentsByTerritory = loadAssignments(territoryIds);
        Map<Id, List<TerritoryTreeNode>> childrenByParent = new Map<Id, List<TerritoryTreeNode>>();
        Map<Id, TerritoryTreeNode> nodesById = new Map<Id, TerritoryTreeNode>();
        Set<Id> childParentIds = new Set<Id>();

        for (Territory2 territory : territories) {
            TerritoryTreeNode node = buildNode(territory, assignmentsByTerritory.get(territory.Id));
            nodesById.put(territory.Id, node);
            if (territory.ParentTerritory2Id != null) {
                childParentIds.add(territory.ParentTerritory2Id);
                if (!childrenByParent.containsKey(territory.ParentTerritory2Id)) {
                    childrenByParent.put(territory.ParentTerritory2Id, new List<TerritoryTreeNode>());
                }
                childrenByParent.get(territory.ParentTerritory2Id).add(node);
            }
        }

        for (Id parentId : childrenByParent.keySet()) {
            if (nodesById.containsKey(parentId)) {
                nodesById.get(parentId).children = childrenByParent.get(parentId);
                nodesById.get(parentId).hasChildren = !childrenByParent.get(parentId).isEmpty();
            }
        }

        List<TerritoryTreeNode> roots = new List<TerritoryTreeNode>();
        for (Territory2 territory : territories) {
            TerritoryTreeNode node = nodesById.get(territory.Id);
            if (node.hasChildren == null) {
                node.hasChildren = false;
                node.children = new List<TerritoryTreeNode>();
            }
            if (territory.ParentTerritory2Id == null || !nodesById.containsKey(territory.ParentTerritory2Id)) {
                roots.add(node);
            }
        }

        roots.sort(new TerritoryNodeNameComparator());
        sortChildrenRecursively(roots);
        return roots;
    }

    @AuraEnabled(cacheable=true)
    public static List<UserOption> getAssignableUsers(String searchTerm) {
        String term = String.isBlank(searchTerm) ? null : '%' + String.escapeSingleQuotes(searchTerm.trim()) + '%';
        String soql =
            'SELECT Id, Name, Username, Title, Department, Division FROM User WHERE IsActive = TRUE AND Username LIKE \'%pharma%\'';
        if (term != null) {
            soql += ' AND (Name LIKE :term OR Username LIKE :term OR Title LIKE :term'
                + ' OR Department LIKE :term OR Division LIKE :term)';
        }
        soql += ' WITH USER_MODE ORDER BY Name ASC LIMIT 50';

        List<UserOption> options = new List<UserOption>();
        for (User userRecord : Database.query(soql)) {
            UserOption option = new UserOption();
            option.id = userRecord.Id;
            option.name = userRecord.Name;
            option.username = userRecord.Username;
            option.title = resolveTitle(userRecord);
            option.businessUnit = resolveBusinessUnit(userRecord);
            option.label = buildUserDisplayLabel(userRecord, option.title, option.businessUnit);
            options.add(option);
        }
        return options;
    }

    private static String resolveTitle(User userRecord) {
        if (String.isNotBlank(userRecord.Title)) {
            return userRecord.Title;
        }
        String username = userRecord.Username == null ? '' : userRecord.Username.toLowerCase();
        if (!username.endsWith('@pharma.demo')) {
            return null;
        }
        String localPart = username.substringBefore('@');
        if (localPart.endsWith('.dm')) {
            return 'District Manager';
        }
        if (localPart.endsWith('.mr')) {
            return 'Medical Rep';
        }
        return null;
    }

    private static String resolveBusinessUnit(User userRecord) {
        if (String.isNotBlank(userRecord.Department)) {
            return userRecord.Department;
        }
        if (String.isNotBlank(userRecord.Division)) {
            return userRecord.Division;
        }
        String username = userRecord.Username == null ? '' : userRecord.Username.toLowerCase();
        if (!username.endsWith('@pharma.demo')) {
            return null;
        }
        String localPart = username.substringBefore('@');
        if (!localPart.contains('.')) {
            return null;
        }
        return localPart.substringBefore('.').toUpperCase();
    }

    private static String buildUserDisplayLabel(User userRecord, String title, String businessUnit) {
        List<String> parts = new List<String>();
        if (String.isNotBlank(userRecord.Name)) {
            parts.add(userRecord.Name);
        }
        if (String.isNotBlank(title)) {
            parts.add(title);
        }
        if (String.isNotBlank(businessUnit)) {
            parts.add(businessUnit);
        }
        if (String.isNotBlank(userRecord.Username)) {
            parts.add(userRecord.Username);
        }
        return String.join(parts, ' · ');
    }

    @AuraEnabled(cacheable=true)
    public static String resolveAssignmentRole(Id userId) {
        if (userId == null) {
            return 'Medical Rep';
        }
        List<User> users = [
            SELECT Username, Title
            FROM User
            WHERE Id = :userId
            WITH USER_MODE
            LIMIT 1
        ];
        if (users.isEmpty()) {
            return 'Medical Rep';
        }
        User userRecord = users[0];
        if (String.isNotBlank(userRecord.Title)) {
            if (userRecord.Title == 'District Manager') {
                return 'District Manager';
            }
            if (userRecord.Title == 'Medical Rep') {
                return 'Medical Rep';
            }
            if (userRecord.Title == 'Sales Force Excellence' || userRecord.Title == 'SFE') {
                return 'SFE';
            }
        }
        String username = userRecord.Username == null ? '' : userRecord.Username.toLowerCase();
        if (username == 'admin@pharma.eg') {
            return 'SFE';
        }
        if (username.endsWith('.dm@pharma.demo')) {
            return 'District Manager';
        }
        if (username.endsWith('.mr@pharma.demo')) {
            return 'Medical Rep';
        }
        return 'Medical Rep';
    }

    @AuraEnabled
    public static void assignUserToTerritory(Id territoryId, Id userId, String role) {
        if (territoryId == null || userId == null) {
            throw new AuraHandledException('Territory and user are required.');
        }

        Boolean isLeaf = isLeafTerritory(territoryId);
        if (isLeaf) {
            delete as user [
                SELECT Id
                FROM UserTerritory2Association
                WHERE Territory2Id = :territoryId
                WITH USER_MODE
            ];
        }

        insert as user new UserTerritory2Association(
            UserId = userId,
            Territory2Id = territoryId,
            RoleInTerritory2 = String.isBlank(role) ? 'Medical Rep' : role
        );
    }

    @AuraEnabled
    public static void clearTerritoryAssignments(Id territoryId) {
        if (territoryId == null) {
            throw new AuraHandledException('Territory Id is required.');
        }
        delete as user [
            SELECT Id
            FROM UserTerritory2Association
            WHERE Territory2Id = :territoryId
            WITH USER_MODE
        ];
    }

    private static Map<Id, List<TerritoryAssignment>> loadAssignments(Set<Id> territoryIds) {
        Map<Id, List<TerritoryAssignment>> assignmentsByTerritory = new Map<Id, List<TerritoryAssignment>>();
        for (UserTerritory2Association association : [
            SELECT Id, Territory2Id, UserId, RoleInTerritory2, User.Name
            FROM UserTerritory2Association
            WHERE Territory2Id IN :territoryIds
            WITH USER_MODE
            ORDER BY User.Name ASC
        ]) {
            if (!assignmentsByTerritory.containsKey(association.Territory2Id)) {
                assignmentsByTerritory.put(association.Territory2Id, new List<TerritoryAssignment>());
            }
            TerritoryAssignment assignment = new TerritoryAssignment();
            assignment.associationId = association.Id;
            assignment.userId = association.UserId;
            assignment.userName = association.User?.Name;
            assignment.role = association.RoleInTerritory2;
            assignmentsByTerritory.get(association.Territory2Id).add(assignment);
        }
        return assignmentsByTerritory;
    }

    private static TerritoryTreeNode buildNode(Territory2 territory, List<TerritoryAssignment> assignments) {
        TerritoryTreeNode node = new TerritoryTreeNode();
        node.id = territory.Id;
        node.name = territory.Name;
        node.externalId = territory.External_ID__c;
        node.level = TerritoryAdminService.resolveLevel(territory.External_ID__c);
        node.parentId = territory.ParentTerritory2Id;
        node.assignments = assignments == null ? new List<TerritoryAssignment>() : assignments;
        node.isVacant = node.assignments.isEmpty();
        node.children = new List<TerritoryTreeNode>();
        node.hasChildren = false;
        node.canEdit = territory.External_ID__c != 'TERR_HEAD_OFFICE';
        node.canDelete = node.canEdit;
        node.canAddChild = node.level != 'MR';
        return node;
    }

    private static Boolean isLeafTerritory(Id territoryId) {
        Integer childCount = [
            SELECT COUNT()
            FROM Territory2
            WHERE ParentTerritory2Id = :territoryId
            WITH USER_MODE
        ];
        return childCount == 0;
    }

    private static void sortChildrenRecursively(List<TerritoryTreeNode> nodes) {
        if (nodes == null) {
            return;
        }
        nodes.sort(new TerritoryNodeNameComparator());
        for (TerritoryTreeNode node : nodes) {
            if (node.children != null && !node.children.isEmpty()) {
                sortChildrenRecursively(node.children);
            }
        }
    }

    private class TerritoryNodeNameComparator implements Comparator<TerritoryTreeNode> {
        public Integer compare(TerritoryTreeNode a, TerritoryTreeNode b) {
            String left = a != null && a.name != null ? a.name : '';
            String right = b != null && b.name != null ? b.name : '';
            return left.compareTo(right);
        }
    }
}
