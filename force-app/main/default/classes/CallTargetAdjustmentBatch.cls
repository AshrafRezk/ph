/**
 * Reapplies the current call-target rule to this month's time cards.
 */
public without sharing class CallTargetAdjustmentBatch implements Database.Batchable<SObject> {
    public Database.QueryLocator start(Database.BatchableContext context) {
        Date monthStart = Date.today().toStartOfMonth();
        return Database.getQueryLocator(
            [
                SELECT Id
                FROM Employee_Time_Card__c
                WHERE Time_Card_Month_Start_Date__c = :monthStart
            ]
        );
    }

    public void execute(Database.BatchableContext context, List<Employee_Time_Card__c> scope) {
        Set<Id> timeCardIds = new Map<Id, Employee_Time_Card__c>(scope).keySet();
        EmployeeTimeCardService.reapplyCallTargets(timeCardIds);
        EmployeeTimeCardMetricsService.recalcTimeCardRollups(timeCardIds);
    }

    public void finish(Database.BatchableContext context) {
    }
}
