trigger Product2Trigger on Product2 (before insert, before update) {
    if (Trigger.isBefore) {
        if (Trigger.isInsert) {
            Product2TriggerHandler.beforeInsert(Trigger.new);
        } else if (Trigger.isUpdate) {
            Product2TriggerHandler.beforeUpdate(Trigger.new, Trigger.oldMap);
        }
    }
}