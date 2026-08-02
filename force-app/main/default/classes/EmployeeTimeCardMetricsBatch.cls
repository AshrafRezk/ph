public without sharing class EmployeeTimeCardMetricsBatch implements Database.Batchable<Id>, Schedulable {

    public void execute(SchedulableContext context) {
        Database.executeBatch(this, 20);
    }

    public Iterable<Id> start(Database.BatchableContext context) {
        Date demoRangeStart = Date.newInstance(2026, 1, 1);
        Date demoRangeEnd = Date.newInstance(2026, 6, 30);
        Date currentMonthStart = Date.newInstance(Date.today().year(), Date.today().month(), 1);
        List<Id> timeCardIds = new List<Id>();
        for (Employee_Time_Card__c timeCard : [
            SELECT Id
            FROM Employee_Time_Card__c
            WHERE
                Active_Time_Card__c = TRUE
                OR Time_Card_Month_Start_Date__c = :currentMonthStart
                OR (
                    Time_Card_Month_Start_Date__c >= :demoRangeStart
                    AND Time_Card_Month_Start_Date__c <= :demoRangeEnd
                )
            WITH SYSTEM_MODE
        ]) {
            timeCardIds.add(timeCard.Id);
        }
        return timeCardIds;
    }

    public void execute(Database.BatchableContext context, List<Id> scope) {
        for (Id timeCardId : scope) {
            EmployeeTimeCardMetricsService.reconcileTimeCard(timeCardId);
        }
    }

    public void finish(Database.BatchableContext context) {
    }
}
