// sf apex run --file scripts/apex/reconcile-stale-mr-feb-targets.apex --target-org pharma-prod
// Sync-only: removes orphan account-target rows and refreshes the Target_Customers__c rollup.
// reconcileTimeCard is omitted here (exceeds 100 SOQL when combined); run per-rep if visit metrics need rebuild.
Date febStart = Date.newInstance(2026, 2, 1);
List<String> reps = new List<String>{ 'git_mr', 'diabetes_mr', 'cluster_mr', 'chc_mr' };
for (String mrKey : reps) {
    Id userId = [SELECT Id FROM User WHERE Username = :mrKey.replace('_', '.') + '@pharma.demo' LIMIT 1].Id;
    Employee_Time_Card__c card = [
        SELECT Id
        FROM Employee_Time_Card__c
        WHERE Employee__c = :userId AND Time_Card_Month_Start_Date__c = :febStart
        LIMIT 1
    ];
    EmployeeTimeCardService.syncAccountTargets(card.Id);
    System.debug('Synced ' + mrKey);
}
