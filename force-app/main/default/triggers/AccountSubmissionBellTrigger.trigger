trigger AccountSubmissionBellTrigger on Account (after insert, after update) {
    DistrictManagerNotifier.onAccounts(Trigger.new, Trigger.isUpdate ? Trigger.oldMap : null);
}