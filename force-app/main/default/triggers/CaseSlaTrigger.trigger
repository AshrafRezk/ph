trigger CaseSlaTrigger on Case (before insert, before update) {
    if (Trigger.isBefore && Trigger.isInsert) {
        CaseSlaService.handleBeforeInsert(Trigger.new);
    }
    if (Trigger.isBefore && Trigger.isUpdate) {
        CaseSlaService.handleBeforeUpdate(Trigger.new, Trigger.oldMap);
    }
}