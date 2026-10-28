trigger BrickTrigger on Brick__c(before insert, before update) {
    BrickTriggerHandler.deriveRegionFields(Trigger.new, Trigger.oldMap);
}
