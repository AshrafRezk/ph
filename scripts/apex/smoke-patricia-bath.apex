Id acctId = [SELECT Id FROM Account WHERE Name = 'Ain Shams University Hospitals' LIMIT 1].Id;
AccountAffiliationController.GraphData graph = AccountAffiliationController.getAccountAffiliations(
    acctId,
    JSON.serialize(new Map<String, Object>{
        'relationType' => 'All',
        'showInactive' => false,
        'showOutsideTerritory' => true,
        'direction' => 'All',
        'role' => 'All',
        'strength' => 'All',
        'accountIds' => new List<String>{ String.valueOf(acctId) }
    }),
    0,
    25
);
System.debug(LoggingLevel.ERROR, 'NODES=' + graph.nodes.size() + ' EDGES=' + graph.edges.size() + ' TOTAL=' + graph.totalCount);
