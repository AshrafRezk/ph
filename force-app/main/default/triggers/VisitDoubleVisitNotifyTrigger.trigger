trigger VisitDoubleVisitNotifyTrigger on Visit__c (after insert, after update) {
    DoubleVisitNotifier.onVisits(Trigger.new, Trigger.isUpdate ? Trigger.oldMap : null);
}