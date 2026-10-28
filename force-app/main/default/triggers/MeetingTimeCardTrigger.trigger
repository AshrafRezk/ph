trigger MeetingTimeCardTrigger on Meeting__c (after insert, after update, after delete) {
    if (Trigger.isDelete) {
        EmployeeTimeCardMetricsService.processMeetingDeletes(Trigger.old);
    } else {
        EmployeeTimeCardMetricsService.processMeetingChanges(Trigger.new, Trigger.oldMap);
    }
}
