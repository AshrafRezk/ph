Date febStart = Date.newInstance(2026, 2, 1);
List<String> reps = new List<String>{
    'git_mr', 'diabetes_mr', 'cluster_mr', 'chc_mr', 'cardio_mr', 'gastro_mr'
};
for (String mrKey : reps) {
    Id userId = [SELECT Id FROM User WHERE Username = :mrKey.replace('_', '.') + '@pharma.demo' LIMIT 1].Id;
    Employee_Time_Card__c card = [
        SELECT Id
        FROM Employee_Time_Card__c
        WHERE Employee__c = :userId AND Time_Card_Month_Start_Date__c = :febStart
        LIMIT 1
    ];
    EmployeeTimeCardService.syncAccountTargets(card.Id);
    EmployeeTimeCardMetricsService.reconcileTimeCard(card.Id);
}
System.debug('Synced and reconciled Feb 2026 account targets for all demo MRs.');
