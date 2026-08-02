Employee_Time_Card__c tc = [
    SELECT Id
    FROM Employee_Time_Card__c
    WHERE Employee__r.Username = 'git.mr@pharma.demo'
    AND Time_Card_Month_Start_Date__c = 2026-01-01
    LIMIT 1
];
EmployeeTimeCardMetricsService.reconcileTimeCard(tc.Id);
tc = [
    SELECT Submitted_Calls__c, Days_With_Activities__c, Actual_Visit_Rate__c
    FROM Employee_Time_Card__c
    WHERE Id = :tc.Id
];
System.debug(
    'Jan git_mr: calls=' +
        tc.Submitted_Calls__c +
        ' days=' +
        tc.Days_With_Activities__c +
        ' rate=' +
        tc.Actual_Visit_Rate__c
);
