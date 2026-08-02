trigger VisitTimeCardTrigger on Visit__c (after insert, after update) {
    EmployeeTimeCardMetricsService.processVisitChanges(Trigger.new, Trigger.oldMap);
}
