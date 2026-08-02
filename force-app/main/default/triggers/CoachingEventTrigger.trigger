trigger CoachingEventTrigger on Coaching_Event__c (after insert, after update) {
    CoachingEventUpdateNotifier.handleChanges(Trigger.new, Trigger.oldMap);
    CoachingEventSectionScoreSync.handleChanges(Trigger.new, Trigger.oldMap);
}
