Id hcpId = [SELECT Id FROM Account WHERE External_ID__c = 'DEMO_HCP_0000' LIMIT 1].Id;
AccountAffiliationController.GraphData graph = AccountAffiliationController.getAccountAffiliations(
    hcpId,
    JSON.serialize(new Map<String, Object>{
        'relationType' => 'All',
        'showInactive' => true,
        'showOutsideTerritory' => true,
        'direction' => 'All',
        'role' => 'All',
        'strength' => 'All',
        'accountIds' => new List<String>{ String.valueOf(hcpId) }
    })
);
System.debug(LoggingLevel.ERROR, 'SMOKE_NODES=' + graph.nodes.size());
System.debug(LoggingLevel.ERROR, 'SMOKE_EDGES=' + graph.edges.size());

AccountAffiliationController.AccountDetails details = AccountAffiliationController.getAccountDetails(hcpId);
System.debug(LoggingLevel.ERROR, 'SMOKE_ACCOUNT=' + details.name);
