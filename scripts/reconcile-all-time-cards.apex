for (Employee_Time_Card__c timeCard : [
    SELECT Id
    FROM Employee_Time_Card__c
    WHERE Time_Card_Month_Start_Date__c >= 2026-01-01
    AND Time_Card_Month_Start_Date__c <= 2026-06-30
]) {
    EmployeeTimeCardMetricsService.reconcileTimeCard(timeCard.Id);
}
System.debug('Reconciled Jan–Jun 2026 time cards.');
