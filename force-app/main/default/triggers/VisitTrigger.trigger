trigger VisitTrigger on Visit__c (before insert, before update, after insert, after update) {
    if (Trigger.isBefore) {
        // First-coverage-cycle duplicate restriction (BRD 5.4.1.3): on insert, and on update
        // when a visit is moved to another day, HCP or rep.
        VisitDuplicateService.enforceFirstCycleRule(Trigger.new, Trigger.isUpdate ? Trigger.oldMap : null);
        // Completed unplanned visits go to the DM validation queue (due in 24 hours).
        VisitStatusHelper.applyUnplannedCompletionValidation(Trigger.new, Trigger.isUpdate ? Trigger.oldMap : null);
    } else {
        UnplannedVisitReviewNotifier.onVisits(Trigger.new, Trigger.isUpdate ? Trigger.oldMap : null);
    }
}
