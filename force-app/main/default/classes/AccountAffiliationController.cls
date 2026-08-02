public with sharing class AccountAffiliationController {

    private static final Integer DEFAULT_PAGE_SIZE = 25;
    private static final Integer MAX_PAGE_SIZE = 100;

    public class GraphNode {
        @AuraEnabled public String id;
        @AuraEnabled public String label;
        @AuraEnabled public String accountType;
        @AuraEnabled public Boolean isActive;
        @AuraEnabled public Boolean hasMoreAffiliations;
    }

    public class GraphEdge {
        @AuraEnabled public String fromId;
        @AuraEnabled public String toId;
        @AuraEnabled public String relationType;
        @AuraEnabled public String description;
        @AuraEnabled public String affiliationId;
    }

    public class GraphData {
        @AuraEnabled public List<GraphNode> nodes;
        @AuraEnabled public List<GraphEdge> edges;
        @AuraEnabled public Integer totalCount;
        @AuraEnabled public Integer offset;
        @AuraEnabled public Integer pageSize;
        @AuraEnabled public Boolean hasMore;
        @AuraEnabled public Integer recordsReturned;
    }

    public class AccountDetails {
        @AuraEnabled public String id;
        @AuraEnabled public String name;
        @AuraEnabled public String accountType;
    }

    public class PicklistValue {
        @AuraEnabled public String label;
        @AuraEnabled public String value;
    }

    private class FilterCriteria {
        public String relationType;
        public Boolean showInactive;
        public Boolean showOutsideTerritory;
        public String direction;
        public String role;
        public String strength;
        public List<String> accountIds;
    }

    @AuraEnabled
    public static GraphData getAccountAffiliations(
        Id accountId,
        String filtersJson,
        Integer offset,
        Integer pageSize
    ) {
        if (accountId == null) {
            throw new AuraHandledException('Account Id is required.');
        }

        Integer resolvedOffset = offset == null || offset < 0 ? 0 : offset;
        Integer resolvedPageSize = pageSize == null || pageSize < 1
            ? DEFAULT_PAGE_SIZE
            : Math.min(pageSize, MAX_PAGE_SIZE);

        FilterCriteria filters = parseFilters(filtersJson, accountId);
        Set<Id> seedAccountIds = resolveSeedAccountIds(filters);

        if (seedAccountIds.isEmpty()) {
            return emptyGraph(resolvedOffset, resolvedPageSize);
        }

        Integer totalCount = countAffiliations(seedAccountIds, filters);
        List<Account_Affiliation__c> affiliations = queryAffiliations(
            seedAccountIds,
            filters,
            resolvedOffset,
            resolvedPageSize
        );

        GraphData graph = buildGraph(affiliations, filters, seedAccountIds);
        graph.totalCount = totalCount;
        graph.offset = resolvedOffset;
        graph.pageSize = resolvedPageSize;
        graph.recordsReturned = affiliations.size();
        graph.hasMore = (resolvedOffset + affiliations.size()) < totalCount;
        markNodesWithMoreAffiliations(graph, seedAccountIds, filters);
        return graph;
    }

    @AuraEnabled(cacheable=true)
    public static AccountDetails getAccountDetails(Id accountId) {
        if (accountId == null) {
            throw new AuraHandledException('Account Id is required.');
        }

        List<Account> accounts = [
            SELECT Id, Name, RecordType.Name
            FROM Account
            WHERE Id = :accountId
            WITH USER_MODE
            LIMIT 1
        ];

        if (accounts.isEmpty()) {
            throw new AuraHandledException('Account not found.');
        }

        Account acct = accounts[0];
        AccountDetails details = new AccountDetails();
        details.id = acct.Id;
        details.name = acct.Name;
        details.accountType = acct.RecordType.Name;
        return details;
    }

    @AuraEnabled(cacheable=true)
    public static List<PicklistValue> getRelationTypePicklistValues() {
        return describePicklist(Account_Affiliation__c.Affiliation_Type__c);
    }

    @AuraEnabled(cacheable=true)
    public static List<PicklistValue> getRolePicklistValues() {
        return describePicklist(Account_Affiliation__c.Role__c);
    }

    @AuraEnabled(cacheable=true)
    public static List<PicklistValue> getStrengthPicklistValues() {
        return describePicklist(Account_Affiliation__c.Strength__c);
    }

    private static FilterCriteria parseFilters(String filtersJson, Id accountId) {
        FilterCriteria filters = new FilterCriteria();
        filters.relationType = 'All';
        filters.showInactive = false;
        filters.showOutsideTerritory = true;
        filters.direction = 'All';
        filters.role = 'All';
        filters.strength = 'All';
        filters.accountIds = new List<String>{ String.valueOf(accountId) };

        if (String.isBlank(filtersJson)) {
            return filters;
        }

        Map<String, Object> parsed = (Map<String, Object>) JSON.deserializeUntyped(filtersJson);
        if (parsed.containsKey('relationType') && parsed.get('relationType') != null) {
            filters.relationType = String.valueOf(parsed.get('relationType'));
        }
        if (parsed.containsKey('showInactive') && parsed.get('showInactive') != null) {
            filters.showInactive = Boolean.valueOf(parsed.get('showInactive'));
        }
        if (parsed.containsKey('showOutsideTerritory') && parsed.get('showOutsideTerritory') != null) {
            filters.showOutsideTerritory = Boolean.valueOf(parsed.get('showOutsideTerritory'));
        }
        if (parsed.containsKey('direction') && parsed.get('direction') != null) {
            filters.direction = String.valueOf(parsed.get('direction'));
        }
        if (parsed.containsKey('role') && parsed.get('role') != null) {
            filters.role = String.valueOf(parsed.get('role'));
        }
        if (parsed.containsKey('strength') && parsed.get('strength') != null) {
            filters.strength = String.valueOf(parsed.get('strength'));
        }
        if (parsed.containsKey('accountIds') && parsed.get('accountIds') != null) {
            List<Object> rawIds = (List<Object>) parsed.get('accountIds');
            filters.accountIds = new List<String>();
            for (Object rawId : rawIds) {
                if (rawId != null) {
                    filters.accountIds.add(String.valueOf(rawId));
                }
            }
        }

        if (filters.accountIds.isEmpty()) {
            filters.accountIds = new List<String>{ String.valueOf(accountId) };
        }

        return filters;
    }

    private static Set<Id> resolveSeedAccountIds(FilterCriteria filters) {
        Set<Id> seedIds = new Set<Id>();
        for (String accountIdValue : filters.accountIds) {
            if (String.isNotBlank(accountIdValue)) {
                seedIds.add((Id) accountIdValue);
            }
        }
        return seedIds;
    }

    private static Integer countAffiliations(Set<Id> seedAccountIds, FilterCriteria filters) {
        String soql = 'SELECT COUNT() FROM Account_Affiliation__c' +
            ' WHERE (Primary_Account__c IN :seedAccountIds OR Related_Account__c IN :seedAccountIds)';
        soql += buildFilterClause(filters);

        String relationTypeFilter = filters.relationType;
        String roleFilter = filters.role;
        String strengthFilter = filters.strength;

        return Database.countQuery(soql);
    }

    private static List<Account_Affiliation__c> queryAffiliations(
        Set<Id> seedAccountIds,
        FilterCriteria filters,
        Integer offset,
        Integer pageSize
    ) {
        String soql = 'SELECT Id, Primary_Account__c, Related_Account__c, Affiliation_Type__c,' +
            ' Description__c, Is_Active__c, Outside_Territory__c, Role__c, Strength__c,' +
            ' Primary_Account__r.Name, Primary_Account__r.RecordType.Name,' +
            ' Related_Account__r.Name, Related_Account__r.RecordType.Name' +
            ' FROM Account_Affiliation__c' +
            ' WHERE (Primary_Account__c IN :seedAccountIds OR Related_Account__c IN :seedAccountIds)';
        soql += buildFilterClause(filters);
        soql += ' WITH USER_MODE ORDER BY Primary_Account__r.Name, Id LIMIT :pageSize OFFSET :offset';

        String relationTypeFilter = filters.relationType;
        String roleFilter = filters.role;
        String strengthFilter = filters.strength;

        return Database.query(soql);
    }

    private static String buildFilterClause(FilterCriteria filters) {
        String clause = '';
        if (!filters.showInactive) {
            clause += ' AND Is_Active__c = true';
        }
        if (!filters.showOutsideTerritory) {
            clause += ' AND Outside_Territory__c = false';
        }
        if (filters.relationType != 'All') {
            clause += ' AND Affiliation_Type__c = :relationTypeFilter';
        }
        if (filters.role != 'All') {
            clause += ' AND Role__c = :roleFilter';
        }
        if (filters.strength != 'All') {
            clause += ' AND Strength__c = :strengthFilter';
        }
        return clause;
    }

    private static GraphData buildGraph(
        List<Account_Affiliation__c> affiliations,
        FilterCriteria filters,
        Set<Id> seedAccountIds
    ) {
        GraphData graph = new GraphData();
        graph.nodes = new List<GraphNode>();
        graph.edges = new List<GraphEdge>();

        Map<Id, GraphNode> nodeMap = new Map<Id, GraphNode>();
        Set<String> edgeKeys = new Set<String>();

        addSeedNodes(nodeMap, seedAccountIds);

        for (Account_Affiliation__c affiliation : affiliations) {
            Id fromId;
            Id toId;

            if (filters.direction == 'Related→Primary') {
                fromId = affiliation.Related_Account__c;
                toId = affiliation.Primary_Account__c;
            } else {
                fromId = affiliation.Primary_Account__c;
                toId = affiliation.Related_Account__c;
            }

            addNode(nodeMap, affiliation.Primary_Account__c,
                affiliation.Primary_Account__r.Name, affiliation.Primary_Account__r.RecordType.Name,
                affiliation.Is_Active__c);
            addNode(nodeMap, affiliation.Related_Account__c,
                affiliation.Related_Account__r.Name, affiliation.Related_Account__r.RecordType.Name,
                affiliation.Is_Active__c);

            String edgeKey = String.valueOf(fromId) + '-' + String.valueOf(toId) + '-' + affiliation.Id;
            if (!edgeKeys.contains(edgeKey)) {
                GraphEdge edge = new GraphEdge();
                edge.fromId = String.valueOf(fromId);
                edge.toId = String.valueOf(toId);
                edge.relationType = affiliation.Affiliation_Type__c;
                edge.description = affiliation.Description__c;
                edge.affiliationId = affiliation.Id;
                graph.edges.add(edge);
                edgeKeys.add(edgeKey);
            }
        }

        graph.nodes.addAll(nodeMap.values());
        return graph;
    }

    private static void addSeedNodes(Map<Id, GraphNode> nodeMap, Set<Id> seedAccountIds) {
        if (seedAccountIds.isEmpty()) {
            return;
        }
        for (Account acct : [
            SELECT Id, Name, RecordType.Name
            FROM Account
            WHERE Id IN :seedAccountIds
            WITH USER_MODE
        ]) {
            addNode(nodeMap, acct.Id, acct.Name, acct.RecordType.Name, true);
        }
    }

    private static void markNodesWithMoreAffiliations(
        GraphData graph,
        Set<Id> seedAccountIds,
        FilterCriteria filters
    ) {
        if (graph.nodes == null || seedAccountIds.size() != 1) {
            return;
        }
        Boolean hasMore = graph.hasMore == true;
        for (GraphNode node : graph.nodes) {
            if (seedAccountIds.contains((Id) node.id)) {
                node.hasMoreAffiliations = hasMore;
            }
        }
    }

    private static void addNode(
        Map<Id, GraphNode> nodeMap,
        Id accountId,
        String name,
        String accountType,
        Boolean affiliationActive
    ) {
        if (accountId == null || nodeMap.containsKey(accountId)) {
            if (accountId != null && nodeMap.containsKey(accountId) && affiliationActive == false) {
                GraphNode existing = nodeMap.get(accountId);
                if (existing.isActive == true) {
                    existing.isActive = false;
                }
            }
            return;
        }

        GraphNode node = new GraphNode();
        node.id = String.valueOf(accountId);
        node.label = name;
        node.accountType = accountType;
        node.isActive = affiliationActive != false;
        node.hasMoreAffiliations = false;
        nodeMap.put(accountId, node);
    }

    private static List<PicklistValue> describePicklist(Schema.SObjectField fieldToken) {
        List<PicklistValue> values = new List<PicklistValue>();
        Schema.DescribeFieldResult fieldDescribe = fieldToken.getDescribe();
        for (Schema.PicklistEntry entry : fieldDescribe.getPicklistValues()) {
            if (entry.isActive()) {
                PicklistValue value = new PicklistValue();
                value.label = entry.getLabel();
                value.value = entry.getValue();
                values.add(value);
            }
        }
        return values;
    }

    private static GraphData emptyGraph(Integer offset, Integer pageSize) {
        GraphData graph = new GraphData();
        graph.nodes = new List<GraphNode>();
        graph.edges = new List<GraphEdge>();
        graph.totalCount = 0;
        graph.offset = offset;
        graph.pageSize = pageSize;
        graph.hasMore = false;
        graph.recordsReturned = 0;
        return graph;
    }
}
