// Sync check-in/check-out for Amr Salah June 2026 time card
Id repId = '005Hu00000V6HOyIAN';
Date monthStart = Date.newInstance(2026, 6, 1);

List<Employee_Time_Card__c> cards = [
    SELECT Id
    FROM Employee_Time_Card__c
    WHERE Employee__c = :repId
      AND Time_Card_Month_Start_Date__c = :monthStart
      AND Active_Time_Card__c = TRUE
    LIMIT 1
];

if (cards.isEmpty()) {
    cards.add(EmployeeTimeCardService.ensureMonthlyTimeCard(repId, monthStart));
}

Id timeCardId = cards[0].Id;
EmployeeTimeCardMetricsService.reconcileTimeCard(timeCardId);
EmployeeTimeCardMetricsService.syncAttendanceTimesForTimeCard(timeCardId);
System.debug('Synced attendance for time card ' + timeCardId);
