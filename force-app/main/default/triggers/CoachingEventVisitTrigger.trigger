trigger CoachingEventVisitTrigger on Coaching_Event_Visit__c (before insert, before update) {
    for (Coaching_Event_Visit__c row : Trigger.new) {
        if (row.Coaching_Event__c != null && row.Visit__c != null) {
            row.Unique_Key__c = String.valueOf(row.Coaching_Event__c) + '_' + String.valueOf(row.Visit__c);
        }
    }
}