/**
 * Hierarchical view of the running manager's subordinate territories and users.
 * Limited to territories where the user holds a manager role, plus any active delegation.
 */
public without sharing class MyTeamController {
    public class TeamUser {
        @AuraEnabled public Id userId;
        @AuraEnabled public String name;
        @AuraEnabled public String role;
    }

    public class TeamNode {
        @AuraEnabled public Id territoryId;
        @AuraEnabled public String name;
        @AuraEnabled public String level;
        @AuraEnabled public List<TeamUser> users;
        @AuraEnabled public List<TeamNode> children;
    }

    private static final Set<String> MANAGER_ROLES = new Set<String>{
        'District Manager',
        'Region Manager',
        'Line Manager',
        'NSM',
        'National Sales Manager',
        'Area Manager',
        'Business Unit Manager',
        'Brand Manager',
        'Trainer'
    };

    private static final Map<String, String> LEVEL_LABELS = new Map<String, String>{
        'Head_Office' => 'Head Office',
        'Business_Unit' => 'Business Unit',
        'Line' => 'Line',
        'District' => 'District',
        'Position' => 'Position'
    };

    @AuraEnabled(cacheable=true)
    public static List<TeamNode> getMyTeamTree() {
        Id userId = UserInfo.getUserId();
        Set<Id> roots = managerTerritoryIds(userId);
        Set<Id> territoryIds = TerritoryHierarchyService.expandTerritoryHierarchy(roots);
        territoryIds.addAll(DelegationService.getActiveDelegatedTerritoryIds(userId));
        territoryIds.remove(null);
        if (territoryIds.isEmpty()) {
            return new List<TeamNode>();
        }

        Map<Id, Territory2> territoryById = new Map<Id, Territory2>([
            SELECT Id, Name, ParentTerritory2Id, Territory_Type__c
            FROM Territory2
            WHERE Id IN :territoryIds
            WITH SYSTEM_MODE
        ]);
        Map<Id, List<TeamUser>> usersByTerritory = loadUsers(territoryIds);
        Map<Id, List<TeamNode>> childrenByParent = new Map<Id, List<TeamNode>>();
        Map<Id, TeamNode> nodesById = new Map<Id, TeamNode>();

        for (Territory2 territory : territoryById.values()) {
            TeamNode node = new TeamNode();
            node.territoryId = territory.Id;
            node.name = territory.Name;
            node.level = LEVEL_LABELS.containsKey(territory.Territory_Type__c)
                ? LEVEL_LABELS.get(territory.Territory_Type__c)
                : territory.Territory_Type__c;
            node.users = usersByTerritory.containsKey(territory.Id)
                ? usersByTerritory.get(territory.Id)
                : new List<TeamUser>();
            node.children = new List<TeamNode>();
            nodesById.put(territory.Id, node);
            if (territory.ParentTerritory2Id != null) {
                if (!childrenByParent.containsKey(territory.ParentTerritory2Id)) {
                    childrenByParent.put(territory.ParentTerritory2Id, new List<TeamNode>());
                }
                childrenByParent.get(territory.ParentTerritory2Id).add(node);
            }
        }

        for (Id parentId : childrenByParent.keySet()) {
            if (nodesById.containsKey(parentId)) {
                List<TeamNode> children = childrenByParent.get(parentId);
                children.sort(new TeamNodeNameComparator());
                nodesById.get(parentId).children = children;
            }
        }

        List<TeamNode> treeRoots = new List<TeamNode>();
        for (Territory2 territory : territoryById.values()) {
            if (territory.ParentTerritory2Id == null || !nodesById.containsKey(territory.ParentTerritory2Id)) {
                treeRoots.add(nodesById.get(territory.Id));
            }
        }
        treeRoots.sort(new TeamNodeNameComparator());
        return treeRoots;
    }

    private static Set<Id> managerTerritoryIds(Id userId) {
        Set<Id> roots = new Set<Id>();
        for (UserTerritory2Association assignment : [
            SELECT Territory2Id, RoleInTerritory2
            FROM UserTerritory2Association
            WHERE UserId = :userId AND Territory2Id != NULL AND RoleInTerritory2 != NULL
            WITH SYSTEM_MODE
        ]) {
            if (MANAGER_ROLES.contains(assignment.RoleInTerritory2)) {
                roots.add(assignment.Territory2Id);
            }
        }
        return roots;
    }

    private static Map<Id, List<TeamUser>> loadUsers(Set<Id> territoryIds) {
        Map<Id, List<TeamUser>> usersByTerritory = new Map<Id, List<TeamUser>>();
        for (UserTerritory2Association association : [
            SELECT Territory2Id, UserId, RoleInTerritory2, User.Name
            FROM UserTerritory2Association
            WHERE Territory2Id IN :territoryIds AND User.IsActive = TRUE
            WITH SYSTEM_MODE
            ORDER BY User.Name ASC
        ]) {
            if (!usersByTerritory.containsKey(association.Territory2Id)) {
                usersByTerritory.put(association.Territory2Id, new List<TeamUser>());
            }
            TeamUser person = new TeamUser();
            person.userId = association.UserId;
            person.name = association.User != null ? association.User.Name : null;
            person.role = association.RoleInTerritory2;
            usersByTerritory.get(association.Territory2Id).add(person);
        }
        return usersByTerritory;
    }

    private class TeamNodeNameComparator implements Comparator<TeamNode> {
        public Integer compare(TeamNode left, TeamNode right) {
            String leftName = left == null || left.name == null ? '' : left.name;
            String rightName = right == null || right.name == null ? '' : right.name;
            return leftName.toLowerCase().compareTo(rightName.toLowerCase());
        }
    }
}