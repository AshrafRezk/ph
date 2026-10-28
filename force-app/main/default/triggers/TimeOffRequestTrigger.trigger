trigger TimeOffRequestTrigger on Time_Off_Request__c (after insert, after update) {
    // When a leave request becomes Approved, recompute the rep's single pro-rated target:
    // base x (working days - counted leave days) / working days (see CallTargetAdjustmentService).
    // The card target is updated here; per-account targets are recalculated right after.
    List<Time_Off_Request__c> newlyApproved = new List<Time_Off_Request__c>();
    for (Time_Off_Request__c t : Trigger.new) {
        Boolean isApproved = t.Stage__c == 'Approved';
        Boolean wasApproved = Trigger.isUpdate
            && Trigger.oldMap.get(t.Id).Stage__c == 'Approved';
        if (isApproved && !wasApproved) {
            newlyApproved.add(t);
        }
    }
    if (!newlyApproved.isEmpty()) {
        LeaveImpactService.recalcForTimeOff(newlyApproved);
    }
}